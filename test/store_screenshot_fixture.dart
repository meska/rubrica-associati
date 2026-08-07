import 'dart:io';

import 'package:flutter/services.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/models/member.dart';

/// Dati inventati e stabili condivisi da tutte le immagini promozionali.
const storeFeaturedMember = Member(
  id: 1,
  firstName: 'Maria',
  lastName: 'Rossi',
  phone: '333 123 4567',
  secondaryPhone: '049 765 4321',
  memberNumber: 'A-001',
  expiryDate: null,
  birthDate: null,
  notes: 'Volontaria del centro e referente per le attività culturali.',
);

const storeMembers = <Member>[
  storeFeaturedMember,
  Member(
    id: 2,
    firstName: 'Giovanni',
    lastName: 'Bianchi',
    phone: '349 234 5678',
    memberNumber: 'A-002',
    expiryDate: null,
    notes: '',
  ),
  Member(
    id: 3,
    firstName: 'Lucia',
    lastName: 'Verdi',
    phone: '347 345 6789',
    secondaryPhone: '0422 123456',
    memberNumber: 'A-003',
    expiryDate: null,
    notes: '',
  ),
  Member(
    id: 4,
    firstName: 'Carlo',
    lastName: 'Neri',
    phone: '338 456 7890',
    memberNumber: 'A-004',
    expiryDate: null,
    notes: '',
  ),
  Member(
    id: 5,
    firstName: 'Anna',
    lastName: 'Dall’Ò',
    phone: '335 567 8901',
    memberNumber: 'A-005',
    expiryDate: null,
    notes: '',
  ),
  Member(
    id: 6,
    firstName: 'Paolo',
    lastName: 'Fontana',
    phone: '334 678 9012',
    memberNumber: 'A-006',
    expiryDate: null,
    notes: '',
  ),
];

Member storeFeaturedMemberFor(String locale) => Member(
  id: storeFeaturedMember.id,
  firstName: storeFeaturedMember.firstName,
  lastName: storeFeaturedMember.lastName,
  phone: storeFeaturedMember.phone,
  secondaryPhone: storeFeaturedMember.secondaryPhone,
  memberNumber: storeFeaturedMember.memberNumber,
  expiryDate: storeFeaturedMember.expiryDate,
  birthDate: storeFeaturedMember.birthDate,
  notes: _localizedDemoNotes[locale]!,
);

const _localizedDemoNotes = <String, String>{
  'it-IT': 'Volontaria del centro e referente per le attività culturali.',
  'en-US': 'Community volunteer and coordinator of cultural activities.',
  'fr-FR': 'Bénévole et référente des activités culturelles.',
  'de-DE': 'Ehrenamtliche und Ansprechpartnerin für Kulturaktivitäten.',
};

class StoreScreenshotRepository extends MemberRepository {
  StoreScreenshotRepository({this.organizationName = 'Circolo Serenità'});

  final String organizationName;

  @override
  Future<List<Member>> search(String query) async => storeMembers;

  @override
  Future<String> loadOrganizationName() async => organizationName;
}

/// Carica i font veri: Ahem no xe bon par screenshot da pubblicare.
Future<void> loadStoreScreenshotFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    throw StateError(
      'FLUTTER_ROOT deve indicare la directory del Flutter SDK.',
    );
  }
  final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';

  Future<ByteData> font(String name) async {
    final bytes = await File('$materialFonts/$name').readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  await (FontLoader('Roboto')
        ..addFont(font('Roboto-Regular.ttf'))
        ..addFont(font('Roboto-Medium.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(font('MaterialIcons-Regular.otf'))).load();
}
