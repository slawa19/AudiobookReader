import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../book/model.dart';
import 'page_style.dart';

/// Кусок блока на странице: текст [start, end) блока [block] и его место по вертикали.
///
/// У картинки два вида кусков: сама картинка ([imageSize] задан, текст пуст) и строки подписи (текст подписи,
/// [imageSize] — `null`). Заголовок и подпись делятся по строкам так же, как абзац.
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

  bool get isImage => imageSize != null;
}

/// Страница: пара «начало» и «конец» (А§5) плюс раскладка кусков.
class BookPageLayout {
  const BookPageLayout({required this.chapter, required this.fragments});

  final int chapter;
  final List<PageFragment> fragments;

  int get firstBlock => fragments.first.block;
  int get firstOffset => fragments.first.start;
  int get lastBlock => fragments.last.block;
  int get lastEnd => fragments.last.end;

  bool containsBlock(int block) => block >= firstBlock && block <= lastBlock;

  /// Стоит ли место (блок, смещение) на этой странице.
  bool contains(int block, int offset) {
    for (final f in fragments) {
      if (f.block == block && offset >= f.start && (offset < f.end || (offset == f.end && f.end == f.start))) {
        return true;
      }
    }
    return false;
  }
}

/// Расчёт главы от сохранённого места. Первая страница готова после [start], каждая следующая считается
/// отдельным событием главного изолята. Экран может рисовать [pages], не дожидаясь [isComplete].
/// Повторный [start] отменяет прежнюю работу; место передаётся явно, а не выводится из новой типографики.
/// С [start] `throughBook: true` расчёт продолжается через границы следующих глав до конца книги.
class ChapterPagination extends ChangeNotifier {
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

  final List<int> chapterFirstPage = [];

  /// Готовая страница места. Последняя известная страница ещё не означает конец книги.
  int? findPage(int block, int offset) {
    if (_pages.isEmpty) return null;
    final i = pageOf(block, offset);
    final page = _pages[i];
    return page.contains(block, offset) ||
        (isComplete && block == page.lastBlock && offset == page.lastEnd) ? i : null;
  }

  final List<BookPageLayout> _pages = [];
  late final List<BookPageLayout> pages = UnmodifiableListView(_pages);
  bool get isCalculating => _iterator != null;
  bool get isComplete => _complete;
  bool _complete = false;
  Timer? _timer;
  Iterator<BookPageLayout>? _iterator;
  int _generation = 0;

  void start({
    required Book book,
    required PageStyle style,
    required Size column,
    required int block,
    required int offset,
    bool throughBook = false,
    Map<String, Size> imageSizes = const {},
  }) {
    cancel();
    _complete = false;
    _pages.clear();
    chapterFirstPage.clear();
    final chapter = book.chapterOf(block);
    _iterator = _Paginator(book, style, column, imageSizes)
        .fromPosition(chapter, block, offset, throughBook).iterator;
    _advance(_generation);
  }

  void _advance(int generation) {
    if (generation != _generation) return;
    final iterator = _iterator;
    if (iterator == null) return;
    if (iterator.moveNext()) {
      if (_pages.isEmpty || _pages.last.chapter != iterator.current.chapter) chapterFirstPage.add(_pages.length);
      _pages.add(iterator.current);
      // Короткая пауза оставляет место кадру и событиям ввода между порциями, в том числе в тестовых часах.
      _timer = Timer(const Duration(milliseconds: 1), () => _advance(generation));
    } else {
      _iterator = null;
      _timer = null;
      _complete = true;
    }
    notifyListeners();
  }

  /// После отмены ни измерений, ни уведомлений от старого расчёта больше нет.
  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _iterator = null;
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

class _Paginator {
  _Paginator(this.book, this.style, this.column, this.imageSizes);

  final Book book;
  final PageStyle style;
  final Size column;
  final Map<String, Size> imageSizes;

  double get lh => style.lineHeight;

  late List<PageFragment> _cur;
  late double _y;
  late int _chapter;

