import 'package:anteas_rubrica/data/member_repository.dart';
import 'package:anteas_rubrica/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnteasApp());
}

class AnteasApp extends StatelessWidget {
  const AnteasApp({super.key, this.repository});

  final MemberRepository? repository;

  @override
  Widget build(BuildContext context) {
    const anteasGreen = Color(0xFF006B52);
    return MaterialApp(
      title: 'Anteas Rubrica',
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
          seedColor: anteasGreen,
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
      home: HomeScreen(repository: repository ?? MemberRepository()),
    );
  }
}
