import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/services/archive_pdf_service.dart';
import 'package:rubrica_associati/services/register_book_service.dart';
import 'package:share_plus/share_plus.dart';

/// Libro soci: scelta dell'anno ed export PDF per archiviazione.
class RegisterBookScreen extends StatefulWidget {
  const RegisterBookScreen({
    super.key,
    required this.entries,
    required this.profile,
    this.pdfService = const ArchivePdfService(),
  });

  final List<RegisterEntry> entries;
  final EntityProfile profile;
  final ArchivePdfService pdfService;

  @override
  State<RegisterBookScreen> createState() => _RegisterBookScreenState();
}

class _RegisterBookScreenState extends State<RegisterBookScreen> {
  static const _service = RegisterBookService();
  late final List<int> _years = _service.availableYears(
    widget.entries,
    DateTime.now(),
  );
  late int _year = _years.first;
  bool _busy = false;

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
