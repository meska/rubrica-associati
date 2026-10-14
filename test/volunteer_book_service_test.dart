import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';
import 'package:rubrica_associati/services/volunteer_book_service.dart';

const _labels = VolunteerBookLabels(
  entity: 'Ente',
  address: 'Indirizzo',
  taxCode: 'CF',
  representative: 'Rappr.',
  generatedOn: 'Generato il',
  number: 'N.',
  started: 'inizio',
  ceased: 'cessato',
  born: 'nato/a',
  residence: 'residenza',
  regularTitle: 'Volontari',
  occasionalTitle: 'Occasionali',
  empty: 'Vuoto',
);

VolunteerEntry _e(
  int n,
  String last, {
  bool occ = false,
  String? end,
  String tax = 'RSSMRA80A01H501U',
}) => VolunteerEntry(
  volunteerId: n,
  progressiveNumber: n,
  firstName: 'Mario',
  lastName: last,
  taxCode: tax,
  birthDate: '1980-01-01',
  birthPlace: 'Roma',
  residence: 'Via Roma 1',
  occasional: occ,
  startDate: '2024-03-01',
  endDate: end,
  note: '',
);

void main() {
  const service = VolunteerBookService();
  const profile = EntityProfile(name: 'Centro', address: 'Via X');

  test('sezioni separate e progressivi propri', () {
    final lines = service.lines(
      entries: [_e(1, 'Rossi'), _e(1, 'Bianchi', occ: true)],
      profile: profile,
      labels: _labels,
      generated: DateTime(2026, 10, 14),
    );
    final text = lines.join('\n');
    expect(text, contains('Ente: Centro'));
    expect(text, contains('Generato il: 2026-10-14'));
    final iReg = lines.indexOf('Volontari');
    final iOcc = lines.indexOf('Occasionali');
    expect(iReg, isNonNegative);
    expect(iOcc, greaterThan(iReg));
    expect(lines.indexWhere((l) => l.contains('Rossi')), lessThan(iOcc));
    expect(lines.indexWhere((l) => l.contains('Bianchi')), greaterThan(iOcc));
  });

  test('riga con tutti i dati del DM e cessazione', () {
    final lines = service.lines(
      entries: [_e(1, 'Rossi', end: '2025-01-31')],
      profile: profile,
      labels: _labels,
      generated: DateTime(2026, 10, 14),
    );
    final row = lines.firstWhere((l) => l.contains('Rossi'));
    expect(row, contains('N. 1'));
    expect(row, contains('Rossi Mario'));
    expect(row, contains('RSSMRA80A01H501U'));
    expect(row, contains('nato/a Roma 1980-01-01'));
    expect(row, contains('residenza Via Roma 1'));
    expect(row, contains('inizio 2024-03-01'));
    expect(row, contains('cessato 2025-01-31'));
  });

  test('senza codice fiscale non resta un trattino vuoto', () {
    final lines = service.lines(
      entries: [_e(1, 'Rossi', tax: '')],
      profile: profile,
      labels: _labels,
      generated: DateTime(2026, 10, 14),
    );
    final row = lines.firstWhere((l) => l.contains('Rossi'));
    expect(row, isNot(contains(' —  — ')));
  });

  test('registro vuoto', () {
    final lines = service.lines(
      entries: const [],
      profile: profile,
      labels: _labels,
      generated: DateTime(2026, 10, 14),
    );
    expect(lines, contains('Vuoto'));
  });

  test('sezione occasionali omessa se vuota', () {
    final lines = service.lines(
      entries: [_e(1, 'Rossi')],
      profile: profile,
      labels: _labels,
      generated: DateTime(2026, 10, 14),
    );
    expect(lines, isNot(contains('Occasionali')));
  });
}
