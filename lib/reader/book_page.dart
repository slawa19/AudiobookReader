import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../book/model.dart';
import 'page_style.dart';
import 'pagination.dart';

/// Page colors. Taken from the app theme by the screen and passed here so that `reader` does not depend on Material.
class PageColors {
  const PageColors({
    required this.ink,
    required this.ink2,
    required this.accent,
    required this.highlight,
    required this.rule,
  });

  final Color ink;
  final Color ink2;
  final Color accent;

  /// Highlight of the voiced or selected paragraph.
  final Color highlight;

  /// The quote line.
  final Color rule;
}

/// One book page: block pieces at precomputed places. Decides nothing itself.
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
    // The default style is reset: otherwise the text would inherit, for example, the Material theme's letter spacing,
    // and lines would wrap not where the pagination counted them.
    return DefaultTextStyle(style: const TextStyle(), child: _stack());
  }

  Widget _stack() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final f in page.fragments)
          if (highlightBlocks.contains(f.block) && !f.isImage)
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
        for (final f in page.fragments)
          if (book.blocks[f.block].kind == BlockKind.cite)
            Positioned(
              key: ValueKey('rule-${f.block}-${f.start}'),
              top: f.top + 2,
              height: math.max(0, f.height - 4),
              left: style.citeRuleX,
              width: 2,
              child: DecoratedBox(decoration: BoxDecoration(color: colors.rule)),
            ),
        for (final f in page.fragments) _fragment(f),
      ],
    );
  }

  Widget _fragment(PageFragment f) {
    final block = book.blocks[f.block];
    if (f.isImage) {
      final size = f.imageSize!;
      return Positioned(
        top: f.top,
        left: 0,
        right: 0,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image(
              image: imageFor(block.imageId ?? ''),
              width: size.width,
              height: size.height,
              fit: BoxFit.contain,
              semanticLabel: block.text,
            ),
          ),
        ),
      );
    }
    if (block.kind == BlockKind.separator) {
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
    }
    return Positioned(
      top: f.top,
      left: fragmentInset(style, block),
      right: 0,
      // RichText, like TextPainter, uses the page's explicit style. Text.rich added the system boldText
      // only when painting, although the measurement had no such weight.
      child: RichText(
        text: pieceSpan(style, block, f.start, f.end, color: colors.ink, subColor: colors.ink2, noteColor: colors.accent),
        textAlign: pieceAlign(block),
        strutStyle: pieceStrut(style, block),
        textScaler: TextScaler.noScaling,
        softWrap: true,
      ),
    );
  }
}

/// What is under the finger on the page. Coordinates are in the text column's system.
class PageHit {
  const PageHit({this.block, this.noteId});

  final int? block;
  final String? noteId;
}

/// The smallest side of the touch area of a footnote mark (FR-R8: touch targets at least 48 dp).
const noteTarget = 48.0;

/// Finds the block and the footnote mark under point [p]. A footnote mark is small, so it is caught by an area of at
/// least [noteTarget] × [noteTarget] centered on the mark.
PageHit hitTestPage({
  required Book book,
  required BookPageLayout page,
  required PageStyle style,
  required double columnWidth,
  required Offset p,
}) {
  int? block;
  for (final f in page.fragments) {
    if (p.dy >= f.top - 4 && p.dy <= f.top + f.height + 4) block = f.block;
  }
  // The 48 × 48 areas of neighboring marks overlap: the mark closest to the touch point opens, not the first in
  // order (gesture review decision G).
  PageHit? best;
  var bestDistance = double.infinity;
  for (final f in page.fragments) {
    final b = book.blocks[f.block];
    if (f.isImage || b.kind == BlockKind.separator) continue;
    if (p.dy < f.top - noteTarget || p.dy > f.top + f.height + noteTarget) continue;
    final refs = b.spans.where((s) => s.style == SpanStyle.noteRef && s.start < f.end && s.end > f.start);
    if (refs.isEmpty) continue;
    final tp = piecePainter(style, b, f.start, f.end, width: columnWidth);
    final shift = hasIndent(b, f.start) ? 1 : 0;
    final inset = fragmentInset(style, b);
    for (final r in refs) {
      final boxes = tp.getBoxesForSelection(
          TextSelection(
            baseOffset: math.max(r.start, f.start) - f.start + shift,
            extentOffset: math.min(r.end, f.end) - f.start + shift,
          ));
      for (final box in boxes) {
        final glyph = box.toRect().shift(Offset(inset, f.top));
        final target = Rect.fromCenter(
          center: glyph.center,
          width: math.max(noteTarget, glyph.width + 16),
          height: math.max(noteTarget, glyph.height + 16),
        );
        final distance = (glyph.center - p).distance;
        if (target.contains(p) && distance < bestDistance) {
          bestDistance = distance;
          best = PageHit(block: f.block, noteId: r.noteId);
        }
      }
    }
    tp.dispose();
  }
  return best ?? PageHit(block: block);
}
