import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'queued_player_test.dart' show Harness, item;

void main() {
  test('quick pause → play during an insert does not leave the engine paused', () async {
    final h = Harness();
    h.player.append(item(0));
    h.player.play();
    await h.player.settled;
    final gate = Completer<void>(), entered = Completer<void>();
    h.engine.appendGate = gate;
    h.engine.appendEntered = entered;
    h.player.append(item(1));
    await entered.future;
    h.player.pause();
    h.player.play();
    gate.complete();
    await h.player.settled;
    expect(h.player.playing, isTrue);
    expect(h.engine.snapshot.playing, isTrue);
    expect(h.engine.overlap, isFalse);
    final plays = h.engine.calls.where((c) => c == 'play').length;
    h.player.play();
    await h.player.settled;
    expect(h.engine.calls.where((c) => c == 'play'), hasLength(plays));
  });
}
