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

  /// Метка clear: запоздавшие события платформенного списка не относятся к новому.
  final int generation;
  final PlayerItem? item;
}

/// Команды принимаются синхронно; адаптер последовательно применяет их к движку.
/// События должны отражать фактический звук. play не возвращает Future до конца файла.
/// append после drained разрешён: следующий play начинает добавленное с нуля.
/// Прерывание сначала останавливает звук, затем сообщает interrupted; автопродолжения нет.
/// Контракт адаптера:
/// - current == null сразу после drained и clear; append в пустой список задаёт его синхронно.
/// - current и item в событиях — исходный экземпляр PlayerItem, переданный append.
/// - position относится к current и неподвижна после pause().
/// - play() идемпотентен; после drained и append следующий play() запускает добавленное.
/// - retainThrough не удаляет и не прерывает текущий элемент.
/// - progress приходит регулярно, пока идёт звук; started — при фактическом начале элемента.
/// - failed несёт несыгранный item: звук остановлен, последующие элементы не начинаются;
///   потребитель очистит список и решит, можно ли повторить файл. Текста исключения в событии нет.
abstract interface class PlayerPort {
  Stream<PlayerEvent> get events;
  PlayerItem? get current;
  Duration get position;
  bool get playing;
  double get speed;

  /// Читает длительность контейнера, в том числе у файла прежнего запуска.
  Future<Duration> duration(File file);
  void append(PlayerItem item);
  void play();
  void pause();
  void setSpeed(double value);
  void clear(int generation);

  /// Таймер, установленный после наполнения списка, отсекает уже добавленный хвост.
  void retainThrough(int segment);
}
