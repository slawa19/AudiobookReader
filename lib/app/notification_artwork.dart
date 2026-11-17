import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import 'theme.dart';

/// The same colors, first letter and typeface as BookCover on the shelf.
Future<Uri> notificationArtwork(Directory root, ShelfEntry entry, Palette palette) async {
  if (entry.cover != null) {
    return File('${root.path}/books/${entry.id}/cover.jpg').uri;
  }
  final file = File('${root.path}/tmp/media-covers/${entry.id}-${palette.name}.png');
  if (await file.exists()) return file.uri;
  final scheme = schemeFor(palette);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 320, 464), Paint()..color = scheme.surfaceContainerHighest);
  final text = TextPainter(
    text: TextSpan(
      text: entry.title.characters.firstOrNull?.toUpperCase() ?? '',
      style: TextStyle(
        fontFamily: 'Merriweather',
        fontSize: 320 * 0.42,
        fontWeight: FontWeight.w700,
        color: scheme.onSurfaceVariant,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset((320 - text.width) / 2, (464 - text.height) / 2));
  text.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 464);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw const FileSystemException('Не удалось создать обложку уведомления');
  }
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List());
  return file.uri;
}
