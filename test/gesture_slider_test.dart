// Ползунок по книге пальцем: перетаскивание, за край, во время прослушивания (раздел C проверки жестов
// 2026-11-14). Прежние тесты ползунка — одно касание дорожки.

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'journey_support.dart' show ru;
import 'support/flows.dart';
import 'support/harness.dart';

const _slider = Key('book-slider');

/// Точка дорожки ползунка для доли [v]: у ползунка Material 3 поля по 24 dp с краёв.
Offset trackPoint(WidgetTester tester, double v) {
  final box = tester.getRect(find.byKey(_slider));
  return Offset(box.left + 24 + (box.width - 48) * v, box.center.dy);
}

void main() {
  testWidgets('перетаскивание во время прослушивания: шапка показывает главу под пальцем, голос места не меняет, '
      'после отпускания — страница с этим местом и следование выключено (FR-R5)', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0));
    await startListening(tester);
    final book = currentBook(tester);
    final block = p.narration.block;
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 500));
    expect(find.byKey(_slider).hitTestable(), findsOneWidget, reason: 'ползунок над панелью плеера');
    final chapterBefore = tester.widget<Text>(find.byKey(const Key('top-bar-chapter'))).data;

    final f = await Finger.down(tester, trackPoint(tester, 0.05));
    await f.move(trackPoint(tester, 0.9) - trackPoint(tester, 0.05), ms: 400);
    await f.hold(200);
    // Палец ещё на ползунке: шапка — глава под пальцем, страница и следование прежние.
    final preview = tester.widget<Text>(find.byKey(const Key('top-bar-chapter'))).data;
    expect(preview, chapterLabel(book, book.chapterOf(book.placeAt(0.9).$1)));
    expect(preview, isNot(chapterBefore), reason: 'предусловие: 90 % книги — другая глава');
    expect(reader(tester).following, isTrue, reason: 'следование выключает отпускание, а не начало перетаскивания');
    await f.up();
    await advance(tester, const Duration(milliseconds: 600));

    final st = reader(tester);
    final page = currentPage(tester);
    expect(book.fractionAt(page.firstBlock, page.firstOffset), lessThanOrEqualTo(0.91));
    expect(book.fractionAt(page.lastBlock, page.lastEnd), greaterThanOrEqualTo(0.89));
    expect(st.following, isFalse);
    // Голос за это время сам прошёл не дальше пары абзацев от места старта — к 90 % книги он не перенесён.
    expect(p.narration.block! - block!, inInclusiveRange(0, 3), reason: 'голос места не меняет');
    expect(p.narration.state, NarrationState.playing);
    expect(find.byKey(const Key('to-reading-place')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('top-bar-chapter'))).data, chapterLabel(book, page.chapter));
  });

  testWidgets('перетаскивание за правый край и отпускание далеко от ползунка — последняя страница и 100 %; за левый — '
      'первая', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    await tester.pumpAndSettle();
    var f = await Finger.down(tester, trackPoint(tester, 0.5));
    await f.move(const Offset(400, -300), ms: 300);
    await f.up();
    await tester.pumpAndSettle();
    final st = reader(tester);
    expect(st.page, st.layout.pages.length - 1);
    expect(find.text(ru.ofBook(1)), findsOneWidget);
    expect(p.library.isFinished('kapitanskaya'), isTrue);

    f = await Finger.down(tester, trackPoint(tester, 0.5));
    await f.move(const Offset(-400, 200), ms: 300);
    await f.up();
    await tester.pumpAndSettle();
    expect(reader(tester).page, 0);
    expect(p.library.isFinished('kapitanskaya'), isFalse);
    expect(p.library.positionOf('kapitanskaya'), const ReadingPosition(0, 0));
  });

  testWidgets('слушаю, тронул бегунок и отпустил, не сдвинув: страница та же, следование не выключено (FR-P4)',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 500));
    final st = reader(tester);
    final page = st.page;
    final book = currentBook(tester);
    final value = book.fractionAt(currentPage(tester).firstBlock, currentPage(tester).firstOffset);
    final f = await Finger.down(tester, trackPoint(tester, value));
    await f.hold(250);
    await f.up();
    await advance(tester, const Duration(milliseconds: 600));
    expect(reader(tester).page, page, reason: 'ползунок не сдвинут — страница та же');
    expect(reader(tester).following, isTrue,
        reason: 'FR-P4: следование выключает ползунок, только когда он сдвинут');
  });

  testWidgets('книга в одну страницу: ползунок не роняет экран и страницу не меняет', (tester) async {
    await pumpPrototype(tester);
    await openBook(tester, 'Война и мир');
    final st = reader(tester);
    expect(st.layout.pages.length, 1, reason: 'предусловие: книга-заглушка — одна страница');
    await tapCenter(tester);
    await tester.pumpAndSettle();
    final f = await Finger.down(tester, trackPoint(tester, 0.9));
    await f.move(const Offset(-250, 0), ms: 300);
    await f.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(reader(tester).page, 0);
    expect(find.text(ru.ofBook(1)), findsOneWidget);
  });
}
