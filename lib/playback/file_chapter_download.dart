import '../book/model.dart';
import '../tts/book_language.dart';
import '../tts/engine.dart';
import '../tts/segments.dart';
import '../tts/voices.dart';
import 'chapter_download.dart';
import 'screen_awake.dart';
import 'synthesis_queue.dart';
import 'tariffs.dart';

/// Один потребитель общей очереди, независимый от сеанса прослушивания.
/// Корень сборки даёт модели открытых книг: синхронный контракт экранов не делает I/O.
/// Готовность каждый раз читается из AudioStore, собственного реестра «озвучена» нет.
class FileChapterDownloads extends ChapterDownloads {
  FileChapterDownloads({
    required this.queue,
    required this.tariffs,
    required this.bookFor,
    required this.screenAwake,
  }) {
    queue.settings.addListener(profileChanged);
    queue.library.addListener(profileChanged);
    queue.audio.addListener(_refresh);
  }

  final SynthesisQueue queue;
  final Tariffs tariffs;
  final Book Function(String bookId) bookFor;
  final ScreenAwakePort screenAwake;
  ChapterDownloadTask? _task;
  Book? _book;
  SynthesisTask? _consumer;
  bool _foreground = true, _awake = false;

  @override
  ChapterDownloadTask? get task => _task;

  @override
  VoiceProfile profileFor(String bookId) => VoiceProfile(
    voiceId: queue.library.bookVoice(bookId) ?? queue.settings.voice,
    model: queue.settings.modelId,
    style: readingStyleFor(bookFor(bookId).language),
  );

  List<SpeechSegment> _segments(Book book, int chapter) {
    final ch = book.chapters[chapter];
    return chapterSegments(book.blocks.sublist(ch.firstBlock, ch.endBlock));
  }

  SegmentReadiness _readiness(
    SpeechSegment segment,
    String bookId,
    VoiceProfile profile, {
    bool pending = false,
  }) => segmentReadiness(
    segment,
    profile,
    queue.audio.formatId,
    (key) =>
        queue.audio.has(key, bookId: bookId) ||
        (pending && queue.isPending(key, bookId: bookId)),
  );

  @override
  bool isVoiced(String bookId, int chapter, VoiceProfile profile) => _segments(
    bookFor(bookId),
    chapter,
  ).every((s) => _readiness(s, bookId, profile).ready);

  List<SynthesisUnit> _missing(Book book, int chapter, VoiceProfile profile) {
    final unique = <String, SynthesisUnit>{};
    for (final segment in _segments(book, chapter)) {
      // Идущие части определяют схему готовности, но пока ещё входят в цену остатка.
      for (final unit in _readiness(
        segment,
        book.id,
        profile,
        pending: true,
      ).units) {
        if (!queue.audio.has(unit.fingerprint, bookId: book.id)) {
          unique.putIfAbsent(unit.fingerprint, () => unit);
        }
      }
    }
    return unique.values.toList();
  }

  @override
  DownloadEstimate estimate(Book book, int chapter, VoiceProfile profile) {
    final chars = _missing(
      book,
      chapter,
      profile,
    ).fold(0, (sum, unit) => sum + unit.text.length);
    final seconds = chars * secondsPerChar;
    return DownloadEstimate(
      seconds,
      seconds / 3600 * tariffs.dollarsPerHour(TtsModel.byId(profile.model)),
    );
  }

  @override
  void start(Book book, int chapter, VoiceProfile profile) {
    _detach();
    _book = book;
    _task = ChapterDownloadTask(
      bookId: book.id,
      chapter: chapter,
      profile: profile,
      totalSeconds:
          _segments(book, chapter).fold(0, (sum, s) => sum + s.text.length) *
          secondsPerChar,
    );
    _refresh();
  }

  void _setAwake(bool value) {
    if (_awake == value) return;
    _awake = value;
    screenAwake.setEnabled(value);
  }

  void _detach() {
    _consumer?.dispose();
    _consumer = null;
    _setAwake(false);
  }

  void _refresh() {
    final t = _task;
    final book = _book;
    if (t == null || book == null) {
      notifyListeners();
      return;
    }
    var readyChars = 0;
    var complete = true;
    for (final segment in _segments(book, t.chapter)) {
      final ready = _readiness(segment, book.id, t.profile);
      complete = complete && ready.ready;
      for (final unit in ready.units) {
        if (queue.audio.has(unit.fingerprint, bookId: book.id)) {
          readyChars += unit.text.length;
        }
      }
    }
    t.readySeconds = readyChars * secondsPerChar;
    if (t.status == DownloadStatus.running) {
      if (complete) {
        stop();
        return;
      }
      if (_foreground) {
        _consumer ??= queue.task(
          session: 0,
          changed: _refresh,
          failed: _failed,
        );
        _consumer!.update([
          for (final unit in _missing(book, t.chapter, t.profile))
            queue.request(unit.text, t.profile, bookId: book.id),
        ], active: true);
        _setAwake(true);
      }
    }
    notifyListeners();
  }

  void _failed(TtsError error) {
    final t = _task;
    if (t == null) return;
    t.status = DownloadStatus.failed;
    t.error = error;
    t.googleMessage = error.message;
    _detach();
    notifyListeners();
  }

  /// Корень сборки сообщает уход с экрана и возврат. Поздние ответы сохраняются,
  /// но новых запросов и повторов в фоне нет. Намерение продолжить живёт до stop.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      // Сохраняем интерес к постоянной ошибке уже начатого запроса, но не к повторам.
      final t = _task;
      final book = _book;
      if (t != null && book != null) {
        _consumer?.update([
          for (final unit in _missing(book, t.chapter, t.profile))
            queue.request(unit.text, t.profile, bookId: book.id),
        ], active: false);
      }
      _setAwake(false);
    }
    _refresh();
  }

  /// Тот же сигнал, что у подставной реализации; подписки покрывают настройки и голос книги.
  void profileChanged() {
    final t = _task;
    if (t != null && t.profile != profileFor(t.bookId)) {
      stop();
    } else {
      notifyListeners();
    }
  }

  @override
  void stop() {
    _detach();
    _task = null;
    _book = null;
    notifyListeners();
  }

  @override
  void forget({String? bookId}) {
    if (bookId == null || _task?.bookId == bookId) stop();
  }

  @override
  void dispose() {
    queue.settings.removeListener(profileChanged);
    queue.library.removeListener(profileChanged);
    queue.audio.removeListener(_refresh);
    _detach();
    super.dispose();
  }
}
