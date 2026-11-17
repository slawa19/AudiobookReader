import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/native_application.dart';
import 'app/prototype/device_frame.dart';
import 'screens/licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLicenses();
  if (kIsWeb) {
    final prototype = await Prototype.create();
    // Prototype in the browser: the app inside a phone frame.
    runApp(
      DeviceFrame(
        settings: prototype.settings,
        child: AudiobookApp(prototype: prototype, phoneChrome: true),
      ),
    );
  } else {
    try {
      final application = await NativeApplication.create();
      await application.connectMedia();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      runApp(AudiobookApp.application(assembly: application));
    } catch (error) {
      // A storage error stays visible even without ready settings and shelf.
      runApp(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Text(error.toString())),
            ),
          ),
        ),
      );
    }
  }
}
