import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/volunteer_screen.dart';
import 'package:sqflite/sqflite.dart';

class _NoDb implements DatabaseExecutor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Repository in memoria: stessa interfaccia, senza SQLite.
class _MemVol extends VolunteerRepository {
  _MemVol() : super(_NoDb());
  final rows = <VolunteerEntry>[];
  int corrections = 0;

  @override
  Future<int> enroll({
    required String firstName,
    required String lastName,
    required String startDate,
    String taxCode = '',
    String birthDate = '',
    String birthPlace = '',
    String residence = '',
    bool occasional = false,
    String note = '',
    DateTime? now,
  }) async {
    if (residence.trim().isEmpty) throw ArgumentError('Residenza obbligatoria');
    if (taxCode.trim().isEmpty) {
      throw ArgumentError('Servono il codice fiscale oppure generalità');
    }
    rows.add(
      VolunteerEntry(
        volunteerId: rows.length + 1,
        progressiveNumber:
            rows.where((r) => r.occasional == occasional).length + 1,
        firstName: firstName,
        lastName: lastName,
        taxCode: taxCode,
        birthDate: birthDate,
        birthPlace: birthPlace,
        residence: residence,
        occasional: occasional,
        startDate: startDate,
        endDate: null,
        note: note,
      ),
    );
    return rows.length;
  }

  @override
  Future<List<VolunteerEntry>> entries() async => List.of(rows);
}

class _Repo extends MemberRepository {
  _Repo(this.vol);
  final _MemVol vol;
  @override
  Future<List<Member>> search(String query) async => const [];
  @override
  Future<VolunteerRepository> volunteerRepository() async => vol;
  @override
  Future<String> loadOrganizationName() async => 'Centro';
  @override
  Future<EntityProfile> loadEntityProfile() async =>
      const EntityProfile(name: 'Centro');
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  for (final e in {
    'it': (
      'Registro volontari',
      'Aggiungi volontario',
      'Nessun volontario registrato.',
    ),
    'en': ('Volunteers register', 'Add volunteer', 'No volunteers registered.'),
    'fr': (
      'Registre des bénévoles',
      'Ajouter un bénévole',
      'Aucun bénévole enregistré.',
    ),
    'de': (
      'Freiwilligenregister',
      'Freiwillige/n hinzufügen',
      'Keine Freiwilligen eingetragen.',
    ),
  }.entries) {
    testWidgets('menu apre il registro volontari vuoto (${e.key})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RubricaAssociatiApp(
          locale: Locale(e.key),
          repository: _Repo(_MemVol()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(e.value.$1));
      await _settle(tester);
      expect(find.text(e.value.$3), findsOneWidget);
      expect(find.text(e.value.$2), findsOneWidget);
    });
  }

  testWidgets(
    'iscrizione di un volontario e di un occasionale in sezioni separate',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _MemVol();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('it'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VolunteerScreen(
            repository: repo,
            profile: const EntityProfile(name: 'Centro'),
          ),
        ),
      );
      await _settle(tester);

      Future<void> add(
        String first,
        String last, {
        required bool occasional,
      }) async {
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), first);
        await tester.enterText(fields.at(1), last);
        await tester.enterText(fields.at(2), 'rssmra80a01h501u');
        await tester.enterText(fields.at(4), 'Via Roma 1');
        if (occasional) {
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Salva'));
        await _settle(tester);
      }

      await add('Mario', 'Rossi', occasional: false);
      await add('Anna', 'Verdi', occasional: true);

      expect(find.text('Rossi Mario'), findsOneWidget);
      expect(find.text('Verdi Anna'), findsOneWidget);
      expect(find.text('Volontari'), findsOneWidget);
      expect(find.text('Volontari occasionali'), findsOneWidget);
      expect(repo.rows.first.taxCode, 'rssmra80a01h501u');
    },
  );

  testWidgets('dati mancanti: messaggio di errore localizzato', (tester) async {
    tester.view.physicalSize = const Size(1000, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _MemVol();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VolunteerScreen(
          repository: repo,
          profile: const EntityProfile(name: 'Centro'),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Mario');
    await tester.enterText(fields.at(1), 'Rossi');
    await tester.enterText(fields.at(2), 'RSSMRA80A01H501U');
    await tester.tap(find.text('Salva'));
    await _settle(tester);
    expect(find.text('Residenza o domicilio obbligatori.'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });
}
