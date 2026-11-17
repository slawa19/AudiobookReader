import 'package:flutter/services.dart';

import '../library/incoming_files.dart';

/// Receiving files on Android (A§7). Created in app; the prototype does not use this implementation.
class AndroidIncomingFiles implements IncomingFiles {
  static const _methods = MethodChannel('audiobook_reader/incoming_files');
  static const _events = EventChannel('audiobook_reader/incoming_files/events');

  @override
  Future<IncomingFile?> pickFile() async {
    final file = await _methods.invokeMapMethod<String, dynamic>('pickFile');
    return file == null ? null : _decode(file);
  }

  // Subscribing to the channel begins only with the receiver's subscription. Until then the queue
  // is held by Android, including when the copy on a cold start has already finished.
  late final Stream<IncomingFile> _incomingFiles = _receive();

  @override
  Stream<IncomingFile> get incomingFiles => _incomingFiles;

  Stream<IncomingFile> _receive() async* {
    yield* _events.receiveBroadcastStream().map((event) => _decode(event as Map<dynamic, dynamic>));
  }

  static IncomingFile _decode(Map<dynamic, dynamic> file) =>
      IncomingFile(path: file['path'] as String, name: file['name'] as String);
}
