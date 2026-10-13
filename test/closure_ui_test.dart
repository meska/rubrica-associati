import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/closure_repository.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/screens/register_book_screen.dart';
import 'package:rubrica_associati/services/closure_service.dart';
import 'package:sqflite/sqflite.dart';

Uint8List _pdf() => Uint8List.fromList(utf8.encode('%PDF-1.4\nfirmato'));

class _NoDb implements DatabaseExecutor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Repository in memoria: stessa interfaccia, senza SQLite (che nel test
/// widget non completa nel tempo simulato).
class _MemRepo extends ClosureRepository {
  _MemRepo() : super(_NoDb());
  final _rows = <YearClosure>[];

  @override
  Future<YearClosure> add({
    required int year,
    required String fileName,
    required String sha256,
    required int sizeBytes,
    String exportSha256 = '',
    String note = '',
    DateTime? now,
  }) async {
    final c = YearClosure(
      id: _rows.length + 1,
      year: year,
      fileName: fileName,
      sha256: sha256,
      sizeBytes: sizeBytes,
      archivedAt: (now ?? DateTime.now()).toUtc().toIso8601String(),
      exportSha256: exportSha256,
      note: note,
    );
    _rows.insert(0, c);
    return c;
  }

  @override
  Future<List<YearClosure>> all() async => List.of(_rows);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  final lastYear = DateTime.now().year - 1;
  final entries = [
    RegisterEntry(
      progressiveNumber: 1,
      memberId: 1,
      firstName: 'Anna',
      lastName: 'Verdi',
      admissionDate: '$lastYear-01-02',
    ),
  ];

  for (final e in {
    'it': ('Archivia chiusura firmata', 'Anni senza chiusura archiviata'),
    'en': ('Archive signed closing', 'Years without an archived closing'),
    'fr': ('Archiver la clôture signée', 'Années sans clôture archivée'),
    'de': (
      'Signierten Abschluss archivieren',
      'Jahre ohne archivierten Abschluss',
    ),
  }.entries) {
    testWidgets('chiusura: promemoria, archivio e verifica (${e.key})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Directory dir;
      late ClosureService service;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('closure_ui');
        service = ClosureService(repository: _MemRepo(), directory: dir);
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(e.key),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RegisterBookScreen(
            entries: entries,
            profile: const EntityProfile(name: 'Centro'),
            closureService: service,
            closurePicker: (_) async => (name: 'libro.pdf', bytes: _pdf()),
          ),
        ),
      );
      await _settle(tester);
      expect(find.textContaining(e.value.$2), findsOneWidget);
      expect(find.textContaining('$lastYear'), findsWidgets);

      await tester.tap(find.text(e.value.$1));
      await _settle(tester);

      expect(find.textContaining(e.value.$2), findsNothing);
      expect(find.textContaining('chiusura-$lastYear-'), findsOneWidget);
      expect(find.textContaining('SHA-256: '), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  }

  testWidgets('chiusura: file alterato segnalato', (tester) async {
    tester.view.physicalSize = const Size(1000, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory dir;
    late ClosureService service;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('closure_ui');
      service = ClosureService(repository: _MemRepo(), directory: dir);
      final c = await service.archive(
        year: lastYear,
        bytes: _pdf(),
        originalName: 'x.pdf',
        now: DateTime.now(),
      );
      await service.fileOf(c).writeAsBytes([1, 2, 3]);
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RegisterBookScreen(
          entries: entries,
          profile: const EntityProfile(name: 'Centro'),
          closureService: service,
        ),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('File mancante o alterato'), findsOneWidget);
    expect(find.byIcon(Icons.warning), findsOneWidget);
  });

  testWidgets('chiusura: tipo non ammesso mostra errore', (tester) async {
    tester.view.physicalSize = const Size(1000, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory dir;
    late ClosureService service;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('closure_ui');
      service = ClosureService(repository: _MemRepo(), directory: dir);
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RegisterBookScreen(
          entries: entries,
          profile: const EntityProfile(name: 'Centro'),
          closureService: service,
          closurePicker: (_) async => (name: 'a.exe', bytes: _pdf()),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Archivia chiusura firmata'));
    await _settle(tester);
    expect(find.text('Sono ammessi solo file .pdf o .p7m.'), findsOneWidget);
    expect(find.textContaining('Nessuna chiusura archiviata'), findsOneWidget);
  });
}
