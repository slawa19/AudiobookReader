import 'dart:async';

/// Часы и одноразовые таймеры писателя без ожидания реальной секунды.
class LibraryTime {
  DateTime now = DateTime.utc(2026, 11, 15);
  final List<_Alarm> _alarms = [];
  DateTime call() => now;

  Timer timer(Duration duration, void Function() callback) {
    final alarm = _Alarm(now.add(duration), callback);
    _alarms.add(alarm);
    return alarm;
  }

  void advance(Duration duration) {
    now = now.add(duration);
    for (final alarm in _alarms.toList()) {
      if (alarm.isActive && !alarm.at.isAfter(now)) alarm.fire();
    }
  }

  int get activeTimers => _alarms.where((a) => a.isActive).length;
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
    isActive = false;
    tick++;
    callback();
  }
}
