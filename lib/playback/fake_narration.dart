import 'dart:async';
import 'dart:math' as math;

import '../audio/audio_store.dart';
import '../book/model.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../tts/sentences.dart';
import '../tts/voices.dart';
import 'chapter_download.dart';
import 'narration.dart';
import 'voice_sample.dart';

/// Подставная озвучка прототипа: звука нет, таймер двигает «звучащий» блок по книге.
///
/// Единица — блок, а не отрезок А§6.1: деления длинных абзацев и склейки коротких реплик в прототипе нет. Старт
/// с предложения внутри блока — доля пройденного блока; в настоящем приложении это стартовый отрезок А§6.1.
/// Длительность блока — знаки × 0,069 с ÷ скорость ÷ [demoAcceleration], чтобы следование за голосом было видно
/// за минуту, а не за десять.
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

  /// Скорость — настройка (FR-P5): сеанс звучит с той, что сохранена, а не с 1×.
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

  /// Номер сеанса (А§6.4): ответ прежнего сеанса не трогает новый.
  int _session = 0;

  /// Смещение начала звучащей единицы в блоке: 0 или начало предложения, с которого начат блок.
  int _unitStart = 0;

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
  ReadingPosition? get unitStart => _block == null ? null : ReadingPosition(_block!, _unitStart);
  @override
  double get speed => settings?.speed ?? _speed;
  @override
  SleepTimer? get sleepTimer => _sleep;
  @override
  DateTime now() => _clock();

  Book? get book => _book;

  // --- команды контракта ---------------------------------------------------------------------------------

  int _commands = 0;

  @override
  int get commandRevision => _commands;

  /// Явная команда пользователя (А§5, А§6.6): счётчик для экрана, и истёкший таймер сна не наследуется новым
  /// стартом (FR-D1, №7 ревью логики).
  void _userCommand() {
    _commands++;
    _dropExpiredSleep();
  }

  @override
  void listen(Book book, PageRange page) {
    _userCommand();
    _enterBook(book);
    final saved = library.listeningPositionOf(book.id);
    // 1. Место прослушивания на этой странице — продолжаем с него.
    if (saved != null && page.contains(saved)) {
      _startAt(book, saved);
      return;
    }
    // 2. Первое предложение, которое начинается на странице. Границы — по тексту для речи (без знаков сносок).
    for (var b = page.start.block; b <= page.end.block && b < book.blocks.length; b++) {
      final block = book.blocks[b];
      if (!block.isSpoken || block.text.trim().isEmpty) continue;
      final from = b == page.start.block ? page.start.offset : 0;
      final to = b == page.end.block ? page.end.offset : block.text.length;
      for (final s in blockSentenceStarts(block)) {
        if (s >= from && s < to) {
          _startAt(book, ReadingPosition(b, s));
          return;
        }
      }
    }
    // 3. Страница целиком внутри одного предложения — с его начала (только тогда страница уходит туда, где оно
    // начинается).
    final first = book.blocks[page.start.block];
    if (first.isSpoken) {
      _startAt(book, ReadingPosition(page.start.block, blockSentenceStartAt(first, page.start.offset)));
    } else {
      _startAt(book, ReadingPosition(page.start.block, 0));
    }
  }

  /// Сеанс переходит к книге [book]; другая книга — таймер сна снимается (правило c).
  void _enterBook(Book book) {
    if (_book != null && _book!.id != book.id) _sleep = null;
    _book = book;
  }

  /// Новый сеанс с места [p]: с блока и смещения внутри него (стартовый отрезок от предложения, А§6.1).
  void _startAt(Book book, ReadingPosition p) {
    _enterBook(book);
    final block = _spokenFrom(p.block, forward: true) ?? p.block;
    _newSession(block, block == p.block ? p.offset : 0);
  }

  @override
  void resume() {
    final book = _book;
    if (book == null) return;
    // Срок таймера истёк, пока звука не было: ему нечего останавливать — снят, «Слушать» звучит (правило c).
    _userCommand();
    if (_state == NarrationState.stopped) {
      // Новый сеанс с актуальной сохранённой позиции: после остановки её мог переписать экран (А§5).
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
      // «Читать отсюда» — с начала выбранного абзаца (FR-P3, D).
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
    final target = forward ? _spokenFrom(_block! + 1, forward: true) : _spokenFrom(_block! - 1, forward: false);
    if (target == null) return;
    _userCommand();
    _moveKeepingIntent(target);
  }

  /// Смена места внутри сеанса: новый сеанс, намерение прежнее (А§6.6). Пауза остаётся паузой. [offset] — начало
  /// единицы внутри блока (стартовый отрезок с предложения).
  void _moveKeepingIntent(int block, {int offset = 0}) {
    final target = _spokenFrom(block, forward: true) ?? block;
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
      // В прототипе звук «соседнего» отрезка всегда готов: сразу playing (А§6.6: или preparing, если звука нет).
      _enter(NarrationState.playing);
    }
  }

  @override
  void close({ReadingPosition? screenPosition}) {
    final book = _book;
    _endSession();
    // Сначала сеанс завершён — потом позиция экрана уходит писателю. Позднее ни одна запись контроллера её не
    // перепишет: номер сеанса уже сменился (А§5).
    if (book != null && screenPosition != null) {
      library.savePosition(book.id, screenPosition, fraction: book.fractionAt(screenPosition.block, screenPosition.offset));
    }
    notifyListeners();
  }

  void _endSession() {
    _session++;
    _timer?.cancel();
    _prepare?.cancel();
    // Таймер сна принадлежит прослушиванию: «Закрыть» и закрытие книги его снимают (правило c).
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
    // С начала текущей единицы, включая стартовую с предложения внутри блока (№2 ревью логики).
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

  // --- только для показа: состояния, которые в жизни вызывает сеть -----------------------------------------

  /// Включает состояние для панели «Состояния для показа». Если прослушивания нет, начинает его с [fromBlock].
  void demoShow(String what, {Book? book, int fromBlock = 0}) {
    if (_book == null || _state == NarrationState.idle) {
      if (book == null) return;
      _book = book;
      _block = _spokenFrom(fromBlock, forward: true) ?? fromBlock;
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
        // Модель, на которой случилась ошибка, — в самой ошибке: выбор другой модели потом её не переименует.
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

  // --- ход «звука» -----------------------------------------------------------------------------------

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
      // Звука нет, но срок таймера сна может истечь и сейчас (правило c).
      final session = _session;
      _timer = Timer.periodic(tick, (_) {
        if (session == _session) _expireSleep();
      });
    }
    if (s == NarrationState.stopped || s == NarrationState.paused) _savePosition();
    notifyListeners();
  }

  /// Перед явным стартом: истёкший срок таймера просто снимается — новому старту он ничего не останавливает.
  void _dropExpiredSleep() {
    final sleep = _sleep;
    if (sleep != null && sleep.kind == SleepKind.minutes && sleep.remaining(now()) == Duration.zero) _sleep = null;
  }

  /// Срок таймера сна по минутам истёк: во время звука и в `preparing`/`waiting` — пауза; на паузе таймер просто
  /// снимается. В любом случае таймер снят и больше ничего не останавливает (правило c, FR-D1).
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
    // Скорость — одна: та же, что показывает панель (№8 ревью логики).
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
    final nextBlock = _spokenFrom(block + 1, forward: true);
    if (nextBlock == null) {
      _progress = 1;
      _stopReason = StopReason.endOfBook;
      // Кончилась и последняя глава: таймер «до конца главы» сработал и снимается (№7 ревью логики).
      if (_sleep?.kind == SleepKind.endOfChapter) _sleep = null;
      _enter(NarrationState.stopped);
      // Прослушивание дошло до конца книги — книга дочитана (FR-L4, правило d).
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

  /// Пока сеанс активен, позицию чтения пишет контроллер: звучащее место (А§5). Место прослушивания — начало
  /// звучащей единицы — пишется всегда и не стирается ни паузой, ни остановкой, ни «Закрыть» (А§4).
  void _savePosition() {
    final book = _book;
    final block = _block;
    if (book == null || block == null) return;
    final len = book.blocks[block].text.length;
    final offset = math.min((_progress * len).floor(), math.max(0, len - 1));
    // Название главы для полки библиотека считает сама по позиции: смена главы оглавлением не оставит на полке
    // прежнюю (находка №2 проверки путей).
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
