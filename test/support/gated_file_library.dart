import 'dart:async';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/file_library.dart';

/// Disk and parsing are real; only handing an already loaded book to the screen is delayed.
class GatedFileLibrary extends FileLibrary {
  GatedFileLibrary(super.root, {required super.settings, super.clock, super.timer});

  String? delayedId;
  final entered = Completer<void>();
  final release = Completer<void>();
  final delivered = Completer<void>();

  @override
  Future<Book> loadBook(String bookId) async {
    final book = await super.loadBook(bookId);
    if (bookId == delayedId) {
      entered.complete();
      await release.future;
      delivered.complete();
    }
    return book;
  }
}
