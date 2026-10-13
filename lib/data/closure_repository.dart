import 'package:sqflite/sqflite.dart';

/// Chiusura annuale archiviata: file firmato dall'ente, con la sua impronta.
class YearClosure {
  const YearClosure({
    required this.id,
    required this.year,
    required this.fileName,
    required this.sha256,
    required this.sizeBytes,
    required this.archivedAt,
    this.exportSha256 = '',
    this.note = '',
  });

  final int id;
  final int year;

  /// Nome del file nella cartella di archivio dell'app (non un percorso).
  final String fileName;
  final String sha256;
  final int sizeBytes;
  final String archivedAt;

  /// Impronta del PDF esportato dall'app (se nota), per confronto.
  final String exportSha256;
  final String note;
}

/// Registro append-only delle chiusure annuali (migrazione additiva v7).
/// Una sostituzione è una nuova riga: la più recente dell'anno è quella valida,
/// le precedenti restano come storico.
class ClosureRepository {
  ClosureRepository(this._db);

  final DatabaseExecutor _db;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS year_closures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        sha256 TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        export_sha256 TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        archived_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS year_closures_year_idx '
      'ON year_closures(year)',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS year_closures_no_update
      BEFORE UPDATE ON year_closures
      BEGIN SELECT RAISE(ABORT, 'year_closures is append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS year_closures_no_delete
      BEFORE DELETE ON year_closures
      BEGIN SELECT RAISE(ABORT, 'year_closures is append-only'); END
    ''');
  }

  Future<YearClosure> add({
    required int year,
    required String fileName,
    required String sha256,
    required int sizeBytes,
    String exportSha256 = '',
    String note = '',
    DateTime? now,
  }) async {
    final archivedAt = (now ?? DateTime.now()).toUtc().toIso8601String();
    final id = await _db.insert('year_closures', {
      'year': year,
      'file_name': fileName,
      'sha256': sha256,
      'size_bytes': sizeBytes,
      'export_sha256': exportSha256,
      'note': note,
      'archived_at': archivedAt,
    });
    return YearClosure(
      id: id,
      year: year,
      fileName: fileName,
      sha256: sha256,
      sizeBytes: sizeBytes,
      archivedAt: archivedAt,
      exportSha256: exportSha256,
      note: note,
    );
  }

  /// Tutte le chiusure, dalla più recente.
  Future<List<YearClosure>> all() async {
    final rows = await _db.query(
      'year_closures',
      orderBy: 'year DESC, id DESC',
    );
    return rows
        .map(
          (r) => YearClosure(
            id: r['id'] as int,
            year: r['year'] as int,
            fileName: r['file_name'] as String,
            sha256: r['sha256'] as String,
            sizeBytes: r['size_bytes'] as int,
            exportSha256: r['export_sha256'] as String? ?? '',
            note: r['note'] as String? ?? '',
            archivedAt: r['archived_at'] as String,
          ),
        )
        .toList(growable: false);
  }

  /// Chiusura valida per anno (la più recente).
  Future<Map<int, YearClosure>> latestByYear() async {
    final result = <int, YearClosure>{};
    for (final c in await all()) {
      result.putIfAbsent(c.year, () => c);
    }
    return result;
  }
}
