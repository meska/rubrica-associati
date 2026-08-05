import 'package:flutter/material.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/services/tip_jar_service.dart';

class SupportSheet extends StatefulWidget {
  const SupportSheet({super.key, required this.controller});

  final TipJarController controller;

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  TipJarController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final checkoutBusy = _controller.pendingProductIds.isNotEmpty;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.tipJarTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(strings.tipJarBody),
                const SizedBox(height: 20),
                if (_controller.loading)
                  _LiveStatus(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 10),
                        Text(strings.tipJarLoading),
                      ],
                    ),
                  )
                else if (!_controller.available || _controller.products.isEmpty)
                  _LiveStatus(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(strings.tipJarUnavailable),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _controller.initialize,
                          child: Text(strings.retry),
                        ),
                      ],
                    ),
                  )
                else
                  ..._controller.products.map(
                    (product) => _TipOption(
                      product: product,
                      pending: _controller.pendingProductIds.contains(
                        product.id,
                      ),
                      disabled: checkoutBusy,
                      onPressed: () => _controller.purchase(product),
                    ),
                  ),
                if (checkoutBusy) ...[
                  const SizedBox(height: 12),
                  _LiveStatus(child: Text(strings.tipJarPending)),
                ],
                if (_controller.notice case final notice?) ...[
                  const SizedBox(height: 12),
                  _LiveStatus(
                    child: Text(
                      notice == TipNotice.thankYou
                          ? strings.tipJarThankYou
                          : strings.tipJarCanceled,
                    ),
                  ),
                ],
                if (_controller.errorKind case final error?) ...[
                  const SizedBox(height: 12),
                  _LiveStatus(
                    child: Text(
                      _errorMessage(strings, error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  if (error == TipErrorKind.completionFailed) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _controller.retryFailedCompletions,
                      child: Text(strings.retry),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                Text(
                  strings.tipJarDisclosure,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TipOption extends StatelessWidget {
  const _TipOption({
    required this.product,
    required this.pending,
    required this.disabled,
    required this.onPressed,
  });

  final TipStoreProduct product;
  final bool pending;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final tip = TipKind.values.firstWhere(
      (candidate) => candidate.productId == product.id,
    );
    final (name, description, icon) = switch (tip) {
      TipKind.secretaryCoffee => (
        strings.tipSecretaryCoffee,
        strings.tipSecretaryCoffeeDescription,
        Icons.coffee_outlined,
      ),
      TipKind.foundCard => (
        strings.tipFoundCard,
        strings.tipFoundCardDescription,
        Icons.badge_outlined,
      ),
      TipKind.paperlessMeeting => (
        strings.tipPaperlessMeeting,
        strings.tipPaperlessMeetingDescription,
        Icons.description_outlined,
      ),
      TipKind.honoraryMember => (
        strings.tipHonoraryMember,
        strings.tipHonoraryMemberDescription,
        Icons.workspace_premium_outlined,
      ),
    };
    final semanticsLabel = pending
        ? strings.tipJarPurchasePending(name)
        : disabled
        ? strings.tipJarCheckoutBusy
        : strings.tipJarPurchase(name, product.price);
    return ListTile(
      key: Key('tip-${product.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text(description),
      trailing: Semantics(
        button: true,
        enabled: !disabled,
        label: semanticsLabel,
        excludeSemantics: true,
        child: FilledButton.tonal(
          onPressed: disabled ? null : onPressed,
          child: pending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(product.price),
        ),
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, liveRegion: true, child: child);
}

String _errorMessage(AppLocalizations strings, TipErrorKind error) =>
    switch (error) {
      TipErrorKind.partialCatalog => strings.tipJarPartialCatalog,
      TipErrorKind.queryFailed => strings.tipJarQueryFailed,
      TipErrorKind.startFailed => strings.tipJarStartFailed,
      TipErrorKind.purchaseFailed => strings.tipJarPurchaseFailed,
      TipErrorKind.completionFailed => strings.tipJarCompletionFailed,
    };
