import 'package:material_ui/material_ui.dart';

import '../audio/audio_store.dart';
import '../library/fake_library.dart';
import '../library/settings.dart';
import '../playback/chapter_download.dart';
import '../playback/fake_narration.dart';
import '../playback/tariffs.dart';
import '../playback/voice_sample.dart';
import '../screens/common.dart';
import '../screens/l10n/app_localizations.dart';
import '../screens/services.dart';
import '../screens/shelf_screen.dart';
import '../tts/voices.dart';
import 'prototype/add_book.dart';
import 'prototype/demo_states.dart';
import 'prototype/phone_chrome.dart';
import 'theme.dart';

/// Языки интерфейса (решение владельца 2026-11-14). Первый — запасной для языка телефона не из списка.
const supportedLocales = [Locale('en'), Locale('ru'), Locale('pl'), Locale('de')];

/// Язык телефона, если он из четырёх, иначе английский.
Locale resolveLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final p in preferred ?? const <Locale>[]) {
    for (final s in supported) {
      if (s.languageCode == p.languageCode) return s;
    }
  }
  return const Locale('en');
}

/// Прототип целиком: все реализации подставные (А§2 — за интерфейсами модулей), сети нет.
class Prototype {
  Prototype._({
    required this.library,
    required this.settings,
    required this.narration,
    required this.downloads,
    required this.sampler,
    required this.audio,
    required this.tariffs,
  });

  final FakeLibrary library;
  final AppSettings settings;
  final FakeNarrationController narration;
  final FakeChapterDownloads downloads;
  final FakeVoiceSampler sampler;
  final FakeAudioStore audio;
  final Tariffs tariffs;
  late final AppServices services;

  /// [clock] — часы приложения: тарифы на сегодня и таймер сна. По умолчанию — настенные.
  static Future<Prototype> create({DateTime Function()? clock, double demoAcceleration = 4}) async {
    final now = clock ?? DateTime.now;
    final library = FakeLibrary();
    await library.preload();
    final settings = AppSettings(voice: defaultVoiceName, modelId: TtsModel.flash.id, apiKey: 'AIzaSyD-prototype-key-a1f3');
    final tariffs = Tariffs(today: now);
    final audio = FakeAudioStore({
      'kapitanskaya': 96 * 1024 * 1024,
      'dama': 274 * 1024 * 1024,
      'voyna': 38 * 1024 * 1024,
    });
    final downloads =
        FakeChapterDownloads(settings: settings, tariffs: tariffs, bookVoice: library.bookVoice, audio: audio);
    // Свой голос книги сменился — задача «Скачать главу» прежнего профиля останавливается (FR-D2).
    library.addListener(downloads.profileChanged);
    final sampler = FakeVoiceSampler(audio: audio);
    final p = Prototype._(
      library: library,
      settings: settings,
      narration: FakeNarrationController(
        library: library,
        audio: audio,
        downloads: downloads,
        sampler: sampler,
        settings: settings,
        clock: now,
        demoAcceleration: demoAcceleration,
      ),
      downloads: downloads,
      sampler: sampler,
      audio: audio,
      tariffs: tariffs,
    );
    p.services = AppServices(
      library: library,
      settings: settings,
      narration: p.narration,
      downloads: downloads,
      sampler: sampler,
      audio: audio,
      tariffs: tariffs,
      addBook: (context) => showDemoFilePicker(context, p),
      openUrl: (context, url) =>
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.linkStub(url)))),
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

class AudiobookApp extends StatefulWidget {
  const AudiobookApp({super.key, required this.prototype, this.phoneChrome = false});

  final Prototype prototype;

  /// Рисовать строку состояния и полоску жестов (браузер и снимки экранов; на телефоне их рисует Android).
  final bool phoneChrome;

  @override
  State<AudiobookApp> createState() => _AudiobookAppState();
}

class _AudiobookAppState extends State<AudiobookApp> {
  @override
  void initState() {
    super.initState();
    // Первая версия — только портретная ориентация (решение F проверки жестов, А§7); то же в манифесте.
    lockPortrait();
  }

  @override
  Widget build(BuildContext context) {
    final prototype = widget.prototype;
    final phoneChrome = widget.phoneChrome;
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
        final language = settings.language;
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.shelfTitle,
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          // Свои строки — из ARB; системные подписи Material и форматы дат — делегаты material_ui.
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: supportedLocales,
          locale: language == null ? null : Locale(language),
          localeListResolutionCallback: resolveLocale,
          builder: phoneChrome ? (context, child) => PhoneChrome(child: child!) : null,
          home: ShelfScreen(services: prototype.services),
        );
      },
    );
  }
}
