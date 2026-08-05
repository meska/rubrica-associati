import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Optional consumables that support development without unlocking anything.
enum TipKind {
  secretaryCoffee('rubrica_tip_small'),
  foundCard('rubrica_tip_medium'),
  paperlessMeeting('rubrica_tip_large'),
  honoraryMember('rubrica_tip_legendary');

  const TipKind(this.productId);

  final String productId;
}

enum TipPurchaseState { pending, purchased, restored, canceled, error }

enum TipNotice { thankYou, canceled }

enum TipErrorKind {
  partialCatalog,
  queryFailed,
  startFailed,
  purchaseFailed,
  completionFailed,
}

class TipStoreProduct {
  const TipStoreProduct({
    required this.id,
    required this.price,
    required this.rawPrice,
    required this.rawProduct,
  });

  final String id;
  final String price;
  final double rawPrice;
  final Object rawProduct;
}

class TipPurchaseUpdate {
  const TipPurchaseUpdate({
    required this.productId,
    required this.state,
    required this.rawPurchase,
    this.needsCompletion = false,
  });

  final String productId;
  final TipPurchaseState state;
  final Object rawPurchase;
  final bool needsCompletion;
}

class TipProductQuery {
  const TipProductQuery({
    required this.products,
    required this.missingIds,
    this.hasError = false,
  });

  final List<TipStoreProduct> products;
  final Set<String> missingIds;
  final bool hasError;
}

abstract interface class TipStoreGateway {
  Stream<List<TipPurchaseUpdate>> get purchaseUpdates;

  Future<bool> isAvailable();
  Future<TipProductQuery> queryProducts(Set<String> ids);
  Future<bool> buyConsumable(TipStoreProduct product);
  Future<void> completePurchase(TipPurchaseUpdate purchase);
}

