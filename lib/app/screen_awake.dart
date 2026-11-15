import 'dart:async';

import '../platform/screen_awake.dart';
import '../playback/screen_awake.dart';

/// Адаптация платформенной функции к порту playback без обратного импорта.
class NativeScreenAwake implements ScreenAwakePort {
  NativeScreenAwake(this.failed);
  final void Function(Object) failed;
  Future<void> _operations = Future.value();
  @override
  void setEnabled(bool enabled) {
    _operations = _operations.then((_) => AndroidScreenAwake.setEnabled(enabled)).catchError((Object error) {
      failed(error);
    });
  }

  Future<void> flush() => _operations;
}
