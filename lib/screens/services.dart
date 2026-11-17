import 'package:material_ui/material_ui.dart';

import '../audio/audio_store.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../playback/chapter_download.dart';
import '../playback/narration.dart';
import '../playback/tariffs.dart';
import '../playback/voice_sample.dart';
import 'reader_sheets.dart';

/// Everything the screens get from the assembly root (`app`): dependencies are passed into constructors (А§8).
/// Deleting audio and books are [narration] commands (А§4): the screen does not assemble them from several calls.
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
    this.fakeTts = false,
  });

  /// Theme colors for the preview in "Text appearance": the palettes live in `app`.
  final Map<ThemeChoice, ThemePreview> themePreviews;

  final Library library;
  final AppSettings settings;

  /// The fake-build flag comes from app, without a reverse import screens → app.
  final bool fakeTts;
  final NarrationController narration;
  final ChapterDownloads downloads;
  final VoiceSampler sampler;
  final AudioStore audio;

  /// The price per hour of audio at today's tariff — the screen does not know dates.
  final Tariffs tariffs;

  /// "+" on the shelf: the system file picker. In the prototype — a simulation.
  final Future<void> Function(BuildContext context) addBook;

  final void Function(BuildContext context, String url) openUrl;

  /// Spent: the current and the previous month, in dollars (FR-M2).
  final List<({DateTime month, double dollars})> Function() spentByMonth;

  /// Prototype only: the "Demo states" panel. In the real app — `null`.
  final void Function(BuildContext context)? openDemoStates;

  /// The real app's root also shows write errors.
  final Future<void> Function()? onFlush;
  Future<void> flush() => onFlush?.call() ?? library.flush();

  /// The real app coordinates opening from the shelf and from an incoming file.
  final Future<void> Function(ShelfEntry entry)? openBook;
}
