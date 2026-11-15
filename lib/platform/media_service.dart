import 'package:flutter/services.dart';

/// Канал возвращает только факт foreground-службы нашего приложения.
class AndroidMediaService {
  static const channel = MethodChannel('audiobook_reader/media_service');
  static Future<void> awaitForeground() => channel.invokeMethod<void>('awaitForeground');
}
