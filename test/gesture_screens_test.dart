// Screens and transitions by finger: shelf, voice, settings, “Text appearance”, screen rotation (sections E and F of
// the gesture review of 2026-11-14).

import 'dart:io';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('shelf', () {
    testWidgets('a book tapped twice in a row (including with slow disk reads): a single reading screen is open',
        (tester) async {
      final p = await pumpPrototype(tester);
      p.library.loadDelay = const Duration(milliseconds: 300);
      final c = tester.getCenter(find.text('Капитанская дочка').first);
      await quickTap(tester, c);
      await frames(tester, 120);
      await quickTap(tester, c);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const Key('page-area')), findsOneWidget);
      // Aligned with decision J: in immersive reading the first Back shows the panels, the second closes the book.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(reader(tester).panelsVisible, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsNothing, reason: 'the book is closed — and the shelf: there is '
          'no second screen');
      expect(find.byKey(const Key('shelf-title')), findsOneWidget);
      // After returning, the book opens again.
      await quickTap(tester, tester.getCenter(find.text('Капитанская дочка').first));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsOneWidget);
    });

    testWidgets('scrolling the shelf and a tap after it; long press — menu, tap on the scrim — menu closed, the book '
        'is '
        'not opened', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.dragFrom(const Offset(160, 500), const Offset(0, -260));
      await tester.pumpAndSettle();
      final row = find.text('Мёртвые души');
      expect(row.hitTestable(), findsOneWidget);
      await tester.longPress(row);
      await tester.pumpAndSettle();
      expect(find.text('Удалить книгу'), findsOneWidget);
      await tester.tapAt(const Offset(160, 60));
      await tester.pumpAndSettle();
      expect(find.text('Удалить книгу'), findsNothing);
      expect(find.byKey(const Key('page-area')), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsOneWidget);
    });
  });

  group('voice', () {
    testWidgets('consecutive probes, a choice during a probe, scrolling to the last voice, leaving during a '
        'probe', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-voice')));
      await tester.pumpAndSettle();

      await quickTap(tester, tester.getCenter(find.byKey(const Key('probe-Achernar'))));
      await frames(tester, 300);
      expect(p.sampler.voice, 'Achernar');
      await quickTap(tester, tester.getCenter(find.byKey(const Key('probe-Autonoe'))));
      await frames(tester, 300);
      expect(p.sampler.voice, 'Autonoe', reason: 'a new probe replaces the previous one');
      expect(p.sampler.state, SampleState.loading);

      // Choosing another voice during a probe: the voice is selected, the probe is not interrupted.
      await quickTap(tester, tester.getCenter(find.text('Callirrhoe')));
      await frames(tester, 100);
      expect(p.settings.voice, 'Callirrhoe');
      expect(p.sampler.voice, 'Autonoe');

      // Tapping “Probe” of the playing voice again stops it.
      await frames(tester, 900);
      expect(p.sampler.state, SampleState.playing);
      await quickTap(tester, tester.getCenter(find.byKey(const Key('probe-Autonoe'))));
      await frames(tester, 100);
      expect(p.sampler.voice, isNull);

      // Scrolling by finger to the last voice and its probe.
      final last = find.byKey(const Key('probe-Zubenelgenubi'));
      await tester.dragUntilVisible(last, find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(last);
      await frames(tester, 200);
      expect(p.sampler.voice, 'Zubenelgenubi');

      // Leaving the screen during a probe stops it.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(p.sampler.voice, isNull);
      expect(p.sampler.state, SampleState.idle);
      expect(find.byKey(const Key('settings-voice')), findsOneWidget);
      expect(find.textContaining('Callirrhoe'), findsOneWidget, reason: 'settings show the selected voice');
    });
  });

  group('settings: the key field (FR-P7)', () {
    testWidgets('“Listen” without a key → the key is entered in the field → the system Back: the key is '
        'saved', (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key-field')), findsOneWidget);
      // The reader pasted the key into the field (long press → “Paste” of the system menu or a keyboard suggestion) and
      // went back to the book. There is no separate “Done” button on the screen — only the keyboard action.
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-typed-key-0000');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsOneWidget, reason: 'precondition: back in the book');
      expect(p.settings.hasApiKey, isTrue,
          reason: 'the entered key must not silently disappear: otherwise “Listen” leads to settings again without '
              'explanation');
    });

    testWidgets('“Change” → a very long value and the keyboard action “Done”: the key is saved, the field is closed, '
        'the tail is four characters', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('key-change')));
      await tester.pumpAndSettle();
      final long = '${'A' * 600}wxyz';
      await tester.enterText(find.byKey(const Key('key-field')), long);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(p.settings.hasApiKey, isTrue);
      expect(p.settings.apiKeyTail, 'wxyz');
      expect(find.byKey(const Key('key-field')), findsNothing);
      expect(find.textContaining('wxyz'), findsOneWidget);
      expect(find.textContaining('AAAA'), findsNothing, reason: 'the key is not shown on screen');
    });
  });

  group('“Text appearance” (FR-R6, FR-R7)', () {
    testWidgets('fast size presses back and forth with a theme change between them: the reading position is the same '
        'block and offset, '
        'the page is the same', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(60, 300));
      final page0 = currentPage(tester);
      final first = ReadingPosition(page0.firstBlock, page0.firstOffset);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      final larger = tester.getCenter(find.byKey(const Key('font-larger')));
      final smaller = tester.getCenter(find.byKey(const Key('font-smaller')));
      for (var i = 0; i < 3; i++) {
        await quickTap(tester, larger);
        await frames(tester, 32);
        expect(currentPage(tester).contains(60, 300), isTrue, reason: 'larger, step ${i + 1}');
      }
      await quickTap(tester, tester.getCenter(find.byKey(const Key('theme-dark'))));
      await frames(tester, 32);
      expect(currentPage(tester).contains(60, 300), isTrue, reason: 'theme change');
      for (var i = 0; i < 5; i++) {
        await quickTap(tester, smaller);
        await frames(tester, 32);
        expect(currentPage(tester).contains(60, 300), isTrue, reason: 'smaller, step ${i + 1}');
      }
      for (var i = 0; i < 2; i++) {
        await quickTap(tester, larger);
        await frames(tester, 32);
      }
      await tester.pumpAndSettle();
      expect(p.settings.fontStep, defaultFontStep);
      expect(p.settings.theme, ThemeChoice.dark);
      final page1 = currentPage(tester);
      expect(ReadingPosition(page1.firstBlock, page1.firstOffset), first,
          reason: 'back to the previous size — the page starts in the same place');
      // The sheet is swiped down; the panels stay, the page is the same.
      final sheet = tester.getRect(find.byKey(const Key('appearance-sheet')));
      await swipe(tester, Offset(sheet.center.dx, sheet.top + 10), const Offset(0, 400), ms: 200);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearance-sheet')), findsNothing);
      expect(reader(tester).panelsVisible, isTrue);
      expect(ReadingPosition(currentPage(tester).firstBlock, currentPage(tester).firstOffset), first);
    });
  });

  group('screen rotation (FR-R7, FR-R8)', () {
    testWidgets('rotating to landscape and back: the reading position is the same', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(60, 300));
      final page0 = currentPage(tester);
      final first = ReadingPosition(page0.firstBlock, page0.firstOffset);
      tester.view.physicalSize = const Size(915, 412) * snapshotDpr;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(currentPage(tester).contains(60, 300), isTrue, reason: 'after the rotation the screen shows the same '
          'position (FR-R7)');
      tester.view.physicalSize = phone412 * snapshotDpr;
      await tester.pumpAndSettle();
      final page1 = currentPage(tester);
      expect(ReadingPosition(page1.firstBlock, page1.firstOffset), first);
    });

    // Replaced per decision F of the gesture review: the first version is portrait orientation only. There used to be a
    // test "landscape orientation with a side cutout: the text does not go under the cutout" — there is no landscape in
    // the first version (spec 001, "Out of scope").
    testWidgets('landscape is not enabled: the app asks the system for portrait only, the same in the manifest',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpPrototype(tester);
      final orientation = calls.where((c) => c.method == 'SystemChrome.setPreferredOrientations').toList();
      expect(orientation, isNotEmpty, reason: 'the app locks the orientation at startup');
      expect(orientation.last.arguments, ['DeviceOrientation.portraitUp']);
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:screenOrientation="portrait"'));
    });
  });
}
