import 'dart:convert';
import 'dart:typed_data';

const measuredUsage = <String, Object>{
  'total_tokens': 37,
  'total_input_tokens': 3,
  'input_tokens_by_modality': [
    {'modality': 'text', 'tokens': 3},
  ],
  'total_cached_tokens': 0,
  'total_output_tokens': 34,
  'output_tokens_by_modality': [
    {'modality': 'audio', 'tokens': 34},
  ],
  'total_tool_use_tokens': 0,
  'total_thought_tokens': 0,
  'initial_input_tokens': 3,
};

Map<String, Object?> audioResponse({
  List<int> bytes = const [1, 0, 2, 0],
  String mime = 'audio/l16;rate=24000',
  Map<String, Object>? usage = measuredUsage,
  String? status = 'completed',
}) => {
  'status': ?status,
  'usage': ?usage,
  'steps': [
    {'type': 'other', 'content': []},
    {
      'type': 'model_output',
      'content': [
        {'type': 'text', 'text': 'служебное'},
        {'type': 'audio', 'data': base64Encode(bytes), 'mime_type': mime},
      ],
    },
  ],
};

/// WAV с нечётным вспомогательным RIFF-чанком: данные начинаются не с фиксированного смещения 44.
Uint8List wav({int rate = 16000, int channels = 1, int bits = 16}) {
  final b = ByteData(58);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 50, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'JUNK');
  b.setUint32(16, 1, Endian.little);
  b.setUint8(20, 77);
  tag(22, 'fmt ');
  b.setUint32(26, 16, Endian.little);
  b.setUint16(30, 1, Endian.little);
  b.setUint16(32, channels, Endian.little);
  b.setUint32(34, rate, Endian.little);
  b.setUint32(38, rate * 2, Endian.little);
  b.setUint16(42, 2, Endian.little);
  b.setUint16(44, bits, Endian.little);
  tag(46, 'data');
  b.setUint32(50, 4, Endian.little);
  b.setInt16(54, 123, Endian.little);
  b.setInt16(56, -456, Endian.little);
  return b.buffer.asUint8List();
}
