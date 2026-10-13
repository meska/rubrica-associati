import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rubrica_associati/data/closure_repository.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/services/archive_pdf_service.dart';
import 'package:rubrica_associati/services/closure_service.dart';
import 'package:rubrica_associati/services/register_book_service.dart';
import 'package:share_plus/share_plus.dart';

/// File scelto dall'utente per la chiusura firmata.
typedef PickedClosure = ({String name, Uint8List bytes});
typedef ClosurePicker = Future<PickedClosure?> Function(int maxBytes);

Future<PickedClosure?> pickClosureFile(int maxBytes) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'p7m'],
    withData: false,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  if (file.size > maxBytes) throw const ClosureException('tooLarge');
  return (name: file.name, bytes: await file.xFile.readAsBytes());
}

/// Libro soci: scelta dell'anno ed export PDF per archiviazione.
class RegisterBookScreen extends StatefulWidget {
  const RegisterBookScreen({
    super.key,
    required this.entries,
    required this.profile,
    this.pdfService = const ArchivePdfService(),
    this.closureService,
    this.closurePicker = pickClosureFile,
  });

  final List<RegisterEntry> entries;
  final EntityProfile profile;
  final ArchivePdfService pdfService;

  /// Se nullo la sezione «chiusura annuale» non viene mostrata.
  final ClosureService? closureService;
  final ClosurePicker closurePicker;

  @override
  State<RegisterBookScreen> createState() => _RegisterBookScreenState();
}

class _RegisterBookScreenState extends State<RegisterBookScreen> {
  static const _service = RegisterBookService();
  late final List<int> _years = _service.availableYears(
    widget.entries,
    DateTime.now(),
  );
  // Con l'archivio chiusure l'anno proposto è l'ultimo concluso, non quello
  // in corso (che non si può ancora chiudere).
  late int _year =
      widget.closureService != null && _years.contains(DateTime.now().year - 1)
      ? DateTime.now().year - 1
      : _years.first;
  bool _busy = false;
  List<YearClosure> _closures = const [];
  Map<int, bool> _intact = const {};
  final Map<int, String> _exportDigests = {};

  @override
  void initState() {
    super.initState();
    _loadClosures();
  }

  Future<void> _loadClosures() async {
    final service = widget.closureService;
    if (service == null) return;
    final all = await service.repository.all();
    final intact = <int, bool>{};
    for (final c in all) {
      intact[c.id] = await service.verify(c);
    }
    if (!mounted) return;
    setState(() {
      _closures = all;
      _intact = intact;
    });
  }

  String _closureError(AppLocalizations s, Object e) {
    if (e is ClosureException) {
      return switch (e.code) {
        'invalidYear' => s.closureErrYear,
        'emptyFile' => s.closureErrEmpty,
        'tooLarge' => s.closureErrSize,
        'unsupportedType' => s.closureErrType,
        'notPdf' => s.closureErrNotPdf,
        _ => s.closureErrGeneric,
      };
    }
    return s.closureErrGeneric;
  }

  Future<void> _archiveClosure() async {
    final service = widget.closureService;
    if (service == null) return;
    final s = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final picked = await widget.closurePicker(service.maxBytes);
      if (picked == null) return;
      await service.archive(
        year: _year,
        bytes: picked.bytes,
        originalName: picked.name,
        now: DateTime.now(),
        exportSha256: _exportDigests[_year] ?? '',
      );
      await _loadClosures();
      messenger.showSnackBar(SnackBar(content: Text(s.closureSaved('$_year'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_closureError(s, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  RegisterBookLabels _labels(AppLocalizations s) => RegisterBookLabels(
    entity: s.bookEntity,
    address: s.bookAddress,
    taxCode: s.bookTaxCode,
    representative: s.bookRepresentative,
    year: s.bookYear,
    generatedOn: s.bookGeneratedOn,
    number: s.bookNumber,
    admitted: s.bookAdmitted,
    ceased: s.bookCeased,
    empty: s.bookEmpty,
    causes: {
      CessationCause.resignation: s.bookCauseResignation,
      CessationCause.exclusion: s.bookCauseExclusion,
      CessationCause.death: s.bookCauseDeath,
      CessationCause.other: s.bookCauseOther,
    },
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
        entries: widget.entries,
        year: _year,
        profile: widget.profile,
        labels: _labels(s),
        generated: DateTime.now(),
      );
      final pdf = await widget.pdfService.build(
        title: '${s.bookPdfTitle} $_year',
        entityName: widget.profile.name,
        lines: lines,
        pageLabel: s.bookPage,
        ofLabel: s.bookOf,
        digestLabel: s.bookDigest,
      );
      _exportDigests[_year] = pdf.fileSha256;
      final dir = await getTemporaryDirectory();
      final name = 'libro-soci-$_year.pdf';
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
          title: s.bookShareTitle,
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _closureSection(AppLocalizations s) {
    final pending = widget.closureService!.pendingYears(
      entries: widget.entries,
      closures: _closures,
      now: DateTime.now(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.closureTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(s.closureHint),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              s.closurePending(pending.join(', ')),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _archiveClosure,
            icon: const Icon(Icons.verified_outlined),
            label: Text(s.closureArchive),
          ),
          if (_closures.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.closureNone),
            ),
          for (final c in _closures)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                _intact[c.id] == true ? Icons.check_circle : Icons.warning,
                color: _intact[c.id] == true ? Colors.green : Colors.orange,
              ),
              title: Text('${c.year} — ${c.fileName}'),
              subtitle: Text(
                '${_intact[c.id] == true ? s.closureIntact : s.closureAltered}'
                ' · ${s.closureArchivedOn(c.archivedAt.substring(0, 10))}'
                '\nSHA-256: ${c.sha256}',
              ),
              isThreeLine: true,
            ),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final rows = _service.entriesForYear(widget.entries, _year);
    return Scaffold(
      appBar: AppBar(title: Text(s.bookTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(s.bookHint)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(s.bookYear),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _year,
                    items: [
                      for (final y in _years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(s.bookExport),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (widget.closureService != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(child: _closureSection(s)),
              ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(s.bookEmpty))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        return ListTile(
                          leading: Text('${r.progressiveNumber}'),
                          title: Text('${r.lastName} ${r.firstName}'.trim()),
                          subtitle: Text(
                            '${s.bookAdmitted} ${r.admissionDate}'
                            '${r.cessationDate == null ? '' : ' — ${s.bookCeased} ${r.cessationDate}'}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
