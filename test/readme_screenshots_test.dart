// Screenshots for README.md → docs/screenshots/*.png: the English interface and an English book (public domain,
// test/fixtures/screenshots_en/). The prototype shows them on fake data, like the screenshots in docs/prototype/screens.
// To regenerate: bash scripts/test.sh test/readme_screenshots_test.dart --update-goldens
// Like the other goldens, they are compared on every normal run of scripts/test.sh.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/demo_en.dart';
import 'support/flows.dart';
import 'support/harness.dart';

Future<void> shot(WidgetTester tester, String name) => snapshot(tester, name, dir: 'screenshots');

Future<Prototype> pumpEnglish(WidgetTester tester) => pumpPrototype(tester, locale: 'en', content: englishDemoContent());

Future<void> openAlice(WidgetTester tester, Prototype p, {required ReadingPosition at}) async {
  p.library.savePosition(englishBookId, at);
  await openBook(tester, 'Alice’s Adventures in Wonderland');
}

void main() {
  testWidgets('01 shelf', (tester) async {
    await pumpEnglish(tester);
    await shot(tester, '01-shelf');
  });

  testWidgets('02 reading, chapter start', (tester) async {
    final p = await pumpEnglish(tester);
    await openAlice(tester, p, at: const ReadingPosition(0, 0));
    await shot(tester, '02-reading');
  });

  testWidgets('03 reading with panels', (tester) async {
    final p = await pumpEnglish(tester);
    await openAlice(tester, p, at: const ReadingPosition(6, 0));
    await tapCenter(tester);
    await settle(tester);
    await shot(tester, '03-reading-panels');
  });

  testWidgets('04 listening and 08 listening, dark', (tester) async {
    final p = await pumpEnglish(tester);
    await openAlice(tester, p, at: const ReadingPosition(6, 0));
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(seconds: 3));
    await shot(tester, '04-listening');
    p.settings.theme = ThemeChoice.dark;
    await advance(tester, const Duration(milliseconds: 600));
    await shot(tester, '08-listening-dark');
  });

  testWidgets('05 table of contents', (tester) async {
    final p = await pumpEnglish(tester);
    await openAlice(tester, p, at: const ReadingPosition(70, 0));
    final Book book = currentBook(tester);
    // Chapters I and II are narrated (DemoContent.voicedChapters); chapter III, where the reader is, is downloading.
    p.downloads.demoShow(book, book.chapterOf(70), failed: false);
    await tapCenter(tester);
    await tester.tap(find.byTooltip('Contents'));
    await settle(tester, animations: false);
    await shot(tester, '05-contents');
  });

  testWidgets('06 voice selection', (tester) async {
    final p = await pumpEnglish(tester);
    await openAlice(tester, p, at: const ReadingPosition(6, 0));
    p.narration.demoShow('paused', book: currentBook(tester), fromBlock: 8);
    // The player panel is a new layer: taps are ignored for the first 350 ms.
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('voice-chip')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('probe-Callirrhoe')));
    await advance(tester, const Duration(milliseconds: 1500));
    await shot(tester, '06-voice');
  });

  testWidgets('07 settings', (tester) async {
    await pumpEnglish(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await shot(tester, '07-settings');
  });
}
