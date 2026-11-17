import 'dart:async';
import 'dart:math' as math;

import '../audio/audio_store.dart';
import '../book/model.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../tts/voices.dart';
import 'chapter_download.dart';
import 'narration.dart';
import 'voice_sample.dart';

/// The same block-start window as in the real controller.
const _blockStartWindow = Duration(seconds: 3);

/// The prototype's fake narration: no audio, a timer moves the "voiced" block through the book.
///
/// The unit is a block, not a segment of А§6.1: the prototype has no splitting of long paragraphs or merging of short
/// lines. A start from a sentence inside a block is a fraction of the block elapsed; in the real app it is the start
/// segment of А§6.1. Block duration is characters × 0.069 s ÷ speed ÷ [demoAcceleration], so that following the voice
/// is visible in a minute rather than ten.
class FakeNarrationController extends NarrationController {
  FakeNarrationController({
    required this.library,
    required this.audio,
    required this.downloads,
    required this.sampler,
    this.prepareDelay = const Duration(milliseconds: 1400),
    this.tick = const Duration(milliseconds: 100),
    this.demoAcceleration = 4,
    this.settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The speed is a setting (FR-P5): the session plays at the saved one, not at 1×.
  final AppSettings? settings;

  final Library library;
  final AudioStore audio;
  final ChapterDownloads downloads;
  final VoiceSampler sampler;
  final Duration prepareDelay;
  final Duration tick;
  final double demoAcceleration;
  final DateTime Function() _clock;

  NarrationState _state = NarrationState.idle;
  StopReason? _stopReason;
  NarrationError? _error;
  Book? _book;
  int? _block;
  double _progress = 0;
  double _speed = 1;
  SleepTimer? _sleep;
  Timer? _timer;
  Timer? _prepare;

  /// Session number (А§6.4): a response of a previous session does not touch the new one.
  int _session = 0;

  /// The offset of the start of the voiced unit in the block: 0 or the start of the sentence the block was started
  /// from.
  int _unitStart = 0;

  /// The state holds until the user changes it (display only: "Preparing voice…", "Waiting for connection…").
  bool _held = false;

  @override
  NarrationState get state => _state;
  @override
  StopReason? get stopReason => _stopReason;
  @override
  NarrationError? get error => _error;
  @override
  String? get bookId => _book?.id;
  @override
  int? get block => _block;
  @override
  double get blockProgress => _progress;
  @override
  ReadingPosition? get sounding {
    if (_book == null || _block == null) return null;
    final len = _book!.blocks[_block!].text.length;
    final offset = math.min((_progress.clamp(0.0, 1.0) * len).floor(), math.max(0, len - 1));
    return ReadingPosition(_block!, offset);
  }
  @override
  ReadingPosition? get unitStart => _block == null ? null : ReadingPosition(_block!, _unitStart);
  @override
  double get speed => settings?.speed ?? _speed;
  @override
  SleepTimer? get sleepTimer => _sleep;
  @override
  DateTime now() => _clock();

  Book? get book => _book;

  // --- contract commands -------------------------------------------------------------------------------

  int _commands = 0;

  @override
  int get commandRevision => _commands;

  /// An explicit user command (А§5, А§6.6): a counter for the screen, and an expired sleep timer is not inherited by
  /// the new start (FR-D1, logic review item 7).
  void _userCommand() {
    _commands++;
    _dropExpiredSleep();
  }

  @override
  void listen(Book book, PageRange page) {
    _userCommand();
    _enterBook(book);
    _startAt(book, listenStart(book, page, library.listeningPositionOf(book.id)));
  }

  /// The session moves to the book [book]; for a different book the sleep timer is cleared (rule c).
  void _enterBook(Book book) {
    if (_book != null && _book!.id != book.id) _sleep = null;
    _book = book;
  }

  /// A new session from place [p]: from a block and an offset inside it (the start segment from a sentence, А§6.1).
  void _startAt(Book book, ReadingPosition p) {
    _enterBook(book);
    final block = spokenBlockFrom(_book!, p.block, forward: true) ?? p.block;
    _newSession(block, block == p.block ? p.offset : 0);
  }

  @override
  void resume() {
    final book = _book;
    if (book == null) return;
    // The timer expired while there was no audio: it has nothing to stop — cleared, "Listen" plays (rule c).
    _userCommand();
    if (_state == NarrationState.stopped) {
      // A new session from the current saved position: after a stop the screen may have rewritten it (А§5).
      final saved = library.positionOf(book.id) ?? ReadingPosition(_block ?? 0, 0);
      _startAt(book, saved);
      return;
    }
    if (_state == NarrationState.paused) {
      _held = false;
      _enter(NarrationState.playing);
    }
  }

  @override
  void pause() {
    if (_state == NarrationState.preparing || _state == NarrationState.playing || _state == NarrationState.waiting) {
      _held = false;
      _prepare?.cancel();
      _enter(NarrationState.paused);
    }
  }

  @override
  void readFrom(Book book, int block) {
    _userCommand();
    if (_book?.id == book.id && (_state == NarrationState.paused || isActive)) {
      _moveKeepingIntent(block);
    } else {
      // "Read from here" — from the start of the selected paragraph (FR-P3, D).
      _startAt(book, ReadingPosition(block, 0));
    }
  }

  @override
  void moveIfListening(Book book, int block) {
    if (_book?.id == book.id && (_state == NarrationState.paused || isActive)) {
      _userCommand();
      _moveKeepingIntent(block);
    }
  }

  @override
  void next() => _step(forward: true);

  @override
  void previous() => _step(forward: false);

  void _step({required bool forward}) {
    if (_book == null || _block == null) return;
    if (_state != NarrationState.paused && !isActive) return;
    final elapsed = _duration(_book!.blocks[_block!]).inMilliseconds * _progress;
    final atStart = elapsed < _blockStartWindow.inMilliseconds;
    final from = forward ? _block! + 1 : atStart ? _block! - 1 : _block!;
    final target = spokenBlockFrom(_book!, from, forward: forward);
    if (target == null) return;
    _userCommand();
    _moveKeepingIntent(target);
  }

  /// A place change within a session: a new session, the intent stays the same (А§6.6). A pause stays a pause. [offset]
  /// — the start of the unit inside the block (the start segment from a sentence).
  void _moveKeepingIntent(int block, {int offset = 0}) {
    final target = spokenBlockFrom(_book!, block, forward: true) ?? block;
    _session++;
    _prepare?.cancel();
    final len = _book!.blocks[target].text.length;
    _block = target;
    _unitStart = target == block ? offset.clamp(0, math.max(0, len - 1)) : 0;
    _progress = len == 0 ? 0 : _unitStart / len;
    _held = false;
    _savePosition();
    if (_state == NarrationState.paused) {
      notifyListeners();
    } else {
      // In the prototype the audio of the "neighboring" segment is always ready: playing at once (А§6.6: or preparing
      // if there is no audio).
      _enter(NarrationState.playing);
    }
  }

  @override
  void close({ReadingPosition? screenPosition}) {
    final book = _book;
    _endSession();
    // First the session is ended — then the screen position goes to the writer. Later no controller write
    // will overwrite it: the session number has already changed (А§5).
    if (book != null && screenPosition != null) {
      library.savePosition(book.id, screenPosition, fraction: book.fractionAt(screenPosition.block, screenPosition.offset));
    }
    notifyListeners();
  }

  void _endSession() {
    _session++;
    _timer?.cancel();
    _prepare?.cancel();
    // The sleep timer belongs to listening: "Close" and closing the book clear it (rule c).
    _sleep = null;
    _held = false;
    _book = null;
    _block = null;
    _progress = 0;
    _error = null;
    _stopReason = null;
    _state = NarrationState.idle;
  }

  @override
  void setSpeed(double speed) {
    _speed = speed;
    settings?.speed = speed;
    notifyListeners();
  }

  @override
  void setSleepTimer(SleepTimer? timer) {
    _sleep = timer;
    notifyListeners();
  }

  @override
  void restartSession() {
    if (_book == null || _block == null) return;
    // From the start of the current unit, including a start from a sentence inside a block (logic review item 2).
    if (_state == NarrationState.paused || isActive) _moveKeepingIntent(_block!, offset: _unitStart);
  }

  @override
  void clearAllNarration() {
    if (_state != NarrationState.idle) _endSession();
    downloads.forget();
    sampler.clearCache();
    audio.clearAll();
    notifyListeners();
  }

  @override
  void deleteBookNarration(String bookId) {
    if (_book?.id == bookId) _endSession();
    downloads.forget(bookId: bookId);
    audio.removeBook(bookId);
    notifyListeners();
  }

  @override
  void deleteBook(String bookId) {
    final title = library.entry(bookId).title;
    deleteBookNarration(bookId);
    unawaited(library.deleteBook(bookId).catchError((Object error) {
      library.recordFileFailure(title, error);
    }));
  }

  // --- display only: states that in real life are caused by the network -------------------------------

  /// Turns on a state for the "Demo states" panel. If there is no listening, starts it from [fromBlock].
  void demoShow(String what, {Book? book, int fromBlock = 0}) {
    if (_book == null || _state == NarrationState.idle) {
      if (book == null) return;
      _book = book;
      _block = spokenBlockFrom(_book!, fromBlock, forward: true) ?? fromBlock;
      _progress = 0.35;
      _unitStart = 0;
      _session++;
    }
    _prepare?.cancel();
    _error = null;
    _stopReason = null;
    switch (what) {
      case 'preparing':
        _held = true;
        _enter(NarrationState.preparing);
      case 'waiting':
        _held = true;
        _enter(NarrationState.waiting);
      case 'playing':
        _held = false;
        _enter(NarrationState.playing);
      case 'paused':
        _held = false;
        _enter(NarrationState.paused);
      case 'sleep':
        _sleep = SleepTimer.minutes(30, now().subtract(const Duration(minutes: 7)));
        _held = false;
        _enter(NarrationState.paused);
      case 'error402':
        _stop(const NarrationError(NarrationErrorKind.payment, 'Your prepayment credits are depleted.'));
      case 'error404':
        // The model on which the error happened is in the error itself: choosing another model later will not rename
        // it.
        final model = settings?.modelId ?? 'gemini-3.8-flash-tts';
        _stop(NarrationError(NarrationErrorKind.modelNotFound, 'models/$model is not found for API version v1beta.',
            modelId: model));
      case 'errorKey':
        _stop(const NarrationError(NarrationErrorKind.badKey, 'API key not valid. Please pass a valid API key.'));
      case 'errorOther':
        _stop(const NarrationError(NarrationErrorKind.other, 'Request contains an invalid argument.'));
      case 'end':
        _block = _lastSpoken();
        _progress = 1;
        _stopReason = StopReason.endOfBook;
        _enter(NarrationState.stopped);
        library.setFinished(_book!.id, true);
    }
  }

  void _stop(NarrationError error) {
    _error = error;
    _stopReason = StopReason.error;
    _enter(NarrationState.stopped);
  }

  // --- the "audio" progress ----------------------------------------------------------------------------

  void _newSession(int block, int offset) {
    _session++;
    final session = _session;
    final len = _book!.blocks[block].text.length;
    _block = block;
    _unitStart = offset.clamp(0, math.max(0, len - 1));
    _progress = len == 0 ? 0 : _unitStart / len;
    _error = null;
    _stopReason = null;
    _held = false;
    _savePosition();
    _enter(NarrationState.preparing);
    _prepare?.cancel();
    _prepare = Timer(prepareDelay, () {
      if (session == _session && _state == NarrationState.preparing && !_held) _enter(NarrationState.playing);
    });
  }

  void _enter(NarrationState s) {
    _state = s;
    _timer?.cancel();
    if (s == NarrationState.playing) {
      final session = _session;
      _timer = Timer.periodic(tick, (_) {
        if (session == _session) _advance();
      });
    } else if (s == NarrationState.preparing || s == NarrationState.waiting || s == NarrationState.paused) {
      // There is no audio, but the sleep timer deadline may pass right now (rule c).
      final session = _session;
      _timer = Timer.periodic(tick, (_) {
        if (session == _session) _expireSleep();
      });
    }
    if (s == NarrationState.stopped || s == NarrationState.paused) _savePosition();
    notifyListeners();
  }

  /// Before an explicit start: an expired timer deadline is simply cleared — it stops nothing for the new start.
  void _dropExpiredSleep() {
    final sleep = _sleep;
    if (sleep != null && sleep.kind == SleepKind.minutes && sleep.remaining(now()) == Duration.zero) _sleep = null;
  }

  /// The sleep timer's minute deadline passed: during audio and in `preparing`/`waiting` — a pause; on a pause the
  /// timer is simply cleared. In any case the timer is cleared and stops nothing more (rule c, FR-D1).
  bool _expireSleep() {
    final sleep = _sleep;
    if (sleep == null || sleep.kind != SleepKind.minutes || sleep.remaining(now()) > Duration.zero) return false;
    _sleep = null;
    if (_state == NarrationState.playing || _state == NarrationState.preparing || _state == NarrationState.waiting) {
      _held = false;
      _prepare?.cancel();
      _enter(NarrationState.paused);
    } else {
      notifyListeners();
    }
    return true;
  }

  Duration _duration(Block b) {
    // There is one speed: the same one the panel shows (logic review item 8).
    final secs = b.text.length * secondsPerChar / speed / demoAcceleration;
    return Duration(milliseconds: (math.max(1.6, secs) * 1000).round());
  }

  void _advance() {
    final book = _book;
    final block = _block;
    if (book == null || block == null) return;
    if (_expireSleep()) return;
    _progress += tick.inMilliseconds / _duration(book.blocks[block]).inMilliseconds;
    if (_progress < 1) {
      notifyListeners();
      return;
    }
    final nextBlock = spokenBlockFrom(_book!, block + 1, forward: true);
    if (nextBlock == null) {
      _progress = 1;
      _stopReason = StopReason.endOfBook;
      // The last chapter has ended too: the "until end of chapter" timer fired and is cleared (logic review item 7).
      if (_sleep?.kind == SleepKind.endOfChapter) _sleep = null;
      _enter(NarrationState.stopped);
      // Listening reached the end of the book — the book is finished (FR-L4, rule d).
      library.setFinished(book.id, true);
      return;
    }
    final chapterEnds = book.chapterOf(nextBlock) != book.chapterOf(block);
    _block = nextBlock;
    _progress = 0;
    _unitStart = 0;
    _savePosition();
    if (chapterEnds && _sleep?.kind == SleepKind.endOfChapter) {
      _sleep = null;
      _enter(NarrationState.paused);
      return;
    }
    notifyListeners();
  }

  int _lastSpoken() => spokenBlockFrom(_book!, _book!.blocks.length - 1, forward: false) ?? 0;

  /// While the session is active, the controller writes the reading position: the voiced place (А§5). The listening
  /// place — the start of the voiced unit — is always written and is erased by neither a pause, nor a stop, nor "Close"
  /// (А§4).
  void _savePosition() {
    final book = _book;
    final block = _block;
    if (book == null || block == null) return;
    final len = book.blocks[block].text.length;
    final offset = math.min((_progress * len).floor(), math.max(0, len - 1));
    // The library computes the chapter name for the shelf from the position itself: changing the chapter via the table
    // of contents will not leave the previous one on the shelf (finding 2 of the path review).
    library.savePosition(book.id, ReadingPosition(block, offset), fraction: book.fractionAt(block, offset));
    library.saveListeningPosition(book.id, ReadingPosition(block, _unitStart));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prepare?.cancel();
    super.dispose();
  }
}
