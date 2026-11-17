// Touch targets under the finger: a hit-test check at the corners of the 48 × 48 area, not by the size of the drawing,
// and that neighbouring areas do not overlap (section F of the gesture review of 2026-11-14; FR-R8).

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// Whether a touch at the point [p] hits the widget [finder] (or its descendant).
bool hits(WidgetTester tester, Finder finder, Offset p) {
  final target = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(p);
  for (final entry in result.path) {
    final t = entry.target;
    if (t is! RenderObject) continue;
    RenderObject? o = t;
    while (o != null) {
      if (o == target) return true;
      o = o.parent;
    }
  }
  return false;
}

/// A 48 × 48 area centred on the element is caught by the element: four points 2 dp from its corners (tolerance for
/// rounding). Returns the misses.
List<String> misses48(WidgetTester tester, Finder finder, String name) {
  expect(finder, findsOneWidget, reason: name);
  final c = tester.getCenter(finder);
  return [
    for (final d in const [Offset(-22, -22), Offset(22, -22), Offset(-22, 22), Offset(22, 22)])
      if (!hits(tester, finder, c + d)) '$name: a touch at ${d.dx.round()};${d.dy.round()} from the centre does not '
          'hit',
  ];
}

void expectTarget48(WidgetTester tester, Finder finder, String name) =>
    expect(misses48(tester, finder, name), isEmpty);

void expectNoOverlap(WidgetTester tester, Map<String, Finder> items) {
  final rects = {for (final e in items.entries) e.key: tester.getRect(e.value)};
  final names = rects.keys.toList();
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final a = rects[names[i]]!;
      final b = rects[names[j]]!;
      final x = a.intersect(b);
      expect(x.width <= 0.5 || x.height <= 0.5, isTrue, reason: '${names[i]} $a and ${names[j]} $b overlap');
    }
  }
}

void main() {
  for (final (size, scale, label) in const [(phone320, 1.3, '320 × 640 ×1,3'), (phone412, 1.0, '412 × 915')]) {
    testWidgets('player panel ($label): voice chip, “To current spot”, cross, speed, back, pause, forward, timer, '
        '“Stop” of the download row', (tester) async {
      final p = await pumpPrototype(tester, size: size, textScale: scale, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      // Turning pages myself makes “To current spot” appear; while downloading, the panel has a row with “Stop”.
      await swipe(tester, at(tester, 0.85, 0.3), Offset(-size.width * 0.6, 0), ms: 110);
      await advance(tester, const Duration(milliseconds: 800));
      p.downloads.demoShow(currentBook(tester), 1, failed: false);
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.playing);
      final items = <String, Finder>{
        'voice chip': find.byKey(const Key('voice-chip')),
        '“To current spot”': find.byKey(const Key('to-reading-place')),
        'cross': find.byKey(const Key('player-close')),
        'speed': find.byKey(const Key('speed')),
        'back': find.byKey(const Key('previous')),
        'pause': find.byKey(const Key('play-pause')),
        'forward': find.byKey(const Key('next')),
        'sleep timer': find.byKey(const Key('sleep')),
        '“Stop”': find.widgetWithText(TextButton, 'Стоп'),
      };
      expect([for (final e in items.entries) ...misses48(tester, e.value, e.key)], isEmpty,
          reason: 'FR-R8: the touch area of every control is at least 48 dp');
      expectNoOverlap(tester, items);
      // The panel is entirely on screen.
      final panel = tester.getRect(find.byKey(const Key('player-panel')));
      expect(panel.top, greaterThan(0));
      expect(panel.bottom, lessThanOrEqualTo(size.height + 0.5));
    });

    testWidgets('reading panels ($label): “Back”, table of contents, “Text appearance”, voice chip, “Listen”; the '
        'speed sheet and theme '
        'tiles', (tester) async {
      final p = await pumpPrototype(tester, size: size, textScale: scale, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      final bars = <String, Finder>{
        '“Back”': find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
        'table of contents': find.widgetWithIcon(IconButton, Icons.toc_rounded),
        '“Text appearance”': find.widgetWithIcon(IconButton, Icons.text_fields_rounded),
        'voice chip': find.byKey(const Key('voice-chip-idle')),
        '“Listen”': find.byKey(const Key('listen')),
      };
      for (final e in bars.entries) {
        expectTarget48(tester, e.value, e.key);
      }
      expectNoOverlap(tester, bars);

      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      final appearance = <String, Finder>{
        'smaller': find.byKey(const Key('font-smaller')),
        'larger': find.byKey(const Key('font-larger')),
        for (final t in ['system', 'light', 'sepia', 'dark']) 'theme $t': find.byKey(Key('theme-$t')),
      };
      for (final e in appearance.entries) {
        expectTarget48(tester, e.value, e.key);
      }
      expectNoOverlap(tester, appearance);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('speed')));
      await advance(tester, const Duration(milliseconds: 600));
      final speeds = <String, Finder>{
        for (final sp in ['0.75', '1.0', '1.25', '1.5', '1.75', '2.0']) 'speed $sp': find.byKey(Key('speed-$sp')),
      };
      for (final e in speeds.entries) {
        expectTarget48(tester, e.value, e.key);
      }
      expectNoOverlap(tester, speeds);
    });
  }

  testWidgets('320 × 640 ×1.3: “Read from here” is entirely on screen, above the player panel, and can be pressed by '
      'finger', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final frags = currentPage(tester).fragments;
    final st = reader(tester);
    // A long press on the lowest piece of the page — right next to the player panel.
    final f = frags.last;
    await tester.longPressAt(Offset(160, st.pagePadding.top + f.top + f.height - 6));
    await advance(tester, const Duration(milliseconds: 400));
    final button = find.byKey(const Key('read-from-here'));
    expect(button, findsOneWidget);
    final r = tester.getRect(button);
    final panel = tester.getRect(find.byKey(const Key('player-panel')));
    expect(r.bottom, lessThanOrEqualTo(panel.top), reason: 'the button is not under the player panel');
    expect(r.top, greaterThanOrEqualTo(0));
    expectTarget48(tester, button, '“Read from here”');
    await quickTap(tester, r.center);
    await advance(tester, const Duration(milliseconds: 300));
    expect(p.narration.unitStart, ReadingPosition(f.block, 0));
  });
}
