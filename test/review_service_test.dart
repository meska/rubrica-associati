import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/services/review_service.dart';

class FakeStore implements ReviewSettingsStore {
  final Map<String, String> data = {};
  @override
  Future<String?> loadSetting(String key) async => data[key];
  @override
  Future<void> saveSetting(String key, String value) async => data[key] = value;
}

class FakeRequester implements ReviewRequester {
  int calls = 0;
  bool available = true;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> requestReview() async => calls++;
  int opened = 0;
  @override
  Future<bool> openStoreReview() async {
    opened++;
    return true;
  }
}

void main() {
  late FakeStore store;
  late FakeRequester requester;
  late ReviewService service;
  var now = DateTime(2026, 10, 1);

  setUp(() {
    now = DateTime(2026, 10, 1);
    store = FakeStore();
    requester = FakeRequester();
    service = ReviewService(
      store: store,
      requester: requester,
      clock: () => now,
    );
  });

  test('stato iniziale: attivo, nessun dato', () async {
    final s = await service.loadState();
    expect(s.enabled, isTrue);
    expect(s.firstLaunch, isNull);
    expect(s.successfulActions, 0);
  });

  test('registerLaunch salva il primo avvio una volta sola', () async {
    await service.registerLaunch();
    now = DateTime(2026, 10, 9);
    await service.registerLaunch();
    expect((await service.loadState()).firstLaunch, DateTime(2026, 10, 1));
  });

  test('stato persiste tra istanze', () async {
    await service.registerLaunch();
    await service.recordSuccess();
    await service.setEnabled(false);
    final other = ReviewService(
      store: store,
      requester: requester,
      clock: () => now,
    );
    final s = await other.loadState();
    expect(s.enabled, isFalse);
    expect(s.successfulActions, 1);
    expect(s.firstLaunch, DateTime(2026, 10, 1));
  });

  test('valori corrotti ricadono sui default', () async {
    store.data['review_first_launch'] = 'boh';
    store.data['review_success_count'] = 'x';
    final s = await service.loadState();
    expect(s.firstLaunch, isNull);
    expect(s.successfulActions, 0);
  });

  test('nessuna richiesta prima delle condizioni', () async {
    await service.registerLaunch();
    expect(await service.maybeRequest(), isFalse);
    expect(requester.calls, 0);
  });

  test('richiesta dopo condizioni, poi blocco 120 giorni', () async {
    await service.registerLaunch();
    await service.recordSuccess();
    await service.recordSuccess();
    now = DateTime(2026, 10, 10);
    expect(await service.maybeRequest(), isTrue);
    expect(requester.calls, 1);
    expect((await service.loadState()).lastPrompt, now);
    expect(await service.maybeRequest(), isFalse);
    now = DateTime(2026, 10, 10).add(const Duration(days: 121));
    expect(await service.maybeRequest(), isTrue);
    expect(requester.calls, 2);
  });

  test('mai dopo errore né se disattivata né se non disponibile', () async {
    await service.registerLaunch();
    await service.recordSuccess();
    await service.recordSuccess();
    now = DateTime(2026, 10, 10);
    expect(await service.maybeRequest(afterError: true), isFalse);
    requester.available = false;
    expect(await service.maybeRequest(), isFalse);
    requester.available = true;
    await service.setEnabled(false);
    expect(await service.maybeRequest(), isFalse);
    expect(requester.calls, 0);
  });

  test('errore del requester non propaga e non consuma il turno', () async {
    final failing = _Failing();
    final svc = ReviewService(
      store: store,
      requester: failing,
      clock: () => now,
    );
    await svc.registerLaunch();
    await svc.recordSuccess();
    await svc.recordSuccess();
    now = DateTime(2026, 10, 10);
    expect(await svc.maybeRequest(), isFalse);
    expect((await svc.loadState()).lastPrompt, isNull);
  });

  test('openStoreReview delegates and ignores policy limits', () async {
    expect(await service.openStoreReview(), isTrue);
    expect(requester.opened, 1);
    expect(requester.calls, 0);
  });

  test('openStoreReview never throws', () async {
    final svc = ReviewService(store: store, requester: _Failing());
    expect(await svc.openStoreReview(), isFalse);
  });
}

class _Failing implements ReviewRequester {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> requestReview() async => throw StateError('store');
  @override
  Future<bool> openStoreReview() async => throw StateError('store');
}
