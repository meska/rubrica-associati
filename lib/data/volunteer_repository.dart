import 'package:sqflite/sqflite.dart';

/// Tipo di annotazione nel registro volontari.
enum VolunteerEventKind { enrollment, correction, cessation }

/// Registro dei volontari non occasionali (DM 6/10/2021, art. 3) e, in
/// sezione separata, degli occasionali. Livello dati append-only:
/// iscrizione, correzione e cancellazione sono nuove righe, mai modifiche.
class VolunteerEntry {
  const VolunteerEntry({
    required this.volunteerId,
    required this.progressiveNumber,
    required this.firstName,
    required this.lastName,
    required this.taxCode,
    required this.birthDate,
    required this.birthPlace,
    required this.residence,
    required this.occasional,
    required this.startDate,
    required this.endDate,
    required this.note,
  });

  final int volunteerId;
  final int progressiveNumber;
  final String firstName;
  final String lastName;
  final String taxCode;
  final String birthDate;
  final String birthPlace;
  final String residence;
  final bool occasional;

  /// Data di inizio attività = data di iscrizione nel registro.
  final String startDate;

  /// Data di cessazione = data di cancellazione dal registro (null se attivo).
  final String? endDate;
  final String note;

  bool get isActive => endDate == null;
}

class VolunteerRepository {
  VolunteerRepository(this._db);

  final DatabaseExecutor _db;

