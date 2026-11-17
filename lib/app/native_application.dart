import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;

import '../audio/audio_encoder.dart';
import '../audio/file_audio_store.dart';
import '../book/model.dart';
import '../library/file_library.dart';
import '../library/incoming_files.dart';
import '../library/library.dart';
import '../library/secret_store.dart';
import '../library/settings.dart';
import '../platform/platform.dart';
import '../platform/secret_store.dart';
import '../platform/audio_encoder.dart';
import '../platform/external_links.dart';
import '../playback/file_chapter_download.dart';
import '../playback/clock.dart';
import '../playback/controller.dart';
import '../playback/file_voice_sample.dart';
import '../playback/just_audio_player.dart';
import '../playback/media_session.dart';
import '../playback/player.dart';
import '../playback/screen_awake.dart';
import '../playback/synthesis_queue.dart';
import '../playback/tariffs.dart';
import '../screens/common.dart';
import '../screens/l10n/app_localizations.dart';
import '../screens/reader_screen.dart';
import '../screens/services.dart';
import '../tts/voices.dart';
import '../tts/engine.dart';
import '../tts/fake_engine.dart';
import 'app.dart' show resolveLocale, supportedLocales;
import 'assembly.dart';
import 'current_key_engine.dart';
import 'media_lifecycle.dart';
import 'native_settings.dart';
import 'notification_artwork.dart';
import 'screen_awake.dart';
import 'theme.dart';

/// The Android root: files, synthesis, players and the media session outlive the screens.
class NativeApplication extends AppAssembly {
  final FileLibrary library;
  @override
  final AppSettings settings;
  final IncomingFiles incoming;
  @override
  late final AppServices services;
  GlobalKey<NavigatorState>? _navigator;
  StreamSubscription<IncomingFile>? _subscription;
  Future<void> _imports = Future.value();
  Future<void> _shelfReady = Future.value();
  bool _picking = false;
  Future<void>? _flushing;
  int _opening = 0;
  late final SynthesisQueue queue;
  late final FileChapterDownloads downloads;
  late final ScreenAwakePort _screenAwake;
  late final PlayerPort player, samplePlayer;
  late final NarrationMediaHandler media;
  NarrationAudioFocus? _focus;
  http.Client? _transport;
  Uri? _art;

  /// Tests replace only the incoming-files source and the storage directory.
  static Future<NativeApplication> create({
    Directory? root,
    IncomingFiles? incoming,
    LibraryParser? parser,
    DateTime Function()? clock,
    LibraryTimer? timer,
    SecretStore? secretStore,
    AudioEncoder? encoder,
    PlayerPort? player,
    PlayerPort? samplePlayer,
    TtsEngine? engine,
    PlaybackClock playbackClock = const SystemPlaybackClock(),
    bool fakeTts = useFakeTts,
    MediaServiceLifecycle? mediaLifecycle,
    ScreenAwakePort? screenAwake,
  }) async {
    final settings = NativeSettings(
      voice: defaultVoiceName,
      modelId: TtsModel.flash.id,
      secretStore: secretStore ?? AndroidSecretStore(),
      fakeTts: fakeTts,
    );
    final library = FileLibrary(
      root ?? await getApplicationSupportDirectory(),
      settings: settings,
      parser: parser,
      interfaceLanguage: () => resolveLocale(
        settings.language == null
            ? WidgetsBinding.instance.platformDispatcher.locales
            : [Locale(settings.language!)],
        supportedLocales,
      ).languageCode,
      clock: clock,
      timer: timer,
    );
    await library.ready;
    return NativeApplication.fromLibrary(
      library,
      incoming ?? AndroidIncomingFiles(),
      clock: clock,
      encoder: encoder,
      player: player,
      samplePlayer: samplePlayer,
      engine: engine,
      playbackClock: playbackClock,
      fakeTts: fakeTts,
      mediaLifecycle: mediaLifecycle,
      screenAwake: screenAwake,
    );
  }

