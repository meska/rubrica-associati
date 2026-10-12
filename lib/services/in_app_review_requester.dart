import 'dart:io';

import 'package:in_app_review/in_app_review.dart';
import 'package:rubrica_associati/services/review_service.dart';

/// Accesso minimo al plugin, sostituibile nei test.
abstract class InAppReviewGateway {
  Future<bool> isAvailable();
  Future<void> requestReview();
}

class _PluginGateway implements InAppReviewGateway {
  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();
}

/// Richiesta nativa (StoreKit su Apple, Play In-App Review su Android).
/// Solo API ufficiali: nessun dialogo proprio, nessun incentivo.
class InAppReviewRequester implements ReviewRequester {
  InAppReviewRequester({
    InAppReviewGateway? gateway,
    bool Function()? supportedPlatform,
  }) : _gateway = gateway ?? _PluginGateway(),
       _supportedPlatform = supportedPlatform ?? _defaultSupported;

  final InAppReviewGateway _gateway;
  final bool Function() _supportedPlatform;

  static bool _defaultSupported() =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Future<bool> isAvailable() async {
    if (!_supportedPlatform()) return false;
    try {
      return await _gateway.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestReview() => _gateway.requestReview();
}
