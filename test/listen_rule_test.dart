// The start rule of “Listen” A–E (owner remark of 2026-11-14; spec 001, FR-P3; A§5).
// (а) and (д) are in listen_owner_scenario_test.dart.

import 'package:audiobook_reader/audio/audio_store.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/fake_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/chapter_download.dart';
import 'package:audiobook_reader/playback/fake_narration.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:audiobook_reader/tts/sentences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';
import 'support/sentence_oracle.dart';

/// A controller on a fake library, without a screen.
FakeNarrationController controller(FakeLibrary library) {
  final settings = AppSettings(voice: 'Aoede', modelId: 'gemini-3.8-flash-tts');
  final tariffs = Tariffs(today: () => DateTime(2026, 11, 14));
  return FakeNarrationController(
    library: library,
    audio: FakeAudioStore({}),
    downloads: FakeChapterDownloads(settings: settings, tariffs: tariffs),
    sampler: FakeVoiceSampler(),
    clock: () => DateTime(2026, 11, 14),
  );
}

Book bookOf(List<String> paragraphs) => Book(
      id: 'synthetic',
      title: 'Синтетическая',
      author: 'Тест',
      language: 'ru',
      chapters: [Chapter(title: '', level: 1, firstBlock: 0, blockCount: paragraphs.length)],
      blocks: [for (var i = 0; i < paragraphs.length; i++) Block(index: i, kind: BlockKind.paragraph, text: paragraphs[i])],
      notes: const {},
    );

