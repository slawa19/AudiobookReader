import 'dart:async';
import 'dart:io';

import 'player.dart';

/// Снимок относится к исходному элементу, а не к изменяемой длине списка.
class EnginePlayback {
  const EnginePlayback({
    this.item,
    this.position = Duration.zero,
    this.playing = false,
    this.ready = false,
    this.completed = false,
    this.progress = false,
  });
  final PlayerItem? item;
  final Duration position;
  final bool playing, ready, completed, progress;
}

/// Ошибка движка сообщает только исходный элемент, без сообщения и путей.
class EngineFailure {
  const EngineFailure(this.item);
  final PlayerItem? item;
}

/// play принимает команду сразу; его завершение не означает конец файла.
/// Остальные Future завершаются после применения операции к платформе.
abstract interface class PlaylistEngine {
  Stream<EnginePlayback> get events;
  EnginePlayback get snapshot;
  Future<void> load(PlayerItem item);
  Future<void> append(PlayerItem item);
  Future<void> seek(int index, {Duration position = Duration.zero});
  Future<void> retain(int count);
  Future<void> setSpeed(double speed);
  void play();
  Future<void> pause();
  Future<void> dispose();
}

class _Playlist {
  _Playlist(this.generation, this.speed);
  final int generation;
  final items = <PlayerItem>[];
  PlaylistEngine? engine;
  StreamSubscription<EnginePlayback>? subscription;
  int loaded = 0, finished = 0, index = 0, revision = 0;
  bool intent = false, playing = false, exhausted = false, drained = false, seeking = false;
  bool failed = false, frozen = false;
  bool playRequested = false;
  Duration frozenPosition = Duration.zero;
  double speed;
  PlayerItem? started;
  PlayerItem? get current => index < items.length ? items[index] : null;
}

/// Единственная очередь всех операций, включая pause, seek, смену поколения
/// и освобождение движка. Учёт загруженного меняется только после Future движка.
class QueuedPlayer implements PlayerPort {
  QueuedPlayer({required this.createEngine, required this.beforePlay, required this.readDuration});
  final PlaylistEngine Function() createEngine;
  final Future<bool> Function() beforePlay;
  final Future<Duration> Function(File) readDuration;
  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  _Playlist _list = _Playlist(0, 1);
  Future<void> _operations = Future.value();
  bool _disposed = false;

  Future<void> get settled async {
    Future<void> pending;
    do {
      pending = _operations;
      await pending;
    } while (!identical(pending, _operations));
  }

  @override
  Stream<PlayerEvent> get events => _events.stream;
  @override
  PlayerItem? get current => _list.current;
  @override
  Duration get position {
    if (_list.frozen) return _list.frozenPosition;
    final state = _list.engine?.snapshot;
    return state != null && identical(state.item, current) && !_list.exhausted ? state.position : Duration.zero;
  }

  @override
  bool get playing => _list.playing;
  @override
  double get speed => _list.speed;
  @override
  Future<Duration> duration(File file) => readDuration(file);

  bool _active(_Playlist list) => !_disposed && identical(list, _list);
  void _emit(_Playlist list, PlayerEventKind kind, {PlayerItem? item}) {
    if (_active(list)) _events.add(PlayerEvent(kind, list.generation, item: item));
  }

