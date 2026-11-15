import 'package:flutter/services.dart';

import '../library/incoming_files.dart';

/// Приём файлов Android (А§7). Создаётся в app; прототип эту реализацию не использует.
class AndroidIncomingFiles implements IncomingFiles {
  static const _methods = MethodChannel('audiobook_reader/incoming_files');
  static const _events = EventChannel('audiobook_reader/incoming_files/events');

  @override
  Future<IncomingFile?> pickFile() async {
    final file = await _methods.invokeMapMethod<String, dynamic>('pickFile');
    return file == null ? null : _decode(file);
  }

  // Подписка на канал начинается только с подпиской получателя. До неё очередь
  // держит Android, в том числе если копирование при холодном запуске уже завершилось.
  late final Stream<IncomingFile> _incomingFiles = _receive();

  @override
  Stream<IncomingFile> get incomingFiles => _incomingFiles;

  Stream<IncomingFile> _receive() async* {
    yield* _events.receiveBroadcastStream().map((event) => _decode(event as Map<dynamic, dynamic>));
  }

  static IncomingFile _decode(Map<dynamic, dynamic> file) =>
      IncomingFile(path: file['path'] as String, name: file['name'] as String);
}