  /// A ready shelf is passed to the constructor; [create] selects the Android storage.
  NativeApplication.fromLibrary(
    this.library,
    this.incoming, {
    DateTime Function()? clock,
    AudioEncoder? encoder,
    PlayerPort? player,
    PlayerPort? samplePlayer,
    TtsEngine? engine,
    PlaybackClock playbackClock = const SystemPlaybackClock(),
    bool fakeTts = useFakeTts,
    MediaServiceLifecycle? mediaLifecycle,
    ScreenAwakePort? screenAwake,
  }) : settings = library.settings {
    final audio = FileAudioStore(library.root, encoder: encoder ?? const AndroidAudioEncoder());
    final tariffs = Tariffs(today: clock ?? DateTime.now);
    final TtsEngine synthesis;
    if (engine != null) {
      synthesis = engine;
    } else if (fakeTts) {
      synthesis = FakeTtsEngine(delay: const Duration(seconds: 2));
    } else {
      _transport = http.Client();
      synthesis = CurrentKeyEngine(settings, _transport!);
    }
    queue = SynthesisQueue(engine: synthesis, audio: audio, library: library, settings: settings, clock: playbackClock);
    _screenAwake = screenAwake ?? NativeScreenAwake((error) => library.recordFileFailure('screen_awake', error));
    downloads = FileChapterDownloads(
      queue: queue,
      tariffs: tariffs,
      bookFor: (id) => library.cachedBook(id) ?? (throw StateError('Book is not open: $id')),
      screenAwake: _screenAwake,
    );
    this.player = player ?? JustAudioPlayer(beforePlay: () async => await _focus?.activateNarration() ?? false);
    this.samplePlayer =
        samplePlayer ?? JustAudioPlayer(beforePlay: () async => await _focus?.activateSample() ?? false);
    final sampler = FileVoiceSampler(queue: queue, player: this.samplePlayer);
    final narration = FileNarrationController(
      library: library,
      queue: queue,
      player: this.player,
      sampler: sampler,
      settings: settings,
      clock: playbackClock,
      downloads: downloads,
    );
    media = NarrationMediaHandler(
      controller: narration,
      strings: _mediaStrings,
      card: () => narration.bookId == null ? null : _mediaCard(),
      lifecycle: mediaLifecycle ?? AndroidMediaServiceLifecycle(),
    );
    settings.addListener(media.publish);
    services = AppServices(
      library: library,
      settings: settings,
      narration: narration,
      downloads: downloads,
      sampler: sampler,
      audio: audio,
      tariffs: tariffs,
      addBook: _pick,
      onFlush: flush,
      openBook: _open,
      openUrl: (context, url) => unawaited(_openUrl(context, url)),
      spentByMonth: () => spentByMonth(library, (clock ?? DateTime.now)()),
      fakeTts: fakeTts,
      themePreviews: {
        for (final c in ThemeChoice.values)
          c: (
            bg: paletteFor(c, Brightness.light).bg,
            ink: paletteFor(c, Brightness.light).ink,
            line: paletteFor(c, Brightness.light).line,
          ),
      },
    );
  }

  MediaStrings _mediaStrings() {
    final preferred = settings.language;
    final locale = resolveLocale(
      preferred == null ? WidgetsBinding.instance.platformDispatcher.locales : [Locale(preferred)],
      supportedLocales,
    );
    final l = lookupAppLocalizations(locale);
    return MediaStrings(
      channel: l.mediaChannel,
      preparing: l.preparing,
      waiting: l.waiting,
      paused: l.pause,
      ended: l.endOfBook,
      play: l.listen,
      pause: l.pause,
      previous: l.mediaPrevious,
      next: l.mediaNext,
    );
  }

  MediaCard? _mediaCard() {
    final id = media.controller.bookId;
    if (id == null) return null;
    final entry = library.entry(id);
    final book = library.cachedBook(id);
    final block = media.controller.block;
    return MediaCard(
      id: id,
      title: entry.title,
      chapter: book?.id == id && block != null ? chapterLabel(book!, book.chapterOf(block)) : entry.chapterTitle ?? '',
      art: _art,
    );
  }

