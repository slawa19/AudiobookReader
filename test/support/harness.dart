import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Размеры экранов из задания (dp) и плотность снимков.
const phone412 = Size(412, 915);
const phone360 = Size(360, 800);
const phone393 = Size(393, 852);
const phone320 = Size(320, 640);
const snapshotDpr = 2.0;

/// Поднимает прототип на экране [size] dp с системным масштабом шрифта [textScale], строкой состояния 32 dp
/// и полоской жестов 20 dp (режим «от края до края»).
Future<Prototype> pumpPrototype(
  WidgetTester tester, {
  Size size = phone412,
  double textScale = 1,
  double demoAcceleration = 4,
}) async {
  // В тестах тени по умолчанию рисуются сплошной обводкой; для снимков нужны настоящие.
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
  tester.view.devicePixelRatio = snapshotDpr;
  tester.view.physicalSize = size * snapshotDpr;
  tester.view.padding = const FakeViewPadding(top: 32 * snapshotDpr, bottom: 20 * snapshotDpr);
  tester.view.viewPadding = const FakeViewPadding(top: 32 * snapshotDpr, bottom: 20 * snapshotDpr);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final p = (await tester.runAsync(() => Prototype.create(demoAcceleration: demoAcceleration)))!;
  addTearDown(() {
    p.narration.close();
    p.downloads.stop();
    p.sampler.stop();
  });
  await tester.pumpWidget(AudiobookApp(prototype: p, phoneChrome: true));
  await settle(tester);
  return p;
}

/// Дорисовывает картинки (обложки, иллюстрации): их декодирование идёт вне подставного времени теста.
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
