/// PCM — знаковый little-endian, 16 бит, один канал.
/// Пути принадлежат вызывающему: вход остаётся нетронутым, выход при ошибке удаляется.
abstract interface class AudioEncoder {
  /// Входит в отпечаток вместе с текстом и профилем голоса.
  String get formatId;
  String get extension;

  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  });
}
