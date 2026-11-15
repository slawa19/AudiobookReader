import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_reader/audio/audio_encoder.dart';
import 'package:audiobook_reader/audio/file_audio_store.dart';
import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/clock.dart';
import 'package:audiobook_reader/playback/controller.dart';
import 'package:audiobook_reader/playback/fake_player.dart';
import 'package:audiobook_reader/playback/file_voice_sample.dart';
import 'package:audiobook_reader/playback/synthesis_queue.dart';
import 'package:audiobook_reader/tts/book_language.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:audiobook_reader/tts/fingerprint.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

Book playbackBook(
  List<List<String>> chapters, {
  BlockKind kind = BlockKind.heading,
  String language = 'ru',
}) {
  var index = 0;
  return Book(
    id: 'source',
    title: 'Синтетическая',
    author: 'Тест',
    language: language,
    chapters: [
      for (var c = 0; c < chapters.length; c++)
        Chapter(
          title: 'Глава $c',
          level: 1,
          firstBlock: chapters.take(c).fold(0, (s, ch) => s + ch.length),
          blockCount: chapters[c].length,
        ),
    ],
    blocks: [
      for (final ch in chapters)
        for (final text in ch) Block(index: index++, kind: kind, text: text),
    ],
    notes: const {},
  );
}

Future<void> until(
  bool Function() condition, [
  String reason = 'асинхронная операция',
]) async {
  final limit = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(limit)) fail('Не завершилась $reason');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Даёт завершиться файловому вводу-выводу; часы логики при этом не продвигаются.
Future<void> ioSettled() async {
  for (var i = 0; i < 35; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class PlaybackHarness {
  PlaybackHarness._(
    this.root,
    this.clock,
    this.settings,
    this.library,
    this.audio,
    this.engine,
    this.queue,
    this.player,
    this.samplePlayer,
    this.sampler,
    this.controller,
    this.book,
  );
  final Directory root;
  final ManualPlaybackClock clock;
  final AppSettings settings;
  final FileLibrary library;
  final FileAudioStore audio;
  final FakeTtsEngine engine;
  final SynthesisQueue queue;
  final FakePlayer player, samplePlayer;
  final FileVoiceSampler sampler;
  final FileNarrationController controller;
  final Book book;

  static Future<PlaybackHarness> create(
    Book source, {
    double speed = 1,
    AudioEncoder? encoder,
    FakePlayer Function(ManualPlaybackClock)? playerFactory,
    FakePlayer Function(ManualPlaybackClock)? sampleFactory,
  }) async {
    final root = await Directory.systemTemp.createTemp('playback-');
    final clock = ManualPlaybackClock();
    final settings = AppSettings(
      voice: 'Aoede',
      modelId: TtsModel.flash.id,
      apiKey: 'dummy-secret',
    );
    final library = FileLibrary(
      root,
      settings: settings,
      clock: clock.now,
      timer: clock.schedule,
      parser: (path) async {
        final bytes = await File(path).readAsBytes();
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        return ParsedBook(
          book: Book.fromJson({
            ...json,
            'id': sha256.convert(bytes).toString().substring(0, 12),
          }),
          format: SourceFormat.fb2,
          images: const {},
        );
      },
    );
    await library.ready;
    settings.speed = speed;
    final audio = FileAudioStore(
      root,
      encoder: encoder ?? const WavAudioEncoder(),
    );
    final engine = FakeTtsEngine(
      manual: true,
      sampleRate: 100,
      secondsPerCharacter: 0.1,
    );
    final queue = SynthesisQueue(
      engine: engine,
      audio: audio,
      library: library,
      settings: settings,
      clock: clock,
    );
    final player = playerFactory?.call(clock) ?? FakePlayer(clock: clock);
    final samplePlayer = sampleFactory?.call(clock) ?? FakePlayer(clock: clock);
    final sampler = FileVoiceSampler(queue: queue, player: samplePlayer);
    final controller = FileNarrationController(
      library: library,
      settings: settings,
      queue: queue,
      player: player,
      sampler: sampler,
      clock: clock,
    );
    final input = await File('${root.path}/input.json')
        .writeAsString(jsonEncode(source.toJson()));
    final entry = (await library.addFile(input.path, 'test.fb2'))!;
    final book = await library.loadBook(entry.id);
    final result = PlaybackHarness._(
      root,
      clock,
      settings,
      library,
      audio,
      engine,
      queue,
      player,
      samplePlayer,
      sampler,
      controller,
      book,
    );
    addTearDown(result.dispose);
    return result;
  }

  Future<Book> addBook(Book source) async {
    final input = await File('${root.path}/other.json')
        .writeAsString(jsonEncode(source.toJson()));
    final entry = (await library.addFile(input.path, 'other.fb2'))!;
    return library.loadBook(entry.id);
  }

  VoiceProfile get profile => VoiceProfile(
    model: settings.modelId,
    voiceId: library.bookVoice(book.id) ?? settings.voice,
    style: readingStyleFor(book.language),
  );
  String key(String text, [VoiceProfile? p]) =>
      fingerprint(text, p ?? profile, audio.formatId);
  Future<void> cache(
    String text, {
    double seconds = 10,
    VoiceProfile? profile,
  }) async {
    await audio.put(
      key(text, profile),
      Uint8List((seconds * 200).round()),
      100,
      bookId: book.id,
    );
  }

  Future<void> calls(int count) => until(
    () => engine.calls.length >= count,
    '$count запросов (сейчас ${engine.calls.length})',
  );
  Future<void> release(int index) async {
    engine.calls[index].release();
    await ioSettled();
  }

  int get audioTokens => library.usage.values.fold(
    0,
    (s, m) => s + m.values.fold(0, (s, u) => s + u.audioTokens),
  );

  Future<void> dispose() async {
    controller.dispose();
    sampler.dispose();
    queue.dispose();
    // Поздние ответы всё ещё вправе учесть расход до закрытия библиотеки.
    queue.invalidateAll();
    for (final call in engine.calls) {
      call.release();
    }
    await queue.drain();
    await library.flush();
    library.dispose();
    await player.dispose();
    await samplePlayer.dispose();
    audio.dispose();
    settings.dispose();
    await root.delete(recursive: true);
  }
}