  BookPageLayout _flush() {
    final page = BookPageLayout(chapter: _chapter, fragments: _cur);
    _cur = <PageFragment>[];
    _y = 0;
    return page;
  }

  Iterable<BookPageLayout> fromPosition(int c, int block, int offset, bool throughBook) sync* {
    yield* chapter(c, firstBlock: block, firstOffset: offset);
    if (throughBook) {
      for (var next = c + 1; next < book.chapters.length; next++) {
        yield* chapter(next);
      }
    }
  }

  Iterable<BookPageLayout> chapter(int c, {int? firstBlock, int firstOffset = 0}) sync* {
    final ch = book.chapters[c];
    _cur = [];
    _y = 0;
    _chapter = c;
    BlockKind? prevKind;

    // Раздел только из заголовка («Ионыч» перед главой I) — страница-заглавие: заголовок ниже обычного.
    final titleOnly = ch.blockCount == 1 && book.blocks[ch.firstBlock].kind == BlockKind.heading;

    for (var i = firstBlock ?? ch.firstBlock; i < ch.endBlock; i++) {
      final block = book.blocks[i];
      final start = i == firstBlock ? firstOffset : 0;
      switch (block.kind) {
        case BlockKind.heading:
          final top = start > 0 ? 0.0 : titleOnly ? column.height * 0.28 : (i == ch.firstBlock ? lh * 1.0 : lh * 1.5);
          yield* _placeText(i, start,
              before: top, beforeAtPageTop: true, after: lh * 1.2, keepTogether: true);
        case BlockKind.image:
          if (start == 0) {
            yield* _placeImage(i, block, gap: _cur.isEmpty ? 0.0 : lh * 0.6);
          } else {
            yield* _placeText(i, start, after: lh * 0.6);
          }
        case BlockKind.separator:
          final sp = _cur.isEmpty ? 0.0 : lh;
          if (_cur.isNotEmpty && _y + sp + lh > column.height) yield _flush();
          final spNow = _cur.isEmpty ? 0.0 : sp;
          _cur.add(PageFragment(block: i, start: 0, end: block.text.length, top: _y + spNow, height: lh));
          _y += spNow + lh * 2;
        case BlockKind.paragraph:
        case BlockKind.verse:
        case BlockKind.cite:
          yield* _placeText(i, start, before: _spacingBefore(prevKind, block.kind));
      }
      prevKind = block.kind;
    }
    if (_cur.isNotEmpty) yield _flush();
  }

  /// Даже один огромный абзац измеряется окнами. Незавершённую последнюю строку окна измеряем заново
  /// со следующим окном: граница окна не становится искусственным переносом строки.
  Iterable<BookPageLayout> _placeText(int i, int start,
      {double before = 0, bool beforeAtPageTop = false, double after = 0, bool keepTogether = false}) sync* {
    final block = book.blocks[i];
    var at = start;
    do {
      var end = math.min(at + 4096, block.text.length);
      // Окно не разрезает суррогатную пару UTF-16.
      if (end < block.text.length && end > at && block.text.codeUnitAt(end - 1) >= 0xD800 &&
          block.text.codeUnitAt(end - 1) <= 0xDBFF) {
        end--;
      }
      // Незавершённое слово может изменить перенос и предпоследней строки окна. По возможности
      // заканчиваем окно на пробеле; последняя строка всё равно остаётся для следующего измерения.
      if (end < block.text.length) {
        final boundary = block.text.substring(at, end).lastIndexOf(RegExp(r'\s'));
        if (boundary >= 0) end = at + boundary + 1;
      }
      var measured = _measure(block, at, end);
      if (end < block.text.length && measured.lineStarts.length > 1) {
        end = measured.lineStarts.last;
        measured = _Measured(measured.lineHeights.sublist(0, measured.lineHeights.length - 1),
            measured.lineStarts.sublist(0, measured.lineStarts.length - 1), end);
      }
      yield* _placeLines(i, measured, before: at == start ? before : 0,
          beforeAtPageTop: beforeAtPageTop, after: end == block.text.length ? after : 0,
          keepTogether: keepTogether && at == start && end == block.text.length);
      at = end;
    } while (at < block.text.length);
  }

