import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/main.dart';
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
}
