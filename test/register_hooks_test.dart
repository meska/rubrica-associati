import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Member _m(String first, String last, {String number = '', String phone = ''}) =>
    Member(
      firstName: first,
      lastName: last,
      phone: phone,
      memberNumber: number,
      notes: '',
    );

void main() {
  late Database database;
  late MemberRepository repository;
  late RegisterRepository register;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        name_key TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        phone_key TEXT NOT NULL DEFAULT '',
        secondary_phone TEXT NOT NULL DEFAULT '',
        secondary_phone_key TEXT NOT NULL DEFAULT '',
        member_number TEXT NOT NULL DEFAULT '',
        expiry_date TEXT,
        birth_date TEXT,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await database.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    repository = MemberRepository(database: database);
    register = RegisterRepository(database);
  });

  tearDown(() => database.close());

  test('la creazione di un socio registra l\'ammissione', () async {
    final saved = await repository.save(_m('Mario', 'Rossi'));
    final history = await repository.registerHistory(saved.id!);
    expect(history, hasLength(1));
    expect(history.single.type, RegisterEventType.admission);
    expect(history.single.lastName, 'Rossi');
    expect(history.single.eventDate, RegisterRepository.todayIso());
  });

  test(
    'la modifica del nome aggiunge una correzione, senza toccare l\'ammissione',
    () async {
      final saved = await repository.save(_m('Mario', 'Rosi'));
      await repository.save(
        Member(
          id: saved.id,
          firstName: 'Mario',
          lastName: 'Rossi',
          phone: '',
          memberNumber: '',
          notes: 'x',
        ),
      );
      final history = await repository.registerHistory(saved.id!);
      expect(history.map((e) => e.type), [
        RegisterEventType.admission,
        RegisterEventType.correction,
      ]);
      expect(history.first.lastName, 'Rosi');
      expect((await register.entries()).single.lastName, 'Rossi');
    },
  );

  test('una modifica senza cambio di nome non aggiunge annotazioni', () async {
    final saved = await repository.save(_m('Mario', 'Rossi'));
    await repository.save(
      Member(
        id: saved.id,
        firstName: 'Mario',
        lastName: 'Rossi',
        phone: '333',
        memberNumber: '',
        notes: '',
      ),
    );
    expect(await repository.registerHistory(saved.id!), hasLength(1));
  });

  test('la cancellazione annota la cessazione e conserva lo storico', () async {
    final saved = await repository.save(_m('Mario', 'Rossi'));
    await repository.delete(saved.id!);
    expect(await repository.search(''), isEmpty);
    final history = await repository.registerHistory(saved.id!);
    expect(history.map((e) => e.type), [
      RegisterEventType.admission,
      RegisterEventType.cessation,
    ]);
    final entry = (await register.entries()).single;
    expect(entry.cessationDate, RegisterRepository.todayIso());
    expect(entry.cessationCause, CessationCause.other);
  });

  test(
    'cancellare un socio senza ammissione (precedente al libro) non fallisce',
    () async {
      final id = await database.insert('members', {
        'first_name': 'Anna',
        'last_name': 'Bianchi',
      });
      await repository.delete(id);
      expect(await repository.search(''), isEmpty);
      expect(await repository.registerHistory(id), isEmpty);
    },
  );

  test(
    'l\'import registra ammissioni per i nuovi e correzioni per i duplicati',
    () async {
      await repository.save(_m('mario', 'rossi', number: 'A1'));
      final result = await repository.importMembers([
        _m('Mario', 'Rossi', number: 'A1'),
        _m('Luisa', 'Verdi', number: 'B2'),
      ]);
      expect(result.inserted, 1);
      expect(result.updated, 1);
      final all = await register.allEvents();
      expect(
        all.where((e) => e.type == RegisterEventType.admission),
        hasLength(2),
      );
      expect(
        all.where((e) => e.type == RegisterEventType.correction),
        hasLength(1),
      );
    },
  );

  test(
    'il trigger append-only impedisce di cancellare le annotazioni',
    () async {
      final saved = await repository.save(_m('Mario', 'Rossi'));
      await expectLater(
        database.delete(
          'register_events',
          where: 'member_id = ?',
          whereArgs: [saved.id],
        ),
        throwsA(anything),
      );
    },
  );
}
