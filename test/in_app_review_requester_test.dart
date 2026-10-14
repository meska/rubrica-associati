import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/services/in_app_review_requester.dart';

class _Gateway implements InAppReviewGateway {
  _Gateway({this.throws = false});
  final bool available = true;
  final bool throws;
  var requests = 0;

  @override
  Future<bool> isAvailable() async {
    if (throws) throw StateError('plugin');
    return available;
  }

  @override
  Future<void> requestReview() async => requests++;

  String? openedStoreId;
  @override
  Future<void> openStoreListing(String appStoreId) async {
    if (throws) throw StateError('plugin');
    openedStoreId = appStoreId;
  }
}

void main() {
  test('unsupported platform is never available', () async {
    final gateway = _Gateway();
    final r = InAppReviewRequester(
      gateway: gateway,
      supportedPlatform: () => false,
    );
    expect(await r.isAvailable(), isFalse);
  });

  test('delegates availability and request to the gateway', () async {
    final gateway = _Gateway();
    final r = InAppReviewRequester(
      gateway: gateway,
      supportedPlatform: () => true,
    );
    expect(await r.isAvailable(), isTrue);
    await r.requestReview();
    expect(gateway.requests, 1);
  });

  test('plugin errors turn into unavailable', () async {
    final r = InAppReviewRequester(
      gateway: _Gateway(throws: true),
      supportedPlatform: () => true,
    );
    expect(await r.isAvailable(), isFalse);
  });

  test(
    'openStoreReview opens the store listing with the App Store id',
    () async {
      final gateway = _Gateway();
      final r = InAppReviewRequester(
        gateway: gateway,
        supportedPlatform: () => true,
      );
      expect(await r.openStoreReview(), isTrue);
      expect(gateway.openedStoreId, InAppReviewRequester.appStoreId);
    },
  );

  test(
    'openStoreReview is false on unsupported platforms and on errors',
    () async {
      expect(
        await InAppReviewRequester(
          gateway: _Gateway(),
          supportedPlatform: () => false,
        ).openStoreReview(),
        isFalse,
      );
      expect(
        await InAppReviewRequester(
          gateway: _Gateway(throws: true),
          supportedPlatform: () => true,
        ).openStoreReview(),
        isFalse,
      );
    },
  );
}
