import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tts/book_language.dart';

enum SampleState { idle, loading, playing, failed }

/// «Проба» голоса (А§6.8): одна фраза, отдельный короткий плеер, второй раз — без запроса. Постоянная ошибка
/// показывается в строке голоса текстом Google как есть.
abstract class VoiceSampler extends ChangeNotifier {
  /// Голос, чья проба сейчас готовится, играет или упала.
  String? get voice;
  SampleState get state;

  /// Доля проигранного пробы.
  double get progress;

  /// Текст Google при [SampleState.failed].
  String? get errorMessage;

  /// Фраза пробы для языка книги (`tts`, таблица по языку книги).
  String phraseFor(String bookLanguage) => samplePhraseFor(bookLanguage);

  /// Проба голоса [voice] фразой на языке книги [bookLanguage]. Звук кэшируется по голосу и фразе.
  void play(String voice, {required String bookLanguage});
  void stop();

  /// Пробы удалены «Очисткой озвучки» (А§4): следующая проба озвучивается заново. Зовёт только
  /// `NarrationController`.
  void clearCache();
}

/// Подставная проба: первый раз «готовится» чуть меньше секунды, потом «играет» три секунды. Звука нет.
class FakeVoiceSampler extends VoiceSampler {
  FakeVoiceSampler({this.loading = const Duration(milliseconds: 900), this.length = const Duration(seconds: 3)});

  final Duration loading;
  final Duration length;
  final Set<String> _cached = {};
  String? _voice;
  SampleState _state = SampleState.idle;
  double _progress = 0;
  String? _error;
  Timer? _timer;

  /// Только для показа: следующая проба этого голоса упадёт с ошибкой Google.
  String? demoFailVoice;

  @override
  String? get voice => _voice;
  @override
  SampleState get state => _state;
  @override
  double get progress => _progress;
  @override
  String? get errorMessage => _error;

  @override
  void play(String voice, {required String bookLanguage}) {
    _timer?.cancel();
    _voice = voice;
    _progress = 0;
    _error = null;
    final key = '$voice|${phraseFor(bookLanguage)}';
    if (_cached.contains(key)) {
      _playNow();
    } else {
      _state = SampleState.loading;
      _timer = Timer(loading, () {
        if (demoFailVoice == voice) {
          demoFailVoice = null;
          _state = SampleState.failed;
          _error = 'The service is currently unavailable.';
          notifyListeners();
          return;
        }
        _cached.add(key);
        _playNow();
      });
    }
    notifyListeners();
  }

  void _playNow() {
    _state = SampleState.playing;
    const step = Duration(milliseconds: 100);
    _timer = Timer.periodic(step, (_) {
      _progress += step.inMilliseconds / length.inMilliseconds;
      if (_progress >= 1) {
        stop();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void stop() {
    _timer?.cancel();
    _voice = null;
    _state = SampleState.idle;
    _progress = 0;
    _error = null;
    notifyListeners();
  }

  @override
  void clearCache() {
    stop();
    _cached.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
