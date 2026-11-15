import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../book/model.dart';
import 'page_style.dart';

/// Наблюдение за фактическими измерениями в тестах; текст книги сюда не передаётся.
@visibleForTesting
void Function(int block, int start, int end)? debugPageMeasurement;

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
  late Book _book;
  late PageStyle _style;
  late Size _column;
  Map<String, Size> _imageSizes = const {};

  /// Индексы в [pages] локальны: при досчёте назад начало массива сдвигается на это число страниц.
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

  /// Конец книги известен из координат самой страницы, без ожидания следующей порции расчёта.
  bool endsBook(BookPageLayout page) {
    if (page.lastEnd != _book.blocks[page.lastBlock].text.length) return false;
    for (var b = page.lastBlock + 1; b < _book.blocks.length; b++) {
      if (_book.blocks[b].text.isNotEmpty || _visualEmpty(_book.blocks[b])) return false;
    }
    return true;
  }

  /// Конец текстового блока относится к следующему блоку. Пустые картинки и разделители — видимые места.
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

  /// Готовая страница места. В перекрытии выбирается следующая, кроме удерживаемой первой [preferredPage].
  /// Последняя известная страница ещё не означает конец книги.
  int? findPage(int block, int offset, {int? preferredPage}) {
    if (_pages.isEmpty) return null;
    final place = _place(block, offset);
    if (place.$1 == _book.blocks.length) return endsBook(_pages.last) ? _pages.length - 1 : null;
    block = place.$1;
    offset = place.$2;
    // Перекрытие есть только у первой страницы главы. Пока читатель на ней, голос её не меняет.
    // В остальных случаях двоичный поиск выбирает следующую страницу с этим местом.
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
      // Для позиции за последним знаком достаточно ограниченного хвоста последнего видимого блока.
      // Его последняя страница становится точкой старта; предшествующий текст подключается обычным ходом назад.
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

  /// Строки префикса измеряются порциями, страницы собираются с конца до уже показанного начала.
  /// Страницы добавляются одной вставкой: видимый кусок и его границы никогда не заменяются.
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
        // Пустая глава или пустой префикс собственной главы не задерживает продвижение назад.
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
      // Короткая пауза оставляет место кадру и событиям ввода между порциями, в том числе в тестовых часах.
      _timer = Timer(const Duration(milliseconds: 1), () => _advance(generation));
    } else {
      _iterator = null;
      _timer = null;
      _complete = true;
    }
    notifyListeners();
  }

  /// Следующая порция тем же итератором. Перераскладка может досчитать ограниченный текст старой
  /// видимой страницы до удерживаемого места перед первым показом; книга до этой страницы не считается.
  void advancePage() {
    if (_paused) return;
    _timer?.cancel();
    _timer = null;
    _advance(_generation);
  }

  /// Пока ищется другая цель, видимые страницы и итератор остаются для возможного возврата.
  void pause() {
    _paused = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    cancelPrevious();
  }

  /// Продолжает хвост без повторного измерения или замены уже показанных страниц.
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_iterator != null) {
      final generation = _generation;
      _timer = Timer(const Duration(milliseconds: 1), () => _advance(generation));
    }
  }

  /// После отмены ни измерений, ни уведомлений от старого расчёта больше нет.
  void cancel() {
    _paused = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _iterator = null;
    cancelPrevious();
  }

  /// Более новая команда вперёд снимает ненужный запрос назад, не останавливая расчёт хвоста.
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

  /// Пустая порция отдаёт кадр после измерения одной страницы. Готовые страницы идут от ближайшей назад.
  Iterable<BookPageLayout?> before(int c, {int? stopBlock, int stopOffset = 0}) sync* {
    final prefix = <BookPageLayout>[];
    for (final page in chapter(c, stopBlock: stopBlock, stopOffset: stopOffset)) {
      prefix.add(page);
      yield null;
    }
    if (stopBlock == null || stopBlock >= book.chapters[c].endBlock) {
      // Предыдущая глава показывается в своей обычной прямой раскладке, включая её короткий конец.
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
      // Остаток у начала главы не показывается коротким: обычная первая страница может
      // повторить последние строки на следующей. Другие границы остаются непересекающимися.
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
      // Небольшой заголовок остаётся целым, как в прямой раскладке.
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
          // Картинка и первая строка подписи переносятся вместе.
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

  /// Даже один огромный абзац измеряется окнами. Незавершённую последнюю строку окна измеряем заново
  /// со следующим окном: граница окна не становится искусственным переносом строки.
  Iterable<BookPageLayout> _placeText(int i, int start,
      {double before = 0, bool beforeAtPageTop = false, double after = 0, bool keepTogether = false}) sync* {
    final block = book.blocks[i];
    var at = start;
    final limit = i == _stopBlock ? math.min(block.text.length, _stopOffset) : block.text.length;
    if (at >= limit) return;
    do {
      var end = math.min(at + 4096, limit);
      // Окно не разрезает суррогатную пару UTF-16.
      if (end < limit && end > at && block.text.codeUnitAt(end - 1) >= 0xD800 &&
          block.text.codeUnitAt(end - 1) <= 0xDBFF) {
        end--;
      }
      // Незавершённое слово может изменить перенос и предпоследней строки окна. По возможности
      // заканчиваем окно на пробеле; последняя строка всё равно остаётся для следующего измерения.
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
        // Строка выше пустой страницы (огромный кегль) — кладём одну, иначе разбивка не продвинется.
        h = m.lineHeights.first;
        k = 1;
      }
      final start = m.lineStarts.first;
      var end = k < m.lineStarts.length ? m.lineStarts[k] : m.end;
      // Разрыв внутри длинного слова меняет перенос последней строки. Проверяем ровно тот кусок,
      // который будет нарисован, а после разрыва заново измеряем оставшийся текст от нового начала.
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

  double _headingBefore(int c, int block, int start) {
    final ch = book.chapters[c];
    // Раздел только из заголовка — страница-заглавие: заголовок ниже обычного.
    return start > 0 ? 0 : ch.blockCount == 1 ? column.height * 0.28 : block == ch.firstBlock ? lh : lh * 1.5;
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

/// Неделимая часть обратной страницы: строка, небольшой заголовок или картинка с началом подписи.
class _BackUnit {
  _BackUnit(this.fragments, this.height, {this.before = 0, this.topBefore = 0, this.after = 0});
  final List<PageFragment> fragments;
  final double height, before, topBefore, after;
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
