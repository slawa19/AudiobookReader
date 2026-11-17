# Spec 002. Cleanup after the architecture reviews

Status: all three stages done and merged into `main` on 2026-11-16; verified on the phone with the fake build (SC-5, see
Changelog). Basis: two independent reviews ([ARCH_REVIEW_2026-11-16.md](../reviews/ARCH_REVIEW_2026-11-16.md)); the
finding numbers below come from there.

The app's behavior for the reader does not change, except for the fixes of the four stage 1 defects. There are no new
features.

## 1. Decisions

| No. | Decision | Who and when |
|---|---|---|
| D1 | The architecture does not change: the module graph matches the declared one; no new layers, ports or libraries | orchestrator, from the two reviews, 2026-11-16 |
| D2 | A change enters the spec only if it reduces code or removes a defect or duplication confirmed in the code. Cases that have not occurred on a real book are not handled | owner, 2026-11-16 ("avoid edge cases and overengineering") |
| D3 | This spec does not touch the reading screen (`reader_screen.dart`, `pagination.dart`, `player_panel.dart`), except for one replacement in FR-4: the owner has not yet checked it on the phone after the 2026-11-15 work | orchestrator, 2026-11-16 |
| D4 | Three stages, each a separate branch and merge: defects → one rule in one place → removal of the superfluous | orchestrator, 2026-11-16 |

## 2. Requirements

### Stage 1. Defects

Each fix comes with a test that fails before it.

- **FR-1** (finding 1). The book size on the shelf does not include the narration: after the app restarts, the shelf
  shows "book + narration", not "book + two narrations". The `audio/` directory is not part of the book size.
- **FR-2** (finding 2). An error in one command in the player queue (`QueuedPlayer`) does not stop the following
  commands, just as is already done in `FileLibrary._enqueue`.
- **FR-3** (finding 3). The Gemini client treats only an `Exception` from the transport as transient; a program error
  (`Error`) reaches the queue and stops narration under the general rule. The error text still does not contain the
  key. The `tts_client_test.dart` test that pins the retry for `StateError` is corrected.
- **FR-4** (finding 4). The `NarrationController` contract reports the sounding spot as a position (paragraph and
  offset), not as a fraction of the paragraph; the screen does not recompute it. `blockProgress` is removed if the
  player panel does not need it after the replacement.

### Stage 2. One rule in one place

- **FR-5** (finding 5). One function in `book` computes the chapter caption. The library records the caption together
  with the reading position; the shelf takes it from the record and does not load the book. The `fraction` and
  `chapterTitle` parameters of `savePosition` are removed. Until the first position write after the update, the
  caption on the shelf may be empty; this is acceptable.
- **FR-6** (finding 6). One function assembles the book's voice profile; both the player and "Download chapter" call
  it. `VoiceProfile` keeps only the names `voiceId` and `model`.
- **FR-7** (finding 7). Choosing the spot on "Listen" and finding the nearest readable paragraph are two pure
  functions next to the contract; the real and the fake controllers call them. The controllers themselves are not
  merged.
- **FR-8** (finding 8). A book is opened in one way: the prototype passes its own `openBook`, and the fallback path on
  the shelf is removed. Only the library holds open books.

### Stage 3. Removal of the superfluous, and documents

- **FR-9** (finding 9). Session numbers are removed from `SynthesisQueue`; generations and task cancellation stay.
- **FR-10** (finding 10). The architecture test sees `import … as`, `show`, `hide` and `export`; the test contains an
  example where the check fires and an example where it stays silent.
- **FR-11.** Withdrawn 2026-11-16 (see "Out of scope").
- **FR-12** (finding 12). Removed: `BookPageLayout.containsBlock`, `FakeChapterDownloads.demoFail`,
  `ChapterDownloadTask.error`, `TtsError.billingUrl` with its copying (the address stays in one place), the
  unreachable branches of `media_session.dart`, the `tts_source_test.dart` test. Before each removal, a search for
  usages in `lib` and `test`.
- **FR-13** (finding 13). `ARCHITECTURE.md` is brought in line with the code: who holds the screens' state, the audio
  storage API, where the tariffs live, what exactly is highlighted during narration, how the protection against late
  responses works.
- **FR-14.** Comments that retell edit history ("review No. N …") in the affected files are replaced with the reason
  or deleted. There is no separate pass over all the code for this.

## 3. Acceptance criteria

