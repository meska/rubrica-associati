import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/services/register_book_service.dart';

void main() {
  const labels = RegisterBookLabels(
    entity: 'Ente',
    address: 'Indirizzo',
    taxCode: 'CF',
    representative: 'Rappresentante',
    year: 'Anno',
    generatedOn: 'Generato il',
    number: 'N.',
    admitted: 'ammesso',
    ceased: 'cessato',
    empty: 'Nessuna annotazione',
    causes: {
      CessationCause.resignation: 'dimissioni',
      CessationCause.exclusion: 'esclusione',
      CessationCause.death: 'decesso',
      CessationCause.other: 'altro',
    },
  );
  const service = RegisterBookService();
  const profile = EntityProfile(
    name: 'Centro',
    address: 'Via Roma 1',
    taxCode: '12345678901',
    legalRepresentative: 'Mario Rossi',
  );

  RegisterEntry e(
    int n,
    String last,
    String adm, {
    String? ces,
    CessationCause? cause,
  }) => RegisterEntry(
    progressiveNumber: n,
    memberId: n,
    firstName: 'A$n',
    lastName: last,
    admissionDate: adm,
    cessationDate: ces,
    cessationCause: cause,
  );

  final entries = [
    e(
      1,
      'Antica',
      '2019-03-01',
      ces: '2021-06-30',
      cause: CessationCause.death,
    ),
    e(2, 'Corrente', '2020-01-10'),
    e(
      3,
      'Cessata',
      '2025-05-05',
      ces: '2026-02-02',
      cause: CessationCause.resignation,
    ),
    e(4, 'Nuova', '2026-09-01'),
    e(5, 'Futura', '2027-01-01'),
  ];

  test('anno: include chi era iscritto in almeno un giorno dell\'anno', () {
    final r = service.entriesForYear(entries, 2026);
    expect(r.map((x) => x.lastName), ['Corrente', 'Cessata', 'Nuova']);
  });

  test('i progressivi del libro restano quelli originali', () {
    final r = service.entriesForYear(entries, 2026);
    expect(r.map((x) => x.progressiveNumber), [2, 3, 4]);
  });

  test(
    'cessazione il 1 gennaio è ancora dell\'anno; il 31/12 precedente no',
    () {
      final r = service.entriesForYear([
        e(1, 'A', '2020-01-01', ces: '2026-01-01', cause: CessationCause.other),
        e(2, 'B', '2020-01-01', ces: '2025-12-31', cause: CessationCause.other),
      ], 2026);
      expect(r.map((x) => x.lastName), ['A']);
    },
  );

  test('intestazione ente e righe', () {
    final lines = service.lines(
      entries: entries,
      year: 2026,
      profile: profile,
      labels: labels,
      generated: DateTime(2026, 10, 13),
    );
    expect(lines[0], 'Ente: Centro');
    expect(lines, contains('Indirizzo: Via Roma 1'));
    expect(lines, contains('CF: 12345678901'));
    expect(lines, contains('Rappresentante: Mario Rossi'));
    expect(lines, contains('Anno: 2026'));
    expect(lines, contains('Generato il: 2026-10-13'));
    expect(
      lines,
      contains(
        'N. 3 — Cessata A3 — ammesso 2025-05-05 — cessato 2026-02-02 (dimissioni)',
      ),
    );
    expect(lines, contains('N. 4 — Nuova A4 — ammesso 2026-09-01'));
  });

  test('campi ente vuoti omessi; anno senza soci', () {
    final lines = service.lines(
      entries: const [],
      year: 2026,
      profile: const EntityProfile(name: 'Centro'),
      labels: labels,
      generated: DateTime(2026, 10, 13),
    );
    expect(lines.any((l) => l.startsWith('Indirizzo')), isFalse);
    expect(lines.last, 'Nessuna annotazione');
  });

  test(
    'anni selezionabili: dal primo anno di ammissione a quello corrente',
    () {
      expect(service.availableYears(entries, DateTime(2026, 10, 13)), [
        2026,
        2025,
        2024,
        2023,
        2022,
        2021,
        2020,
        2019,
      ]);
      expect(service.availableYears(const [], DateTime(2026, 10, 13)), [2026]);
    },
  );
}
