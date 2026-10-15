import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/models/member_filter.dart';

import 'store_screenshot_fixture.dart';

class _Repo extends MemberRepository {
  @override
  Future<List<Member>> search(String q) async => const [
    Member(
      id: 1,
      firstName: 'A',
      lastName: 'B',
      phone: '1',
      memberNumber: '1',
      notes: '',
    ),
  ];
  @override
  Future<String> loadOrganizationName() async => 'Centro';
  @override
  Future<Set<int>> membersNotInBook() async => const {};
}

/// Le etichette dei tre filtri principali devono stare intere su un telefono
/// stretto (360 px) a testo normale: niente puntini di sospensione.
void main() {
  for (final lang in ['it', 'en', 'fr', 'de']) {
    for (final width in [360.0, 320.0]) {
      testWidgets('filtri senza troncamento ($lang, $width px)', (
        tester,
      ) async {
        // Font veri (Roboto): con quello di prova le lettere sono quadrati.
        await tester.runAsync(loadStoreScreenshotFonts);
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RubricaAssociatiApp(locale: Locale(lang), repository: _Repo()),
        );
        await tester.pumpAndSettle();
        final texts = find.descendant(
          of: find.byType(SegmentedButton<MemberFilter>),
          matching: find.byType(Text),
        );
        expect(texts, findsNWidgets(3));
        for (final e in texts.evaluate()) {
          final p = tester.renderObject<RenderParagraph>(
            find.byWidget(e.widget),
          );
          expect(p.didExceedMaxLines, isFalse, reason: (e.widget as Text).data);
          final line = p.getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: p.text.toPlainText().length,
            ),
          );
          expect(line, isNotEmpty);
        }
      });
    }
  }
}
