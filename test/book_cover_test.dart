import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final title in ['', 'ёжик', '👩‍🚀 Полёт']) {
    testWidgets('cover placeholder: title «$title»', (tester) async {
      final entry = ShelfEntry(
        id: 'book',
        title: title,
        author: '',
        addedAt: DateTime(2026),
        bookBytes: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: BookCover(entry: entry, width: 80)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text(switch (title) {
          '' => '',
          'ёжик' => 'Ё',
          _ => '👩‍🚀',
        }),
        findsOneWidget,
      );
    });
  }
}
