import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

/// Открывает «Капитанскую дочку» на месте [at] (по умолчанию — сохранённом).
Future<void> openKapitanskaya(WidgetTester tester, Prototype p, {ReadingPosition? at}) async {
  if (at != null) p.library.savePosition('kapitanskaya', at);
  await openBook(tester, 'Капитанская дочка');
}

Future<void> openDama(WidgetTester tester, Prototype p, {ReadingPosition? at}) async {
  if (at != null) p.library.savePosition('dama', at);
  await openBook(tester, 'Дама с собачкой. Рассказы');
}

Book currentBook(WidgetTester tester) => reader(tester).widget.book;

/// Середина экрана — касание центра.
Future<void> tapCenter(WidgetTester tester) async {
  final size = tester.getSize(find.byKey(const Key('page-area')));
  await tester.tapAt(Offset(size.width / 2, size.height / 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapRightThird(WidgetTester tester) async {
  final size = tester.getSize(find.byKey(const Key('page-area')));
  await tester.tapAt(Offset(size.width * 0.9, size.height / 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapLeftThird(WidgetTester tester) async {
  final size = tester.getSize(find.byKey(const Key('page-area')));
  await tester.tapAt(Offset(size.width * 0.1, size.height / 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Центр знака сноски [noteId] на текущей странице в координатах экрана.
Offset noteRefCenter(WidgetTester tester, String noteId) {
  final st = reader(tester);
  final book = st.widget.book;
  final page = st.layout.pages[st.page];
  for (final f in page.fragments) {
    final b = book.blocks[f.block];
    for (final s in b.spans) {
      if (s.noteId != noteId || s.start < f.start || s.end > f.end) continue;
      final tp = fragmentPainter(st.pageStyle, b, f.start, f.end, width: st.columnSize.width);
      final shift = hasIndent(b, f.start) ? 1 : 0;
      final box = tp.getBoxesForSelection(
          TextSelection(baseOffset: s.start - f.start + shift, extentOffset: s.end - f.start + shift)).first;
      tp.dispose();
      final inset = fragmentInset(st.pageStyle, b);
      return Offset(st.pagePadding.left + inset, st.pagePadding.top + f.top) + box.toRect().center;
    }
  }
  throw StateError('Сноски $noteId на странице нет');
}

/// Центр первого куска блока [block] на текущей странице в координатах экрана.
Offset blockCenter(WidgetTester tester, int block) {
  final st = reader(tester);
  final f = st.layout.pages[st.page].fragments.firstWhere((f) => f.block == block);
  final size = tester.getSize(find.byKey(const Key('page-area')));
  return Offset(size.width / 2, st.pagePadding.top + f.top + f.height / 2);
}

/// Первый абзац текущей страницы, целиком стоящий на ней.
int wholeParagraphOnPage(WidgetTester tester) {
  final st = reader(tester);
  final book = st.widget.book;
  final page = st.layout.pages[st.page];
  return page.fragments
      .firstWhere((f) => book.blocks[f.block].kind == BlockKind.paragraph && f.start == 0 && f.end == book.blocks[f.block].text.length)
      .block;
}

/// Ход подставной озвучки: время идёт кусками, чтобы таймеры и анимации отработали.
Future<void> advance(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 100);
  var left = d;
  while (left > Duration.zero) {
    await tester.pump(step);
    left -= step;
  }
}
