import 'dart:async';
import 'dart:io';

import 'package:audiobook_reader/audio/audio_encoder.dart';
import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/fake_player.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:audiobook_reader/tts/book_language.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

class GatedEncoder implements AudioEncoder {
  final entered = Completer<void>(), release = Completer<void>();
  bool failOnce = false;
  int calls = 0;
  @override
  String get extension => 'wav';
  @override
  String get formatId => const WavAudioEncoder().formatId;
  @override
  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  }) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    if (failOnce) {
      failOnce = false;
      throw const FileSystemException('Диск занят');
    }
    await const WavAudioEncoder().encode(
      pcmPath: pcmPath,
      outputPath: outputPath,
      sampleRate: sampleRate,
    );
  }
}

class GatedDurationPlayer extends FakePlayer {
  GatedDurationPlayer({required super.clock});
  final entered = Completer<void>(), release = Completer<Duration>();
  @override
  Future<Duration> duration(File file) {
    if (!entered.isCompleted) entered.complete();
    return release.future;
  }
}

void main() {
  test(
    '2 удалённая и повторно импортированная книга снова озвучивается',
    () async {
      final source = playbackBook([
        ['Книга.'],
      ]);
      final h = await PlaybackHarness.create(source);
      h.controller.readFrom(h.book, 0);
      await h.calls(1);
      h.controller.deleteBook(h.book.id);
      await until(() => h.library.shelf.isEmpty);
      final restored = await h.addBook(source);
      expect(restored.id, h.book.id);
      h.controller.readFrom(restored, 0);
      await h.release(0);
      expect(h.audioTokens, 15);
      expect(h.controller.state, NarrationState.preparing);
      await h.calls(2);
      await h.release(1);
      expect(h.controller.state, NarrationState.playing);
      expect(h.engine.calls.length, 2);
      expect(h.audioTokens, 30);
    },
  );

  for (final sample in [false, true]) {
    test(
      '2 поздняя ошибка чтения длительности ${sample ? 'пробы' : 'книги'} после очистки игнорируется',
      () async {
        late GatedDurationPlayer player;
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Книга.'],
          ]),
          playerFactory: sample
              ? null
              : (clock) => player = GatedDurationPlayer(clock: clock),
          sampleFactory: sample
              ? (clock) => player = GatedDurationPlayer(clock: clock)
              : null,
        );
        h.engine.enqueue(
          usage: const TtsUsage(audioTokens: 19, inputTokens: 3),
        );
        if (sample) {
          h.sampler.play(h.profile, bookLanguage: 'ru');
        } else {
          h.controller.readFrom(h.book, 0);
        }
        await h.calls(1);
        h.engine.calls.single.release();
        await player.entered.future;
        h.controller.clearAllNarration();
        player.release.completeError(const FileSystemException('Файл удалён'));
        await ioSettled();
        expect(h.controller.state, NarrationState.idle);
        expect(h.sampler.state, SampleState.idle);
        expect(h.audio.totalBytes, 0);
        expect(h.audioTokens, 19);
        expect(h.engine.calls.length, 1);
      },
    );
  }

  test('6 очистка пробы во время запроса не восстанавливает samples; новая проба делает новый запрос', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Книга.'],
      ]),
    );
    h.sampler.play(h.profile, bookLanguage: 'ru');
    await h.calls(1);
    h.controller.clearAllNarration();
    h.sampler.play(h.profile, bookLanguage: 'ru');
    await h.release(0);
    await h.calls(2);
    expect(Directory('${h.root.path}/samples').existsSync(), isFalse);
    expect(h.sampler.state, SampleState.loading);
    await h.release(1);
    expect(h.sampler.state, SampleState.playing);
    expect(Directory('${h.root.path}/samples').existsSync(), isTrue);
    expect(h.engine.calls.length, 2);
  });
  test('6 общий лимит: старый сеанс, новый и проба; кэш пробы, новая модель, язык и стиль', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Старый.', 'Второй.'],
        ['Третий.'],
      ]),
    );
    final c = h.controller;
    c.readFrom(h.book, 0);
    await h.calls(2);
    c.moveIfListening(h.book, 2);
    h.sampler.play(h.profile, bookLanguage: 'de');
    await ioSettled();
    expect(h.engine.calls.length, 2);
    expect(h.queue.inFlight, 2);
    expect(h.sampler.state, SampleState.loading);
    await h.release(0);
    await h.calls(3);
    expect(h.engine.calls[2].text, 'Третий.');
    expect(h.queue.inFlight, 2);
    await h.release(1);
    await h.calls(4);
    expect(h.engine.calls[3].text, samplePhraseFor('de'));
    expect(h.engine.calls[3].profile.style, readingStyleFor('de'));
    expect(h.queue.inFlight, 2);
    await h.release(3);
    expect(h.sampler.state, SampleState.playing);
    expect(h.audio.totalBytes, greaterThan(0));
    h.clock.advance(const Duration(milliseconds: 500));
    expect(h.sampler.progress, greaterThan(0));
    h.sampler.stop();
    h.sampler.play(h.profile, bookLanguage: 'de');
    await ioSettled();
    expect(h.sampler.state, SampleState.playing);
    expect(h.engine.calls.length, 4);
    h.sampler.stop();
    h.sampler.play(
      VoiceProfile(model: TtsModel.flashLite.id, voiceId: 'Aoede'),
      bookLanguage: 'de',
    );
    await h.calls(5);
    expect(h.engine.calls[4].profile.model, TtsModel.flashLite.id);
    expect(h.sampler.state, SampleState.loading);
    expect(h.queue.inFlight, 2);
  });

  test('6 проба: временная ошибка повторяется, stop отменяет повтор; постоянная показывает Google', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Книга.'],
      ]),
    );
    h.engine.enqueue(error: const TemporaryTtsError('Подождите'));
    h.sampler.play(h.profile, bookLanguage: 'ru');
    await h.calls(1);
    await h.release(0);
    expect(h.sampler.state, SampleState.loading);
    h.clock.advance(const Duration(seconds: 1));
    await h.calls(2);
    await h.release(1);
    expect(h.sampler.state, SampleState.playing);
    h.clock.advance(const Duration(minutes: 1));
    expect(h.sampler.state, SampleState.idle);
    h.engine.enqueue(error: const TemporaryTtsError('Подождите'));
    final other = VoiceProfile(model: TtsModel.flash.id, voiceId: 'Kore');
    h.sampler.play(other, bookLanguage: 'ru');
    await h.calls(3);
    await h.release(2);
    h.sampler.stop();
    h.clock.advance(const Duration(minutes: 2));
    await ioSettled();
    expect(h.engine.calls.length, 3);
    h.engine.enqueue(error: const TtsError('Google отказал'));
    h.sampler.play(other, bookLanguage: 'ru');
    await h.calls(4);
    await h.release(3);
    expect(h.sampler.state, SampleState.failed);
    expect(h.sampler.errorMessage, 'Google отказал');
  });

  test(
    '7 одновременные ответы и ошибка с usage учитываются каждый один раз',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первый.', 'Второй.', 'Третий.'],
        ]),
      );
      h.engine.enqueue(usage: const TtsUsage(audioTokens: 11, inputTokens: 3));
      h.engine.enqueue(usage: const TtsUsage(audioTokens: 13, inputTokens: 5));
      h.engine.enqueue(
        error: const TtsError(
          'Google',
          usage: TtsUsage(audioTokens: 17, inputTokens: 7),
        ),
      );
      h.controller.readFrom(h.book, 0);
      await h.calls(2);
      h.engine.calls[0].release();
      h.engine.calls[1].release();
      await until(() => h.audioTokens == 24);
      await h.calls(3);
      await h.release(2);
      expect(h.audioTokens, 41);
      final usage = h.library.usage[DateTime(2026, 11)]![TtsModel.flash.id]!;
      expect(usage.inputTokens, 15);
      h.clock.advance(const Duration(minutes: 1));
      await ioSettled();
      expect(h.audioTokens, 41);
      expect(h.engine.calls.length, 3);
    },
  );

  test('7 суммы месяцев по тарифу своего периода на 01.01.2027, включая пустые месяцы', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Книга.'],
      ]),
    );
    await h.library.recordUsage(
      modelId: TtsModel.flash.id,
      audioTokens: 1000000,
      inputTokens: 1000000,
      at: DateTime(2026, 12, 31),
    );
    await h.library.recordUsage(
      modelId: TtsModel.flashLite.id,
      audioTokens: 1000000,
      inputTokens: 1000000,
      at: DateTime(2026, 12, 31),
    );
    await h.library.recordUsage(
      modelId: TtsModel.flash.id,
      audioTokens: 1000000,
      inputTokens: 1000000,
      at: DateTime(2027, 1, 1),
    );
    await h.library.recordUsage(
      modelId: TtsModel.flashLite.id,
      audioTokens: 1000000,
      inputTokens: 1000000,
      at: DateTime(2027, 1, 1),
    );
    expect(spentByMonth(h.library, DateTime(2027, 1, 1)), [
      (month: DateTime(2027, 1), dollars: 32.0),
      (month: DateTime(2026, 12), dollars: 16.0),
    ]);
    expect(spentByMonth(h.library, DateTime(2026, 11)), [
      (month: DateTime(2026, 11), dollars: 0.0),
      (month: DateTime(2026, 10), dollars: 0.0),
    ]);
    expect(h.engine.calls, isEmpty);
  });

  test('4 повторы 1,2,4,8,16,30,30 секунд; пауза отменяет таймер', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Книга.'],
      ]),
    );
    for (var i = 0; i < 8; i++) {
      h.engine.enqueue(error: const TemporaryTtsError('Сеть'));
    }
    h.controller.readFrom(h.book, 0);
    await h.calls(1);
    final delays = [1, 2, 4, 8, 16, 30, 30];
    for (var i = 0; i < delays.length; i++) {
      await h.release(i);
      expect(h.controller.state, NarrationState.preparing);
      h.clock.advance(Duration(milliseconds: delays[i] * 1000 - 1));
      await ioSettled();
      expect(h.engine.calls.length, i + 1);
      h.clock.advance(const Duration(milliseconds: 1));
      await h.calls(i + 2);
      expect(h.engine.calls.last.text, 'Книга.');
    }
    await h.release(7);
    h.controller.pause();
    h.clock.advance(const Duration(minutes: 5));
    await ioSettled();
    expect(h.engine.calls.length, 8);
    expect(h.controller.state, NarrationState.paused);
  });

  test('4 запас непрерывный, 120 секунд делятся на скорость; дальний кэш не закрывает дыру', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Второй.', 'Третий.', 'Четвёртый.'],
      ]),
    );
    await h.cache('Первый.', seconds: 120);
    await h.cache('Третий.', seconds: 200);
    h.controller.readFrom(h.book, 0);
    await ioSettled();
    expect(h.engine.calls, isEmpty);
    expect(h.controller.state, NarrationState.playing);
    h.controller.setSpeed(2);
    expect(h.engine.calls, isEmpty);
    h.clock.advance(const Duration(milliseconds: 100));
    await h.calls(2);
    expect(h.engine.calls.map((c) => c.text), ['Второй.', 'Четвёртый.']);
    expect(h.player.items.length, 1);
    expect(h.controller.unitStart, const ReadingPosition(0, 0));
  });

  test(
    'Q3 запись повторяется тем же PCM, расход до записи, запрос один',
    () async {
      final encoder = GatedEncoder()..failOnce = true;
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Книга.'],
        ]),
        encoder: encoder,
      );
      h.controller.readFrom(h.book, 0);
      await h.calls(1);
      h.engine.calls.single.release();
      await encoder.entered.future;
      expect(h.audioTokens, 15);
      expect(h.audio.totalBytes, 0);
      encoder.release.complete();
      await ioSettled();
      expect(h.engine.calls.length, 1);
      expect(h.controller.state, NarrationState.preparing);
      h.clock.advance(const Duration(seconds: 1));
      await until(() => h.controller.state == NarrationState.playing);
      expect(encoder.calls, 2);
      expect(h.engine.calls.length, 1);
      expect(h.audioTokens, 15);
    },
  );

  for (final action in ['close', 'clear', 'delete']) {
    test(
      '2 поздняя запись на диск после $action и новой команды не трогает новый сеанс',
      () async {
        final encoder = GatedEncoder();
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Старый.'],
            ['Новый.'],
          ]),
          encoder: encoder,
        );
        h.controller.readFrom(h.book, 0);
        await h.calls(2);
        h.engine.calls[0].release();
        await encoder.entered.future;
        expect(h.audioTokens, 18);
        final oldKey = h.key('Старый.');
        if (action == 'close') h.controller.close();
        if (action == 'clear') h.controller.clearAllNarration();
        if (action == 'delete') {
          h.controller.deleteBook(h.book.id);
          await until(
            () => !Directory('${h.root.path}/books/${h.book.id}').existsSync(),
          );
        }
        final book = action == 'delete'
            ? await h.addBook(
                playbackBook([
                  ['Другая.'],
                ]),
              )
            : h.book;
        h.controller.readFrom(book, action == 'delete' ? 0 : 1);
        final at = h.controller.unitStart;
        encoder.release.complete();
        await ioSettled();
        expect(h.controller.unitStart, at);
        expect(h.controller.state, NarrationState.preparing);
        expect(h.player.items, isEmpty);
        expect(h.audioTokens, 18);
        expect(h.audio.has(oldKey, bookId: h.book.id), action == 'close');
        if (action != 'close') {
          expect(
            Directory('${h.root.path}/books/${h.book.id}/audio').existsSync(),
            isFalse,
          );
        }
      },
    );
  }
}
