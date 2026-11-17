import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) =>
    File('test/fixtures/book/$name').readAsStringSync();
List<int> zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.add(ArchiveFile(e.key, e.value.length, e.value));
  }
  return ZipEncoder().encode(archive);
}

List<int> epub({
  String? content,
  String? nav,
  bool ncx = false,
  Map<String, String> extra = const {},
  Map<String, List<int>> raw = const {},
  String encryption = '',
  bool cover3 = true,
  List<String>? spine,
}) {
  // NCX is a table of contents, not an XHTML reading document. In EPUB3 a nav in the spine is allowed.
  spine ??= ncx ? const ['text'] : const ['text', 'nav'];
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': fixture('container.xml'),
    'OPS/book.opf': fixture('package.opf')
        .replaceAll('VERSION', ncx ? '2.0' : '3.0')
        .replaceAll(
          'COVER_META',
          cover3 ? '' : '<meta name="cover" content="cover"/>',
        )
        .replaceAll('NAV_HREF', ncx ? 'toc.ncx' : 'nav.xhtml')
        .replaceAll(
          'NAV_TYPE',
          ncx ? 'application/x-dtbncx+xml' : 'application/xhtml+xml',
        )
        .replaceAll('NAV_PROPERTIES', ncx ? '' : 'properties="nav"')
        .replaceAll(
          'COVER_PROPERTIES',
          cover3 ? 'properties="cover-image"' : '',
        )
        .replaceAll(
          'SPINE',
          spine.map((id) => '<itemref idref="$id"/>').join(),
        ),
    'OPS/text.xhtml': content ?? fixture('epub_boundaries.xhtml'),
    'OPS/nav/${ncx ? 'toc.ncx' : 'nav.xhtml'}':
        nav ?? fixture(ncx ? 'epub_toc.ncx' : 'epub_nav.xhtml'),
    'OPS/notes.xhtml': fixture('epub_notes.xhtml'),
    'OPS/second.xhtml': fixture('epub_second.xhtml'),
    if (encryption.isNotEmpty)
      'META-INF/encryption.xml': fixture('encryption.xml')
          .replaceAll('RESOURCE', encryption),
    ...extra,
  };
  return zip({
    for (final e in files.entries) e.key: utf8.encode(e.value),
    'OPS/pic.png': [1, 2, 3],
    'OPS/font.otf': [0, 1, 2],
    ...raw,
  });
}

ParsedBook checked(List<int> bytes) {
  final result = parseBook(bytes);
  invariants(result.book);
  return result;
}

void invariants(Book book) {
  expect(
    book.blocks.map((b) => b.index),
    List.generate(book.blocks.length, (i) => i),
  );
  var next = 0;
  for (final c in book.chapters) {
    expect(c.firstBlock, next);
    expect(c.blockCount, greaterThan(0));
    next = c.endBlock;
  }
  expect(next, book.blocks.length);
  expect(
    book.totalChars,
    book.blocks.fold<int>(0, (n, b) => n + b.text.length),
  );
  for (final blocks in [
    book.blocks,
    ...book.notes.values.map((n) => n.blocks),
  ]) {
    for (final b in blocks) {
      for (final s in b.spans) {
        expect(s.start, inInclusiveRange(0, b.text.length));
        expect(s.end, inInclusiveRange(s.start + 1, b.text.length));
        if (s.style == SpanStyle.noteRef) {
          expect(book.notes.containsKey(s.noteId), isTrue);
        }
      }
    }
  }
}

List<(String, int, int, int)> chapters(Book b) => [
  for (final c in b.chapters) (c.title, c.level, c.firstBlock, c.blockCount),
];
