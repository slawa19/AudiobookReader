// Области касания под пальцем: проверка попаданием (hit-test) по углам области 48 × 48, а не размером рисунка, и
// непересечение соседних областей (раздел F проверки жестов 2026-11-14; FR-R8).

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

/// Попадает ли касание в точке [p] в виджет [finder] (или в его потомка).
bool hits(WidgetTester tester, Finder finder, Offset p) {
  final target = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(p);
  for (final entry in result.path) {
    final t = entry.target;
    if (t is! RenderObject) continue;
    RenderObject? o = t;
    while (o != null) {
      if (o == target) return true;
      o = o.parent;
    }
  }
  return false;
}

/// Область 48 × 48 с центром в центре элемента ловится элементом: четыре точки в 2 dp от её углов (допуск на
/// скругления). Возвращает промахи.
List<String> misses48(WidgetTester tester, Finder finder, String name) {
  expect(finder, findsOneWidget, reason: name);
  final c = tester.getCenter(finder);
  return [
    for (final d in const [Offset(-22, -22), Offset(22, -22), Offset(-22, 22), Offset(22, 22)])
      if (!hits(tester, finder, c + d)) '$name: касание в ${d.dx.round()};${d.dy.round()} от центра не попадает',
  ];
}

void expectTarget48(WidgetTester tester, Finder finder, String name) =>
    expect(misses48(tester, finder, name), isEmpty);

void expectNoOverlap(WidgetTester tester, Map<String, Finder> items) {
  final rects = {for (final e in items.entries) e.key: tester.getRect(e.value)};
  final names = rects.keys.toList();
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final a = rects[names[i]]!;
      final b = rects[names[j]]!;
      final x = a.intersect(b);
      expect(x.width <= 0.5 || x.height <= 0.5, isTrue, reason: '${names[i]} $a и ${names[j]} $b перекрываются');
    }
  }
}

void main() {
  for (final (size, scale, label) in const [(phone320, 1.3, '320 × 640 ×1,3'), (phone412, 1.0, '412 × 915')]) {
    testWidgets('панель плеера ($label): чип голоса, «К месту чтения», крестик, скорость, назад, пауза, вперёд, таймер, '
        '«Стоп» строки скачивания', (tester) async {
      final p = await pumpPrototype(tester, size: size, textScale: scale, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await startListening(tester);
      // Листаю сам — появляется «К месту чтения»; идёт скачивание — в панели строка со «Стоп».
      await swipe(tester, at(tester, 0.85, 0.3), Offset(-size.width * 0.6, 0), ms: 110);
      await advance(tester, const Duration(milliseconds: 800));
      p.downloads.demoShow(currentBook(tester), 1, failed: false);
      await advance(tester, const Duration(milliseconds: 600));
      expect(p.narration.state, NarrationState.playing);
      final items = <String, Finder>{
        'чип голоса': find.byKey(const Key('voice-chip')),
        '«К месту чтения»': find.byKey(const Key('to-reading-place')),
        'крестик': find.byKey(const Key('player-close')),
        'скорость': find.byKey(const Key('speed')),
        'назад': find.byKey(const Key('previous')),
        'пауза': find.byKey(const Key('play-pause')),
        'вперёд': find.byKey(const Key('next')),
        'таймер сна': find.byKey(const Key('sleep')),
        '«Стоп»': find.widgetWithText(TextButton, 'Стоп'),
      };
      expect([for (final e in items.entries) ...misses48(tester, e.value, e.key)], isEmpty,
          reason: 'FR-R8: область касания каждого элемента управления не меньше 48 dp');
      expectNoOverlap(tester, items);
      // Панель целиком на экране.
      final panel = tester.getRect(find.byKey(const Key('player-panel')));
      expect(panel.top, greaterThan(0));
      expect(panel.bottom, lessThanOrEqualTo(size.height + 0.5));
    });

    testWidgets('панели чтения ($label): «Назад», оглавление, «Вид текста», чип голоса, «Слушать»; лист скорости и плитки '
        'тем', (tester) async {
      final p = await pumpPrototype(tester, size: size, textScale: scale, demoAcceleration: 1);
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      final bars = <String, Finder>{
        '«Назад»': find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
        'оглавление': find.widgetWithIcon(IconButton, Icons.toc_rounded),
        '«Вид текста»': find.widgetWithIcon(IconButton, Icons.text_fields_rounded),
        'чип голоса': find.byKey(const Key('voice-chip-idle')),
        '«Слушать»': find.byKey(const Key('listen')),
      };
      for (final e in bars.entries) {
        expectTarget48(tester, e.value, e.key);
      }
      expectNoOverlap(tester, bars);

      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      final appearance = <String, Finder>{
        'мельче': find.byKey(const Key('font-smaller')),
        'крупнее': find.byKey(const Key('font-larger')),
        for (final t in ['system', 'light', 'sepia', 'dark']) 'тема $t': find.byKey(Key('theme-$t')),
      };
      for (final e in appearance.entries) {
        expectTarget48(tester, e.value, e.key);
      }
      expectNoOverlap(tester, appearance);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('listen')));
      await advance(tester, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('speed')));
      await advance(tester, const Duration(milliseconds: 600));
      final speeds = <String, Finder>{
        for (final sp in ['0.75', '1.0', '1.25', '1.5', '1.75', '2.0']) 'скорость $sp': find.byKey(Key('speed-$sp')),
      };
      for (final e in speeds.entries) {
        expectTarget48(tester, e.value, e.key);
      }
      expectNoOverlap(tester, speeds);
    });
  }

  testWidgets('320 × 640 ×1,3: «Читать отсюда» целиком на экране, над панелью плеера, и нажимается пальцем', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await startListening(tester);
    final frags = currentPage(tester).fragments;
    final st = reader(tester);
    // Долгое нажатие на самый нижний кусок страницы — у самой панели плеера.
    final f = frags.last;
    await tester.longPressAt(Offset(160, st.pagePadding.top + f.top + f.height - 6));
    await advance(tester, const Duration(milliseconds: 400));
    final button = find.byKey(const Key('read-from-here'));
    expect(button, findsOneWidget);
    final r = tester.getRect(button);
    final panel = tester.getRect(find.byKey(const Key('player-panel')));
    expect(r.bottom, lessThanOrEqualTo(panel.top), reason: 'кнопка не под панелью плеера');
    expect(r.top, greaterThanOrEqualTo(0));
    expectTarget48(tester, button, '«Читать отсюда»');
    await quickTap(tester, r.center);
    await advance(tester, const Duration(milliseconds: 300));
    expect(p.narration.unitStart, ReadingPosition(f.block, 0));
  });
}
