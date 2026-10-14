import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/card_validity.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Repo extends MemberRepository {
  _Repo({this.history = const []});
  List<RegisterEvent> history;
  CardValidity validity = CardValidity.calendarYear;
  Member? saved;
  String? admittedWith;

  @override
  Future<List<RegisterEvent>> registerHistory(int id) async => history;
  @override
  Future<CardValidity> loadCardValidity() async => validity;
  @override
  Future<void> saveCardValidity(CardValidity value) async => validity = value;
  @override
  Future<Member> save(Member member) async => saved = member;
  @override
  Future<bool> admitMember(int memberId, {required String fallbackDate}) async {
    admittedWith = fallbackDate;
    return true;
  }
}

const _admission = RegisterEvent(
  id: 1,
  memberId: 1,
  type: RegisterEventType.admission,
  eventDate: '2020-01-01',
  firstName: 'A',
  lastName: 'B',
  recordedAt: '2020-01-01T00:00:00Z',
);

Future<void> _open(WidgetTester tester, Member m, _Repo repo) async {
  tester.view.physicalSize = const Size(600, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('it'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MemberDetailScreen(member: m, repository: repo),
    ),
  );
  await tester.pumpAndSettle();
}

String _fmt(DateTime d) => DateFormat.yMd('it').format(d);

void main() {
  const bare = Member(
    id: 1,
    firstName: 'Ezio',
    lastName: 'Agostini',
    phone: '333',
    memberNumber: '',
    notes: '',
  );

  testWidgets('socio senza tessera e fuori dal libro: due scorciatoie', (
    tester,
  ) async {
    await _open(tester, bare, _Repo());
    expect(find.text('Da completare'), findsOneWidget);
    expect(find.text('Aggiungi tessera'), findsOneWidget);
    expect(find.text('Registra nel libro'), findsOneWidget);
  });

  testWidgets('socio completo e nel libro: nessun riquadro', (tester) async {
    final ok = Member(
      id: 1,
      firstName: 'A',
      lastName: 'B',
      phone: '1',
      memberNumber: '7',
      expiryDate: DateTime(2999),
      notes: '',
    );
    await _open(tester, ok, _Repo(history: const [_admission]));
    expect(find.text('Da completare'), findsNothing);
  });

  testWidgets('socio scaduto: Rinnova tessera', (tester) async {
    final old = Member(
      id: 1,
      firstName: 'A',
      lastName: 'B',
      phone: '1',
      memberNumber: '7',
      expiryDate: DateTime(2020),
      notes: '',
    );
    await _open(tester, old, _Repo(history: const [_admission]));
    expect(find.text('Rinnova tessera'), findsOneWidget);
    expect(find.text('Aggiungi tessera'), findsNothing);
  });

  testWidgets('Aggiungi tessera: scadenza proposta a fine anno e salvataggio', (
    tester,
  ) async {
    final repo = _Repo(history: const [_admission]);
    await _open(tester, bare, repo);
    await tester.tap(find.text('Aggiungi tessera'));
    await tester.pumpAndSettle();
    final first = CardValidity.calendarYear.suggestions(DateTime.now()).first;
    expect(find.text('Fino al ${_fmt(first)}'), findsOneWidget);
    expect(
      find.text('Le tessere scadono: ogni anno il 31 dicembre'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(repo.saved?.memberNumber, '123');
    expect(repo.saved?.expiryDate, first);
    expect(find.text('Tessera aggiornata'), findsOneWidget);
  });

  testWidgets('la regola di scadenza è configurabile e viene ricordata', (
    tester,
  ) async {
    final repo = _Repo(history: const [_admission]);
    await _open(tester, bare, repo);
    await tester.tap(find.text('Aggiungi tessera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dopo 12 mesi dal rinnovo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva').last);
    await tester.pumpAndSettle();
    expect(repo.validity, const CardValidity.twelveMonths());
    final next = const CardValidity.twelveMonths()
        .suggestions(DateTime.now())
        .first;
    expect(find.text('Fino al ${_fmt(next)}'), findsOneWidget);
    expect(
      find.text('Le tessere scadono: 12 mesi dopo il rinnovo'),
      findsOneWidget,
    );
  });

  testWidgets('Registra nel libro: conferma e data di riserva', (tester) async {
    final repo = _Repo();
    await _open(
      tester,
      const Member(
        id: 1,
        firstName: 'Ezio',
        lastName: 'Agostini',
        phone: '333',
        memberNumber: '5',
        notes: '',
      ),
      repo,
    );
    await tester.tap(find.text('Registra nel libro'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Verrà annotata nel libro soci l\'ammissione di Ezio Agostini.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();
    expect(repo.admittedWith, RegisterRepository.todayIso());
    expect(find.text('Ammissione registrata'), findsOneWidget);
  });

  group('admitMember (database)', () {
    late Database db;
    late MemberRepository repo;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        '''CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL, last_name TEXT NOT NULL, name_key TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '', phone_key TEXT NOT NULL DEFAULT '',
        secondary_phone TEXT NOT NULL DEFAULT '', secondary_phone_key TEXT NOT NULL DEFAULT '',
        member_number TEXT NOT NULL DEFAULT '', expiry_date TEXT, birth_date TEXT,
        notes TEXT NOT NULL DEFAULT '')''',
      );
      await db.execute(
        'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      repo = MemberRepository(database: db);
      await repo.membersNotInBook();
    });
    tearDown(() => db.close());

    test('scrive una sola ammissione, con data scheda o di riserva', () async {
      await db.insert('members', {
        'first_name': 'Con',
        'last_name': 'Data',
        'join_date': '2019-03-04',
      });
      await db.insert('members', {'first_name': 'Senza', 'last_name': 'Data'});
      expect(await repo.admitMember(1, fallbackDate: '2026-01-15'), isTrue);
      expect(await repo.admitMember(2, fallbackDate: '2026-01-15'), isTrue);
      expect(await repo.admitMember(1, fallbackDate: '2026-02-01'), isFalse);
      expect(await repo.admitMember(99, fallbackDate: '2026-02-01'), isFalse);
      final e = await repo.registerEntries();
      expect(e.map((x) => x.admissionDate).toSet(), {
        '2019-03-04',
        '2026-01-15',
      });
    });

    test('la regola delle tessere si salva e si rilegge', () async {
      expect(await repo.loadCardValidity(), CardValidity.calendarYear);
      await repo.saveCardValidity(const CardValidity.fixed(30, 9));
      expect(await repo.loadCardValidity(), const CardValidity.fixed(30, 9));
    });
  });
}
