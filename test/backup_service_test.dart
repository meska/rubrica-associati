import 'dart:convert';
import 'dart:typed_data';

import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = BackupService();

  test('esporta e reimporta tutti i campi senza gli id locali', () {
    final bytes = service.encode([
      Member(
        id: 42,
        firstName: 'Giovanna',
        lastName: 'Dall’Ò',
        phone: '+39 049 123456',
        secondaryPhone: '333 9876543',
        memberNumber: 'A-001',
        expiryDate: DateTime(2028, 12, 31),
        birthDate: DateTime(1949, 3, 2),
        notes: 'Volontaria',
      ),
    ], exportedAt: DateTime.utc(2026, 7, 16, 12));

    final members = service.decode(bytes);

    expect(members, hasLength(1));
    expect(members.single.id, isNull);
    expect(members.single.fullName, 'Giovanna Dall’Ò');
    expect(members.single.memberNumber, 'A-001');
    expect(members.single.secondaryPhone, '333 9876543');
    expect(members.single.expiryDate, DateTime(2028, 12, 31));
    expect(members.single.birthDate, DateTime(1949, 3, 2));
  });

  test('rifiuta JSON generico che non è un backup Rubrica Associati', () {
    final bytes = Uint8List.fromList(utf8.encode('{"members":[]}'));

    expect(() => service.decode(bytes), throwsA(isA<BackupException>()));
  });

  test('rifiuta campi troppo lunghi o di tipo errato', () {
    final document = {
      'format': BackupService.format,
      'version': BackupService.version,
      'members': [
        {
          'firstName': 123,
          'lastName': 'Rossi',
          'phone': '',
          'memberNumber': '',
          'expiryDate': null,
          'birthDate': null,
          'notes': '',
        },
      ],
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(document)));

    expect(() => service.decode(bytes), throwsA(isA<BackupException>()));
  });
}
