import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/closure_repository.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';

class _Repo extends MemberRepository {
  @override
  Future<List<Member>> search(String query) async => const [];
  @override
  Future<ClosureRepository> closureRepository() async =>
      throw UnsupportedError('no db in test');
  @override
  Future<String> loadOrganizationName() async => 'Centro';
  @override
  Future<EntityProfile> loadEntityProfile() async =>
      const EntityProfile(name: 'Centro');
  @override
  Future<List<RegisterEntry>> registerEntries() async => [
    RegisterEntry(
      progressiveNumber: 1,
      memberId: 1,
      firstName: 'Anna',
      lastName: 'Verdi',
      admissionDate: '${DateTime.now().year}-01-02',
    ),
  ];
}

void main() {
  for (final e in {
    'it': ('Libro soci', 'Esporta PDF'),
    'en': ('Members register', 'Export PDF'),
    'fr': ('Registre des membres', 'Exporter le PDF'),
    'de': ('Mitgliederbuch', 'PDF exportieren'),
  }.entries) {
    testWidgets('libro soci mostra anno e righe (${e.key})', (tester) async {
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RubricaAssociatiApp(locale: Locale(e.key), repository: _Repo()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(e.value.$1));
      await tester.pumpAndSettle();
      expect(find.text('Verdi Anna'), findsOneWidget);
      expect(find.text(e.value.$2), findsOneWidget);
      expect(find.text('${DateTime.now().year}'), findsWidgets);
    });
  }
}
