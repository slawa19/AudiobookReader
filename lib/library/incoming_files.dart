/// An accepted file: already copied into the app's temporary folder, the source URI is not needed.
class IncomingFile {
  const IncomingFile({required this.path, required this.name});

  final String path;

  /// The name from DISPLAY_NAME or the last URI segment, for the "Adding" row.
  final String name;
}

/// Receiving files without knowing Android (А§2, А§7).
///
/// The receiver owns every copy it is handed: after adding (including a failure
/// or a detected duplicate) it deletes the file [IncomingFile.path] in `finally`.
/// Android cleans up the remaining copies once at process start, before the first copy.
abstract interface class IncomingFiles {
  /// The system file picker; cancelling returns `null`, a copy error — a Future error.
  Future<IncomingFile?> pickFile();

  /// Files from "Open with" and "Share", including a cold start.
  /// One subscription for the whole lifetime of the app; the queue is not lost before the subscription.
  /// A copy error arrives as a stream error, the following files keep arriving.
  Stream<IncomingFile> get incomingFiles;
}
