import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';

void main() {
  for (final (system, selected, expected) in [
    ('ru', null, 'ru'),
    ('pl', null, 'pl'),
    ('de', null, 'de'),
    ('fr', null, 'en'),
    ('ru', 'en', 'en'),
    ('ru', 'pl', 'pl'),
  ]) {
    testWidgets(
      'язык новой книги: система=$system, настройка=$selected → $expected',
      (tester) async {
        final h = AppHarness(tester);
        await h.start();
        tester.platformDispatcher.localesTestValue = [Locale(system)];
        h.app.settings.language = selected;
        final file = await h.copy(utf8.encode('Текст книги.'), 'Книга.txt');
        final language = await tester.runAsync(() async {
          final entry = (await h.app.library.addFile(file.path, file.name))!;
          return (await h.app.library.loadBook(entry.id)).language;
        });
        expect(language, expected);
      },
    );
  }
}
