// Page gestures with real pointer events (section A of the gesture review of 2026-11-14).

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
  group('tap on thirds (FR-R2)', () {
    for (final (size, scale, label) in const [(phone412, 1.0, '412 × 915'), (phone320, 1.3, '320 × 640 ×1,3')]) {
      testWidgets('boundaries of the thirds ($label): 2 dp left of 1/3 — back, right of it — panels; left of 2/3 — '
          'panels, right of it — '
          'forward', (tester) async {
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

  group('swipe (FR-R2)', () {
    testWidgets('slow: stopped short of half — the page is the same; dragged past half — the next '
        'page', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);

      var f = await Finger.down(tester, at(tester, 0.8, 0.5));
      await f.move(const Offset(-150, 0), ms: 700);
      await f.hold(300);
      await f.up();
      await tester.pumpAndSettle();
      expect(reader(tester).page, start, reason: '36 % of the width and the finger stopped — the page returns');
      expect(p.library.positionOf('kapitanskaya'),
          ReadingPosition(currentPage(tester).firstBlock, currentPage(tester).firstOffset));

      f = await Finger.down(tester, at(tester, 0.9, 0.5));
      await f.move(const Offset(-270, 0), ms: 900);
      await f.hold(300);
      await f.up();
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 1, reason: '65 % of the width — the next page');
    });

    testWidgets('a vertical swipe with a slight sideways drift does not turn the page', (tester) async {
      // A reader used to feeds swipes the thumb up; the thumb moves in an arc: 260 dp up, 45 dp left.
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      final flipped = <String>[];
      for (final dx in [-25.0, -45.0, 45.0]) {
        await swipe(tester, at(tester, 0.6, 0.75), Offset(dx, -260), ms: 160);
        await tester.pumpAndSettle();
        if (reader(tester).page != start) {
          flipped.add('up 260 dp with a sideways drift of ${dx.round()} dp: page '
              '${reader(tester).page - start > 0 ? '+1' : '−1'}');
          await jumpTo(tester, start);
        }
      }
      expect(flipped, isEmpty,
          reason: 'the gesture is vertical (5–10° from the vertical): FR-R2 turns pages only on a swipe left or right');
      expect(reader(tester).panelsVisible, isFalse);
    });

    testWidgets('a swipe followed at once by a tap on the right third — two pages forward', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-200, 0), ms: 110);
      await frames(tester, 48);
      await quickTap(tester, at(tester, 0.9, 0.5));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2,
          reason: 'a second gesture during the settling of the first is not lost (FR-R2 — same as for two taps)');
    });

    testWidgets('two fast swipes in a row — two pages forward', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-200, 0), ms: 110);
      await frames(tester, 64);
      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-200, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2);
    });

    testWidgets('first page — back, last page — forward: the page is the same, the position is intact', (tester) async {
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
      expect(reader(tester).page, last - 1, reason: 'after hitting the end, ordinary flipping back works');
    });
  });

  group('long press', () {
    testWidgets('a long press and a finger shift: a paragraph is selected, the page does not turn', (tester) async {
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

    testWidgets('an image and a caption are not selectable; a note marker under a long press selects the paragraph and '
        'does not open the note',
        (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      // The note marker n1 on the first page.
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

    testWidgets('picked a paragraph, changed my mind and swiped the page: the next tap on the right third turns the '
        'page', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p);
      final start = await gotoPlainPage(tester);
      await tester.longPressAt(blockCenter(tester, wholeParagraphOnPage(tester)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('read-from-here')), findsOneWidget);

      await swipe(tester, at(tester, 0.85, 0.5), const Offset(-220, 0), ms: 110);
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 1, reason: 'precondition: the swipe turned the page');
      expect(find.byKey(const Key('read-from-here')), findsNothing, reason: 'precondition: there is no button on the '
          'new page');

      await tester.tapAt(at(tester, 0.9, 0.5));
      await tester.pumpAndSettle();
      expect(reader(tester).page, start + 2,
          reason: 'the screen has neither a selection nor a button — a tap on the right third must turn the page '
              '(FR-R2)');
    });
  });

  group('note marker (FR-R3)', () {
    testWidgets('two note markers next to each other: tapping the second opens the second note', (tester) async {
      final p = await pumpPrototype(tester);
      await openSynthetic(tester, p, twoNotesBook());
      final a = noteRefCenter(tester, 'a');
      final b = noteRefCenter(tester, 'b');
      expect((b - a).distance, lessThan(24), reason: 'precondition: the 48 × 48 areas of the two markers overlap');
      await tester.tapAt(b);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet')), findsOneWidget);
      expect(find.text('Вторая сноска.'), findsOneWidget, reason: 'the finger is exactly on the second marker');
    });

    testWidgets('the marker area is 48 × 48, no larger: 20 dp below the marker — the note, 30 dp — the ordinary rule '
        'of thirds; '
        'a tap on the scrim closes the sheet and does not touch the page', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
      final st = reader(tester);
      // A page with a single note marker, neither first nor last — so that page turning is visible.
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
