import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

const p = VoiceProfile(model: 'm', voiceId: 'v', style: 's');

void main() {
  test('FR-T5: тон PCM16, длина пропорциональна речи, расход; память вызовов', () async {
    final engine = FakeTtsEngine();
    final short = await engine.synthesize('Да.', p);
    final long = await engine.synthesize('Да.Да.', p);
    expect(long.pcm.length, short.pcm.length * 2);
    expect(short.durationSeconds, closeTo(3 * secondsPerChar, 1 / 24000));
    expect(short.pcm.any((b) => b != 0), isTrue);
    expect(short.usage.audioTokens, (short.durationSeconds * 25).ceil());
    expect(engine.calls.map((c) => c.text), ['Да.', 'Да.Да.']);
    expect(engine.calls.first.profile, p);
  });

  test('ручные ответы можно отпустить в обратном порядке, повторный release безвреден', () async {
    final engine = FakeTtsEngine(manual: true);
    var firstReady = false;
    var secondReady = false;
    final first = engine.synthesize('Раз.', p).then((r) {
      firstReady = true;
      return r;
    });
    final second = engine.synthesize('Два.', p).then((r) {
      secondReady = true;
      return r;
    });
    await Future<void>.delayed(Duration.zero);
    expect(firstReady, isFalse);
    expect(secondReady, isFalse);
    engine.calls[1].release();
    await second;
    expect(firstReady, isFalse);
    expect(secondReady, isTrue);
    engine.calls[0].release();
    engine.calls[0].release();
    await first;
    expect(firstReady, isTrue);
  });

  test('задержка, индивидуальная задержка и расход под управлением теста', () async {
    final engine = FakeTtsEngine(delay: const Duration(milliseconds: 10));
    engine.enqueue(usage: const TtsUsage(audioTokens: 12, inputTokens: 3), delay: const Duration(milliseconds: 20));
    var ready = false;
    final response = engine.synthesize('Да.', p).then((r) {
      ready = true;
      return r;
    });
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    expect((await response).usage.inputTokens, 3);
    expect(ready, isTrue);
  });

  test('все постоянные причины и временные ошибки, с usage и без; после них успешный ответ', () async {
    final engine = FakeTtsEngine(manual: true);
    for (final usage in [null, const TtsUsage(audioTokens: 34, inputTokens: 3)]) {
      for (final reason in TtsErrorReason.values) {
        final error =
            reason == TtsErrorReason.timeout ||
                reason == TtsErrorReason.network ||
                reason == TtsErrorReason.temporaryHttp
            ? TemporaryTtsError('Позже', reason: reason, usage: usage)
            : TtsError(
                'Стоп',
                reason: reason,
                usage: usage,
                model: 'm',
                billingUrl: 'https://aistudio.google.com/billing',
              );
        engine.enqueue(error: error);
        final future = engine.synthesize('Да.', p);
        final assertion = expectLater(future, throwsA(same(error)));
        engine.calls.last.release();
        await assertion;
        expect(error.usage, same(usage));
      }
    }
    final success = engine.synthesize('Да.', p);
    engine.calls.last.release();
    expect((await success).pcm, isNotEmpty);
  });
}
