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
  int _session = 0, _commands = 0, _cursor = 0, _appended = 0, _segment = 0;
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
    player.clear(_session);
    player.setSpeed(speed);
    _book = book;
    _profile = profileFor(book);
    _failure = null;
    _error = null;
    _reason = null;
    _intent = intent;
    _heard = false;
    _cursor = _appended = _segment = 0;
    _segments = [];
    final chapter = book.chapterOf(at.block);
    for (var c = chapter; c < book.chapters.length; c++) {
      final ch = book.chapters[c];
      final blocks = book.blocks.sublist(ch.firstBlock, ch.endBlock);
      final canonical = chapterSegments(blocks);
      final exact = canonical.indexWhere((s) => _first(s) == at);
      // Каноническая часть длинного предложения уже имеет точную границу.
      // Повторная нормализация к началу предложения увела бы назад на другой отрезок.
      final list = c != chapter
          ? canonical
          : exact >= 0
          ? canonical.sublist(exact)
          : segmentsFrom(blocks, block: at.block, offset: at.offset);
      _segments.addAll(list.map((s) => _Segment(s, c)));
    }
    _units = [];
    for (var i = 0; i < _segments.length; i++) {
      final ready = segmentReadiness(
        _segments[i].speech,
        _profile!,
        queue.audio.formatId,
        (key) =>
            queue.audio.has(key, bookId: book.id) ||
            queue.isPending(key, bookId: book.id),
        startup: i == 0,
      );
      for (final u in ready.units) {
        _units.add(
          _Unit(
            u.segment,
            i,
            queue.request(
              u.text,
              _profile!,
              bookId: book.id,
              session: _session,
            ),
          ),
        );
      }
    }
    _start = _position = _segments.isEmpty
        ? at
        : _first(_segments.first.speech);
    _state = intent ? NarrationState.preparing : NarrationState.paused;
    _save(listening: true);
    final session = _session;
    _task = queue.task(
      session: session,
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
    _state = player.current == null
        ? NarrationState.preparing
        : NarrationState.playing;
    notifyListeners();
    if (player.current != null) player.play();
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
    unawaited(library.flush());
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
    if (book == null || !isActive || _start == null) return;
    final all = <SpeechSegment>[
      for (final ch in book.chapters)
        ...chapterSegments(book.blocks.sublist(ch.firstBlock, ch.endBlock)),
    ];
    var current = all.indexWhere(
      (s) => s.mappings.any(
        (m) =>
            m.block == _start!.block &&
            m.blockStart <= _start!.offset &&
            m.blockEnd > _start!.offset,
      ),
    );
    current += forward ? 1 : -1;
    if (current < 0 || current >= all.length) return;
    _command();
    _begin(book, _first(all[current]), _intent);
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
        final boundary = _boundary;
        // Только непрерывный префикс попадает в список, в том числе при паузе.
        while (_appended < boundary) {
          final u = _units[_appended];
          final file = queue.audio.file(u.request.fingerprint, bookId: bookId);
          if (file == null) break;
          Duration length;
          try {
            length = await player.duration(file);
          } catch (_) {
            if (!_disposed && session == _session && isActive) {
              _failure = const TtsError('Не удалось прочитать звуковой файл');
              _stopError();
            }
            break;
          }
          if (_disposed || session != _session || !isActive) break;
          if (_appended >= _boundary) break;
          final item = PlayerItem(
            file: file,
            segment: u.segment,
            duration: length,
          );
          u.item = item;
          _appended++;
          player.append(item);
        }
        if (_disposed || session != _session || !isActive) continue;
        if (_intent && player.current != null) {
          _state = NarrationState.playing;
          player.play();
        }
        var reserve = 0.0;
        for (var i = _cursor; i < _appended; i++) {
          reserve +=
              (_units[i].item!.duration.inMicroseconds -
                  (identical(player.current, _units[i].item)
                      ? player.position.inMicroseconds
                      : 0)) /
              1000000 /
              speed;
        }
        var target = reserveTarget.inSeconds.toDouble();
        if (_sleep?.kind == SleepKind.minutes) {
          target = math.min(
            target,
            _sleep!.remaining(now()).inMicroseconds / 1000000,
          );
        }
        final requests = _units
            .skip(_cursor)
            .take(math.max(0, _boundary - _cursor))
            .map((u) => u.request)
            .toList();
        // Пауза сохраняет интерес к уже идущему ответу и его постоянной ошибке.
        _task?.update(
          requests,
          active: _intent && _failure == null && reserve < target,
        );
        if (player.current == null) _exhausted();
        if (!_disposed) notifyListeners();
      }
    } finally {
      _refreshing = false;
    }
  }

  void _event(PlayerEvent event) {
    if (_disposed || event.generation != _session || !isActive) return;
    switch (event.kind) {
      case PlayerEventKind.interrupted:
        pause();
      case PlayerEventKind.started:
        final index = _units.indexWhere((u) => identical(u.item, event.item));
        if (index < 0) return;
        _cursor = index;
        _segment = _units[index].segment;
        _heard = true;
        _start = _first(_segments[_segment].speech);
        _updatePosition();
        _save(listening: true);
        notifyListeners();
      case PlayerEventKind.progress:
        _updatePosition();
        _save();
        notifyListeners();
        _refresh();
      case PlayerEventKind.drained:
        _cursor = _appended;
        _exhausted();
        _refresh();
    }
  }

  void _updatePosition() {
    if (_cursor >= _units.length || player.current == null) return;
    final u = _units[_cursor];
    final fraction =
        player.position.inMicroseconds /
        math.max(1, player.current!.duration.inMicroseconds);
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
    final missing = _units
        .skip(_cursor)
        .where((u) => !queue.audio.has(u.request.fingerprint, bookId: bookId))
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
    unawaited(library.flush());
    notifyListeners();
  }

  void _exhausted() {
    if (!_intent || player.current != null) return;
    if (_failure != null) {
      _stopError();
      return;
    }
    if (_cursor >= _units.length) {
      if (_sleep?.kind == SleepKind.endOfChapter) setSleepTimer(null);
      library.setFinished(bookId!, true);
      _stop(StopReason.endOfBook);
    } else if (_cursor >= _boundary && _sleep?.kind == SleepKind.endOfChapter) {
      final at = _first(_segments[_units[_cursor].segment].speech);
      setSleepTimer(null);
      _begin(_book!, at, false);
    } else if (_heard) {
      _state = NarrationState.waiting;
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
    final position = screenPosition ?? _position;
    _session++;
    _task?.dispose();
    _task = null;
    player.clear(_session);
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
    unawaited(library.flush());
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
    deleteBookNarration(bookId);
    queue.invalidateBook(bookId, deleted: true);
    unawaited(library.deleteBook(bookId));
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _task?.dispose();
    _sleepAlarm?.cancel();
    player.clear(_session);
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
