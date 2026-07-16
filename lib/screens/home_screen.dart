import 'dart:async';
import 'dart:io';

import 'package:rubrica_associati/data/member_repository.dart';
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
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['rubrica', 'json', 'xlsx', 'csv'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    if (file.size > BackupService.maxFileBytes) {
      _showMessage('Il file supera il limite di 10 MB.');
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline),
          title: const Text('Importazione completata'),
          content: Text(
            '${saved.inserted} nuovi associati\n'
            '${saved.updated} associati aggiornati'
            '${warningCount == 0 ? '' : '\n\n$warningCount righe con avvisi.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      );
    } on SpreadsheetImportException catch (error) {
      _showMessage(error.message);
    } on BackupException catch (error) {
      _showMessage(error.message);
    } on Object catch (_) {
      _showMessage(
        'Importazione non riuscita. Il file potrebbe essere danneggiato.',
      );
    }
  }

  Future<void> _shareBackup() async {
    try {
      final members = await widget.repository.search('');
      if (members.isEmpty) {
        _showMessage(
          'La rubrica è vuota: non c’è ancora nulla da condividere.',
        );
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
          title: 'Condividi Rubrica Associati',
          subject: 'Backup Rubrica Associati del $date',
          sharePositionOrigin: origin,
        ),
      );
    } on BackupException catch (error) {
      _showMessage(error.message);
    } on Object catch (_) {
      _showMessage('Non è stato possibile condividere la rubrica.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDonations() async {
    // La donazion la resta fora dall'app e no la sblocca gnente: xe proprio volontaria.
    final opened = await launchUrl(
      _donationsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      _showMessage('Non è stato possibile aprire la pagina delle donazioni.');
    }
  }

  Future<void> _editOrganizationName() async {
    var editedName = _organizationName;
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome del centro'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: _organizationName,
            autofocus: true,
            maxLength: MemberRepository.maxOrganizationNameLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome visualizzato'),
            onChanged: (value) => editedName = value,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Inserisci il nome del centro'
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
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, editedName.trim());
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (name == null || name == _organizationName) return;

    try {
      await widget.repository.saveOrganizationName(name);
      if (!mounted) return;
      setState(() => _organizationName = name);
    } on Object catch (_) {
      _showMessage('Non è stato possibile salvare il nome del centro.');
    }
  }

  Future<void> _showImportHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Come preparare il file'),
        content: const SingleChildScrollView(
          child: Text(
            'Per trasferire tutta la rubrica tra dispositivi usa Condividi rubrica e importa il file .rubrica sull’altro dispositivo.\n\n'
            'Puoi anche usare un file Excel .xlsx oppure CSV. La prima riga deve contenere le intestazioni.\n\n'
            'Colonne riconosciute:\n'
            '• Nome\n• Cognome\n• Telefono\n• Secondo telefono\n• Numero tessera\n'
            '• Scadenza tessera\n• Data di nascita\n• Note\n\n'
            'Le date possono essere nel formato 31/12/2026. Numero tessera e telefono servono anche per riconoscere e aggiornare i duplicati.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/branding/rubrica-associati-logo.png',
              semanticLabel: 'Logo Rubrica Associati',
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rubrica Associati'),
            Text(
              _organizationName,
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
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.ios_share_outlined),
                  title: Text('Condividi rubrica'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Importa rubrica / Excel'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'organization',
                child: ListTile(
                  leading: Icon(Icons.business_outlined),
                  title: Text('Nome del centro'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'help',
                child: ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('Formato del file'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'donate',
                child: ListTile(
                  leading: Icon(Icons.volunteer_activism_outlined),
                  title: Text('Sostieni il progetto'),
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
                hintText: 'Cerca nome, telefono o tessera',
                leading: const Icon(Icons.search),
                trailing: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Cancella ricerca',
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
        label: const Text('Aggiungi'),
      ),
    );
  }

  Widget _buildContent() {
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
                    ? 'La rubrica è vuota'
                    : 'Nessun associato trovato',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _searchController.text.isEmpty
                    ? 'Aggiungi il primo associato oppure importa una rubrica o un file Excel.'
                    : 'Prova con un altro nome, telefono o numero tessera.',
                textAlign: TextAlign.center,
              ),
              if (_searchController.text.isEmpty) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Importa rubrica / Excel'),
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
                '${_members.length} ${_members.length == 1 ? 'associato' : 'associati'}',
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
              subtitle: Text(_memberSubtitle(member)),
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

  String _memberSubtitle(Member member) {
    final parts = <String>[];
    if (member.phone.isNotEmpty) parts.add(member.phone);
    if (member.secondaryPhone.isNotEmpty) parts.add(member.secondaryPhone);
    if (member.memberNumber.isNotEmpty) {
      parts.add('Tessera ${member.memberNumber}');
    }
    if (member.isExpired && member.expiryDate != null) {
      parts.add(
        'Scaduta il ${DateFormat('dd/MM/yyyy').format(member.expiryDate!)}',
      );
    }
    return parts.isEmpty ? 'Apri la scheda' : parts.join(' · ');
  }
}
