import 'package:material_ui/material_ui.dart';

import '../audio/audio_store.dart';
import '../library/fake_library.dart';
import '../library/settings.dart';
import '../playback/chapter_download.dart';
import '../playback/fake_narration.dart';
import '../playback/voice_sample.dart';
import '../screens/services.dart';
import '../tts/voices.dart';
import '../screens/shelf_screen.dart';
import 'prototype/add_book.dart';
import 'prototype/demo_states.dart';
import 'prototype/phone_chrome.dart';
import 'theme.dart';

/// Прототип целиком: все реализации подставные (А§2 — за интерфейсами модулей), сети нет.
class Prototype {
  Prototype._({
    required this.library,
    required this.settings,
    required this.narration,
    required this.downloads,
    required this.sampler,
    required this.audio,
  });

  final FakeLibrary library;
  final AppSettings settings;
  final FakeNarrationController narration;
  final FakeChapterDownloads downloads;
  final FakeVoiceSampler sampler;
  final FakeAudioStore audio;
  late final AppServices services;

  static Future<Prototype> create({DateTime Function()? clock, double demoAcceleration = 4}) async {
    final library = FakeLibrary();
    await library.preload();
    final p = Prototype._(
      library: library,
      settings: AppSettings(voice: defaultVoiceName, modelId: TtsModel.flash.id, apiKey: 'AIzaSyD-prototype-key-a1f3'),
      narration: FakeNarrationController(library: library, clock: clock, demoAcceleration: demoAcceleration),
      downloads: FakeChapterDownloads(),
      sampler: FakeVoiceSampler(),
      audio: FakeAudioStore({
        'kapitanskaya': 96 * 1024 * 1024,
        'dama': 274 * 1024 * 1024,
        'voyna': 38 * 1024 * 1024,
      }),
    );
    p.services = AppServices(
      library: library,
      settings: p.settings,
      narration: p.narration,
      downloads: p.downloads,
      sampler: p.sampler,
      audio: p.audio,
      addBook: (context) => showDemoFilePicker(context, p),
      openUrl: (context, url) => ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('В прототипе ссылки не открываются: $url'))),
      clearNarration: () {
        p.narration.close();
        p.audio.clearAll();
      },
      deleteNarration: (id) {
        if (p.narration.bookId == id) p.narration.close();
        p.audio.removeBook(id);
      },
      spentByMonth: () => [
        (month: DateTime(2026, 11), dollars: 4.12),
        (month: DateTime(2026, 10), dollars: 7.80),
      ],
      themePreviews: {
        for (final c in ThemeChoice.values)
          c: (
            bg: paletteFor(c, Brightness.light).bg,
            ink: paletteFor(c, Brightness.light).ink,
            line: paletteFor(c, Brightness.light).line,
          ),
      },
      // Только прототип. В настоящем приложении этого входа нет.
      openDemoStates: (context) => showDemoStates(context, p),
    );
    return p;
  }
}

class AudiobookApp extends StatelessWidget {
  const AudiobookApp({super.key, required this.prototype, this.phoneChrome = false});

  final Prototype prototype;

  /// Рисовать строку состояния и полоску жестов (браузер и снимки экранов; на телефоне их рисует Android).
  final bool phoneChrome;

  @override
  Widget build(BuildContext context) {
    final settings = prototype.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final choice = settings.theme;
        final light = buildTheme(choice == ThemeChoice.sepia ? sepiaPalette : lightPalette);
        final dark = buildTheme(darkPalette);
        final mode = switch (choice) {
          ThemeChoice.system => ThemeMode.system,
          ThemeChoice.light || ThemeChoice.sepia => ThemeMode.light,
          ThemeChoice.dark => ThemeMode.dark,
        };
        return MaterialApp(
          title: 'Читалка',
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          builder: phoneChrome ? (context, child) => PhoneChrome(child: child!) : null,
          home: ShelfScreen(services: prototype.services),
        );
      },
    );
  }
}
