import 'dart:convert';
import 'dart:typed_data';

import 'package:anteas_rubrica/services/spreadsheet_importer.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final importer = SpreadsheetImporter();

  test('riconosce intestazioni italiane e date', () {
    final result = importer.parseRows([
      ['Nome', 'Cognome', 'Cellulare', 'N. tessera', 'Scadenza'],
      ['Maria', 'Rossi', 3331234567, 12.0, '31/12/2027'],
    ]);

    expect(result.members, hasLength(1));
    final member = result.members.single;
    expect(member.fullName, 'Maria Rossi');
    expect(member.phone, '3331234567');
    expect(member.memberNumber, '12');
    expect(member.expiryDate, DateTime(2027, 12, 31));
    expect(result.warnings, isEmpty);
  });

  test('legge CSV italiano separato da punto e virgola', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        'Nome;Cognome;Telefono;Numero tessera\nLuca;Bianchi;049 123456;009\n',
      ),
    );

    final result = importer.parse('tesserati.csv', bytes);

    expect(result.members.single.fullName, 'Luca Bianchi');
    expect(result.members.single.memberNumber, '009');
  });

  test('legge un vero file xlsx', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Tesserati'];
    sheet.appendRow([
      TextCellValue('Nome'),
      TextCellValue('Cognome'),
      TextCellValue('Telefono'),
      TextCellValue('Data di nascita'),
    ]);
    sheet.appendRow([
      TextCellValue('Giulia'),
      TextCellValue('Neri'),
      TextCellValue('333 0000000'),
      DateCellValue(year: 1948, month: 2, day: 3),
    ]);
    final encoded = workbook.encode();
    expect(encoded, isNotNull);

    final result = importer.parse(
      'tesserati.xlsx',
      Uint8List.fromList(encoded!),
    );

    expect(result.members.single.fullName, 'Giulia Neri');
    expect(result.members.single.birthDate, DateTime(1948, 2, 3));
  });

  test('rifiuta file senza colonne nome e cognome', () {
    expect(
      () => importer.parseRows([
        ['Telefono', 'Tessera'],
        ['123', 'A1'],
      ]),
      throwsA(isA<SpreadsheetImportException>()),
    );
  });

  test('rifiuta file oltre il limite di sicurezza', () {
    expect(
      () => importer.parse(
        'enorme.csv',
        Uint8List(SpreadsheetImporter.maxFileBytes + 1),
      ),
      throwsA(isA<SpreadsheetImportException>()),
    );
  });
}
