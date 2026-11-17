// User journeys of “Download chapter” (FR-D2, A§6.7) and the “narrated” mark.

import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'journey_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

Future<void> openToc(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byTooltip('Оглавление'));
  await tester.pumpAndSettle();
}

String estimateText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('download-estimate'))).data!;

void main() {
  testWidgets('chapter narrated → changed the book voice → table of contents: the chapter is no longer “narrated”, '
      'there is an estimate',
      (tester) async {
    // FR-D2: “narrated” follows the readiness rule A§6.1 for the CURRENT voice profile. Chapter audio in another voice
    // is no good for the new voice: while listening it will be synthesized and paid for again.
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0)); // chapter I is narrated in the demo data
    await openToc(tester);
    expect(find.byKey(const Key('voiced-mark')), findsOneWidget, reason: 'precondition: chapter I is narrated');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('voice-chip-idle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-Kore')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(p.library.bookVoice('kapitanskaya'), 'Kore');

    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voiced-mark')), findsNothing, reason: 'the chapter is not narrated for the voice '
        'Kore');
    expect(find.byKey(const Key('download-estimate')), findsOneWidget);
  });

  testWidgets('“Download chapter” → half is ready → “Stop”: the estimate is the remainder, not the whole '
      'chapter', (tester) async {
    // FR-D2: "after a manual stop, an offer to download again with the estimate of the remainder"; A§6.7: the estimate
    // is based on the missing fingerprints of the chapter.
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p); // chapter II, not narrated
    await openToc(tester);
    final full = estimateText(tester);
    final book = p.library.cachedBook('kapitanskaya')!;
    final chapter = book.chapterOf(39);
    final profile = p.downloads.profileFor('kapitanskaya');
    final total = p.downloads.estimate(book, chapter, profile);
    await tester.tap(find.byKey(const Key('download-start')));
    await advance(tester, const Duration(seconds: 20));
    final task = p.downloads.task!;
    expect(task.fraction, greaterThan(0.4), reason: 'precondition: more than a third is ready');
    final ready = task.readySeconds;
    await tester.tap(find.byKey(const Key('download-stop')));
    await tester.pumpAndSettle();
    expect(estimateText(tester), isNot(full), reason: 'the estimate after the stop is the remainder, not the previous '
        'price of the chapter');
    // Strengthened per the logic review: the remainder is exactly the unfinished part (not zero and not more than the
    // chapter), the price is proportional.
    final rest = p.downloads.estimate(book, chapter, profile);
    expect(rest.seconds, closeTo(total.seconds - ready, 0.5));
    expect(rest.dollars, closeTo(total.dollars * rest.seconds / total.seconds, 0.0001));
    expect(estimateText(tester), ru.notVoicedEstimate((rest.seconds / 60).ceil(), rest.dollars));
  });
}
