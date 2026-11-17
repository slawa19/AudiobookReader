# Two independent code reviews: architecture, separation of concerns, duplication, quality — 2026-11-16

Requested by the owner. The reviewers — Claude Opus 5.5 and Codex `gpt-6-astra` (high) — worked in parallel on `main`
at `3b71e04`, each in its own worktree, from one brief, without knowing about each other. This is a reading review: the
tests were not run. The brief carried an owner constraint: no edge cases and no overengineering — a proposal is
acceptable only if it reduces code or removes a named risk. The orchestrator checked every finding against the code
itself (the "Check" column). This file is not a source of truth; the follow-up work is
[spec 002](../specs/002-cleanup-after-reviews.md).

## Where they agreed

1. **Modules depend on each other as declared.** Both built the import graph between the `lib/` directories and got the
   same result: every edge is allowed by section 2 of the architecture, there are no cycles, and `book` and `tts` have
   no Flutter.
2. **The weak spot is the seams between slices.** The slices were written by different agents in parallel; the same
   decision was left in two or three places: the chapter caption, the voice profile, the "Listen" rule, opening a book.
3. **Failure paths are done well:** late replies, deletion during a write, atomic writes, the key in error texts.
4. **Not needed:** rewriting the reader screen navigation, splitting large files by size, introducing layers, DI and a
   state library, merging the real and fake controllers, replacing our own XML parser with a package.
5. The reader screen and the player are the weakest parts in quality; the prototype's fake controller serves a large
   share of the screen tests, and such tests do not prove the behavior of the real player.

## Findings

| # | What is wrong | Who | Orchestrator's check | Decision |
|---|---|---|---|---|
| 1 | After the app restarts, the book size on the shelf counts the narration twice: the book folder size includes `audio/`, and the screen adds the narration again | Astra | confirmed: `file_library.dart:166,671`, `shelf_screen.dart:152,486` | spec 002, FR-1 |
| 2 | The player command queue does not survive an error: after a single player release failure, all following commands silently do not run | both | confirmed: `queued_player.dart:101-103`; `file_library.dart:537-541` does the same thing correctly. The likelihood of a failure is a forecast | FR-2 |
| 3 | The Gemini client declares any exception a transient network error, including a program error; the queue retries the request. A test pins this down | both | confirmed: `gemini.dart:111-114` | FR-3 |
| 4 | The controller gives the audio position to the screen as a paragraph fraction, the screen converts it back to an offset and in some cases ends up one character short; the controller knows the exact position | Opus | code confirmed: `controller.dart:95-98`, `reader_screen.dart:703-708`; the loss measurement (3.8 % of pairs) is the reviewer's; the consequences for the reader are a forecast | FR-4 |
| 5 | The chapter caption for the shelf is computed in three places and the results differ; for it the shelf loads the whole book; the real library ignores the `fraction` and `chapterTitle` parameters | both | confirmed: `file_library.dart:698-708`, `common.dart:108-128`, `fake_library.dart:257`, `shelf_screen.dart:273-291` | FR-5 |
| 6 | The voice profile is built by two identical formulas (the player and "Download chapter"); `VoiceProfile` has two sets of parameter names | both (Astra — only the names) | confirmed: `controller.dart:133-137`, `file_chapter_download.dart:39-43`, `voices.dart:101-115` | FR-6 |
| 7 | The "Listen" rule and the search for the paragraph to read are written twice — in the real and in the fake controller — and the texts have diverged | Opus | confirmed: `controller.dart:148-178` and `fake_narration.dart:107-137` | FR-7 |
| 8 | Opening a book is written as two paths (the shelf and the composition root); open books are cached in two places | Opus | confirmed: `shelf_screen.dart:112-133`, `native_application.dart:371-397` | FR-8 |
| 9 | Session numbers in the synthesis queue are passed and copied, but take part in no decision | Astra | confirmed by searching for `session` in `synthesis_queue.dart`: only declarations and passing | FR-9 |
| 10 | The architecture test does not see `import … as x;` and `export` | Astra | confirmed by reading the expression: `architecture_test.dart:21` | FR-10 |
| 11 | The controller deletes the audio file itself, bypassing the storage | both | confirmed: `controller.dart:580-585` | FR-11 |
| 12 | Dead code: `containsBlock`, `demoFail`, the `TtsError.billingUrl` chain, `ChapterDownloadTask.error`, unreachable branches of `media_session.dart`; a test that reads source code (`tts_source_test.dart`) | both | spot-checked by searching for usages | FR-12 |
| 13 | The document diverges from the code: `ShelfController`/`ReaderController`, the audio storage API, the place of the tariffs, the highlighting of "the blocks of the sounding segment", the description of sessions | both | highlighting and tariffs confirmed; the rest — from the reports | FR-13 |
| 14 | The Gemini request timeout frees a place in the queue although the request may still be running | Astra | code confirmed (`gemini.dart:108`), harm is a forecast | **rejected**: a request accepted by Google is billed even when cancelled; a 30–60 line change for a case that has not occurred |
| 15 | Reader screen: the "pending layout" is six parallel fields, not all of them are reset | Opus | confirmed: `reader_screen.dart:39-52,231-251` | **deferred** until the screen is checked on the phone: the owner has not yet checked the screen after yesterday's work |
| 16 | "Whether to restart the same voice" is decided by both the screen and the controller | Astra | confirmed | **rejected**: the interface is protected, the gain is 5–15 lines at medium risk |

## Where they diverged

- **Chapter caption.** Opus: compute it when the position is written and store it; Astra: merge only the parent lookup.
  Opus's option was accepted — it alone removes the shelf loading the book.
- **Scores.** Astra is more generous (tests 4, `app` 4, `library` 4), Opus is stricter (tests 3, `screens` 2.5). The
  difference on tests is in the weight of one fact: 31–32 screen test files run on the fake controller.
- **Unexpected transport error.** Astra proposes listing the known transient errors, Opus — one line (`on Exception`).
  Opus's option was accepted.

## Codex code quality

Scores on a five-point scale, Opus / Astra:

| Directory | Opus | Astra | Main point |
|---|---|---|---|
| `book` | 4 | 4 | general rules, no book-specific literals |
| `tts` | 4 | 3 | pure Dart, key scrubbing; crude classification of transport errors |
| `audio` | 4 | 4 | atomic file publication |
| `platform` | 4 | 4 | thin layer |
| `reader` | 3.5 | 4 | the layout is clear |
| `library` | 3.5 | 4 | one writer, atomic writes; state in raw `Map`s |
| `app` | 3 | 4 | the composition root also does other people's work; duplication with the prototype |
| `playback` | 3 | 3 | generations are tidy; many flags, a duplicate of the contract |
| `screens` | 2.5 | 3 | reader screen: about 49 mutable fields, decisions hold on the order of calls |
| tests | 3 | 4 | not vacuous; a large share runs on the fake controller and on the screen device |

**Orchestrator's conclusion: 3.5 out of 5.** Better than a human usually manages in two days: failure paths, test
density, decisions tied to the spec, no fitting to books and no needless scaffolding. Worse: the code accumulates flags
and special cases instead of being restructured (the reader screen, the player queue); duplicates remain at the seams
of the parallel slices; compatibility is solved with synonyms rather than renaming; comments retell the edit history
("№8 of the logic review"); a test sometimes pins down wrong behavior. The second half is equally a consequence of
acceptance: the orchestrator accepted the slices by tests and reports and did not do a pass across the slices.
