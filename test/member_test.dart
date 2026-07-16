import 'package:rubrica_associati/models/member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializza e ricostruisce tutti i campi', () {
    final original = Member(
      id: 7,
      firstName: 'Anna',
      lastName: 'Verdi',
      phone: '+39 0123 456789',
      memberNumber: 'A-42',
      expiryDate: DateTime(2027, 12, 31),
      birthDate: DateTime(1950, 5, 4),
      notes: 'Socio volontario',
    );

    final restored = Member.fromMap(original.toMap());

    expect(restored.fullName, 'Anna Verdi');
    expect(restored.phoneKey, '390123456789');
    expect(restored.memberNumber, 'A-42');
    expect(restored.expiryDate, DateTime(2027, 12, 31));
    expect(restored.birthDate, DateTime(1950, 5, 4));
  });
}
