import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pagination_test.dart' show styleFor, colors;
import 'support/book_samples.dart';

/// Эффективный стиль каждого кодового элемента, включая вложенные диапазоны.
List<TextStyle> styles(InlineSpan span, [TextStyle parent = const TextStyle()]) {
  final out = <TextStyle>[];
  if (span is TextSpan) {
    final own = parent.merge(span.style);
    out.addAll(List.filled(span.text?.length ?? 0, own));
    for (final child in span.children ?? <InlineSpan>[]) {
      out.addAll(styles(child, own));
    }
  }
  return out;
}

void main() {
  final style = styleFor(2, 1);
  for (final kind in ['h1', 'figcaption', 'p']) {
    test('диапазоны настоящего EPUB применяются в $kind и обрезаются на границах куска', () {
      final inline = fixture('epub_structures.xhtml');
      final paragraph = RegExp(r'<p>Текст.*?</p>').firstMatch(inline)!.group(0)!;
      final text = paragraph.replaceFirst('<p>', '').replaceFirst('</p>', '');
      final content = kind == 'figcaption'
          ? '<figure><img src="pic.png"/><figcaption>$text</figcaption></figure>'
          : '<$kind>$text</$kind>';
      final book = checked(
        epub(
          content:
              '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
              '$content<p>Конец.</p><aside epub:type="footnote" id="n"><p>Сноска.</p></aside></body></html>',
        ),
      ).book;
      final block = book.blocks.firstWhere((b) => b.text.startsWith('Текст'));
      expect(block.spans.map((s) => s.style).toSet(), SpanStyle.values.toSet());
      for (final (start, end) in [(0, block.text.length), (8, 19), (19, block.text.length)]) {
        final painted = styles(pieceSpan(style, block, start, end, noteColor: colors.accent));
        expect(painted.length, end - start);
        for (var i = start; i < end; i++) {
          final active = block.spans.where((s) => s.start <= i && i < s.end).map((s) => s.style).toSet();
          final actual = painted[i - start];
          if (active.contains(SpanStyle.bold)) expect(actual.fontWeight, FontWeight.w700);
          if (active.contains(SpanStyle.italic)) expect(actual.fontStyle, FontStyle.italic);
          if (active.contains(SpanStyle.sup) || active.contains(SpanStyle.noteRef)) {
            expect(actual.fontFeatures, contains(const FontFeature.superscripts()));
          }
          if (active.contains(SpanStyle.sub)) {
            expect(actual.fontFeatures, contains(const FontFeature.subscripts()));
          }
          if (active.contains(SpanStyle.noteRef)) expect(actual.color, colors.accent);
        }
        // Обычный текст рядом с диапазонами не получает надстрочного начертания и акцента.
        expect(painted.last.color, isNot(colors.accent));
        expect(painted.last.fontFeatures ?? [], isEmpty);
      }
    });
  }

  test('сноска, пересекающая границу страниц: обе видимые части доступны', () {
    final b = checked(utf8.encode(fixture('fb2_inline.xml'))).book;
    final source = b.blocks.single;
    final ref = source.spans.firstWhere((s) => s.style == SpanStyle.noteRef);
    for (final (start, end) in [(ref.start, ref.end - 1), (ref.start + 1, ref.end)]) {
      final painter = piecePainter(style, source, start, end, width: 272);
      final box = painter.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: end - start)).first;
      final page = BookPageLayout(
        chapter: 0,
        fragments: [PageFragment(block: 0, start: start, end: end, top: 0, height: painter.height)],
      );
      final hit = hitTestPage(book: b, page: page, style: style, columnWidth: 272, p: box.toRect().center);
      painter.dispose();
      expect(hit.noteId, ref.noteId);
      expect(
        hitTestPage(book: b, page: page, style: style, columnWidth: 272, p: const Offset(260, 200)).noteId,
        isNull,
      );
    }
  });
}
