// Helpers for user journeys (test/journey_*.dart). The existing test/support/* are unchanged.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/screens/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// A wall clock that the test advances itself: the sleep timer counts minutes by it (А§6.6).
class TestClock {
  DateTime now = DateTime(2026, 11, 14, 12, 30);
  DateTime call() => now;
  void forward(Duration d) => now = now.add(d);
}

/// The same as `pumpPrototype`, but with a clock that runs on the test command.
Future<Prototype> pumpWithClock(WidgetTester tester, TestClock clock, {double demoAcceleration = 1}) async {
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
  tester.view.devicePixelRatio = snapshotDpr;
  tester.view.physicalSize = phone412 * snapshotDpr;
  tester.view.padding = const FakeViewPadding(top: 32 * snapshotDpr, bottom: 20 * snapshotDpr);
  tester.view.viewPadding = const FakeViewPadding(top: 32 * snapshotDpr, bottom: 20 * snapshotDpr);
  tester.platformDispatcher.textScaleFactorTestValue = 1;
  tester.platformDispatcher.localesTestValue = [const Locale('ru')];
  tester.platformDispatcher.localeTestValue = const Locale('ru');
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final p = (await tester.runAsync(() => Prototype.create(demoAcceleration: demoAcceleration, clock: clock.call)))!;
  addTearDown(() {
    p.narration.close();
    p.downloads.stop();
    p.sampler.stop();
  });
  await tester.pumpWidget(AudiobookApp(prototype: p, phoneChrome: true));
  await settle(tester);
  return p;
}

AppLocalizations get ru => lookupAppLocalizations(const Locale('ru'));

/// “Listen” from the bottom panel and the time for “Preparing the voice…”.
Future<void> listenFromPanel(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byKey(const Key('listen')));
  await advance(tester, const Duration(seconds: 2));
}

/// Opens the table of contents from the header (the panels must be shown) and picks a chapter by title.
Future<void> chooseChapter(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Оглавление'));
  await advance(tester, const Duration(milliseconds: 800));
  await tester.tap(find.text(title).last);
  await advance(tester, const Duration(milliseconds: 1200));
}

/// The last paragraph of the current page that STARTS on it and is not the first one (at the bottom of the page).
int lowestStartingParagraph(WidgetTester tester) {
  final st = reader(tester);
  final book = st.widget.book;
  final frags = st.layout.pages[st.page].fragments;
  for (var i = frags.length - 1; i > 0; i--) {
    final f = frags[i];
    final b = book.blocks[f.block];
    if (b.isSpoken && f.start == 0 && b.text.trim().isNotEmpty) return f.block;
  }
  throw StateError('the page has no paragraph that starts below the first one');
}

/// The position is on the page that is currently on screen.
bool onScreen(WidgetTester tester, int block, int offset) {
  final st = reader(tester);
  return st.layout.pages[st.page].contains(block, offset);
}
