import 'dart:async';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Пакетные проверки ждут тот же порционный расчёт, которым пользуется экран.
Future<ChapterPagination> paginate({
  required Book book,
  required PageStyle style,
  required Size column,
  Map<String, Size> imageSizes = const {},
  WidgetTester? tester,
}) async {
  Future<ChapterPagination> calculate() async {
    final pagination = ChapterPagination();
    final done = Completer<void>();
    void changed() {
      if (pagination.isComplete) done.complete();
    }
    pagination.addListener(changed);
    pagination.start(book: book, style: style, column: column, block: 0, offset: 0,
        imageSizes: imageSizes, throughBook: true);
    await done.future.timeout(const Duration(seconds: 30));
    pagination.removeListener(changed);
    return pagination;
  }
  return tester == null ? calculate() : (await tester.runAsync(calculate))!;
}
