import 'review_prompt_policy.dart';

/// Chiede davvero la recensione (StoreKit / Play In-App Review).
/// L'implementazione reale arriva col passo R3; nei test si usa un fake.
abstract class ReviewRequester {
  Future<bool> isAvailable();
  Future<void> requestReview();
}

/// Archivio chiave/valore (implementato da MemberRepository su app_settings).
abstract class ReviewSettingsStore {
  Future<String?> loadSetting(String key);
  Future<void> saveSetting(String key, String value);
}

class ReviewService {
  ReviewService({
    required ReviewSettingsStore store,
    required ReviewRequester requester,
    ReviewPromptPolicy policy = const ReviewPromptPolicy(),
    DateTime Function()? clock,
  }) : _store = store,
       _requester = requester,
       _policy = policy,
       _clock = clock ?? DateTime.now;

  static const enabledKey = 'review_enabled';
  static const firstLaunchKey = 'review_first_launch';
  static const lastPromptKey = 'review_last_prompt';
  static const successCountKey = 'review_success_count';

  final ReviewSettingsStore _store;
  final ReviewRequester _requester;
  final ReviewPromptPolicy _policy;
  final DateTime Function() _clock;

  Future<ReviewPromptState> loadState() async {
    final enabled = await _store.loadSetting(enabledKey);
    final count = await _store.loadSetting(successCountKey);
    return ReviewPromptState(
      enabled: enabled != '0',
      firstLaunch: DateTime.tryParse(
        await _store.loadSetting(firstLaunchKey) ?? '',
      ),
      lastPrompt: DateTime.tryParse(
        await _store.loadSetting(lastPromptKey) ?? '',
      ),
      successfulActions: int.tryParse(count ?? '') ?? 0,
    );
  }

  Future<void> registerLaunch() async {
    if (await _store.loadSetting(firstLaunchKey) != null &&
        DateTime.tryParse(await _store.loadSetting(firstLaunchKey) ?? '') !=
            null) {
      return;
    }
    await _store.saveSetting(firstLaunchKey, _clock().toIso8601String());
  }

  Future<void> recordSuccess() async {
    final state = await loadState();
    await _store.saveSetting(successCountKey, '${state.successfulActions + 1}');
  }

  Future<void> setEnabled(bool value) =>
      _store.saveSetting(enabledKey, value ? '1' : '0');

  /// Chiede la recensione se la policy lo consente. Non lancia mai.
  Future<bool> maybeRequest({bool afterError = false}) async {
    try {
      final now = _clock();
      final state = await loadState();
      if (!_policy.shouldPrompt(state, now, afterError: afterError)) {
        return false;
      }
      if (!await _requester.isAvailable()) return false;
      await _requester.requestReview();
      await _store.saveSetting(lastPromptKey, now.toIso8601String());
      return true;
    } catch (_) {
      return false;
    }
  }
}
