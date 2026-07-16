import 'package:anteas_rubrica/data/member_repository.dart';
import 'package:anteas_rubrica/main.dart';
import 'package:anteas_rubrica/models/member.dart';
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
    await tester.pumpWidget(AnteasApp(repository: _FakeMemberRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Rubrica tesserati'), findsOneWidget);
    expect(find.text('La rubrica è vuota'), findsOneWidget);
    expect(find.text('Importa rubrica / Excel'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Condividi rubrica'), findsOneWidget);
  });
}
