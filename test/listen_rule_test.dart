// Правило старта «Слушать» A–E (замечание владельца 2026-11-14; спека 001, FR-P3; А§5).
// (а) и (д) — в listen_owner_scenario_test.dart.

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

/// Контроллер на подставной библиотеке, без экрана.
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
  group('границы предложений (А§6.1, правило 2)', () {
    test('знак конца и пробел; закрывающие кавычки и скобки не мешают', () {
      const t = 'Раз. Два! «Три?» Четыре… пять (шесть.) Семь';
      expect(sentenceStarts(t), [0, 5, 10, 17, 25, 39]);
      expect(sentenceStartAt(t, 12), 10);
      expect(sentenceStartAt(t, 0), 0);
    });

    test('без пробела после знака — не граница (числа, сокращения слитно)', () {
      expect(sentenceStarts('Версия 3.8 вышла.'), [0]);
      expect(sentenceStarts('Ответ:да,нет'), [0]);
    });
  });

  group('контроллер выбирает место (B)', () {
    late FakeLibrary library;
    setUp(() => library = FakeLibrary());

    test('(в) страница начинается хвостом предложения — хвост не читается, старт со следующего предложения', () {
      final book = bookOf(['Первое предложение. Второе предложение. Третье.', 'Новый абзац.']);
      final c = controller(library);
      // Страница начинается внутри первого предложения (смещение 6) и идёт до конца книги.
      c.listen(book, const PageRange(ReadingPosition(0, 6), ReadingPosition(1, 12)));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(0, 20));
      expect(c.unitStart, const ReadingPosition(0, 20));
      c.close();
    });

    test('страница начинается ровно с начала предложения — с него (правило не перескакивает)', () {
      final book = bookOf(['Первое предложение. Второе предложение.']);
      final c = controller(library);
      c.listen(book, const PageRange(ReadingPosition(0, 20), ReadingPosition(0, 39)));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(0, 20));
      c.close();
    });

    test('(г) страница целиком внутри одного предложения — с его начала, хотя оно на прошлой странице', () {
      final long = 'Очень длинное предложение ${List.filled(200, 'и ещё слова').join(', ')} кончается здесь.';
      final book = bookOf(['Короткое.', long]);
      final c = controller(library);
      c.listen(book, const PageRange(ReadingPosition(1, 400), ReadingPosition(1, 900)));
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(1, 0));
      c.close();
    });

    test('B1: место прослушивания на странице — продолжает с него, а не с первого предложения', () {
      final book = bookOf(['Первое. Второе. Третье.', 'Четвёртое.']);
      final c = controller(library);
      library.saveListeningPosition('synthetic', const ReadingPosition(1, 0));
      c.listen(book, const PageRange(ReadingPosition(0, 0), ReadingPosition(1, 10)));
      expect(c.block, 1);
      expect(c.unitStart, const ReadingPosition(1, 0));
      c.close();
    });

    test('B1 молчит, если место прослушивания не на странице', () {
      final book = bookOf(['Первое. Второе.', 'Третье. Четвёртое.']);
      final c = controller(library);
      library.saveListeningPosition('synthetic', const ReadingPosition(1, 8));
      c.listen(book, const PageRange(ReadingPosition(0, 0), ReadingPosition(1, 8)));
      expect(c.unitStart, const ReadingPosition(0, 0));
      c.close();
    });

    test('A: «Закрыть» не забывает место прослушивания; позиция чтения уходит экрану', () {
      final book = bookOf(['Первое. Второе.', 'Третье.']);
      final c = controller(library);
      c.readFrom(book, 1);
      c.pause();
      c.close(screenPosition: const ReadingPosition(0, 0));
      expect(c.state, NarrationState.idle);
      expect(library.listeningPositionOf('synthetic'), const ReadingPosition(1, 0));
      expect(library.positionOf('synthetic'), const ReadingPosition(0, 0));
    });

    test('D: «Читать отсюда» — с начала абзаца, даже если место прослушивания в нём дальше', () {
      final book = bookOf(['Первое. Второе. Третье.']);
      final c = controller(library);
      library.saveListeningPosition('synthetic', const ReadingPosition(0, 8));
      c.readFrom(book, 0);
      expect(c.unitStart, const ReadingPosition(0, 0));
      c.close();
    });
  });

  testWidgets('(б) место прослушивания не на экране — старт с первого предложения страницы, страница та же',
      (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    await openDama(tester, p, at: const ReadingPosition(23, 0));
    p.narration.readFrom(currentBook(tester), 23);
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('play-pause')));
    await advance(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('player-close')));
    await advance(tester, const Duration(milliseconds: 800));
    // Перелистал дальше сам.
    await tapRightThird(tester);
    await tester.pumpAndSettle();
    await tapRightThird(tester);
    await tester.pumpAndSettle();
    final st = reader(tester);
    final page = st.layout.pages[st.page];
    final book = st.widget.book;
    expect(page.contains(23, 0), isFalse, reason: 'место прослушивания не на экране');
    ReadingPosition? expected;
    for (final f in page.fragments) {
      if (f.isImage || !book.blocks[f.block].isSpoken) continue;
      final s = sentenceStarts(book.blocks[f.block].text).where((s) => s >= f.start && s < f.end).firstOrNull;
      if (s != null) {
        expected = ReadingPosition(f.block, s);
        break;
      }
    }
    await tapCenter(tester);
    await advance(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('listen')));
    // Сразу после старта (до того, как подставной голос дочитает короткий абзац).
    await advance(tester, const Duration(milliseconds: 600));
    expect(p.library.listeningPositionOf('dama'), expected);
    final now = st.layout.pages[st.page];
    expect(now.contains(expected!.block, expected.offset), isTrue, reason: 'страница не сменилась');
    expect(st.following, isTrue);
    expect(find.byKey(const Key('to-reading-place')), findsNothing);
  });
}
