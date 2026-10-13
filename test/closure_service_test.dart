import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/closure_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/services/closure_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List _pdf(String body) =>
    Uint8List.fromList(utf8.encode('%PDF-1.4\n$body'));

void main() {
  late Database db;
  late Directory dir;
  late ClosureService service;
  final now = DateTime.utc(2027, 1, 10);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ClosureRepository.createSchema(db);
    dir = await Directory.systemTemp.createTemp('closures');
    service = ClosureService(repository: ClosureRepository(db), directory: dir);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('archivia file firmato con impronta e lo verifica', () async {
    final c = await service.archive(
      year: 2026,
      bytes: _pdf('firmato'),
      originalName: 'libro firmato.pdf',
      now: now,
      exportSha256: 'abc',
    );
    expect(c.sha256, hasLength(64));
    expect(c.fileName, startsWith('chiusura-2026-'));
    expect(c.fileName, isNot(contains(' ')));
    expect(c.exportSha256, 'abc');
    expect(await service.verify(c), isTrue);
    await service.fileOf(c).writeAsString('manomesso');
    expect(await service.verify(c), isFalse);
  });

  test('rifiuta anno, file vuoto, tipo e PDF non validi', () async {
    Future<String> code(Future<Object?> f) async {
      try {
        await f;
      } on ClosureException catch (e) {
        return e.code;
      }
      return 'ok';
    }

    expect(
      await code(
        service.archive(
          year: 2028,
          bytes: _pdf('x'),
          originalName: 'a.pdf',
          now: now,
        ),
      ),
      'invalidYear',
    );
    expect(
      await code(
        service.archive(
          year: 2026,
          bytes: Uint8List(0),
          originalName: 'a.pdf',
          now: now,
        ),
      ),
      'emptyFile',
    );
    expect(
      await code(
        service.archive(
          year: 2026,
          bytes: _pdf('x'),
          originalName: 'a.exe',
          now: now,
        ),
      ),
      'unsupportedType',
    );
    expect(
      await code(
        service.archive(
          year: 2026,
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          originalName: 'a.pdf',
          now: now,
        ),
      ),
      'notPdf',
    );
    expect(
      await code(
        ClosureService(
          repository: ClosureRepository(db),
          directory: dir,
          maxBytes: 4,
        ).archive(
          year: 2026,
          bytes: _pdf('x'),
          originalName: 'a.pdf',
          now: now,
        ),
      ),
      'tooLarge',
    );
    expect(await ClosureRepository(db).all(), isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test('p7m accettato senza controllo intestazione PDF', () async {
    final c = await service.archive(
      year: 2026,
      bytes: Uint8List.fromList([0x30, 0x82, 1, 2]),
      originalName: 'libro.PDF.p7m',
      now: now,
    );
    expect(c.fileName, endsWith('.p7m'));
  });

  test(
    'sostituzione = nuova riga, la più recente vale, file mai sovrascritti',
    () async {
      final a = await service.archive(
        year: 2026,
        bytes: _pdf('uno'),
        originalName: 'a.pdf',
        now: now,
      );
      final b = await service.archive(
        year: 2026,
        bytes: _pdf('due'),
        originalName: 'b.pdf',
        now: now.add(const Duration(days: 1)),
      );
      expect(a.fileName, isNot(b.fileName));
      expect(dir.listSync(), hasLength(2));
      final latest = await ClosureRepository(db).latestByYear();
      expect(latest[2026]!.id, b.id);
      expect(await ClosureRepository(db).all(), hasLength(2));
      // stesso contenuto due volte: un solo file su disco, due annotazioni
      await service.archive(
        year: 2026,
        bytes: _pdf('due'),
        originalName: 'b.pdf',
        now: now,
      );
      expect(dir.listSync(), hasLength(2));
    },
  );

  test('tabella append-only', () async {
    await service.archive(
      year: 2026,
      bytes: _pdf('x'),
      originalName: 'a.pdf',
      now: now,
    );
    expect(() => db.update('year_closures', {'year': 2020}), throwsA(anything));
    expect(() => db.delete('year_closures'), throwsA(anything));
  });

  test('promemoria: anni conclusi con soci e senza chiusura', () async {
    RegisterEntry e(String adm, [String? cess]) => RegisterEntry(
      progressiveNumber: 1,
      memberId: 1,
      firstName: 'A',
      lastName: 'B',
      admissionDate: adm,
      cessationDate: cess,
    );
    final entries = [e('2024-03-01', '2025-06-30')];
    expect(
      service.pendingYears(entries: entries, closures: const [], now: now),
      [2024, 2025],
    );
    await service.archive(
      year: 2024,
      bytes: _pdf('x'),
      originalName: 'a.pdf',
      now: now,
    );
    final closures = await ClosureRepository(db).all();
    expect(
      service.pendingYears(entries: entries, closures: closures, now: now),
      [2025],
    );
    // anno in corso mai nel promemoria; libro vuoto: nessun promemoria
    expect(
      service.pendingYears(entries: const [], closures: const [], now: now),
      isEmpty,
    );
  });
}
