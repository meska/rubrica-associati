import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/card_validity.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';

class _Repo extends MemberRepository {
  final list = [
    for (var i = 1; i <= 4; i++)
      Member(
        id: i,
        firstName: 'Nome$i',
        lastName: 'Cognome$i',
        phone: '333$i',
        memberNumber: '$i',
        expiryDate: DateTime(2999),
        notes: '',
      ),
  ];
  var searches = 0;
  var deleted = <int>[];
  @override
  Future<List<Member>> search(String q) async {
    searches++;
    return list.where((m) => !deleted.contains(m.id)).toList();
  }

  @override
  Future<String> loadOrganizationName() async => 'Centro';
  @override
  Future<Set<int>> membersNotInBook() async => const {};
  @override
  Future<CardValidity> loadCardValidity() async => CardValidity.calendarYear;
  @override
  Future<List<RegisterEvent>> registerHistory(int id) async => const [];
  @override
  Future<void> delete(int id) async => deleted.add(id);
}

Future<void> _pump(WidgetTester tester, Size size, _Repo repo) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RubricaAssociatiApp(locale: const Locale('it'), repository: repo),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'schermo largo: lista e scheda affiancate, senza cambiare pagina',
    (tester) async {
      final repo = _Repo();
      await _pump(tester, const Size(1200, 900), repo);
      expect(find.text('Scegli un associato dall’elenco'), findsOneWidget);
      await tester.tap(find.text('Nome2 Cognome2'));
      await tester.pumpAndSettle();
      // La lista resta visibile e la scheda compare a fianco.
      expect(find.text('Nome1 Cognome1'), findsWidgets);
      expect(find.text('Chiama 3332'), findsOneWidget);
      expect(find.text('Scegli un associato dall’elenco'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
    },
  );

  testWidgets('schermo largo: eliminare dalla scheda svuota il pannello', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, const Size(1200, 900), repo);
    await tester.tap(find.text('Nome1 Cognome1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MemberDetailScreen),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina').last);
    await tester.pumpAndSettle();
    expect(repo.deleted, [1]);
    expect(find.text('Scegli un associato dall’elenco'), findsOneWidget);
    expect(find.text('Nome1 Cognome1'), findsNothing);
  });

  testWidgets('schermo stretto: la scheda si apre come pagina', (tester) async {
    final repo = _Repo();
    await _pump(tester, const Size(500, 900), repo);
    expect(find.text('Scegli un associato dall’elenco'), findsNothing);
    await tester.tap(find.text('Nome2 Cognome2'));
    await tester.pumpAndSettle();
    expect(find.text('Chiama 3332'), findsOneWidget);
    expect(find.text('Nome1 Cognome1'), findsNothing); // lista coperta
  });

  testWidgets('schermo largo con testo x2: nessun overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = _Repo();
    await _pump(tester, const Size(1024, 1366), repo);
    await tester.tap(find.text('Nome3 Cognome3'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
