import 'dart:convert';
import 'dart:math';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_screen_real_navigation_test.dart' show expectFullProsePage;
import 'support/app_harness.dart';
import 'support/harness.dart' show reader;

const propertySeeds = [17, 31, 59, 83, 107, 139, 173, 211, 257, 307, 359, 419];

List<int> propertyBook() => utf8.encode('''<FictionBook><description><title-info>
<book-title>Свойства страниц</book-title><lang>ru</lang></title-info></description><body>
${List.generate(2, (c) => '<section>${List.generate(300, (b) {
  final text = List.filled(30, 'Утром путешественник осмотрел дорогу и продолжил путь. '
      'Вдали показались деревья, за которыми открывалась широкая долина. ').join();
  return '<p>${text.substring(0, b == 200 ? 2500 : 300 + (b * 173 % 2201))}</p>';
}).join()}</section>').join()}</body></FictionBook>''');

(int, int, int, int) textBounds(ReaderScreenState st) {
  final p = st.layout.pages[st.page];
  return (p.firstBlock, p.firstOffset, p.lastBlock, p.lastEnd);
}

Offset pageThird(WidgetTester tester, bool right) {
  final st = reader(tester);
  final area = tester.getRect(find.byKey(const Key('page-area')));
  return Offset(area.width * (right ? 0.9 : 0.1), st.pagePadding.top + 100);
}

Future<AppHarness> propertyApp(WidgetTester tester, {bool narrow = false}) async {
  final h = AppHarness(tester);
  await h.start(fakeTts: true, textScale: narrow ? 1.3 : 1,
      synthesis: FakeTtsEngine(delay: const Duration(milliseconds: 300),
          sampleRate: 100, secondsPerCharacter: 0.1));
  tester.view.devicePixelRatio = narrow ? 1 : 3;
  tester.view.physicalSize = narrow ? const Size(320, 900) : const Size(1440, 3120);
  tester.view.padding = FakeViewPadding(top: narrow ? 32 : 96, bottom: narrow ? 48 : 144);
  tester.view.viewPadding = tester.view.padding;
  h.app.settings.voice = 'Pulcherrima';
  final file = await h.copy(propertyBook());
  h.files.events.add(file);
  await h.until(() => find.byType(ReaderScreen).evaluate().isNotEmpty);
  final st = reader(tester);
  st.goToPosition(const ReadingPosition(200, 0));
  await tester.pump();
  st.listen();
  await h.until(() => h.player.playing);
  // Только кадры: не досчитываем всю книгу через pumpAndSettle.
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return h;
}

/// Оракул наблюдает координаты текста каждого кадра, а не идентичность объектов раскладки.
class ScreenOracle {
  ScreenOracle(this.tester, this.h, this.seed);
  final WidgetTester tester;
  final AppHarness h;
  final int seed;
  final frames = <(int, int, int, int)>[];
  (int, int, int, int)? stable;
  int followingLate = 0;

  Future<void> frame({bool mayMove = false}) async {
    await tester.pump(const Duration(milliseconds: 16));
    final st = reader(tester);
    final bounds = textBounds(st);
    frames.add(bounds);
    final why = 'seed=$seed frame=${frames.length} bounds=$bounds';
    if (!mayMove && stable != null) expect(bounds, stable, reason: 'I1 $why');
    stable = bounds;
    expect(find.byKey(const Key('to-reading-place')).evaluate().isNotEmpty,
        !st.following, reason: 'I4 $why');
    expectFullProsePage(st); // I5 — в том числе во время подготовки и анимации.
    final at = st.soundingPosition;
    final page = st.layout.pages[st.page];
    if (at != null && page.contains(at.block, at.offset)) {
      final shown = tester.widgetList<BookPage>(find.byType(BookPage))
          .singleWhere((p) => identical(p.page, page));
      expect(shown.highlightBlocks, contains(at.block), reason: 'I6 $why');
      followingLate = 0;
    } else if (st.following && h.player.playing) {
      followingLate++;
      expect(followingLate, lessThanOrEqualTo(28), reason: 'I3 $why');
    } else {
      followingLate = 0;
    }
  }

