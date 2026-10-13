import 'dart:io';

import 'package:rubrica_associati/data/closure_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/services/review_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ImportSaveResult {
  const ImportSaveResult({required this.inserted, required this.updated});

  final int inserted;
  final int updated;
}

/// Dati anagrafici dell'ente per l'intestazione dei documenti.
class EntityProfile {
  const EntityProfile({
    required this.name,
    this.address = '',
    this.taxCode = '',
    this.legalRepresentative = '',
  });

  static const addressKey = 'entity_address';
  static const taxCodeKey = 'entity_tax_code';
  static const repKey = 'entity_legal_representative';
  static const maxFieldLength = 200;

  final String name;
  final String address;
  final String taxCode;
  final String legalRepresentative;

  EntityProfile normalized() => EntityProfile(
    name: name.trim(),
    address: address.trim(),
    taxCode: Member.normalizeTaxCode(taxCode),
    legalRepresentative: legalRepresentative.trim(),
  );
}

class MemberRepository implements ReviewSettingsStore {
  MemberRepository({Database? database, String? databasePath})
    : _databaseOverride = database,
      _databasePathOverride = databasePath;

  static const defaultOrganizationName = 'Centro pensionati';
  static const maxOrganizationNameLength = 80;
  static const _databaseFileName = 'rubrica_associati.db';

  final Database? _databaseOverride;
  final String? _databasePathOverride;
  Database? _database;
  bool _overrideSchemaReady = false;

