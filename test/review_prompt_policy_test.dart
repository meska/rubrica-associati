import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/services/review_prompt_policy.dart';

void main() {
  const policy = ReviewPromptPolicy();
  final now = DateTime(2026, 11, 1);
  final ready = ReviewPromptState(
    firstLaunch: now.subtract(const Duration(days: 10)),
    successfulActions: 3,
  );

  test('chiede dopo un momento positivo con tutte le condizioni', () {
    expect(policy.shouldPrompt(ready, now), isTrue);
  });

  test('mai al primo avvio o troppo presto', () {
    expect(policy.shouldPrompt(const ReviewPromptState(), now), isFalse);
    expect(
      policy.shouldPrompt(
        ready.copyWith(firstLaunch: now.subtract(const Duration(days: 1))),
        now,
      ),
      isFalse,
    );
  });

  test('mai dopo un errore', () {
    expect(policy.shouldPrompt(ready, now, afterError: true), isFalse);
  });

  test('servono almeno due azioni riuscite', () {
    expect(
      policy.shouldPrompt(ready.copyWith(successfulActions: 1), now),
      isFalse,
    );
  });

  test('al massimo una volta ogni 120 giorni', () {
    final recent = ready.copyWith(
      lastPrompt: now.subtract(const Duration(days: 119)),
    );
    final old = ready.copyWith(
      lastPrompt: now.subtract(const Duration(days: 120)),
    );
    expect(policy.shouldPrompt(recent, now), isFalse);
    expect(policy.shouldPrompt(old, now), isTrue);
  });

  test('rispetta la disattivazione', () {
    expect(policy.shouldPrompt(ready.copyWith(enabled: false), now), isFalse);
  });
}
