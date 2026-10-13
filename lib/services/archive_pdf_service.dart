import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

/// Risultato di un export PDF di archiviazione.
class ArchivePdf {
  const ArchivePdf({
    required this.bytes,
    required this.fileSha256,
    required this.contentSha256,
  });

  final Uint8List bytes;

  /// Impronta SHA-256 dell'intero file (da comunicare a parte: non può stare
  /// dentro il file stesso).
  final String fileSha256;

  /// Impronta SHA-256 del contenuto (righe), stampata in ogni pagina.
  final String contentSha256;
}

/// Spike: PDF per archiviazione «vicino a PDF/A» (font incorporato, metadati
/// XMP, PDF 1.4, niente trasparenze né cifratura, «pagina x di y»).
///
/// Non è un PDF/A conforme: manca il profilo colore (OutputIntent sRGB) e
/// non c'è una validazione con veraPDF. Nell'app va chiamato «archiviazione
/// PDF», mai «PDF/A».
class ArchivePdfService {
  const ArchivePdfService({this.fontLoader = _defaultFont});

  final Future<Uint8List> Function() fontLoader;

  static Future<Uint8List> _defaultFont() async {
    final data = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static String contentDigest(List<String> lines) =>
      sha256.convert(utf8.encode(lines.join('\n'))).toString();

  Future<ArchivePdf> build({
    required String title,
    required String entityName,
    required List<String> lines,
    required String pageLabel,
    required String ofLabel,
    required String digestLabel,
    DateTime? created,
  }) async {
    final when = (created ?? DateTime.now()).toUtc();
    final digest = contentDigest(lines);
    final font = pw.Font.ttf(ByteData.sublistView(await fontLoader()));
    final doc = pw.Document(
      version: PdfVersion.pdf_1_4,
      compress: false,
      title: title,
      author: entityName,
      creator: 'Rubrica Associati',
      producer: 'Rubrica Associati',
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    doc.document.catalog.metadata = PdfMetadata(
      doc.document,
      _xmp(title: title, author: entityName, created: when),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (c) => pw.Text(
          '$entityName — $title',
          style: const pw.TextStyle(fontSize: 11),
        ),
        footer: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$digestLabel $digest',
              style: const pw.TextStyle(fontSize: 6),
            ),
            pw.Text(
              '$pageLabel ${c.pageNumber} $ofLabel ${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        build: (c) => [
          for (final l in lines)
            pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
    final bytes = Uint8List.fromList(await doc.save());
    return ArchivePdf(
      bytes: bytes,
      fileSha256: sha256.convert(bytes).toString(),
      contentSha256: digest,
    );
  }

  XmlDocument _xmp({
    required String title,
    required String author,
    required DateTime created,
  }) {
    final b = XmlBuilder();
    b.processing('xpacket', 'begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"');
    b.element(
      'x:xmpmeta',
      namespaces: {'adobe:ns:meta/': 'x'},
      nest: () {
        b.element(
          'rdf:RDF',
          namespaces: {'http://www.w3.org/1999/02/22-rdf-syntax-ns#': 'rdf'},
          nest: () {
            b.element(
              'rdf:Description',
              attributes: {'rdf:about': ''},
              namespaces: {
                'http://purl.org/dc/elements/1.1/': 'dc',
                'http://ns.adobe.com/xap/1.0/': 'xmp',
                'http://ns.adobe.com/pdf/1.3/': 'pdf',
              },
              nest: () {
                b.element(
                  'dc:title',
                  nest: () {
                    b.element(
                      'rdf:Alt',
                      nest: () {
                        b.element(
                          'rdf:li',
                          attributes: {'xml:lang': 'x-default'},
                          nest: title,
                        );
                      },
                    );
                  },
                );
                b.element(
                  'dc:creator',
                  nest: () {
                    b.element(
                      'rdf:Seq',
                      nest: () {
                        b.element('rdf:li', nest: author);
                      },
                    );
                  },
                );
                b.element('xmp:CreateDate', nest: created.toIso8601String());
                b.element('xmp:CreatorTool', nest: 'Rubrica Associati');
                b.element('pdf:Producer', nest: 'Rubrica Associati');
              },
            );
          },
        );
      },
    );
    b.processing('xpacket', 'end="r"');
    return b.buildDocument();
  }
}
