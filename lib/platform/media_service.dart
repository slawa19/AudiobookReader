import 'package:flutter/services.dart';

/// Confirms the start and explicitly clears the foreground service of our app.
class AndroidMediaService {
  static const channel = MethodChannel('audiobook_reader/media_service');
  static Future<void> awaitForeground() => channel.invokeMethod<void>('awaitForeground');
  static Future<void> stopForeground() => channel.invokeMethod<void>('stopForeground');
}
