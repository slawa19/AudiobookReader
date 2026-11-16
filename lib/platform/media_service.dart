import 'package:flutter/services.dart';

/// Подтверждение запуска и явное снятие foreground-службы нашего приложения.
class AndroidMediaService {
  static const channel = MethodChannel('audiobook_reader/media_service');
  static Future<void> awaitForeground() => channel.invokeMethod<void>('awaitForeground');
  static Future<void> stopForeground() => channel.invokeMethod<void>('stopForeground');
}
