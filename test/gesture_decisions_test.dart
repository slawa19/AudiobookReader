// Решения A–J по проверке жестов 2026-11-14 (docs/reviews/GESTURE_AUDIT_2026-11-14.md) и пути, которые проверяющий
// не прошёл: второй палец во время листания, прокрутка оглавления, диалог под системной «Назад», смена языка при
// открытом листе. Находки проверяющего — в gesture_*_test.dart.

import 'dart:math' as math;

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// Те же две сноски рядом, что в gesture_page_test.dart.
Book twoNotesBookForDecisions() {
  const lead = 'Так об этом писали оба автора';
  const text = '${lead}1,2 и спорить с ними никто не стал. Дальше идёт обычный текст абзаца, в котором сносок нет.';
  return Book(
    id: 'synthetic-two-notes',
    title: 'Две сноски',
    author: 'Проверка',
    language: 'ru',
    chapters: const [Chapter(title: 'Глава', level: 1, firstBlock: 0, blockCount: 1)],
    blocks: [
      Block(index: 0, kind: BlockKind.paragraph, text: text, spans: [
        TextSpanRange(start: lead.length, end: lead.length + 1, style: SpanStyle.noteRef, noteId: 'a'),
        TextSpanRange(start: lead.length + 2, end: lead.length + 3, style: SpanStyle.noteRef, noteId: 'b'),
      ]),
    ],
    notes: const {
      'a': Note(id: 'a', blocks: [Block(index: 0, kind: BlockKind.paragraph, text: 'Первая сноска.')]),
      'b': Note(id: 'b', blocks: [Block(index: 0, kind: BlockKind.paragraph, text: 'Вторая сноска.')]),
    },
  );
}

