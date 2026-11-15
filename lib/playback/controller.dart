import 'dart:async';
import 'dart:math' as math;

import '../book/model.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../tts/book_language.dart';
import '../tts/engine.dart';
import '../tts/segments.dart';
import '../tts/sentences.dart';
import '../tts/voices.dart';
import 'chapter_download.dart';
import 'clock.dart';
import 'narration.dart';
import 'player.dart';
import 'synthesis_queue.dart';
import 'voice_sample.dart';

/// Первые три секунды блока считаются его началом при команде «назад».
const blockStartWindow = Duration(seconds: 3);

class _Segment {
  _Segment(this.speech, this.chapter);
  final SpeechSegment speech;
  final int chapter;
}

class _Unit {
  _Unit(this.speech, this.segment, this.request);
  final SpeechSegment speech;
  final int segment;
  final SynthesisRequest request;
  PlayerItem? item;
  Duration? duration;
}

/// Настоящая логика прослушивания; платформенный адаптер получает только файлы и команды.
class FileNarrationController extends NarrationController {
  FileNarrationController({
    required this.library,
    required this.settings,
    required this.queue,
    required this.player,
    required this.sampler,
    this.downloads,
    this.clock = const SystemPlaybackClock(),
  }) {
    _subscription = player.events.listen(_event);
    player.setSpeed(settings.speed);
  }
  final Library library;
  final AppSettings settings;
  final SynthesisQueue queue;
  final PlayerPort player;
  final VoiceSampler sampler;
  final ChapterDownloads? downloads;
  final PlaybackClock clock;
  late final StreamSubscription<PlayerEvent> _subscription;
  NarrationState _state = NarrationState.idle;
  StopReason? _reason;
  NarrationError? _error;
  Book? _book;
  VoiceProfile? _profile;
  ReadingPosition? _start, _position;
  SleepTimer? _sleep;
  Timer? _sleepAlarm;
  SynthesisTask? _task;
  List<_Segment> _segments = [];
  List<_Unit> _units = [];
  int _nextChapter = 0, _nextSegment = 0;
  PlayerItem? _current;
  final _requested = <String>{};
  final _repaired = <String>{};
  _Unit? _badUnit;
  Object? _visible;
  int _session = 0, _commands = 0, _cursor = 0, _appended = 0, _segment = 0;
  int _playerGeneration = 0;
  bool _intent = false,
      _heard = false,
      _refreshing = false,
      _again = false,
      _disposed = false;
  TtsError? _failure;
  @override
  NarrationState get state => _state;
  @override
  StopReason? get stopReason => _reason;
  @override
  NarrationError? get error => _error;
  @override
  String? get bookId => _book?.id;
  @override
  int? get block => _position?.block;
  @override
  double get blockProgress => _book == null || _position == null
      ? 0
      : _position!.offset /
            math.max(1, _book!.blocks[_position!.block].text.length);
  @override
  ReadingPosition? get unitStart => _start;
  @override
  double get speed => settings.speed;
  @override
  SleepTimer? get sleepTimer => _sleep;
  @override
  DateTime now() => clock.now();
  @override
  int get commandRevision => _commands;
  int get session => _session;

  @override
  void notifyListeners() {
    // Шаг — полпроцента блока или восемь знаков для длинного абзаца.
    // Одинаковый снимок не пересобирает экран и уведомление на каждом ходе.
    final visible = (
      _state,
      _reason,
      _error,
      bookId,
      block,
      (blockProgress * 200).floor(),
      (_position?.offset ?? 0) ~/ 8,
      _start,
      speed,
      _sleep,
      _commands,
    );
    if (visible == _visible) return;
    _visible = visible;
    super.notifyListeners();
  }

  VoiceProfile profileFor(Book book) => VoiceProfile(
    model: settings.modelId,
    voiceId: library.bookVoice(book.id) ?? settings.voice,
    style: readingStyleFor(book.language),
  );

  void _command() {
    _commands++;
    if (_sleep?.kind == SleepKind.minutes &&
        _sleep!.remaining(now()) == Duration.zero) {
      _sleepAlarm?.cancel();
      _sleep = null;
    }
  }

  @override
  void listen(Book book, PageRange page) {
    if (!settings.hasApiKey) return;
    _command();
    final saved = library.listeningPositionOf(book.id);
    if (saved != null && page.contains(saved)) {
      _begin(book, saved, true);
      return;
    }
    for (
      var i = page.start.block;
      i <= page.end.block && i < book.blocks.length;
      i++
    ) {
      final b = book.blocks[i];
      if (!b.isSpoken) continue;
      for (final offset in blockSentenceStarts(b)) {
        final p = ReadingPosition(i, offset);
        if (page.contains(p)) {
          _begin(book, p, true);
          return;
        }
      }
    }
    final b = book.blocks[page.start.block];
    _begin(
      book,
      ReadingPosition(b.index, blockSentenceStartAt(b, page.start.offset)),
      true,
    );
  }

