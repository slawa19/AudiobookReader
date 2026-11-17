import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../book/model.dart';
import 'page_style.dart';

/// Observing actual measurements in tests; the book text is not passed here.
@visibleForTesting
void Function(int block, int start, int end)? debugPageMeasurement;

/// A piece of a block on a page: the text [start, end) of block [block] and its vertical place.
///
/// An image has two kinds of pieces: the image itself ([imageSize] set, text empty) and the caption lines (the caption
/// text, [imageSize] — `null`). A heading and a caption are split by lines the same way as a paragraph.
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

  /// For an image — the size it is fitted into.
  final Size? imageSize;

  bool get isImage => imageSize != null;
}

/// A page: a "start" and "end" pair (A§5) plus the layout of the pieces.
class BookPageLayout {
  const BookPageLayout({required this.chapter, required this.fragments});

  final int chapter;
  final List<PageFragment> fragments;

  int get firstBlock => fragments.first.block;
  int get firstOffset => fragments.first.start;
  int get lastBlock => fragments.last.block;
  int get lastEnd => fragments.last.end;


  /// Whether the place (block, offset) is on this page.
  bool contains(int block, int offset) {
    for (final f in fragments) {
      if (f.block == block && offset >= f.start && (offset < f.end || (offset == f.end && f.end == f.start))) {
        return true;
      }
    }
    return false;
  }
}

/// Computing a chapter from a saved place. The first page is ready after [start], each following one is computed
/// as a separate main-isolate event. The screen may draw [pages] without waiting for [isComplete].
/// A repeated [start] cancels the previous work; the place is passed explicitly, not derived from the new typography.
/// With [start] `throughBook: true` the computation continues across the boundaries of the following chapters to the
/// end of the book.
class ChapterPagination extends ChangeNotifier {
  late Book _book;
  late PageStyle _style;
  late Size _column;
  Map<String, Size> _imageSizes = const {};

  /// Indices in [pages] are local: when computing backwards, the start of the array shifts by this many pages.
  int get prependedCount => _prepended;
  int _prepended = 0;
  int _bookStart = 0;
  bool get hasPrevious => _pages.isNotEmpty &&
      (_pages.first.firstBlock > _bookStart || _pages.first.firstOffset > 0);
  bool get isLoadingPrevious => _backIterator != null;
  Timer? _backTimer;
  Iterator<BookPageLayout?>? _backIterator;
  final List<BookPageLayout> _before = [];
  Completer<int>? _backDone;
  int _backChapter = 0;

  /// The end of the book is known from the page's own coordinates, without waiting for the next batch of computation.
  bool endsBook(BookPageLayout page) {
    if (page.lastEnd != _book.blocks[page.lastBlock].text.length) return false;
    for (var b = page.lastBlock + 1; b < _book.blocks.length; b++) {
      if (_book.blocks[b].text.isNotEmpty || _visualEmpty(_book.blocks[b])) return false;
    }
    return true;
  }

  /// The end of a text block belongs to the next block. Empty images and dividers are visible places.
  (int, int) _place(int block, int offset) {
    block = block.clamp(0, _book.blocks.length - 1);
    offset = offset.clamp(0, _book.blocks[block].text.length);
    while (block < _book.blocks.length) {
      final b = _book.blocks[block];
      if (offset < b.text.length || (b.text.isEmpty && _visualEmpty(b))) return (block, offset);
      block++;
      offset = 0;
    }
    return (_book.blocks.length, 0);
  }

  bool _visualEmpty(Block b) => b.kind == BlockKind.image || b.kind == BlockKind.separator;
  /// The number of the page the place (block, offset) is on.
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

  /// The ready page of a place. In an overlap the next one is chosen, except the held first [preferredPage].
  /// The last known page does not yet mean the end of the book.
  int? findPage(int block, int offset, {int? preferredPage}) {
    if (_pages.isEmpty) return null;
    final place = _place(block, offset);
    if (place.$1 == _book.blocks.length) return endsBook(_pages.last) ? _pages.length - 1 : null;
    block = place.$1;
    offset = place.$2;
    // Only the first page of a chapter has an overlap. While the reader is on it, the voice does not change it.
    // In other cases a binary search picks the next page with this place.
    if (preferredPage != null && preferredPage >= 0 && preferredPage < _pages.length) {
      final preferred = _pages[preferredPage];
      final chapterStart = _place(_book.chapters[preferred.chapter].firstBlock, 0);
      if (preferred.firstBlock == chapterStart.$1 && preferred.firstOffset == 0 &&
          preferred.contains(block, offset)) {
        return preferredPage;
      }
    }
    final i = pageOf(block, offset);
    final page = _pages[i];
    return page.contains(block, offset) ||
        (isComplete && block == page.lastBlock && offset == page.lastEnd) ? i : null;
  }

