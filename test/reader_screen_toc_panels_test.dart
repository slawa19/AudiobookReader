import 'dart:convert';

import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/screens/toc_screen.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/flows.dart';
import 'support/harness.dart' show reader;

Future<AppHarness> openContents(WidgetTester tester) async {
  final h = AppHarness(tester);
  await h.start(fakeTts: true);
  final file = await h.copy(utf8.encode('<FictionBook><body>'
      '<section><title><p>Первая глава</p></title><p>Начало книги.</p></section>'
      '<section><title><p>Вторая глава</p></title><p>Продолжение книги.</p></section>'
      '</body></FictionBook>'));
  h.files.events.add(file);
  await h.opened();
  await tapCenter(tester);
  expectPanelsPainted(tester, true);
  await tester.tap(find.byTooltip('Оглавление'));
  await tester.pumpAndSettle();
  expect(find.byType(TocScreen), findsOneWidget);
  return h;
}

void expectPanelsPainted(WidgetTester tester, bool visible) {
  // Проверяем сами рисуемые панели, а не panelsVisible/IgnorePointer: логическое
  // скрытие ещё не означает, что анимация уже увела их за экран.
  final panels = find.descendant(
    of: find.byType(ReaderScreen, skipOffstage: false),
    matching: find.byType(AnimatedOpacity, skipOffstage: false),
    skipOffstage: false,
  );
  expect(panels, findsNWidgets(2));
  final viewport = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  for (var i = 0; i < 2; i++) {
    final panel = panels.at(i);
    final render = tester.renderObject<RenderAnimatedOpacity>(panel);
    final bounds = tester.getRect(panel);
    expect(render.opacity.value > 0 && bounds.overlaps(viewport), visible,
        reason: '${i == 0 ? 'шапка' : 'нижняя панель'}: opacity=${render.opacity.value}, bounds=$bounds');
  }
}

Future<void> checkReturnFrames(WidgetTester tester, ModalRoute<dynamic> route, {required bool visible}) async {
  var returned = false;
  route.completed.then((_) => returned = true);
  final deadline = tester.binding.clock.now().add(const Duration(seconds: 5));
  // Нулевой шаг проверяет первый кадр после нажатия, до продвижения анимации.
  await tester.pump();
  expectPanelsPainted(tester, visible);
  while (!returned || tester.binding.hasScheduledFrame) {
    expect(tester.binding.clock.now().isBefore(deadline), isTrue, reason: 'возврат из оглавления не завершился');
    await tester.pump(const Duration(milliseconds: 16));
    expectPanelsPainted(tester, visible);
  }
  expect(find.byType(TocScreen), findsNothing);
}

void main() {
  testWidgets('выбор главы: панели не рисуются ни в одном кадре возврата', (tester) async {
    await openContents(tester);
    final route = ModalRoute.of(tester.element(find.byType(TocScreen)))!;
    await tester.tap(find.text('Вторая глава'));
    await checkReturnFrames(tester, route, visible: false);
    final st = reader(tester);
    expect(st.layout.pages[st.page].chapter, 1);
    expect(st.panelsVisible, isFalse);
  });

  for (final close in ['крестик', 'системная Назад']) {
    testWidgets('$close без выбора: панели видны в каждом кадре возврата', (tester) async {
      await openContents(tester);
      final route = ModalRoute.of(tester.element(find.byType(TocScreen)))!;
      if (close == 'крестик') {
        await tester.tap(find.byTooltip('Закрыть'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await checkReturnFrames(tester, route, visible: true);
      final st = reader(tester);
      expect(st.layout.pages[st.page].chapter, 0);
      expect(st.panelsVisible, isTrue);
    });
  }
}
