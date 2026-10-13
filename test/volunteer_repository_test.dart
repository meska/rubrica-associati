import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late VolunteerRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await VolunteerRepository.createSchema(db);
    repo = VolunteerRepository(db);
  });

  tearDown(() => db.close());

  Future<int> enroll(
    String last,
    String start, {
    bool occasional = false,
    String tax = 'RSSMRA80A01H501U',
  }) => repo.enroll(
    firstName: 'Mario',
    lastName: last,
    startDate: start,
    taxCode: tax,
    residence: 'Via Roma 1, Milano',
    occasional: occasional,
  );

  test('progressivo per data di inizio, separato per occasionali', () async {
    await enroll('Bianchi', '2024-05-10');
    await enroll('Verdi', '2023-01-02');
    await enroll('Neri', '2022-01-01', occasional: true);
    final e = await repo.entries();
    expect(e.map((x) => x.lastName), ['Neri', 'Verdi', 'Bianchi']);
    expect(e.where((x) => !x.occasional).map((x) => x.progressiveNumber), [
      1,
      2,
    ]);
    expect(e.first.occasional, isTrue);
    expect(e.first.progressiveNumber, 1);
  });

  test(
    'campi DM: CF oppure generalità+nascita; residenza obbligatoria',
    () async {
      await expectLater(
        repo.enroll(
          firstName: 'A',
          lastName: 'B',
          startDate: '2024-01-01',
          residence: 'Via X',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.enroll(
          firstName: 'A',
          lastName: 'B',
          startDate: '2024-01-01',
          taxCode: 'RSSMRA80A01H501U',
        ),
        throwsArgumentError,
      );
      await repo.enroll(
        firstName: 'A',
        lastName: 'B',
        startDate: '2024-01-01',
        birthDate: '1980-01-01',
        birthPlace: 'Roma',
        residence: 'Via X',
      );
      await expectLater(
        repo.enroll(
          firstName: 'A',
          lastName: 'B',
          startDate: '01/01/2024',
          taxCode: 'X',
          residence: 'Via X',
        ),
        throwsArgumentError,
      );
      expect(await repo.entries(), hasLength(1));
    },
  );

  test(
    'cessazione: data fine, riga conservata, no doppia cessazione',
    () async {
      final id = await enroll('Bianchi', '2024-05-10');
      await expectLater(
        repo.cease(volunteerId: id, endDate: '2024-01-01'),
        throwsArgumentError,
      );
      await repo.cease(volunteerId: id, endDate: '2025-02-03');
      final e = (await repo.entries()).single;
      expect(e.endDate, '2025-02-03');
      expect(e.isActive, isFalse);
      await expectLater(
        repo.cease(volunteerId: id, endDate: '2025-03-03'),
        throwsStateError,
      );
      expect(await repo.rawEvents(id), hasLength(2));
    },
  );

  test(
    'correzione = nuova riga; originale nello storico; inizio invariato',
    () async {
      final id = await enroll('Bianchi', '2024-05-10');
      await repo.correct(
        volunteerId: id,
        date: '2024-06-01',
        firstName: 'Mario',
        lastName: 'Bianchini',
        taxCode: 'rssmra80a01h501u',
        residence: 'Via Nuova 2',
      );
      final e = (await repo.entries()).single;
      expect(e.lastName, 'Bianchini');
      expect(e.residence, 'Via Nuova 2');
      expect(e.startDate, '2024-05-10');
      expect(e.taxCode, 'RSSMRA80A01H501U');
      final raw = await repo.rawEvents(id);
      expect(raw, hasLength(2));
      expect(raw.first['last_name'], 'Bianchi');
      await expectLater(
        repo.correct(
          volunteerId: 99,
          date: '2024-06-01',
          firstName: 'A',
          lastName: 'B',
          taxCode: 'X',
          residence: 'Via',
        ),
        throwsStateError,
      );
    },
  );

  test('append-only: UPDATE e DELETE bloccati', () async {
    await enroll('Bianchi', '2024-05-10');
    await expectLater(
      db.update('volunteer_events', {'last_name': 'X'}),
      throwsA(anything),
    );
    await expectLater(db.delete('volunteer_events'), throwsA(anything));
  });

  test('reiscrizione dopo cessazione = nuovo volontario/riga', () async {
    final a = await enroll('Bianchi', '2022-01-01');
    await repo.cease(volunteerId: a, endDate: '2023-01-01');
    final b = await enroll('Bianchi', '2024-01-01');
    expect(b, isNot(a));
    final e = await repo.entries();
    expect(e.map((x) => x.isActive), [false, true]);
    expect(e.map((x) => x.progressiveNumber), [1, 2]);
  });

  test(
    'upgrade da v7 a v8: dati preservati, tabella nuova append-only',
    () async {
      final dir = await Directory.systemTemp.createTemp('rubrica_v7');
      final file = path.join(dir.path, 'old.db');
      final members = MemberRepository(databasePath: file);
      await members.loadSetting('x'); // crea direttamente l'ultima versione
      await members.close();
      final raw = await databaseFactoryFfi.openDatabase(file);
      await raw.execute('DROP TRIGGER volunteer_events_no_delete');
      await raw.execute('DROP TABLE volunteer_events');
      await raw.insert('members', {
        'first_name': 'Mario',
        'last_name': 'Rossi',
      });
      await raw.setVersion(7);
      await raw.close();

      final again = MemberRepository(databasePath: file);
      final v = await again.volunteerRepository();
      await v.enroll(
        firstName: 'A',
        lastName: 'B',
        startDate: '2024-01-01',
        taxCode: 'X',
        residence: 'Via',
      );
      await again.close();

      final upgraded = await databaseFactoryFfi.openDatabase(file);
      expect(await upgraded.getVersion(), 8);
      expect(await upgraded.query('members'), hasLength(1));
      expect(await upgraded.query('volunteer_events'), hasLength(1));
      await expectLater(upgraded.delete('volunteer_events'), throwsA(anything));
      await upgraded.close();
      await dir.delete(recursive: true);
    },
  );
}