void main() {
  group('A. касание вдогонку', () {
    test('порог — именованная константа 350 мс', () {
      expect(layerSettleTime, const Duration(milliseconds: 350));
    });

    testWidgets('обычный темп: «Слушать», через 400 мс «Пауза» — пауза нажата', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await quickTap(tester, tester.getCenter(find.byKey(const Key('listen'))));
      await frames(tester, 400);
      await quickTap(tester, tester.getCenter(find.byKey(const Key('play-pause'))));
      await frames(tester, 100);
      expect(p.narration.state, NarrationState.paused, reason: 'второе нажатие через 400 мс — осмысленное, работает');
    });

    testWidgets('лист скорости открыт двойным касанием: второе касание не выбирает скорость и не закрывает лист',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final c = tester.getCenter(find.byKey(const Key('speed')));
      await quickTap(tester, c);
      await frames(tester, 200);
      await quickTap(tester, c);
      await frames(tester, 400);
      expect(find.byKey(const Key('speed-1.0')), findsOneWidget, reason: 'лист открыт');
      expect(p.narration.speed, 1);
      // Через 350 мс лист работает как обычно.
      await tester.tap(find.byKey(const Key('speed-1.5')));
      await tester.pumpAndSettle();
      expect(p.narration.speed, 1.5);
    });

    testWidgets('после закрытия листа: касание через 400 мс доходит до панели плеера', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      await tester.tap(find.byKey(const Key('sleep')));
      await advance(tester, const Duration(milliseconds: 600));
      await quickTap(tester, tester.getCenter(find.byKey(const Key('sleep-15'))));
      await frames(tester, 450);
      await quickTap(tester, tester.getCenter(find.byKey(const Key('play-pause'))));
      await frames(tester, 100);
      expect(p.narration.sleepTimer?.minutes, 15);
      expect(p.narration.state, NarrationState.paused);
    });
  });

  group('B. выбор абзаца снимается при смене страницы', () {
    testWidgets('выбрал абзац → смахнул назад: выбора и подсветки нет', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final block = wholeParagraphOnPage(tester);
      await tester.longPressAt(blockCenter(tester, block));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('hl-$block-0')), findsOneWidget, reason: 'предусловие');
      await swipe(tester, at(tester, 0.15, 0.5), const Offset(220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, start - 1);
      await jumpTo(tester, start);
      expect(find.byKey(const Key('read-from-here')), findsNothing);
      expect(find.byKey(ValueKey('hl-$block-0')), findsNothing, reason: 'вернулся на страницу — выбора нет');
    });
  });

  group('C. палец во время автоматического переворота', () {
    testWidgets('вне автопереворота: малое перетаскивание с возвратом следование не выключает', (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      final f = await Finger.down(tester, at(tester, 0.6, 0.4));
      await f.move(const Offset(-40, 0), ms: 120);
      await f.move(const Offset(40, 0), ms: 120);
      // Палец остановился — без скорости броска страница встаёт на прежнее место.
      await f.hold(300);
      await f.up();
      await advance(tester, const Duration(milliseconds: 800));
      expect(reader(tester).following, isTrue);
      expect(p.narration.state, NarrationState.playing);
    });
  });

  group('D. листает только преимущественно горизонтальный жест', () {
    for (final (deg, flips) in const [(10, true), (30, true), (44, true), (46, false), (60, false), (80, false)]) {
      testWidgets('смахивание влево-вверх под $deg° к горизонтали: ${flips ? 'листает' : 'не листает'}', (tester) async {
        final p = await pumpPrototype(tester);
        await openKapitanskaya(tester, p);
        final start = await gotoPlainPage(tester);
        final a = deg * math.pi / 180;
        const length = 240.0;
        await swipe(tester, at(tester, 0.75, 0.7), Offset(-length * math.cos(a), -length * math.sin(a)), ms: 110);
        await tester.pumpAndSettle();
        expect(reader(tester).page, flips ? start + 1 : start);
        expect(reader(tester).panelsVisible, isFalse, reason: 'вертикальный жест не делает ничего');
      });
    }
  });

  group('E. ключ сохраняется при уходе с поля и с экрана', () {
    Future<void> openKeyField(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('key-change')));
      await tester.pumpAndSettle();
    }

    testWidgets('стрелка «Назад» экрана настроек: введённый ключ сохранён', (tester) async {
      final p = await pumpPrototype(tester);
      await openKeyField(tester);
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-new-key-1234');
      await tester.pump();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(p.settings.apiKeyTail, '1234');
    });

    testWidgets('ушёл с поля касанием другого пункта: ключ сохранён, поле закрыто', (tester) async {
      final p = await pumpPrototype(tester);
      await openKeyField(tester);
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-new-key-5678');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(p.settings.apiKeyTail, '5678');
      expect(find.byKey(const Key('key-field')), findsNothing);
    });

    testWidgets('пустое поле и «Назад»: прежний ключ не тронут', (tester) async {
      final p = await pumpPrototype(tester);
      final before = p.settings.apiKeyTail;
      await openKeyField(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(p.settings.hasApiKey, isTrue);
      expect(p.settings.apiKeyTail, before);
    });
  });

  group('G. ближайший знак сноски', () {
    testWidgets('два знака рядом: касание первого открывает первую', (tester) async {
      final p = await pumpPrototype(tester);
      await openSynthetic(tester, p, twoNotesBookForDecisions());
      await tester.tapAt(noteRefCenter(tester, 'a'));
      await tester.pumpAndSettle();
      expect(find.text('Первая сноска.'), findsOneWidget);
    });
  });

  group('J. системная «Назад» в чтении', () {
    testWidgets('слушаю, панели скрыты: «Назад» показывает шапку и ползунок, звук идёт; вторая — закрывает книгу',
        (tester) async {
      final p = await pumpPrototype(tester, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      expect(reader(tester).panelsVisible, isFalse);
      await tester.binding.handlePopRoute();
      await advance(tester, const Duration(milliseconds: 500));
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(reader(tester).panelsVisible, isTrue);
      expect(find.byKey(const Key('book-slider')), findsOneWidget, reason: 'ползунок над панелью плеера');
      expect(p.narration.state, NarrationState.playing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(p.narration.state, NarrationState.idle);
    });

    testWidgets('стрелка «Назад» в шапке закрывает книгу сразу', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(p.library.shelf.first.id, 'kapitanskaya');
    });
  });

  group('пути, которые проверяющий не прошёл', () {
    testWidgets('второй палец во время смахивания: одна страница, без исключений', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final first = await Finger.down(tester, at(tester, 0.8, 0.5));
      await first.move(const Offset(-80, 0), ms: 80);
      final second = await Finger.down(tester, at(tester, 0.3, 0.3), pointer: 2);
      await first.move(const Offset(-140, 0), ms: 80);
      await second.move(const Offset(-60, 0), ms: 60);
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(reader(tester).page, inInclusiveRange(start, start + 1), reason: 'не больше одной страницы за жест');
    });

    testWidgets('оглавление: прокрутка пальцем и касание главы — открыта эта глава', (tester) async {
      final p = await pumpPrototype(tester);
      await openDama(tester, p);
      final book = currentBook(tester);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Оглавление'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final last = book.chapters.length - 1;
      final title = find.text(book.chapters[last].title).last;
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(reader(tester).layout.pages[reader(tester).page].chapter, last);
    });

    testWidgets('диалог удаления книги под системной «Назад»: диалог закрыт, книга на полке', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.longPress(find.text('Записки охотника'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить книгу'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-delete')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-delete')), findsNothing);
      expect(p.library.shelf.any((e) => e.id == 'zapiski'), isTrue);
      expect(find.byKey(const Key('shelf-title')), findsOneWidget);
    });

    testWidgets('смена языка при открытом листе «Вид текста»: лист открыт и уже на новом языке', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearance-sheet')), findsOneWidget);
      p.settings.language = 'en';
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('appearance-sheet')), findsOneWidget);
      expect(find.text('Text appearance'), findsOneWidget);
    });
  });
}
