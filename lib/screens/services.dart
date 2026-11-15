import 'package:material_ui/material_ui.dart';

import '../audio/audio_store.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../playback/chapter_download.dart';
import '../playback/narration.dart';
import '../playback/tariffs.dart';
import '../playback/voice_sample.dart';
import 'reader_sheets.dart';

/// Всё, что экраны получают от корня сборки (`app`): зависимости передаются в конструкторы (А§8).
/// Удаление звука и книг — команды [narration] (А§4): экран не собирает их из нескольких вызовов.
class AppServices {
  AppServices({
    required this.library,
    required this.settings,
    required this.narration,
    required this.downloads,
    required this.sampler,
    required this.audio,
    required this.tariffs,
    required this.addBook,
    required this.openUrl,
    required this.spentByMonth,
    required this.themePreviews,
    this.openDemoStates,
    this.onFlush,
    this.openBook,
  });

  /// Цвета тем для превью в «Виде текста»: палитры живут в `app`.
  final Map<ThemeChoice, ThemePreview> themePreviews;

  final Library library;
  final AppSettings settings;
  final NarrationController narration;
  final ChapterDownloads downloads;
  final VoiceSampler sampler;
  final AudioStore audio;

  /// Цена за час звука по тарифу на сегодня — экран дат не знает.
  final Tariffs tariffs;

  /// «+» на полке: системный выбор файла. В прототипе — имитация.
  final Future<void> Function(BuildContext context) addBook;

  final void Function(BuildContext context, String url) openUrl;

  /// Потрачено: текущий и прошлый месяц, долларов (FR-M2).
  final List<({DateTime month, double dollars})> Function() spentByMonth;

  /// Только прототип: панель «Состояния для показа». В настоящем приложении — `null`.
  final void Function(BuildContext context)? openDemoStates;

  /// Корень настоящего приложения также показывает ошибки записи.
  final Future<void> Function()? onFlush;
  Future<void> flush() => onFlush?.call() ?? library.flush();

  /// Настоящее приложение согласует открытие с полки и из входящего файла.
  final Future<void> Function(ShelfEntry entry)? openBook;
}
