// Жесты и слои: панели, панель плеера, листы, системная «Назад», второе касание по месту, где слой только что
// сменился (разделы B, D, G проверки жестов 2026-11-14).

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('второе касание по тому же месту', () {
    for (final (size, scale, label) in const [(phone412, 1.0, '412 × 915'), (phone320, 1.3, '320 × 640 ×1,3')]) {
      testWidgets('«Слушать» нажата дважды подряд ($label): озвучка идёт с того же места, а не стоит на паузе',
          (tester) async {
        final p = await pumpPrototype(tester, size: size, textScale: scale, demoAcceleration: 1);
        await openKapitanskaya(tester, p);
        await tapCenter(tester);
        await tester.pumpAndSettle();
        final c = tester.getCenter(find.byKey(const Key('listen')));
        await quickTap(tester, c);
        await frames(tester, 160);
        final started = p.narration.unitStart;
        expect(p.narration.state, NarrationState.preparing, reason: 'предусловие: первое касание начало озвучку');
        await quickTap(tester, c);
        await advance(tester, const Duration(seconds: 2));
        expect(p.narration.state, NarrationState.playing,
            reason: 'двойное нажатие на «Слушать» — всё равно «слушать»: под палец не должна вставать другая кнопка');
        expect(p.narration.unitStart, started);
      });
    }

    testWidgets('«Слушать» нажата дважды подряд в любом месте кнопки: второе касание ничего не нажимает', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      final wrong = <String>[];
      for (final fx in [0.08, 0.25, 0.5, 0.75, 0.92]) {
        await tapCenter(tester);
        await advance(tester, const Duration(milliseconds: 400));
        final r = tester.getRect(find.byKey(const Key('listen')));
        final c = Offset(r.left + r.width * fx, r.center.dy);
        await quickTap(tester, c);
        await frames(tester, 160);
        final started = p.narration.unitStart;
        await quickTap(tester, c);
        await advance(tester, const Duration(seconds: 2));
        final at = '${(fx * 100).round()} % ширины кнопки';
        if (find.byKey(const Key('sleep-15')).evaluate().isNotEmpty) wrong.add('$at: открыт таймер сна');
        if (find.byKey(const Key('speed-1.0')).evaluate().isNotEmpty) wrong.add('$at: открыт лист скорости');
        if (p.narration.state != NarrationState.playing) wrong.add('$at: ${p.narration.state.name}');
        if (p.narration.unitStart != started) {
          wrong.add('$at: место звука ушло с блока ${started?.block} на ${p.narration.unitStart?.block}');
        }
        // Вернуть экран к чтению без плеера (подготовка следующего прохода).
        if (find.byKey(const Key('player-panel')).hitTestable().evaluate().isEmpty) {
          await tester.binding.handlePopRoute();
          await advance(tester, const Duration(milliseconds: 600));
        }
        await tester.tap(find.byKey(const Key('player-close')));
        await advance(tester, const Duration(milliseconds: 600));
      }
      expect(wrong, isEmpty);
    });

    testWidgets('«Закрыть» нажата дважды подряд: страница не перелистывается', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final sounding = reader(tester).soundingPosition!;
      final c = tester.getCenter(find.byKey(const Key('player-close')));
      await quickTap(tester, c);
      await frames(tester, 160);
      await quickTap(tester, c);
      await tester.pumpAndSettle();
      expect(p.narration.state, NarrationState.idle);
      expect(onPage(tester, sounding), isTrue,
          reason: 'после «Закрыть» на экране звучавшее место (FR-P8); второе касание его не уводит');
      expect(reader(tester).panelsVisible, isFalse);
    });

    testWidgets('выбор в листе скорости или таймера сделан двойным касанием: лист закрыт, звук идёт, экран чтения тот же',
        (tester) async {
      final wrong = <String>[];
      for (final (opener, choice) in const [
        ('speed', 'speed-0.75'),
        ('speed', 'speed-1.5'),
        ('sleep', 'sleep-15'),
        ('sleep', 'sleep-chapter'),
      ]) {
        // Каждый выбор — на свежем экране.
        await tester.pumpWidget(const SizedBox());
        final p = await pumpPrototype(tester, demoAcceleration: 1);
        await openKapitanskaya(tester, p);
        await startListening(tester);
        await tester.tap(find.byKey(Key(opener)));
        await advance(tester, const Duration(milliseconds: 600));
        final c = tester.getCenter(find.byKey(Key(choice)));
        await quickTap(tester, c);
        await frames(tester, 160);
        await quickTap(tester, c);
        await advance(tester, const Duration(milliseconds: 800));
        if (p.narration.state != NarrationState.playing) wrong.add('$choice: звук остановлен (${p.narration.state.name})');
        if (find.byKey(const Key('page-area')).hitTestable().evaluate().isEmpty) {
          wrong.add('$choice: поверх чтения открыт другой экран');
        } else if (reader(tester).panelsVisible) {
          wrong.add('$choice: открыты панели чтения');
        }
      }
      expect(wrong, isEmpty, reason: 'второе касание той же кнопки листа попадает в то, что под листом');
    });

    testWidgets('строка скачивания: «Стоп» дважды — панели не открываются, страница та же', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final page = reader(tester).page;
      p.downloads.demoShow(currentBook(tester), 1, failed: false);
      await advance(tester, const Duration(milliseconds: 400));
      final c = tester.getCenter(find.text('Стоп'));
      await quickTap(tester, c);
      await frames(tester, 160);
      await quickTap(tester, c);
      await tester.pumpAndSettle();
      expect(p.downloads.task, isNull);
      expect(reader(tester).page, page);
      expect(reader(tester).panelsVisible, isFalse);
    });
  });

  group('выбранный абзац и другие жесты', () {
    testWidgets('слушаю → долгое нажатие → передумал и смахнул → «К месту чтения» возвращает к голосу', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final voicePage = reader(tester).page;
      await tester.longPressAt(blockCenter(tester, lowestParagraph(tester)));
      await advance(tester, const Duration(milliseconds: 300));
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);

      await swipe(tester, at(tester, 0.85, 0.3), const Offset(-220, 0), ms: 110);
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).page, voicePage + 1, reason: 'предусловие: смахивание перелистнуло');
      expect(find.byKey(const Key('read-from-here')), findsNothing, reason: 'предусловие: кнопки «Читать отсюда» нет');
      expect(find.byKey(const Key('to-reading-place')), findsOneWidget);

      await tester.tap(find.byKey(const Key('to-reading-place')));
      await advance(tester, const Duration(milliseconds: 800));
      final sounding = reader(tester).soundingPosition!;
      expect(onPage(tester, sounding), isTrue,
          reason: '«К месту чтения» включает следование (FR-P4): на экране должно быть звучащее место');
    });
  });

  group('слой перехватывает жест', () {
    testWidgets('смахивание, начатое на панели плеера, страницу не листает; начатое на странице и законченное на панели — '
        'листает', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final page = reader(tester).page;
      final panel = tester.getRect(find.byKey(const Key('player-panel')));
      await swipe(tester, Offset(panel.right - 30, panel.top + 30), const Offset(-240, 0), ms: 120);
      await advance(tester, const Duration(milliseconds: 600));
      expect(reader(tester).page, page);
      expect(reader(tester).following, isTrue);
      expect(p.narration.state, NarrationState.playing, reason: 'смахивание по панели не нажимает её кнопок');

      await swipe(tester, Offset(panel.right - 30, panel.top - 40), const Offset(-240, 80), ms: 120);
      await advance(tester, const Duration(milliseconds: 1200));
      expect(reader(tester).page, page + 1);
      expect(reader(tester).following, isFalse);
      expect(p.narration.state, NarrationState.playing);
    });

    testWidgets('панели чтения открыты: смахивание по шапке ничего не листает и панели не прячет', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final page = reader(tester).page;
      await tapCenter(tester);
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byKey(const Key('reader-top-bar')));
      await swipe(tester, Offset(bar.center.dx + 60, bar.center.dy), const Offset(-200, 0), ms: 120);
      await tester.pumpAndSettle();
      expect(reader(tester).page, page);
      expect(reader(tester).panelsVisible, isTrue);
    });
  });

  group('системная «Назад» (FR-R9)', () {
    // Приведено к решению J (проверка жестов 2026-11-14): при показанных панелях «Назад» после листа закрывает книгу;
    // прятать панели «Назад» больше не должна. Было: «лист, потом панели, потом книга».
    testWidgets('панели + сноска: лист, потом книга; страница та же', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await tester.tapAt(noteRefCenter(tester, 'n1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsOneWidget);
      expect(reader(tester).panelsVisible, isTrue, reason: 'сноска открывается и при открытых панелях');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsNothing);
      expect(reader(tester).panelsVisible, isTrue);
      expect(reader(tester).page, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsNothing);
      expect(find.byKey(const Key('shelf-title')), findsOneWidget);
    });

    testWidgets('«Назад» посреди анимации листа скорости и посреди перелистывания', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      await tester.tap(find.byKey(const Key('speed')));
      await frames(tester, 64);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed-1.5')), findsNothing, reason: 'лист закрыт');
      expect(find.byKey(const Key('player-panel')), findsOneWidget, reason: 'книга и плеер на месте');
      expect(p.narration.state, NarrationState.playing);

      // Касание правой трети и «Назад» через 80 мс: книга закрывается без исключений, позиция записана. Приведено к
      // решению J: панели скрыты — первая «Назад» их показывает, вторая закрывает книгу.
      await quickTap(tester, at(tester, 0.9, 0.3));
      await frames(tester, 80);
      await tester.binding.handlePopRoute();
      await frames(tester, 80);
      expect(reader(tester).panelsVisible, isTrue, reason: 'решение J: первая «Назад» показывает панели');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shelf-title')), findsOneWidget);
      expect(p.narration.state, NarrationState.idle);
    });
  });
}

/// Место стоит на странице, которая сейчас на экране.
bool onPage(WidgetTester tester, ReadingPosition at) => currentPage(tester).contains(at.block, at.offset);

/// Абзац текущей страницы, начинающийся на ней ниже первого куска (под ним не панель плеера).
int lowestParagraph(WidgetTester tester) {
  final st = reader(tester);
  final book = st.widget.book;
  final frags = currentPage(tester).fragments;
  for (var i = 1; i < frags.length; i++) {
    final b = book.blocks[frags[i].block];
    if (b.isSpoken && frags[i].start == 0 && b.text.trim().isNotEmpty) return frags[i].block;
  }
  return frags.first.block;
}
