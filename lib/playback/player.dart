import 'dart:async';
import 'dart:io';

class PlayerItem {
  const PlayerItem({
    required this.file,
    required this.segment,
    required this.duration,
  });
  final File file;
  final int segment;
  final Duration duration;
}

enum PlayerEventKind { started, progress, drained, interrupted, failed }

class PlayerEvent {
  const PlayerEvent(this.kind, this.generation, {this.item});
  final PlayerEventKind kind;

  /// The clear mark: late events of the platform list do not belong to the new one.
  final int generation;
  final PlayerItem? item;
}

/// Commands are accepted synchronously; the adapter applies them to the engine sequentially.
/// Events must reflect the actual audio. play does not return a Future until the end of the file.
/// append after drained is allowed: the next play starts the appended item from zero.
/// An interruption first stops the audio, then reports interrupted; there is no auto-resume.
/// The adapter contract:
/// - current == null right after drained and clear; append into an empty list sets it synchronously.
/// - current and item in events are the original PlayerItem instance passed to append.
/// - position refers to current and is still after pause().
/// - play() is idempotent; after drained and append the next play() starts the appended item.
/// - retainThrough neither removes nor interrupts the current item.
/// - progress arrives regularly while audio plays; started — when the item actually begins.
/// - failed carries the unplayed item: the audio is stopped, the following items do not start;
///   the consumer will clear the list and decide whether the file can be retried. The event has no exception text.
abstract interface class PlayerPort {
  Stream<PlayerEvent> get events;
  PlayerItem? get current;
  Duration get position;
  bool get playing;
  double get speed;

  /// Reads the container duration, including for a file from a previous launch.
  Future<Duration> duration(File file);
  void append(PlayerItem item);
  void play();
  void pause();
  void setSpeed(double value);
  void clear(int generation);

  /// A timer set after the list is filled cuts off the already appended tail.
  void retainThrough(int segment);
}
