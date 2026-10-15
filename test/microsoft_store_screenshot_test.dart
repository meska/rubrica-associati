import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';

import 'store_screenshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final generateScreenshots =
      Platform.environment['GENERATE_STORE_SCREENSHOTS'] == '1';

  testWidgets('genera gli screenshot desktop per Microsoft Store', (
    tester,
  ) async {
    // Flutter Test usa Ahem, che rende ogni lettera come un quadrato: qua carichiamo
    // i font veri del motore prima de far le foto promozionali.
    await tester.runAsync(loadStoreScreenshotFonts);
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = StoreScreenshotRepository();
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
  }, skip: !generateScreenshots);
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
  // Su desktop lista e scheda sono affiancate: seleziona il primo socio.
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(Scaffold).first,
    matchesGoldenFile(
      '../microsoft_store/screenshots/$directory/01-rubrica-desktop.png',
    ),
  );

  await tester.pumpWidget(
    RubricaAssociatiApp(
      locale: locale,
      home: MemberDetailScreen(
        member: storeFeaturedMember,
        repository: repository,
      ),
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
      home: MemberFormScreen(member: storeFeaturedMember),
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
