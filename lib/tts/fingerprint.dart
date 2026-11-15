import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'voices.dart';

/// Текст уже очищен speechText; ударения снимаются также для прямых вызовов клиента.
String fingerprint(String text, VoiceProfile profile, String audioFormat) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          'format': audioFormat,
          'model': profile.model,
          'style': profile.style,
          'text': text.replaceAll('\u0301', ''),
          'voice_id': profile.voiceId,
        }),
      ),
    )
    .toString();
