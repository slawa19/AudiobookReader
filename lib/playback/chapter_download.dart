import 'dart:async';

import 'package:flutter/foundation.dart';

import '../book/model.dart';
import '../tts/voices.dart';

enum DownloadStatus { running, failed }

/// Задача «Скачать главу» (А§6.7, FR-D2): одна на приложение, только текущая глава.
class ChapterDownloadTask {
  ChapterDownloadTask({required this.bookId, required this.chapter, required this.totalSeconds});

  final String bookId;
  final int chapter;
  final double totalSeconds;
  double readySeconds = 0;
  DownloadStatus status = DownloadStatus.running;
  String? googleMessage;

  double get fraction => totalSeconds == 0 ? 1 : (readySeconds / totalSeconds).clamp(0.0, 1.0);
}

/// Оценка перед началом: секунды звука неозвученного текста главы и цена по тарифу на сегодня.
@immutable
class DownloadEstimate {
  const DownloadEstimate(this.seconds, this.dollars);

  final double seconds;
  final double dollars;
}

abstract class ChapterDownloads extends ChangeNotifier {
  ChapterDownloadTask? get task;

  bool isVoiced(String bookId, int chapter);

  DownloadEstimate estimate(Book book, int chapter, TtsModel model, DateTime today);

  void start(Book book, int chapter, TtsModel model);

  /// «Стоп» / «Остановить».
  void stop();
}

/// Подставная реализация: доля готового растёт по таймеру, сети нет.
class FakeChapterDownloads extends ChapterDownloads {
  FakeChapterDownloads({this.tick = const Duration(milliseconds: 250), this.demoSeconds = 40});

  final Duration tick;

  /// За сколько секунд прототип «озвучивает» главу.
  final double demoSeconds;

  ChapterDownloadTask? _task;
  Timer? _timer;
  final Set<String> _voiced = {'dama#1', 'dama#2', 'kapitanskaya#0'};

  @override
  ChapterDownloadTask? get task => _task;

  @override
  bool isVoiced(String bookId, int chapter) => _voiced.contains('$bookId#$chapter');

  @override
  DownloadEstimate estimate(Book book, int chapter, TtsModel model, DateTime today) {
    final ch = book.chapters[chapter];
    var chars = 0;
    for (var i = ch.firstBlock; i < ch.endBlock; i++) {
      if (book.blocks[i].isSpoken) chars += book.blocks[i].text.length;
    }
    final seconds = chars * secondsPerChar;
    return DownloadEstimate(seconds, seconds / 3600 * model.dollarsPerHourAt(today));
  }

  @override
  void start(Book book, int chapter, TtsModel model) {
    _timer?.cancel();
    final est = estimate(book, chapter, model, DateTime(2026, 11, 14));
    _task = ChapterDownloadTask(bookId: book.id, chapter: chapter, totalSeconds: est.seconds);
    _run();
    notifyListeners();
  }

  void _run() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) {
      final t = _task;
      if (t == null || t.status != DownloadStatus.running) return;
      t.readySeconds += t.totalSeconds * tick.inMilliseconds / (demoSeconds * 1000);
      if (t.readySeconds >= t.totalSeconds) {
        _voiced.add('${t.bookId}#${t.chapter}');
        _task = null;
        _timer?.cancel();
      }
      notifyListeners();
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _task = null;
    notifyListeners();
  }

  /// Только для показа: задача на заданной доле или с постоянной ошибкой.
  void demoShow(Book book, int chapter, {required bool failed}) {
    start(book, chapter, TtsModel.flash);
    final t = _task!;
    t.readySeconds = t.totalSeconds * 0.4;
    if (failed) {
      _timer?.cancel();
      t.status = DownloadStatus.failed;
      t.googleMessage = 'API key not valid. Please pass a valid API key.';
    }
    notifyListeners();
  }

  /// Ошибка показывается в блоке главы в оглавлении; «Скачать главу» оттуда начинает заново.
  void dismissFailure() {
    if (_task?.status == DownloadStatus.failed) {
      _task = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
