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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT NOT NULL,
            last_name TEXT NOT NULL,
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
      final phoneTerm = '%${cleaned.replaceAll(RegExp(r'\D'), '')}%';
      rows = await db.query(
        'members',
        where: '''
          LOWER(first_name || ' ' || last_name) LIKE ? ESCAPE '\\'
          OR LOWER(last_name || ' ' || first_name) LIKE ? ESCAPE '\\'
          OR LOWER(phone) LIKE ? ESCAPE '\\'
          OR phone_key LIKE ?
          OR LOWER(secondary_phone) LIKE ? ESCAPE '\\'
          OR secondary_phone_key LIKE ?
          OR LOWER(member_number) LIKE ? ESCAPE '\\'
        ''',
        whereArgs: [term, term, term, phoneTerm, term, phoneTerm, term],
        orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE',
      );
    }

    return rows.map(Member.fromMap).toList(growable: false);
  }

  Future<Member> save(Member member) async {
    final db = await _db;
    final values = member.toMap()..remove('id');
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
          final values = member.toMap()..remove('id');
          await transaction.insert('members', values);
          inserted++;
          continue;
        }

        // L'import completa i dati nuovi senza cancellare campi già compilati.
        final merged = _merge(existing, member);
        final values = merged.toMap()..remove('id');
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
        where: 'phone_key = ? OR secondary_phone_key = ?',
        whereArgs: [member.phoneKey, member.phoneKey],
        limit: 1,
      );
    }
    if (rows.isEmpty && member.secondaryPhoneKey.isNotEmpty) {
      rows = await db.query(
        'members',
        where: 'phone_key = ? OR secondary_phone_key = ?',
        whereArgs: [member.secondaryPhoneKey, member.secondaryPhoneKey],
        limit: 1,
      );
    }
    return rows.isEmpty ? null : Member.fromMap(rows.first);
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
}
