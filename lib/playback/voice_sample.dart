import 'dart:async';

import 'package:flutter/foundation.dart';

enum SampleState { idle, loading, playing }

/// «Проба» голоса (А§6.8): одна фраза, отдельный короткий плеер, второй раз — без запроса.
abstract class VoiceSampler extends ChangeNotifier {
  String? get voice;
  SampleState get state;

  /// Доля проигранного пробы.
  double get progress;

  void play(String voice);
  void stop();
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
  Timer? _timer;

  @override
  String? get voice => _voice;
  @override
  SampleState get state => _state;
  @override
  double get progress => _progress;

  @override
  void play(String voice) {
    _timer?.cancel();
    _voice = voice;
    _progress = 0;
    if (_cached.contains(voice)) {
      _playNow();
    } else {
      _state = SampleState.loading;
      _timer = Timer(loading, () {
        _cached.add(voice);
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
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
