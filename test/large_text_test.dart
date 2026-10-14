import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/card_validity.dart';
import 'package:rubrica_associati/models/member.dart';

/// Regressione: con testo ingrandito (utenti anziani) nessuna schermata
/// principale deve rompersi (overflow, errori di layout).
class _Fake extends MemberRepository {
  final list = [
    Member(
      id: 1,
      firstName: 'Maria Giuseppina Antonietta',
      lastName: 'Della Torre di Montefalcone',
      phone: '3331234567',
      memberNumber: '100',
      expiryDate: DateTime(2020),
      notes: '',
    ),
    const Member(
      id: 2,
      firstName: 'Mario',
      lastName: 'Rossi',
      phone: '3331234567',
      memberNumber: '101',
      notes: '',
    ),
  ];
  @override
  Future<List<Member>> search(String q) async => list;
  @override
  Future<String> loadOrganizationName() async =>
      'Centro pensionati di Montefalcone';
  @override
  Future<Set<int>> membersNotInBook() async => {1};
  @override
  Future<List<RegisterEvent>> registerHistory(int id) async => const [];
  @override
  Future<CardValidity> loadCardValidity() async => CardValidity.calendarYear;
}

void main() {
  for (final scale in [2.0, 3.0]) {
    for (final lang in ['it', 'en', 'fr', 'de']) {
      testWidgets('testo x$scale ($lang): lista, scheda, modulo, menu', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 1800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          RubricaAssociatiApp(locale: Locale(lang), repository: _Fake()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'lista');

        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'scheda socio scaduto');

        // Scorciatoie «Da completare» (rinnova tessera, registra nel libro) e
        // finestra della regola di scadenza, anche con testo molto grande.
        await tester.ensureVisible(find.byIcon(Icons.autorenew));
        await tester.tap(find.byIcon(Icons.autorenew));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'finestra tessera');
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byIcon(Icons.menu_book_outlined));
        await tester.tap(find.byIcon(Icons.menu_book_outlined));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'finestra libro');
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'modulo');
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'menu principale');
      });
    }
  }

  testWidgets('testo x3: aggiornamento massivo del libro', (tester) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RubricaAssociatiApp(locale: const Locale('it'), repository: _Fake()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Altri filtri'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Non nel libro'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'filtro non nel libro');
    await tester.ensureVisible(find.byIcon(Icons.menu_book_outlined));
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'dialogo massivo');
  });
}
