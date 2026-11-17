import 'package:flutter/services.dart';

/// The system request for the notification permission (Android 13+); `true` when notifications are allowed.
class AndroidNotificationPermission {
  static const channel = MethodChannel('audiobook_reader/notification_permission');
  static Future<bool> request() async => await channel.invokeMethod<bool>('request') ?? false;
}
