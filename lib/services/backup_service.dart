import 'dart:convert';
import 'dart:typed_data';

import 'package:rubrica_associati/models/member.dart';

enum BackupError {
  tooManyMembers,
  tooLarge,
  invalidContent,
  wrongFormat,
  unsupportedVersion,
  invalidMembers,
  invalidMember,
  unreadable,
  missingMemberName,
  invalidField,
}

class BackupException implements Exception {
  const BackupException(this.error, {this.row, this.field});

  final BackupError error;
  final int? row;
  final String? field;

  @override
  String toString() => 'BackupException($error, row: $row, field: $field)';
}

class BackupService {
  static const format = 'rubrica-associati';
  static const version = 1;
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxMembers = 20000;

  Uint8List encode(List<Member> members, {DateTime? exportedAt}) {
    if (members.length > maxMembers) {
      throw const BackupException(BackupError.tooManyMembers);
    }
    // Gli ID sono locali: tra telefoni il merge usa numero tessera o telefono.
    final document = <String, Object?>{
      'format': format,
      'version': version,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'members': members.map(_memberToJson).toList(growable: false),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(document)));
    if (bytes.length > maxFileBytes) {
      throw const BackupException(BackupError.tooLarge);
    }
    return bytes;
  }

  List<Member> decode(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const BackupException(BackupError.tooLarge);
    }

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const BackupException(BackupError.invalidContent);
      }
      if (decoded['format'] != format) {
        throw const BackupException(BackupError.wrongFormat);
      }
      if (decoded['version'] != version) {
        throw const BackupException(BackupError.unsupportedVersion);
      }
      final rows = decoded['members'];
      if (rows is! List || rows.length > maxMembers) {
        throw const BackupException(BackupError.invalidMembers);
      }

      return rows.indexed
          .map((entry) {
            final row = entry.$2;
            if (row is! Map<String, dynamic>) {
              throw BackupException(
                BackupError.invalidMember,
                row: entry.$1 + 1,
              );
            }
            return _memberFromJson(row, entry.$1 + 1);
          })
          .toList(growable: false);
    } on BackupException {
      rethrow;
    } on Object catch (_) {
      throw const BackupException(BackupError.unreadable);
    }
  }

  Map<String, Object?> _memberToJson(Member member) => {
    'firstName': member.firstName,
    'lastName': member.lastName,
    'phone': member.phone,
    'secondaryPhone': member.secondaryPhone,
    'memberNumber': member.memberNumber,
    'expiryDate': _dateToJson(member.expiryDate),
    'birthDate': _dateToJson(member.birthDate),
    'notes': member.notes,
  };

  Member _memberFromJson(Map<String, dynamic> row, int rowNumber) {
    final firstName = _string(row, 'firstName', 100, rowNumber);
    final lastName = _string(row, 'lastName', 100, rowNumber);
    if (firstName.isEmpty && lastName.isEmpty) {
      throw BackupException(BackupError.missingMemberName, row: rowNumber);
    }
    return Member(
      firstName: firstName,
      lastName: lastName,
      phone: _string(row, 'phone', 40, rowNumber),
      secondaryPhone: _optionalString(row, 'secondaryPhone', 40, rowNumber),
      memberNumber: _string(row, 'memberNumber', 100, rowNumber),
      expiryDate: _date(row, 'expiryDate', rowNumber),
      birthDate: _date(row, 'birthDate', rowNumber),
      notes: _string(row, 'notes', 2000, rowNumber),
    );
  }

  String _string(
    Map<String, dynamic> row,
    String key,
    int maxLength,
    int rowNumber,
  ) {
    final value = row[key];
    if (value is! String || value.length > maxLength) {
      throw BackupException(
        BackupError.invalidField,
        row: rowNumber,
        field: key,
      );
    }
    return value.trim();
  }

  String _optionalString(
    Map<String, dynamic> row,
    String key,
    int maxLength,
    int rowNumber,
  ) {
    if (!row.containsKey(key)) return '';
    return _string(row, key, maxLength, rowNumber);
  }

  DateTime? _date(Map<String, dynamic> row, String key, int rowNumber) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw BackupException(
        BackupError.invalidField,
        row: rowNumber,
        field: key,
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _dateToJson(parsed) != value) {
      throw BackupException(
        BackupError.invalidField,
        row: rowNumber,
        field: key,
      );
    }
    return parsed;
  }

  String? _dateToJson(DateTime? value) {
    if (value == null) return null;
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }
}