  /// Кладёт строки куска на страницы. [before] — отступ перед первой строкой (у начала страницы — только при
  /// [beforeAtPageTop]); [keepTogether] — не делить, если целиком помещается на пустую страницу.
  Iterable<BookPageLayout> _placeLines(int i, _Measured m,
      {double before = 0, bool beforeAtPageTop = false, double after = 0, bool keepTogether = false}) sync* {
    if (m.lineHeights.isEmpty) return;
    final total = m.lineHeights.fold(0.0, (a, b) => a + b);
    if (keepTogether && _cur.isNotEmpty) {
      final fitsEmpty = before + total <= column.height;
      if (fitsEmpty && _y + before + total > column.height) yield _flush();
    }
    var line = 0;
    while (line < m.lineHeights.length) {
      final sp = line > 0 ? 0.0 : (_cur.isEmpty && !beforeAtPageTop ? 0.0 : before);
      final avail = column.height - _y - sp;
      var k = 0;
      var h = 0.0;
      while (line + k < m.lineHeights.length && h + m.lineHeights[line + k] <= avail + 0.01) {
        h += m.lineHeights[line + k];
        k++;
      }
      if (k == 0) {
        if (_cur.isNotEmpty) {
          yield _flush();
          continue;
        }
        // Строка выше пустой страницы (огромный кегль) — кладём одну, иначе разбивка не продвинется.
        h = m.lineHeights[line];
        k = 1;
      }
      final start = m.lineStarts[line];
      final end = line + k < m.lineStarts.length ? m.lineStarts[line + k] : m.end;
      _cur.add(PageFragment(block: i, start: start, end: end, top: _y + sp, height: h));
      _y += sp + h;
      line += k;
      if (line < m.lineHeights.length) yield _flush();
    }
    _y += after;
  }

  /// Картинка вписывается в страницу вместе с первой строкой подписи; длинная подпись продолжается кусками.
  Iterable<BookPageLayout> _placeImage(int i, Block block, {required double gap}) sync* {
    final caption = block.text.isEmpty ? null : _measure(block, 0, math.min(4096, block.text.length));
    final captionGap = caption == null ? 0.0 : lh * 0.3;
    final firstLine = caption == null ? 0.0 : caption.lineHeights.first;
    var size = _imageBox(block, column.height - captionGap - firstLine);
    if (_cur.isNotEmpty && _y + gap + size.height + captionGap + firstLine > column.height) yield _flush();
    final g = _cur.isEmpty ? 0.0 : gap;
    if (_cur.isEmpty) size = _imageBox(block, column.height - captionGap - firstLine);
    _cur.add(PageFragment(block: i, start: 0, end: 0, top: _y + g, height: size.height, imageSize: size));
    _y += g + size.height;
    if (caption != null) yield* _placeText(i, 0, before: captionGap);
    _y += lh * 0.6;
  }

  double _spacingBefore(BlockKind? prev, BlockKind kind) {
    if (prev == null) return 0;
    final a = style.isVerseLike(prev);
    final b = style.isVerseLike(kind);
    if (a != b) return lh * 0.6;
    if (a && b && prev != kind) return lh * 0.15;
    return 0;
  }

  /// Картинка во всю ширину колонки, но не выше 62 % страницы и не выше [maxHeight].
  Size _imageBox(Block block, double maxHeight) {
    final natural = imageSizes[block.imageId] ?? const Size(4, 3);
    final maxH = math.max(lh * 2, math.min(column.height * 0.62, maxHeight));
    var w = column.width;
    var h = w * natural.height / natural.width;
    if (h > maxH) {
      h = maxH;
      w = h * natural.width / natural.height;
    }
    return Size(w, h);
  }