  void _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation());
  }

  void _command(_Playlist list, Future<void> Function() operation, {PlayerItem? failureItem}) {
    _enqueue(() async {
      if (!_active(list) || list.failed) return;
      try {
        await operation();
      } catch (_) {
        _fail(list, failureItem ?? list.current);
      }
    });
  }

  void _fail(_Playlist list, PlayerItem? item) {
    if (!_active(list) || list.failed || item == null) return;
    list.frozenPosition = position;
    list.frozen = list.failed = true;
    list.intent = list.playing = false;
    list.playRequested = false;
    // queued-команды уже видят failed и не запускают хвост. Само событие
    // публикуется только после освобождения декодера и остановки звука.
    _enqueue(() async {
      if (!_active(list)) return;
      await _disposeList(list);
      if (_active(list)) _emit(list, PlayerEventKind.failed, item: item);
    });
  }

  PlaylistEngine _engine(_Playlist list) {
    if (list.engine != null) return list.engine!;
    final engine = list.engine = createEngine();
    list.subscription = engine.events.listen(
      (state) => _state(list, state),
      onError: (Object error) => _fail(list, error is EngineFailure ? error.item ?? list.current : list.current),
    );
    return engine;
  }

  void _state(_Playlist list, EnginePlayback state) {
    if (!_active(list) || list.seeking || list.failed || list.frozen) return;
    final item = state.item;
    if (item == null) return;
    final index = list.items.indexWhere((i) => identical(i, item));
    if (index < 0) return;
    if (state.completed) {
      // Завершился именно этот префикс. append мог уже принять следующий файл,
      // хотя платформенная вставка ещё не завершилась.
      final through = index + 1;
      if (through <= list.finished) return;
      list.finished = through;
      list.index = through;
      list.exhausted = true;
      list.playRequested = false;
      list.playing = false;
      list.started = null;
      _drained(list);
      return;
    }
    if (index < list.finished || list.exhausted) return;
    list.index = index;
    list.playing = list.intent && state.playing && state.ready;
    if (list.playing && !identical(list.started, item)) {
      list.started = item;
      _emit(list, PlayerEventKind.started, item: item);
    } else if (list.playing && state.progress) {
      _emit(list, PlayerEventKind.progress, item: item);
    }
  }

  void _drained(_Playlist list) {
    if (list.finished >= list.items.length && !list.drained) {
      list.drained = true;
      _emit(list, PlayerEventKind.drained);
    }
  }

  Future<void> _play(_Playlist list) async {
    if (!_active(list) || list.failed || !list.intent || list.current == null || list.finished >= list.loaded) return;
    final engine = _engine(list);
    if (list.playRequested && !list.exhausted && !list.frozen) return;
    if (engine.snapshot.playing && !list.exhausted && !list.frozen) return;
    final revision = list.revision;
    final allowed = await beforePlay();
    if (!_active(list) || list.failed || revision != list.revision || !list.intent) return;
    if (!allowed) {
      list.intent = list.playing = false;
      await engine.pause();
      _emit(list, PlayerEventKind.interrupted, item: list.current);
      return;
    }
    if (list.frozen) {
      final state = engine.snapshot;
      if (!identical(state.item, list.current) || state.position != list.frozenPosition) {
        await engine.pause();
        if (!_active(list) || list.failed || revision != list.revision || !list.intent) return;
        list.seeking = true;
        try {
          await engine.seek(list.index, position: list.frozenPosition);
        } finally {
          list.seeking = false;
        }
        if (!_active(list) || list.failed || revision != list.revision || !list.intent) return;
      }
      list.frozen = false;
    }
    list.playRequested = true;
    engine.play();
  }

  @override
  void append(PlayerItem item) {
    final list = _list;
    list.items.add(item);
    list.drained = false;
    _command(list, () async {
      if (!list.items.any((i) => identical(i, item))) return;
      final engine = _engine(list);
      if (list.loaded == 0) {
        await engine.setSpeed(list.speed);
        if (!_active(list)) return;
        await engine.load(item);
      } else {
        // STATE_ENDED может сам продолжить после вставки. Когда конец уже
        // известен, сначала снимаем платформенное намерение играть.
        if (list.exhausted) await engine.pause();
        if (!_active(list)) return;
        await engine.append(item);
      }
      list.loaded++;
      if (!_active(list) || list.failed) return;
      if (list.exhausted && list.finished < list.loaded && list.current != null) {
        await engine.pause();
        if (!_active(list)) return;
        list.seeking = true;
        try {
          await engine.seek(list.finished);
        } finally {
          list.seeking = false;
        }
        if (!_active(list)) return;
        list.exhausted = false;
        _state(list, engine.snapshot);
      }
      await _play(list);
    }, failureItem: item);
  }

  @override
  void play() {
    final list = _list;
    if (list.failed) return;
    list.intent = true;
    _command(list, () => _play(list));
  }

  @override
  void pause() {
    final list = _list;
    list.frozenPosition = position;
    list.frozen = true;
    list.revision++;
    list.intent = list.playing = false;
    list.playRequested = false;
    // Физическая пауза ждёт незавершённую операцию движка. Прерывать вставку
    // параллельной командой нельзя: все команды используют одну очередь.
    _command(list, () async {
      await list.engine?.pause();
      // Пока вставка ждала, intent мог снова стать true и её завершение могло
      // послать play. После фактической паузы следующая play-команда нужна заново.
      list.playRequested = false;
    });
  }

  @override
  void setSpeed(double value) {
    if (!value.isFinite || value <= 0) throw ArgumentError.value(value);
    final list = _list;
    list.speed = value;
    _command(list, () async {
      await list.engine?.setSpeed(value);
    });
  }

  @override
  void retainThrough(int segment) {
    final list = _list;
    final tail = list.items.indexWhere((i) => i.segment > segment);
    if (tail < 0) return;
    // Даже при границе перед current сам текущий элемент сохраняется.
    final first = tail > list.index ? tail : list.index + 1;
    if (first >= list.items.length) return;
    list.items.removeRange(first, list.items.length);
    _command(list, () async {
      if (list.loaded > first) {
        await list.engine!.retain(first);
        list.loaded = first;
      }
      _drained(list);
    });
  }

  @override
  void clear(int generation) {
    final old = _list;
    old.revision++;
    old.intent = old.playing = false;
    _list = _Playlist(generation, old.speed);
    _enqueue(() => _disposeList(old));
  }

  Future<void> _disposeList(_Playlist list) async {
    await list.subscription?.cancel();
    await list.engine?.dispose();
    list.subscription = null;
    list.engine = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _list.intent = _list.playing = false;
    _enqueue(() => _disposeList(_list));
    await _operations;
    await _events.close();
  }
}
