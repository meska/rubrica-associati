import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/services/archive_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> font() async =>
      File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync();

  final service = ArchivePdfService(fontLoader: font);
  final lines = [for (var i = 0; i < 150; i++) 'Rossi Mario $i — à è ì ò ù'];

  Future<ArchivePdf> make({
    List<String>? l,
    String title = 'Libro soci 2026',
  }) => service.build(
    title: title,
    entityName: 'Centro <Pensionati> & C.',
    lines: l ?? lines,
    pageLabel: 'Pagina',
    ofLabel: 'di',
    digestLabel: 'SHA-256',
    created: DateTime.utc(2026, 10, 13),
  );

  test('PDF 1.4 senza cifratura né trasparenze, font incorporato', () async {
    final pdf = await make();
    final text = latin1.decode(pdf.bytes);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text.contains('/Encrypt'), isFalse);
    expect(text.contains('/SMask'), isFalse);
    expect(text.contains('/ca '), isFalse);
    expect(text.contains('/FontFile2'), isTrue);
    expect(text.contains('/Metadata'), isTrue);
  });

  test('metadati XMP ben formati con caratteri speciali escapati', () async {
    final text = latin1.decode((await make()).bytes);
    expect(text.contains('Centro &lt;Pensionati> &amp; C.'), isTrue);
    expect(
      text.contains('pdfaid'),
      isFalse,
      reason: 'nessuna dichiarazione PDF/A',
    );
  });

  test('impronta SHA-256 di file e contenuto', () async {
    final pdf = await make();
    expect(pdf.fileSha256, sha256.convert(pdf.bytes).toString());
    expect(pdf.contentSha256, ArchivePdfService.contentDigest(lines));
    final other = await make(l: [...lines, 'extra']);
    expect(other.contentSha256, isNot(pdf.contentSha256));
    expect(other.fileSha256, isNot(pdf.fileSha256));
  });

  test('pagina x di y: più pagine', () async {
    final text = latin1.decode((await make()).bytes);
    final pages = RegExp(r'/Type/Page/').allMatches(text).length;
    expect(pages, greaterThan(1));
    expect(text.contains('/Count $pages'), isTrue);
  });
}
