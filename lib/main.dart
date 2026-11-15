import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/native_application.dart';
import 'app/prototype/device_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    final prototype = await Prototype.create();
    // Прототип в браузере: приложение в рамке телефона.
    runApp(
      DeviceFrame(
        settings: prototype.settings,
        child: AudiobookApp(prototype: prototype, phoneChrome: true),
      ),
    );
  } else {
    final application = await NativeApplication.create();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    runApp(AudiobookApp.application(assembly: application));
  }
}