  Future<void> wait(int count, {bool mayMove = false}) async {
    for (var i = 0; i < count; i++) {
      await frame(mayMove: mayMove);
    }
  }

  Future<void> tapPages(bool right, int count) async {
    final st = reader(tester);
    h.app.services.narration.pause();
    await wait(24, mayMove: true);
    var previous = textBounds(st);
    var changes = 0;
    Future<void> sample() async {
      await frame(mayMove: true);
      final next = textBounds(st);
      if (next == previous) return;
      final book = st.widget.book;
      int absolute(int block, int offset) => book.charsBefore(block) + offset;
      if (right) {
        expect(absolute(next.$1, next.$2), absolute(previous.$3, previous.$4),
            reason: 'I2 forward seed=$seed');
      } else {
        expect(absolute(next.$3, next.$4), absolute(previous.$1, previous.$2),
            reason: 'I2 backward seed=$seed');
      }
      previous = next;
      changes++;
    }
    for (var tap = 0; tap < count; tap++) {
      await tester.tapAt(pageThird(tester, right));
      await sample();
      await sample();
    }
    // Досчёт назад пока может занять начало длинной главы (D8).
    for (var i = 0; i < 120; i++) {
      await sample();
      if (changes == count) break;
    }
    expect(changes, count, reason: 'I2 потерянное касание seed=$seed');
    await wait(4);
  }
}

void main() {
  for (var index = 0; index < propertySeeds.length; index++) {
    final seed = propertySeeds[index];
    testWidgets('свойства экрана seed=$seed', (tester) async {
      final h = await propertyApp(tester, narrow: index.isOdd);
      final o = ScreenOracle(tester, h, seed);
      final random = Random(seed);
      final n = h.app.services.narration;
      for (var action = 0; action < 48; action++) {
        switch (action == 0 ? 0 : random.nextInt(11)) {
          case 0:
          case 1:
            await o.tapPages(action.isOdd, 1);
          case 2:
            await o.tapPages(true, 2);
          case 3:
            final area = tester.getRect(find.byKey(const Key('page-area')));
            await tester.tapAt(Offset(area.width / 2, reader(tester).pagePadding.top + 100));
            await o.wait(24);
          case 4:
            if (find.byKey(const Key('to-reading-place')).evaluate().isNotEmpty) {
              await tester.tap(find.byKey(const Key('to-reading-place')));
            } else {
              n.resume();
            }
            await o.wait(28, mayMove: true);
          case 5:
          case 6:
            if (action.isOdd) {
              n.next();
            } else {
              n.previous();
            }
            await o.wait(28, mayMove: true);
          case 7:
            h.playbackClock.advance(const Duration(seconds: 12));
            await o.wait(28, mayMove: true);
          case 8:
            final gesture = await tester.startGesture(pageThird(tester, false) + const Offset(80, 0));
            await gesture.moveBy(const Offset(-28, 0));
            await o.wait(2, mayMove: true);
            if (action.isEven) n.next();
            await gesture.cancel();
            await o.wait(28, mayMove: true);
          case 9:
            final gesture = await tester.startGesture(pageThird(tester, true));
            await gesture.moveBy(Offset(-reader(tester).columnSize.width * 0.8, 0));
            await o.wait(2, mayMove: true);
            await gesture.up();
            await o.wait(28, mayMove: true);
          case 10:
            if (action % 13 == 0) {
              h.app.settings.fontStep = (h.app.settings.fontStep + 1) % 4;
              await o.wait(28, mayMove: true);
            } else {
              n.pause();
              await o.wait(2);
            }
        }
        await o.wait(4);
      }
    // D1–D7 воспроизведены на исходном коде; снять skip после правок управления.
    }, skip: true);
  }
}
