import 'dart:async';

/// One clock for the sleep timer, queue delays and fake audio.
abstract interface class PlaybackClock {
  DateTime now();
  Timer schedule(Duration delay, void Function() callback);
}

class SystemPlaybackClock implements PlaybackClock {
  const SystemPlaybackClock();
  @override
  DateTime now() => DateTime.now();
  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

/// Advances time through the deadlines, including timers created inside handlers.
class ManualPlaybackClock implements PlaybackClock {
  ManualPlaybackClock([DateTime? start])
    : _now = start ?? DateTime(2026, 11, 15);
  DateTime _now;
  final _alarms = <_Alarm>[];
  @override
  DateTime now() => _now;
  @override
  Timer schedule(Duration delay, void Function() callback) {
    final alarm = _Alarm(_now.add(delay), callback);
    _alarms.add(alarm);
    return alarm;
  }

  void advance(Duration duration) {
    if (duration.isNegative) throw ArgumentError.value(duration);
    final end = _now.add(duration);
    while (true) {
      _alarms.removeWhere((a) => !a.isActive);
      _alarms.sort((a, b) => a.at.compareTo(b.at));
      if (_alarms.isEmpty || _alarms.first.at.isAfter(end)) break;
      final alarm = _alarms.removeAt(0);
      _now = alarm.at;
      alarm.fire();
    }
    _now = end;
  }
}

class _Alarm implements Timer {
  _Alarm(this.at, this.callback);
  final DateTime at;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}
