import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'engine.dart';
import 'voices.dart';

/// Ручной затвор относится к вызову, а не к движку: поздний ответ легко отпустить после смены сеанса.
class FakeTtsCall {
  FakeTtsCall(this.text, this.profile);
  final String text;
  final VoiceProfile profile;
  final _release = Completer<void>();
  bool get released => _release.isCompleted;
  void release() {
    if (!released) _release.complete();
  }
}

class _Response {
  const _Response(this.error, this.usage, this.delay);
  final TtsError? error;
  final TtsUsage? usage;
  final Duration? delay;
}

class FakeTtsEngine implements TtsEngine {
  FakeTtsEngine({
    this.manual = false,
    this.delay = Duration.zero,
    this.sampleRate = 24000,
    this.secondsPerCharacter = secondsPerChar,
  }) {
    if (sampleRate <= 0 || secondsPerCharacter <= 0) {
      throw ArgumentError('Нужны положительные частота и длительность');
    }
  }
  final bool manual;
  final Duration delay;
  final int sampleRate;
  final double secondsPerCharacter;
  final calls = <FakeTtsCall>[];
  final _responses = Queue<_Response>();

  /// Ответы назначаются в порядке старта запросов. Ошибка может быть любого вида, с usage или без.
  /// Параметр usage задаёт успешный ответ; у ошибки расход передаётся в error.usage.
  void enqueue({TtsError? error, TtsUsage? usage, Duration? delay}) => _responses.add(_Response(error, usage, delay));

  @override
  Future<TtsResult> synthesize(String text, VoiceProfile profile) async {
    final call = FakeTtsCall(text, profile);
    calls.add(call);
    final response = _responses.isEmpty ? const _Response(null, null, null) : _responses.removeFirst();
    if (manual) await call._release.future;
    final wait = response.delay ?? delay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (response.error != null) throw response.error!;
    final count = (text.replaceAll('\u0301', '').length * secondsPerCharacter * sampleRate).round();
    final pcm = ByteData(count * 2);
    for (var i = 0; i < count; i++) {
      pcm.setInt16(i * 2, (3000 * math.sin(2 * math.pi * 440 * i / sampleRate)).round(), Endian.little);
    }
    return TtsResult(
      pcm: pcm.buffer.asUint8List(),
      sampleRate: sampleRate,
      usage: response.usage ?? TtsUsage(audioTokens: (count / sampleRate * audioTokensPerSecond).ceil()),
    );
  }
}
