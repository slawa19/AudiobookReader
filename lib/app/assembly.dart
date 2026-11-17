import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';
import '../screens/services.dart';

/// The --fake parameter in scripts/build-apk.sh; Android reads the same FAKE_TTS for a separate storage.
const useFakeTts = bool.fromEnvironment('FAKE_TTS');

/// Dependencies outlive the screens; only the assembly root wires in the platform.
abstract class AppAssembly {
  AppSettings get settings;
  AppServices get services;

  void attach(GlobalKey<NavigatorState> navigator) {}
  void detach() {}
  void setForeground(bool foreground) {}
}
