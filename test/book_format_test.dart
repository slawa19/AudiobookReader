import 'dart:convert';

import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  test('FR-B2: EPUB прежде FB2.ZIP, содержимое важнее имени файла', () {
    final bytes = epub(extra: {'also.fb2': fixture('fb2_inline.xml')});
    expect(detectFormat(bytes), SourceFormat.epub);
    expect(checked(bytes).format.extension, 'epub');
    final fb = utf8.encode(fixture('fb2_inline.xml'));
    expect(detectFormat(fb), SourceFormat.fb2);
    final zipped = zip({
      'random.FB2': fb,
      'image.png': [1, 2, 3],
    });
    expect(detectFormat(zipped), SourceFormat.fb2Zip);
    final result = checked(zipped);
    expect(result.format.extension, 'fb2.zip');
    expect(
      result.book.blocks.map((b) => b.text),
      checked(fb).book.blocks.map((b) => b.text),
    );
    expect(result.book.id, hasLength(12));
    expect(result.book.id, isNot(checked(fb).book.id));
  });
  test('FR-B2: PDF, двоичный файл, посторонний ZIP и два FB2 отклоняются', () {
    for (final bytes in [
      utf8.encode('%PDF-1.7'),
      [0, 1, 2, 3],
      zip({'notes.xml': utf8.encode('<x/>')}),
      zip({
        'a.fb2': [1],
        'b.fb2': [2],
      }),
    ]) {
      expect(
        () => detectFormat(bytes),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.unsupported,
          ),
        ),
      );
      expect(
        () => parseBook(bytes),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.unsupported,
          ),
        ),
      );
    }
  });
  test('FR-B2: TXT определяется по первым 64КБ и сейчас не разбирается', () {
    for (final bytes in [
      utf8.encode('Текст.'),
      [9, 10, 13, 65],
      [...List.filled(65536, 65), 0],
    ]) {
      expect(detectFormat(bytes), SourceFormat.txt);
      expect(
        () => parseBook(bytes),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.unsupported,
          ),
        ),
      );
    }
    expect(
      () => detectFormat([...List.filled(65535, 65), 8]),
      throwsA(isA<BookParseException>()),
    );
    expect(
      detectFormat(utf8.encode('<other><FictionBook/></other>')),
      SourceFormat.txt,
    );
  });
  test(
    'FR-B2: зашифрованный spine отклоняется, шрифты и неиспользуемое — нет',
    () {
      expect(
        () => parseBook(epub(encryption: 'OPS/text.xhtml')),
        throwsA(
          isA<BookParseException>().having(
            (e) => e.reason,
            'reason',
            ParseFailure.protected,
          ),
        ),
      );
      for (final uri in ['OPS/font.otf', 'OPS/unused.xhtml']) {
        final b = checked(epub(encryption: uri)).book;
        expect(b.blocks.first.text, 'До.');
        expect(b.notes, isEmpty);
      }
    },
  );
  test('FR-B2: зашифрованная картинка и обложка не показываются', () {
    final content = fixture('epub_structures.xhtml');
    final visible = checked(epub(content: content));
    expect(visible.images, isNotEmpty);
    expect(visible.cover, isNotNull);
    final hidden = checked(epub(content: content, encryption: 'OPS/pic.png'));
    expect(hidden.images, isEmpty);
    expect(hidden.cover, isNull);
    expect(hidden.book.blocks.any((b) => b.imageId != null), isFalse);
  });
}
