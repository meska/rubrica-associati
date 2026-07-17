import 'dart:io';

import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/screens/home_screen.dart';
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

class RubricaAssociatiApp extends StatelessWidget {
  const RubricaAssociatiApp({
    super.key,
    this.repository,
    this.home,
    this.locale,
  });

  final MemberRepository? repository;
  final Widget? home;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    const brandTeal = Color(0xFF006B5B);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
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
      home: home ?? HomeScreen(repository: repository ?? MemberRepository()),
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