  _Measured _measure(Block block, int start, int end) {
    final tp = piecePainter(style, block, start, end, width: column.width);
    final metrics = tp.computeLineMetrics();
    final heights = <double>[];
    final starts = <int>[];
    final shift = hasIndent(block, start) ? 1 : 0;
    var y = 0.0;
    for (var i = 0; i < metrics.length; i++) {
      heights.add(metrics[i].height);
      if (i == 0) {
        starts.add(start);
      } else {
        // Начало строки — позиция у левого края строки. Для выравнивания по центру (заголовок, подпись) левее
        // текста стоит её же начало.
        final pos = tp.getPositionForOffset(Offset(0.5, y + metrics[i].height / 2)).offset - shift + start;
        starts.add(math.max(starts.last + 1, pos.clamp(start, end)));
      }
      y += metrics[i].height;
    }
    tp.dispose();
    return _Measured(heights, starts, end);
  }
}

class _Measured {
  _Measured(this.lineHeights, this.lineStarts, this.end);

  final List<double> lineHeights;
  final List<int> lineStarts;
  final int end;
}

/// Красная строка — только у абзаца и только в его начале.
bool hasIndent(Block block, int start) => block.kind == BlockKind.paragraph && start == 0;

/// Отступ слева у куска блока.
double fragmentInset(PageStyle style, Block block) => style.isVerseLike(block.kind) ? style.insetVerse : 0;

/// Текст куска для измерения и отрисовки — один и тот же: абзац, стих, цитата, заголовок или подпись картинки.
InlineSpan pieceSpan(PageStyle style, Block block, int start, int end, {Color? color, Color? subColor, Color? noteColor}) {
  // Кусок, оборванный сразу после перевода строки (стихи, заголовок), рисуется без него: иначе внизу куска
  // появилась бы лишняя пустая строка.
  if (end > start && block.text.codeUnitAt(end - 1) == 0x0A) end--;
  switch (block.kind) {
    case BlockKind.heading:
      return _headingSpan(style, block, start, end, color: color, subColor: subColor, noteColor: noteColor);
    case BlockKind.image:
      return TextSpan(
        style: style.caption.copyWith(color: subColor ?? color),
        children: style.spans(block, start, end, noteColor: noteColor),
      );
    default:
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
}

TextAlign pieceAlign(Block block) =>
    block.kind == BlockKind.heading || block.kind == BlockKind.image ? TextAlign.center : TextAlign.start;

StrutStyle? pieceStrut(PageStyle style, Block block) => switch (block.kind) {
      BlockKind.paragraph || BlockKind.verse || BlockKind.cite => style.strutFor(block.kind),
      _ => null,
    };

TextPainter piecePainter(PageStyle style, Block block, int start, int end, {required double width}) {
  final tp = TextPainter(
    text: pieceSpan(style, block, start, end),
    textAlign: pieceAlign(block),
    textDirection: TextDirection.ltr,
    strutStyle: pieceStrut(style, block),
  );
  if (hasIndent(block, start)) {
    tp.setPlaceholderDimensions([
      PlaceholderDimensions(
          size: Size(style.indent, 1),
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 1),
    ]);
  }
  tp.layout(maxWidth: width - fragmentInset(style, block));
  return tp;
}

/// Заголовок: первая строка — крупно, остальные (после `\n`) — курсивом. Кусок [start, end) сохраняет стиль
/// своей строки, поэтому длинный заголовок делится по строкам, как абзац.
InlineSpan _headingSpan(PageStyle style, Block block, int start, int end, {Color? color, Color? subColor, Color? noteColor}) {
  final text = block.text;
  final children = <InlineSpan>[];
  var lineStart = 0;
  var lineNo = 0;
  while (lineStart <= text.length) {
    final nl = text.indexOf('\n', lineStart);
    final lineEnd = nl < 0 ? text.length : nl + 1;
    final a = math.max(start, lineStart);
    final b = math.min(end, lineEnd);
    if (a < b) {
      children.add(TextSpan(
        children: style.spans(block, a, b, noteColor: noteColor),
        style: lineNo == 0 ? style.headingTitle.copyWith(color: color) : style.headingSub.copyWith(color: subColor ?? color),
      ));
    }
    if (nl < 0) break;
    lineStart = lineEnd;
    lineNo++;
  }
  return TextSpan(children: children);
}
