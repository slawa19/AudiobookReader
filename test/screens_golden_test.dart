// Снимки экранов прототипа → docs/prototype/screens/*.png.
// Переснять: bash scripts/test.sh test/screens_golden_test.dart --update-goldens
// Это снимки прототипа для просмотра владельцем, а не утверждённый эталон (тот записывается после
// утверждения экранов на телефоне, AGENTS.md «Интерфейс»).

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('412×915', () {
    testWidgets('01 полка', (tester) async {
      await pumpPrototype(tester);
      await snapshot(tester, '01-shelf');
    });

    testWidgets('02 полка пустая', (tester) async {
      final p = await pumpPrototype(tester);
      p.library.setDemoEmptyShelf(true);
      await settle(tester);
      await snapshot(tester, '02-shelf-empty');
    });

    testWidgets('03 полка добавление и отказы', (tester) async {
      final p = await pumpPrototype(tester);
      p.library.demoAddJob('broken');
      p.library.demoAddJob('unsupported');
      p.library.demoAddJob('adding');
      await advance(tester, const Duration(milliseconds: 900));
      await snapshot(tester, '03-shelf-adding');
    });

    testWidgets('04 меню книги и 05 удаление', (tester) async {
      await pumpPrototype(tester);
      await tester.longPress(find.text('Война и мир'));
      await settle(tester);
      await snapshot(tester, '04-shelf-menu');
      await tester.tap(find.text('Удалить книгу'));
      await settle(tester);
      await snapshot(tester, '05-shelf-delete');
    });

    testWidgets('06 чтение, начало главы', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await snapshot(tester, '06-reading-chapter-start');
    });

    testWidgets('06 чтение, середина главы', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await snapshot(tester, '06-reading');
    });

    testWidgets('07 чтение с панелями', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await settle(tester);
      await snapshot(tester, '07-reading-panels');
    });

    testWidgets('08 чтение, картинка', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(43, 0));
      await snapshot(tester, '08-reading-image');
    });

    testWidgets('09 вид текста', (tester) async {
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

    testWidgets('10 оглавление', (tester) async {
      final p = await pumpPrototype(tester);
      await openDama(tester, p, at: const ReadingPosition(180, 0));
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await settle(tester);
      await snapshot(tester, '10-contents');
    });

    testWidgets('11 оглавление, скачивание идёт и ошибка', (tester) async {
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

    testWidgets('12 сноска', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tester.tapAt(noteRefCenter(tester, 'n1'));
      await settle(tester);
      await snapshot(tester, '12-footnote');
    });

    testWidgets('13 читать отсюда', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tester.longPressAt(blockCenter(tester, wholeParagraphOnPage(tester)));
      await settle(tester);
      await snapshot(tester, '13-read-from-here');
    });

    testWidgets('14 слушает, 15 листаю сам, 16 тёмная', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 3));
      await snapshot(tester, '14-listening');
      await tester.fling(find.byKey(const Key('page-area')), const Offset(-300, 0), 1000);
      await advance(tester, const Duration(milliseconds: 600));
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
      ('errorOther', '18-player-error-other'),
    ]) {
      testWidgets('плеер: $state', (tester) async {
        final p = await pumpPrototype(tester);
        await openKapitanskaya(tester, p);
        p.narration.demoShow(state, book: currentBook(tester), fromBlock: 39);
        await advance(tester, const Duration(milliseconds: 600));
        await snapshot(tester, name);
      });
    }

    testWidgets('19 скорость, 20 таймер сна', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('speed')));
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, '19-speed');
      await tester.tap(find.byKey(const Key('speed-1.25')));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, '20-sleep-timer');
    });

    testWidgets('21 голос', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('voice-chip')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('probe-Callirrhoe')));
      await advance(tester, const Duration(milliseconds: 1500));
      await snapshot(tester, '21-voice');
    });

    testWidgets('22 настройки, 24 модель, 25 очистка', (tester) async {
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

    testWidgets('23 настройки без ключа', (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byKey(const Key('listen')));
      await settle(tester);
      await snapshot(tester, '23-settings-no-key');
    });

    testWidgets('26 строка скачивания на экране чтения', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      p.downloads.demoShow(book, book.chapterOf(39), failed: false);
      await advance(tester, const Duration(milliseconds: 500));
      await snapshot(tester, '26-reading-download-strip');
    });

    testWidgets('27 голос приложения из настроек', (tester) async {
      await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-voice')));
      await settle(tester);
      await snapshot(tester, '27-voice-app');
    });
  });

  group('320×640, шрифт ×1,3', () {
    testWidgets('полка', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await snapshot(tester, 'n320-01-shelf');
    });

    testWidgets('чтение с панелями, ступень 3', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tapCenter(tester);
      await settle(tester);
      await snapshot(tester, 'n320-07-reading-panels');
    });

    testWidgets('чтение, ступень 6', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      p.settings.fontStep = fontSteps.length - 1;
      await openKapitanskaya(tester, p);
      await snapshot(tester, 'n320-06-reading-step6');
    });

    testWidgets('плеер играет', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await tapCenter(tester);
      await advance(tester, const Duration(milliseconds: 400));
      await snapshot(tester, 'n320-14-player');
    });

    testWidgets('плеер 402', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await snapshot(tester, 'n320-18-player-402');
    });

    testWidgets('настройки', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.tap(find.byTooltip('Настройки'));
      await settle(tester);
      await snapshot(tester, 'n320-22-settings');
    });
  });

  group('360 и 393', () {
    testWidgets('360 полка', (tester) async {
      await pumpPrototype(tester, size: phone360);
      await snapshot(tester, 'w360-01-shelf');
    });

    testWidgets('393 чтение с панелями', (tester) async {
      final p = await pumpPrototype(tester, size: phone393);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await settle(tester);
      await snapshot(tester, 'w393-07-reading-panels');
    });
  });
}
