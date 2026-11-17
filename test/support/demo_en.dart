import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/fake_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:material_ui/material_ui.dart';

/// The English demo shelf for the README screenshots (test/readme_screenshots_test.dart): one book with a real
/// public-domain text (test/fixtures/screenshots_en/, see SOURCES.txt there) and five more with metadata only.
/// The covers are the text-free abstract ones from assets/demo/covers/ (drawn by scripts/prototype-texts.py).
const englishBookId = 'alice';

DemoContent englishDemoContent() {
  final json = jsonDecode(File('test/fixtures/screenshots_en/alice.json').readAsStringSync());
  final book = Book.fromJson(json as Map<String, Object?>);
  return DemoContent(
    entries: _entries,
    books: {englishBookId: book},
    positions: {englishBookId: const ReadingPosition(40, 0)},
    finished: {'moby'},
    // Chapters I and II are narrated in the default voice and model.
    voicedChapters: [(englishBookId, 0), (englishBookId, 1)],
    audioBytes: {englishBookId: 96 * 1024 * 1024, 'pride': 274 * 1024 * 1024, 'sawyer': 38 * 1024 * 1024},
  );
}

List<ShelfEntry> _entries(DateTime now) {
  // [hoursAgo] — when it was opened; `null` — never (the book is "new").
  ShelfEntry e(String id, String title, String author, int? hoursAgo,
          {String? cover, double? fraction, int kb = 600, int addedDaysAgo = 60}) =>
      ShelfEntry(
        id: id,
        title: title,
        author: author,
        addedAt: now.subtract(Duration(days: addedDaysAgo)),
        lastOpened: hoursAgo == null ? null : now.subtract(Duration(hours: hoursAgo)),
        cover: cover == null ? null : AssetImage('assets/demo/covers/$cover.png'),
        fraction: fraction,
        bookBytes: kb * 1024,
      );
  return [
    e(englishBookId, 'Alice’s Adventures in Wonderland', 'Lewis Carroll', 1, cover: 'kapitanskaya', kb: 150),
    e('pride', 'Pride and Prejudice', 'Jane Austen', 30, cover: 'dama', fraction: 0.13, kb: 710),
    e('sawyer', 'The Adventures of Tom Sawyer', 'Mark Twain', null, cover: 'voyna', kb: 420, addedDaysAgo: 8),
    e('expectations', 'Great Expectations', 'Charles Dickens', 260, fraction: 0.58, kb: 1100),
    e('wuthering', 'Wuthering Heights', 'Emily Brontë', 400, cover: 'geroy', fraction: 0.03, kb: 640),
    e('moby', 'Moby-Dick', 'Herman Melville', 900, cover: 'dushi', fraction: 1, kb: 1300),
  ];
}
