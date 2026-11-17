# External review of stage 2 of spec 001 — Fable 5.2, 2026-11-15

The owner's experiment ([EXPERIMENT_CODEX_IMPL.md](EXPERIMENT_CODEX_IMPL.md)): the code was written by Codex agents, the
external review by two separate Fable 5.2 agents. The review ran on `main` at `e64283c`, in a separate worktree, before
the real player was connected and before the app was built on real narration; the reviewers proved the findings with
temporary tests. This file is not a source of truth: the spec and the code remain so.

Both verdicts — **REWORK**.

## Reviewer 1: `tts`, `audio`, spend and key, build

Splitting into segments, the fingerprint, readiness and spend accounting were checked on hundreds of thousands of random
inputs — no defects.

| # | Raised | Confirmed | Orchestrator's decision |
|---|---|---|---|
| 1 | a key with a line feed or an invisible character gets into the client's exception text | test | fix: any transport exception becomes a `TtsError` without foreign text; the key is normalized on input |
| 2 | a network drop (`SocketException`, a TLS failure) is a permanent error, narration stops | test | fix: a transient error, the queue retries |
| 3 | real synthesis is not connected in the app | fact | in progress (`s002-player`) |
| 4 | "* * *", "…", a block of only footnotes go to Gemini as a paid request | test | fix; A§3: a block without letters and digits is not read aloud |
| 5 | the "Top up" link is taken from Google's text with punctuation stuck to it | test | fix: the address is constant; GEMINI_TTS.md corrected |
| 6 | a first starting part of 3–6 characters: a second of audio, then ≈ 8 s of silence | test | fix; A§6.1: the first part is no less than 80 characters |
| 7 | a key refusal is looked for with a pattern over the whole body; 401 not recognized | test | fix |
| 8 | a WAV with a streaming header is rejected after a paid response | test | fix |
| 9 | a timeout does not cancel the request: the late response is paid for and not accounted | reading | **rejected**: an accepted limitation, as in the studio |
| 10 | Kotlin: the encoder delay gives silence at the start of the file; the encoder channel closes with the activity — with a live player service the writes will fail | forecast | silence — a by-ear measurement on the phone (A§11); the channel — check and fix together with the player |
| 11 | synchronous disk access in the storage on the main isolate; an empty file counts as ready | reading | empty file — fix; synchronous disk — **rejected** until measured on the phone |
| 12 | `DEVICE_CHECKLIST.md`: some items cannot be carried out as written | reading | rewrite after the app is built on real narration |
| 13 | minor: unused constants; Russian `tts` error texts for en/pl/de; `source .env` | reading | remove the constants; the rest — **rejected** (internal rare errors; `.env` is written by the owner himself) |

## Reviewer 2: queue, sessions, controller (`lib/playback`)

Random runs (8 seeds of 220 commands each, then to the end of the book): not a single twice-paid combination of text and
voice, no more than two requests at once, the end of the book reached in all of them.

| # | Raised | Confirmed | Orchestrator's decision |
|---|---|---|---|
| 1 | while the nearest segment fails, the distant ones are bought up to the end of the book (481 s against a 120 s target) | test | fix; a hole in A§6.3 itself — a limit on all audio ahead was added, including audio beyond a not-ready segment |
| 2 | a failed book deletion: the error is lost, the book stays without narration until restart | test | fix |
| 3 | one unreadable ready file: ready audio does not play, the position skips over the ready text | test | fix: the file is deleted and requested again once |
| 4 | the clock went back during the retry delay — the retry never happens | test | fix |
| 5 | the start waits for a duration probe of all ready audio; the whole ready book goes into the player | test | fix: append up to the reserve target |
| 6 | every command synchronously splits the rest of the book into segments (0.5–0.7 s on a million characters) | test, measurement on the computer | fix: by chapters, as needed |
| 7 | the position is written and listeners are notified 10 times a second | test | fix, as in the prototype |
| 8 | the service "Close" overwrites the position written by the screen after the stop | test | fix |
| 9 | the controller relies on unwritten properties of the fake player; with a player behaving like `just_audio` the end of the book is not announced; there is no playback error event | test | fix: the port contract is written down, the reliance removed, the event added |
| 10 | minor: an unhandled `flush` error; Russian strings as "Google text"; `waiting` flicker at a chapter boundary; paid requests on a full disk | test / forecast | fix |
| 10 | "back" from a starting segment inside a block leads to the previous segment; a timer race during one probe | test / forecast | **rejected**: the interpretation is acceptable; the race is unreachable by hand |
| — | A§5 says "the reading position while listening is the start of the sounding segment", the code and the prototype write an estimate of the place inside the segment | reading | A§5 corrected: the behavior of the code stands |

What was done for the accepted findings is in the git history (branches `s002-ttsfix`, `s002-pbfix`) and in the
Changelog of spec 001.
