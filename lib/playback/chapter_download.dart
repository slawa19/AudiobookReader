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

/// Задача «Скачать главу» (А§6.7, FR-D2): одна на приложение. Принадлежит главе и профилю голоса, с которыми её
/// начали; смена голоса или модели её останавливает (готовое сохраняется).
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

  /// Текст Google как есть.
  String? googleMessage;

  /// Причина постоянной ошибки, включая модель и ссылку на оплату; текст — в googleMessage.
  TtsError? error;

  double get fraction => totalSeconds == 0 ? 1 : (readySeconds / totalSeconds).clamp(0.0, 1.0);
}

/// Оценка перед началом: секунды звука ещё не озвученного текста главы (остатка) и цена по тарифу на сегодня.
@immutable
class DownloadEstimate {
  const DownloadEstimate(this.seconds, this.dollars);

  final double seconds;
  final double dollars;
}

abstract class ChapterDownloads extends ChangeNotifier {
  ChapterDownloadTask? get task;

  /// Действующий профиль книги: её свой голос или голос приложения, модель из настроек (FR-V2, А§6.2).
  VoiceProfile profileFor(String bookId);

  /// Глава готова для [profile] по правилу готовности А§6.1: звук другим голосом или моделью не в счёт.
  bool isVoiced(String bookId, int chapter, VoiceProfile profile);

  /// Готовая оценка остатка: только то, чего для [profile] ещё нет (после «Остановить» и после ошибки — не цена
  /// всей главы). Тариф — на сегодня по модели профиля. Экран ничего не считает (FR-D2, FR-M1).
  DownloadEstimate estimate(Book book, int chapter, VoiceProfile profile);

  /// Начинает задачу; прежняя (остановленная или с ошибкой) заменяется — задача одна.
  void start(Book book, int chapter, VoiceProfile profile);

  /// «Стоп» / «Остановить». Готовое сохраняется.
  void stop();

  /// Звук удалён (А§4): задача затронутой книги остановлена, готовность глав сброшена. `null` — все книги.
  /// Зовёт только `NarrationController` как часть одной операции удаления.
  void forget({String? bookId});
}

/// Подставная реализация: доля готового растёт по таймеру, сети нет.
class FakeChapterDownloads extends ChapterDownloads {
  FakeChapterDownloads({
    required this.settings,
    required this.tariffs,
    this.bookVoice,
    this.audio,
    this.tick = const Duration(milliseconds: 250),
    this.demoSeconds = 40,
  }) {
    settings.addListener(profileChanged);
    for (final (book, chapter) in const [('dama', 1), ('dama', 2), ('kapitanskaya', 0)]) {
      _voiced.add(_key(book, chapter, VoiceProfile(voiceId: settings.voice, model: settings.modelId)));
    }
  }

  final AppSettings settings;
  final Tariffs tariffs;

  /// Свой голос книги (`null` — как в настройках); даёт корень сборки из библиотеки.
  final String? Function(String bookId)? bookVoice;

  /// Подставное хранилище: готовый звук занимает место, иначе после «Очистить озвучку» новая озвучка не видна
  /// ни в «Удалить озвучку», ни в настройках (№9 ревью логики).
  final FakeAudioStore? audio;

  /// Байт сжатого звука на секунду (≈ 32 кбит/с).
  static const bytesPerSecond = 4000;
  final Duration tick;

  /// За сколько секунд прототип «озвучивает» главу.
  final double demoSeconds;

  ChapterDownloadTask? _task;
  Timer? _timer;
  final Set<String> _voiced = {};

  /// Готовые секунды звука по главе и профилю: то, что уже лежит в хранилище.
  final Map<String, double> _ready = {};

  static String _key(String bookId, int chapter, VoiceProfile profile) => '$bookId#$chapter#${profile.key}';

  @override
  ChapterDownloadTask? get task => _task;

  @override
  VoiceProfile profileFor(String bookId) =>
      VoiceProfile(voiceId: bookVoice?.call(bookId) ?? settings.voice, model: settings.modelId);

  /// Голос книги или модель могли смениться: задача чужого теперь профиля останавливается, готовое остаётся
  /// (правило g, принято владельцем 2026-11-14; FR-D2).
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

  /// Только для показа: задача на заданной доле или с постоянной ошибкой.
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
