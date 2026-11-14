// Жесты страницы настоящими событиями указателя (раздел A проверки жестов 2026-11-14).

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

Book twoNotesBook() {
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
  group('касание третей (FR-R2)', () {
    for (final (size, scale, label) in const [(phone412, 1.0, '412 × 915'), (phone320, 1.3, '320 × 640 ×1,3')]) {
      testWidgets('границы третей ($label): на 2 dp левее 1/3 — назад, правее — панели; левее 2/3 — панели, правее — '
          'вперёд', (tester) async {
      final p = await pumpPrototype(tester, size: size, textScale: scale);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final r = pageRect(tester);
      final y = r.center.dy;

      await tester.tapAt(Offset(r.width / 3 - 2, y));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start - 1);
      expect(reader(tester).panelsVisible, isFalse);

      await tester.tapAt(Offset(r.width / 3 + 2, y));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start - 1);
      expect(reader(tester).panelsVisible, isTrue);
      await tester.tapAt(Offset(r.width / 2, y));
      await tester.pumpAndSettle();
      expect(reader(tester).panelsVisible, isFalse);

      await tester.tapAt(Offset(r.width * 2 / 3 - 2, y));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start - 1);
      expect(reader(tester).panelsVisible, isTrue);
      await tester.tapAt(Offset(r.width / 2, y));
      await tester.pumpAndSettle();

      await tester.tapAt(Offset(r.width * 2 / 3 + 2, y));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start);
      expect(reader(tester).panelsVisible, isFalse);
      });
    }
  });

  group('смахивание (FR-R2)', () {
    testWidgets('медленное: не дотянул до половины — страница та же; перетянул за половину — следующая', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);

      var f = await Finger.down(tester, at(tester, 0.8, 0.5));
      await f.move(const Offset(-150, 0), ms: 700);
      await f.hold(300);
      await f.up();
      await tester.pumpAndSettle();
      expect(reader(tester).page, start, reason: '36 % ширины и палец остановился — страница возвращается');
      expect(p.library.positionOf('kapitanskaya'),
          ReadingPosition(currentPage(tester).firstBlock, currentPage(tester).firstOffset));

      f = await Finger.down(tester, at(tester, 0.9, 0.5));
      await f.move(const Offset(-270, 0), ms: 900);
      await f.hold(300);
      await f.up();
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 1, reason: '65 % ширины — следующая страница');
    });

    testWidgets('вертикальное смахивание с небольшим уходом вбок страницу не листает', (tester) async {
      // Читатель с привычкой к ленте проводит большим пальцем вверх; палец идёт дугой: 260 dp вверх, 45 dp влево.
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final flipped = <String>[];
      for (final dx in [-25.0, -45.0, 45.0]) {
        await swipe(tester, at(tester, 0.6, 0.75), Offset(dx, -260), ms: 160);
        await tester.pumpAndSettle();
        if (reader(tester).page != start) {
          flipped.add('вверх на 260 dp с уходом вбок на ${dx.round()} dp: страница ${reader(tester).page - start > 0 ? '+1' : '−1'}');
          await jumpTo(tester, start);
        }
      }
      expect(flipped, isEmpty,
          reason: 'жест вертикальный (5–10° от вертикали): FR-R2 листает только смахивание влево и вправо');
      expect(reader(tester).panelsVisible, isFalse);
    });

    testWidgets('смахивание и сразу касание правой трети — две страницы вперёд', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-200, 0), ms: 110);
      await frames(tester, 48);
      await quickTap(tester, at(tester, 0.9, 0.5));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2,
          reason: 'второй жест во время доводки первого не теряется (FR-R2 — то же, что для двух касаний)');
    });

    testWidgets('два быстрых смахивания подряд — две страницы вперёд', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-200, 0), ms: 110);
      await frames(tester, 64);
      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-200, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2);
    });

    testWidgets('первая страница — назад, последняя — вперёд: страница та же, позиция цела', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      await swipe(tester, at(tester, 0.2, 0.5), const Offset(220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, 0);
      await tester.tapAt(at(tester, 0.1, 0.9));
      await tester.pumpAndSettle();
      expect(reader(tester).page, 0);
      expect(reader(tester).panelsVisible, isFalse);

      final st = reader(tester);
      final last = st.layout.pages.length - 1;
      await jumpTo(tester, last);
      await swipe(tester, at(tester, 0.85, 0.3), const Offset(-220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, last);
      await swipe(tester, at(tester, 0.2, 0.3), const Offset(220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, last - 1, reason: 'после упора в конец обычное листание назад работает');
    });
  });

  group('долгое нажатие', () {
    testWidgets('долгое нажатие и сдвиг пальца: выбран абзац, страница не листается', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final block = wholeParagraphOnPage(tester);
      final f = await Finger.down(tester, blockCenter(tester, block));
      await f.hold(650);
      await f.move(const Offset(-170, 0), ms: 200);
      await f.up();
      await tester.pumpAndSettle();
      expect(reader(tester).page, start);
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);
      expect(find.byKey(ValueKey('hl-$block-0')), findsOneWidget);
    });

    testWidgets('картинка и подпись не выбираются; знак сноски под долгим нажатием выбирает абзац, а не открывает сноску',
        (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      // Знак сноски n1 на первой странице.
      await tester.longPressAt(noteRefCenter(tester, 'n1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsNothing);
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);
      await tester.tapAt(at(tester, 0.5, 0.97));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('read-from-here')), findsNothing);

      final st = reader(tester);
      await gotoPageWhere(tester, (i) => st.layout.pages[i].fragments.any((f) => f.isImage));
      final img = currentPage(tester).fragments.firstWhere((f) => f.isImage);
      await tester.longPressAt(Offset(pageRect(tester).center.dx, st.pagePadding.top + img.top + img.height / 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('read-from-here')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('выбрал абзац, передумал и смахнул страницу: следующее касание правой трети листает', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      await tester.longPressAt(blockCenter(tester, wholeParagraphOnPage(tester)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);

      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 1, reason: 'предусловие: смахивание перелистнуло');
      expect(find.byKey(const Key('read-from-here')), findsNothing, reason: 'предусловие: кнопки на новой странице нет');

      await tester.tapAt(at(tester, 0.9, 0.5));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2,
          reason: 'на экране нет ни выбора, ни кнопки — касание правой трети обязано листать (FR-R2)');
    });
  });

  group('знак сноски (FR-R3)', () {
    testWidgets('два знака сносок рядом: касание второго открывает вторую сноску', (tester) async {
      final p = await pumpPrototype(tester);
      await openSynthetic(tester, p, twoNotesBook());
      final a = noteRefCenter(tester, 'a');
      final b = noteRefCenter(tester, 'b');
      expect((b - a).distance, lessThan(24), reason: 'предусловие: области 48 × 48 двух знаков перекрываются');
      await tester.tapAt(b);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsOneWidget);
      expect(find.text('Вторая сноска.'), findsOneWidget, reason: 'палец стоит точно на втором знаке');
    });

    testWidgets('область знака — 48 × 48, не больше: в 20 dp под знаком — сноска, в 30 dp — обычное правило третей; '
        'касание затемнения закрывает лист и страницу не трогает', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      final st = reader(tester);
      // Страница с одним знаком сноски, не первая и не последняя — чтобы листание было видно.
      await gotoPageWhere(tester, (i) => notesOnPage(tester, i).length == 1, from: 1);
      final page = st.page;
      final c = noteRefCenter(tester, notesOnPage(tester).single);
      await tester.tapAt(c + const Offset(0, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsOneWidget);
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsNothing);
      expect(reader(tester).page, page);
      expect(reader(tester).panelsVisible, isFalse);

      await tester.tapAt(c + const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsNothing);
      final x = c.dx / pageRect(tester).width;
      if (x < 1 / 3) {
        expect(reader(tester).page, page - 1);
      } else if (x > 2 / 3) {
        expect(reader(tester).page, page + 1);
      } else {
        expect(reader(tester).panelsVisible, isTrue);
      }
    });
  });
}
