// Замечание владельца 2026-11-14: пауза на абзаце в середине страницы → «Закрыть» → «Слушать» перелистывал назад
// и читал предыдущий длинный абзац с начала, а следование оказывалось выключенным. Правило A–E — спека 001, FR-P3.
// (а) падал на коде 1af7332 (звучал абзац 20 вместо 23). (д) на 1af7332 в тестовой среде НЕ падал: выключение
// следования у владельца (браузер) здесь не воспроизвелось ни на одном из 24 сочетаний размера окна, ускорения
// подставного голоса и шага кадров; тест стережёт результат, а не доказывает причину.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart' hide openDama;
import 'support/reference_pages.dart' show openDama;
import 'support/harness.dart';

/// «Ионыч», глава I: вверху страницы — хвост длинного абзаца 22, в середине начинается абзац 23
/// («— Ну, Котик, сегодня ты играла…»). Тёмная тема, как у владельца.
Future<void> openOwnerPage(WidgetTester tester, Prototype p) async {
  p.settings.theme = ThemeChoice.dark;
  await openDama(tester, p, at: const ReadingPosition(23, 0));
  final st = reader(tester);
  final page = st.layout.pages[st.page];
  expect(page.firstBlock, 22, reason: 'вверху страницы — хвост абзаца 22');
  expect(page.firstOffset, greaterThan(0));
  expect(page.fragments.any((f) => f.block == 23 && f.start == 0), isTrue, reason: 'абзац 23 начинается на странице');
}

void main() {
  testWidgets('(а) пауза на абзаце в середине страницы → «Закрыть» → «Слушать»: тот же абзац, та же страница, '
      'следование включено', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openOwnerPage(tester, p);
    // Слушает абзац 23 и ставит паузу.
    p.narration.readFrom(currentBook(tester), 23);
    await advance(tester, const Duration(seconds: 3));
    expect(p.narration.block, 23);
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 500));
    expect(p.narration.state, NarrationState.paused);
    final pageBefore = reader(tester).layout.pages[reader(tester).page];
    expect(pageBefore.fragments.any((f) => f.block == 23), isTrue);
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 800));
    // Снова «Слушать».
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(seconds: 3));
    final st = reader(tester);
    expect(p.narration.block, 23, reason: 'продолжает с того абзаца, где остановился');
    final page = st.layout.pages[st.page];
    final sounding = st.soundingPosition!;
    expect(page.contains(sounding.block, sounding.offset), isTrue,
        reason: 'на экране тот же звучащий абзац; начало страницы теперь задаётся местом голоса');
    expect(st.following, isTrue);
  });

  testWidgets('(д) сразу после «Слушать» кнопки «К месту чтения» нет — в той же последовательности, что у владельца',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openOwnerPage(tester, p);
    p.narration.readFrom(currentBook(tester), 23);
    await advance(tester, const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 800));
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('listen')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('to-reading-place')), findsNothing, reason: 'шаг $i после «Слушать»');
    }
    expect(reader(tester).following, isTrue);
  });
}
