// Помощники для путей пользователя (test/journey_*.dart). Существующие test/support/* не меняются.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/screens/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// Настенные часы, которые тест двигает сам: таймер сна считает минуты по ним (А§6.6).
class TestClock {
  DateTime now = DateTime(2026, 11, 14, 12, 30);
  DateTime call() => now;
  void forward(Duration d) => now = now.add(d);
}

/// То же, что `pumpPrototype`, но с часами, которые идут по команде теста.
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

/// «Слушать» из нижней панели и время на «Готовлю голос…».
Future<void> listenFromPanel(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byKey(const Key('listen')));
  await advance(tester, const Duration(seconds: 2));
}

/// Открывает оглавление из шапки (панели должны быть показаны) и выбирает главу по названию.
Future<void> chooseChapter(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Оглавление'));
  await advance(tester, const Duration(milliseconds: 800));
  await tester.tap(find.text(title).last);
  await advance(tester, const Duration(milliseconds: 1200));
}

/// Последний абзац текущей страницы, который НАЧИНАЕТСЯ на ней и стоит не первым (у низа страницы).
int lowestStartingParagraph(WidgetTester tester) {
  final st = reader(tester);
  final book = st.widget.book;
  final frags = st.layout.pages[st.page].fragments;
  for (var i = frags.length - 1; i > 0; i--) {
    final f = frags[i];
    final b = book.blocks[f.block];
    if (b.isSpoken && f.start == 0 && b.text.trim().isNotEmpty) return f.block;
  }
  throw StateError('на странице нет абзаца, начатого ниже первого');
}

/// Место стоит на странице, которая сейчас на экране.
bool onScreen(WidgetTester tester, int block, int offset) {
  final st = reader(tester);
  return st.layout.pages[st.page].contains(block, offset);
}
