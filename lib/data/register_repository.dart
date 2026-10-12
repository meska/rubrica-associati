import 'package:sqflite/sqflite.dart';

enum RegisterEventType { admission, cessation, correction }

enum CessationCause { resignation, exclusion, death, other }

/// Annotazione immutabile del libro soci. Le righe non si modificano né si
/// cancellano mai: una correzione è una nuova annotazione che rimanda a quella
/// corretta.
class RegisterEvent {
  const RegisterEvent({
    required this.id,
    required this.memberId,
    required this.type,
    required this.eventDate,
    required this.firstName,
    required this.lastName,
    required this.recordedAt,
    this.cause,
    this.correctsEventId,
    this.note = '',
  });

  final int id;
  final int memberId;
  final RegisterEventType type;

  /// Data dell'evento, formato AAAA-MM-GG.
  final String eventDate;
  final String firstName;
  final String lastName;
  final String recordedAt;
  final CessationCause? cause;
  final int? correctsEventId;
  final String note;
}

/// Riga del libro in forma "effettiva" (correzioni applicate).
class RegisterEntry {
  const RegisterEntry({
    required this.progressiveNumber,
    required this.memberId,
    required this.firstName,
    required this.lastName,
    required this.admissionDate,
    this.cessationDate,
    this.cessationCause,
  });

  final int progressiveNumber;
  final int memberId;
  final String firstName;
  final String lastName;
  final String admissionDate;
  final String? cessationDate;
  final CessationCause? cessationCause;
}

class RegisterRepository {
  RegisterRepository(this._db);

  final DatabaseExecutor _db;

