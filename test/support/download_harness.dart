import 'package:audiobook_reader/playback/file_chapter_download.dart';
import 'package:audiobook_reader/playback/screen_awake.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_harness.dart';

class FakeScreenAwake implements ScreenAwakePort {
  bool enabled = false;
  final changes = <bool>[];
  @override
  void setEnabled(bool value) {
    enabled = value;
    changes.add(value);
  }
}

class DownloadHarness {
  DownloadHarness._(this.h, this.downloads, this.awake);
  final PlaybackHarness h;
  final FileChapterDownloads downloads;
  final FakeScreenAwake awake;

  static Future<DownloadHarness> create(Book source) async {
    late PlaybackHarness h;
    late FileChapterDownloads downloads;
    final awake = FakeScreenAwake();
    h = await PlaybackHarness.create(
      source,
      downloadsFactory: (queue) => downloads = FileChapterDownloads(
        queue: queue,
        tariffs: Tariffs(today: queue.clock.now),
        bookFor: (id) {
          expect(id, h.book.id);
          return h.book;
        },
        screenAwake: awake,
      ),
    );
    return DownloadHarness._(h, downloads, awake);
  }

  void start([int chapter = 0]) => downloads.start(h.book, chapter, h.profile);

  Future<void> finish() async {
    for (var turn = 0; downloads.task != null && turn < 30; turn++) {
      await ioSettled();
      for (final call in h.engine.calls.where((c) => !c.released)) {
        call.release();
      }
    }
    await until(() => downloads.task == null, 'chapter download');
    await h.queue.drain();
  }
}
