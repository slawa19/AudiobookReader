import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'voices.dart';

/// The text is already cleaned by speechText; stress marks are removed for direct client calls too.
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
