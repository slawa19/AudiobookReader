import 'dart:async';

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/library/fake_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/fake_narration.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingDeleteLibrary extends FakeLibrary {
  @override
  Future<void> deleteBook(String bookId) async => throw StateError('delete denied verbatim');
}

void main() {
  testWidgets('a delete error is shown as a failure row and is not lost in the Future', (tester) async {
    final prototype = await Prototype.create();
    final library = _FailingDeleteLibrary();
    final controller = FakeNarrationController(
      library: library, audio: prototype.audio, downloads: prototype.downloads, sampler: prototype.sampler,
    );
    addTearDown(() {
      controller.dispose();
      library.dispose();
      prototype.narration.dispose();
      prototype.downloads.dispose();
      prototype.sampler.dispose();
      prototype.library.dispose();
      prototype.settings.dispose();
    });
    final escaped = <Object>[];
    runZonedGuarded(() => controller.deleteBook(library.shelf.first.id), (error, _) => escaped.add(error));
    await tester.pump();
    expect(library.addJobs, hasLength(1));
    expect(library.addJobs.single.status, AddJobStatus.failed);
    expect(library.addJobs.single.technical, contains('delete denied verbatim'));
    expect(escaped, isEmpty);
    expect(library.shelf, isNotEmpty);
  });
}