  ReadingPosition _first(SpeechSegment s) =>
      ReadingPosition(s.mappings.first.block, s.mappings.first.blockStart);
  void _begin(Book book, ReadingPosition at, bool intent) {
    if (_book?.id != book.id) {
      _sleepAlarm?.cancel();
      _sleep = null;
    }
    _session++;
    _task?.dispose();
    player.clear(++_playerGeneration);
    player.setSpeed(speed);
    _book = book;
    _profile = profileFor(book);
    _failure = null;
    _error = null;
    _reason = null;
    _intent = intent;
    _heard = false;
    _cursor = _appended = _segment = 0;
    _current = null;
    _requested.clear();
    _repaired.clear();
    _badUnit = null;
    _segments = [];
    _units = [];
    _nextSegment = 0;
    _nextChapter = book.chapterOf(at.block);
    _loadChapter(at: at);
    _ensureUnits();
    _start = _position = _segments.isEmpty
        ? at
        : _first(_segments.first.speech);
    _state = intent ? NarrationState.preparing : NarrationState.paused;
    _save(listening: true);
    final session = _session;
    _task = queue.task(
      session: session,
      canStart: _canStart,
      changed: () {
        if (session == _session) _refresh();
      },
      failed: (e) {
        if (session == _session) _fatal(e);
      },
    );
    notifyListeners();
    _refresh();
  }

  bool _loadChapter({ReadingPosition? at}) {
    final book = _book!;
    while (_nextChapter < book.chapters.length) {
      final c = _nextChapter++;
      final ch = book.chapters[c];
      final blocks = book.blocks.sublist(ch.firstBlock, ch.endBlock);
      final canonical = chapterSegments(blocks);
      final exact = at == null
          ? -1
          : canonical.indexWhere((s) => _first(s) == at);
      // Каноническая часть длинного предложения уже имеет точную границу.
      // Повторная нормализация к началу предложения увела бы назад на другой отрезок.
      final list = at == null
          ? canonical
          : exact >= 0
          ? canonical.sublist(exact)
          : segmentsFrom(blocks, block: at.block, offset: at.offset);
      _segments.addAll(list.map((s) => _Segment(s, c)));
      if (list.isNotEmpty) return true;
      at = null;
    }
    return false;
  }

  double get _target {
    var seconds = reserveTarget.inSeconds.toDouble();
    if (_sleep?.kind == SleepKind.minutes) {
      seconds = math.min(
        seconds,
        _sleep!.remaining(now()).inMicroseconds / 1000000,
      );
    }
    return seconds;
  }

  double _seconds(_Unit u) =>
      (u.duration?.inMicroseconds.toDouble() ??
          u.speech.text.length * secondsPerChar * 1000000) /
      1000000 /
      speed;

  double get _elapsed =>
      _current == null ? 0 : player.position.inMicroseconds / 1000000 / speed;

  // Готовность и отпечатки проверяем только для окна запаса, главы делим по надобности.
  void _ensureUnits() {
    var ahead = -_elapsed;
    for (var i = _cursor; i < _units.length; i++) {
      ahead += _seconds(_units[i]);
    }
    while (ahead < _target || _units.length <= _cursor) {
      if (_nextSegment >= _segments.length && !_loadChapter()) break;
      final i = _nextSegment++;
      final ready = segmentReadiness(
        _segments[i].speech,
        _profile!,
        queue.audio.formatId,
        (key) =>
            queue.audio.has(key, bookId: bookId) ||
            queue.isPending(key, bookId: bookId),
        startup: i == 0,
      );
      for (final u in ready.units) {
        _units.add(
          _Unit(
            u.segment,
            i,
            queue.request(u.text, _profile!, bookId: bookId, session: _session),
          ),
        );
        ahead += _seconds(_units.last);
      }
    }
  }

  bool _canStart(SynthesisRequest request) {
    if (!_intent || _failure != null || !isActive) return false;
    if (_requested.contains(request.fingerprint)) return true;
    var bought = -_elapsed;
    for (var i = _cursor; i < _boundary; i++) {
      final u = _units[i];
      if (_requested.contains(u.request.fingerprint) ||
          queue.audio.has(u.request.fingerprint, bookId: bookId) ||
          queue.isPending(u.request.fingerprint, bookId: bookId)) {
        bought += _seconds(u);
      }
    }
    if (bought >= _target) return false;
    _requested.add(request.fingerprint);
    return true;
  }

