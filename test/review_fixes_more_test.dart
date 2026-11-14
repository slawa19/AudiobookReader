// Тесты на остальные находки ревью Codex 2026-11-14 (docs/reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md).
// №6, №7 и №21 — в pagination_test.dart; №1, 2, 3, 5, 11, 12 — в review_fixes_test.dart.

import 'package:audiobook_reader/app/theme.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// Низ колонки текста на экране.
double textBottom(WidgetTester tester) => reader(tester).pagePadding.top + reader(tester).columnSize.height;

Future<void> startListening(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byKey(const Key('listen')));
  await advance(tester, const Duration(seconds: 2));
}

void main() {
  testWidgets('№4: «Закрыть» — сеанс завершён, позиция экрана записана и больше не переписывается', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 40);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final st = reader(tester);
    final shown = st.layout.pages[st.page];
    final onScreen = ReadingPosition(shown.firstBlock, shown.firstOffset);
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(seconds: 3));
    expect(p.narration.state, NarrationState.idle);
    expect(p.library.positionOf('kapitanskaya'), onScreen);
  });

  testWidgets('№8: «Читать отсюда» у абзаца длиннее страницы — в видимой части, не под плеером', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
    p.settings.fontStep = fontSteps.length - 1;
    await openKapitanskaya(tester, p);
    p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 39);
    await advance(tester, const Duration(milliseconds: 600));
    final st = reader(tester);
    final f = st.layout.pages[st.page].fragments.first;
    await tester.longPressAt(Offset(160, st.pagePadding.top + f.top + f.height / 2));
    await advance(tester, const Duration(milliseconds: 600));
    final button = tester.getRect(find.byKey(const Key('read-from-here')));
    final panel = tester.getRect(find.byKey(const Key('player-panel')));
    expect(button.top, greaterThanOrEqualTo(0));
    expect(button.bottom, lessThanOrEqualTo(panel.top), reason: 'кнопка не под панелью плеера');
  });

  testWidgets('№9: «К месту чтения» — внутри панели плеера и не перекрывает текст', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tester.fling(find.byKey(const Key('page-area')), const Offset(-250, 0), 1200);
    await advance(tester, const Duration(seconds: 1));
    final button = find.byKey(const Key('to-reading-place'));
    expect(find.descendant(of: find.byKey(const Key('player-panel')), matching: button), findsOneWidget);
    expect(tester.getRect(button).top, greaterThanOrEqualTo(textBottom(tester)));
  });

  for (final (name, open) in <(String, Future<void> Function(WidgetTester))>[
    ('вид текста', (t) async {
      await tapCenter(t);
      await t.tap(find.byTooltip('Вид текста'));
    }),
    ('таймер сна активный', (t) async {
      await t.tap(find.byKey(const Key('sleep')));
    }),
  ]) {
    testWidgets('№10: лист «$name» на 320×640 ×1,3 не переполняется', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openKapitanskaya(tester, p);
      p.narration.demoShow('sleep', book: currentBook(tester), fromBlock: 39);
      await advance(tester, const Duration(milliseconds: 600));
      await open(tester);
      await advance(tester, const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  }

  testWidgets('№13: смахивание во время автоматического перелистывания — пользовательское', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final st = reader(tester);
    final start = st.page;
    // Автоматический переход ещё идёт, а пользователь уже тянет страницу обратно.
    st.goToPage(start + 1, user: false);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.fling(find.byKey(const Key('page-area')), const Offset(300, 0), 1500);
    await advance(tester, const Duration(seconds: 1));
    expect(st.following, isFalse, reason: 'жест пользователя отключает следование');
    expect(p.narration.state, NarrationState.playing);
  });

  testWidgets('№14: голос книги выбирается и до первого прослушивания', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    await tester.pumpAndSettle();
    expect(p.narration.state, NarrationState.idle);
    await tester.tap(find.byKey(const Key('voice-chip-idle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-Kore')));
    await tester.pump();
    expect(p.library.bookVoice('kapitanskaya'), 'Kore');
  });

  testWidgets('№15: название главы только в шапке и переносится; в плеере и над ползунком его нет', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    final chapter = tester.widget<Text>(find.byKey(const Key('top-bar-chapter')));
    expect(chapter.maxLines, isNull);
    expect(chapter.overflow, isNot(TextOverflow.ellipsis));
    expect(find.descendant(of: find.byKey(const Key('player-panel')), matching: find.text(chapter.data!)), findsNothing);
  });

  testWidgets('№16: знак сноски ловится в области 48×48', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
    final c = noteRefCenter(tester, 'n1');
    // 20 dp справа от знака — меньше половины цели 48: сноска открывается.
    await tester.tapAt(c + const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-sheet')), findsOneWidget);
  });

  testWidgets('№16: кнопка «Проба» не ниже 48 dp', (tester) async {
    final p = await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-voice')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('probe-Achernar'))).height, greaterThanOrEqualTo(48));
    expect(p.narration.state, NarrationState.idle);
  });

  testWidgets('№17: в сепии «озвучена» у выбранной главы — основным цветом текста', (tester) async {
    final p = await pumpPrototype(tester);
    p.settings.theme = ThemeChoice.sepia;
    await openDama(tester, p, at: const ReadingPosition(5, 0));
    await tapCenter(tester);
    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    final mark = find.descendant(of: find.byKey(const Key('voiced-mark')).first, matching: find.text('озвучена'));
    expect(tester.widget<Text>(mark).style?.color, sepiaPalette.ink);
  });

  test('№18: цена и оценка — по тарифу на дату из часов приложения, а не зашитой в экран', () {
    final now = Tariffs(today: () => DateTime(2026, 11, 14));
    final later = Tariffs(today: () => DateTime(2027, 1, 5));
    expect(now.dollarsPerHour(TtsModel.flash), 0.81);
    expect(later.dollarsPerHour(TtsModel.flash), 1.62);
    expect(now.beforePriceChange, isTrue);
    expect(later.beforePriceChange, isFalse);
  });

  testWidgets('№18: настройки показывают цену на сегодня по часам приложения', (tester) async {
    await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0,81'), findsOneWidget);
  });

  testWidgets('№19: строка скачивания видна при открытых панелях; после ошибки — «Скачать снова»', (tester) async {
    final p = await pumpPrototype(tester);
    await openDama(tester, p, at: const ReadingPosition(180, 0));
    final book = currentBook(tester);
    p.downloads.demoShow(book, book.chapterOf(180), failed: false);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    expect(find.byKey(const Key('download-strip')).hitTestable(), findsOneWidget);
    p.downloads.demoShow(book, book.chapterOf(180), failed: true);
    await tester.tap(find.byTooltip('Оглавление'));
    await advance(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('download-estimate')), findsOneWidget);
    expect(find.text('Скачать снова'), findsOneWidget);
  });

  testWidgets('№20: текст 402 не обещает автопродолжения', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
    await advance(tester, const Duration(milliseconds: 600));
    expect(find.textContaining('нажмите «Слушать»'), findsOneWidget);
    expect(find.textContaining('продолжится'), findsNothing);
  });

  testWidgets('проба голоса: постоянная ошибка показана в строке голоса текстом Google', (tester) async {
    final p = await pumpPrototype(tester);
    p.sampler.demoFailVoice = 'Aoede';
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('probe-Aoede')));
    await advance(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('probe-error')), findsOneWidget);
    expect(find.textContaining('The service is currently unavailable.'), findsOneWidget);
  });

  testWidgets('двойное нажатие на книгу при медленном открытии открывает один экран', (tester) async {
    final p = await pumpPrototype(tester);
    p.library.loadDelay = const Duration(milliseconds: 300);
    await tester.tap(find.text('Капитанская дочка').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Капитанская дочка').first);
    await advance(tester, const Duration(seconds: 1));
    await settle(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('page-area')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing, reason: 'под первым экраном чтения второго нет');
  });

  testWidgets('следование за голосом: страница содержит звучащее место внутри длинного блока', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3, demoAcceleration: 20);
    p.settings.fontStep = fontSteps.length - 1;
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
    await startListening(tester);
    var turned = 0;
    var last = reader(tester).page;
    for (var i = 0; i < 40; i++) {
      // Голос идёт; затем голос «замирает» на время анимации перелистывания (паузой), и страница проверяется.
      await tester.pump(const Duration(milliseconds: 250));
      p.narration.pause();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final st = reader(tester);
      final at = st.soundingPosition!;
      expect(st.layout.pages[st.page].contains(at.block, at.offset), isTrue,
          reason: 'шаг $i: звучит ${at.block}:${at.offset}, на экране другая страница');
      if (st.page != last) turned++;
      last = st.page;
      p.narration.resume();
    }
    expect(turned, greaterThan(1), reason: 'тест не вакуумный: страница переворачивалась за голосом');
  });
}