  /// Crea tabella e trigger append-only (migrazione additiva v5).
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS register_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        event_date TEXT NOT NULL,
        first_name TEXT NOT NULL DEFAULT '',
        last_name TEXT NOT NULL DEFAULT '',
        cause TEXT,
        corrects_event_id INTEGER,
        note TEXT NOT NULL DEFAULT '',
        recorded_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS register_events_member_idx '
      'ON register_events(member_id)',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS register_events_no_update
      BEFORE UPDATE ON register_events
      BEGIN SELECT RAISE(ABORT, 'register_events is append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS register_events_no_delete
      BEFORE DELETE ON register_events
      BEGIN SELECT RAISE(ABORT, 'register_events is append-only'); END
    ''');
  }

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String _checkDate(String value) {
    if (!_isoDate.hasMatch(value) || DateTime.tryParse(value) == null) {
      throw ArgumentError.value(value, 'date', 'atteso AAAA-MM-GG');
    }
    return value;
  }

  Future<RegisterEvent> _insert({
    required int memberId,
    required RegisterEventType type,
    required String eventDate,
    required String firstName,
    required String lastName,
    CessationCause? cause,
    int? correctsEventId,
    String note = '',
    DateTime? now,
  }) async {
    final recordedAt = (now ?? DateTime.now()).toUtc().toIso8601String();
    final id = await _db.insert('register_events', {
      'member_id': memberId,
      'event_type': type.name,
      'event_date': _checkDate(eventDate),
      'first_name': firstName,
      'last_name': lastName,
      'cause': cause?.name,
      'corrects_event_id': correctsEventId,
      'note': note,
      'recorded_at': recordedAt,
    });
    return RegisterEvent(
      id: id,
      memberId: memberId,
      type: type,
      eventDate: eventDate,
      firstName: firstName,
      lastName: lastName,
      recordedAt: recordedAt,
      cause: cause,
      correctsEventId: correctsEventId,
      note: note,
    );
  }

  Future<RegisterEvent> recordAdmission({
    required int memberId,
    required String firstName,
    required String lastName,
    required String date,
    String note = '',
    DateTime? now,
  }) => _insert(
    memberId: memberId,
    type: RegisterEventType.admission,
    eventDate: date,
    firstName: firstName,
    lastName: lastName,
    note: note,
    now: now,
  );

  Future<RegisterEvent> recordCessation({
    required int memberId,
    required String date,
    required CessationCause cause,
    String note = '',
    DateTime? now,
  }) async {
    final last = await _latestIdentity(memberId);
    return _insert(
      memberId: memberId,
      type: RegisterEventType.cessation,
      eventDate: date,
      firstName: last.$1,
      lastName: last.$2,
      cause: cause,
      note: note,
      now: now,
    );
  }

  /// Nuova annotazione che corregge [eventId]. I campi non indicati restano
  /// quelli dell'annotazione corretta (o dell'ultima correzione).
  Future<RegisterEvent> recordCorrection({
    required int eventId,
    String? date,
    String? firstName,
    String? lastName,
    CessationCause? cause,
    String note = '',
    DateTime? now,
  }) async {
    final target = await _effectiveEvent(eventId);
    if (target == null) {
      throw ArgumentError.value(eventId, 'eventId', 'annotazione inesistente');
    }
    if (target.type == RegisterEventType.correction) {
      throw ArgumentError.value(eventId, 'eventId', 'correggere l\'originale');
    }
    return _insert(
      memberId: target.memberId,
      type: RegisterEventType.correction,
      eventDate: date ?? target.eventDate,
      firstName: firstName ?? target.firstName,
      lastName: lastName ?? target.lastName,
      cause: cause ?? target.cause,
      correctsEventId: eventId,
      note: note,
      now: now,
    );
  }

  static String todayIso([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

  /// Ammissione più recente del socio che non è seguita da una cessazione.
  Future<RegisterEvent?> openAdmission(int memberId) async {
    final events = await eventsForMember(memberId);
    RegisterEvent? open;
    for (final e in events) {
      if (e.type == RegisterEventType.admission) open = e;
      if (e.type == RegisterEventType.cessation) open = null;
    }
    return open;
  }

  /// Allinea nome e cognome del libro a quelli del socio: se differiscono
  /// aggiunge una correzione (mai modifica). Senza ammissione aperta non fa
  /// nulla (soci precedenti all'introduzione del libro).
  Future<RegisterEvent?> syncIdentity({
    required int memberId,
    required String firstName,
    required String lastName,
    DateTime? now,
  }) async {
    final open = await openAdmission(memberId);
    if (open == null) return null;
    final effective = await _effectiveEvent(open.id);
    if (effective == null ||
        (effective.firstName == firstName && effective.lastName == lastName)) {
      return null;
    }
    return recordCorrection(
      eventId: open.id,
      firstName: firstName,
      lastName: lastName,
      now: now,
    );
  }

  /// Allinea la data di ammissione del libro alla data di iscrizione del
  /// socio ([joinDate], AAAA-MM-GG). Se il socio non ha mai avuto annotazioni
  /// (precedente alla v5) crea l'ammissione; se la data differisce aggiunge
  /// una correzione. Senza [joinDate] non fa nulla.
  Future<RegisterEvent?> syncJoinDate({
    required int memberId,
    required String firstName,
    required String lastName,
    required String? joinDate,
    DateTime? now,
  }) async {
    if (joinDate == null) return null;
    final open = await openAdmission(memberId);
    if (open == null) {
      if ((await eventsForMember(memberId)).isNotEmpty) return null;
      return recordAdmission(
        memberId: memberId,
        firstName: firstName,
        lastName: lastName,
        date: joinDate,
        now: now,
      );
    }
    final effective = await _effectiveEvent(open.id);
    if (effective == null || effective.eventDate == joinDate) return null;
    return recordCorrection(eventId: open.id, date: joinDate, now: now);
  }

  /// Cessazione per cancellazione dall'app, solo se c'è un'ammissione aperta.
  Future<RegisterEvent?> recordRemovalIfAdmitted(
    int memberId, {
    DateTime? now,
  }) async {
    if (await openAdmission(memberId) == null) return null;
    return recordCessation(
      memberId: memberId,
      date: todayIso(now),
      cause: CessationCause.other,
      note: 'removed-from-app',
      now: now,
    );
  }

  Future<(String, String)> _latestIdentity(int memberId) async {
    final events = await eventsForMember(memberId);
    if (events.isEmpty) return ('', '');
    final last = events.last;
    return (last.firstName, last.lastName);
  }

  /// Annotazione con l'ultima correzione applicata (se esiste).
  Future<RegisterEvent?> _effectiveEvent(int eventId) async {
    final rows = await _db.query(
      'register_events',
      where: 'id = ? OR corrects_event_id = ?',
      whereArgs: [eventId, eventId],
      orderBy: 'id',
    );
    if (rows.isEmpty) return null;
    final events = rows.map(_fromRow).toList();
    final original = events.firstWhere(
      (e) => e.id == eventId,
      orElse: () => events.first,
    );
    final corrections = events.where((e) => e.correctsEventId == eventId);
    if (corrections.isEmpty) return original;
    final c = corrections.last;
    return RegisterEvent(
      id: original.id,
      memberId: original.memberId,
      type: original.type,
      eventDate: c.eventDate,
      firstName: c.firstName,
      lastName: c.lastName,
      recordedAt: original.recordedAt,
      cause: c.cause ?? original.cause,
      note: original.note,
    );
  }

  /// Storico grezzo (in ordine di registrazione) di un socio.
  Future<List<RegisterEvent>> eventsForMember(int memberId) async {
    final rows = await _db.query(
      'register_events',
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'id',
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<RegisterEvent>> allEvents() async {
    final rows = await _db.query('register_events', orderBy: 'id');
    return rows.map(_fromRow).toList();
  }

  /// Libro soci: una riga per ammissione, correzioni applicate, numerata in
  /// progressivo per data di ammissione (a parità, ordine di registrazione).
  /// Un socio riammesso genera una nuova riga.
  Future<List<RegisterEntry>> entries() async {
    final events = await allEvents();
    final corrections = <int, RegisterEvent>{};
    for (final e in events) {
      if (e.type == RegisterEventType.correction) {
        corrections[e.correctsEventId!] = e;
      }
    }
    RegisterEvent effective(RegisterEvent e) {
      final c = corrections[e.id];
      if (c == null) return e;
      return RegisterEvent(
        id: e.id,
        memberId: e.memberId,
        type: e.type,
        eventDate: c.eventDate,
        firstName: c.firstName,
        lastName: c.lastName,
        recordedAt: e.recordedAt,
        cause: c.cause ?? e.cause,
        note: e.note,
      );
    }

    final admissions =
        events
            .where((e) => e.type == RegisterEventType.admission)
            .map(effective)
            .toList()
          ..sort((a, b) {
            final byDate = a.eventDate.compareTo(b.eventDate);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
    final cessations = events
        .where((e) => e.type == RegisterEventType.cessation)
        .map(effective)
        .toList();

    final result = <RegisterEntry>[];
    for (var i = 0; i < admissions.length; i++) {
      final a = admissions[i];
      final nextAdmission = admissions
          .skip(i + 1)
          .where((x) => x.memberId == a.memberId)
          .firstOrNull;
      // La cessazione appartiene a questa ammissione se registrata dopo di
      // essa e prima di un'eventuale riammissione.
      final cessation = cessations
          .where(
            (c) =>
                c.memberId == a.memberId &&
                c.id > a.id &&
                (nextAdmission == null || c.id < nextAdmission.id),
          )
          .firstOrNull;
      result.add(
        RegisterEntry(
          progressiveNumber: i + 1,
          memberId: a.memberId,
          firstName: a.firstName,
          lastName: a.lastName,
          admissionDate: a.eventDate,
          cessationDate: cessation?.eventDate,
          cessationCause: cessation?.cause,
        ),
      );
    }
    return result;
  }

  static RegisterEvent _fromRow(Map<String, Object?> row) => RegisterEvent(
    id: row['id'] as int,
    memberId: row['member_id'] as int,
    type: RegisterEventType.values.byName(row['event_type'] as String),
    eventDate: row['event_date'] as String,
    firstName: row['first_name'] as String? ?? '',
    lastName: row['last_name'] as String? ?? '',
    recordedAt: row['recorded_at'] as String,
    cause: row['cause'] == null
        ? null
        : CessationCause.values.byName(row['cause'] as String),
    correctsEventId: row['corrects_event_id'] as int?,
    note: row['note'] as String? ?? '',
  );
}
