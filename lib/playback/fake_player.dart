import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'clock.dart';
import 'player.dart';

/// Подставной плеер WAV. Никакого синтеза длительности по тексту: время берётся из файла.
class FakePlayer implements PlayerPort {
  FakePlayer({required this.clock});
  final PlaybackClock clock;
  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  final items = <PlayerItem>[];
  int _generation = 0, _index = 0;
  Duration _position = Duration.zero;
  DateTime? _since;
  Timer? _timer;
  bool _playing = false, _started = false;
  double _speed = 1;
  @override
  Stream<PlayerEvent> get events => _events.stream;
  @override
  PlayerItem? get current => _index < items.length ? items[_index] : null;
  @override
  Duration get position =>
      _position +
      (_since == null
          ? Duration.zero
          : Duration(
              microseconds:
                  (clock.now().difference(_since!).inMicroseconds * _speed)
                      .round(),
            ));
  @override
  bool get playing => _playing;
  @override
  double get speed => _speed;

  @override
  Future<Duration> duration(File file) async {
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes);
    int? rate, length;
    for (var i = 12; i + 8 <= bytes.length;) {
      final tag = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size = data.getUint32(i + 4, Endian.little);
      if (tag == 'fmt ') rate = data.getUint32(i + 16, Endian.little);
      if (tag == 'data') length = size;
      i += 8 + size + size % 2;
    }
    if (rate == null || rate <= 0 || length == null) {
      throw const FormatException('Не WAV');
    }
    return Duration(microseconds: (length * 1000000 / rate).round());
  }

  @override
  void append(PlayerItem item) => items.add(item);
  void _emit(PlayerEventKind kind) =>
      _events.add(PlayerEvent(kind, _generation, item: current));
  @override
  void play() {
    if (_playing || current == null) return;
    _playing = true;
    _since = clock.now();
    if (!_started) {
      _started = true;
      _emit(PlayerEventKind.started);
    }
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (!_playing || current == null) return;
    final left = current!.duration - position;
    final us = math.max(
      1,
      math.min(100000, (left.inMicroseconds / _speed).ceil()),
    );
    _timer = clock.schedule(Duration(microseconds: us), _tick);
  }

  void _tick() {
    if (!_playing) return;
    _capture();
    if (_position >= current!.duration) {
      _index++;
      _position = Duration.zero;
      _started = false;
      if (current == null) {
        _playing = false;
        _since = null;
        _emit(PlayerEventKind.drained);
        return;
      }
      _started = true;
      _emit(PlayerEventKind.started);
    } else {
      _emit(PlayerEventKind.progress);
    }
    _arm();
  }

  void _capture() {
    _position = position;
    _since = _playing ? clock.now() : null;
  }

  @override
  void pause() {
    _capture();
    _playing = false;
    _since = null;
    _timer?.cancel();
  }

  void interrupt() {
    pause();
    _emit(PlayerEventKind.interrupted);
  }

  /// Ошибка декодирования текущего файла, управляемая тестом.
  void failCurrent() {
    if (current == null) return;
    pause();
    _emit(PlayerEventKind.failed);
  }

  @override
  void setSpeed(double value) {
    if (!value.isFinite || value <= 0) throw ArgumentError.value(value);
    _capture();
    _speed = value;
    _arm();
  }

  @override
  void clear(int generation) {
    pause();
    _generation = generation;
    items.clear();
    _index = 0;
    _position = Duration.zero;
    _started = false;
  }

  @override
  void retainThrough(int segment) {
    final first = items.indexWhere((i) => i.segment > segment);
    if (first >= 0) {
      final from = math.max(first, _index + 1);
      if (from < items.length) items.removeRange(from, items.length);
    }
  }

  Future<void> dispose() async {
    pause();
    await _events.close();
  }
}
