import 'dart:typed_data';

import 'voices.dart';

abstract interface class TtsEngine {
  Future<TtsResult> synthesize(String text, VoiceProfile profile);
}

class TtsUsage {
  const TtsUsage({required this.audioTokens, this.inputTokens});
  final int audioTokens;
  final int? inputTokens;

  TtsUsage operator +(TtsUsage other) => TtsUsage(
    audioTokens: audioTokens + other.audioTokens,
    inputTokens: inputTokens == null && other.inputTokens == null
        ? null
        : (inputTokens ?? 0) + (other.inputTokens ?? 0),
  );
}

class TtsResult {
  const TtsResult({required this.pcm, required this.sampleRate, required this.usage});

  /// PCM 16-bit, little endian, mono, without a container.
  final Uint8List pcm;
  final int sampleRate;
  final TtsUsage usage;
  double get durationSeconds => pcm.length / (2 * sampleRate);
}

enum TtsErrorReason {
  paymentRequired,
  modelNotFound,
  invalidKey,
  other,
  invalidResponse,
  invalidRequest,
  temporaryHttp,
  timeout,
  network,
}

class TtsError implements Exception {
  const TtsError(
    this.message, {
    this.reason = TtsErrorReason.other,
    this.usage,
    this.statusCode,
    this.model,
    this.billingUrl,
  });
  final String message;
  final TtsErrorReason reason;
  final TtsUsage? usage;
  final int? statusCode;
  final String? model;
  final String? billingUrl;

  @override
  String toString() => message;
}

class TemporaryTtsError extends TtsError {
  const TemporaryTtsError(super.message, {super.reason = TtsErrorReason.temporaryHttp, super.usage, super.statusCode});
}
