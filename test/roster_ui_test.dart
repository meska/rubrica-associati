import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';

class _Repo extends MemberRepository {
  @override
  Future<List<Member>> search(String query) async => const [
    Member(
      firstName: 'Anna',
      lastName: 'Verdi',
      phone: '3331234567',
      memberNumber: '1',
      notes: 'segreto',
      taxCode: 'RSSMRA80A01H501U',
    ),
  ];
  @override
  Future<String> loadOrganizationName() async => 'Centro';
}

void main() {
  for (final e in {
    'it': 'Elenco soci',
    'en': 'Member list',
    'fr': 'Liste des membres',
    'de': 'Mitgliederliste',
  }.entries) {
    testWidgets('roster shows name and quality only (${e.key})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RubricaAssociatiApp(locale: Locale(e.key), repository: _Repo()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(e.value));
      await tester.pumpAndSettle();
      expect(find.text('Verdi Anna'), findsOneWidget);
      expect(find.textContaining('3331234567'), findsNothing);
      expect(find.textContaining('RSSMRA'), findsNothing);
      expect(find.textContaining('segreto'), findsNothing);
    });
  }
}
