import 'dart:async';

import '../library/settings.dart';
import 'narration.dart';

/// Asks the system for the notification permission once, when listening starts for the first time (A§7).
///
/// The media card in the shade and on the lock screen is exempt from the permission and is shown without it; what the
/// permission changes is the app's notification switch in the system settings: without the declared and requested
/// permission Android shows the app's notifications as blocked and does not let the user turn them on. Playback does
/// not wait for the answer, a refusal changes nothing in listening, and the app does not ask again.
class NotificationPrompt {
  NotificationPrompt({required this.controller, required this.settings, required this.request, required this.failed}) {
    controller.addListener(_check);
    _check();
  }

  final NarrationController controller;
  final AppSettings settings;

  /// Shows the system dialog; the answer is whether notifications are allowed. The prompt does not need it.
  final Future<bool> Function() request;
  final void Function(Object error) failed;

  void _check() {
    if (!controller.isActive || settings.notificationsAsked) return;
    settings.notificationsAsked = true;
    unawaited(
      request().then<void>((_) {}, onError: (Object error) => failed(error)),
    );
  }

  void dispose() => controller.removeListener(_check);
}
