import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/services/review_service.dart';

class _Store implements ReviewSettingsStore {
  final values = <String, String>{};
  @override
  Future<String?> loadSetting(String key) async => values[key];
  @override
  Future<void> saveSetting(String key, String value) async =>
      values[key] = value;
}

class _FakeRepository extends MemberRepository {
  @override
  Future<List<Member>> search(String query) async => const [];
  @override
  Future<String> loadOrganizationName() async => 'Centro';
}

class _Requester implements ReviewRequester {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> requestReview() async {}
}

void main() {
  for (final entry in {
    'it': 'Richiesta di recensione',
    'en': 'Ask for a review',
    'fr': "Demande d'avis",
    'de': 'Bewertungsanfrage',
  }.entries) {
    testWidgets('review switch toggles and persists (${entry.key})', (
      tester,
    ) async {
      final store = _Store();
      final service = ReviewService(store: store, requester: _Requester());

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RubricaAssociatiApp(
          locale: Locale(entry.key),
          repository: _FakeRepository(),
          reviewService: service,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      await tester.tap(find.text(entry.value));
      await tester.pumpAndSettle();
      expect(store.values[ReviewService.enabledKey], '0');

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.value));
      await tester.pumpAndSettle();
      expect(store.values[ReviewService.enabledKey], '1');
    });
  }
}
