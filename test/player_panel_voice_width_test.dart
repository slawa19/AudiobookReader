import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_panel_layout_test.dart' show panelApp;

void main() {
  final longestName = allVoices.map((voice) => voice.name).reduce((a, b) => a.length >= b.length ? a : b);

  for (final voiceName in [longestName, 'Aoede']) {
    testWidgets('411 dp: ширина чипа голоса $voiceName без подписи состояния', (tester) async {
      final h = await panelApp(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 900);
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 48);
      h.app.settings.voice = 'Aoede';
      await tester.pumpAndSettle();
      final chip = find.byKey(const Key('voice-chip'));
      final shortWidth = tester.getSize(chip).width;
      final panel = tester.getRect(find.byKey(const Key('player-panel')));
      final close = tester.getRect(find.byKey(const Key('player-close')));
      await tester.drag(find.byKey(const Key('page-area')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      final back = tester.getRect(find.byKey(const Key('to-reading-place')));

      h.app.settings.voice = voiceName;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-status')), findsNothing);
      expect(tester.getRect(find.byKey(const Key('player-panel'))), panel);
      expect(tester.getRect(find.byKey(const Key('player-close'))), close);
      expect(tester.getRect(find.byKey(const Key('to-reading-place'))), back);
      if (voiceName == 'Aoede') {
        // Прежняя ширина: отступы панели 12 + 8, два значка по 48 dp.
        expect(shortWidth, closeTo((411 - 20 - 96) * 0.55, 0.001));
        expect(tester.getSize(chip).width, shortWidth);
      } else {
        final text = find.descendant(of: chip, matching: find.text(voiceName));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        final naturalWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
        expect(paragraph.size.width, greaterThanOrEqualTo(naturalWidth),
            reason: '$voiceName должен помещаться целиком');
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
