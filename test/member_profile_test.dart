import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Member _m(String first, String last, {DateTime? join, String cf = ''}) =>
    Member(
      firstName: first,
      lastName: last,
      phone: '',
      memberNumber: '',
      joinDate: join,
      taxCode: cf,
      birthPlace: 'Padova',
      notes: '',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late MemberRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rubrica_l3');
    repo = MemberRepository(databasePath: path.join(dir.path, 'a.db'));
  });

  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  test(
    'i nuovi campi socio si salvano e il codice fiscale è normalizzato',
    () async {
      final saved = await repo.save(
        _m(
          'Mario',
          'Rossi',
          join: DateTime(2019, 5, 3),
          cf: ' rssmra 49c02 g224x ',
        ),
      );
      final loaded = (await repo.search('')).single;
      expect(loaded.id, saved.id);
      expect(loaded.joinDate, DateTime(2019, 5, 3));
      expect(loaded.taxCode, 'RSSMRA49C02G224X');
      expect(loaded.birthPlace, 'Padova');
    },
  );

  test('l\'ammissione usa la data di iscrizione, altrimenti oggi', () async {
    final a = await repo.save(_m('A', 'Uno', join: DateTime(2018, 1, 15)));
    final b = await repo.save(_m('B', 'Due'));
    expect((await repo.registerHistory(a.id!)).single.eventDate, '2018-01-15');
    expect(
      (await repo.registerHistory(b.id!)).single.eventDate,
      RegisterRepository.todayIso(),
    );
  });

  test(
    'cambiare la data iscrizione aggiunge una correzione, non modifica',
    () async {
      final a = await repo.save(_m('A', 'Uno', join: DateTime(2018, 1, 15)));
      await repo.save(
        Member(
          id: a.id,
          firstName: 'A',
          lastName: 'Uno',
          phone: '',
          memberNumber: '',
          joinDate: DateTime(2017, 12, 1),
          notes: '',
        ),
      );
      final history = await repo.registerHistory(a.id!);
      expect(history, hasLength(2));
      expect(history.first.eventDate, '2018-01-15');
      expect(history.last.type, RegisterEventType.correction);
      expect(history.last.eventDate, '2017-12-01');
    },
  );

  test(
    'socio senza storico: la data iscrizione crea l\'ammissione una volta sola',
    () async {
      final memory = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      await RegisterRepository.createSchema(memory);
      final reg = RegisterRepository(memory);
      final event = await reg.syncJoinDate(
        memberId: 7,
        firstName: 'X',
        lastName: 'Y',
        joinDate: '2015-06-01',
      );
      expect(event?.type, RegisterEventType.admission);
      expect(event?.eventDate, '2015-06-01');
      expect(
        await reg.syncJoinDate(
          memberId: 7,
          firstName: 'X',
          lastName: 'Y',
          joinDate: '2015-06-01',
        ),
        isNull,
      );
      expect(
        await reg.syncJoinDate(
          memberId: 8,
          firstName: 'X',
          lastName: 'Y',
          joinDate: null,
        ),
        isNull,
      );
      await memory.close();
    },
  );

  test('dati ente: salvataggio, normalizzazione e valori di default', () async {
    var profile = await repo.loadEntityProfile();
    expect(profile.name, MemberRepository.defaultOrganizationName);
    expect(profile.address, '');
    await repo.saveEntityProfile(
      const EntityProfile(
        name: ' Centro Aurora ',
        address: 'Via Roma 1, Padova',
        taxCode: '92 000 000 285',
        legalRepresentative: 'Anna Bianchi',
      ),
    );
    profile = await repo.loadEntityProfile();
    expect(profile.name, 'Centro Aurora');
    expect(profile.taxCode, '92000000285');
    expect(profile.legalRepresentative, 'Anna Bianchi');
    expect(
      () =>
          repo.saveEntityProfile(EntityProfile(name: 'X', address: 'a' * 201)),
      throwsArgumentError,
    );
  });

  test(
    'backup: round trip dei nuovi campi e compatibilità con vecchi .rubrica',
    () {
      final service = BackupService();
      final bytes = service.encode([
        _m(
          'Mario',
          'Rossi',
          join: DateTime(2019, 5, 3),
          cf: 'rssmra49c02g224x',
        ),
      ]);
      final back = service.decode(bytes).single;
      expect(back.joinDate, DateTime(2019, 5, 3));
      expect(back.taxCode, 'RSSMRA49C02G224X');
      expect(back.birthPlace, 'Padova');

      final old = utf8.encode(
        jsonEncode({
          'format': 'rubrica-associati',
          'version': 1,
          'exportedAt': '2026-01-01T00:00:00Z',
          'members': [
            {
              'firstName': 'Vecchio',
              'lastName': 'Backup',
              'phone': '',
              'memberNumber': '',
              'expiryDate': null,
              'birthDate': null,
              'notes': '',
            },
          ],
        }),
      );
      final restored = service.decode(Uint8List.fromList(old)).single;
      expect(restored.joinDate, isNull);
      expect(restored.taxCode, '');
      expect(restored.birthPlace, '');
    },
  );

  test(
    'upgrade da v5 a v6: dati e storico preservati, colonne nuove vuote',
    () async {
      final file = path.join(dir.path, 'v5.db');
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT NOT NULL, last_name TEXT NOT NULL,
            name_key TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '', phone_key TEXT NOT NULL DEFAULT '',
            secondary_phone TEXT NOT NULL DEFAULT '',
            secondary_phone_key TEXT NOT NULL DEFAULT '',
            member_number TEXT NOT NULL DEFAULT '',
            expiry_date TEXT, birth_date TEXT,
            notes TEXT NOT NULL DEFAULT '')''');
            await d.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await RegisterRepository.createSchema(d);
            await d.insert('members', {
              'first_name': 'Mario',
              'last_name': 'Rossi',
            });
            await RegisterRepository(d).recordAdmission(
              memberId: 1,
              firstName: 'Mario',
              lastName: 'Rossi',
              date: '2020-01-01',
            );
          },
        ),
      );
      await old.close();

      final upgradedRepo = MemberRepository(databasePath: file);
      final members = await upgradedRepo.search('');
      expect(members, hasLength(1));
      expect(members.single.joinDate, isNull);
      expect(members.single.taxCode, '');
      expect(await upgradedRepo.registerHistory(1), hasLength(1));
      await upgradedRepo.close();
    },
  );
}
