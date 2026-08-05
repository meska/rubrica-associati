import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/services/tip_jar_service.dart';
import 'package:rubrica_associati/widgets/support_sheet.dart';

/// Catalogo finto par verificar testi e semantica senza dipendere dallo store.
class SupportSheetStore implements TipStoreGateway {
  final updates = StreamController<List<TipPurchaseUpdate>>.broadcast();

  @override
  Stream<List<TipPurchaseUpdate>> get purchaseUpdates => updates.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<TipProductQuery> queryProducts(Set<String> ids) async =>
      TipProductQuery(
        products: [
          for (final (index, id) in ids.indexed)
            TipStoreProduct(
              id: id,
              price: '€${index + 1},99',
              rawPrice: (index + 1).toDouble(),
              rawProduct: id,
            ),
        ],
        missingIds: const {},
      );

  @override
  Future<bool> buyConsumable(TipStoreProduct product) async => true;

  @override
  Future<void> completePurchase(TipPurchaseUpdate purchase) async {}
}

void main() {
  testWidgets('shows four localized tips and accessible purchase labels', (
    tester,
  ) async {
    final store = SupportSheetStore();
    final controller = TipJarController(store: store);
    addTearDown(() async {
      controller.dispose();
      await store.updates.close();
    });

    await tester.pumpWidget(
      RubricaAssociatiApp(
        locale: const Locale('it'),
        tipJarController: controller,
        home: Scaffold(body: SupportSheet(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caffè del segretario'), findsOneWidget);
    expect(find.text('Tessera ritrovata'), findsOneWidget);
    expect(find.text('Assemblea senza fogli'), findsOneWidget);
    expect(find.text('Socio onorario digitale'), findsOneWidget);
    expect(find.textContaining('non sbloccano funzioni'), findsOneWidget);
    expect(find.textContaining('Ripristina'), findsNothing);

    final firstProduct = controller.products.first;
    final semantics = tester.getSemantics(
      find.bySemanticsLabel(
        RegExp('Acquista .+ a ${RegExp.escape(firstProduct.price)}'),
      ),
    );
    expect(semantics.label, contains('Acquista'));
    expect(semantics.label, contains(firstProduct.price));
  });

  testWidgets('keeps listening after the support sheet is dismissed', (
    tester,
  ) async {
    final store = SupportSheetStore();
    final controller = TipJarController(store: store);
    addTearDown(() async {
      controller.dispose();
      await store.updates.close();
    });

    await tester.pumpWidget(
      RubricaAssociatiApp(
        locale: const Locale('it'),
        tipJarController: controller,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => SupportSheet(controller: controller),
              ),
              child: const Text('Open support'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final product = controller.products.first;

    await tester.tap(find.text('Open support'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await controller.purchase(product);
    store.updates.add([
      TipPurchaseUpdate(
        productId: product.id,
        state: TipPurchaseState.purchased,
        rawPurchase: product.id,
        needsCompletion: true,
      ),
    ]);
    await tester.pump();

    expect(controller.notice, TipNotice.thankYou);
    expect(controller.pendingProductIds, isEmpty);
  });
}
