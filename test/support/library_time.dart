import 'dart:async';
import 'dart:io';

import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/library.dart';

/// Только тестовые образцы создаются из байтов; рабочий интерфейс получает путь.
extension TestFileLibrary on FileLibrary {
  Future<ShelfEntry?> addTestBytes(List<int> bytes, String name) async {
    final temp = await Directory.systemTemp.createTemp('test-source-');
    try {
      final file = await File('${temp.path}/source').writeAsBytes(bytes);
      return await addFile(file.path, name);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}

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
