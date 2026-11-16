import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_reader/playback/synthesis_queue.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/gemini.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/tts_responses.dart';
import 'support/playback_harness.dart';

const profile = VoiceProfile(model: 'gemini-3.8-flash-tts', voiceId: 'Aoede', style: 'Читай естественно.');
const key = 'fake-secret+key';

GeminiTtsEngine engine(
  FutureOr<http.Response> Function(http.Request) handler, {
  Duration timeout = ttsRequestTimeout,
}) => GeminiTtsEngine(apiKey: key, transport: MockClient((r) async => handler(r)), timeout: timeout);

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<TtsError> errorOf(Future<TtsResult> future) async {
  try {
    await future;
  } on TtsError catch (e) {
    return e;
  }
  throw StateError('Ожидалась ошибка');
}

void main() {
  test('транспорт: чужой текст исключения никогда не попадает в TtsError', () async {
    for (final failure in [
      FormatException('Invalid HTTP header field value: "$key\\n"'),
      http.ClientException('чужой текст ${Uri.encodeComponent(key)}'),
    ]) {
      final e = await errorOf(engine((_) => throw failure).synthesize('Да.', profile));
      expect(e, isA<TemporaryTtsError>());
      expect(e.reason, TtsErrorReason.network);
      expect(e.message, contains(failure.runtimeType.toString()));
      expect(e.message, isNot(contains('чужой текст')));
      expect(e.message, isNot(contains('Invalid HTTP header')));
      expect(e.toString(), isNot(contains(key)));
      expect(e.toString(), isNot(contains(Uri.encodeComponent(key))));
    }
    expect((await engine((_) => jsonResponse(audioResponse())).synthesize('Да.', profile)).pcm, isNotEmpty);
  });

  test('FR-3: ошибка программы проходит через клиент без превращения во временную', () async {
    final failure = StateError('чужой текст $key ${Uri.encodeComponent(key)}');
    await expectLater(engine((_) => throw failure).synthesize('Да.', profile), throwsA(same(failure)));
  });

  for (final failure in [
    FormatException('чужой текст $key ${Uri.encodeComponent(key)}'),
    http.ClientException('чужой текст $key ${Uri.encodeComponent(key)}'),
    StateError('чужой текст $key ${Uri.encodeComponent(key)}'),
  ]) {
    test('FR-3: очередь, ${failure.runtimeType}: повтор Exception, остановка Error, ключ скрыт', () async {
      final h = await PlaybackHarness.create(playbackBook([['Да.']]));
      h.settings.apiKey = key;
      var calls = 0;
      final queue = SynthesisQueue(
        engine: engine((_) {
          if (++calls == 1) throw failure;
          return jsonResponse(audioResponse());
        }),
        audio: h.audio,
        library: h.library,
        settings: h.settings,
        clock: h.clock,
      );
      addTearDown(queue.dispose);
      final errors = <TtsError>[];
      final request = queue.request('Да.', profile, bookId: h.book.id);
      late final SynthesisTask task;
      task = queue.task(changed: () => task.update([request], active: true), failed: errors.add);
      task.update([request], active: true);
      await until(() => calls == 1 && queue.inFlight == 0);
      h.clock.advance(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      await queue.drain();
      if (failure is Error) {
        expect(calls, 1);
        expect(task.error, same(errors.single));
        expect(errors.single, isNot(isA<TemporaryTtsError>()));
        expect(errors.single.message, 'StateError: synthesis request failed');
        expect(errors.single.toString(), isNot(contains(key)));
        expect(errors.single.toString(), isNot(contains(Uri.encodeComponent(key))));
      } else {
        expect(calls, 2);
        expect(errors, isEmpty);
        expect(task.error, isNull);
        expect(h.audio.has(request.fingerprint, bookId: h.book.id), isTrue);
      }
    });
  }

  test('ключ вне печатного ASCII отклоняется до транспорта; печатный ASCII отправляется', () async {
    for (final value in ['fake\nkey', 'fake\u200bkey', 'fakeékey', 'fake\u007fkey']) {
      var sent = false;
      final tts = GeminiTtsEngine(apiKey: value, transport: MockClient((_) async {
        sent = true;
        return jsonResponse(audioResponse());
      }));
      final e = await errorOf(tts.synthesize('Да.', profile));
      expect(e.reason, TtsErrorReason.invalidKey);
      expect(e, isNot(isA<TemporaryTtsError>()));
      expect(e.toString(), isNot(contains(value)));
      expect(sent, isFalse);
    }
    var sent = false;
    await GeminiTtsEngine(apiKey: 'fake-ASCII_09+~', transport: MockClient((r) async {
      sent = true;
      expect(r.headers['x-goog-api-key'], 'fake-ASCII_09+~');
      return jsonResponse(audioResponse());
    })).synthesize('Да.', profile);
    expect(sent, isTrue);
  });

  for (final readingBody in [false, true]) {
    for (final failure in [
      const SocketException('fake socket secret'),
      const HandshakeException('fake handshake secret'),
      const TlsException('fake tls secret'),
      const HttpException('fake http secret'),
    ]) {
      test('сеть: ${failure.runtimeType}, чтение тела=$readingBody — временная ошибка', () async {
        var calls = 0;
        final tts = GeminiTtsEngine(apiKey: key, transport: MockClient.streaming((_, _) async {
          calls++;
          if (!readingBody) throw failure;
          return http.StreamedResponse(Stream<List<int>>.error(failure), 200);
        }));
        final e = await errorOf(tts.synthesize('Да.', profile));
        expect(e, isA<TemporaryTtsError>());
        expect(e.reason, TtsErrorReason.network);
        expect(e.toString(), isNot(contains('secret')));
        expect(calls, 1);
      });
    }
  }

  test('оплата: постоянный адрес независимо от ссылок и пунктуации Google', () async {
    for (final message in ['payment_required', 'See https://aistudio.google.com/billing).',
      'Docs https://example.test/help, then https://aistudio.google.com/billing']) {
      final e = await errorOf(engine((_) => jsonResponse({'error': {'message': message}}, status: 402))
          .synthesize('Да.', profile));
      expect(e.billingUrl, 'https://aistudio.google.com/billing');
      expect(e.message, message);
    }
    final e = await errorOf(engine((_) => jsonResponse({'error': {'message': 'See https://example.test'}}, status: 403))
        .synthesize('Да.', profile));
    expect(e.billingUrl, isNull);
  });

  test('отказ по ключу: 401 всегда; 400/403 только message/status, ссылки и details молчат', () async {
    for (final status in [400, 401, 403, 418]) {
      for (final (error, denied) in <(Map<String, Object>, bool)>[
        ({'message': 'Denied'}, false),
        ({'message': 'API key invalid'}, true),
        ({'message': 'Denied', 'status': 'API_KEY_INVALID'}, true),
        ({'message': 'Denied', 'details': [{'url': 'https://example.test/api-key', 'reason': 'API_KEY_INVALID'}]}, false),
      ]) {
        final e = await errorOf(engine((_) => jsonResponse({
          'error': error, 'url': 'https://example.test/api-key',
        }, status: status)).synthesize('Да.', profile));
        expect(e.reason, status == 401 || (status == 400 || status == 403) && denied
            ? TtsErrorReason.invalidKey : TtsErrorReason.other);
      }
    }
  });

  for (final size in [0, 0xffffffff]) {
    test('WAV: потоковый data=$size читается до конца', () async {
      final bytes = wav();
      ByteData.sublistView(bytes).setUint32(50, size, Endian.little);
      final result = await engine((_) => jsonResponse(audioResponse(bytes: bytes, mime: 'audio/wav')))
          .synthesize('Да.', profile);
      expect(result.pcm, [123, 0, 56, 254]);
      expect(result.sampleRate, 16000);
    });
  }

  test('WAV: обычный размер ограничивает data, обрезанный чанк отклоняется', () async {
    final bounded = wav();
    ByteData.sublistView(bounded).setUint32(50, 2, Endian.little);
    expect((await engine((_) => jsonResponse(audioResponse(bytes: bounded, mime: 'audio/wav')))
        .synthesize('Да.', profile)).pcm, [123, 0]);
    final truncated = wav();
    ByteData.sublistView(truncated).setUint32(50, 6, Endian.little);
    expect((await errorOf(engine((_) => jsonResponse(audioResponse(bytes: truncated, mime: 'audio/wav')))
        .synthesize('Да.', profile))).reason, TtsErrorReason.invalidResponse);
  });

  test('FR-T1/T2: точное тело запроса, стиль только в metadata, ключ только в заголовке', () async {
    final tts = engine((r) {
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/interactions');
      expect(r.url.toString(), isNot(contains(key)));
      expect(r.headers['x-goog-api-key'], key);
      expect(r.headers['content-type'], contains('application/json'));
      expect(
        r.body,
        jsonEncode({
          'model': profile.model,
          'input': [
            {
              'type': 'user_input',
              'content': [
                {
                  'type': 'text',
                  'text': 'Замок.',
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
              {'voice': 'Aoede'},
            ],
          },
        }),
      );
      expect(r.body, isNot(contains(key)));
      return jsonResponse(audioResponse());
    });
    final result = await tts.synthesize('За\u0301мок.', profile);
    expect(result.pcm, [1, 0, 2, 0]);
    expect(result.sampleRate, 24000);
    expect(result.usage.audioTokens, 34);
    expect(result.usage.inputTokens, 3);
  });

  test('PCM rate=, запасная частота; WAV берёт частоту из fmt и снимает контейнер', () async {
    for (final (mime, bytes, rate, expected) in [
      ('audio/l16; rate=22050', [1, 0], 22050, [1, 0]),
      ('audio/l16', [2, 0], 24000, [2, 0]),
      ('audio/wav;rate=44100', wav(), 16000, [123, 0, 56, 254]),
    ]) {
      final result = await engine((_) => jsonResponse(audioResponse(bytes: bytes, mime: mime)))
          .synthesize('Да.', profile);
      expect(result.sampleRate, rate);
      expect(result.pcm, expected);
    }
  });

  test('usage: audio имеет приоритет, иначе total_output, иначе длительность; без сложения счётчиков', () async {
    for (final (usage, expected) in <(Map<String, Object>?, int)>[
      (
        {
          'output_tokens_by_modality': [
            {'modality': 'text', 'tokens': 999},
            {'modality': 'audio', 'tokens': 7},
          ],
          'total_output_tokens': 123,
        },
        7,
      ),
      (
        {
          'output_tokens_by_modality': [
            {'modality': 'audio', 'tokens': 0},
          ],
          'total_output_tokens': 123,
        },
        0,
      ),
      ({'total_output_tokens': 11}, 11),
      ({'total_input_tokens': 3}, 25),
      (null, 25),
    ]) {
      final result = await engine((_) => jsonResponse(audioResponse(bytes: List.filled(48000, 0), usage: usage)))
          .synthesize('Да.', profile);
      expect(result.usage.audioTokens, expected);
      expect(result.durationSeconds, 1);
    }
  });

  test('status отсутствует — допустим; status != completed — постоянная ошибка с usage', () async {
    await engine((_) => jsonResponse(audioResponse(status: null))).synthesize('Да.', profile);
    for (final status in ['in_progress', 'failed', 'cancelled']) {
      final e = await errorOf(engine((_) => jsonResponse(audioResponse(status: status))).synthesize('Да.', profile));
      expect(e, isNot(isA<TemporaryTtsError>()));
      expect(e.reason, TtsErrorReason.invalidResponse);
      expect(e.message, contains(status));
      expect(e.usage!.audioTokens, 34);
    }
    final failed = audioResponse(status: 'failed')..['error'] = {'message': 'Google refused $key'};
    final e = await errorOf(engine((_) => jsonResponse(failed)).synthesize('Да.', profile));
    expect(e.message, 'Google refused [REDACTED]');
    expect(e.usage!.audioTokens, 34);
  });

  test('HTTP: все временные классы, без повторов, usage в ошибке', () async {
    for (final status in [408, 429, 500, 502, 503, 599]) {
      var calls = 0;
      final e = await errorOf(
        engine((_) {
          calls++;
          return jsonResponse({
            'error': {'message': 'Google $status'},
            'usage': measuredUsage,
          }, status: status);
        }).synthesize('Да.', profile),
      );
      expect(e, isA<TemporaryTtsError>());
      expect(e.statusCode, status);
      expect(e.message, 'Google $status');
      expect(e.usage!.audioTokens, 34);
      expect(calls, 1);
    }
  });

  test('таймаут и ClientException — временные, ключ очищается и повторов нет', () async {
    for (final failure in [TimeoutException('timeout $key'), http.ClientException('network $key')]) {
      final e = await errorOf(engine((_) => throw failure).synthesize('Да.', profile));
      expect(e, isA<TemporaryTtsError>());
      expect(e.reason, failure is TimeoutException ? TtsErrorReason.timeout : TtsErrorReason.network);
      expect(e.toString(), isNot(contains(key)));
      expect(e.usage, isNull);
    }
    final gate = Completer<http.Response>();
    final e = await errorOf(
      engine((_) => gate.future, timeout: const Duration(milliseconds: 1)).synthesize('Да.', profile),
    );
    expect(e.reason, TtsErrorReason.timeout);
    gate.complete(jsonResponse(audioResponse()));
  });

  test('402: постоянная ссылка; 404 несёт модель запроса', () async {
    for (final link in ['', ' https://aistudio.google.com/custom-billing']) {
      final e = await errorOf(
        engine(
          (_) => jsonResponse({
            'error': {'message': 'payment_required$link'},
            'usage': measuredUsage,
          }, status: 402),
        ).synthesize('Да.', profile),
      );
      expect(e.reason, TtsErrorReason.paymentRequired);
      expect(e.billingUrl, defaultBillingUrl);
      expect(e.usage!.inputTokens, 3);
    }
    final e = await errorOf(
      engine(
        (_) => jsonResponse({
          'error': {'message': 'Model missing'},
        }, status: 404),
      ).synthesize('Да.', profile),
    );
    expect(e.reason, TtsErrorReason.modelNotFound);
    expect(e.model, profile.model);
  });

  test('400/403: только отказ по ключу распознан; прочее — текст Google как есть', () async {
    for (final status in [400, 403]) {
      for (final denied in [true, false]) {
        final message = denied ? 'API key not valid. $key' : 'Speech annotations are not supported';
        final e = await errorOf(
          engine(
            (_) => jsonResponse({
              'error': {'message': message},
            }, status: status),
          ).synthesize('Да.', profile),
        );
        expect(e.reason, denied ? TtsErrorReason.invalidKey : TtsErrorReason.other);
        expect(e.message, denied ? 'API key not valid. [REDACTED]' : message);
        expect(e, isNot(isA<TemporaryTtsError>()));
      }
    }
    final e = await errorOf(
      engine(
        (_) => jsonResponse({
          'error': {
            'message': 'Denied',
            'status': 'API_KEY_INVALID',
          },
        }, status: 403),
      ).synthesize('Да.', profile),
    );
    expect(e.reason, TtsErrorReason.invalidKey);
  });

  test('ключ очищен из JSON, не-JSON, status, сетевой ошибки и ссылки 402', () async {
    final responses = [
      http.Response('Google echoed $key ${Uri.encodeComponent(key)}', 401),
      jsonResponse({
        'error': {'message': 'Google $key'},
        'usage': measuredUsage,
      }, status: 418),
      jsonResponse(audioResponse(status: key)),
      jsonResponse({
        'error': {'message': 'See https://example.test/?secret=$key'},
      }, status: 402),
    ];
    for (final response in responses) {
      final e = await errorOf(engine((_) => response).synthesize('Да.', profile));
      expect(e.toString(), isNot(contains(key)));
      expect(e.toString(), isNot(contains(Uri.encodeComponent(key))));
      expect(e.billingUrl ?? '', isNot(contains(key)));
    }
  });

  test('повреждённые успешные ответы — постоянная ошибка с usage, без утечки тела', () async {
    for (final body in [
      {'usage': measuredUsage, 'steps': []},
      {'usage': measuredUsage, 'steps': 'wrong'},
      audioResponse(bytes: [1]),
      audioResponse(bytes: wav(channels: 2), mime: 'audio/wav'),
      audioResponse(bytes: wav(bits: 8), mime: 'audio/wav'),
      audioResponse(bytes: [82, 73, 70, 70], mime: 'audio/wav'),
      audioResponse(bytes: [1, 0], mime: 'audio/wav'),
      audioResponse(bytes: [1, 0], mime: 'audio/l16;rate=0'),
    ]) {
      final e = await errorOf(engine((_) => jsonResponse(body)).synthesize('Да.', profile));
      expect(e.reason, TtsErrorReason.invalidResponse);
      expect(e.usage!.audioTokens, 34);
    }
    final e = await errorOf(engine((_) => http.Response('not JSON $key', 200)).synthesize('Да.', profile));
    expect(e.reason, TtsErrorReason.invalidResponse);
    expect(e.toString(), isNot(contains(key)));
  });

  test('4000: короткий запрос один, длинный разбит без потерь; PCM и usage склеены', () async {
    for (final n in [4000, 10000]) {
      final sent = <String>[];
      final text = 'я' * n;
      final result = await engine((r) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        sent.add(((body['input'] as List).first['content'] as List).first['text'] as String);
        return jsonResponse(audioResponse());
      }).synthesize(text, profile);
      expect(sent.join(), text);
      expect(sent.every((s) => s.length <= maximumRequestChars), isTrue);
      expect(sent.length, n == 4000 ? 1 : 3);
      expect(result.pcm.length, sent.length * 4);
      expect(result.usage.audioTokens, sent.length * 34);
      expect(result.usage.inputTokens, sent.length * 3);
    }
  });

  test('ошибка следующей части сохраняет расход предыдущих и своего ответа', () async {
    for (final withUsage in [false, true]) {
      var calls = 0;
      final e = await errorOf(
        engine(
          (_) => ++calls == 1
              ? jsonResponse(audioResponse())
              : jsonResponse({
                  'error': {'message': 'Try later'},
                  if (withUsage) 'usage': measuredUsage,
                }, status: 429),
        ).synthesize('я' * 5000, profile),
      );
      expect(e, isA<TemporaryTtsError>());
      expect(e.usage!.audioTokens, withUsage ? 68 : 34);
      expect(calls, 2);
    }
  });

  test('пустые входы не отправляются', () async {
    final tts = engine((_) => throw StateError('HTTP не нужен'));
    expect((await errorOf(tts.synthesize('\u0301', profile))).reason, TtsErrorReason.invalidRequest);
  });
}
