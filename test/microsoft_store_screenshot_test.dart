import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';

const _featuredMember = Member(
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

const _members = <Member>[
  _featuredMember,
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

class _ScreenshotRepository extends MemberRepository {
  @override
  Future<List<Member>> search(String query) async => _members;

  @override
  Future<String> loadOrganizationName() async => 'Circolo Serenità';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final generateScreenshots =
      Platform.environment['GENERATE_STORE_SCREENSHOTS'] == '1';

  testWidgets(
    'genera gli screenshot desktop per Microsoft Store',
    (tester) async {
      // Flutter Test usa Ahem, che rende ogni lettera come un quadrato: qua carichiamo
      // i font veri del motore prima de far le foto promozionali.
      await tester.runAsync(_loadStoreScreenshotFonts);
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _ScreenshotRepository();
      const locales = <String, Locale>{
        'it-IT': Locale('it'),
        'en-US': Locale('en'),
        'fr-FR': Locale('fr'),
        'de-DE': Locale('de'),
      };
      for (final entry in locales.entries) {
        await _captureLocalizedSet(
          tester,
          repository: repository,
          locale: entry.value,
          directory: entry.key,
        );
      }
    },
    skip: !generateScreenshots,
  );
}

Future<void> _captureLocalizedSet(
  WidgetTester tester, {
  required MemberRepository repository,
  required Locale locale,
  required String directory,
}) async {
  await tester.pumpWidget(
    RubricaAssociatiApp(repository: repository, locale: locale),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile(
      '../microsoft_store/screenshots/$directory/01-rubrica-desktop.png',
    ),
  );

  await tester.pumpWidget(
    RubricaAssociatiApp(
      locale: locale,
      home: MemberDetailScreen(member: _featuredMember, repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile(
      '../microsoft_store/screenshots/$directory/02-scheda-associato-desktop.png',
    ),
  );

  await tester.pumpWidget(
    RubricaAssociatiApp(
      locale: locale,
      home: const MemberFormScreen(member: _featuredMember),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile(
      '../microsoft_store/screenshots/$directory/03-modifica-associato-desktop.png',
    ),
  );
}

Future<void> _loadStoreScreenshotFonts() async {
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
