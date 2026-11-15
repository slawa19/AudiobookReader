import 'dart:async';
import 'dart:io';

import '../audio/audio_store.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../tts/engine.dart';
import '../tts/fingerprint.dart';
import '../tts/voices.dart';
import 'clock.dart';

const synthesisConcurrency = 2;
const reserveTarget = Duration(seconds: 120);

class SynthesisRequest {
  SynthesisRequest._(
    this.text,
    this.profile,
    this.fingerprint,
    this.bookId,
    this.generation,
    this.bookGeneration,
    this.session,
  );
  final String text, fingerprint;
  final VoiceProfile profile;
  final String? bookId;
  final int generation, bookGeneration, session;
}

/// Потребитель задаёт упорядоченный остаток работы, а не запускает сетевые вызовы.
/// Пауза запрещает новые запросы и повторы; уже начатое по-прежнему публикуется.
/// Такой же потребитель сможет задать весь остаток скачиваемой главы.
class SynthesisTask {
  SynthesisTask._(this.queue, this.session, this.changed, this.failed);
  final SynthesisQueue queue;
  final int session;
  final void Function() changed;
  final void Function(TtsError error) failed;
  List<SynthesisRequest> _requests = [];
  bool _active = true, _disposed = false, _settling = false;
  TtsError? error;
  void update(List<SynthesisRequest> requests, {required bool active}) {
    if (_disposed) return;
    _requests = requests;
    _active = active;
    _settling = false;
    queue._schedule();
  }

  void dispose() {
    _disposed = true;
    queue._tasks.remove(this);
    queue._schedule();
  }
}

class _Retry {
  _Retry(this.attempt, this.at, this.session);
  final int attempt;
  final DateTime at;
  final int session;
  Timer? timer;
}

class _Flight {
  _Flight(this.request);
  final SynthesisRequest request;
  final targets = <(String?, int, int), SynthesisRequest>{};
  Timer? writeTimer;
  Completer<void>? writeWake;
}

/// Единственный реестр оплачиваемых запросов. Обработчик ответа не знает плеера.
class SynthesisQueue {
  SynthesisQueue({
    required this.engine,
    required this.audio,
    required this.library,
    required this.settings,
    this.clock = const SystemPlaybackClock(),
  }) {
    library.addListener(_libraryChanged);
  }
  final TtsEngine engine;
  final AudioStore audio;
  final Library library;
  final AppSettings settings;
  final PlaybackClock clock;
  final _tasks = <SynthesisTask>[];
  final _flights = <String, _Flight>{};
  final _retries = <String, _Retry>{};
  final _bookGenerations = <String, int>{};
  final _deleted = <String, bool>{};
  final _operations = <Future<void>>{};
  int _generation = 0, _network = 0;
  bool _scheduled = false, _disposed = false;
  int get inFlight => _network;

  /// Идущая часть выбирает ту же схему готовности, что уже опубликованная часть.
  bool isPending(String key, {String? bookId}) =>
      _flights[key]?.targets.values.any(
        (r) => r.bookId == bookId && _valid(r),
      ) ??
      false;

  SynthesisRequest request(
    String text,
    VoiceProfile profile, {
    String? bookId,
    int session = 0,
  }) => SynthesisRequest._(
    text,
    profile,
    fingerprint(text, profile, audio.formatId),
    bookId,
    _generation,
    _bookGenerations[bookId] ?? 0,
    session,
  );

  SynthesisTask task({
    required int session,
    required void Function() changed,
    required void Function(TtsError) failed,
  }) {
    final task = SynthesisTask._(this, session, changed, failed);
    _tasks.add(task);
    return task;
  }

