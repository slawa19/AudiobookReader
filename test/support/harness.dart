import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Screen sizes from the brief (dp) and the density of the screenshots.
const phone412 = Size(412, 915);
const phone360 = Size(360, 800);
const phone393 = Size(393, 852);
const phone320 = Size(320, 640);
const snapshotDpr = 2.0;

/// Starts the prototype on a [size] dp screen with the system font scale [textScale], a 32 dp status bar
/// and a 20 dp gesture bar (edge-to-edge mode).
Future<Prototype> pumpPrototype(
  WidgetTester tester, {
  Size size = phone412,
  double textScale = 1,
  double demoAcceleration = 4,
  String locale = 'ru',
}) async {
  // In tests shadows are drawn as a solid outline by default; screenshots need real ones.
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
  tester.view.devicePixelRatio = snapshotDpr;
  tester.view.physicalSize = size * snapshotDpr;
  tester.view.padding = const FakeViewPadding(top: 32 * snapshotDpr, bottom: 20 * snapshotDpr);
  tester.view.viewPadding = const FakeViewPadding(top: 32 * snapshotDpr, bottom: 20 * snapshotDpr);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  // Phone language. The Flutter test environment defaults to en_US; tests default to Russian.
  tester.platformDispatcher.localesTestValue = [Locale(locale)];
  tester.platformDispatcher.localeTestValue = Locale(locale);
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  // The app clock is pinned: "today" tariffs and the sleep timer do not depend on the day of the run.
  final p = (await tester.runAsync(
      () => Prototype.create(demoAcceleration: demoAcceleration, clock: () => DateTime(2026, 11, 14, 12, 30))))!;
  addTearDown(() {
    p.narration.close();
    p.downloads.stop();
    p.sampler.stop();
  });
  await tester.pumpWidget(AudiobookApp(prototype: p, phoneChrome: true));
  await settle(tester);
  return p;
}

/// Finishes drawing images (covers, illustrations): their decoding runs outside the fake time of the test.
Future<void> settle(WidgetTester tester, {bool animations = true}) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  if (animations) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> openBook(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
  await settle(tester);
}

ReaderScreenState reader(WidgetTester tester) => tester.state<ReaderScreenState>(find.byType(ReaderScreen));

Future<void> snapshot(WidgetTester tester, String name) async {
  await expectLater(find.byType(AudiobookApp), matchesGoldenFile('../docs/prototype/screens/$name.png'));
}
