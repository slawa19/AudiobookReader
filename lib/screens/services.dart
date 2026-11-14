import 'package:material_ui/material_ui.dart';

import '../audio/audio_store.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../playback/chapter_download.dart';
import '../playback/narration.dart';
import '../playback/voice_sample.dart';
import 'reader_sheets.dart';

/// Всё, что экраны получают от корня сборки (`app`): зависимости передаются в конструкторы (А§8).
class AppServices {
  AppServices({
    required this.library,
    required this.settings,
    required this.narration,
    required this.downloads,
    required this.sampler,
    required this.audio,
    required this.addBook,
    required this.openUrl,
    required this.clearNarration,
    required this.deleteNarration,
    required this.spentByMonth,
    required this.themePreviews,
    this.openDemoStates,
  });

  /// Цвета тем для превью в «Виде текста»: палитры живут в `app`.
  final Map<ThemeChoice, ThemePreview> themePreviews;

  final Library library;
  final AppSettings settings;
  final NarrationController narration;
  final ChapterDownloads downloads;
  final VoiceSampler sampler;
  final AudioStore audio;

  /// «+» на полке: системный выбор файла. В прототипе — имитация.
  final Future<void> Function(BuildContext context) addBook;

  final void Function(BuildContext context, String url) openUrl;

  /// «Очистить озвучку» (FR-M3) и «Удалить озвучку» книги (FR-D3) — выполняет `playback` (А§2, А§4).
  final VoidCallback clearNarration;
  final void Function(String bookId) deleteNarration;

  /// Потрачено: текущий и прошлый месяц, долларов (FR-M2).
  final List<({DateTime month, double dollars})> Function() spentByMonth;

  /// Только прототип: панель «Состояния для показа». В настоящем приложении — `null`.
  final void Function(BuildContext context)? openDemoStates;

  Listenable get all => Listenable.merge([library, settings, narration, downloads, sampler]);
}