  final List<BookPageLayout> _pages = [];
  late final List<BookPageLayout> pages = UnmodifiableListView(_pages);
  bool get isCalculating => (!_paused && _iterator != null) || _backIterator != null;
  bool get isComplete => _complete;
  bool _complete = false;
  bool _paused = false;
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
    _prepended = 0;
    _book = book;
    _bookStart = 0;
    while (_bookStart < book.blocks.length - 1 && book.blocks[_bookStart].text.isEmpty &&
        !_visualEmpty(book.blocks[_bookStart])) { _bookStart++; }
    _style = style;
    _column = column;
    _imageSizes = imageSizes;
    var place = _place(block, offset);
    if (place.$1 == book.blocks.length) {
      // For a position past the last character, a bounded tail of the last visible block is enough.
      // Its last page becomes the start point; the preceding text is attached by the usual backward move.
      var last = book.blocks.length - 1;
      while (last > 0 && book.blocks[last].text.isEmpty && !_visualEmpty(book.blocks[last])) { last--; }
      var tail = math.max(0, book.blocks[last].text.length - 4096);
      if (tail > 0 && book.blocks[last].text.codeUnitAt(tail) >= 0xDC00 &&
          book.blocks[last].text.codeUnitAt(tail) <= 0xDFFF) { tail--; }
      final pages = _Paginator(book, style, column, imageSizes)
          .chapter(book.chapterOf(last), firstBlock: last, firstOffset: tail).toList();
      place = (pages.last.firstBlock, pages.last.firstOffset);
    }
    block = place.$1;
    offset = place.$2;
    final chapter = book.chapterOf(block);
    _iterator = _Paginator(book, style, column, imageSizes)
        .fromPosition(chapter, block, offset, throughBook).iterator;
    _advance(_generation);
  }

  /// Prefix lines are measured in batches, pages are assembled from the end up to the already shown start.
  /// Pages are added with a single insertion: a visible piece and its boundaries are never replaced.
  Future<int> loadPrevious() {
    if (_backDone != null) return _backDone!.future;
    if (!hasPrevious) return Future.value(0);
    final first = _pages.first;
    var chapter = _book.chapterOf(first.firstBlock);
    final atChapterStart = first.firstBlock == _book.chapters[chapter].firstBlock && first.firstOffset == 0;
    if (atChapterStart) chapter--;
    _backChapter = chapter;
    _before.clear();
    _backDone = Completer<int>();
    _backIterator = _Paginator(_book, _style, _column, _imageSizes).before(chapter,
        stopBlock: first.firstBlock, stopOffset: first.firstOffset).iterator;
    final generation = _generation;
    _backTimer = Timer(const Duration(milliseconds: 1), () => _advanceBack(generation));
    return _backDone!.future;
  }

  void _advanceBack(int generation) {
    if (generation != _generation) return;
    final iterator = _backIterator;
    if (iterator == null) return;
    if (iterator.moveNext()) {
      final page = iterator.current;
      if (page != null) _before.add(page);
      _backTimer = Timer(const Duration(milliseconds: 1), () => _advanceBack(generation));
    } else {
      if (_before.isEmpty && _backChapter > 0) {
        // An empty chapter or an empty prefix of its own chapter does not delay moving backwards.
        _backIterator = _Paginator(_book, _style, _column, _imageSizes).before(--_backChapter).iterator;
        _backTimer = Timer(const Duration(milliseconds: 1), () => _advanceBack(generation));
        notifyListeners();
        return;
      }
      final count = _before.length;
      _pages.insertAll(0, _before.reversed);
      _prepended += count;
      _before.clear();
      _backIterator = null;
      _backTimer = null;
      final done = _backDone!;
      _backDone = null;
      _updateChapterFirsts();
      done.complete(count);
    }
    notifyListeners();
  }

  void _updateChapterFirsts() {
    chapterFirstPage.clear();
    for (var i = 0; i < _pages.length; i++) {
      if (i == 0 || _pages[i - 1].chapter != _pages[i].chapter) chapterFirstPage.add(i);
    }
  }

  void _advance(int generation) {
    if (generation != _generation) return;
    final iterator = _iterator;
    if (iterator == null) return;
    if (iterator.moveNext()) {
      if (_pages.isEmpty || _pages.last.chapter != iterator.current.chapter) chapterFirstPage.add(_pages.length);
      _pages.add(iterator.current);
      // A short pause leaves room for a frame and input events between batches, including in test clocks.
      _timer = Timer(const Duration(milliseconds: 1), () => _advance(generation));
    } else {
      _iterator = null;
      _timer = null;
      _complete = true;
    }
    notifyListeners();
  }

  /// The next batch with the same iterator. Re-layout may finish computing the bounded text of the old
  /// visible page up to the held place before the first display; the book up to that page is not computed.
  void advancePage() {
    if (_paused) return;
    _timer?.cancel();
    _timer = null;
    _advance(_generation);
  }

  /// While another target is being searched, the visible pages and the iterator stay for a possible return.
  void pause() {
    _paused = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    cancelPrevious();
  }

  /// Continues the tail without re-measuring or replacing already shown pages.
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_iterator != null) {
      final generation = _generation;
      _timer = Timer(const Duration(milliseconds: 1), () => _advance(generation));
    }
  }

  /// After cancellation there are no more measurements or notifications from the old computation.
  void cancel() {
    _paused = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _iterator = null;
    cancelPrevious();
  }

  /// A newer forward command drops an unneeded backward request without stopping the tail computation.
  void cancelPrevious() {
    _backTimer?.cancel();
    _backTimer = null;
    _backIterator = null;
    _before.clear();
    _backDone?.complete(0);
    _backDone = null;
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

  int? _stopBlock;
  int _stopOffset = 0;

  Iterable<BookPageLayout> chapter(int c, {int? firstBlock, int firstOffset = 0,
      int? stopBlock, int stopOffset = 0}) sync* {
    _stopBlock = stopBlock;
    _stopOffset = stopOffset;
    final ch = book.chapters[c];
    _cur = [];
    _y = 0;
    _chapter = c;
    BlockKind? prevKind;

    for (var i = firstBlock ?? ch.firstBlock; i < ch.endBlock; i++) {
      if (stopBlock != null && (i > stopBlock || (i == stopBlock && stopOffset == 0))) break;
      final block = book.blocks[i];
      final start = i == firstBlock ? firstOffset : 0;
      switch (block.kind) {
        case BlockKind.heading:
          final top = _headingBefore(c, i, start);
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
    if (_cur.isNotEmpty) {
      yield _flush();
    }
  }

  /// An empty batch yields a frame after measuring one page. Ready pages go from the nearest one backwards.
  Iterable<BookPageLayout?> before(int c, {int? stopBlock, int stopOffset = 0}) sync* {
    final prefix = <BookPageLayout>[];
    for (final page in chapter(c, stopBlock: stopBlock, stopOffset: stopOffset)) {
      prefix.add(page);
      yield null;
    }
    if (stopBlock == null || stopBlock >= book.chapters[c].endBlock) {
      // The previous chapter is shown in its ordinary forward layout, including its short end.
      yield* prefix.reversed;
      return;
    }
    final units = <_BackUnit>[];
    for (final page in prefix) {
      units.addAll(_backUnits(page));
      yield null;
    }
    final current = ListQueue<_BackUnit>();
    var height = 0.0;
    for (final unit in units.reversed) {
      double withUnit() => unit.topBefore + unit.height + (current.isEmpty ? 0 :
          unit.after + current.first.before + height - current.first.topBefore);
      if (current.isNotEmpty && withUnit() > column.height + 0.01) {
        yield _backPage(c, current);
        current.clear();
        height = 0;
      }
      height = withUnit();
      current.addFirst(unit);
    }
    if (current.isNotEmpty) {
      // The remainder at the start of a chapter is not shown as short: an ordinary first page may
      // repeat the last lines on the next one. Other boundaries stay non-overlapping.
      yield _Paginator(book, style, column, imageSizes).chapter(c).first;
    }
  }

  List<_BackUnit> _backUnits(BookPageLayout page) {
    final out = <_BackUnit>[];
    final ch = book.chapters[page.chapter];
    for (final f in page.fragments) {
      final b = book.blocks[f.block];
      if (f.isImage) {
        out.add(_BackUnit([PageFragment(block: f.block, start: 0, end: 0, top: 0,
            height: f.height, imageSize: f.imageSize)], f.height, before: lh * 0.6,
            after: b.text.isEmpty ? lh * 0.6 : 0));
        continue;
      }
      if (b.kind == BlockKind.separator) {
        out.add(_BackUnit([PageFragment(block: f.block, start: f.start, end: f.end, top: 0, height: lh)],
            lh, before: lh, after: lh));
        continue;
      }
      final heading = b.kind == BlockKind.heading;
      final before = f.start > 0 ? 0.0 : heading ? _headingBefore(page.chapter, f.block, f.start)
          : b.kind == BlockKind.image ? lh * 0.3
          : _spacingBefore(f.block == ch.firstBlock ? null : book.blocks[f.block - 1].kind, b.kind);
      final after = f.end != b.text.length ? 0.0 : heading ? lh * 1.2 : b.kind == BlockKind.image ? lh * 0.6 : 0.0;
      // A small heading stays whole, as in the forward layout.
      if (heading && f.start == 0 && f.end == b.text.length && before + f.height <= column.height) {
        out.add(_BackUnit([PageFragment(block: f.block, start: f.start, end: f.end, top: 0, height: f.height)],
            f.height, before: before, topBefore: before, after: after));
        continue;
      }
      final measured = _measure(b, f.start, f.end);
      for (var i = 0; i < measured.lineStarts.length; i++) {
        final row = PageFragment(block: f.block, start: measured.lineStarts[i],
            end: i + 1 < measured.lineStarts.length ? measured.lineStarts[i + 1] : f.end,
            top: 0, height: measured.lineHeights[i]);
        final first = i == 0;
        final last = i == measured.lineStarts.length - 1;
        if (b.kind == BlockKind.image && row.start == 0 && out.isNotEmpty && out.last.fragments.last.isImage) {
          // An image and the first caption line are moved together.
          final image = out.removeLast();
          out.add(_BackUnit([...image.fragments, PageFragment(block: row.block, start: row.start, end: row.end,
              top: image.height + before, height: row.height)], image.height + before + row.height,
              before: image.before, after: last ? after : 0));
        } else {
          out.add(_BackUnit([row], row.height, before: first ? before : 0,
              topBefore: heading && first ? before : 0, after: last ? after : 0));
        }
      }
    }
    return out;
  }

  BookPageLayout _backPage(int c, Iterable<_BackUnit> units) {
    final fragments = <PageFragment>[];
    var y = 0.0;
    for (final unit in units) {
      y += fragments.isEmpty ? unit.topBefore : unit.before;
      for (final f in unit.fragments) {
        final top = y + f.top;
        final previous = fragments.isEmpty ? null : fragments.last;
        if (!f.isImage && previous != null && !previous.isImage && previous.block == f.block &&
            previous.end == f.start && (previous.top + previous.height - top).abs() < 0.01) {
          fragments[fragments.length - 1] = PageFragment(block: f.block, start: previous.start, end: f.end,
              top: previous.top, height: previous.height + f.height);
        } else {
          fragments.add(PageFragment(block: f.block, start: f.start, end: f.end,
              top: top, height: f.height, imageSize: f.imageSize));
        }
      }
      y += unit.height + unit.after;
    }
    return BookPageLayout(chapter: c, fragments: fragments);
  }

  /// Even one huge paragraph is measured in windows. The unfinished last line of a window is measured again
  /// with the next window: a window boundary does not become an artificial line break.
  Iterable<BookPageLayout> _placeText(int i, int start,
      {double before = 0, bool beforeAtPageTop = false, double after = 0, bool keepTogether = false}) sync* {
    final block = book.blocks[i];
    var at = start;
    final limit = i == _stopBlock ? math.min(block.text.length, _stopOffset) : block.text.length;
    if (at >= limit) return;
    do {
      var end = math.min(at + 4096, limit);
      // A window does not split a UTF-16 surrogate pair.
      if (end < limit && end > at && block.text.codeUnitAt(end - 1) >= 0xD800 &&
          block.text.codeUnitAt(end - 1) <= 0xDBFF) {
        end--;
      }
      // An unfinished word may change the wrap of the window's second-to-last line too. When possible,
      // end the window at a space; the last line still stays for the next measurement.
      if (end < limit) {
        final boundary = block.text.substring(at, end).lastIndexOf(RegExp(r'\s'));
        if (boundary >= 0) end = at + boundary + 1;
      }
      var measured = _measure(block, at, end);
      if (end < limit && measured.lineStarts.length > 1) {
        end = measured.lineStarts.last;
        measured = _Measured(measured.lineHeights.sublist(0, measured.lineHeights.length - 1),
            measured.lineStarts.sublist(0, measured.lineStarts.length - 1), end);
      }
      yield* _placeLines(i, measured, before: at == start ? before : 0,
          beforeAtPageTop: beforeAtPageTop, after: end == limit ? after : 0,
          keepTogether: keepTogether && at == start && end == limit);
      at = end;
    } while (at < limit);
  }

  /// Puts the piece's lines onto pages. [before] — the gap before the first line (at the page top — only with
  /// [beforeAtPageTop]); [keepTogether] — do not split if it fits whole on an empty page.
  Iterable<BookPageLayout> _placeLines(int i, _Measured m,
      {double before = 0, bool beforeAtPageTop = false, double after = 0, bool keepTogether = false}) sync* {
    if (m.lineHeights.isEmpty) return;
    final total = m.lineHeights.fold(0.0, (a, b) => a + b);
    if (keepTogether && _cur.isNotEmpty) {
      final fitsEmpty = before + total <= column.height;
      if (fitsEmpty && _y + before + total > column.height) yield _flush();
    }
    var first = true;
    while (m.lineHeights.isNotEmpty) {
      final sp = !first ? 0.0 : (_cur.isEmpty && !beforeAtPageTop ? 0.0 : before);
      final avail = column.height - _y - sp;
      var k = 0;
      var h = 0.0;
      while (k < m.lineHeights.length && h + m.lineHeights[k] <= avail + 0.01) {
        h += m.lineHeights[k];
        k++;
      }
      if (k == 0) {
        if (_cur.isNotEmpty) {
          yield _flush();
          continue;
        }
        // A line taller than an empty page (a huge font size) — put one, otherwise pagination will not advance.
        h = m.lineHeights.first;
        k = 1;
      }
      final start = m.lineStarts.first;
      var end = k < m.lineStarts.length ? m.lineStarts[k] : m.end;
      // A break inside a long word changes the wrap of the last line. We check exactly the piece
      // that will be drawn, and after the break measure the remaining text again from the new start.
      h = _measure(book.blocks[i], start, end).lineHeights.fold(0.0, (a, b) => a + b);
      while (h > avail + 0.01 && k > 1) {
        k--;
        end = m.lineStarts[k];
        h = _measure(book.blocks[i], start, end).lineHeights.fold(0.0, (a, b) => a + b);
      }
      if (h > avail + 0.01 && _cur.isNotEmpty) {
        yield _flush();
        continue;
      }
      _cur.add(PageFragment(block: i, start: start, end: end, top: _y + sp, height: h));
      _y += sp + h;
      first = false;
      if (end == m.end) break;
      yield _flush();
      m = _measure(book.blocks[i], end, m.end);
    }
    _y += after;
  }

  /// An image is fitted into the page together with the first caption line; a long caption continues in pieces.
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

  double _headingBefore(int c, int block, int start) {
    final ch = book.chapters[c];
    // A section of only a heading is a title page: the heading is lower than usual.
    return start > 0 ? 0 : ch.blockCount == 1 ? column.height * 0.28 : block == ch.firstBlock ? lh : lh * 1.5;
  }

  /// An image the full width of the column, but not taller than 62 % of the page and not taller than [maxHeight].
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
    debugPageMeasurement?.call(block.index, start, end);
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
        // The line start is the position at the line's left edge. For center alignment (heading, caption) the line's
        // own start is to the left of the text.
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

/// An indivisible part of a backward page: a line, a small heading or an image with the start of its caption.
class _BackUnit {
  _BackUnit(this.fragments, this.height, {this.before = 0, this.topBefore = 0, this.after = 0});
  final List<PageFragment> fragments;
  final double height, before, topBefore, after;
}

/// A first-line indent only for a paragraph and only at its start.
bool hasIndent(Block block, int start) => block.kind == BlockKind.paragraph && start == 0;

/// The left indent of a block piece.
double fragmentInset(PageStyle style, Block block) => style.isVerseLike(block.kind) ? style.insetVerse : 0;

/// The text of a piece for measuring and drawing is one and the same: a paragraph, verse, quote, heading or image
/// caption.
InlineSpan pieceSpan(PageStyle style, Block block, int start, int end, {Color? color, Color? subColor, Color? noteColor}) {
  // A piece cut off right after a line break (verse, heading) is drawn without it: otherwise an extra empty line
  // would appear at the bottom of the piece.
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

/// A heading: the first line is large, the rest (after `\n`) are italic. A piece [start, end) keeps the style
/// of its line, so a long heading is split by lines like a paragraph.
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
