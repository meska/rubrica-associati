import 'package:rubrica_associati/models/member.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class ImportSaveResult {
  const ImportSaveResult({required this.inserted, required this.updated});

  final int inserted;
  final int updated;
}

class MemberRepository {
  MemberRepository({Database? database}) : _databaseOverride = database;

  static const defaultOrganizationName = 'Centro pensionati';
  static const maxOrganizationNameLength = 80;

  final Database? _databaseOverride;
  Database? _database;

  Future<Database> get _db async {
    if (_databaseOverride != null) return _databaseOverride;
    if (_database != null) return _database!;

    final databasesPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasesPath, 'rubrica_associati.db'),
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT NOT NULL,
            last_name TEXT NOT NULL,
            name_key TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            phone_key TEXT NOT NULL DEFAULT '',
            secondary_phone TEXT NOT NULL DEFAULT '',
            secondary_phone_key TEXT NOT NULL DEFAULT '',
            member_number TEXT NOT NULL DEFAULT '',
            expiry_date TEXT,
            birth_date TEXT,
            notes TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute(
          'CREATE INDEX members_name_idx ON members(last_name, first_name)',
        );
        await db.execute(
          'CREATE INDEX members_card_idx ON members(member_number)',
        );
        await _createSettingsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSettingsTable(db);
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE members ADD COLUMN secondary_phone TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE members ADD COLUMN secondary_phone_key TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE members ADD COLUMN name_key TEXT NOT NULL DEFAULT ''",
          );
          await _populateNameKeys(db);
        }
      },
    );
    return _database!;
  }

  static Future<void> _createSettingsTable(DatabaseExecutor db) =>
      db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

  static Future<void> _populateNameKeys(Database db) async {
    final rows = await db.query(
      'members',
      columns: const ['id', 'first_name', 'last_name'],
    );
    final batch = db.batch();
    for (final row in rows) {
      batch.update(
        'members',
        {
          'name_key': _nameKey(
            row['first_name'] as String? ?? '',
            row['last_name'] as String? ?? '',
          ),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    // Una botta sola al database, cussì l'aggiornamento resta svelto.
    await batch.commit(noResult: true);
  }

  Future<String> loadOrganizationName() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['organization_name'],
      limit: 1,
    );
    if (rows.isEmpty) return defaultOrganizationName;
    return rows.single['value'] as String;
  }

  Future<void> saveOrganizationName(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty || cleaned.length > maxOrganizationNameLength) {
      throw ArgumentError.value(name, 'name', 'Nome del centro non valido');
    }

    final db = await _db;
    await db.insert('app_settings', {
      'key': 'organization_name',
      'value': cleaned,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Member>> search(String query) async {
    final db = await _db;
    final cleaned = query.trim().toLowerCase();
    List<Map<String, Object?>> rows;

    if (cleaned.isEmpty) {
      rows = await db.query(
        'members',
        orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE',
      );
    } else {
      // Escape LIKE wildcards: el cerca quel che l'utente ga scritto davvero.
      final escaped = cleaned
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final term = '%$escaped%';
      final phoneDigits = cleaned.replaceAll(RegExp(r'\D'), '');
      final nameTokens = _normalizeSearchText(
        cleaned,
      ).split(' ').where((token) => token.isNotEmpty).toList(growable: false);
      final conditions = <String>[
        if (nameTokens.isNotEmpty)
          '(${nameTokens.map((_) => "name_key LIKE ? ESCAPE '\\'").join(' AND ')})',
        "LOWER(phone) LIKE ? ESCAPE '\\'",
        "LOWER(secondary_phone) LIKE ? ESCAPE '\\'",
        "LOWER(member_number) LIKE ? ESCAPE '\\'",
        if (phoneDigits.isNotEmpty) 'phone_key LIKE ?',
        if (phoneDigits.isNotEmpty) 'secondary_phone_key LIKE ?',
      ];
      rows = await db.query(
        'members',
        where: conditions.join(' OR '),
        whereArgs: [
          ...nameTokens.map((token) => '%$token%'),
          term,
          term,
          term,
          if (phoneDigits.isNotEmpty) '%$phoneDigits%',
          if (phoneDigits.isNotEmpty) '%$phoneDigits%',
        ],
        orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE',
      );
    }

    return rows.map(Member.fromMap).toList(growable: false);
  }

  Future<Member> save(Member member) async {
    final db = await _db;
    final values = _valuesFor(member);
    if (member.id == null) {
      final id = await db.insert('members', values);
      return member.copyWith(id: id);
    }

    await db.update('members', values, where: 'id = ?', whereArgs: [member.id]);
    return member;
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<ImportSaveResult> importMembers(List<Member> members) async {
    final db = await _db;
    return db.transaction((transaction) async {
      var inserted = 0;
      var updated = 0;

      for (final member in members) {
        final existing = await _findDuplicate(transaction, member);
        if (existing == null) {
          final values = _valuesFor(member);
          await transaction.insert('members', values);
          inserted++;
          continue;
        }

        // L'import completa i dati nuovi senza cancellare campi già compilati.
        final merged = _merge(existing, member);
        final values = _valuesFor(merged);
        await transaction.update(
          'members',
          values,
          where: 'id = ?',
          whereArgs: [existing.id],
        );
        updated++;
      }

      return ImportSaveResult(inserted: inserted, updated: updated);
    });
  }

  Future<Member?> _findDuplicate(DatabaseExecutor db, Member member) async {
    List<Map<String, Object?>> rows = [];
    if (member.memberNumber.isNotEmpty) {
      rows = await db.query(
        'members',
        where: 'LOWER(member_number) = ?',
        whereArgs: [member.memberNumber.toLowerCase()],
        limit: 1,
      );
    }
    if (rows.isEmpty && member.phoneKey.isNotEmpty) {
      rows = await db.query(
        'members',
        where: 'name_key = ? AND (phone_key = ? OR secondary_phone_key = ?)',
        whereArgs: [
          _nameKey(member.firstName, member.lastName),
          member.phoneKey,
          member.phoneKey,
        ],
        limit: 1,
      );
    }
    if (rows.isEmpty && member.secondaryPhoneKey.isNotEmpty) {
      rows = await db.query(
        'members',
        where: 'name_key = ? AND (phone_key = ? OR secondary_phone_key = ?)',
        whereArgs: [
          _nameKey(member.firstName, member.lastName),
          member.secondaryPhoneKey,
          member.secondaryPhoneKey,
        ],
        limit: 1,
      );
    }
    if (rows.isEmpty &&
        member.memberNumber.isEmpty &&
        member.phoneKey.isEmpty &&
        member.secondaryPhoneKey.isEmpty) {
      rows = await _findDuplicateWithoutContact(db, member);
    }
    return rows.isEmpty ? null : Member.fromMap(rows.first);
  }

  Future<List<Map<String, Object?>>> _findDuplicateWithoutContact(
    DatabaseExecutor db,
    Member member,
  ) async {
    final nameKey = _nameKey(member.firstName, member.lastName);
    if (nameKey.isEmpty) return const [];

    final candidates = await db.query(
      'members',
      where: 'name_key = ?',
      whereArgs: [nameKey],
    );
    if (candidates.isEmpty) return const [];

    final birthDate = member.toMap()['birth_date'];
    if (birthDate != null) {
      final sameBirthDate = candidates
          .where((row) => row['birth_date'] == birthDate)
          .toList(growable: false);
      if (sameBirthDate.length == 1) return sameBirthDate;
      if (candidates.length == 1 && candidates.single['birth_date'] == null) {
        return candidates;
      }
      return const [];
    }

    // Col solo nome se aggiorna esclusivamente un candidato non ambiguo.
    return candidates.length == 1 ? candidates : const [];
  }

  Member _merge(Member old, Member incoming) => Member(
    id: old.id,
    firstName: _preferIncoming(old.firstName, incoming.firstName),
    lastName: _preferIncoming(old.lastName, incoming.lastName),
    phone: _preferIncoming(old.phone, incoming.phone),
    secondaryPhone: _preferIncoming(
      old.secondaryPhone,
      incoming.secondaryPhone,
    ),
    memberNumber: _preferIncoming(old.memberNumber, incoming.memberNumber),
    expiryDate: incoming.expiryDate ?? old.expiryDate,
    birthDate: incoming.birthDate ?? old.birthDate,
    notes: _preferIncoming(old.notes, incoming.notes),
  );

  String _preferIncoming(String old, String incoming) =>
      incoming.trim().isEmpty ? old : incoming.trim();

  Map<String, Object?> _valuesFor(Member member) => member.toMap()
    ..remove('id')
    ..['name_key'] = _nameKey(member.firstName, member.lastName);

  static String _nameKey(String firstName, String lastName) =>
      _normalizeSearchText('$firstName $lastName');

  static String _normalizeSearchText(String value) {
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    final buffer = StringBuffer();
    for (final character in value.toLowerCase().split('')) {
      buffer.write(replacements[character] ?? character);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
