import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:audiobook_reader/tts/segments.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';
import 'support/playback_harness.dart';

String paragraph(int n) => List.filled(16,
    'Путешественник $n вышел на дорогу и посмотрел на широкую долину. '
    'Ветер шевелил траву, а над рекой медленно поднимался утренний туман.').join(' ');

Book navigationBlocks() => Book(id: 'blocks', title: 'Блоки', author: '', language: 'ru',
    chapters: const [Chapter(title: '', level: 1, firstBlock: 0, blockCount: 5),
      Chapter(title: '', level: 1, firstBlock: 5, blockCount: 3)],
    blocks: [Block(index: 0, kind: BlockKind.paragraph, text: paragraph(0)),
      const Block(index: 1, kind: BlockKind.paragraph, text: '… — !!!'),
      const Block(index: 2, kind: BlockKind.image, text: 'Подпись', imageId: 'x'),
      const Block(index: 3, kind: BlockKind.separator, text: '***'),
      const Block(index: 4, kind: BlockKind.paragraph, text: '12345'),
      Block(index: 5, kind: BlockKind.paragraph, text: paragraph(5)),
      const Block(index: 6, kind: BlockKind.paragraph, text: '   '),
      const Block(index: 7, kind: BlockKind.paragraph, text: 'Окончание.')], notes: const {});

Future<void> playedBook(PlaybackHarness h) async {
  h.controller.readFrom(h.book, 0);
  for (var i = 0; i < 200 && h.controller.state != NarrationState.stopped; i++) {
    await until(() => h.player.playing || h.controller.state == NarrationState.stopped);
    h.clock.advance(const Duration(seconds: 10));
    await ioSettled();
  }
  expect(h.controller.stopReason, StopReason.endOfBook);
}

void main() {
  test('шаги по читаемым блокам пропускают знаки и картинки, пересекают главу и останавливаются у края', () async {
    final h = await PlaybackHarness.create(navigationBlocks());
    final c = h.controller;
    c.readFrom(h.book, 0);
    for (final target in [4, 5, 7]) {
      final revision = c.commandRevision;
      c.next();
      expect(c.unitStart, ReadingPosition(target, 0));
      expect(c.commandRevision, revision + 1);
    }
    final revision = c.commandRevision;
    c.next();
    expect(c.commandRevision, revision);
    expect(c.unitStart, const ReadingPosition(7, 0));
    for (final target in [5, 4, 0]) {
      c.previous();
      expect(c.unitStart, ReadingPosition(target, 0));
    }
    c.pause();
    c.previous();
    expect(c.unitStart, const ReadingPosition(0, 0));
    c.next();
    expect(c.state, NarrationState.paused);
    expect(c.unitStart, const ReadingPosition(4, 0));
  });

  test('назад: до трёх секунд — предыдущий блок, позже — текущий; второй шаг — предыдущий; пауза не считается началом', () async {
    final h = await PlaybackHarness.create(playbackBook([[paragraph(0), paragraph(1)]], kind: BlockKind.paragraph));
    for (final s in chapterSegments(h.book.blocks)) {
      await h.cache(s.text, seconds: (s.text.length * secondsPerChar).ceilToDouble());
    }
    final c = h.controller;
    Future<void> start() async {
      c.readFrom(h.book, 1);
      await until(() => h.player.playing);
    }
    await start();
    h.clock.advance(const Duration(milliseconds: 2800));
    c.previous();
    expect(c.unitStart, const ReadingPosition(0, 0));
    await start();
    h.clock.advance(const Duration(milliseconds: 3400));
    c.previous();
    expect(c.unitStart, const ReadingPosition(1, 0));
    c.previous();
    expect(c.unitStart, const ReadingPosition(0, 0));
    await start();
    h.clock.advance(const Duration(seconds: 40));
    expect(c.blockProgress, greaterThan(0));
    c.previous();
    expect(c.unitStart, const ReadingPosition(1, 0), reason: 'начало следующего отрезка не является началом абзаца');
    await start();
    h.clock.advance(const Duration(seconds: 5));
    c.pause();
    c.previous();
    expect(c.unitStart, const ReadingPosition(1, 0), reason: 'пауза посреди абзаца: назад — к его началу');
    c.previous();
    expect(c.unitStart, const ReadingPosition(0, 0));
    expect(c.state, NarrationState.paused);
    expect(h.engine.calls, isEmpty);
  });

  test('следующий блок определяется звучащим местом внутри группы, а не началом отрезка', () async {
    final h = await PlaybackHarness.create(playbackBook([['Первый абзац.', 'Второй абзац.', 'Третий абзац.']],
        kind: BlockKind.paragraph));
    final segment = chapterSegments(h.book.blocks).single;
    await h.cache(segment.text, seconds: 9);
    h.controller.readFrom(h.book, 0);
    await until(() => h.player.playing);
    h.clock.advance(const Duration(seconds: 4));
    expect(h.controller.block, 1);
    h.controller.next();
    expect(h.controller.unitStart, const ReadingPosition(2, 0));
  });

  test('прослушанные длинные абзацы: серия вперёд/назад не делает новых запросов', () async {
    final h = await PlaybackHarness.create(playbackBook([[paragraph(0), paragraph(1), paragraph(2)]],
        kind: BlockKind.paragraph), engineFactory: () => FakeTtsEngine(sampleRate: 100, secondsPerCharacter: 0.02));
    await playedBook(h);
    final bought = h.engine.calls.length;
    expect(bought, greaterThan(0));
    h.controller.readFrom(h.book, 0);
    await until(() => h.player.playing);
    for (final forward in [true, true, false, false, true, false]) {
      if (forward) { h.controller.next(); } else { h.controller.previous(); }
      await until(() => h.player.playing);
      await ioSettled();
      expect(h.engine.calls.length, bought);
    }
  });

  test('середина группы покупает только хвост; повтор использует его файл', () async {
    final h = await PlaybackHarness.create(playbackBook([['Первый абзац.', 'Второй абзац.', 'Третий абзац.']],
        kind: BlockKind.paragraph), engineFactory: () => FakeTtsEngine(sampleRate: 100, secondsPerCharacter: 0.1));
    await playedBook(h);
    final bought = h.engine.calls.length;
    h.controller.readFrom(h.book, 0);
    await until(() => h.player.playing);
    h.controller.next();
    await until(() => h.player.playing);
    await ioSettled();
    expect(h.engine.calls.length, bought + 1);
    expect(h.engine.calls.last.text, 'Второй абзац.\nТретий абзац.');
    h.controller.previous();
    await until(() => h.player.playing);
    h.controller.next();
    await until(() => h.player.playing);
    await ioSettled();
    expect(h.engine.calls.length, bought + 1);
  });

  testWidgets('прототип: те же читаемые блоки и правило трёх секунд для назад', (tester) async {
    final p = await pumpPrototype(tester, demoAcceleration: 1);
    final book = navigationBlocks();
    p.narration.readFrom(book, 0);
    await advance(tester, const Duration(seconds: 2));
    p.narration.next();
    expect(p.narration.unitStart, const ReadingPosition(4, 0));
    p.narration.next();
    expect(p.narration.unitStart, const ReadingPosition(5, 0));
    await advance(tester, const Duration(milliseconds: 3400));
    p.narration.previous();
    expect(p.narration.unitStart, const ReadingPosition(5, 0));
    p.narration.previous();
    expect(p.narration.unitStart, const ReadingPosition(4, 0));
    p.narration.pause();
    p.narration.previous();
    expect(p.narration.unitStart, const ReadingPosition(0, 0));
    await tester.pumpWidget(const SizedBox());
  });
}
