import 'dart:async';
import 'dart:io';

import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/models/member_filter.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';
import 'package:rubrica_associati/screens/register_book_screen.dart';
import 'package:rubrica_associati/screens/roster_screen.dart';
import 'package:rubrica_associati/screens/volunteer_screen.dart';
import 'package:rubrica_associati/services/backup_service.dart';
import 'package:rubrica_associati/services/closure_service.dart';
import 'package:rubrica_associati/services/review_service.dart';
import 'package:rubrica_associati/services/spreadsheet_importer.dart';
import 'package:rubrica_associati/services/tip_jar_service.dart';
import 'package:rubrica_associati/support/app_support.dart';
import 'package:rubrica_associati/widgets/content_width.dart';
import 'package:rubrica_associati/widgets/support_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    this.tipJarController,
    this.reviewService,
    this.supportLauncher = AppSupport.openExternal,
  });

  final MemberRepository repository;
  final ReviewService? reviewService;
  final TipJarController? tipJarController;
  final ExternalSupportLauncher supportLauncher;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _importer = SpreadsheetImporter();
  final _backupService = BackupService();
  Timer? _searchTimer;
  List<Member> _members = const [];
  var _organizationName = MemberRepository.defaultOrganizationName;
  var _loading = true;
  var _loadFailed = false;
  var _loadGeneration = 0;
  var _reviewEnabled = true;
  var _filter = MemberFilter.all;
  Set<int> _notInBook = const {};
  Member? _selected;

  /// Da questa larghezza (iPad in orizzontale e verticale grande, Mac,
  /// Windows) lista e scheda stanno affiancate.
  static const _wideBreakpoint = 840.0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrganizationName();
    unawaited(_initReview());
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
    try {
      final members = await widget.repository.search(query);
      Set<int> notInBook = const {};
      try {
        notInBook = await widget.repository.membersNotInBook();
      } catch (_) {
        // Il filtro del libro è un extra: la rubrica si carica comunque.
      }
      // Se nel frattempo xe cambiada la ricerca, sta risposta ormai xe vecia.
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _members = members;
        _notInBook = notInBook;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      // Niente spinner eterno: se el database no parte, femose capir e riprovemo.
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _initReview() async {
    final service = widget.reviewService;
    if (service == null) return;
    try {
      await service.registerLaunch();
      final state = await service.loadState();
      if (!mounted) return;
      setState(() => _reviewEnabled = state.enabled);
    } catch (_) {
      // La richiesta di recensione non deve mai disturbare l'uso dell'app.
    }
  }

  Future<void> _toggleReview() async {
    final service = widget.reviewService;
    if (service == null) return;
    final next = !_reviewEnabled;
    setState(() => _reviewEnabled = next);
    try {
      await service.setEnabled(next);
    } catch (_) {
      if (mounted) setState(() => _reviewEnabled = !next);
    }
  }

  Future<void> _rateApp() async {
    final service = widget.reviewService;
    if (service == null) return;
    await service.openStoreReview();
  }

  Widget _detailPane(AppLocalizations strings) {
    final member = _selected;
    if (member == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                strings.selectMember,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return MemberDetailScreen(
      key: ValueKey('detail-${member.id}'),
      member: member,
      repository: widget.repository,
      onChanged: _load,
      onDeleted: () {
        setState(() => _selected = null);
        _load();
      },
    );
  }

  List<Member> get _visibleMembers =>
      applyMemberFilter(_members, _filter, _notInBook);

  Future<void> _admitAllMissing() async {
    final strings = AppLocalizations.of(context);
    final missing = _members
        .where((m) => m.id != null && _notInBook.contains(m.id))
        .toList(growable: false);
    // Anche fuori dalla ricerca corrente: il libro riguarda tutti i soci.
    final all = await widget.repository.search('');
    final allMissing = all
        .where((m) => m.id != null && _notInBook.contains(m.id))
        .toList(growable: false);
    if (!mounted) return;
    if (allMissing.isEmpty && missing.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.bookNothingMissing)));
      return;
    }
    final withDate = allMissing.where((m) => m.joinDate != null).length;
    final withoutDate = allMissing.length - withDate;
    var fallback = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.bookAdmitTitle(allMissing.length)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (withDate > 0) Text(strings.bookAdmitWithDate(withDate)),
                if (withDate > 0 && withoutDate > 0) const SizedBox(height: 10),
                if (withoutDate > 0) ...[
                  Text(strings.bookAdmitWithoutDate(withoutDate)),
                  const SizedBox(height: 6),
                  Text(
                    strings.bookAdmitDate(
                      _formatDate(fallback, strings.localeName),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: fallback,
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => fallback = picked);
                        }
                      },
                      child: Text(strings.bookAdmitChangeDate),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  strings.bookAdmitNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.bookAdmitConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final written = await widget.repository.admitAllMissing(
        fallbackDate: RegisterRepository.todayIso(fallback),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.bookAdmitDone(written))));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.bookAdmitFailed)));
    }
  }

  Widget _filterBar(AppLocalizations strings) {
    int count(MemberFilter f) =>
        applyMemberFilter(_members, f, _notInBook).length;
    final labels = {
      MemberFilter.all: strings.filterAll,
      MemberFilter.inGoodStanding: strings.filterActive,
      MemberFilter.expired: strings.filterExpired,
      MemberFilter.noExpiry: strings.filterNoExpiry,
      MemberFilter.notInBook: strings.filterNotInBook,
    };
    // Tre filtri principali sempre visibili; gli altri stanno nel menu «...».
    // Se uno dei secondari è attivo compare come chip, così si vede sempre
    // cosa si sta guardando.
    const main = [
      MemberFilter.all,
      MemberFilter.inGoodStanding,
      MemberFilter.expired,
    ];
    const more = [MemberFilter.noExpiry, MemberFilter.notInBook];
    // Tre filtri principali in un controllo segmentato (una sola riga, testo
    // senza conteggio: l'intestazione «N associati» lo mostra già); gli altri
    // stanno nel menu «...». Se ne è attivo uno secondario compare come chip
    // rimovibile, così si vede sempre cosa si sta guardando.
    final hidden = more.contains(_filter);
    final moreButton = PopupMenuButton<MemberFilter>(
      tooltip: strings.filterMore,
      icon: const Icon(Icons.more_horiz),
      onSelected: (f) => setState(() => _filter = f),
      itemBuilder: (_) => [
        for (final f in more)
          CheckedPopupMenuItem(
            value: f,
            checked: _filter == f,
            child: Text('${labels[f]} (${count(f)})'),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: hidden
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text(
                        '${labels[_filter]} (${count(_filter)})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      deleteButtonTooltipMessage: strings.filterAll,
                      onDeleted: () =>
                          setState(() => _filter = MemberFilter.all),
                    ),
                  )
                : SegmentedButton<MemberFilter>(
                    showSelectedIcon: false,
                    // Padding ridotto: le etichette restano intere anche su 320 px.
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    segments: [
                      for (final f in main)
                        ButtonSegment(
                          value: f,
                          // Se non c'è spazio il testo si rimpicciolisce: meglio di
                          // un'etichetta tagliata con i puntini.
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(labels[f]!, maxLines: 1),
                          ),
                        ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) =>
                        setState(() => _filter = v.first),
                  ),
          ),
          moreButton,
        ],
      ),
    );
  }

  /// Suggerimenti in parole semplici: chi non ha la scadenza non compare in
  /// «In regola»/«Scaduti», e va detto come sistemare.
  Widget _filterHint(AppLocalizations strings) {
    final noExpiry = applyMemberFilter(
      _members,
      MemberFilter.noExpiry,
      _notInBook,
    ).length;
    if (noExpiry == 0) return const SizedBox.shrink();
    final String text;
    final bool offerShow;
    switch (_filter) {
      case MemberFilter.inGoodStanding:
      case MemberFilter.expired:
        text = strings.hintNoExpiryElsewhere(noExpiry);
        offerShow = true;
      case MemberFilter.noExpiry:
        text = strings.hintNoExpiryHere;
        offerShow = false;
      case MemberFilter.all:
      case MemberFilter.notInBook:
        return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            if (offerShow)
              TextButton(
                onPressed: () =>
                    setState(() => _filter = MemberFilter.noExpiry),
                child: Text(strings.hintShow),
              ),
          ],
        ),
      ),
    );
  }

  Widget _missingBookBanner(AppLocalizations strings) {
    final missing = applyMemberFilter(
      _members,
      MemberFilter.notInBook,
      _notInBook,
    ).length;
    if (_filter != MemberFilter.notInBook || _notInBook.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.bookMissingBanner(
                missing > 0 ? missing : _notInBook.length,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _admitAllMissing,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(strings.bookAdmitAll),
            ),
          ],
        ),
      ),
    );
  }

  /// Dopo un'azione riuscita (mai dopo un errore): la policy decide se chiedere.
  Future<void> _afterSuccess() async {
    final service = widget.reviewService;
    if (service == null) return;
    try {
      await service.recordSuccess();
      await service.maybeRequest();
    } catch (_) {
      // Nessun effetto sull'azione appena riuscita.
    }
  }

  Future<void> _loadOrganizationName() async {
    try {
      final name = await widget.repository.loadOrganizationName();
      if (!mounted) return;
      setState(() => _organizationName = name);
    } catch (_) {
      // L'errore principale vien mostrà dal caricamento della rubrica.
    }
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
    if (MediaQuery.sizeOf(context).width >= _wideBreakpoint) {
      setState(() => _selected = member);
      return;
    }
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
      unawaited(_afterSuccess());
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
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backupFile.path, mimeType: 'application/json')],
          fileNameOverrides: [fileName],
          title: strings.shareTitle,
          subject: strings.shareSubject(date),
          sharePositionOrigin: origin,
        ),
      );
      if (result.status == ShareResultStatus.success) {
        unawaited(_afterSuccess());
      }
    } on BackupException catch (error) {
      _showMessage(_backupErrorMessage(strings, error));
    } on Object catch (_) {
      _showMessage(strings.shareFailed);
    }
  }

  Future<void> _openRoster() async {
    final members = await widget.repository.search('');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RosterScreen(members: members)),
    );
  }

  Future<void> _openRegisterBook() async {
    final entries = await widget.repository.registerEntries();
    final profile = await widget.repository.loadEntityProfile();
    ClosureService? closureService;
    try {
      final closures = await widget.repository.closureRepository();
      final docs = await getApplicationDocumentsDirectory();
      closureService = ClosureService(
        repository: closures,
        directory: Directory(path.join(docs.path, 'chiusure')),
      );
    } catch (_) {
      closureService = null;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterBookScreen(
          entries: entries,
          profile: profile,
          closureService: closureService,
        ),
      ),
    );
  }

  Future<void> _openVolunteers() async {
    final profile = await widget.repository.loadEntityProfile();
    VolunteerRepository repo;
    try {
      repo = await widget.repository.volunteerRepository();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VolunteerScreen(repository: repo, profile: profile),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSupport() async {
    final strings = AppLocalizations.of(context);
    final tipJarController = widget.tipJarController;
    if (tipJarController != null) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SupportSheet(controller: tipJarController),
      );
      return;
    }
    // Su desktop Ko-fi resta fora dall'app e no sblocca proprio gnente.
    try {
      final opened = await widget.supportLauncher(AppSupport.koFiUri);
      if (!opened) _showMessage(strings.supportOpenFailed);
    } catch (_) {
      _showMessage(strings.supportOpenFailed);
    }
  }

  Future<void> _editEntityDetails() async {
    final strings = AppLocalizations.of(context);
    final current = await widget.repository.loadEntityProfile();
    if (!mounted) return;
    final profile = await showDialog<EntityProfile>(
      context: context,
      builder: (_) => _EntityDetailsDialog(initial: current),
    );
    if (profile == null || !mounted) return;
    try {
      await widget.repository.saveEntityProfile(profile);
    } catch (_) {
      _showMessage(strings.entityDetailsSaveFailed);
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
        centerTitle: false,
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
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'share') unawaited(_shareBackup());
              if (value == 'import') unawaited(_import());
              if (value == 'organization') unawaited(_editOrganizationName());
              if (value == 'entity') unawaited(_editEntityDetails());
              if (value == 'roster') unawaited(_openRoster());
              if (value == 'book') unawaited(_openRegisterBook());
              if (value == 'volunteers') unawaited(_openVolunteers());
              if (value == 'help') unawaited(_showImportHelp());
              if (value == 'support') unawaited(_openSupport());
              if (value == 'review') unawaited(_toggleReview());
              if (value == 'rate') unawaited(_rateApp());
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
                value: 'entity',
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(strings.entityDetails),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'roster',
                child: ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(strings.rosterTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'book',
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(strings.bookTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'volunteers',
                child: ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: Text(strings.volMenu),
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
              if (widget.reviewService != null)
                PopupMenuItem(
                  value: 'rate',
                  child: ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: Text(strings.rateApp),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (widget.reviewService != null)
                CheckedPopupMenuItem(
                  value: 'review',
                  checked: _reviewEnabled,
                  child: Text(strings.reviewRequestSetting),
                ),
              PopupMenuItem(
                value: 'support',
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final listColumn = Column(
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
                _filterBar(strings),
                _missingBookBanner(strings),
                _filterHint(strings),
                Expanded(child: _buildContent()),
              ],
            );
            if (constraints.maxWidth < _wideBreakpoint) {
              return ContentWidth(child: listColumn);
            }
            return Row(
              children: [
                SizedBox(width: 400, child: listColumn),
                const VerticalDivider(width: 1),
                Expanded(child: _detailPane(strings)),
              ],
            );
          },
        ),
      ),
      // In due colonne il pulsante resta sopra la lista, non sulla scheda.
      floatingActionButtonLocation:
          MediaQuery.sizeOf(context).width >= _wideBreakpoint
          ? FloatingActionButtonLocation.startFloat
          : null,
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
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                strings.directoryLoadFailed,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                  _loadOrganizationName();
                },
                icon: const Icon(Icons.refresh),
                label: Text(strings.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_visibleMembers.isEmpty && _members.isNotEmpty) {
      // Il filtro non trova nessuno, ma la rubrica non è vuota.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list_off,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                strings.filterEmpty,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => setState(() => _filter = MemberFilter.all),
                child: Text(strings.filterShowAll),
              ),
            ],
          ),
        ),
      );
    }
    if (_visibleMembers.isEmpty) {
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
        itemCount: _visibleMembers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Text(
                strings.membersCount(_visibleMembers.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            );
          }
          final member = _visibleMembers[index - 1];
          return Card(
            child: ListTile(
              onTap: () => _openMember(member),
              selected:
                  MediaQuery.sizeOf(context).width >= _wideBreakpoint &&
                  _selected?.id == member.id,
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

class _EntityDetailsDialog extends StatefulWidget {
  const _EntityDetailsDialog({required this.initial});

  final EntityProfile initial;

  @override
  State<_EntityDetailsDialog> createState() => _EntityDetailsDialogState();
}

class _EntityDetailsDialogState extends State<_EntityDetailsDialog> {
  late final TextEditingController _address;
  late final TextEditingController _taxCode;
  late final TextEditingController _representative;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: widget.initial.address);
    _taxCode = TextEditingController(text: widget.initial.taxCode);
    _representative = TextEditingController(
      text: widget.initial.legalRepresentative,
    );
  }

  @override
  void dispose() {
    _address.dispose();
    _taxCode.dispose();
    _representative.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    const max = EntityProfile.maxFieldLength;
    return AlertDialog(
      title: Text(strings.entityDetails),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.entityDetailsHint),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              maxLength: max,
              decoration: InputDecoration(labelText: strings.entityAddress),
            ),
            TextField(
              controller: _taxCode,
              maxLength: max,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: strings.entityTaxCode),
            ),
            TextField(
              controller: _representative,
              maxLength: max,
              decoration: InputDecoration(
                labelText: strings.entityLegalRepresentative,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            EntityProfile(
              name: widget.initial.name,
              address: _address.text,
              taxCode: _taxCode.text,
              legalRepresentative: _representative.text,
            ),
          ),
          child: Text(strings.save),
        ),
      ],
    );
  }
}
