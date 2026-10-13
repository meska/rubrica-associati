import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/services/roster_service.dart';

Member m(
  String f,
  String l, {
  String phone = '333',
  String tax = 'RSSMRA80A01H501U',
}) => Member(
  firstName: f,
  lastName: l,
  phone: phone,
  memberNumber: '7',
  taxCode: tax,
  birthPlace: 'Roma',
  notes: 'riservato',
);

void main() {
  const service = RosterService();

  test('entries contain only name and quality, sorted by surname', () {
    final entries = service.entries([
      m('Zoe', 'Bianchi'),
      m('Anna', 'Verdi'),
      m('Luca', 'Bianchi'),
    ]);
    expect(entries.map((e) => e.displayName).toList(), [
      'Bianchi Luca',
      'Bianchi Zoe',
      'Verdi Anna',
    ]);
  });

  test('csv never leaks personal data', () {
    final csv = service.toCsv(
      [m('Anna', 'Verdi')],
      nameHeader: 'Nome',
      qualityHeader: 'Qualità',
      qualityValue: 'Socio',
    );
    expect(csv, 'Nome,Qualità\r\nVerdi Anna,Socio\r\n');
    for (final secret in ['333', 'RSSMRA', 'Roma', 'riservato']) {
      expect(csv.contains(secret), isFalse);
    }
  });

  test('csv escapes commas, quotes and formula injection', () {
    final csv = service.toCsv(
      [m('Anna "Nan"', 'De, Verdi'), m('=cmd', '+x')],
      nameHeader: 'N',
      qualityHeader: 'Q',
      qualityValue: 'S',
    );
    expect(csv, contains('"De, Verdi Anna ""Nan""",S'));
    expect(csv, contains("'+x =cmd,S"));
  });

  test('empty list yields header only', () {
    expect(
      service.toCsv(
        const [],
        nameHeader: 'N',
        qualityHeader: 'Q',
        qualityValue: 'S',
      ),
      'N,Q\r\n',
    );
  });
}
