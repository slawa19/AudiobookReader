import 'dart:convert';
import 'dart:isolate';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/book/speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  test('FR-B1: pure synchronous parsing moves to an isolate', () async {
    final bytes = utf8.encode(fixture('fb2_inline.xml'));
    final result = await Isolate.run(() => parseBook(bytes));
    invariants(result.book);
    expect(
      result.book.blocks.single.text,
      '😀 тихо громко x2 H2O[1][2][3][4].',
    );
  });
  test('FR-B1: JSON keeps the whole model, notes, images and UTF-16', () {
    final book = checked(utf8.encode(fixture('fb2_inline.xml'))).book;
    final json = jsonDecode(jsonEncode(book.toJson())) as Map<String, Object?>;
    final restored = Book.fromJson(json);
    expect(restored.toJson(), book.toJson());
    expect(json['totalChars'], book.blocks.single.text.length);
    expect(restored.blocks.single.spans.first.start, 8);
    invariants(restored);
    final illustrated = checked(utf8.encode(fixture('fb2_structure.xml'))).book;
    expect(
      Book.fromJson(
        jsonDecode(jsonEncode(illustrated.toJson())) as Map<String, Object?>,
      ).toJson(),
      illustrated.toJson(),
    );
  });

  test(
    'FR-B1: speechText removes only noteRef and stress marks, UTF-16 offsets',
    () {
      const b = Block(
        index: 0,
        kind: BlockKind.paragraph,
        text: '😀до́м[1]x',
        spans: [
          TextSpanRange(
            start: 6,
            end: 9,
            style: SpanStyle.noteRef,
            noteId: 'n',
          ),
          TextSpanRange(start: 2, end: 6, style: SpanStyle.bold),
        ],
      );
      final s = speechText(b);
      expect(s.text, '😀домx');
      expect(List.generate(s.text.length + 1, s.toBlock), [
        0,
        1,
        2,
        3,
        5,
        9,
        10,
      ]);
      expect(List.generate(b.text.length + 1, s.fromBlock), [
        0,
        1,
        2,
        3,
        4,
        4,
        5,
        5,
        5,
        5,
        6,
      ]);
      expect(s.toBlock(-1), 0);
      expect(s.toBlock(100), 10);
      const ordinary = Block(index: 0, kind: BlockKind.cite, text: 'дом[1]');
      expect(speechText(ordinary).text, 'дом[1]');
      expect(List.generate(7, speechText(ordinary).toBlock), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    },
  );

  test(
    'FR-B1: empty speech, overlapping references, kinds of spoken blocks',
    () {
      const empty = Block(
        index: 0,
        kind: BlockKind.paragraph,
        text: '́[12]',
        spans: [
          TextSpanRange(
            start: 1,
            end: 4,
            style: SpanStyle.noteRef,
            noteId: 'n',
          ),
          TextSpanRange(
            start: 2,
            end: 5,
            style: SpanStyle.noteRef,
            noteId: 'm',
          ),
        ],
      );
      expect(speechText(empty).text, '');
      expect(speechText(empty).toBlock(0), 5);
      for (final kind in BlockKind.values) {
        expect(
          Block(index: 0, kind: kind, text: 'Текст').isSpoken,
          !{BlockKind.image, BlockKind.separator}.contains(kind),
        );
      }
    },
  );
}