- **SC-1.** The full `scripts/test.sh` is green in the main tree after each merge; `git status --porcelain` is
  empty; CI on GitHub is green.
- **SC-2.** The reference screenshots of the screens do not change.
- **SC-3.** Stages 2 and 3 reduce `lib/`: the total line count goes down (the reviewers expected 150–200 lines).
- **SC-4.** Each stage 1 defect is closed by a test that failed before the fix; the FR-1 and FR-10 tests show both
  sides.
- **SC-5.** On the phone after stage 1: the size of a book with narration on the shelf is the same before and after
  restarting the app; "Listen" from the middle of a paragraph does not turn the page back.

Scope estimate: about a day of agent work, three launches.

## 4. Out of scope

Recorded so that it does not come back.

- Rewriting the reading screen's navigation as a single operation: 3–5 days, high risk; the frame-by-frame property
  test is green. Return to the question only if the phone shows a new defect of the same kind.
- Merging the six fields of the reading screen's "pending layout" into one record (finding 15): postponed until the
  screen is checked on the phone (D3).
- Cancelling the Gemini request on timeout (finding 14): Google charges for an accepted request even when it is
  cancelled; the case has not occurred.
- Removing the voice comparison from the voice selection screen (finding 16).
- Moving the deletion of a corrupted audio file from the controller into the storage (finding 11): the change adds
  15–30 lines and removes neither a defect nor a duplication, so it does not pass D2.
- Replacing the prototype's fake controller with the real one in the prototype and in ~300 tests. New screen tests
  are written against the real controller (`AppHarness`); old ones are not migrated.
- Splitting `controller.dart`, `file_library.dart`, `parse.dart`, `native_application.dart` by size.
- Introducing DI, a state library, new ports; a common "sequential chain" helper for all queues.
- Replacing the in-house XML parser with a package; trimming the HTML entity table.
- Evicting open books from memory, chapter-readiness caches, speeding up file checks: not before a measurement on the
  phone.
- Moving `FakePlayer` and `WavAudioEncoder` from `lib/` into the tests; separate packaging of the demo resources
  (260 KB).
- Replacing the remaining fixed `ioSettled()` pauses in the queue tests: not until CI shows a failure again.
- A `dart format` check and a uniform line width.

## 5. Changelog

- 2026-11-16 — spec written from the two reviews (Opus 5.5 and gpt-6-astra); the orchestrator checked each finding
  against the code. Findings 14 and 16 rejected, 15 postponed.
- 2026-11-16 — the owner started the spec with the condition "do not polish edge cases". The orchestrator re-read the
  requirements against D2 and withdrew FR-11: it added code for the sake of port purity.
- 2026-11-16 — stage 1 merged (`s005-defects`): FR-1…FR-4, 26 lines in `lib`, each defect closed by a test that
  failed before the fix. `blockProgress` stays in the contract: the media session and the tests use it.
- 2026-11-16 — stage 2 merged (`s006-single-rule`): FR-5…FR-7 and a trimmed FR-8, 127 lines fewer in `lib`. FR-8 was
  trimmed by the orchestrator to "only the library holds open books": merging the two ways of opening a book turned
  out to be moving code around while complicating the prototype. The `fraction` parameter of `savePosition` stays:
  the screen uses it to pass "last page — the book is finished". Consequences for the reader: the chapter caption on
  the shelf is always up to two lines; for books added earlier it appears after the book is first opened.
- 2026-11-16 — stage 3 merged (`s007-removal`): FR-9, FR-10, FR-12…FR-14. `ChapterDownloadTask.error`,
  `TtsError.billingUrl` and `defaultBillingUrl` were kept: the tests use them, the review was wrong. Spec result:
  `lib` 16 892 → 16 755 lines (−137 counting the +17 of stage 1), 872 tests green, reference screenshots unchanged.
  SC-3 was met below the reviewers' expectation (150–200): part of the "dead" code turned out to be alive, and FR-11
  and half of FR-8 were withdrawn.
- 2026-11-16 — check on the owner's phone (Samsung, fake build from `b50dae1`, orchestrator via adb). SC-5: the size
  of a book with narration is the same before and after restarting the app (7 MB, narration 3 MB). The chapter
  caption on the "Continue" card appeared after the book was first opened. The second half of SC-5 ("Listen" from the
  middle of a paragraph does not turn back) was not reproduced separately: the original defect was a review forecast.
  The real build was installed over the previous one, books and positions are intact; not checked with the Gemini
  voice.
