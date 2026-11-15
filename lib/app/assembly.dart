import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';
import '../screens/services.dart';

/// Зависимости живут дольше экранов; платформу подключает только корень сборки.
abstract class AppAssembly {
  AppSettings get settings;
  AppServices get services;

  void attach(GlobalKey<NavigatorState> navigator) {}
  void detach() {}
}
