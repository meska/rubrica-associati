import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/services/archive_pdf_service.dart';
import 'package:rubrica_associati/services/volunteer_book_service.dart';
import 'package:share_plus/share_plus.dart';

/// Registro volontari: elenco (volontari e, separati, occasionali),
/// iscrizione, correzione, cessazione ed export PDF per archiviazione.
class VolunteerScreen extends StatefulWidget {
  const VolunteerScreen({
    super.key,
    required this.repository,
    required this.profile,
    this.pdfService = const ArchivePdfService(),
  });

  final VolunteerRepository repository;
  final EntityProfile profile;
  final ArchivePdfService pdfService;

  @override
  State<VolunteerScreen> createState() => _VolunteerScreenState();
}

class _VolunteerScreenState extends State<VolunteerScreen> {
  static const _service = VolunteerBookService();
  List<VolunteerEntry> _entries = const [];
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repository.entries();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loaded = true;
    });
  }

  String _error(AppLocalizations s, Object e) {
    if (e is ArgumentError) {
      final m = e.message.toString();
      if (m.contains('Residenza')) return s.volErrResidence;
      if (m.contains('codice fiscale') || m.contains('Nome e cognome')) {
        return s.volErrIdentity;
      }
    }
    return s.volErrGeneric;
  }

  Future<void> _edit([VolunteerEntry? existing]) async {
    final s = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final data = await showDialog<_VolunteerData>(
      context: context,
      builder: (_) => _VolunteerDialog(existing: existing),
    );
    if (data == null) return;
    try {
      if (existing == null) {
        await widget.repository.enroll(
          firstName: data.firstName,
          lastName: data.lastName,
          startDate: data.startDate,
          taxCode: data.taxCode,
          birthDate: data.birthDate,
          birthPlace: data.birthPlace,
          residence: data.residence,
          occasional: data.occasional,
        );
      } else {
        await widget.repository.correct(
          volunteerId: existing.volunteerId,
          date: RegisterRepository.todayIso(DateTime.now()),
          firstName: data.firstName,
          lastName: data.lastName,
          taxCode: data.taxCode,
          birthDate: data.birthDate,
          birthPlace: data.birthPlace,
          residence: data.residence,
          occasional: data.occasional,
        );
      }
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_error(s, e))));
    }
  }

  Future<void> _cease(VolunteerEntry entry) async {
    final s = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showDatePicker(
      context: context,
      helpText: s.volEndDate.toUpperCase(),
      initialDate: DateTime.now(),
      firstDate: DateTime.tryParse(entry.startDate) ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    try {
      await widget.repository.cease(
        volunteerId: entry.volunteerId,
        endDate: RegisterRepository.todayIso(picked),
      );
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_error(s, e))));
    }
  }

  VolunteerBookLabels _labels(AppLocalizations s) => VolunteerBookLabels(
    entity: s.bookEntity,
    address: s.bookAddress,
    taxCode: s.bookTaxCode,
    representative: s.bookRepresentative,
    generatedOn: s.bookGeneratedOn,
    number: s.bookNumber,
    started: s.volPdfStarted,
    ceased: s.bookCeased,
    born: s.volPdfBorn,
    residence: s.volPdfResidence,
    regularTitle: s.volSectionRegular,
    occasionalTitle: s.volPdfOccasional,
    empty: s.volEmpty,
  );

  Future<void> _export() async {
    final s = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final lines = _service.lines(
        entries: _entries,
        profile: widget.profile,
        labels: _labels(s),
        generated: DateTime.now(),
      );
      final pdf = await widget.pdfService.build(
        title: s.volPdfTitle,
        entityName: widget.profile.name,
        lines: lines,
        pageLabel: s.bookPage,
        ofLabel: s.bookOf,
        digestLabel: s.bookDigest,
      );
      final dir = await getTemporaryDirectory();
      final name = 'registro-volontari.pdf';
      final file = File(path.join(dir.path, name));
      await file.writeAsBytes(pdf.bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.bookDigestNote(pdf.fileSha256))));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          fileNameOverrides: [name],
          title: s.volShareTitle,
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile(AppLocalizations s, VolunteerEntry e) {
    return ListTile(
      leading: Text('${e.progressiveNumber}'),
      title: Text('${e.lastName} ${e.firstName}'.trim()),
      subtitle: Text(
        '${s.volStartDate} ${e.startDate} · '
        '${e.endDate == null ? s.volActive : s.volStatusCeased(e.endDate!)}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') _edit(e);
          if (v == 'cease') _cease(e);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(s.volCorrect)),
          if (e.isActive)
            PopupMenuItem(value: 'cease', child: Text(s.volCease)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final regular = _entries.where((e) => !e.occasional).toList();
    final occasional = _entries.where((e) => e.occasional).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.volTitle),
        actions: [
          IconButton(
            tooltip: s.volExport,
            onPressed: _busy || _entries.isEmpty ? null : _export,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(s.volAdd),
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(s.volHint),
                  ),
                  if (_entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(s.volEmpty),
                    ),
                  if (regular.isNotEmpty) ...[
                    _header(s.volSectionRegular),
                    for (final e in regular) _tile(s, e),
                  ],
                  if (occasional.isNotEmpty) ...[
                    _header(s.volSectionOccasional),
                    for (final e in occasional) _tile(s, e),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _VolunteerData {
  const _VolunteerData({
    required this.firstName,
    required this.lastName,
    required this.taxCode,
    required this.birthDate,
    required this.birthPlace,
    required this.residence,
    required this.startDate,
    required this.occasional,
  });

  final String firstName;
  final String lastName;
  final String taxCode;
  final String birthDate;
  final String birthPlace;
  final String residence;
  final String startDate;
  final bool occasional;
}

class _VolunteerDialog extends StatefulWidget {
  const _VolunteerDialog({this.existing});

  final VolunteerEntry? existing;

  @override
  State<_VolunteerDialog> createState() => _VolunteerDialogState();
}

class _VolunteerDialogState extends State<_VolunteerDialog> {
  late final _first = TextEditingController(text: widget.existing?.firstName);
  late final _last = TextEditingController(text: widget.existing?.lastName);
  late final _tax = TextEditingController(text: widget.existing?.taxCode);
  late final _place = TextEditingController(text: widget.existing?.birthPlace);
  late final _residence = TextEditingController(
    text: widget.existing?.residence,
  );
  late String _birth = widget.existing?.birthDate ?? '';
  late String _start =
      widget.existing?.startDate ?? RegisterRepository.todayIso(DateTime.now());
  late bool _occasional = widget.existing?.occasional ?? false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _tax.dispose();
    _place.dispose();
    _residence.dispose();
    super.dispose();
  }

  Future<void> _pickBirth(AppLocalizations s) async {
    final picked = await showDatePicker(
      context: context,
      helpText: s.dateOfBirthPicker,
      initialDate: DateTime.tryParse(_birth) ?? DateTime(1980),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _birth = RegisterRepository.todayIso(picked));
    }
  }

  Future<void> _pickStart(AppLocalizations s) async {
    final picked = await showDatePicker(
      context: context,
      helpText: s.volStartDate.toUpperCase(),
      initialDate: DateTime.tryParse(_start) ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _start = RegisterRepository.todayIso(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? s.volCorrect : s.volAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _first,
              decoration: InputDecoration(labelText: s.firstName),
            ),
            TextField(
              controller: _last,
              decoration: InputDecoration(labelText: s.lastName),
            ),
            TextField(
              controller: _tax,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: s.taxCode),
            ),
            TextField(
              controller: _place,
              decoration: InputDecoration(labelText: s.birthPlace),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.dateOfBirth),
              subtitle: Text(_birth.isEmpty ? '—' : _birth),
              onTap: () => _pickBirth(s),
            ),
            TextField(
              controller: _residence,
              decoration: InputDecoration(labelText: s.volResidence),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.volStartDate),
              subtitle: Text(_start),
              onTap: editing ? null : () => _pickStart(s),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.volOccasional),
              value: _occasional,
              onChanged: (v) => setState(() => _occasional = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _VolunteerData(
              firstName: _first.text,
              lastName: _last.text,
              taxCode: _tax.text,
              birthDate: _birth,
              birthPlace: _place.text,
              residence: _residence.text,
              startDate: _start,
              occasional: _occasional,
            ),
          ),
          child: Text(s.save),
        ),
      ],
    );
  }
}
