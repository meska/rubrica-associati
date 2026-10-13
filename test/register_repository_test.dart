import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() {
  late Database db;
  late RegisterRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await RegisterRepository.createSchema(db);
    repo = RegisterRepository(db);
  });

  tearDown(() => db.close());

  test(
    'numero progressivo per data di ammissione, non per inserimento',
    () async {
      await repo.recordAdmission(
        memberId: 1,
        firstName: 'Anna',
        lastName: 'Bianchi',
        date: '2024-05-10',
      );
      await repo.recordAdmission(
        memberId: 2,
        firstName: 'Luca',
        lastName: 'Verdi',
        date: '2023-01-02',
      );
      final entries = await repo.entries();
      expect(entries.map((e) => e.lastName), ['Verdi', 'Bianchi']);
      expect(entries.map((e) => e.progressiveNumber), [1, 2]);
    },
  );

  test('cessazione con causa resta sulla riga del socio', () async {
    await repo.recordAdmission(
      memberId: 1,
      firstName: 'Anna',
      lastName: 'Bianchi',
      date: '2020-01-01',
    );
    await repo.recordCessation(
      memberId: 1,
      date: '2025-03-04',
      cause: CessationCause.resignation,
    );
    final e = (await repo.entries()).single;
    expect(e.cessationDate, '2025-03-04');
    expect(e.cessationCause, CessationCause.resignation);
    expect(e.firstName, 'Anna');
  });

  test('riammissione genera una nuova riga con propria cessazione', () async {
    await repo.recordAdmission(
      memberId: 1,
      firstName: 'A',
      lastName: 'B',
      date: '2020-01-01',
    );
    await repo.recordCessation(
      memberId: 1,
      date: '2021-01-01',
      cause: CessationCause.exclusion,
    );
    await repo.recordAdmission(
      memberId: 1,
      firstName: 'A',
      lastName: 'B',
      date: '2022-01-01',
    );
    final entries = await repo.entries();
    expect(entries, hasLength(2));
    expect(entries[0].cessationCause, CessationCause.exclusion);
    expect(entries[1].cessationDate, isNull);
  });

  test(
    'correzione è una nuova annotazione; l\'originale resta intatto',
    () async {
      final adm = await repo.recordAdmission(
        memberId: 1,
        firstName: 'Anna',
        lastName: 'Bianchi',
        date: '2024-05-10',
      );
      await repo.recordCorrection(
        eventId: adm.id,
        date: '2024-05-12',
        lastName: 'Bianco',
        note: 'refuso',
      );
      final raw = await repo.eventsForMember(1);
      expect(raw, hasLength(2));
      expect(raw.first.eventDate, '2024-05-10');
      expect(raw.first.lastName, 'Bianchi');
      expect(raw.last.type, RegisterEventType.correction);
      expect(raw.last.correctsEventId, adm.id);
      final e = (await repo.entries()).single;
      expect(e.admissionDate, '2024-05-12');
      expect(e.lastName, 'Bianco');
      expect(e.firstName, 'Anna');
    },
  );

  test('correzione che sposta la data cambia il progressivo', () async {
    final a = await repo.recordAdmission(
      memberId: 1,
      firstName: 'A',
      lastName: 'Uno',
      date: '2020-01-01',
    );
    await repo.recordAdmission(
      memberId: 2,
      firstName: 'B',
      lastName: 'Due',
      date: '2021-01-01',
    );
    await repo.recordCorrection(eventId: a.id, date: '2022-01-01');
    final entries = await repo.entries();
    expect(entries.map((e) => e.lastName), ['Due', 'Uno']);
  });

  test('append-only: update e delete rifiutati dal database', () async {
    final adm = await repo.recordAdmission(
      memberId: 1,
      firstName: 'A',
      lastName: 'B',
      date: '2020-01-01',
    );
    expect(
      () => db.update(
        'register_events',
        {'note': 'x'},
        where: 'id = ?',
        whereArgs: [adm.id],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      () => db.delete('register_events'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.allEvents(), hasLength(1));
  });

  test(
    'date non valide e correzioni su id inesistenti sono rifiutate',
    () async {
      expect(
        () => repo.recordAdmission(
          memberId: 1,
          firstName: 'A',
          lastName: 'B',
          date: '10/05/2024',
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.recordCorrection(eventId: 99, date: '2020-01-01'),
        throwsArgumentError,
      );
    },
  );

  test(
    'upgrade da v4 a v5: dati preservati, registro vuoto e append-only',
    () async {
      final dir = await Directory.systemTemp.createTemp('rubrica_v4');
      final file = path.join(dir.path, 'old.db');
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT NOT NULL, last_name TEXT NOT NULL,
            name_key TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '', phone_key TEXT NOT NULL DEFAULT '',
            secondary_phone TEXT NOT NULL DEFAULT '',
            secondary_phone_key TEXT NOT NULL DEFAULT '',
            member_number TEXT NOT NULL DEFAULT '',
            expiry_date TEXT, birth_date TEXT,
            notes TEXT NOT NULL DEFAULT '')''');
            await d.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await d.insert('members', {
              'first_name': 'Mario',
              'last_name': 'Rossi',
            });
          },
        ),
      );
      await old.close();

      final members = MemberRepository(databasePath: file);
      await members.loadSetting('x'); // apre il DB: scatta onUpgrade 4 → 5
      await members.close();

      final upgraded = await databaseFactoryFfi.openDatabase(file);
      expect(await upgraded.getVersion(), 7);
      expect(await upgraded.query('members'), hasLength(1));
      final r = RegisterRepository(upgraded);
      expect(await r.allEvents(), isEmpty);
      await r.recordAdmission(
        memberId: 1,
        firstName: 'Mario',
        lastName: 'Rossi',
        date: '2020-01-01',
      );
      expect(
        () => upgraded.delete('register_events'),
        throwsA(isA<DatabaseException>()),
      );
      await upgraded.close();
      await dir.delete(recursive: true);
    },
  );
}
