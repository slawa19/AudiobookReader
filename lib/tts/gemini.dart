import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'engine.dart';
import 'segments.dart';
import 'voices.dart';

const ttsRequestTimeout = Duration(seconds: 90);
const maximumRequestChars = 4000;
const defaultSampleRate = 24000;
const defaultBillingUrl = 'https://aistudio.google.com/billing';

/// The transport belongs to the calling code. There are no retries here: the queue manages them.
class GeminiTtsEngine implements TtsEngine {
  GeminiTtsEngine({required String apiKey, required http.Client transport, this.timeout = ttsRequestTimeout})
    // Named parameters are public, the fields with the key and the transport are private.
    // ignore: prefer_initializing_formals
    : _apiKey = apiKey,
      // ignore: prefer_initializing_formals
      _transport = transport;
  final String _apiKey;
  final http.Client _transport;
  final Duration timeout;

  String _clean(String message) {
    if (_apiKey.isEmpty) return message;
    return message.replaceAll(_apiKey, '[REDACTED]').replaceAll(Uri.encodeComponent(_apiKey), '[REDACTED]');
  }

  @override
  Future<TtsResult> synthesize(String text, VoiceProfile profile) async {
    text = text.replaceAll('\u0301', '');
    if (text.isEmpty || _apiKey.isEmpty) {
      throw const TtsError('Empty text or key', reason: TtsErrorReason.invalidRequest);
    }
    if (!RegExp(r'^[\x20-\x7e]+$').hasMatch(_apiKey)) {
      throw const TtsError('Invalid characters in the key', reason: TtsErrorReason.invalidKey);
    }
    final bytes = BytesBuilder(copy: false);
    TtsUsage? usage;
    int? rate;
    for (final part in splitSpeech(text, maximumRequestChars)) {
      try {
        final result = await _request(part, profile);
        // All parts of one take must have the same PCM format.
        if (rate != null && rate != result.sampleRate) {
          throw TtsError('Parts of the response have different sample rates', reason: TtsErrorReason.invalidResponse, usage: result.usage);
        }
        rate = result.sampleRate;
        bytes.add(result.pcm);
        usage = usage == null ? result.usage : usage + result.usage;
      } on TtsError catch (e) {
        final spent = usage == null
            ? e.usage
            : e.usage == null
            ? usage
            : usage + e.usage!;
        if (e is TemporaryTtsError) {
          throw TemporaryTtsError(_clean(e.message), reason: e.reason, statusCode: e.statusCode, usage: spent);
        }
        throw TtsError(
          _clean(e.message),
          reason: e.reason,
          statusCode: e.statusCode,
          usage: spent,
          model: e.model,
          billingUrl: e.billingUrl,
        );
      }
    }
    return TtsResult(pcm: bytes.takeBytes(), sampleRate: rate!, usage: usage!);
  }