  /// Called by main before runApp. Tests substitute the ports without starting Android.
  Future<void> connectMedia() async {
    await AudioService.init(
      builder: () => media,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'audiobook_reader.playback',
        androidNotificationChannelName: _mediaStrings().channel,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_stat_book',
        preloadArtwork: false,
      ),
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _focus = NarrationAudioFocus(
      controller: services.narration,
      sampler: services.sampler,
      session: SystemAudioFocusSession(session),
      media: media,
      failed: (error, stack) {
        services.narration.pause();
        library.recordFileFailure(_mediaStrings().channel, error);
      },
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      await AndroidExternalLinks.open(url);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> disposePlayback() async {
    settings.removeListener(media.publish);
    media.dispose();
    await _focus?.dispose();
    services.narration.dispose();
    services.sampler.dispose();
    services.downloads.dispose();
    if (_screenAwake case final NativeScreenAwake native) await native.flush();
    queue.dispose();
    queue.invalidateAll();
    await queue.drain();
    for (final p in [player, samplePlayer]) {
      if (p is JustAudioPlayer) await p.dispose();
    }
    services.audio.dispose();
    _transport?.close();
  }

  @override
  void attach(GlobalKey<NavigatorState> navigator) {
    _navigator = navigator;
    // A single subscription, independent of navigation between shelf, reading and settings.
    _subscription ??= incoming.incomingFiles.listen((file) {
      unawaited(_enqueueImport(file, open: true));
    }, onError: (Object error) => _failure(error));
  }

  @override
  void detach() {
    _opening++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _navigator = null;
  }

  @override
  void setForeground(bool foreground) => downloads.setForeground(foreground);

  void _failure(Object error, [String? name]) {
    _opening++;
    final context = _navigator?.currentContext;
    library.recordFileFailure(name ?? (context == null ? '' : context.l10n.addBook), error);
    // A failure is visible on the shelf even if the file arrived on top of an open book.
    unawaited(_returnToShelf());
  }

  Future<void> _enqueueImport(IncomingFile file, {required bool open}) =>
      _imports = _imports.then((_) => _import(file, open: open));

  Future<void> _returnToShelf() {
    final closing = <Future<void>>[_shelfReady];
    _navigator?.currentState?.popUntil((route) {
      if (route.isFirst) return true;
      if (route is TransitionRoute<dynamic>) {
        closing.add(route.completed.then((_) {}));
      }
      return false;
    });
    // Disposing the previous reading screen restores the system bars. The new reading
    // starts its own lifecycle only after this transition completes.
    return _shelfReady = Future.wait(closing).then((_) {});
  }

  Future<void> _pick(BuildContext context) async {
    if (_picking) return;
    _picking = true;
    try {
      final file = await incoming.pickFile();
      if (file != null) unawaited(_enqueueImport(file, open: false));
    } catch (error) {
      _failure(error);
    } finally {
      _picking = false;
    }
  }

  Future<void> _import(IncomingFile incomingFile, {required bool open}) async {
    final file = File(incomingFile.path);
    ShelfEntry? entry;
    final existing = library.shelf.map((e) => e.id).toSet();
    try {
      try {
        entry = await library.addFile(incomingFile.path, incomingFile.name);
      } finally {
        // The copy belongs to the receiver: also after a failure and after a duplicate is detected.
        if (await file.exists()) await file.delete();
      }
      if (entry == null) {
        await _returnToShelf();
      } else if (open || existing.contains(entry.id)) {
        await _open(entry);
      }
    } catch (error) {
      _failure(error, incomingFile.name);
    }
  }

  Future<void> _open(ShelfEntry entry) async {
    final opening = ++_opening;
    // The previous screen stays until loading finishes; an empty ReaderScreen is never created.
    final book = await library.loadBook(entry.id);
    if (opening != _opening) return;
    await _returnToShelf();
    if (opening != _opening) return;
    final navigator = _navigator?.currentState;
    if (navigator == null) return;
    // The cover is ready before "Listen" is pressed: starting the service does not wait for the PNG to render.
    _art = await notificationArtwork(
      library.root,
      entry,
      paletteFor(settings.theme, WidgetsBinding.instance.platformDispatcher.platformBrightness),
    );
    if (opening != _opening) return;
    library.markOpened(entry.id);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(services: services, book: book),
        ),
      ),
    );
  }

  Future<void> flush() => _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    try {
      await library.flush();
    } catch (error) {
      library.recordFileFailure('state.json / settings.json', error);
    }
  }
}