  Future<Database> get _db async {
    if (_databaseOverride != null) {
      if (!_overrideSchemaReady) {
        _overrideSchemaReady = true;
        await _addRegisterColumns(_databaseOverride);
        await RegisterRepository.createSchema(_databaseOverride);
        await ClosureRepository.createSchema(_databaseOverride);
        await VolunteerRepository.createSchema(_databaseOverride);
      }
      return _databaseOverride;
    }
    if (_database != null) return _database!;

    final databasePath = _databasePathOverride ?? await _defaultDatabasePath();
    _database = await openDatabase(
      databasePath,
      version: 8,
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
            join_date TEXT,
            tax_code TEXT NOT NULL DEFAULT '',
            birth_place TEXT NOT NULL DEFAULT '',
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
        await RegisterRepository.createSchema(db);
        await ClosureRepository.createSchema(db);
        await VolunteerRepository.createSchema(db);
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
        if (oldVersion < 5) await RegisterRepository.createSchema(db);
        if (oldVersion < 6) await _addRegisterColumns(db);
        if (oldVersion < 7) await ClosureRepository.createSchema(db);
        if (oldVersion < 8) await VolunteerRepository.createSchema(db);
      },
    );
    return _database!;
  }

  static Future<String> _defaultDatabasePath() async {
    final legacyPath = path.join(await getDatabasesPath(), _databaseFileName);
    if (!Platform.isWindows && !Platform.isLinux) return legacyPath;

    final supportDirectory = await getApplicationSupportDirectory();
    final databasePath = path.join(
      supportDirectory.path,
      'databases',
      _databaseFileName,
    );
    await _copyLegacyDesktopDatabase(legacyPath, databasePath);
    return databasePath;
  }

  static Future<void> _copyLegacyDesktopDatabase(
    String legacyPath,
    String databasePath,
  ) async {
    if (path.equals(legacyPath, databasePath) ||
        await File(databasePath).exists() ||
        !await File(legacyPath).exists()) {
      return;
    }

    await Directory(path.dirname(databasePath)).create(recursive: true);
    // I file laterali vien prima: el DB principale fa da segnale de copia completa.
    for (final suffix in const ['-wal', '-shm', '']) {
      final source = File('$legacyPath$suffix');
      if (await source.exists()) {
        await source.copy('$databasePath$suffix');
      }
    }
  }

  /// Migrazione additiva v6: data iscrizione, codice fiscale, luogo di nascita.
  /// Idempotente (controlla le colonne presenti).
  static Future<void> _addRegisterColumns(DatabaseExecutor db) async {
    final existing = (await db.rawQuery(
      'PRAGMA table_info(members)',
    )).map((row) => row['name']).toSet();
    const columns = {
      'join_date': 'TEXT',
      'tax_code': "TEXT NOT NULL DEFAULT ''",
      'birth_place': "TEXT NOT NULL DEFAULT ''",
    };
    for (final entry in columns.entries) {
      if (!existing.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE members ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
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

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  @override
  Future<String?> loadSetting(String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  @override
  Future<void> saveSetting(String key, String value) async {
    final db = await _db;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  /// Dati dell'ente per l'intestazione del libro soci (chiavi entity_*).
  Future<EntityProfile> loadEntityProfile() async {
    final name = await loadOrganizationName();
    return EntityProfile(
      name: name,
      address: await loadSetting(EntityProfile.addressKey) ?? '',
      taxCode: await loadSetting(EntityProfile.taxCodeKey) ?? '',
      legalRepresentative: await loadSetting(EntityProfile.repKey) ?? '',
    );
  }

  Future<void> saveEntityProfile(EntityProfile profile) async {
    final cleaned = profile.normalized();
    if (cleaned.address.length > EntityProfile.maxFieldLength ||
        cleaned.taxCode.length > EntityProfile.maxFieldLength ||
        cleaned.legalRepresentative.length > EntityProfile.maxFieldLength) {
      throw ArgumentError.value(profile, 'profile', 'Dati ente non validi');
    }
    await saveOrganizationName(cleaned.name);
    await saveSetting(EntityProfile.addressKey, cleaned.address);
    await saveSetting(EntityProfile.taxCodeKey, cleaned.taxCode);
    await saveSetting(EntityProfile.repKey, cleaned.legalRepresentative);
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
    return db.transaction((tx) async {
      final register = RegisterRepository(tx);
      if (member.id == null) {
        final id = await tx.insert('members', values);
        await register.recordAdmission(
          memberId: id,
          firstName: member.firstName.trim(),
          lastName: member.lastName.trim(),
          date: values['join_date'] as String? ?? RegisterRepository.todayIso(),
        );
        return member.copyWith(id: id);
      }

      await tx.update(
        'members',
        values,
        where: 'id = ?',
        whereArgs: [member.id],
      );
      await register.syncJoinDate(
        memberId: member.id!,
        firstName: member.firstName.trim(),
        lastName: member.lastName.trim(),
        joinDate: values['join_date'] as String?,
      );
      await register.syncIdentity(
        memberId: member.id!,
        firstName: member.firstName.trim(),
        lastName: member.lastName.trim(),
      );
      return member;
    });
  }

  /// Elimina il socio dalla rubrica; nel libro soci annota la cessazione e
  /// conserva lo storico (nessuna cancellazione fisica delle annotazioni).
  Future<void> delete(int id) async {
    final db = await _db;
    await db.transaction((tx) async {
      await RegisterRepository(tx).recordRemovalIfAdmitted(id);
      await tx.delete('members', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Storico grezzo del libro soci per un socio.
  Future<List<RegisterEntry>> registerEntries() async {
    final db = await _db;
    return RegisterRepository(db).entries();
  }

  Future<ClosureRepository> closureRepository() async =>
      ClosureRepository(await _db);

  Future<VolunteerRepository> volunteerRepository() async =>
      VolunteerRepository(await _db);

  Future<List<RegisterEvent>> registerHistory(int memberId) async {
    final db = await _db;
    return RegisterRepository(db).eventsForMember(memberId);
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
          final id = await transaction.insert('members', values);
          await RegisterRepository(transaction).recordAdmission(
            memberId: id,
            firstName: member.firstName.trim(),
            lastName: member.lastName.trim(),
            date:
                values['join_date'] as String? ?? RegisterRepository.todayIso(),
          );
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
        await RegisterRepository(transaction).syncJoinDate(
          memberId: existing.id!,
          firstName: merged.firstName.trim(),
          lastName: merged.lastName.trim(),
          joinDate: values['join_date'] as String?,
        );
        await RegisterRepository(transaction).syncIdentity(
          memberId: existing.id!,
          firstName: merged.firstName.trim(),
          lastName: merged.lastName.trim(),
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
    joinDate: incoming.joinDate ?? old.joinDate,
    taxCode: _preferIncoming(old.taxCode, incoming.taxCode),
    birthPlace: _preferIncoming(old.birthPlace, incoming.birthPlace),
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
