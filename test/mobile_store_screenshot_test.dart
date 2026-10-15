import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';

import 'store_screenshot_fixture.dart';

const _locales = <String, Locale>{
  'it-IT': Locale('it'),
  'en-US': Locale('en'),
  'fr-FR': Locale('fr'),
  'de-DE': Locale('de'),
};

const _stores = <_MobileStore>[
  _MobileStore(
    directory: 'app_store/screenshots',
    physicalSize: Size(1242, 2688),
  ),
  // iPad Pro 13": obbligatorio perché l'app supporta anche iPad.
  _MobileStore(
    directory: 'app_store/screenshots_ipad',
    physicalSize: Size(2064, 2752),
    pixelRatio: 2,
  ),
  _MobileStore(
    directory: 'play_store/graphics/phone-screenshots',
    physicalSize: Size(1242, 2484),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final generateScreenshots =
      Platform.environment['GENERATE_STORE_SCREENSHOTS'] == '1';

  testWidgets('genera gli screenshot mobili localizzati per App Store e Play', (
    tester,
  ) async {
    await tester.runAsync(loadStoreScreenshotFonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final store in _stores) {
      tester.view.physicalSize = store.physicalSize;
      tester.view.devicePixelRatio = store.pixelRatio;
      for (final locale in _locales.entries) {
        final featuredMember = storeFeaturedMemberFor(locale.key);
        await _captureLocalizedSet(
          tester,
          repository: StoreScreenshotRepository(
            organizationName: _organizationNames[locale.key]!,
          ),
          locale: locale.value,
          directory: '${store.directory}/${locale.key}',
          featuredMember: featuredMember,
          pixelRatio: store.pixelRatio,
        );
      }
    }
  }, skip: !generateScreenshots);
}

const _organizationNames = <String, String>{
  'it-IT': 'Circolo Aurora',
  'en-US': 'Aurora Community Club',
  'fr-FR': 'Association Aurore',
  'de-DE': 'Verein Aurora',
};

const _screenshotKey = Key('store-screenshot');

Future<void> _captureLocalizedSet(
  WidgetTester tester, {
  required MemberRepository repository,
  required Locale locale,
  required String directory,
  required Member featuredMember,
  required double pixelRatio,
}) async {
  await _pumpScreenshot(
    tester,
    app: RubricaAssociatiApp(repository: repository, locale: locale),
    path: '$directory/home.png',
    pixelRatio: pixelRatio,
    // Su iPad lista e scheda stanno affiancate: mostra un socio selezionato.
    afterPump: pixelRatio == 2
        ? () async {
            await tester.tap(find.byType(ListTile).first);
            await tester.pumpAndSettle();
          }
        : null,
  );

  await _pumpScreenshot(
    tester,
    app: RubricaAssociatiApp(
      locale: locale,
      home: MemberDetailScreen(member: featuredMember, repository: repository),
    ),
    path: '$directory/detail.png',
    pixelRatio: pixelRatio,
  );

  await _pumpScreenshot(
    tester,
    app: RubricaAssociatiApp(
      locale: locale,
      home: MemberFormScreen(member: featuredMember),
    ),
    path: '$directory/form.png',
    pixelRatio: pixelRatio,
  );
}

Future<void> _pumpScreenshot(
  WidgetTester tester, {
  required Widget app,
  required String path,
  required double pixelRatio,
  Future<void> Function()? afterPump,
}) async {
  await tester.pumpWidget(RepaintBoundary(key: _screenshotKey, child: app));
  await tester.pumpAndSettle();
  if (afterPump != null) await afterPump();

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenshotKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    expect(image.width, tester.view.physicalSize.width.toInt());
    expect(image.height, tester.view.physicalSize.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Impossibile codificare $path');

    // Qua se scrive el rendering vero dell'app, senza cornici o testi sovrapposti.
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  });
}

class _MobileStore {
  const _MobileStore({
    required this.directory,
    required this.physicalSize,
    this.pixelRatio = 3,
  });

  final String directory;
  final Size physicalSize;
  final double pixelRatio;
}
