/// PCM is signed little-endian, 16-bit, one channel.
/// The paths belong to the caller: the input is left untouched, the output is deleted on error.
abstract interface class AudioEncoder {
  /// Part of the fingerprint together with the text and the voice profile.
  String get formatId;
  String get extension;

  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  });
}
