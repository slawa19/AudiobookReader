import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../audio/audio_store.dart';
import '../library/file_library.dart';
import '../library/incoming_files.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../platform/platform.dart';
import '../playback/chapter_download.dart';
import '../playback/fake_narration.dart';
import '../playback/tariffs.dart';
import '../playback/voice_sample.dart';
import '../screens/common.dart';
import '../screens/reader_screen.dart';
import '../screens/services.dart';
import '../tts/voices.dart';
import 'assembly.dart';
import 'theme.dart';

/// Этап 1: настоящие файлы и настройки, прежние подставные службы озвучки.
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

  /// В тестах меняются только источник входящих файлов и каталог хранения.
  static Future<NativeApplication> create({
    Directory? root,
    IncomingFiles? incoming,
    LibraryParser? parser,
    DateTime Function()? clock,
    LibraryTimer? timer,
  }) async {
    final settings = AppSettings(voice: defaultVoiceName, modelId: TtsModel.flash.id);
    final library = FileLibrary(
      root ?? await getApplicationSupportDirectory(),
      settings: settings,
      parser: parser,
      clock: clock,
      timer: timer,
    );
    await library.ready;
    return NativeApplication.fromLibrary(library, incoming ?? AndroidIncomingFiles(), clock: clock);
  }

  /// Готовая полка передаётся в конструктор; [create] выбирает Android-хранилище.
  NativeApplication.fromLibrary(this.library, this.incoming, {DateTime Function()? clock})
    : settings = library.settings {
    final audio = FakeAudioStore({});
    final tariffs = Tariffs(today: clock ?? DateTime.now);
    final downloads = FakeChapterDownloads(
      settings: settings,
      tariffs: tariffs,
      bookVoice: library.bookVoice,
      audio: audio,
    );
    library.addListener(downloads.profileChanged);
    final sampler = FakeVoiceSampler(audio: audio);
    final narration = FakeNarrationController(
      library: library,
      audio: audio,
      downloads: downloads,
      sampler: sampler,
      settings: settings,
    );
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
      openUrl: (context, url) =>
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.linkStub(url)))),
      spentByMonth: () => [],
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

  @override
  void attach(GlobalKey<NavigatorState> navigator) {
    _navigator = navigator;
    // Подписка одна, не зависит от переходов между полкой, чтением и настройками.
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

  void _failure(Object error, [String? name]) {
    _opening++;
    final context = _navigator?.currentContext;
    library.recordFileFailure(name ?? (context == null ? '' : context.l10n.addBook), error);
    // Отказ виден на полке даже если файл пришёл поверх открытой книги.
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
    // dispose прежнего чтения возвращает системные панели. Новое чтение
    // начинает свой жизненный цикл только после завершения этого перехода.
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
        // Копия принадлежит получателю: также после отказа и обнаружения повтора.
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
    // До полной загрузки остаётся прежний экран; пустой ReaderScreen не создаётся.
    final book = await library.loadBook(entry.id);
    if (opening != _opening) return;
    await _returnToShelf();
    if (opening != _opening) return;
    final navigator = _navigator?.currentState;
    if (navigator == null) return;
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