  bool _valid(SynthesisRequest r) =>
      r.generation == _generation &&
      r.bookGeneration == (_bookGenerations[r.bookId] ?? 0) &&
      !_deleted.containsKey(r.bookId);
  bool _has(SynthesisRequest r) =>
      _valid(r) && audio.has(r.fingerprint, bookId: r.bookId);
  bool _needs(String key) => _tasks.any(
    (t) =>
        !t._disposed &&
        t._active &&
        t.error == null &&
        t._requests.any((r) => r.fingerprint == key && _valid(r) && !_has(r)),
  );

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) _pump();
    });
  }

  void _pump() {
    for (final entry in _retries.entries.toList()) {
      if (!_needs(entry.key)) {
        entry.value.timer?.cancel();
        _retries.remove(entry.key);
      }
    }
    for (final task in _tasks.toList()) {
      if (task._disposed ||
          !task._active ||
          task._settling ||
          task.error != null) {
        continue;
      }
      for (final r in task._requests) {
        if (!_valid(r) || _has(r)) continue;
        final retry = _retries[r.fingerprint];
        // Пока ближайший ждёт повтора, свободное место не отдаётся дальним.
        if (retry != null && clock.now().isBefore(retry.at)) break;
        final flight = _flights[r.fingerprint];
        if (flight != null) {
          _attach(flight, r);
          if (flight.writeWake != null) break;
          continue;
        }
        if (_network >= synthesisConcurrency) break;
        final next = _Flight(r);
        _attach(next, r);
        _flights[r.fingerprint] = next;
        _network++;
        final operation = _run(next);
        _operations.add(operation);
        unawaited(operation.whenComplete(() => _operations.remove(operation)));
      }
    }
  }

  void _attach(_Flight flight, SynthesisRequest r) {
    // После очистки новая команда ждёт завершения старого вызова, но не получает его звук.
    if (flight.request.generation != r.generation) return;
    if (flight.targets.values.any(
      (old) => old.bookId == r.bookId && old.bookGeneration != r.bookGeneration,
    )) {
      return;
    }
    flight.targets[(r.bookId, r.generation, r.bookGeneration)] = r;
  }

  Duration _delay(int attempt) =>
      Duration(seconds: (1 << attempt.clamp(0, 5)).clamp(1, 30));
  Future<void> _later(Duration delay) {
    final done = Completer<void>();
    clock.schedule(delay, done.complete);
    return done.future;
  }

  Future<void> _writeLater(_Flight flight, Duration delay) async {
    final wake = Completer<void>();
    flight.writeWake = wake;
    flight.writeTimer = clock.schedule(delay, wake.complete);
    await wake.future;
    flight.writeWake = null;
    flight.writeTimer = null;
  }

  Future<void> _usage(TtsUsage? usage, String model, DateTime at) async {
    if (usage == null) return;
    var attempt = 0;
    while (true) {
      try {
        await library.recordUsage(
          modelId: model,
          audioTokens: usage.audioTokens,
          inputTokens: usage.inputTokens ?? 0,
          at: at,
        );
        return;
      } on FileSystemException {
        await _later(_delay(attempt++));
      }
    }
  }

  TtsError _safe(TtsError error, String model) {
    final key = settings.apiKey;
    final message = key == null || key.isEmpty
        ? error.message
        : error.message.replaceAll(key, '[REDACTED]');
    return TtsError(
      message,
      reason: error.reason,
      statusCode: error.statusCode,
      model: error.model ?? model,
      billingUrl: error.billingUrl,
    );
  }

  Future<void> _run(_Flight flight) async {
    final r = flight.request;
    TtsResult? result;
    TtsError? failure;
    try {
      result = await engine.synthesize(r.text, r.profile);
    } on TtsError catch (e) {
      failure = e;
    } catch (_) {
      // Не печатаем произвольный объект транспорта: в нём могут оказаться заголовки.
      failure = const TtsError('Не удалось получить ответ синтеза');
    }
    _network--;
    final at = clock.now();
    if (failure != null) {
      _flights.remove(r.fingerprint);
      if (failure is TemporaryTtsError) {
        if (_needs(r.fingerprint)) {
          final attempt = (_retries[r.fingerprint]?.attempt ?? -1) + 1;
          final retry = _Retry(
            attempt,
            clock.now().add(_delay(attempt)),
            r.session,
          );
          _retries[r.fingerprint] = retry;
          retry.timer = clock.schedule(_delay(attempt), _schedule);
        }
      } else {
        for (final task in _tasks.toList()) {
          if (!task._disposed &&
              task.error == null &&
              task._requests.any(
                (target) =>
                    target.fingerprint == r.fingerprint &&
                    _valid(target) &&
                    flight.targets.containsKey((
                      target.bookId,
                      target.generation,
                      target.bookGeneration,
                    )),
              )) {
            task.error = _safe(failure, r.profile.model);
            task.failed(task.error!);
          }
        }
      }
      // Останавливаем новую работу сразу, не после ожидания писателя расхода.
      await _usage(failure.usage, r.profile.model, at);
    } else {
      // Оба ответа проходят через единственного писателя Library, независимо от сеанса.
      await _usage(result!.usage, r.profile.model, at);
      _retries.remove(r.fingerprint)?.timer?.cancel();
      // Один PCM может понадобиться разным книгам. Цели добавляются и во время записи.
      final written = <(String?, int, int)>{};
      while (true) {
        final pending = flight.targets.entries
            .where((e) => !written.contains(e.key))
            .toList();
        if (pending.isEmpty) break;
        for (final target in pending) {
          written.add(target.key);
          var attempt = 0;
          while (_valid(target.value)) {
            try {
              await audio.put(
                r.fingerprint,
                result.pcm,
                result.sampleRate,
                bookId: target.value.bookId,
              );
              break;
            } on AudioWriteCancelled {
              break;
            } catch (_) {
              if (!_valid(target.value)) break;
              await _writeLater(flight, _delay(attempt++));
            }
          }
        }
      }
      _flights.remove(r.fingerprint);
    }
    for (final task in _tasks.toList()) {
      if (!task._disposed) {
        task._settling = true;
        task.changed();
      }
    }
    _schedule();
  }

  /// Инвалидация происходит до дискового удаления; поздний put вообще не начинается.
  void invalidateBook(String id, {bool deleted = false}) {
    _bookGenerations[id] = (_bookGenerations[id] ?? 0) + 1;
    if (deleted) _deleted[id] = false;
    _wakeInvalidWrites();
    _schedule();
  }

  void invalidateAll() {
    _generation++;
    _wakeInvalidWrites();
    _schedule();
  }

  void _wakeInvalidWrites() {
    for (final flight in _flights.values) {
      if (flight.targets.values.any(_valid)) continue;
      flight.writeTimer?.cancel();
      final wake = flight.writeWake;
      if (wake != null && !wake.isCompleted) wake.complete();
    }
  }

  void _libraryChanged() {
    if (_deleted.isEmpty) return;
    for (final id in _deleted.keys.toList()) {
      final present = library.shelf.any((book) => book.id == id);
      if (!present) {
        _deleted[id] = true;
      } else if (_deleted[id]!) {
        _deleted.remove(id);
      }
    }
    _schedule();
  }

  /// Барьер завершения ответов и дисковых публикаций; удаление его не ждёт.
  Future<void> drain() async {
    while (_operations.isNotEmpty) {
      await Future.wait(_operations.toList());
    }
  }

  void dispose() {
    _disposed = true;
    library.removeListener(_libraryChanged);
    for (final retry in _retries.values) {
      retry.timer?.cancel();
    }
    for (final task in _tasks.toList()) {
      task.dispose();
    }
  }
}
