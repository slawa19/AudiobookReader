// Правила a–k (приняты владельцем 2026-11-14) по пробелам документов, найденным проверкой путей пользователя
// 2026-11-14 (docs/reviews/JOURNEY_AUDIT_2026-11-14.md), и две непроверенные проверяющим гипотезы. Находки
// проверяющего — в journey_listening_test.dart, journey_shelf_test.dart, journey_download_test.dart.

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/screens/settings_screen.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'journey_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

Future<void> flingNext(WidgetTester tester) async {
  await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
  await advance(tester, const Duration(milliseconds: 800));
}

Future<void> toShelf(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byTooltip('Назад'));
  await tester.pumpAndSettle();
  await settle(tester);
}

void main() {
  group('листание', () {
    testWidgets('второе касание правой трети через 40 мс после первого не теряется: +2 страницы', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = reader(tester).page;
      final size = tester.getSize(find.byKey(const Key('page-area')));
      await tester.tapAt(Offset(size.width * 0.9, size.height / 2));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(Offset(size.width * 0.9, size.height / 2));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2);
    });
  });

  group('скорость (FR-P5)', () {
    testWidgets('сохранённая скорость 1,5× — прослушивание сразу идёт с ней', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      p.settings.speed = 1.5;
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      expect(p.narration.speed, 1.5);
      expect(find.text('1,5×'), findsOneWidget);
      // Не только подпись: голос и движется со скоростью 1,5 (№8 ревью логики).
      final block = p.narration.block!;
      final before = p.narration.blockProgress;
      await advance(tester, const Duration(milliseconds: 500));
      if (p.narration.block == block) {
        final seconds = currentBook(tester).blocks[block].text.length * secondsPerChar / 1.5;
        expect(p.narration.blockProgress - before, closeTo(0.5 / (seconds < 1.6 ? 1.6 : seconds), 0.003));
      }
    });
  });

  group('a. следование включают действия, меняющие место звука', () {
    Future<void> listeningFlipped(WidgetTester tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      expect(reader(tester).following, isFalse, reason: 'предусловие: листал сам');
    }

    testWidgets('листал сам → «вперёд»: следование включено', (tester) async {
      await listeningFlipped(tester);
      await tester.tap(find.byKey(const Key('next')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue);
    });

    testWidgets('листал сам → «назад»: следование включено', (tester) async {
      await listeningFlipped(tester);
      await tester.tap(find.byKey(const Key('previous')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
    });

    testWidgets('пауза → листал сам → «Слушать» на панели: следование включено', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      await flingNext(tester);
      expect(reader(tester).following, isFalse, reason: 'предусловие');
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(p.narration.state, NarrationState.playing);
      expect(reader(tester).following, isTrue);
      expect(find.byKey(const Key('to-reading-place')), findsNothing);
    });

    testWidgets('ошибка → листал сам → «Слушать» в панели ошибки: следование включено', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      p.narration.demoShow('error402');
      await advance(tester, const Duration(milliseconds: 600));
      await flingNext(tester);
      // Не вакуумно: листание при открытой панели ошибки следование выключило (№1 ревью логики).
      expect(reader(tester).following, isFalse, reason: 'предусловие: листал сам после остановки');
      await tester.tap(find.byKey(const Key('error-listen')));
      await advance(tester, const Duration(seconds: 2));
      expect(p.narration.isActive, isTrue);
      expect(reader(tester).following, isTrue);
      final at = reader(tester).soundingPosition!;
      expect(onScreen(tester, at.block, at.offset), isTrue, reason: 'экран вернулся к голосу');
    });

    testWidgets('оглавление во время прослушивания: та же глава — голос к её началу', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      final book = currentBook(tester);
      final chapter = book.chapterOf(p.narration.block!);
      await tapCenter(tester);
      await chooseChapter(tester, book.chapters[chapter].title);
      expect(p.narration.block, greaterThanOrEqualTo(book.chapters[chapter].firstBlock));
      expect(p.narration.block, lessThan(book.chapters[chapter].firstBlock + 3), reason: 'голос у начала главы');
      expect(reader(tester).following, isTrue);
    });
  });

  group('b. перераскладка без следования', () {
    testWidgets('листал сам во время звука → крупнее шрифт: на экране прежнее начало страницы, не место голоса',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await flingNext(tester);
      await flingNext(tester);
      final st = reader(tester);
      final shown = st.layout.pages[st.page];
      final top = ReadingPosition(shown.firstBlock, shown.firstOffset);
      st.widget.services.settings.fontStep = st.widget.services.settings.fontStep + 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(reader(tester).following, isFalse);
      expect(onScreen(tester, top.block, top.offset), isTrue);
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('c. таймер сна', () {
    testWidgets('выход на полку снимает таймер; снова в книгу — «Слушать» без таймера', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-30')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer, isNotNull);
      await toShelf(tester);
      expect(p.narration.sleepTimer, isNull);
      // Снова в книгу и «Слушать»: звук идёт, на панели нет таймера.
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 1));
      expect(p.narration.state, NarrationState.playing);
      expect(p.narration.sleepTimer, isNull);
      expect(find.byIcon(Icons.bedtime_rounded), findsNothing, reason: 'значок включённого таймера не горит');
    });

    testWidgets('«до конца главы» из листа: пауза на первом абзаце следующей главы, таймер снят', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p);
      final book = currentBook(tester);
      final chapter = book.chapterOf(39);
      await listenFromPanel(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('sleep-chapter')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.kind, SleepKind.endOfChapter);
      var guard = 0;
      while (p.narration.state != NarrationState.paused && guard++ < 1200) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(p.narration.state, NarrationState.paused);
      expect(book.chapterOf(p.narration.block!), chapter + 1, reason: 'остановился на начале следующей главы');
      expect(p.narration.sleepTimer, isNull);
    });

    testWidgets('срок истёк в «Жду связь…» — пауза, таймер снят', (tester) async {
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.setSleepTimer(SleepTimer.minutes(15, p.narration.now()));
      p.narration.demoShow('waiting');
      await advance(tester, const Duration(milliseconds: 300));
      clock.forward(const Duration(minutes: 16));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.state, NarrationState.paused);
      expect(p.narration.sleepTimer, isNull);
    });

    testWidgets('смена места в той же книге («вперёд») таймер не снимает; смена книги — снимает', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.setSleepTimer(SleepTimer.minutes(30, p.narration.now()));
      await tester.tap(find.byKey(const Key('next')));
      await advance(tester, const Duration(milliseconds: 500));
      expect(p.narration.sleepTimer?.minutes, 30);
      final dama = await p.library.loadBook('dama');
      p.narration.readFrom(dama, 40);
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.bookId, 'dama');
      expect(p.narration.sleepTimer, isNull);
    });

    testWidgets('срок истёк в «Готовлю голос…» — пауза, таймер снят', (tester) async {
      final clock = TestClock();
      final p = await pumpWithClock(tester, clock);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.setSleepTimer(SleepTimer.minutes(15, p.narration.now()));
      p.narration.demoShow('preparing');
      await advance(tester, const Duration(milliseconds: 300));
      clock.forward(const Duration(minutes: 16));
      await advance(tester, const Duration(milliseconds: 300));
      expect(p.narration.state, NarrationState.paused);
      expect(p.narration.sleepTimer, isNull);
    });
  });

  group('d. дочитанная книга', () {
    testWidgets('дослушал до конца → «Закрыть» → полка: 100 %; назад на две страницы → не 100 %', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 40);
      await openKapitanskaya(tester, p, at: const ReadingPosition(99, 0));
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 10));
      expect(p.narration.stopReason, StopReason.endOfBook, reason: 'предусловие');
      await tester.tap(find.byKey(const Key('player-close')));
      await advance(tester, const Duration(milliseconds: 600));
      expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1));
      await toShelf(tester);
      expect(shelfProgress(ru, p.library.entry('kapitanskaya').fraction), shelfProgress(ru, 1));
      await openKapitanskaya(tester, p);
      await tapLeftThird(tester);
      await tapLeftThird(tester);
      await toShelf(tester);
      expect(p.library.entry('kapitanskaya').fraction, lessThan(1));
    });
  });

  group('e. полка', () {
    testWidgets('ни разу не открытые — первыми под карточкой, новые сверху', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Добавить книгу'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-ok')));
      await advance(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final belkin = tester.getTopLeft(find.text('Повести Белкина')).dy;
      final voyna = tester.getTopLeft(find.text('Война и мир')).dy;
      final dama = tester.getTopLeft(find.text('Дама с собачкой. Рассказы')).dy;
      final card = tester.getTopLeft(find.text('Капитанская дочка')).dy;
      expect(card < belkin && belkin < voyna && voyna < dama, isTrue,
          reason: 'карточка → новая «Повести Белкина» → неоткрытая «Война и мир» → открывавшиеся');
      expect(p.library.entry('belkin').opened, isFalse);
    });
  });

  group('f. системная «Назад»', () {
    // Правило f заменено решением J проверки жестов 2026-11-14 (краевой жест Android — это «Назад»): панели скрыты —
    // «Назад» их показывает; показаны — закрывает книгу. Было: «панели открыты → прячет; второе — закрывает».
    testWidgets('панели скрыты → «Назад» показывает панели; панели показаны → «Назад» закрывает книгу', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      expect(reader(tester).panelsVisible, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget, reason: 'случайный краевой жест книгу не закрывает');
      expect(reader(tester).panelsVisible, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
    });
  });

  group('g. «Скачать главу»', () {
    Future<void> openToc(WidgetTester tester) async {
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
    }

    testWidgets('скачивание главы II идёт, читатель перешёл в главу III: блок хода — у главы II, предложения нет',
        (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await openToc(tester);
      await tester.tap(find.byKey(const Key('download-start')));
      await advance(tester, const Duration(seconds: 2));
      await tester.tap(find.text('Глава III. Крепость'));
      await tester.pumpAndSettle();
      expect(reader(tester).layout.pages[reader(tester).page].chapter, 2);
      await openToc(tester);
      expect(find.byKey(const Key('download-stop')), findsOneWidget, reason: 'ход задачи виден');
      expect(find.byKey(const Key('download-start')), findsNothing, reason: 'пока задача идёт, второй не предлагают');
      final stop = tester.getTopLeft(find.byKey(const Key('download-stop'))).dy;
      expect(stop, greaterThan(tester.getTopLeft(find.text('Глава II. Вожатый')).dy));
      expect(stop, lessThan(tester.getTopLeft(find.text('Глава III. Крепость')).dy), reason: 'блок — у главы II');
    });

    testWidgets('смена голоса книги останавливает задачу; у текущей главы — предложение с новой оценкой',
        (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await openToc(tester);
      await tester.tap(find.byKey(const Key('download-start')));
      await advance(tester, const Duration(seconds: 10));
      expect(p.downloads.task!.fraction, greaterThan(0.1), reason: 'предусловие: часть главы готова');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final book = currentBook(tester);
      final chapter = book.chapterOf(39);
      final remainder = p.downloads.estimate(book, chapter, p.downloads.profileFor('kapitanskaya')).seconds;
      // Панели после оглавления ещё открыты.
      await tester.tap(find.byKey(const Key('voice-chip-idle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice-Kore')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(p.downloads.task, isNull, reason: 'задача прежнего голоса остановлена');
      final kore = p.downloads.estimate(book, chapter, p.downloads.profileFor('kapitanskaya')).seconds;
      expect(kore, greaterThan(remainder), reason: 'для нового голоса оценка — вся глава, а не остаток прежнего');
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download-start')), findsOneWidget);
    });
  });

  group('h. неверный ключ', () {
    testWidgets('отказ по ключу: пояснение, «Изменить ключ» → поле ключа; «Назад» — в книгу', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('errorKey', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text(ru.errorKeyTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('change-key')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('key-field')), findsOneWidget, reason: 'поле ключа открыто, хотя ключ сохранён');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(p.settings.hasApiKey, isTrue);
    });
  });

  group('i. «Книга закончилась»', () {
    testWidgets('в панели только «Закрыть»', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('end', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text(ru.endOfBook), findsOneWidget);
      expect(find.byKey(const Key('player-close')), findsOneWidget);
      for (final k in ['play-pause', 'next', 'previous', 'error-listen', 'voice-chip']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });
  });

  group('j. касание уже выбранного', () {
    testWidgets('пауза → настройки → модель → та же модель: место паузы не сбрасывается', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      await advance(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('play-pause')));
      await advance(tester, const Duration(milliseconds: 300));
      final block = p.narration.block;
      final progress = p.narration.blockProgress;
      expect(progress, greaterThan(0.05), reason: 'предусловие');
      tester.state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: p.services)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-flash')));
      await tester.pumpAndSettle();
      expect(p.narration.block, block);
      expect(p.narration.blockProgress, closeTo(progress, 0.001));
    });
  });

  group('k. «Готовлю голос…»', () {
    testWidgets('«Готовлю голос…» + листал сам: подпись отдельной строкой, чип голоса и «К месту чтения»',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await listenFromPanel(tester);
      p.narration.demoShow('preparing');
      await advance(tester, const Duration(milliseconds: 400));
      await flingNext(tester);
      expect(find.byKey(const Key('player-status')), findsOneWidget);
      expect(find.text(ru.preparing), findsOneWidget);
      expect(find.byKey(const Key('voice-chip')), findsOneWidget);
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
      await tester.tap(find.byKey(const Key('to-reading-place')));
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
    });
  });
}
