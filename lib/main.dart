import 'dart:io';

import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/screens/home_screen.dart';
import 'package:rubrica_associati/services/tip_jar_service.dart';
import 'package:rubrica_associati/support/app_support.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Sui desktop SQLite el ga bisogno del backend FFI, sui telefoni fa tuto el plugin nativo.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const RubricaAssociatiApp());
}

class RubricaAssociatiApp extends StatefulWidget {
  const RubricaAssociatiApp({
    super.key,
    this.repository,
    this.home,
    this.locale,
    this.tipJarController,
    this.supportLauncher = AppSupport.openExternal,
  });

  final MemberRepository? repository;
  final Widget? home;
  final Locale? locale;
  final TipJarController? tipJarController;
  final ExternalSupportLauncher supportLauncher;

  @override
  State<RubricaAssociatiApp> createState() => _RubricaAssociatiAppState();
}

class _RubricaAssociatiAppState extends State<RubricaAssociatiApp> {
  TipJarController? _tipJarController;
  var _ownsTipJarController = false;

  @override
  void initState() {
    super.initState();
    final supportsNativeTips = Platform.isAndroid || Platform.isIOS;
    _tipJarController =
        widget.tipJarController ??
        (supportsNativeTips ? TipJarController() : null);
    _ownsTipJarController =
        widget.tipJarController == null && _tipJarController != null;
    // El listener resta vivo par tutta la sessione, anca col pannello serà.
    _tipJarController?.initialize();
  }

  @override
  void dispose() {
    if (_ownsTipJarController) _tipJarController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandTeal = Color(0xFF006B5B);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: widget.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: _resolveLocale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandTeal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          elevation: 0,
        ),
      ),
      home:
          widget.home ??
          HomeScreen(
            repository: widget.repository ?? MemberRepository(),
            tipJarController: _tipJarController,
            supportLauncher: widget.supportLauncher,
          ),
    );
  }
}

Locale _resolveLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  for (final preferred in preferredLocales ?? const <Locale>[]) {
    for (final supported in supportedLocales) {
      if (preferred.languageCode == supported.languageCode) return supported;
    }
  }
  // Se el telefono parla una lingua che no gavemo, l'inglese xe el fallback più universale.
  return const Locale('en');
}
