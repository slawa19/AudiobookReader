import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../audio/audio_store.dart';
import '../book/model.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../tts/book_language.dart';
import '../tts/engine.dart';
import '../tts/voices.dart';
import 'tariffs.dart';

VoiceProfile bookVoiceProfile(Book book, Library library, AppSettings settings) => VoiceProfile(
  voiceId: library.bookVoice(book.id) ?? settings.voice,
  model: settings.modelId,
  style: readingStyleFor(book.language),
);

enum DownloadStatus { running, failed }

/// The "Download chapter" task (A§6.7, FR-D2): one per app. Belongs to the chapter and the voice profile it was
/// started with; changing the voice or model stops it (what is ready is kept).
class ChapterDownloadTask {
  ChapterDownloadTask({
    required this.bookId,
    required this.chapter,
    required this.profile,
    required this.totalSeconds,
    this.readySeconds = 0,
  });

  final String bookId;
  final int chapter;
  final VoiceProfile profile;
  final double totalSeconds;
  double readySeconds;
  DownloadStatus status = DownloadStatus.running;

  /// Google's text as is.
  String? googleMessage;

  /// The reason for a permanent error, including the model and the payment link; the text is in googleMessage.
  TtsError? error;

  double get fraction => totalSeconds == 0 ? 1 : (readySeconds / totalSeconds).clamp(0.0, 1.0);
}

/// Estimate before starting: seconds of audio of the chapter's not-yet-narrated text (the remainder) and the price at
/// today's tariff.
@immutable
class DownloadEstimate {
  const DownloadEstimate(this.seconds, this.dollars);

  final double seconds;
  final double dollars;
}

abstract class ChapterDownloads extends ChangeNotifier {
  ChapterDownloadTask? get task;

  /// The book's effective profile: its own voice or the app voice, the model from settings (FR-V2, A§6.2).
  VoiceProfile profileFor(String bookId);

  /// The chapter is ready for [profile] by the readiness rule of A§6.1: audio in another voice or model does not count.
  bool isVoiced(String bookId, int chapter, VoiceProfile profile);

  /// A ready estimate of the remainder: only what [profile] does not have yet (after "Stop" and after an error — not
  /// the price of the whole chapter). The tariff is today's, by the profile's model. The screen computes nothing
  /// (FR-D2, FR-M1).
  DownloadEstimate estimate(Book book, int chapter, VoiceProfile profile);

  /// Starts the task; the previous one (stopped or failed) is replaced — there is only one task.
  void start(Book book, int chapter, VoiceProfile profile);

  /// "Stop". What is ready is kept.
  void stop();

  /// Audio deleted (A§4): the task of the affected book is stopped, chapter readiness is reset. `null` — all books.
  /// Called only by `NarrationController` as part of a single delete operation.
  void forget({String? bookId});
}

/// The fake implementation: the ready fraction grows on a timer, no network.
class FakeChapterDownloads extends ChapterDownloads {
  FakeChapterDownloads({
    required this.settings,
    required this.tariffs,
    this.bookVoice,
    this.audio,
    this.tick = const Duration(milliseconds: 250),
    this.demoSeconds = 40,
    List<(String, int)>? voicedChapters,
  }) {
    settings.addListener(profileChanged);
    for (final (book, chapter) in voicedChapters ?? const [('dama', 1), ('dama', 2), ('kapitanskaya', 0)]) {
      _voiced.add(_key(book, chapter, VoiceProfile(voiceId: settings.voice, model: settings.modelId)));
    }
  }

  final AppSettings settings;
  final Tariffs tariffs;

  /// The book's own voice (`null` — as in settings); provided by the assembly root from the library.
  final String? Function(String bookId)? bookVoice;

  /// The fake storage: ready audio takes up space, otherwise after "Clear narration" the new narration is visible
  /// neither in "Delete narration" nor in settings.
  final FakeAudioStore? audio;

  /// Bytes of compressed audio per second (≈ 32 kbit/s).
  static const bytesPerSecond = 4000;
  final Duration tick;

