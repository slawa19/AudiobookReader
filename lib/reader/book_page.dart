import 'package:flutter/widgets.dart';

import '../book/model.dart';
import 'page_style.dart';
import 'pagination.dart';

/// Цвета страницы. Берутся из темы приложения экраном и передаются сюда, чтобы `reader` не зависел от Material.
class PageColors {
  const PageColors({required this.ink, required this.ink2, required this.accent, required this.highlight});

  final Color ink;
  final Color ink2;
  final Color accent;

  /// Подсветка звучащего или выбранного абзаца.
  final Color highlight;
}

/// Одна страница книги: куски блоков на заранее рассчитанных местах. Ничего не решает сама.
class BookPage extends StatelessWidget {
  const BookPage({
    super.key,
    required this.book,
    required this.page,
    required this.style,
    required this.colors,
    required this.imageFor,
    this.highlightBlocks = const {},
  });

  final Book book;
  final BookPageLayout page;
  final PageStyle style;
  final PageColors colors;
  final ImageProvider Function(String imageId) imageFor;
  final Set<int> highlightBlocks;

  @override
  Widget build(BuildContext context) {
    // Стиль по умолчанию сброшен: иначе текст унаследует, например, межбуквенный интервал темы Material,
    // и строки перенесутся не там, где их посчитала разбивка.
    return DefaultTextStyle(
      style: const TextStyle(),
      child: _stack(),
    );
  }

  Widget _stack() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final f in page.fragments)
          if (highlightBlocks.contains(f.block))
            Positioned(
              key: ValueKey('hl-${f.block}-${f.start}'),
              top: f.top - 2,
              height: f.height + 4,
              left: -8,
              right: -8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: colors.highlight, borderRadius: BorderRadius.circular(8)),
              ),
            ),
        for (final f in page.fragments) _fragment(f),
      ],
    );
  }

  Widget _fragment(PageFragment f) {
    final block = book.blocks[f.block];
    switch (block.kind) {
      case BlockKind.heading:
        return Positioned(
          top: f.top,
          left: 0,
          right: 0,
          child: Text.rich(
            headingSpan(style, block, color: colors.ink, subColor: colors.ink2),
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
          ),
        );
      case BlockKind.image:
        final size = f.imageSize!;
        return Positioned(
          top: f.top,
          left: 0,
          right: 0,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(
                  image: imageFor(block.imageId ?? ''),
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.cover,
                  semanticLabel: block.text,
                ),
              ),
              if (block.text.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: style.lineHeight * 0.3),
                  child: Text(
                    block.text,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: style.caption.copyWith(color: colors.ink2),
                  ),
                ),
            ],
          ),
        );
      case BlockKind.separator:
        return Positioned(
          top: f.top,
          left: 0,
          right: 0,
          height: f.height,
          child: Center(
            child: Text('*  *  *',
                textScaler: TextScaler.noScaling, style: style.body.copyWith(color: colors.ink2, height: 1)),
          ),
        );
      case BlockKind.paragraph:
      case BlockKind.verse:
      case BlockKind.cite:
        return Positioned(
          top: f.top,
          left: fragmentInset(style, block),
          right: 0,
          child: Text.rich(
            fragmentSpan(style, block, f.start, f.end, color: colors.ink, noteColor: colors.accent),
            strutStyle: style.strutFor(block.kind),
            textScaler: TextScaler.noScaling,
            softWrap: true,
          ),
        );
    }
  }
}

/// Что под пальцем на странице. Координаты — в системе колонки текста.
class PageHit {
  const PageHit({this.block, this.noteId});

  final int? block;
  final String? noteId;
}

/// Ищет блок и знак сноски под точкой [p]. Знак сноски мал, поэтому ловится с запасом [noteSlop] —
/// так цель касания не меньше 48 dp.
PageHit hitTestPage({
  required Book book,
  required BookPageLayout page,
  required PageStyle style,
  required double columnWidth,
  required Offset p,
  double noteSlop = 20,
}) {
  int? block;
  for (final f in page.fragments) {
    if (p.dy >= f.top - 4 && p.dy <= f.top + f.height + 4) block = f.block;
  }
  for (final f in page.fragments) {
    final b = book.blocks[f.block];
    if (b.kind != BlockKind.paragraph && b.kind != BlockKind.verse && b.kind != BlockKind.cite) continue;
    if (p.dy < f.top - noteSlop || p.dy > f.top + f.height + noteSlop) continue;
    final refs = b.spans.where((s) => s.style == SpanStyle.noteRef && s.start >= f.start && s.end <= f.end);
    if (refs.isEmpty) continue;
    final tp = fragmentPainter(style, b, f.start, f.end, width: columnWidth);
    final shift = hasIndent(b, f.start) ? 1 : 0;
    final inset = fragmentInset(style, b);
    for (final r in refs) {
      final boxes = tp.getBoxesForSelection(
          TextSelection(baseOffset: r.start - f.start + shift, extentOffset: r.end - f.start + shift));
      for (final box in boxes) {
        final rect = box.toRect().shift(Offset(inset, f.top)).inflate(noteSlop);
        if (rect.contains(p)) {
          tp.dispose();
          return PageHit(block: f.block, noteId: r.noteId);
        }
      }
    }
    tp.dispose();
  }
  return PageHit(block: block);
}
