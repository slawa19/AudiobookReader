import 'package:flutter/services.dart';

class AndroidScreenAwake {
  static const channel = MethodChannel('audiobook_reader/screen_awake');
  static Future<void> setEnabled(bool enabled) => channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
}