class InAppPurchaseTipStore implements TipStoreGateway {
  InAppPurchaseTipStore({InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  @override
  Stream<List<TipPurchaseUpdate>> get purchaseUpdates => _store.purchaseStream
      .map((purchases) => purchases.map(_adaptPurchase).toList());

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<TipProductQuery> queryProducts(Set<String> ids) async {
    final response = await _store.queryProductDetails(ids);
    return TipProductQuery(
      products: response.productDetails
          .map(
            (product) => TipStoreProduct(
              id: product.id,
              price: product.price,
              rawPrice: product.rawPrice,
              rawProduct: product,
            ),
          )
          .toList(),
      missingIds: response.notFoundIDs.toSet(),
      hasError: response.error != null,
    );
  }

  @override
  Future<bool> buyConsumable(TipStoreProduct product) => _store.buyConsumable(
    purchaseParam: PurchaseParam(
      productDetails: product.rawProduct as ProductDetails,
    ),
  );

  @override
  Future<void> completePurchase(TipPurchaseUpdate purchase) =>
      _store.completePurchase(purchase.rawPurchase as PurchaseDetails);

  TipPurchaseUpdate _adaptPurchase(PurchaseDetails purchase) {
    final state = switch (purchase.status) {
      PurchaseStatus.pending => TipPurchaseState.pending,
      PurchaseStatus.purchased => TipPurchaseState.purchased,
      // Un consumabile ripristinato xe solo una consegna rimasta da chiudere.
      PurchaseStatus.restored => TipPurchaseState.restored,
      PurchaseStatus.canceled => TipPurchaseState.canceled,
      PurchaseStatus.error => TipPurchaseState.error,
    };
    return TipPurchaseUpdate(
      productId: purchase.productID,
      state: state,
      rawPurchase: purchase,
      needsCompletion: purchase.pendingCompletePurchase,
    );
  }
}

/// Owns the consumable lifecycle and exposes only localized, UI-safe states.
class TipJarController extends ChangeNotifier {
  TipJarController({TipStoreGateway? store})
    : _store = store ?? InAppPurchaseTipStore();

  final TipStoreGateway _store;
  StreamSubscription<List<TipPurchaseUpdate>>? _subscription;
  Future<void>? _initialization;
  final Map<String, TipStoreProduct> _products = <String, TipStoreProduct>{};
  final Map<String, TipPurchaseUpdate> _failedCompletions =
      <String, TipPurchaseUpdate>{};

  bool loading = true;
  bool available = false;
  bool disposed = false;
  TipErrorKind? errorKind;
  TipNotice? notice;
  final Set<String> pendingProductIds = <String>{};
  var _retryingCompletions = false;

  List<TipStoreProduct> get products {
    final catalog = TipKind.values
        .map((tip) => _products[tip.productId])
        .whereType<TipStoreProduct>()
        .toList();
    catalog.sort((left, right) => left.rawPrice.compareTo(right.rawPrice));
    return catalog;
  }

  Future<void> initialize() {
    final active = _initialization;
    if (active != null) return active;
    final initialization = _initialize();
    _initialization = initialization;
    return initialization.whenComplete(() {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    });
  }

  Future<void> _initialize() async {
    _subscription ??= _store.purchaseUpdates.listen(
      _handlePurchaseUpdates,
      onError: (Object _) {
        errorKind = TipErrorKind.purchaseFailed;
        _notify();
      },
    );
    loading = true;
    errorKind = null;
    _notify();
    try {
      available = await _store.isAvailable();
      if (!available) {
        _products.clear();
        return;
      }
      final expectedIds = TipKind.values.map((tip) => tip.productId).toSet();
      final result = await _store.queryProducts(expectedIds);
      _products
        ..clear()
        ..addEntries(
          result.products
              .where((item) => expectedIds.contains(item.id))
              .map((item) => MapEntry(item.id, item)),
        );
      if (result.hasError) {
        errorKind = TipErrorKind.queryFailed;
      } else if (result.missingIds.isNotEmpty ||
          _products.length != expectedIds.length) {
        errorKind = TipErrorKind.partialCatalog;
      }
      if (_failedCompletions.isNotEmpty) {
        await retryFailedCompletions();
      }
    } catch (_) {
      available = false;
      errorKind = TipErrorKind.queryFailed;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> purchase(TipStoreProduct product) async {
    // Un checkout ala volta: i store no i ga bisogno de gare de velocità.
    if (pendingProductIds.isNotEmpty || !_products.containsKey(product.id)) {
      return;
    }
    pendingProductIds.add(product.id);
    errorKind = null;
    notice = null;
    _notify();
    try {
      final started = await _store.buyConsumable(product);
      if (!started) {
        pendingProductIds.remove(product.id);
        errorKind = TipErrorKind.startFailed;
        _notify();
      }
    } catch (_) {
      pendingProductIds.remove(product.id);
      errorKind = TipErrorKind.startFailed;
      _notify();
    }
  }

  Future<void> _handlePurchaseUpdates(List<TipPurchaseUpdate> purchases) async {
    final knownIds = TipKind.values.map((tip) => tip.productId).toSet();
    for (final purchase in purchases) {
      if (!knownIds.contains(purchase.productId)) continue;
      switch (purchase.state) {
        case TipPurchaseState.pending:
          pendingProductIds.add(purchase.productId);
          continue;
        case TipPurchaseState.purchased:
        case TipPurchaseState.restored:
        case TipPurchaseState.canceled:
        case TipPurchaseState.error:
          await _finishTerminalPurchase(purchase);
          continue;
      }
    }
    _notify();
  }

  Future<void> _finishTerminalPurchase(
    TipPurchaseUpdate purchase, {
    bool alreadyCompleted = false,
  }) async {
    if (purchase.needsCompletion && !alreadyCompleted) {
      try {
        await _store.completePurchase(purchase);
        _failedCompletions.remove(purchase.productId);
        if (errorKind == TipErrorKind.completionFailed) errorKind = null;
      } catch (_) {
        // Tegnimo el prodotto bloccà finché la consegna no xe chiusa davvero.
        _failedCompletions[purchase.productId] = purchase;
        pendingProductIds.add(purchase.productId);
        errorKind = TipErrorKind.completionFailed;
        return;
      }
    }
    pendingProductIds.remove(purchase.productId);
    switch (purchase.state) {
      case TipPurchaseState.purchased:
        notice = TipNotice.thankYou;
      case TipPurchaseState.restored:
        // Una consegna recuperata no crea diritti e no simula un nuovo acquisto.
        break;
      case TipPurchaseState.canceled:
        notice = TipNotice.canceled;
      case TipPurchaseState.error:
        errorKind = TipErrorKind.purchaseFailed;
      case TipPurchaseState.pending:
        break;
    }
  }

  Future<void> retryFailedCompletions() async {
    if (_retryingCompletions || _failedCompletions.isEmpty) return;
    _retryingCompletions = true;
    final failed = _failedCompletions.values.toList();
    errorKind = null;
    _notify();
    try {
      for (final purchase in failed) {
        try {
          await _store.completePurchase(purchase);
          _failedCompletions.remove(purchase.productId);
          await _finishTerminalPurchase(purchase, alreadyCompleted: true);
        } catch (_) {
          errorKind = TipErrorKind.completionFailed;
        }
      }
    } finally {
      _retryingCompletions = false;
      _notify();
    }
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
