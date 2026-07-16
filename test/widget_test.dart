import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMemberRepository extends MemberRepository {
  @override
  Future<List<Member>> search(String query) async => const [];
}

void main() {
  testWidgets('mostra lo stato vuoto e il comando di importazione', (
    tester,
  ) async {
    await tester.pumpWidget(
      RubricaAssociatiApp(repository: _FakeMemberRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rubrica Associati'), findsOneWidget);
    expect(find.text('La rubrica è vuota'), findsOneWidget);
    expect(find.text('Importa rubrica / Excel'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Condividi rubrica'), findsOneWidget);
  });
}
