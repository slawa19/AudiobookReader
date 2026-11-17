import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/player.dart';
import 'package:audiobook_reader/playback/queued_player.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_playback_test.dart' show openBook;
import 'queued_player_test.dart' show TestEngine;
import 'support/app_harness.dart';

void main() {
  testWidgets('failed of the main adapter deletes the file and starts a retry through the real '
      'controller', (tester) async {
    final h = AppHarness(tester);
    final engines = <TestEngine>[];
    final player = QueuedPlayer(
      createEngine: () {
        final engine = TestEngine();
        engines.add(engine);
        return engine;
      },
      beforePlay: () async => true,
      readDuration: (file) => h.player.duration(file),
    );
    addTearDown(player.dispose);
    final events = <PlayerEvent>[];
    player.events.listen(events.add);
    await h.start(fakeTts: true, playerPort: player);
    await openBook(h);
    await tester.tap(find.text('Слушать'));
    await h.until(() => player.playing);
    final oldItem = player.current!;
    final oldGeneration = events.last.generation;
    final calls = h.engine.calls.length;
    engines.first.updates.addError(EngineFailure(oldItem));
    await h.until(() => h.engine.calls.length > calls && engines.length > 1 && player.playing);
    expect(events.where((e) => e.kind == PlayerEventKind.failed).single.item, same(oldItem));
    expect(player.current, isNot(same(oldItem)));
    expect(events.last.generation, greaterThan(oldGeneration));
    expect(oldItem.file.existsSync(), isTrue, reason: 'the file is published again after the repeated synthesis');
    expect(h.app.services.narration.state, NarrationState.playing);
    h.app.services.narration.pause();
  });

  testWidgets('failed of the separate probe adapter is passed to FileVoiceSampler without platform '
      'text', (tester) async {
    final h = AppHarness(tester);
    final engine = TestEngine();
    final player = QueuedPlayer(
      createEngine: () => engine,
      beforePlay: () async => true,
      readDuration: (file) => h.samplePlayer.duration(file),
    );
    addTearDown(player.dispose);
    await h.start(fakeTts: true, samplePort: player);
    h.app.services.sampler.play(
      VoiceProfile(voiceId: 'Aoede', model: TtsModel.flash.id),
      bookLanguage: 'en',
    );
    await h.until(() => player.playing);
    engine.updates.addError(EngineFailure(player.current));
    await h.until(() => h.app.services.sampler.state == SampleState.failed);
    expect(h.app.services.sampler.errorMessage, 'PlayerError: audio file unreadable');
    expect(h.app.services.narration.state, NarrationState.idle);
    expect(player.current, isNull);
  });
}
