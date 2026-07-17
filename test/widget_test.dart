import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMemberRepository extends MemberRepository {
  String organizationName = MemberRepository.defaultOrganizationName;

  @override
  Future<List<Member>> search(String query) async => const [];

  @override
  Future<String> loadOrganizationName() async => organizationName;

  @override
  Future<void> saveOrganizationName(String name) async {
    organizationName = name;
  }
}

void main() {
  testWidgets('mostra lo stato vuoto e il comando di importazione', (
    tester,
  ) async {
    await tester.pumpWidget(
      RubricaAssociatiApp(
        repository: _FakeMemberRepository(),
        locale: const Locale('it'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rubrica Associati'), findsOneWidget);
    expect(find.text('La rubrica è vuota'), findsOneWidget);
    expect(find.text('Importa rubrica / Excel'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Condividi rubrica'), findsOneWidget);
    expect(find.text('Nome del centro'), findsOneWidget);
    expect(find.text('Sostieni il progetto'), findsOneWidget);
  });

  testWidgets('modifica il nome del centro dal menu', (tester) async {
    final repository = _FakeMemberRepository();
    await tester.pumpWidget(
      RubricaAssociatiApp(repository: repository, locale: const Locale('it')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Centro pensionati'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nome del centro'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Centro pensionati'),
      'Circolo Serenità',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Circolo Serenità'), findsOneWidget);
    expect(repository.organizationName, 'Circolo Serenità');
  });

  testWidgets('usa le quattro lingue supportate', (tester) async {
    const expectedTitles = <String, String>{
      'en': 'Member Directory',
      'it': 'Rubrica Associati',
      'fr': 'Répertoire des adhérents',
      'de': 'Mitgliederverzeichnis',
    };

    for (final entry in expectedTitles.entries) {
      await tester.pumpWidget(
        RubricaAssociatiApp(
          repository: _FakeMemberRepository(),
          locale: Locale(entry.key),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('usa l’inglese per una lingua non supportata', (tester) async {
    await tester.pumpWidget(
      RubricaAssociatiApp(
        repository: _FakeMemberRepository(),
        locale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Member Directory'), findsOneWidget);
    expect(find.text('The directory is empty'), findsOneWidget);
  });
}
