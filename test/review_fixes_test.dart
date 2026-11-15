// Тесты на находки ревью Codex 2026-11-14 (docs/reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md).
// Каждый тест падал на коде 53c78d3 — до исправления.

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart' hide openKapitanskaya;
import 'support/reference_pages.dart' show openKapitanskaya;
import 'support/harness.dart';
import 'support/sentence_oracle.dart';

void main() {
  testWidgets('№1: короткий ключ не роняет настройки', (tester) async {
    final p = await pumpPrototype(tester);
    p.settings.apiKey = 'abc';
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('abc'), findsOneWidget);
  });

  testWidgets('№2: «Читать отсюда» из паузы оставляет паузу на новом месте', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openKapitanskaya(tester, p);
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 300));
    expect(p.narration.state, NarrationState.paused);
    final block = wholeParagraphOnPage(tester);
    await tester.longPressAt(blockCenter(tester, block));
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('read-from-here')));
    await advance(tester, const Duration(seconds: 2));
    expect(p.narration.block, block);
    expect(p.narration.state, NarrationState.paused);
  });

  testWidgets('№3: после ошибки и ручного листания «Слушать» начинает с нового места', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    p.narration.demoShow('error402', book: currentBook(tester), fromBlock: 39);
    await advance(tester, const Duration(milliseconds: 600));
    await tapRightThird(tester);
    await advance(tester, const Duration(milliseconds: 600));
    await tapRightThird(tester);
    await advance(tester, const Duration(milliseconds: 600));
    final saved = p.library.positionOf('kapitanskaya')!;
    expect(saved.block, greaterThan(39), reason: 'экран после явного листания пишет позицию сам (А§5)');
    await tester.tap(find.byKey(const Key('error-listen')));
    await tester.pump();
    expect(p.narration.block, saved.block);
  });

  testWidgets('№5: «Очистить озвучку» сбрасывает готовность глав, пробы и останавливает скачивание', (tester) async {
    final p = await pumpPrototype(tester);
    expect(p.downloads.isVoiced('dama', 1, p.downloads.profileFor('dama')), isTrue);
    final book = await p.library.loadBook('dama');
    p.downloads.demoShow(book, 3, failed: false);
    const kore = VoiceProfile(voice: 'Kore', modelId: 'gemini-3.8-flash-tts');
    p.sampler.play(kore, bookLanguage: 'ru');
    await advance(tester, const Duration(seconds: 5));
    p.sampler.stop();
    await tester.tap(find.byTooltip('Настройки'));
    await settle(tester, animations: false);
    await tester.tap(find.byKey(const Key('clear')));
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('clear-confirm')));
    await advance(tester, const Duration(milliseconds: 600));
    expect(p.audio.totalBytes, 0);
    expect(p.downloads.isVoiced('dama', 1, p.downloads.profileFor('dama')), isFalse, reason: 'готовность глав сброшена');
    expect(p.downloads.task, isNull, reason: 'скачивание остановлено');
    p.sampler.play(kore, bookLanguage: 'ru');
    await tester.pump();
    expect(p.sampler.state.name, 'loading', reason: 'проба после очистки озвучивается заново');
  });

  // №11 заменён правилом A–E (замечание владельца 2026-11-14): хвост предложения с прошлой страницы не читается,
  // старт — с первого предложения, которое начинается на странице; страница назад не уезжает.
  testWidgets('№11 → FR-P3: «Слушать» начинает с первого предложения на странице, назад не листает', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p);
    final st = reader(tester);
    final page = st.layout.pages[st.page];
    expect(page.firstOffset, greaterThan(0), reason: 'страница начинается хвостом абзаца');
    final book = st.widget.book;
    // Ожидаемое место — первое начало предложения на странице, найденное независимой проверкой по тексту правил
    // А§6.1, а не той же `sentenceStarts` (ревью логики 2026-11-14).
    final expected = firstSentenceStartOnPage(book, page);
    expect(expected, isNotNull);
    expect(expected, isNot(ReadingPosition(page.firstBlock, page.firstOffset)),
        reason: 'тест не вакуумный: страница начинается не с начала предложения');
    await tapCenter(tester);
    await tester.tap(find.byKey(const Key('listen')));
    await advance(tester, const Duration(milliseconds: 500));
    expect(p.library.listeningPositionOf('kapitanskaya'), expected);
    final now = reader(tester).layout.pages[reader(tester).page];
    expect(now.contains(expected!.block, expected.offset), isTrue, reason: 'страница не уехала назад');
    expect(reader(tester).following, isTrue);
  });

  testWidgets('№12: при открытых панелях касание знака сноски открывает сноску', (tester) async {
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(0, 0));
    await tapCenter(tester);
    await tester.pumpAndSettle();
    expect(reader(tester).panelsVisible, isTrue);
    await tester.tapAt(noteRefCenter(tester, 'n1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-sheet')), findsOneWidget);
  });
}