  @override
  void resume() {
    final book = _book;
    if (book == null ||
        !settings.hasApiKey ||
        (_state != NarrationState.paused && _state != NarrationState.stopped)) {
      return;
    }
    _command();
    if (_state == NarrationState.stopped) {
      _begin(book, library.positionOf(book.id) ?? _start!, true);
      return;
    }
    _intent = true;
    _state = _current == null
        ? NarrationState.preparing
        : NarrationState.playing;
    notifyListeners();
    if (_cursor < _appended) player.play();
    _refresh();
  }

  @override
  void pause() {
    if (!isActive) return;
    _intent = false;
    player.pause();
    _updatePosition();
    _state = NarrationState.paused;
    _task?.update(
      _units.skip(_cursor).map((u) => u.request).toList(),
      active: false,
    );
    _save();
    _flush();
    notifyListeners();
  }

  @override
  void readFrom(Book book, int block) {
    if (!settings.hasApiKey) return;
    _command();
    _begin(
      book,
      ReadingPosition(block, 0),
      _book?.id == book.id && isActive ? _intent : true,
    );
  }

  @override
  void moveIfListening(Book book, int block) {
    if (_book?.id != book.id || !isActive) return;
    _command();
    _begin(book, ReadingPosition(block, 0), _intent);
  }

  void _step(bool forward) {
    final book = _book;
    if (book == null || !isActive || _position == null) return;
    _updatePosition();
    final current = _position!.block;
    // Это оценка места, а не время текущего файла: один абзац может занимать несколько файлов.
    final seconds = _position!.offset * secondsPerChar / speed;
    // Пауза посреди абзаца началом не считается: «назад» возвращает к началу этого абзаца.
    final atStart = !_heard || seconds < blockStartWindow.inMilliseconds / 1000;
    var target = forward ? current + 1 : atStart ? current - 1 : current;
    while (target >= 0 && target < book.blocks.length) {
      // Те же правила пригодности текста, что у синтеза, включая сноски и блоки из одних знаков.
      if (chapterSegments([book.blocks[target]]).isNotEmpty) break;
      target += forward ? 1 : -1;
    }
    if (target < 0 || target >= book.blocks.length) return;
    _command();
    // Каноническое начало/части берутся из кэша; segmentsFrom нужен только для хвоста группы.
    _begin(book, ReadingPosition(target, 0), _intent);
  }

  @override
  void next() => _step(true);
  @override
  void previous() => _step(false);
  @override
  void restartSession() {
    if (!isActive ||
        _book == null ||
        _start == null ||
        profileFor(_book!) == _profile) {
      return;
    }
    _begin(_book!, _start!, _intent);
  }

  int get _boundary {
    if (_sleep?.kind != SleepKind.endOfChapter || _segments.isEmpty) {
      return _units.length;
    }
    final chapter = _segments[_segment].chapter;
    final index = _units.indexWhere(
      (u) => _segments[u.segment].chapter > chapter,
    );
    return index < 0 ? _units.length : index;
  }

  void _refresh() {
    if (_disposed || !isActive) return;
    _again = true;
    if (_refreshing) return;
    unawaited(_refreshLoop());
  }

  Future<void> _refreshLoop() async {
    _refreshing = true;
    try {
      while (_again && !_disposed && isActive) {
        _again = false;
        final session = _session;
        _ensureUnits();
        var ahead = -_elapsed;
        // Пробуем только окно запаса. Файлы за дырой учитываются в покупке,
        // но в плеер попадает лишь непрерывный префикс.
        for (var i = _cursor; i < _boundary && ahead < _target; i++) {
          final u = _units[i];
          final file = queue.audio.file(u.request.fingerprint, bookId: bookId);
          if (file != null && u.duration == null) {
            try {
              u.duration = await player.duration(file);
              if (u.duration! <= Duration.zero) throw const FormatException();
            } catch (e) {
              if (!_disposed && session == _session && isActive) {
                _repairFile(u, '${e.runtimeType}');
              }
            }
          }
          if (_disposed || session != _session || !isActive) break;
          if (i >= _boundary) break;
          if (i == _appended &&
              u.duration != null &&
              queue.audio.has(u.request.fingerprint, bookId: bookId)) {
            final item = PlayerItem(
              file: file!,
              segment: u.segment,
              duration: u.duration!,
            );
            u.item = item;
            _appended++;
            player.append(item);
            // Первый звук не ждёт проб оставшихся файлов.
            if (_intent) {
              player.play();
            }
          }
          ahead += _seconds(u);
        }
        if (_disposed || session != _session || !isActive) continue;
        if (_intent && _cursor < _appended) {
          if (_current != null) _state = NarrationState.playing;
          player.play();
        }
        final requests = _units
            .skip(_cursor)
            .take(math.max(0, _boundary - _cursor))
            .map((u) => u.request)
            .toList();
        // Пауза сохраняет интерес к уже идущему ответу и его постоянной ошибке.
        _task?.update(requests, active: _intent && _failure == null);
        if (_cursor >= _appended) _exhausted();
        if (!_disposed) notifyListeners();
      }
    } finally {
      _refreshing = false;
    }
  }

