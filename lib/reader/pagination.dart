import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../book/model.dart';
import 'page_style.dart';

/// Кусок блока на странице: текст [start, end) блока [block] и его место по вертикали.
class PageFragment {
  const PageFragment({
    required this.block,
    required this.start,
    required this.end,
    required this.top,
    required this.height,
    this.imageSize,
  });

  final int block;
  final int start;
  final int end;
  final double top;
  final double height;

  /// У картинки — размер, в который она вписана.
  final Size? imageSize;
}

/// Страница: пара «начало» и «конец» (А§5) плюс раскладка кусков.
class BookPageLayout {
  const BookPageLayout({required this.chapter, required this.fragments, this.titlePage = false});

  final int chapter;
  final List<PageFragment> fragments;

  /// Страница-заглавие раздела без собственного текста (например, «Ионыч» перед главой I).
  final bool titlePage;

  int get firstBlock => fragments.first.block;
  int get firstOffset => fragments.first.start;
  int get lastBlock => fragments.last.block;
  int get lastEnd => fragments.last.end;

  bool containsBlock(int block) => block >= firstBlock && block <= lastBlock;
}

/// Вся книга, разбитая на страницы для одного размера колонки и одной типографики.
///
/// Прототип считает книгу целиком и сразу (≈ 100 тыс. знаков — доли секунды). Расчёт порциями от текущей
/// позиции (А§5, FR-R1) — работа этапа 1.
class BookLayout {
  BookLayout._(this.pages, this.chapterFirstPage);

  final List<BookPageLayout> pages;
  final List<int> chapterFirstPage;

  static BookLayout compute({
    required Book book,
    required PageStyle style,
    required Size column,
    Map<String, Size> imageSizes = const {},
  }) {
    final pages = <BookPageLayout>[];
    final firsts = <int>[];
    final p = _Paginator(book, style, column, imageSizes);
    for (var c = 0; c < book.chapters.length; c++) {
      firsts.add(pages.length);
      pages.addAll(p.chapter(c));
    }
    return BookLayout._(pages, firsts);
  }

