import 'dart:convert';
import 'dart:typed_data';

import 'package:rubrica_associati/models/member.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

class SpreadsheetImportResult {
  const SpreadsheetImportResult({
    required this.members,
    required this.warnings,
  });

  final List<Member> members;
  final List<String> warnings;
}

class SpreadsheetImportException implements Exception {
  const SpreadsheetImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SpreadsheetImporter {
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxRows = 20000;

  static const _headerAliases = <String, Set<String>>{
    'firstName': {'nome', 'firstname'},
    'lastName': {'cognome', 'lastname'},
    'phone': {
      'telefono',
      'cellulare',
      'tel',
      'numero telefono',
      'numero cellulare',
      'phone',
    },
    'secondaryPhone': {
      'telefono 2',
      'secondo telefono',
      'cellulare 2',
      'secondo cellulare',
      'tel 2',
      'phone 2',
      'secondary phone',
    },
    'memberNumber': {
      'tessera',
      'numero tessera',
      'n tessera',
      'n. tessera',
      'codice tessera',
    },
    'expiryDate': {'scadenza', 'scadenza tessera', 'data scadenza'},
    'birthDate': {'compleanno', 'data nascita', 'nascita', 'data di nascita'},
    'notes': {'note', 'annotazioni'},
  };

  SpreadsheetImportResult parse(String fileName, Uint8List bytes) {
    // El limite evita che un file scelto per sbaglio saturi la memoria del telefono.
    if (bytes.length > maxFileBytes) {
      throw const SpreadsheetImportException(
        'Il file supera il limite di 10 MB.',
      );
    }
    final lowerName = fileName.toLowerCase();
    final rows = lowerName.endsWith('.csv')
        ? _readCsv(bytes)
        : lowerName.endsWith('.xlsx')
        ? _readExcel(bytes)
        : throw const SpreadsheetImportException(
            'Formato non supportato. Scegli un file .xlsx o .csv.',
          );
    return parseRows(rows);
  }

  SpreadsheetImportResult parseRows(List<List<Object?>> rows) {
    if (rows.length > maxRows) {
      throw const SpreadsheetImportException(
        'Il file supera il limite di 20.000 righe.',
      );
    }
    final nonEmptyRows = rows
        .where((row) => row.any((cell) => _asText(cell).isNotEmpty))
        .toList(growable: false);
    if (nonEmptyRows.isEmpty) {
      throw const SpreadsheetImportException('Il file selezionato è vuoto.');
    }

    final header = nonEmptyRows.first;
    final columns = <String, int>{};
    for (var index = 0; index < header.length; index++) {
      final normalized = _normalizeHeader(_asText(header[index]));
      for (final entry in _headerAliases.entries) {
        if (!entry.value.contains(normalized)) continue;
        if (entry.key == 'phone' && columns.containsKey('phone')) {
          columns.putIfAbsent('secondaryPhone', () => index);
        } else {
          columns[entry.key] = index;
        }
      }
    }

    if (!columns.containsKey('firstName') && !columns.containsKey('lastName')) {
      throw const SpreadsheetImportException(
        'Manca una colonna Nome o Cognome. Controlla le intestazioni.',
      );
    }

    final members = <Member>[];
    final warnings = <String>[];
    for (var index = 1; index < nonEmptyRows.length; index++) {
      final row = nonEmptyRows[index];
      final firstName = _valueAt(row, columns['firstName'], maxLength: 100);
      final lastName = _valueAt(row, columns['lastName'], maxLength: 100);
      if (firstName.isEmpty && lastName.isEmpty) {
        warnings.add('Riga ${index + 1}: ignorata perché senza nome.');
        continue;
      }

      final expiry = _dateAt(row, columns['expiryDate']);
      final birth = _dateAt(row, columns['birthDate']);
      if (expiry.invalid) {
        warnings.add('Riga ${index + 1}: scadenza non riconosciuta.');
      }
      if (birth.invalid) {
        warnings.add('Riga ${index + 1}: data di nascita non riconosciuta.');
      }

      members.add(
        Member(
          firstName: firstName,
          lastName: lastName,
          phone: _cleanPhone(_valueAt(row, columns['phone'], maxLength: 40)),
          secondaryPhone: _cleanPhone(
            _valueAt(row, columns['secondaryPhone'], maxLength: 40),
          ),
          memberNumber: _cleanNumericText(
            _valueAt(row, columns['memberNumber'], maxLength: 100),
          ),
          expiryDate: expiry.value,
          birthDate: birth.value,
          notes: _valueAt(row, columns['notes'], maxLength: 2000),
        ),
      );
    }

    if (members.isEmpty) {
      throw const SpreadsheetImportException(
        'Non ho trovato righe valide da importare.',
      );
    }
    return SpreadsheetImportResult(members: members, warnings: warnings);
  }

  List<List<Object?>> _readExcel(Uint8List bytes) {
    try {
      final workbook = Excel.decodeBytes(bytes);
      for (final tableName in workbook.tables.keys) {
        final table = workbook.tables[tableName];
        if (table == null || table.rows.isEmpty) continue;
        return table.rows
            .map<List<Object?>>(
              (row) => row.map<Object?>((cell) => cell?.value).toList(),
            )
            .toList();
      }
    } on Object catch (_) {
      throw const SpreadsheetImportException(
        'Non riesco a leggere il file Excel. Verifica che sia un .xlsx valido.',
      );
    }
    return const [];
  }

  List<List<Object?>> _readCsv(Uint8List bytes) {
    try {
      final content = utf8
          .decode(bytes, allowMalformed: true)
          .replaceAll('\r\n', '\n');
      final firstLine = content.split('\n').firstOrNull ?? '';
      final delimiter = _delimiterFor(firstLine);
      final rows = CsvToListConverter(
        fieldDelimiter: delimiter,
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(content);
      return rows.map<List<Object?>>((row) => List<Object?>.from(row)).toList();
    } on Object catch (_) {
      throw const SpreadsheetImportException(
        'Non riesco a leggere il file CSV. Verifica separatori e codifica.',
      );
    }
  }

  String _delimiterFor(String firstLine) {
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    return semicolons > commas ? ';' : ',';
  }

  String _valueAt(List<Object?> row, int? index, {int? maxLength}) {
    if (index == null || index >= row.length) return '';
    final value = _asText(row[index]);
    if (maxLength == null || value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  _ParsedDate _dateAt(List<Object?> row, int? index) {
    if (index == null || index >= row.length) return const _ParsedDate();
    final raw = row[index];
    if (raw == null || _asText(raw).isEmpty) return const _ParsedDate();
    if (raw is DateCellValue) {
      return _ParsedDate(value: raw.asDateTimeLocal());
    }
    if (raw is DateTimeCellValue) {
      return _ParsedDate(value: raw.asDateTimeLocal());
    }

    final text = _asText(raw);
    for (final pattern in ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd']) {
      try {
        return _ParsedDate(value: DateFormat(pattern).parseStrict(text));
      } on FormatException {
        // Prova el formato dopo, finché ghe n'è uno che torna.
      }
    }
    return const _ParsedDate(invalid: true);
  }

  String _asText(Object? value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString().trim();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    return value.toString().trim().replaceFirst('\ufeff', '');
  }

  String _cleanPhone(String value) =>
      _cleanNumericText(value).replaceAll(RegExp(r'[^0-9+() /.-]'), '');

  String _cleanNumericText(String value) =>
      value.endsWith('.0') ? value.substring(0, value.length - 2) : value;

  String _normalizeHeader(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ParsedDate {
  const _ParsedDate({this.value, this.invalid = false});

  final DateTime? value;
  final bool invalid;
}
