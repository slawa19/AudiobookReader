import 'package:flutter/services.dart';

class AndroidExternalLinks {
  static const channel = MethodChannel('audiobook_reader/external_links');
  static Future<void> open(String url) => channel.invokeMethod<void>('open', {'url': url});
}
