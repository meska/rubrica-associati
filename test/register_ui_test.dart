import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';

class _FakeRepository extends MemberRepository {
  EntityProfile? saved;
  @override
  Future<List<Member>> search(String query) async => const [];
  @override
  Future<String> loadOrganizationName() async => 'Centro';
  @override
  Future<EntityProfile> loadEntityProfile() async =>
      const EntityProfile(name: 'Centro', address: 'Via Roma 1');
  @override
  Future<void> saveEntityProfile(EntityProfile profile) async =>
      saved = profile;
}

void main() {
  for (final entry in {
    'it': "Dati dell'ente",
    'en': 'Organization details',
    'fr': "Données de l'association",
    'de': 'Vereinsdaten',
  }.entries) {
    testWidgets('entity details dialog saves (${entry.key})', (tester) async {
      final repo = _FakeRepository();
      await tester.pumpWidget(
        RubricaAssociatiApp(locale: Locale(entry.key), repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.value));
      await tester.pumpAndSettle();
      expect(find.text('Via Roma 1'), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .at(1),
        'abc 123',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.saved?.address, 'Via Roma 1');
      expect(repo.saved?.taxCode, 'abc 123');
    });
  }

  testWidgets('member form returns new register fields', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Member? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await Navigator.of(context).push<Member>(
                  MaterialPageRoute(builder: (_) => const MemberFormScreen()),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Codice fiscale'), findsOneWidget);
    expect(find.text('Luogo di nascita'), findsOneWidget);
    expect(find.text('Data di iscrizione'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Maria');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Codice fiscale'),
      'rss mra',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Luogo di nascita'),
      ' Roma ',
    );
    await tester.tap(find.byTooltip('Salva'));
    await tester.pumpAndSettle();
    expect(result?.taxCode, 'RSSMRA');
    expect(result?.birthPlace, 'Roma');
  });
}
