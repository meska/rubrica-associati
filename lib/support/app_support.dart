import 'package:url_launcher/url_launcher.dart';

typedef ExternalSupportLauncher = Future<bool> Function(Uri uri);

class AppSupport {
  const AppSupport._();

  // Xe l'indirizzo pubblico già usà dai progetti Meskatech, tutto in un posto.
  static final koFiUri = Uri.parse('https://ko-fi.com/meskatech');

  static Future<bool> openExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