  static final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS volunteer_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        volunteer_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        event_date TEXT NOT NULL,
        first_name TEXT NOT NULL DEFAULT '',
        last_name TEXT NOT NULL DEFAULT '',
        tax_code TEXT NOT NULL DEFAULT '',
        birth_date TEXT NOT NULL DEFAULT '',
        birth_place TEXT NOT NULL DEFAULT '',
        residence TEXT NOT NULL DEFAULT '',
        occasional INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        recorded_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS volunteer_events_vol_idx '
      'ON volunteer_events(volunteer_id)',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS volunteer_events_no_update
      BEFORE UPDATE ON volunteer_events
      BEGIN SELECT RAISE(ABORT, 'volunteer_events is append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS volunteer_events_no_delete
      BEFORE DELETE ON volunteer_events
      BEGIN SELECT RAISE(ABORT, 'volunteer_events is append-only'); END
    ''');
  }

  /// DM art. 3: codice fiscale oppure (generalità + luogo e data di nascita);
  /// residenza o domicilio; data di inizio attività.
  static void _validateIdentity({
    required String firstName,
    required String lastName,
    required String taxCode,
    required String birthDate,
    required String birthPlace,
    required String residence,
  }) {
    final hasTax = taxCode.trim().isNotEmpty;
    final hasFull =
        firstName.trim().isNotEmpty &&
        lastName.trim().isNotEmpty &&
        birthPlace.trim().isNotEmpty &&
        birthDate.isNotEmpty;
    if (!hasTax && !hasFull) {
      throw ArgumentError(
        'Servono il codice fiscale oppure generalità, luogo e data di nascita',
      );
    }
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      throw ArgumentError('Nome e cognome obbligatori');
    }
    if (residence.trim().isEmpty) {
      throw ArgumentError('Residenza o domicilio obbligatori');
    }
    if (birthDate.isNotEmpty && !_dateRe.hasMatch(birthDate)) {
      throw ArgumentError('Data di nascita non valida: $birthDate');
    }
  }

  static void _validateDate(String date) {
    if (!_dateRe.hasMatch(date)) {
      throw ArgumentError('Data non valida: $date');
    }
  }

  Future<int> _nextVolunteerId() async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(MAX(volunteer_id), 0) + 1 AS n FROM volunteer_events',
    );
    return r.first['n'] as int;
  }

  Future<void> _insert({
    required int volunteerId,
    required VolunteerEventKind kind,
    required String date,
    String firstName = '',
    String lastName = '',
    String taxCode = '',
    String birthDate = '',
    String birthPlace = '',
    String residence = '',
    bool occasional = false,
    String note = '',
    DateTime? now,
  }) async {
    await _db.insert('volunteer_events', {
      'volunteer_id': volunteerId,
      'kind': kind.name,
      'event_date': date,
      'first_name': firstName,
      'last_name': lastName,
      'tax_code': taxCode.trim().toUpperCase(),
      'birth_date': birthDate,
      'birth_place': birthPlace.trim(),
      'residence': residence.trim(),
      'occasional': occasional ? 1 : 0,
      'note': note,
      'recorded_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  /// Iscrive un volontario; restituisce il suo identificativo.
  Future<int> enroll({
    required String firstName,
    required String lastName,
    required String startDate,
    String taxCode = '',
    String birthDate = '',
    String birthPlace = '',
    String residence = '',
    bool occasional = false,
    String note = '',
    DateTime? now,
  }) async {
    _validateDate(startDate);
    _validateIdentity(
      firstName: firstName,
      lastName: lastName,
      taxCode: taxCode,
      birthDate: birthDate,
      birthPlace: birthPlace,
      residence: residence,
    );
    final id = await _nextVolunteerId();
    await _insert(
      volunteerId: id,
      kind: VolunteerEventKind.enrollment,
      date: startDate,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      taxCode: taxCode,
      birthDate: birthDate,
      birthPlace: birthPlace,
      residence: residence,
      occasional: occasional,
      note: note,
      now: now,
    );
    return id;
  }

  /// Correzione dei dati: nuova annotazione, l'originale resta nello storico.
  /// [date] è la data dell'annotazione, non della modifica di inizio attività.
  Future<void> correct({
    required int volunteerId,
    required String date,
    required String firstName,
    required String lastName,
    String taxCode = '',
    String birthDate = '',
    String birthPlace = '',
    String residence = '',
    bool occasional = false,
    String note = '',
    DateTime? now,
  }) async {
    _validateDate(date);
    _validateIdentity(
      firstName: firstName,
      lastName: lastName,
      taxCode: taxCode,
      birthDate: birthDate,
      birthPlace: birthPlace,
      residence: residence,
    );
    await _requireExisting(volunteerId);
    await _insert(
      volunteerId: volunteerId,
      kind: VolunteerEventKind.correction,
      date: date,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      taxCode: taxCode,
      birthDate: birthDate,
      birthPlace: birthPlace,
      residence: residence,
      occasional: occasional,
      note: note,
      now: now,
    );
  }

  /// Cessazione dell'attività = cancellazione dal registro (riga conservata).
  Future<void> cease({
    required int volunteerId,
    required String endDate,
    String note = '',
    DateTime? now,
  }) async {
    _validateDate(endDate);
    final entry = await _requireExisting(volunteerId);
    if (entry.endDate != null) {
      throw StateError('Volontario già cessato');
    }
    if (endDate.compareTo(entry.startDate) < 0) {
      throw ArgumentError('La cessazione precede l\'inizio attività');
    }
    await _insert(
      volunteerId: volunteerId,
      kind: VolunteerEventKind.cessation,
      date: endDate,
      note: note,
      now: now,
    );
  }

  Future<VolunteerEntry> _requireExisting(int volunteerId) async {
    final e = (await entries()).where((x) => x.volunteerId == volunteerId);
    if (e.isEmpty) throw StateError('Volontario sconosciuto: $volunteerId');
    return e.first;
  }

  /// Storico grezzo, in ordine di inserimento.
  Future<List<Map<String, Object?>>> rawEvents(int volunteerId) => _db.query(
    'volunteer_events',
    where: 'volunteer_id = ?',
    whereArgs: [volunteerId],
    orderBy: 'id',
  );

  /// Stato corrente di ogni volontario. Il progressivo segue la data di
  /// inizio attività (a parità, ordine di iscrizione), separatamente per
  /// non occasionali e occasionali (sezione separata).
  Future<List<VolunteerEntry>> entries() async {
    final rows = await _db.query('volunteer_events', orderBy: 'id');
    final state = <int, Map<String, Object?>>{};
    final order = <int>[];
    for (final r in rows) {
      final vid = r['volunteer_id'] as int;
      final kind = r['kind'] as String;
      if (kind == VolunteerEventKind.enrollment.name) {
        state[vid] = {...r, 'start': r['event_date'], 'end': null};
        order.add(vid);
      } else if (kind == VolunteerEventKind.correction.name) {
        final s = state[vid]!;
        state[vid] = {...r, 'start': s['start'], 'end': s['end']};
      } else {
        state[vid] = {...state[vid]!, 'end': r['event_date']};
      }
    }
    final list = [for (final vid in order) (vid, state[vid]!)];
    list.sort((a, b) {
      final c = (a.$2['start'] as String).compareTo(b.$2['start'] as String);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    final counters = <bool, int>{false: 0, true: 0};
    return [
      for (final (vid, s) in list)
        () {
          final occ = (s['occasional'] as int) == 1;
          counters[occ] = counters[occ]! + 1;
          return VolunteerEntry(
            volunteerId: vid,
            progressiveNumber: counters[occ]!,
            firstName: s['first_name'] as String,
            lastName: s['last_name'] as String,
            taxCode: s['tax_code'] as String,
            birthDate: s['birth_date'] as String,
            birthPlace: s['birth_place'] as String,
            residence: s['residence'] as String,
            occasional: occ,
            startDate: s['start'] as String,
            endDate: s['end'] as String?,
            note: s['note'] as String,
          );
        }(),
    ];
  }
}
