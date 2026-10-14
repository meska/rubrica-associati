import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/models/member_filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Member _m(int id, {DateTime? expiry}) => Member(
  id: id,
  firstName: 'N$id',
  lastName: 'C$id',
  phone: '',
  memberNumber: '',
  expiryDate: expiry,
  notes: '',
);

class _Repo extends MemberRepository {
  _Repo(this.members, this.missing);
  final List<Member> members;
  Set<int> missing;
  String? admittedWith;
  @override
  Future<List<Member>> search(String query) async => members;
  @override
  Future<String> loadOrganizationName() async => 'Centro';
  @override
  Future<Set<int>> membersNotInBook() async => missing;
  @override
  Future<int> admitAllMissing({required String fallbackDate}) async {
    admittedWith = fallbackDate;
    final n = missing.length;
    missing = {};
    return n;
  }
}

void main() {
  group('filtri', () {
    final past = DateTime(2020);
    final future = DateTime(2999);
    final members = [_m(1, expiry: past), _m(2, expiry: future), _m(3)];
    test('in regola = scadenza valida; senza scadenza a parte', () {
      List<int?> ids(MemberFilter f) =>
          applyMemberFilter(members, f, {3}).map((m) => m.id).toList();
      expect(ids(MemberFilter.all), [1, 2, 3]);
      expect(ids(MemberFilter.inGoodStanding), [2]);
      expect(ids(MemberFilter.expired), [1]);
      expect(ids(MemberFilter.noExpiry), [3]);
      expect(ids(MemberFilter.notInBook), [3]);
    });
  });

  group('aggiornamento massivo', () {
    late Database database;
    late MemberRepository repository;

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
      // Soci "storici": presenti prima del libro, senza annotazioni.
      await repository.membersNotInBook(); // forza migrazioni/colonne
      await database.insert('members', {
        'first_name': 'Con',
        'last_name': 'Data',
        'join_date': '2019-03-04',
      });
      await database.insert('members', {
        'first_name': 'Senza',
        'last_name': 'Data',
      });
    });

    tearDown(() => database.close());

    test(
      'scrive le ammissioni mancanti con data scheda o di riserva',
      () async {
        expect((await repository.membersNotInBook()), hasLength(2));
        final written = await repository.admitAllMissing(
          fallbackDate: '2026-01-15',
        );
        expect(written, 2);
        expect(await repository.membersNotInBook(), isEmpty);
        final entries = await repository.registerEntries();
        final byName = {for (final e in entries) e.lastName: e.admissionDate};
        expect(byName['Data'], isNotNull);
        expect(entries.map((e) => e.admissionDate).toSet(), {
          '2019-03-04',
          '2026-01-15',
        });
      },
    );

    test('è idempotente e non tocca chi è già nel libro', () async {
      expect(await repository.admitAllMissing(fallbackDate: '2026-01-15'), 2);
      expect(await repository.admitAllMissing(fallbackDate: '2026-02-20'), 0);
      expect(await repository.registerEntries(), hasLength(2));
    });

    test('un nuovo socio creato dall\'app non risulta mancante', () async {
      await repository.save(_m(0).copyWith(id: null));
      expect(await repository.membersNotInBook(), hasLength(2));
    });

    test('annulla tutto se una scrittura fallisce', () async {
      await expectLater(
        repository.admitAllMissing(fallbackDate: 'data-sbagliata'),
        throwsA(anything),
      );
      expect(await repository.membersNotInBook(), hasLength(2));
      expect(await RegisterRepository(database).allEvents(), isEmpty);
    });
  });

  testWidgets('filtro "Non nel libro" e aggiornamento massivo', (tester) async {
    final repo = _Repo([_m(1), _m(2), _m(3)], {2, 3});
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RubricaAssociatiApp(locale: const Locale('it'), repository: repo),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tutti (3)'), findsOneWidget);
    // «Non nel libro» sta nel menu dei filtri secondari.
    expect(find.text('Non nel libro (2)'), findsNothing);
    await tester.tap(find.byTooltip('Altri filtri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non nel libro (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Non nel libro (2)'), findsOneWidget); // ora è un chip
    expect(find.text('2 soci non sono ancora nel libro soci'), findsOneWidget);
    await tester.tap(find.text('Registra ammissione'));
    await tester.pumpAndSettle();
    expect(find.text("Registrare l'ammissione di 2 soci?"), findsOneWidget);
    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();
    expect(repo.admittedWith, RegisterRepository.todayIso());
    expect(find.text('2 ammissioni registrate'), findsOneWidget);
    expect(find.text('Non nel libro (0)'), findsOneWidget);
  });

  testWidgets('suggerimenti chiari per chi non ha la scadenza', (tester) async {
    final repo = _Repo([_m(1), _m(2)], {});
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RubricaAssociatiApp(locale: const Locale('it'), repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('In regola (0)'));
    await tester.pumpAndSettle();
    // Non "La rubrica è vuota": la rubrica ha soci, è il filtro a essere vuoto.
    expect(find.text('La rubrica è vuota'), findsNothing);
    expect(find.text('Nessun socio in questo elenco'), findsOneWidget);
    expect(
      find.text(
        '2 soci non hanno la data di scadenza, quindi non compaiono qui.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Mostra'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('inserisci la scadenza della tessera'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
