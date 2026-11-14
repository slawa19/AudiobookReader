import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/prototype/device_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prototype = await Prototype.create();
  if (kIsWeb) {
    // Прототип в браузере: приложение в рамке телефона.
    runApp(DeviceFrame(child: AudiobookApp(prototype: prototype, phoneChrome: true)));
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    runApp(AudiobookApp(prototype: prototype));
  }
}
