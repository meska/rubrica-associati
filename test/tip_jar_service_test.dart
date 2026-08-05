import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/services/tip_jar_service.dart';

/// Store deterministico: i test controlla el lifecycle senza tocar soldi veri.
class FakeTipStore implements TipStoreGateway {
  final updates = StreamController<List<TipPurchaseUpdate>>.broadcast();

  bool storeAvailable = true;
  bool startsPurchase = true;
  bool queryHasError = false;
  Object? queryException;
  Object? completionException;
  Set<String> missingIds = const {};
  final purchasedIds = <String>[];
  final completedIds = <String>[];

  @override
  Stream<List<TipPurchaseUpdate>> get purchaseUpdates => updates.stream;

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<TipProductQuery> queryProducts(Set<String> ids) async {
    if (queryException case final exception?) throw exception;
    final reversed = ids.toList().reversed.toList();
    return TipProductQuery(
      products: [
        for (var index = 0; index < reversed.length; index++)
          TipStoreProduct(
            id: reversed[index],
            price: '€${index + 1},99',
            rawPrice: (index + 1).toDouble(),
            rawProduct: reversed[index],
          ),
      ],
      missingIds: missingIds,
      hasError: queryHasError,
    );
  }

  @override
  Future<bool> buyConsumable(TipStoreProduct product) async {
    purchasedIds.add(product.id);
    return startsPurchase;
  }

  @override
  Future<void> completePurchase(TipPurchaseUpdate purchase) async {
    if (completionException case final exception?) throw exception;
    completedIds.add(purchase.productId);
  }

  Future<void> close() => updates.close();
}

void main() {
  late FakeTipStore store;
  late TipJarController controller;

  setUp(() {
    store = FakeTipStore();
    controller = TipJarController(store: store);
  });

  tearDown(() async {
    controller.dispose();
    await store.close();
  });

  test('loads four unique consumables ordered by store price', () async {
    await controller.initialize();

    expect(controller.available, isTrue);
    expect(controller.products, hasLength(4));
    expect(controller.products.map((product) => product.id).toSet(), {
      'rubrica_tip_small',
      'rubrica_tip_medium',
      'rubrica_tip_large',
      'rubrica_tip_legendary',
    });
    expect(
      controller.products.map((product) => product.rawPrice),
      orderedEquals(<double>[1, 2, 3, 4]),
    );
  });

  test('reports unavailable and incomplete catalogs safely', () async {
    store.storeAvailable = false;
    await controller.initialize();
    expect(controller.available, isFalse);
    expect(controller.products, isEmpty);

    store
      ..storeAvailable = true
      ..missingIds = {'rubrica_tip_legendary'};
    await controller.initialize();
    expect(controller.errorKind, TipErrorKind.partialCatalog);
  });

  test('sanitizes returned and thrown catalog failures', () async {
    store.queryHasError = true;
    await controller.initialize();
    expect(controller.errorKind, TipErrorKind.queryFailed);

    store
      ..queryHasError = false
      ..queryException = StateError('private store diagnostic');
    await controller.initialize();
    expect(controller.available, isFalse);
    expect(controller.errorKind, TipErrorKind.queryFailed);
  });

  test('clears checkout lock when purchase cannot start', () async {
    await controller.initialize();
    store.startsPurchase = false;

    await controller.purchase(controller.products.first);

    expect(controller.pendingProductIds, isEmpty);
    expect(controller.errorKind, TipErrorKind.startFailed);
  });

  test('tracks pending then completes a successful purchase', () async {
    await controller.initialize();
    final product = controller.products.first;
    await controller.purchase(product);
    expect(controller.pendingProductIds, contains(product.id));

    store.updates.add([
      TipPurchaseUpdate(
        productId: product.id,
        state: TipPurchaseState.purchased,
        rawPurchase: product.id,
        needsCompletion: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.pendingProductIds, isEmpty);
    expect(controller.notice, TipNotice.thankYou);
    expect(store.completedIds, [product.id]);
  });

  test('blocks concurrent checkout and completes cancel and error', () async {
    await controller.initialize();
    final first = controller.products.first;
    await controller.purchase(first);
    await controller.purchase(controller.products.last);
    expect(store.purchasedIds, [first.id]);

    store.updates.add([
      TipPurchaseUpdate(
        productId: first.id,
        state: TipPurchaseState.canceled,
        rawPurchase: first.id,
        needsCompletion: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.notice, TipNotice.canceled);
    expect(controller.pendingProductIds, isEmpty);
    expect(store.completedIds, [first.id]);

    await controller.purchase(first);
    store.updates.add([
      TipPurchaseUpdate(
        productId: first.id,
        state: TipPurchaseState.error,
        rawPurchase: first.id,
        needsCompletion: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.errorKind, TipErrorKind.purchaseFailed);
    expect(controller.pendingProductIds, isEmpty);
    expect(store.completedIds, [first.id, first.id]);
  });

  test(
    'acknowledges restored consumable without notice or entitlement',
    () async {
      await controller.initialize();
      final product = controller.products.first;
      store.updates.add([
        TipPurchaseUpdate(
          productId: product.id,
          state: TipPurchaseState.restored,
          rawPurchase: product.id,
          needsCompletion: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.notice, isNull);
      expect(controller.pendingProductIds, isEmpty);
      expect(store.completedIds, [product.id]);
    },
  );

  test('retains completion failure until an explicit retry succeeds', () async {
    await controller.initialize();
    final product = controller.products.first;
    await controller.purchase(product);
    store.completionException = StateError('completion failed');
    store.updates.add([
      TipPurchaseUpdate(
        productId: product.id,
        state: TipPurchaseState.purchased,
        rawPurchase: product.id,
        needsCompletion: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.notice, isNull);
    expect(controller.pendingProductIds, contains(product.id));
    expect(controller.errorKind, TipErrorKind.completionFailed);

    store.completionException = null;
    await controller.retryFailedCompletions();

    expect(controller.pendingProductIds, isEmpty);
    expect(controller.errorKind, isNull);
    expect(controller.notice, TipNotice.thankYou);
    expect(store.completedIds, [product.id]);
  });

  test('ignores purchase updates belonging to unknown products', () async {
    await controller.initialize();
    store.updates.add([
      const TipPurchaseUpdate(
        productId: 'another_app_product',
        state: TipPurchaseState.purchased,
        rawPurchase: 'foreign',
        needsCompletion: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.notice, isNull);
    expect(store.completedIds, isEmpty);
  });
}