  /// In how many seconds the prototype "narrates" the chapter.
  final double demoSeconds;

  ChapterDownloadTask? _task;
  Timer? _timer;
  final Set<String> _voiced = {};

  /// Ready seconds of audio by chapter and profile: what is already in the storage.
  final Map<String, double> _ready = {};

  static String _key(String bookId, int chapter, VoiceProfile profile) => '$bookId#$chapter#${profile.key}';

  @override
  ChapterDownloadTask? get task => _task;

  @override
  VoiceProfile profileFor(String bookId) =>
      VoiceProfile(voiceId: bookVoice?.call(bookId) ?? settings.voice, model: settings.modelId);

  /// The book's voice or model may have changed: the task of the now-foreign profile is stopped, what is ready stays
  /// (rule g, accepted by the owner 2026-11-14; FR-D2).
  void profileChanged() {
    final t = _task;
    if (t != null && t.profile != profileFor(t.bookId)) stop();
  }

  @override
  bool isVoiced(String bookId, int chapter, VoiceProfile profile) => _voiced.contains(_key(bookId, chapter, profile));

  double _chapterSeconds(Book book, int chapter) {
    final ch = book.chapters[chapter];
    var chars = 0;
    for (var i = ch.firstBlock; i < ch.endBlock; i++) {
      if (book.blocks[i].isSpoken) chars += book.blocks[i].text.length;
    }
    return chars * secondsPerChar;
  }

  @override
  DownloadEstimate estimate(Book book, int chapter, VoiceProfile profile) {
    final key = _key(book.id, chapter, profile);
    final seconds = _voiced.contains(key) ? 0.0 : math.max(0.0, _chapterSeconds(book, chapter) - (_ready[key] ?? 0));
    return DownloadEstimate(seconds, seconds / 3600 * tariffs.dollarsPerHour(TtsModel.byId(profile.model)));
  }

  @override
  void start(Book book, int chapter, VoiceProfile profile) {
    _timer?.cancel();
    _task = ChapterDownloadTask(
      bookId: book.id,
      chapter: chapter,
      profile: profile,
      totalSeconds: _chapterSeconds(book, chapter),
      readySeconds: _ready[_key(book.id, chapter, profile)] ?? 0,
    );
    _run();
    notifyListeners();
  }

  void _run() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) {
      final t = _task;
      if (t == null || t.status != DownloadStatus.running) return;
      final key = _key(t.bookId, t.chapter, t.profile);
      final before = t.readySeconds;
      t.readySeconds = math.min(t.totalSeconds, t.readySeconds + t.totalSeconds * tick.inMilliseconds / (demoSeconds * 1000));
      _ready[key] = t.readySeconds;
      audio?.addBook(t.bookId, ((t.readySeconds - before) * bytesPerSecond).round());
      if (t.readySeconds >= t.totalSeconds) {
        _voiced.add(key);
        _task = null;
        _timer?.cancel();
      }
      notifyListeners();
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    if (_task == null) return;
    _task = null;
    notifyListeners();
  }

  @override
  void forget({String? bookId}) {
    if (_task != null && (bookId == null || _task!.bookId == bookId)) {
      _timer?.cancel();
      _task = null;
    }
    _voiced.removeWhere((k) => bookId == null || k.startsWith('$bookId#'));
    _ready.removeWhere((k, _) => bookId == null || k.startsWith('$bookId#'));
    notifyListeners();
  }

  /// For display only: a task at a given fraction or with a permanent error.
  void demoShow(Book book, int chapter, {required bool failed}) {
    final profile = profileFor(book.id);
    start(book, chapter, profile);
    final t = _task!;
    t.readySeconds = t.totalSeconds * 0.4;
    _ready[_key(book.id, chapter, profile)] = t.readySeconds;
    if (failed) {
      _timer?.cancel();
      t.status = DownloadStatus.failed;
      t.googleMessage = 'Request contains an invalid argument.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(profileChanged);
    _timer?.cancel();
    super.dispose();
  }
}
