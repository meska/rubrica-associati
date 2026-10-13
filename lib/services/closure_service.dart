import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:rubrica_associati/data/closure_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/services/register_book_service.dart';

class ClosureException implements Exception {
  const ClosureException(this.code);

  /// Uno tra: invalidYear, emptyFile, tooLarge, unsupportedType, notPdf.
  final String code;

  @override
  String toString() => 'ClosureException($code)';
}

/// Archiviazione della chiusura annuale: l'ente firma fuori dall'app il PDF
/// del libro, l'app ne conserva una copia con la sua impronta SHA-256.
/// L'app non verifica né attesta la firma.
class ClosureService {
  ClosureService({
    required this.repository,
    required this.directory,
    this.maxBytes = 50 * 1024 * 1024,
  });

  final ClosureRepository repository;

  /// Cartella di archivio (interna all'app).
  final Directory directory;
  final int maxBytes;

  static const _extensions = {'.pdf', '.p7m'};

  Future<YearClosure> archive({
    required int year,
    required Uint8List bytes,
    required String originalName,
    required DateTime now,
    String exportSha256 = '',
    String note = '',
  }) async {
    if (year < 1900 || year > now.year) {
      throw const ClosureException('invalidYear');
    }
    if (bytes.isEmpty) throw const ClosureException('emptyFile');
    if (bytes.length > maxBytes) throw const ClosureException('tooLarge');
    final ext = path.extension(originalName).toLowerCase();
    if (!_extensions.contains(ext)) {
      throw const ClosureException('unsupportedType');
    }
    if (ext == '.pdf' && !_hasPdfHeader(bytes)) {
      throw const ClosureException('notPdf');
    }

    final digest = sha256.convert(bytes).toString();
    await directory.create(recursive: true);
    var name = 'chiusura-$year-${digest.substring(0, 12)}$ext';
    var file = File(path.join(directory.path, name));
    // Mai sovrascrivere: se esiste lo stesso contenuto va bene, altrimenti suffisso.
    var n = 1;
    while (await file.exists()) {
      final existing = await file.readAsBytes();
      if (sha256.convert(existing).toString() == digest) break;
      name = 'chiusura-$year-${digest.substring(0, 12)}-${n++}$ext';
      file = File(path.join(directory.path, name));
    }
    final created = !await file.exists();
    if (created) await file.writeAsBytes(bytes, flush: true);
    try {
      return await repository.add(
        year: year,
        fileName: name,
        sha256: digest,
        sizeBytes: bytes.length,
        exportSha256: exportSha256,
        note: note,
        now: now,
      );
    } catch (_) {
      if (created) await file.delete();
      rethrow;
    }
  }

  /// Vero se il file archiviato esiste e ha ancora l'impronta registrata.
  Future<bool> verify(YearClosure closure) async {
    final file = File(path.join(directory.path, closure.fileName));
    if (!await file.exists()) return false;
    return sha256.convert(await file.readAsBytes()).toString() ==
        closure.sha256;
  }

  File fileOf(YearClosure closure) =>
      File(path.join(directory.path, closure.fileName));

  /// Anni conclusi (prima dell'anno corrente) con righe nel libro e senza
  /// chiusura archiviata: da ricordare all'utente, dal più vecchio.
  List<int> pendingYears({
    required List<RegisterEntry> entries,
    required Iterable<YearClosure> closures,
    required DateTime now,
  }) {
    const book = RegisterBookService();
    final closed = closures.map((c) => c.year).toSet();
    final years = book.availableYears(entries, now)
      ..removeWhere((y) => y >= now.year || closed.contains(y));
    return [
      for (final y in years.reversed)
        if (book.entriesForYear(entries, y).isNotEmpty) y,
    ];
  }

  static bool _hasPdfHeader(Uint8List b) =>
      b.length >= 5 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46 &&
      b[4] == 0x2D;
}