  Future<TtsResult> _request(String text, VoiceProfile profile) async {
    final http.Response response;
    try {
      response = await _transport
          .post(
            Uri.https('generativelanguage.googleapis.com', '/v1beta/interactions'),
            headers: {'x-goog-api-key': _apiKey, 'content-type': 'application/json'},
            body: jsonEncode({
              'model': profile.model,
              'input': [
                {
                  'type': 'user_input',
                  'content': [
                    {
                      'type': 'text',
                      'text': text,
                      'annotations': [
                        {'type': 'speech_metadata', 'style': profile.style},
                      ],
                    },
                  ],
                },
              ],
              'response_format': {'type': 'audio'},
              'generation_config': {
                'speech_config': [
                  {'voice': profile.voiceId},
                ],
              },
            }),
          )
          .timeout(timeout);
    } on TimeoutException catch (e) {
      throw TemporaryTtsError('Request timed out (${e.runtimeType})', reason: TtsErrorReason.timeout);
    } on Exception catch (e) {
      // post covers sending and reading the body. Foreign text may contain the key, even in escaped form.
      throw TemporaryTtsError('Network error (${e.runtimeType})', reason: TtsErrorReason.network);
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      /* An HTTP error text may not be JSON. */
    }
    final rawUsage = json?['usage'];
    final usage = rawUsage is Map ? _usage(rawUsage) : null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json?['error'];
      final message = _clean(error is Map && error['message'] is String ? error['message'] as String : body);
      final status = response.statusCode;
      if (status == 408 || status == 429 || status >= 500 && status <= 599) {
        throw TemporaryTtsError(message, statusCode: status, usage: usage);
      }
      final keyDenied =
          status == 401 ||
          (status == 400 || status == 403) &&
              error is Map &&
              RegExp(r'API_KEY_|api[ _-]?key|invalid key', caseSensitive: false)
                  .hasMatch('${error['message']} ${error['status']}');
      final reason = status == 402
          ? TtsErrorReason.paymentRequired
          : status == 404
          ? TtsErrorReason.modelNotFound
          : keyDenied
          ? TtsErrorReason.invalidKey
          : TtsErrorReason.other;
      throw TtsError(
        message,
        reason: reason,
        statusCode: status,
        usage: usage,
        model: status == 404 ? _clean(profile.model) : null,
        billingUrl: status == 402 ? defaultBillingUrl : null,
      );
    }
    try {
      if (json == null) {
        throw const FormatException('The Gemini response is not a JSON object');
      }
      if (json.containsKey('status') && json['status'] != 'completed') {
        final error = json['error'];
        throw FormatException(
          error is Map && error['message'] is String
              ? error['message'] as String
              : 'Incomplete Gemini response: ${json['status']}',
        );
      }
      final pcm = BytesBuilder(copy: false);
      int? rate;
      for (final step in json['steps'] as List) {
        if (step is! Map || step['type'] != 'model_output') continue;
        for (final item in step['content'] as List) {
          if (item is! Map || item['type'] != 'audio') continue;
          final decoded = _decodeAudio(base64Decode(item['data'] as String), item['mime_type'] as String? ?? '');
          if (rate != null && rate != decoded.$2) {
            throw const FormatException('Audio chunks have different sample rates');
          }
          rate = decoded.$2;
          pcm.add(decoded.$1);
        }
      }
      final bytes = pcm.takeBytes();
      if (rate == null || bytes.isEmpty || bytes.length.isOdd) {
        throw const FormatException('The response has no mono PCM16 audio');
      }
      return TtsResult(
        pcm: bytes,
        sampleRate: rate,
        usage: rawUsage is Map
            ? _usage(rawUsage, seconds: bytes.length / (2 * rate))
            : TtsUsage(audioTokens: (bytes.length / (2 * rate) * audioTokensPerSecond).ceil()),
      );
    } on FormatException catch (e) {
      throw TtsError(_clean(e.message), reason: TtsErrorReason.invalidResponse, usage: usage);
    } on TypeError {
      throw TtsError('Unexpected structure of the Gemini response', reason: TtsErrorReason.invalidResponse, usage: usage);
    } on RangeError {
      throw TtsError('Corrupted Gemini audio', reason: TtsErrorReason.invalidResponse, usage: usage);
    }
  }
}

TtsUsage _usage(Map<dynamic, dynamic> raw, {double seconds = 0}) {
  int? audio;
  final modalities = raw['output_tokens_by_modality'];
  if (modalities is List) {
    for (final m in modalities) {
      if (m is Map && m['modality'] == 'audio' && m['tokens'] is num) {
        audio = (m['tokens'] as num).toInt();
        break;
      }
    }
  }
  final output = raw['total_output_tokens'];
  final input = raw['total_input_tokens'];
  return TtsUsage(
    audioTokens: audio ?? (output is num ? output.toInt() : null) ?? (seconds * audioTokensPerSecond).ceil(),
    inputTokens: input is num ? input.toInt() : null,
  );
}

(Uint8List, int) _decodeAudio(Uint8List bytes, String mime) {
  bool tag(int at, String value) =>
      at + value.length <= bytes.length && String.fromCharCodes(bytes.sublist(at, at + value.length)) == value;
  if (!tag(0, 'RIFF')) {
    if (mime.toLowerCase().contains('wav')) {
      throw const FormatException('Corrupted WAV');
    }
    final rate =
        int.tryParse(RegExp(r'rate\s*=\s*(\d+)', caseSensitive: false).firstMatch(mime)?.group(1) ?? '') ??
        defaultSampleRate;
    if (rate <= 0) throw const FormatException('Invalid PCM sample rate');
    return (bytes, rate);
  }
  if (!tag(8, 'WAVE')) throw const FormatException('Corrupted WAV');
  final data = ByteData.sublistView(bytes);
  int? rate;
  Uint8List? pcm;
  var at = 12;
  while (at + 8 <= bytes.length) {
    var size = data.getUint32(at + 4, Endian.little);
    final start = at + 8;
    // A streaming WAV does not know the data length in advance: both markers mean audio to the end of the file.
    if (tag(at, 'data') && (size == 0 || size == 0xffffffff)) size = bytes.length - start;
    if (start + size > bytes.length) {
      throw const FormatException('Truncated WAV');
    }
    if (tag(at, 'fmt ')) {
      if (size < 16 ||
          data.getUint16(start, Endian.little) != 1 ||
          data.getUint16(start + 2, Endian.little) != 1 ||
          data.getUint16(start + 14, Endian.little) != 16) {
        throw const FormatException('Mono PCM16 WAV is required');
      }
      rate = data.getUint32(start + 4, Endian.little);
    } else if (tag(at, 'data')) {
      pcm = Uint8List.sublistView(bytes, start, start + size);
    }
    at = start + size + (size % 2);
  }
  if (rate == null || rate <= 0 || pcm == null) {
    throw const FormatException('The WAV has no fmt/data chunk');
  }
  return (pcm, rate);
}