  void _event(PlayerEvent event) {
    if (_disposed || event.generation != _playerGeneration || !isActive) return;
    switch (event.kind) {
      case PlayerEventKind.failed:
        final index = _units.indexWhere((u) => identical(u.item, event.item));
        if (index < _cursor) return;
        _cursor = index;
        _current = null;
        // Список заменяется, сеанс синтеза остаётся. Старый drained не вправе
        // завершить уже восстановленный список.
        player.clear(++_playerGeneration);
        _appended = index;
        for (final u in _units.skip(index)) {
          u.item = null;
        }
        _repairFile(_units[index], 'PlayerError');
        _refresh();
      case PlayerEventKind.interrupted:
        pause();
      case PlayerEventKind.started:
        final index = _units.indexWhere((u) => identical(u.item, event.item));
        if (index < 0) return;
        _cursor = index;
        _current = event.item;
        if (_intent) _state = NarrationState.playing;
        _segment = _units[index].segment;
        _heard = true;
        _start = _first(_segments[_segment].speech);
        final oldBlock = block;
        _updatePosition();
        if (oldBlock != block) _save();
        library.saveListeningPosition(bookId!, _start!);
        notifyListeners();
      case PlayerEventKind.progress:
        final oldBlock = block;
        _updatePosition();
        if (oldBlock != block) _save();
        notifyListeners();
        _refresh();
      case PlayerEventKind.drained:
        _current = null;
        _cursor = _appended;
        _exhausted();
        _refresh();
    }
  }

  void _updatePosition() {
    if (_cursor >= _units.length || _current == null) return;
    final u = _units[_cursor];
    final fraction =
        player.position.inMicroseconds /
        math.max(1, _current!.duration.inMicroseconds);
    final offset = (fraction * u.speech.text.length).floor().clamp(
      0,
      u.speech.text.length - 1,
    );
    final mapping =
        u.speech.mappings.where((m) => m.end > offset).firstOrNull ??
        u.speech.mappings.last;
    _position = ReadingPosition(
      mapping.block,
      mapping.blockStart +
          (offset - mapping.start).clamp(
            0,
            mapping.blockEnd - mapping.blockStart - 1,
          ),
    );
  }

  void _save({bool listening = false}) {
    if (_book == null || _position == null) return;
    library.savePosition(_book!.id, _position!);
    if (listening && _start != null) {
      library.saveListeningPosition(_book!.id, _start!);
    }
  }

  void _flush() {
    unawaited(
      library.flush().catchError((Object error) {
        library.recordFileFailure('state.json / settings.json', error);
      }),
    );
  }

  void _repairFile(_Unit u, String type) {
    final file = queue.audio.file(u.request.fingerprint, bookId: bookId);
    u.duration = null;
    u.item = null;
    try {
      if (file != null) file.deleteSync();
    } catch (e) {
      _badUnit = u;
      _failure = TtsError('${e.runtimeType}: audio file removal failed');
    }
    if (!_repaired.add(u.request.fingerprint)) {
      _badUnit = u;
      _failure = TtsError('$type: audio file unreadable');
    } else {
      // Замена уже оплаченного файла сохраняет его место в резерве, как повтор
      // временной ошибки; дальний готовый звук не должен запирать эту дыру.
      _requested.add(u.request.fingerprint);
    }
    if (_failure != null && !_intent) _stopError();
  }

  void _fatal(TtsError error) {
    _failure = error;
    if (_state == NarrationState.paused) {
      _stopError();
      return;
    }
    _refresh();
  }

