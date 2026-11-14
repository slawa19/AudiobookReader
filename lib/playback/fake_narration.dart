import 'dart:async';
import 'dart:math' as math;

import '../book/model.dart';
import '../library/library.dart';
import '../tts/voices.dart';
import 'narration.dart';

/// Подставная озвучка прототипа: звука нет, таймер двигает «звучащий» блок по книге.
///
/// Единица — блок, а не отрезок А§6.1: деления длинных абзацев и склейки коротких реплик в прототипе нет.
/// Длительность блока — знаки × 0,069 с ÷ скорость ÷ [demoAcceleration], чтобы следование за голосом было видно
/// за минуту, а не за десять.
class FakeNarrationController extends NarrationController {
  FakeNarrationController({
    required this.library,
    this.prepareDelay = const Duration(milliseconds: 1400),
    this.tick = const Duration(milliseconds: 100),
    this.demoAcceleration = 4,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Library library;
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

  /// Состояние держится, пока его не сменит пользователь (только для показа: «Готовлю голос…», «Жду связь…»).
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
  double get speed => _speed;
  @override
  SleepTimer? get sleepTimer => _sleep;
  @override
  DateTime now() => _clock();

  Book? get book => _book;

  @override
  void start(Book book, int fromBlock) {
    _book = book;
    _block = _spokenFrom(fromBlock, forward: true) ?? fromBlock;
    _progress = 0;
    _error = null;
    _stopReason = null;
    _held = false;
    _savePosition();
    _enter(NarrationState.preparing);
    _prepare?.cancel();
    _prepare = Timer(prepareDelay, () {
      if (_state == NarrationState.preparing && !_held) _enter(NarrationState.playing);
    });
  }

  @override
  void resume() {
    if (_book == null) return;
    if (_state == NarrationState.stopped) {
      start(_book!, _block ?? 0);
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
      _enter(NarrationState.paused);
    }
  }

  @override
  void next() => _jump(forward: true);

  @override
  void previous() => _jump(forward: false);

  void _jump({required bool forward}) {
    if (_book == null || _block == null) return;
    final target = forward ? _spokenFrom(_block! + 1, forward: true) : _spokenFrom(_block! - 1, forward: false);
    if (target == null) return;
    _block = target;
    _progress = 0;
    _savePosition();
    if (_state == NarrationState.paused) {
      notifyListeners();
    } else {
      _held = false;
      _enter(NarrationState.playing);
    }
  }

  @override
  void close() {
    _timer?.cancel();
    _prepare?.cancel();
    _held = false;
    _book = null;
    _block = null;
    _progress = 0;
    _error = null;
    _stopReason = null;
    _state = NarrationState.idle;
    notifyListeners();
  }

  @override
  void setSpeed(double speed) {
    _speed = speed;
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
    _progress = 0;
    if (_state == NarrationState.paused || _state == NarrationState.stopped || _state == NarrationState.idle) {
      notifyListeners();
      return;
    }
    start(_book!, _block!);
  }

  // --- только для показа: состояния, которые в жизни вызывает сеть -----------------------------------------

  /// Включает состояние для панели «Состояния для показа». Если прослушивания нет, начинает его с [fromBlock].
  void demoShow(String what, {Book? book, int fromBlock = 0}) {
    if (_book == null || _state == NarrationState.idle) {
      if (book == null) return;
      _book = book;
      _block = _spokenFrom(fromBlock, forward: true) ?? fromBlock;
      _progress = 0.35;
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
        _stop(const NarrationError(
            NarrationErrorKind.modelNotFound, 'models/gemini-3.8-flash-tts is not found for API version v1beta.'));
      case 'errorOther':
        _stop(const NarrationError(NarrationErrorKind.other, 'API key not valid. Please pass a valid API key.'));
      case 'end':
        _block = _lastSpoken();
        _progress = 1;
        _stopReason = StopReason.endOfBook;
        _enter(NarrationState.stopped);
    }
  }

  void _stop(NarrationError error) {
    _error = error;
    _stopReason = StopReason.error;
    _enter(NarrationState.stopped);
  }

  // --- ход «звука» -----------------------------------------------------------------------------------

  void _enter(NarrationState s) {
    _state = s;
    _timer?.cancel();
    if (s == NarrationState.playing) {
      _timer = Timer.periodic(tick, (_) => _advance());
    }
    if (s == NarrationState.stopped || s == NarrationState.paused) _savePosition();
    notifyListeners();
  }

  Duration _duration(Block b) {
    final secs = b.text.length * secondsPerChar / _speed / demoAcceleration;
    return Duration(milliseconds: (math.max(1.6, secs) * 1000).round());
  }

  void _advance() {
    final book = _book;
    final block = _block;
    if (book == null || block == null) return;
    final sleep = _sleep;
    if (sleep != null && sleep.kind == SleepKind.minutes && sleep.remaining(now()) == Duration.zero) {
      _sleep = null;
      _enter(NarrationState.paused);
      return;
    }
    _progress += tick.inMilliseconds / _duration(book.blocks[block]).inMilliseconds;
    if (_progress < 1) {
      notifyListeners();
      return;
    }
    final nextBlock = _spokenFrom(block + 1, forward: true);
    if (nextBlock == null) {
      _progress = 1;
      _stopReason = StopReason.endOfBook;
      _enter(NarrationState.stopped);
      return;
    }
    final chapterEnds = book.chapterOf(nextBlock) != book.chapterOf(block);
    _block = nextBlock;
    _progress = 0;
    _savePosition();
    if (chapterEnds && _sleep?.kind == SleepKind.endOfChapter) {
      _sleep = null;
      _enter(NarrationState.paused);
      return;
    }
    notifyListeners();
  }

  int? _spokenFrom(int from, {required bool forward}) {
    final book = _book;
    if (book == null) return null;
    var i = from;
    while (i >= 0 && i < book.blocks.length) {
      if (book.blocks[i].isSpoken && book.blocks[i].text.trim().isNotEmpty) return i;
      i += forward ? 1 : -1;
    }
    return null;
  }

  int _lastSpoken() => _spokenFrom(_book!.blocks.length - 1, forward: false) ?? 0;

  void _savePosition() {
    final book = _book;
    final block = _block;
    if (book == null || block == null) return;
    library.savePosition(book.id, ReadingPosition(block, 0), fraction: book.fractionAt(block, 0));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prepare?.cancel();
    super.dispose();
  }
}