  /// Номер страницы, на которой стоит место (блок, смещение).
  int pageOf(int block, int offset) {
    var lo = 0;
    var hi = pages.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final f = pages[mid].fragments.first;
      if (f.block < block || (f.block == block && f.start <= offset)) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

class _Paginator {
  _Paginator(this.book, this.style, this.column, this.imageSizes);

  final Book book;
  final PageStyle style;
  final Size column;
  final Map<String, Size> imageSizes;

  double get lh => style.lineHeight;

  List<BookPageLayout> chapter(int c) {
    final ch = book.chapters[c];
    final pages = <BookPageLayout>[];
    var cur = <PageFragment>[];
    var y = 0.0;
    BlockKind? prevKind;

    void flush() {
      if (cur.isNotEmpty) pages.add(BookPageLayout(chapter: c, fragments: cur));
      cur = <PageFragment>[];
      y = 0;
      prevKind = null;
    }

    final titleOnly = ch.blockCount == 1 && book.blocks[ch.firstBlock].kind == BlockKind.heading;

    for (var i = ch.firstBlock; i < ch.endBlock; i++) {
      final block = book.blocks[i];
      switch (block.kind) {
        case BlockKind.heading:
          final atChapterStart = i == ch.firstBlock;
          final top = titleOnly ? column.height * 0.28 : (atChapterStart ? lh * 1.0 : lh * 1.5);
          final h = top + headingHeight(block) + lh * 1.2;
          if (cur.isNotEmpty && y + h > column.height) flush();
          cur.add(PageFragment(block: i, start: 0, end: block.text.length, top: y + top, height: h - top));
          y += h;
        case BlockKind.image:
          final size = imageBox(block);
          final caption = block.text.isEmpty ? 0.0 : captionHeight(block) + lh * 0.3;
          final sp = cur.isEmpty ? 0.0 : lh * 0.6;
          var h = size.height + caption;
          if (cur.isNotEmpty && y + sp + h > column.height) {
            flush();
          }
          final spNow = cur.isEmpty ? 0.0 : sp;
          h = math.min(h, column.height);
          cur.add(PageFragment(block: i, start: 0, end: block.text.length, top: y + spNow, height: h, imageSize: size));
          y += spNow + h + lh * 0.6;
        case BlockKind.separator:
          final sp = cur.isEmpty ? 0.0 : lh;
          if (cur.isNotEmpty && y + sp + lh > column.height) flush();
          final spNow = cur.isEmpty ? 0.0 : sp;
          cur.add(PageFragment(block: i, start: 0, end: block.text.length, top: y + spNow, height: lh));
          y += spNow + lh * 2;
        case BlockKind.paragraph:
        case BlockKind.verse:
        case BlockKind.cite:
          final m = measure(block);
          var line = 0;
          while (line < m.lineTops.length) {
            final sp = (cur.isEmpty || line > 0) ? 0.0 : spacingBefore(prevKind, block.kind);
            final avail = column.height - y - sp;
            var k = 0;
            var h = 0.0;
            while (line + k < m.lineTops.length && h + m.lineHeights[line + k] <= avail + 0.01) {
              h += m.lineHeights[line + k];
              k++;
            }
            if (k == 0) {
              if (cur.isNotEmpty) {
                flush();
                continue;
              }
              h = m.lineHeights[line];
              k = 1;
            }
            final start = m.lineStarts[line];
            final end = line + k < m.lineStarts.length ? m.lineStarts[line + k] : block.text.length;
            cur.add(PageFragment(block: i, start: start, end: end, top: y + sp, height: h));
            y += sp + h;
            line += k;
            prevKind = block.kind;
            if (line < m.lineTops.length) flush();
          }
          prevKind = block.kind;
          continue;
      }
      prevKind = block.kind;
    }
    flush();
    if (titleOnly && pages.isNotEmpty) {
      pages[0] = BookPageLayout(chapter: c, fragments: pages[0].fragments, titlePage: true);
    }
    return pages;
  }

  double spacingBefore(BlockKind? prev, BlockKind kind) {
    if (prev == null) return 0;
    final a = style.isVerseLike(prev);
    final b = style.isVerseLike(kind);
    if (a != b) return lh * 0.6;
    if (a && b && prev != kind) return lh * 0.15;
    if (prev == BlockKind.heading || prev == BlockKind.image || prev == BlockKind.separator) return 0;
    return 0;
  }

  double headingHeight(Block block) {
    final tp = TextPainter(
      text: headingSpan(style, block),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: column.width);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  Size imageBox(Block block) {
    final natural = imageSizes[block.imageId] ?? const Size(4, 3);
    final maxH = column.height * 0.62;
    var w = column.width;
    var h = w * natural.height / natural.width;
    if (h > maxH) {
      h = maxH;
      w = h * natural.width / natural.height;
    }
    return Size(w, h);
  }

  double captionHeight(Block block) {
    final tp = TextPainter(
      text: TextSpan(text: block.text, style: style.caption),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: column.width);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  _Measured measure(Block block) {
    final tp = fragmentPainter(style, block, 0, block.text.length, width: column.width);
    final metrics = tp.computeLineMetrics();
    final tops = <double>[];
    final heights = <double>[];
    final starts = <int>[];
    final shift = hasIndent(block, 0) ? 1 : 0;
    var y = 0.0;
    for (var i = 0; i < metrics.length; i++) {
      tops.add(y);
      heights.add(metrics[i].height);
      if (i == 0) {
        starts.add(0);
      } else {
        final pos = tp.getPositionForOffset(Offset(0.5, y + metrics[i].height / 2)).offset - shift;
        starts.add(pos.clamp(0, block.text.length));
      }
      y += metrics[i].height;
    }
    tp.dispose();
    return _Measured(tops, heights, starts);
  }
}

class _Measured {
  _Measured(this.lineTops, this.lineHeights, this.lineStarts);

  final List<double> lineTops;
  final List<double> lineHeights;
  final List<int> lineStarts;
}

/// Красная строка — только у абзаца и только в его начале.
bool hasIndent(Block block, int start) => block.kind == BlockKind.paragraph && start == 0;

/// Отступ слева у куска блока.
double fragmentInset(PageStyle style, Block block) =>
    style.isVerseLike(block.kind) ? style.insetVerse : 0;

/// Текст куска для измерения и отрисовки — один и тот же.
InlineSpan fragmentSpan(PageStyle style, Block block, int start, int end, {Color? color, Color? noteColor}) {
  return TextSpan(
    style: style.textStyleFor(block.kind).copyWith(color: color),
    children: [
      if (hasIndent(block, start))
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: SizedBox(width: style.indent, height: 1),
        ),
      ...style.spans(block, start, end, noteColor: noteColor),
    ],
  );
}

TextPainter fragmentPainter(PageStyle style, Block block, int start, int end, {required double width}) {
  final inset = fragmentInset(style, block);
  final tp = TextPainter(
    text: fragmentSpan(style, block, start, end),
    textDirection: TextDirection.ltr,
    strutStyle: style.strutFor(block.kind),
  );
  if (hasIndent(block, start)) {
    tp.setPlaceholderDimensions([
      PlaceholderDimensions(size: Size(style.indent, 1), alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: 1),
    ]);
  }
  tp.layout(maxWidth: width - inset);
  return tp;
}

InlineSpan headingSpan(PageStyle style, Block block, {Color? color, Color? subColor}) {
  final lines = block.text.split('\n');
  return TextSpan(children: [
    TextSpan(text: lines.first, style: style.headingTitle.copyWith(color: color)),
    for (final l in lines.skip(1)) TextSpan(text: '\n$l', style: style.headingSub.copyWith(color: subColor ?? color)),
  ]);
}