  void _stopError() {
    final e = _failure!;
    // Первое ещё не опубликованное место, а не место последнего готового дальнего файла.
    final missing =
        _badUnit ??
        _units
            .skip(_cursor)
            .where(
              (u) => !queue.audio.has(u.request.fingerprint, bookId: bookId),
            )
            .firstOrNull;
    if (missing != null) _start = _position = _first(missing.speech);
    _error = NarrationError(
      switch (e.reason) {
        TtsErrorReason.paymentRequired => NarrationErrorKind.payment,
        TtsErrorReason.modelNotFound => NarrationErrorKind.modelNotFound,
        TtsErrorReason.invalidKey => NarrationErrorKind.badKey,
        _ => NarrationErrorKind.other,
      },
      e.message,
      modelId: e.model,
    );
    _stop(StopReason.error);
  }

  void _stop(StopReason reason) {
    _intent = false;
    player.pause();
    _task?.dispose();
    _state = NarrationState.stopped;
    _reason = reason;
    _save(listening: true);
    _flush();
    notifyListeners();
  }

  void _exhausted() {
    if (!_intent || _cursor < _appended) return;
    if (_failure != null) {
      _stopError();
      return;
    }
    // Конец материализованного окна ещё не означает конец главы или книги.
    // Сначала открываем следующие отрезки, затем проверяем настоящую границу.
    if (_cursor >= _units.length) _ensureUnits();
    final more =
        _nextSegment < _segments.length ||
        _nextChapter < _book!.chapters.length;
    if (_cursor >= _units.length && !more) {
      if (_sleep?.kind == SleepKind.endOfChapter) {
        _sleepAlarm?.cancel();
        _sleep = null;
      }
      library.setFinished(bookId!, true);
      _stop(StopReason.endOfBook);
    } else if (_cursor >= _boundary && _sleep?.kind == SleepKind.endOfChapter) {
      final at = _first(_units[_cursor].speech);
      _sleepAlarm?.cancel();
      _sleep = null;
      _begin(_book!, at, false);
    } else {
      _state = _heard ? NarrationState.waiting : NarrationState.preparing;
    }
  }

  @override
  void setSpeed(double speed) {
    if (!speeds.contains(speed)) throw ArgumentError.value(speed);
    settings.speed = speed;
    player.setSpeed(speed);
    notifyListeners();
    // Пересчёт запаса идёт на следующем событии/ответе; сама команда запросов не делает.
  }

  @override
  void setSleepTimer(SleepTimer? timer) {
    _sleepAlarm?.cancel();
    _sleep = timer;
    if (timer?.kind == SleepKind.minutes) {
      _sleepAlarm = clock.schedule(timer!.remaining(now()), () {
        _sleep = null;
        if (_state == NarrationState.playing ||
            _state == NarrationState.preparing ||
            _state == NarrationState.waiting) {
          pause();
        } else {
          notifyListeners();
        }
      });
    }
    if (timer?.kind == SleepKind.endOfChapter && _units.isNotEmpty) {
      final boundary = _boundary;
      if (boundary < _units.length) {
        player.retainThrough(_units[boundary].segment - 1);
        _appended = math.min(_appended, boundary);
      }
    }
    notifyListeners();
    _refresh();
  }

  @override
  void close({ReadingPosition? screenPosition}) {
    final book = _book;
    _updatePosition();
    final position = screenPosition ?? (isActive ? _position : null);
    _session++;
    _task?.dispose();
    _task = null;
    player.clear(++_playerGeneration);
    _current = null;
    _sleepAlarm?.cancel();
    _sleep = null;
    _intent = false;
    _state = NarrationState.idle;
    _reason = null;
    _error = null;
    _book = null;
    _start = _position = null;
    if (book != null && position != null) {
      library.savePosition(book.id, position);
    }
    _flush();
    notifyListeners();
  }

  @override
  void clearAllNarration() {
    downloads?.forget();
    close();
    queue.invalidateAll();
    sampler.clearCache();
    queue.audio.clearAll();
  }

  @override
  void deleteBookNarration(String bookId) {
    downloads?.forget(bookId: bookId);
    if (this.bookId == bookId) close();
    queue.invalidateBook(bookId);
    queue.audio.removeBook(bookId);
  }

  @override
  void deleteBook(String bookId) {
    final title = library.entry(bookId).title;
    deleteBookNarration(bookId);
    queue.invalidateBook(bookId, deleted: true);
    unawaited(
      library.deleteBook(bookId).catchError((Object error) {
        if (library.shelf.any((book) => book.id == bookId)) {
          queue.restoreBook(bookId);
        }
        library.recordFileFailure(title, error);
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _task?.dispose();
    _sleepAlarm?.cancel();
    player.clear(++_playerGeneration);
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
