import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late MemberRepository repository;

  setUp(() async {
    sqfliteFfiInit();
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
    await database.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    repository = MemberRepository(database: database);
  });

  tearDown(() => database.close());

  test('salva, cerca e aggiorna un duplicato importato', () async {
    await repository.save(
      const Member(
        firstName: 'Mario',
        lastName: 'Rossi',
        phone: '333 1234567',
        secondaryPhone: '049 7654321',
        memberNumber: 'A001',
        notes: 'Nota originale',
      ),
    );

    expect(await repository.search('rossi'), hasLength(1));
    expect(await repository.search('A001'), hasLength(1));
    expect(await repository.search('333123'), hasLength(1));
    expect(await repository.search('049765'), hasLength(1));

    final result = await repository.importMembers([
      Member(
        firstName: 'Mario',
        lastName: 'Rossi',
        phone: '',
        memberNumber: 'A001',
        expiryDate: DateTime(2027, 12, 31),
        notes: '',
      ),
    ]);

    expect(result.inserted, 0);
    expect(result.updated, 1);
    final members = await repository.search('Mario');
    expect(members, hasLength(1));
    expect(members.single.phone, '333 1234567');
    expect(members.single.secondaryPhone, '049 7654321');
    expect(members.single.notes, 'Nota originale');
    expect(members.single.expiryDate, DateTime(2027, 12, 31));
  });

  test('salva e rilegge il nome personalizzato del centro', () async {
    expect(
      await repository.loadOrganizationName(),
      MemberRepository.defaultOrganizationName,
    );

    await repository.saveOrganizationName('  Circolo Serenità  ');

    expect(await repository.loadOrganizationName(), 'Circolo Serenità');
    expect(() => repository.saveOrganizationName('   '), throwsArgumentError);
  });

  test('cerca nomi accentati, composti e in qualsiasi ordine', () async {
    await repository.save(
      const Member(
        firstName: 'Niccolò Maria',
        lastName: 'Dall’Ò',
        phone: '',
        memberNumber: '',
        notes: '',
      ),
    );

    expect(await repository.search('niccolo'), hasLength(1));
    expect(await repository.search('dall o'), hasLength(1));
    expect(await repository.search('ò niccolò'), hasLength(1));
  });

  test('non fonde associati diversi che condividono il telefono', () async {
    final result = await repository.importMembers(const [
      Member(
        firstName: 'Anna',
        lastName: 'Bianchi',
        phone: '333 1112222',
        memberNumber: '',
        notes: '',
      ),
      Member(
        firstName: 'Paolo',
        lastName: 'Verdi',
        phone: '333 1112222',
        memberNumber: '',
        notes: '',
      ),
    ]);

    expect(result.inserted, 2);
    expect(await repository.search('Anna'), hasLength(1));
    expect(await repository.search('Paolo'), hasLength(1));
  });
}
