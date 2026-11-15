import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';
import '../screens/services.dart';

/// Параметр --fake в scripts/build-apk.sh; Android читает тот же FAKE_TTS для отдельного хранилища.
const useFakeTts = bool.fromEnvironment('FAKE_TTS');

/// Зависимости живут дольше экранов; платформу подключает только корень сборки.
abstract class AppAssembly {
  AppSettings get settings;
  AppServices get services;

  void attach(GlobalKey<NavigatorState> navigator) {}
  void detach() {}
  void setForeground(bool foreground) {}
}