void main() {
  group('sentence boundaries (A§6.1, rule 2)', () {
    test('an end mark and a space; closing quotes and brackets do not interfere', () {
      // “пять” after an ellipsis is lowercase: a continuation of the sentence (rule (ii)).
      const t = 'Раз. Два! «Три?» Четыре… пять (шесть.) Семь';
      expect(sentenceStarts(t), [0, 5, 10, 17, 39]);
      expect(sentenceStartAt(t, 12), 10);
      expect(sentenceStartAt(t, 0), 0);
    });

    test('no space after the mark — not a boundary (numbers, abbreviations written together)', () {
      expect(sentenceStarts('Версия 3.8 вышла.'), [0]);
      expect(sentenceStarts('Ответ:да,нет'), [0]);
    });

    // Rule (i): a period after a one-letter word is not the end of a sentence. Pairs "silent / fires".
    test('(i) silent: «г. Москве», initials «А. С. Пушкин», «т. е.»', () {
      const a = 'Он жил в г. Москве. Потом уехал.';
      expect(sentenceStarts(a), [0, a.indexOf('Потом')]);
      const b = 'А. С. Пушкин вошёл. Все встали.';
      expect(sentenceStarts(b), [0, b.indexOf('Все')]);
      const c = 'Дома, т. е. в Москве. Дальше.';
      expect(sentenceStarts(c), [0, c.indexOf('Дальше')]);
    });

    test('(i) fires: a period after a word of two or more letters', () {
      const t = 'Он жил в Москве. Потом уехал.';
      expect(sentenceStarts(t), [0, t.indexOf('Потом')]);
    });

    // Rule (ii): after an end mark a new sentence starts with a capital letter, a digit or an opening quote.
    test('(ii) silent: lowercase after an ellipsis; a remark by the author after “!” and a dash', () {
      expect(sentenceStarts('Он молчал... потом заговорил.'), [0]);
      const t = '— Стой! — крикнул он. — Подожди.';
      expect(sentenceStarts(t), [0, t.lastIndexOf('—')]);
    });

    test('(ii) fires: a capital letter, a digit, a quote, a dialogue line with a dash and a capital', () {
      const a = 'Он молчал... Потом заговорил.';
      expect(sentenceStarts(a), [0, a.indexOf('Потом')]);
      const b = 'Итог таков. 1920 год был трудным.';
      expect(sentenceStarts(b), [0, b.indexOf('1920')]);
      const c = 'Он сказал. «Нет», — ответила она.';
      expect(sentenceStarts(c), [0, c.indexOf('«')]);
      const d = 'Он ушёл. — Куда? — спросила она.';
      expect(sentenceStarts(d), [0, d.indexOf('—')]);
    });

    test('(ii) does not apply to scripts without letter case', () {
      const t = 'שלום. עולם.';
      expect(sentenceStarts(t), [0, t.indexOf('עולם')]);
    });

    test('accepted limitation: an abbreviation longer than one letter counts as an end', () {
      const t = 'См. рис. 3 ниже.';
      // “рис.” and “3” form a boundary by shape; the start may come slightly later, no text is lost.
      expect(sentenceStarts(t), [0, t.indexOf('3')]);
    });
  });

  group('the controller chooses the position (B)', () {
    late FakeLibrary library;
    setUp(() => library = FakeLibrary());

    test('(в) the page starts with the tail of a sentence — the tail is not read, the start is from the next '
        'sentence', () {
      final book = bookOf(['Первое предложение. Второе предложение. Третье.', 'Новый абзац.']);
      final c = controller(library);
      // The page starts inside the first sentence (offset 6) and runs to the end of the book.
      c.listen(book, const PageRange(ReadingPosition(0, 6), ReadingPosition(1, 12)));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(0, 20));
      expect(c.unitStart, const ReadingPosition(0, 20));
      c.close();
    });

    test('the page starts exactly at a sentence start — the start is from it (the rule does not skip)', () {
      final book = bookOf(['Первое предложение. Второе предложение.']);
      final c = controller(library);
      c.listen(book, const PageRange(ReadingPosition(0, 20), ReadingPosition(0, 39)));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(0, 20));
      c.close();
    });

    test('(г) the page is entirely inside one sentence — start from its beginning, although it is on the previous '
        'page', () {
      final long = 'Очень длинное предложение ${List.filled(200, 'и ещё слова').join(', ')} кончается здесь.';
      final book = bookOf(['Короткое.', long]);
      final c = controller(library);
      c.listen(book, const PageRange(ReadingPosition(1, 400), ReadingPosition(1, 900)));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(1, 0));
      c.close();
    });

    test('B1: the listening position is on the page — continue from it, not from the first sentence', () {
      final book = bookOf(['Первое. Второе. Третье.', 'Четвёртое.']);
      final c = controller(library);
      library.saveListeningPosition('synthetic', const ReadingPosition(1, 0));
      c.listen(book, const PageRange(ReadingPosition(0, 0), ReadingPosition(1, 10)));
      expect(c.block, 1);
      expect(c.unitStart, const ReadingPosition(1, 0));
      c.close();
    });

    test('B1 stays silent if the listening position is not on the page', () {
      final book = bookOf(['Первое. Второе.', 'Третье. Четвёртое.']);
      final c = controller(library);
      library.saveListeningPosition('synthetic', const ReadingPosition(1, 8));
      c.listen(book, const PageRange(ReadingPosition(0, 0), ReadingPosition(1, 8)));
      expect(c.unitStart, const ReadingPosition(0, 0));
      c.close();
    });

    test('A: “Close” does not forget the listening position; the reading position goes to the screen', () {
      final book = bookOf(['Первое. Второе.', 'Третье.']);
      final c = controller(library);
      c.readFrom(book, 1);
      c.pause();
      c.close(screenPosition: const ReadingPosition(0, 0));
      expect(c.state, NarrationState.idle);
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(1, 0));
      expect(library.positionOf('synthetic'), const ReadingPosition(0, 0));
    });

    test('D: “Read from here” starts at the paragraph start, even if the listening position is further inside it', () {
      final book = bookOf(['Первое. Второе. Третье.']);
      final c = controller(library);
      library.saveListeningPosition('synthetic', const ReadingPosition(0, 8));
      c.readFrom(book, 0);
      expect(c.unitStart, const ReadingPosition(0, 0));
      c.close();
    });
  });

  testWidgets('(б) the listening position is not on screen — start from the first sentence of the page, the page is '
      'the same',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openDama(tester, p, at: const ReadingPosition(23, 0));
    p.narration.readFrom(currentBook(tester), 23);
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 800));
    // Turned further pages myself.
    await tapRightThird(tester);
    await tester.pumpAndSettle();
    await tapRightThird(tester);
    await tester.pumpAndSettle();
    final st = reader(tester);
    final page = st.layout.pages[st.page];
    final book = st.widget.book;
    expect(page.contains(23, 0), isFalse, reason: 'the listening position is not on screen');
    // The expectation is an independent check against the rule text, not the same `sentenceStarts` (logic review of
    // 2026-11-14).
    final expected = firstSentenceStartOnPage(book, page);
    expect(expected, isNotNull);
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('listen')));
    // Right after the start (before the fake voice finishes the short paragraph).
    await advance(tester, const Duration(milliseconds: 600));
    expect(p.library.listeningPositionOf('dama'), expected);
    final now = st.layout.pages[st.page];
    expect(now.contains(expected!.block, expected.offset), isTrue, reason: 'the page did not change');
    expect(st.following, isTrue);
    expect(find.byKey(const Key('to-reading-place')), findsNothing);
  });
}
