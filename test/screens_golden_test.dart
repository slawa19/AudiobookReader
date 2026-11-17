// Prototype screenshots → docs/prototype/screens/*.png.
// To regenerate: bash scripts/test.sh test/screens_golden_test.dart --update-goldens
// These are prototype screenshots for the owner to review, not the approved golden (that one is recorded after
// the screens are approved on the phone, AGENTS.md "Interface").

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('412×915', () {
    testWidgets('01 shelf', (tester) async {
      await pumpPrototype(tester);
      await snapshot(tester, '01-shelf');
    });

    testWidgets('02 empty shelf', (tester) async {
      final p = await pumpPrototype(tester);
      p.library.setDemoEmptyShelf(true);
      await settle(tester);
      await snapshot(tester, '02-shelf-empty');
    });

    testWidgets('03 shelf adding and rejections', (tester) async {
      final p = await pumpPrototype(tester);
      p.library.demoAddJob('broken');
      p.library.demoAddJob('unsupported');
      p.library.demoAddJob('adding');
      await advance(tester, const Duration(milliseconds: 900));
      await snapshot(tester, '03-shelf-adding');
    });

    testWidgets('04 book menu and 05 deletion', (tester) async {
      await pumpPrototype(tester);
      await tester.longPress(find.text('Война и мир'));
      await settle(tester);
      await snapshot(tester, '04-shelf-menu');
      await tester.tap(find.text('Удалить книгу'));
      await settle(tester);
      await snapshot(tester, '05-shelf-delete');
    });

    testWidgets('06 reading, chapter start', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await snapshot(tester, '06-reading-chapter-start');
    });

    testWidgets('06 reading, chapter middle', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await snapshot(tester, '06-reading');
    });

    testWidgets('07 reading with panels', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await settle(tester);
      await snapshot(tester, '07-reading-panels');
    });

    testWidgets('08 reading, image', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(43, 0));
      await snapshot(tester, '08-reading-image');
    });

    testWidgets('09 text appearance', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('theme-sepia')));
      await tester.tap(find.byKey(const Key('font-larger')));
      await settle(tester);
      await snapshot(tester, '09-appearance');
    });

    testWidgets('10 table of contents', (tester) async {
      final p = await pumpPrototype(tester);
      await openDama(tester, p, at: const ReadingPosition(180, 0));
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await settle(tester);
      await snapshot(tester, '10-contents');
    });

    testWidgets('11 table of contents, download in progress and error', (tester) async {
      final p = await pumpPrototype(tester);
      await openDama(tester, p, at: const ReadingPosition(180, 0));
      final book = currentBook(tester);
      p.downloads.demoShow(book, book.chapterOf(180), failed: false);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await settle(tester, animations: false);
      await snapshot(tester, '11-contents-downloading');
      p.downloads.demoShow(book, book.chapterOf(180), failed: true);
      await tester.pump(const Duration(milliseconds: 300));
      await snapshot(tester, '11-contents-download-failed');
    });

    testWidgets('12 footnote', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tester.tapAt(noteRefCenter(tester, 'n1'));
      await settle(tester);
      await snapshot(tester, '12-footnote');
    });

    testWidgets('13 read from here', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tester.longPressAt(blockCenter(tester, wholeParagraphOnPage(tester)));
      await settle(tester);
      await snapshot(tester, '13-read-from-here');
    });

    testWidgets('14 listening, 15 turning pages myself, 16 dark', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 3));
      await snapshot(tester, '14-listening');
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-300, 0), 1000);
      // "To reading place" appears once the page has settled after the gesture (a page change turns following off).
      await advance(tester, const Duration(milliseconds: 1200));
      await settle(tester, animations: false); // image on the new page
      await snapshot(tester, '15-listening-own-page');
      await tester.tap(find.byKey(const Key('to-reading-place')));
      await advance(tester, const Duration(milliseconds: 600));
      p.settings.theme = ThemeChoice.dark;
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, '16-listening-dark');
    });

    for (final (state, name) in const [
      ('preparing', '17-player-preparing'),
      ('waiting', '17-player-waiting'),
      ('sleep', '17-player-paused-sleep'),
      ('end', '17-player-end-of-book'),
      ('error402', '18-player-402'),
      ('error404', '18-player-404'),
      ('errorKey', '18-player-error-key'),
      ('errorOther', '18-player-error-other'),
    ]) {
      testWidgets('player: $state', (tester) async {
        final p = await pumpPrototype(tester);
        await openKapitanskaya(tester, p);
        p.narration.demoShow(state, book: currentBook(tester), fromBlock: 39);
        await advance(tester, const Duration(milliseconds: 600));
        await snapshot(tester, name);
      });
    }

    testWidgets('19 speed, 20 sleep timer', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 39);
      // The player panel is a new layer: taps are ignored for the first 350 ms (protection against a follow-up tap).
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('speed')));
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, '19-speed');
      await tester.tap(find.byKey(const Key('speed-1.25')));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, '20-sleep-timer');
    });

    testWidgets('21 voice', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 39);
      // The player panel is a new layer: taps are ignored for the first 350 ms (protection against a follow-up tap).
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('voice-chip')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('probe-Callirrhoe')));
      await advance(tester, const Duration(milliseconds: 1500));
      await snapshot(tester, '21-voice');
    });

    testWidgets('22 settings, 24 model, 25 clearing', (tester) async {
      await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await snapshot(tester, '22-settings');
      await tester.tap(find.byKey(const Key('settings-model')));
      await settle(tester);
      await snapshot(tester, '24-settings-model');
      await tester.tapAt(const Offset(200, 100));
      await settle(tester);
      await tester.tap(find.byKey(const Key('clear')));
      await settle(tester);
      await snapshot(tester, '25-settings-clear');
    });

    testWidgets('23 settings without a key', (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await settle(tester);
      await snapshot(tester, '23-settings-no-key');
    });

    testWidgets('26 download strip on the reading screen', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      p.downloads.demoShow(book, book.chapterOf(39), failed: false);
      await advance(tester, const Duration(milliseconds: 500));
      await snapshot(tester, '26-reading-download-strip');
    });

    testWidgets('27 app voice from settings', (tester) async {
      await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-voice')));
      await settle(tester);
      await snapshot(tester, '27-voice-app');
    });
  });

  group('320×640, font ×1,3', () {
    testWidgets('shelf', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await snapshot(tester, 'n320-01-shelf');
    });

    testWidgets('reading with panels, step 3', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tapCenter(tester);
      await settle(tester);
      await snapshot(tester, 'n320-07-reading-panels');
    });

    testWidgets('reading, step 6', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      p.settings.fontStep = fontSteps.length - 1;
      await openKapitanskaya(tester, p);
      await snapshot(tester, 'n320-06-reading-step6');
    });

    testWidgets('player playing (playing, sleep timer on), with panels', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.setSleepTimer(SleepTimer.minutes(30, p.narration.now().subtract(const Duration(minutes: 7))));
      p.narration.demoShow('playing', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.playing);
      await tapCenter(tester);
      await advance(tester, const Duration(milliseconds: 400));
      await snapshot(tester, 'n320-14-player');
    });

    testWidgets('"Text appearance" sheet', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await settle(tester);
      await snapshot(tester, 'n320-09-appearance');
    });

    testWidgets('sleep timer sheet, timer on', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 800));
      await snapshot(tester, 'n320-20-sleep-timer');
    });

    testWidgets('model sheet', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-model')));
      await settle(tester);
      await snapshot(tester, 'n320-24-model');
    });

    testWidgets('table of contents with a download', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openDama(tester, p, at: const ReadingPosition(180, 0));
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await settle(tester);
      await snapshot(tester, 'n320-10-contents');
    });

    testWidgets('voice selection', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-voice')));
      await settle(tester);
      await snapshot(tester, 'n320-27-voice');
    });

    testWidgets('player 402', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, 'n320-18-player-402');
    });

    testWidgets('settings', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await snapshot(tester, 'n320-22-settings');
    });
  });

  group('languages', () {
    for (final lang in ['en', 'pl', 'de', 'uk']) {
      testWidgets('$lang: shelf', (tester) async {
        await pumpPrototype(tester, locale: lang);
        await snapshot(tester, 'l10n-$lang-01-shelf');
      });

      testWidgets('$lang: reading with panels', (tester) async {
        final p = await pumpPrototype(tester, locale: lang);
        await openKapitanskaya(tester, p);
        await tapCenter(tester);
        await settle(tester);
        await snapshot(tester, 'l10n-$lang-07-reading-panels');
      });

      testWidgets('$lang: player and error 402', (tester) async {
        final p = await pumpPrototype(tester, locale: lang);
        await openKapitanskaya(tester, p);
        p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
        await advance(tester, const Duration(milliseconds: 600));
        await snapshot(tester, 'l10n-$lang-14-player');
        p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
        await advance(tester, const Duration(milliseconds: 600));
        await snapshot(tester, 'l10n-$lang-18-player-402');
      });

      testWidgets('$lang: settings', (tester) async {
        await pumpPrototype(tester, locale: lang);
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await settle(tester);
        await snapshot(tester, 'l10n-$lang-22-settings');
      });
    }

    testWidgets('de, 320×640 ×1,3: player with panels', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3, locale: 'de');
      await openKapitanskaya(tester, p);
      p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await tapCenter(tester);
      await advance(tester, const Duration(milliseconds: 400));
      await snapshot(tester, 'l10n-de-n320-14-player');
    });

    testWidgets('pl, 320×640 ×1,3: settings', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3, locale: 'pl');
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settle(tester);
      await snapshot(tester, 'l10n-pl-n320-22-settings');
    });

    testWidgets('uk, 320×640 ×1,3: player with panels', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3, locale: 'uk');
      await openKapitanskaya(tester, p);
      p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await tapCenter(tester);
      await advance(tester, const Duration(milliseconds: 400));
      await snapshot(tester, 'l10n-uk-n320-14-player');
    });

    testWidgets('uk, 320×640 ×1,3: settings', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3, locale: 'uk');
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settle(tester);
      await snapshot(tester, 'l10n-uk-n320-22-settings');
    });
  });

  group('360 and 393', () {
    testWidgets('360 shelf', (tester) async {
      await pumpPrototype(tester, size: phone360);
      await snapshot(tester, 'w360-01-shelf');
    });

    testWidgets('393 reading with panels', (tester) async {
      final p = await pumpPrototype(tester, size: phone393);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await settle(tester);
      await snapshot(tester, 'w393-07-reading-panels');
    });
  });
}
