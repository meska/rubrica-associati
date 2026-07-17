import 'dart:async';
import 'dart:io';

import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';
import 'package:rubrica_associati/services/backup_service.dart';
import 'package:rubrica_associati/services/spreadsheet_importer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final MemberRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _donationsUri = Uri.parse('https://github.com/sponsors/meska');

  final _searchController = TextEditingController();
  final _importer = SpreadsheetImporter();
  final _backupService = BackupService();
  Timer? _searchTimer;
  List<Member> _members = const [];
  var _organizationName = MemberRepository.defaultOrganizationName;
  var _loading = true;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrganizationName();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final query = _searchController.text;
    final members = await widget.repository.search(query);
    // Se nel frattempo xe cambiada la ricerca, sta risposta ormai xe vecia.
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _members = members;
      _loading = false;
    });
  }

  Future<void> _loadOrganizationName() async {
    final name = await widget.repository.loadOrganizationName();
    if (!mounted) return;
    setState(() => _organizationName = name);
  }

  void _search(String _) {
    _searchTimer?.cancel();
    // Un fià de pausa evita una query par ogni singola lettera digitada.
    _searchTimer = Timer(const Duration(milliseconds: 220), _load);
  }

  Future<void> _addMember() async {
    final member = await Navigator.of(
      context,
    ).push<Member>(MaterialPageRoute(builder: (_) => const MemberFormScreen()));
    if (member == null) return;
    await widget.repository.save(member);
    await _load();
  }

  Future<void> _openMember(Member member) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            MemberDetailScreen(member: member, repository: widget.repository),
      ),
    );
    // Rilegge sempre: dalla scheda si può modificare oppure eliminare.
    await _load();
  }

  Future<void> _import() async {
    final strings = AppLocalizations.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['rubrica', 'json', 'xlsx', 'csv'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    if (file.size > BackupService.maxFileBytes) {
      _showMessage(strings.fileTooLarge);
      return;
    }

    try {
      final bytes = await file.xFile.readAsBytes();
      final lowerName = file.name.toLowerCase();
      final isBackup =
          lowerName.endsWith('.rubrica') || lowerName.endsWith('.json');
      late final List<Member> imported;
      var warningCount = 0;
      if (isBackup) {
        imported = _backupService.decode(bytes);
      } else {
        final parsed = _importer.parse(file.name, bytes);
        imported = parsed.members;
        warningCount = parsed.warnings.length;
      }
      final saved = await widget.repository.importMembers(imported);
      await _load();
      if (!mounted) return;
      final warningText = warningCount == 0
          ? ''
          : '\n\n${strings.importWarnings(warningCount)}';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline),
          title: Text(strings.importCompleted),
          content: Text(
            '${strings.importedNewMembers(saved.inserted)}\n'
            '${strings.importedUpdatedMembers(saved.updated)}$warningText',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.close),
            ),
          ],
        ),
      );
    } on SpreadsheetImportException catch (error) {
      _showMessage(_spreadsheetErrorMessage(strings, error));
    } on BackupException catch (error) {
      _showMessage(_backupErrorMessage(strings, error));
    } on Object catch (_) {
      _showMessage(strings.importFailed);
    }
  }

  Future<void> _shareBackup() async {
    final strings = AppLocalizations.of(context);
    try {
      final members = await widget.repository.search('');
      if (members.isEmpty) {
        _showMessage(strings.emptyDirectoryShare);
        return;
      }

      final now = DateTime.now();
      final date = DateFormat('yyyy-MM-dd').format(now);
      final fileName = 'rubrica-associati-$date.rubrica';
      final directory = await getTemporaryDirectory();
      final backupFile = File(path.join(directory.path, fileName));
      await backupFile.writeAsBytes(
        _backupService.encode(members, exportedAt: now),
        flush: true,
      );
      if (!mounted) return;

      // Su iPad il pannello di condivisione ga bisogno de un punto d'ancoraggio.
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backupFile.path, mimeType: 'application/json')],
          fileNameOverrides: [fileName],
          title: strings.shareTitle,
          subject: strings.shareSubject(date),
          sharePositionOrigin: origin,
        ),
      );
    } on BackupException catch (error) {
      _showMessage(_backupErrorMessage(strings, error));
    } on Object catch (_) {
      _showMessage(strings.shareFailed);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDonations() async {
    final strings = AppLocalizations.of(context);
    // La donazion la resta fora dall'app e no la sblocca gnente: xe proprio volontaria.
    final opened = await launchUrl(
      _donationsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      _showMessage(strings.donationsFailed);
    }
  }

  Future<void> _editOrganizationName() async {
    final strings = AppLocalizations.of(context);
    final currentName = _displayOrganizationName(strings);
    var editedName = currentName;
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.organizationName),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: currentName,
            autofocus: true,
            maxLength: MemberRepository.maxOrganizationNameLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: strings.displayedName),
            onChanged: (value) => editedName = value,
            validator: (value) => value == null || value.trim().isEmpty
                ? strings.enterOrganizationName
                : null,
            onFieldSubmitted: (value) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, editedName.trim());
              }
            },
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (name == null || name == currentName) return;

    try {
      await widget.repository.saveOrganizationName(name);
      if (!mounted) return;
      setState(() => _organizationName = name);
    } on Object catch (_) {
      _showMessage(strings.organizationSaveFailed);
    }
  }

  Future<void> _showImportHelp() async {
    final strings = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.fileHelpTitle),
        content: SingleChildScrollView(child: Text(strings.fileHelpContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.understood),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/branding/rubrica-associati-logo.png',
              semanticLabel: strings.logoSemanticLabel,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.appTitle),
            Text(
              _displayOrganizationName(strings),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'share') unawaited(_shareBackup());
              if (value == 'import') unawaited(_import());
              if (value == 'organization') unawaited(_editOrganizationName());
              if (value == 'help') unawaited(_showImportHelp());
              if (value == 'donate') unawaited(_openDonations());
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: const Icon(Icons.ios_share_outlined),
                  title: Text(strings.shareDirectory),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(strings.importDirectoryExcel),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'organization',
                child: ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(strings.organizationName),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'help',
                child: ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(strings.fileFormat),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'donate',
                child: ListTile(
                  leading: const Icon(Icons.volunteer_activism_outlined),
                  title: Text(strings.supportProject),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SearchBar(
                controller: _searchController,
                onChanged: _search,
                hintText: strings.searchHint,
                leading: const Icon(Icons.search),
                trailing: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      tooltip: strings.clearSearch,
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        _load();
                      },
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMember,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(strings.add),
      ),
    );
  }

  Widget _buildContent() {
    final strings = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _searchController.text.isEmpty
                    ? Icons.people_outline
                    : Icons.person_search_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                _searchController.text.isEmpty
                    ? strings.emptyDirectory
                    : strings.noMemberFound,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _searchController.text.isEmpty
                    ? strings.emptyDirectoryHelp
                    : strings.noMemberFoundHelp,
                textAlign: TextAlign.center,
              ),
              if (_searchController.text.isEmpty) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(strings.importDirectoryExcel),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _members.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Text(
                strings.membersCount(_members.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            );
          }
          final member = _members[index - 1];
          return Card(
            child: ListTile(
              onTap: () => _openMember(member),
              leading: CircleAvatar(child: Text(member.initials)),
              title: Text(member.fullName),
              subtitle: Text(_memberSubtitle(member, strings)),
              isThreeLine: member.isExpired,
              trailing: member.isExpired
                  ? Icon(
                      Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error,
                    )
                  : const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }

  String _memberSubtitle(Member member, AppLocalizations strings) {
    final parts = <String>[];
    if (member.phone.isNotEmpty) parts.add(member.phone);
    if (member.secondaryPhone.isNotEmpty) parts.add(member.secondaryPhone);
    if (member.memberNumber.isNotEmpty) {
      parts.add(strings.memberCard(member.memberNumber));
    }
    if (member.isExpired && member.expiryDate != null) {
      parts.add(
        strings.expiredOn(_formatDate(member.expiryDate!, strings.localeName)),
      );
    }
    return parts.isEmpty ? strings.openMember : parts.join(' · ');
  }

  String _displayOrganizationName(AppLocalizations strings) =>
      _organizationName == MemberRepository.defaultOrganizationName
      ? strings.defaultOrganizationName
      : _organizationName;

  String _formatDate(DateTime value, String localeName) =>
      DateFormat.yMd(localeName).format(value);

  String _spreadsheetErrorMessage(
    AppLocalizations strings,
    SpreadsheetImportException exception,
  ) => switch (exception.error) {
    SpreadsheetImportError.fileTooLarge => strings.fileTooLarge,
    SpreadsheetImportError.unsupportedFormat =>
      strings.spreadsheetUnsupportedFormat,
    SpreadsheetImportError.tooManyRows => strings.spreadsheetTooManyRows,
    SpreadsheetImportError.emptyFile => strings.spreadsheetEmpty,
    SpreadsheetImportError.missingNameColumn =>
      strings.spreadsheetMissingNameColumn,
    SpreadsheetImportError.noValidRows => strings.spreadsheetNoValidRows,
    SpreadsheetImportError.unreadableExcel =>
      strings.spreadsheetUnreadableExcel,
    SpreadsheetImportError.unreadableCsv => strings.spreadsheetUnreadableCsv,
  };

  String _backupErrorMessage(
    AppLocalizations strings,
    BackupException exception,
  ) => switch (exception.error) {
    BackupError.tooManyMembers => strings.backupTooManyMembers,
    BackupError.tooLarge => strings.backupTooLarge,
    BackupError.invalidContent => strings.backupInvalidContent,
    BackupError.wrongFormat => strings.backupWrongFormat,
    BackupError.unsupportedVersion => strings.backupUnsupportedVersion,
    BackupError.invalidMembers => strings.backupInvalidMembers,
    BackupError.invalidMember => strings.backupInvalidMember(
      exception.row ?? 0,
    ),
    BackupError.unreadable => strings.backupUnreadable,
    BackupError.missingMemberName => strings.backupMissingMemberName(
      exception.row ?? 0,
    ),
    BackupError.invalidField => strings.backupInvalidField(
      _localizedBackupField(strings, exception.field),
      exception.row ?? 0,
    ),
  };

  String _localizedBackupField(AppLocalizations strings, String? field) =>
      switch (field) {
        'firstName' => strings.firstName,
        'lastName' => strings.lastName,
        'phone' => strings.phone,
        'secondaryPhone' => strings.secondaryPhone,
        'memberNumber' => strings.memberNumber,
        'expiryDate' => strings.membershipExpiry,
        'birthDate' => strings.dateOfBirth,
        'notes' => strings.notes,
        _ => field ?? '',
      };
}
