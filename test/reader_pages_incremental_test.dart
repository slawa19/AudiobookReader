import 'dart:async';
import 'dart:convert';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pagination_test.dart' show colors;
import 'support/book_samples.dart';
import 'support/pagination.dart';

class MeasuredStyle extends PageStyle {
  MeasuredStyle({double size = 16, double height = 27})
    : super(fontSize: size, lineHeight: height, textScaler: TextScaler.noScaling);

  final measured = <(int, int)>[];

  @override
  List<InlineSpan> spans(Block block, int start, int end, {Color? noteColor}) {
    measured.add((start, end));
    return super.spans(block, start, end, noteColor: noteColor);
  }
}

Book longChapter() {
  final text = '${List.filled(30000, 'Текст тут ').join().trimRight()}.';
  return checked(utf8.encode('<FictionBook><body><section><p>$text</p></section></body></FictionBook>')).book;
}

Future<void> finished(ChapterPagination pagination) async {
  if (pagination.isComplete) return;
  final done = Completer<void>();
  void changed() {
    if (pagination.isComplete) done.complete();
  }

  pagination.addListener(changed);
  await done.future.timeout(const Duration(seconds: 20));
  pagination.removeListener(changed);
}

void main() {
  const column = Size(272, 516);

  testWidgets('SC-1: the first page of 300K characters is drawn before the chapter tail is measured', (tester) async {
    final book = longChapter();
    expect(book.totalChars, 300000);
    final style = MeasuredStyle();
    final pagination = ChapterPagination();
    addTearDown(pagination.dispose);
    pagination.start(book: book, style: style, column: column, block: 0, offset: 0);
    expect(pagination.pages, hasLength(1));
    expect(pagination.isCalculating, isTrue);
    expect(pagination.isComplete, isFalse);
    // This observes the measurements themselves, not just the batched delivery of the ready page array.
    expect(style.measured, isNotEmpty);
    expect(
      style.measured.every((r) => r.$2 <= 4096),
      isTrue,
      reason: 'measuring the whole chapter synchronously before the page is delivered is forbidden',
    );
    var renderedBeforeEnd = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (_) {
            renderedBeforeEnd = !pagination.isComplete && style.measured.every((r) => r.$2 <= 4096);
            return SizedBox.fromSize(
              size: column,
              child: BookPage(
                book: book,
                page: pagination.pages.first,
                style: style,
                colors: colors,
                imageFor: (_) => const AssetImage('unused'),
              ),
            );
          },
        ),
      ),
    );
    expect(find.byType(RichText), findsWidgets);
    expect(renderedBeforeEnd, isTrue);
    pagination.cancel();
  });

  test('an event passes between pages; the chapter matches the batched layout of the book', () async {
    final book = checked(epub(content: fixture('epub_structures.xhtml'))).book;
    final style = MeasuredStyle();
    final pagination = ChapterPagination();
    addTearDown(pagination.dispose);
    var heartbeat = false;
    var heartbeatBeforeSecondPage = false;
    Timer.run(() => heartbeat = true);
    pagination.addListener(() {
      if (pagination.pages.length == 2) heartbeatBeforeSecondPage = heartbeat;
    });
    pagination.start(book: book, style: style, column: column, block: 0, offset: 0);
    expect(heartbeat, isFalse);
    expect(pagination.pages, hasLength(1));
    await finished(pagination);
    expect(heartbeat, isTrue);
    expect(pagination.pages.length, greaterThan(1));
    expect(heartbeatBeforeSecondPage, isTrue);
    final sync = await paginate(book: book, style: style, column: column);
    addTearDown(sync.dispose);
    final chapter = sync.pages.where((p) => p.chapter == 0).toList();
    expect(pagination.pages.length, chapter.length);
    for (var i = 0; i < chapter.length; i++) {
      expect(
        pagination.pages[i].fragments.map((f) => (f.block, f.start, f.end, f.top, f.height)),
        chapter[i].fragments.map((f) => (f.block, f.start, f.end, f.top, f.height)),
      );
    }
  });

  test('changing font size and line height cancels old measurements and keeps the UTF-16 position', () async {
    final book = longChapter();
    final oldStyle = MeasuredStyle();
    final newStyle = MeasuredStyle(size: 28.6, height: 48.1);
    final pagination = ChapterPagination();
    addTearDown(pagination.dispose);
    const offset = 234567;
    pagination.start(book: book, style: oldStyle, column: column, block: 0, offset: offset);
    expect(pagination.pages.first.firstOffset, offset);
    expect(oldStyle.measured.every((r) => r.$1 >= offset), isTrue);
    final oldCount = oldStyle.measured.length;
    final oldFirstEnd = pagination.pages.first.lastEnd;
    pagination.start(book: book, style: newStyle, column: const Size(250, 500), block: 0, offset: offset);
    expect(pagination.pages.first.firstOffset, offset);
    final firstEnd = pagination.pages.first.lastEnd;
    expect(firstEnd, lessThan(oldFirstEnd), reason: 'the new font size really changes the pagination');
    await finished(pagination);
    expect(oldStyle.measured, hasLength(oldCount), reason: 'a cancelled calculation measures no old fragment at all');
    expect(pagination.pages.first.firstOffset, offset);
    expect(pagination.pages.last.lastEnd, book.blocks.single.text.length);
    expect(firstEnd, lessThan(book.blocks.single.text.length));
    var at = offset;
    for (final page in pagination.pages) {
      for (final fragment in page.fragments) {
        expect(fragment.start, at);
        at = fragment.end;
      }
    }
    expect(at, book.blocks.single.text.length);
    // Cancelling without a restart also stops notifications and measurements.
    pagination.start(book: book, style: newStyle, column: column, block: 0, offset: 0);
    var notifications = 0;
    pagination.addListener(() => notifications++);
    pagination.cancel();
    final measured = newStyle.measured.length;
    await Future<void>.delayed(Duration.zero);
    expect(newStyle.measured, hasLength(measured));
    expect(notifications, 0);
    expect(pagination.isCalculating, isFalse);
    expect(pagination.isComplete, isFalse);
  });

  test('the calculation starts in the selected chapter; a start inside a caption does not repeat the image', () async {
    final pagination = ChapterPagination();
    addTearDown(pagination.dispose);
    final style = MeasuredStyle();
    final fb2 = checked(utf8.encode(fixture('fb2_structure.xml'))).book;
    final chapter = fb2.chapters.last;
    pagination.start(book: fb2, style: style, column: column, block: chapter.firstBlock, offset: 0);
    await finished(pagination);
    expect(pagination.pages.first.firstBlock, chapter.firstBlock);
    expect(pagination.pages.every((p) => p.chapter == fb2.chapters.length - 1), isTrue);

    final book = checked(
      epub(content: fixture('epub_structures.xhtml').replaceFirst('Подпись ', List.filled(500, 'Подпись ').join())),
    ).book;
    final image = book.blocks.singleWhere((b) => b.kind == BlockKind.image);
    pagination.start(book: book, style: style, column: column, block: image.index, offset: 1000);
    expect((pagination.pages.first.firstBlock, pagination.pages.first.firstOffset), (image.index, 1000));
    await finished(pagination);
    expect(pagination.pages.expand((p) => p.fragments).any((f) => f.isImage), isFalse);
    // A similar start at the beginning of the block must show the image itself.
    pagination.start(book: book, style: style, column: column, block: image.index, offset: 0);
    expect(pagination.pages.first.fragments.first.isImage, isTrue);
    pagination.cancel();
  });
}
