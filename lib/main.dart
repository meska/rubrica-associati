import 'dart:io';

import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
  const RubricaAssociatiApp({super.key, this.repository, this.home});

  final MemberRepository? repository;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    const brandTeal = Color(0xFF006B5B);
    return MaterialApp(
      title: 'Rubrica Associati',
      debugShowCheckedModeBanner: false,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
