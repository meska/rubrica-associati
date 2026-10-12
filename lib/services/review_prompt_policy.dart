/// Regole per chiedere una recensione dello store senza infastidire.
///
/// Logica pura (nessun plugin): decide solo *se* è il momento giusto.
/// Mostrare davvero la richiesta spetta alle API ufficiali (StoreKit su iOS,
/// Play In-App Review su Android). Nessuna ricompensa, sempre disattivabile.
class ReviewPromptState {
  const ReviewPromptState({
    this.enabled = true,
    this.firstLaunch,
    this.lastPrompt,
    this.successfulActions = 0,
  });

  final bool enabled;
  final DateTime? firstLaunch;
  final DateTime? lastPrompt;
  final int successfulActions;

  ReviewPromptState copyWith({
    bool? enabled,
    DateTime? firstLaunch,
    DateTime? lastPrompt,
    int? successfulActions,
  }) => ReviewPromptState(
    enabled: enabled ?? this.enabled,
    firstLaunch: firstLaunch ?? this.firstLaunch,
    lastPrompt: lastPrompt ?? this.lastPrompt,
    successfulActions: successfulActions ?? this.successfulActions,
  );
}

class ReviewPromptPolicy {
  const ReviewPromptPolicy({
    this.minInterval = const Duration(days: 120),
    this.minInstallAge = const Duration(days: 3),
    this.minSuccessfulActions = 2,
  });

  final Duration minInterval;
  final Duration minInstallAge;
  final int minSuccessfulActions;

  /// True solo dopo un momento positivo e se tutte le condizioni reggono.
  /// [afterError] vale true se l'operazione appena conclusa ha avuto problemi.
  bool shouldPrompt(
    ReviewPromptState state,
    DateTime now, {
    bool afterError = false,
  }) {
    if (!state.enabled || afterError) return false;
    final first = state.firstLaunch;
    if (first == null || now.difference(first) < minInstallAge) return false;
    if (state.successfulActions < minSuccessfulActions) return false;
    final last = state.lastPrompt;
    if (last != null && now.difference(last) < minInterval) return false;
    return true;
  }
}
