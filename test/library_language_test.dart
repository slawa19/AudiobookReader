import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/tts/book_language.dart';
import 'package:audiobook_reader/tts/fingerprint.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

List<int> sample(String format, {String language = ''}) => switch (format) {
  'txt' => utf8.encode('Текст книги.'),
  'fb2' => utf8.encode(
    '<FictionBook><description><title-info>'
    '${language.isEmpty ? '' : '<lang>$language</lang>'}'
    '</title-info></description><body><section><p>Текст книги.</p></section></body></FictionBook>',
  ),
  'epub' => epub(
    raw: {
      'OPS/book.opf': utf8.encode(
        '<package><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '${language.isEmpty ? '' : '<dc:language>$language</dc:language>'}</metadata><manifest>'
        '<item id="text" href="text.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="text"/></spine></package>',
      ),
    },
  ),
  _ => throw ArgumentError(format),
};

String audioKey(Book book) => fingerprint(
  book.blocks.first.text,
  VoiceProfile(
    voiceId: 'default',
    model: 'model',
    style: readingStyleFor(book.language),
  ),
  'wav',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileLibrary library;

  Future<void> start({LibraryParser? parser}) async {
    library = FileLibrary(
      root,
      settings: AppSettings(voice: 'default', modelId: 'model'),
      parser: parser,
    );
    await library.ready;
  }

  Future<void> restart() async {
    await library.flush();
    library.dispose();
    await start();
  }

  File modelFile(String id) => File('${root.path}/books/$id/book.json');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-language-');
    await start();
  });
  tearDown(() async {
    await library.flush();
    library.dispose();
    await root.delete(recursive: true);
  });

  for (final format in ['txt', 'fb2', 'epub']) {
    test(
      '$format: пустой язык фиксируется при добавлении и переживает смену интерфейса и переразбор',
      () async {
        library.settings.language = 'ru';
        final bytes = sample(format);
        expect(parseBook(bytes).book.language, '');
        final source = await File('${root.path}/source').writeAsBytes(bytes);
        final entry = (await library.addFile(source.path, 'Книга.$format'))!;
        final book = await library.loadBook(entry.id);
        expect(book.language, 'ru');
        expect(samplePhraseFor(book.language), samplePhrases['ru']);
        final key = audioKey(book);
        final saved = jsonDecode(
          await modelFile(entry.id).readAsString(),
        ) as Map<String, Object?>;
        expect(saved['language'], 'ru');
        library.settings.language = 'de';
        saved['parserVersion'] = 0;
        await modelFile(entry.id).writeAsString(jsonEncode(saved));
        await restart();
        expect(library.settings.language, 'de');
        expect(
          (await library.addFile(source.path, 'Другое.$format'))!.id,
          entry.id,
        );
        final reparsed = await library.loadBook(entry.id);
        expect(reparsed.language, 'ru');
        expect(reparsed.parserVersion, currentParserVersion);
        expect(audioKey(reparsed), key);
        await restart();
        expect((await library.loadBook(entry.id)).language, 'ru');
      },
    );
  }

  for (final format in ['fb2', 'epub']) {
    test(
      '$format: язык из метаданных не заменяется языком интерфейса',
      () async {
        library.settings.language = 'ru';
        final source = await File('${root.path}/source')
            .writeAsBytes(sample(format, language: 'pl'));
        final entry = (await library.addFile(source.path, 'Книга.$format'))!;
        expect((await library.loadBook(entry.id)).language, 'pl');
      },
    );
  }

  for (final version in [0, currentParserVersion]) {
    test(
      'старая книга с пустым языком сохраняет его и отпечаток: parserVersion=$version',
      () async {
        final source = await File('${root.path}/source')
            .writeAsBytes(sample('txt'));
        final entry = (await library.addFile(source.path, 'Книга.txt'))!;
        final saved = jsonDecode(
          await modelFile(entry.id).readAsString(),
        ) as Map<String, Object?>;
        saved['language'] = '';
        saved['parserVersion'] = version;
        final oldBook = Book.fromJson(saved);
        await modelFile(entry.id).writeAsString(jsonEncode(saved));
        library.settings.language = 'ru';
        await restart();
        expect(
          (await library.addFile(source.path, 'Повтор.txt'))!.id,
          entry.id,
        );
        final book = await library.loadBook(entry.id);
        expect(book.language, '');
        expect(audioKey(book), audioKey(oldBook));
        expect(
          (jsonDecode(await modelFile(entry.id).readAsString())
              as Map)['language'],
          '',
        );
      },
    );
  }

  test('язык захватывается до ожидания разбора', () async {
    library.dispose();
    final parsing = Completer<void>();
    final gate = Completer<ParsedBook>();
    await start(
      parser: (_) {
        parsing.complete();
        return gate.future;
      },
    );
    library.settings.language = 'ru';
    final bytes = sample('txt');
    final source = await File('${root.path}/source').writeAsBytes(bytes);
    final adding = library.addFile(source.path, 'Книга.txt');
    await parsing.future;
    library.settings.language = 'de';
    gate.complete(parseBook(bytes));
    final entry = (await adding)!;
    expect((await library.loadBook(entry.id)).language, 'ru');
  });
}
