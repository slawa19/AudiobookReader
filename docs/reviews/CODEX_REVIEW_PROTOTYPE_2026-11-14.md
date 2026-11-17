# Prototype review — Codex, 2026-11-14

Subject: the clickable interface prototype in Flutter (`lib/`, `test/`, `scripts/`, `docs/prototype/`, commit `53c78d3`),
35 screenshots attached to the prompt; checked against spec 001 and `ARCHITECTURE.md`. Codex 0.167.0-alpha.4.1, model
`gpt-6-astra`, `--sandbox read-only`, 318,668 tokens. Verdict: **REWORK**.

This file is a record of the review, not a source of truth; the spec, `ARCHITECTURE.md`, the prototype code and its
README remain so.

The orchestrator took the decisions on the findings: all 21 were accepted. The executor checked each one against the code
before the fix — all were confirmed, none was wrong. The tests for the findings are `test/review_fixes_test.dart`,
`test/review_fixes_more_test.dart`, `test/pagination_test.dart`. The tests for #1, 2, 3, 5, 11, 12 were run on the code
at `53c78d3` before the fix and failed for the stated reason (#1 — `RangeError`; #2 — `playing` instead of `paused`; #3 —
audio from block 39 instead of 46; #5 — the chapter stayed "narrated"; #11 — block 39 instead of 38; #12 — the footnote
did not open). The finding numbers are the order of the rows of the table in Codex's answer.

## Raised / verdict / what was done

| # | Raised | Verdict | What was done |
|---|---|---|---|
| 1 | a key shorter than four characters crashes the settings (`RangeError`) | accepted | `AppSettings.apiKeyTail` returns a tail of any length; a test |
| 2 | "Read from here" from a pause releases the pause | accepted | the controller contract: `readFrom` changes the place with the previous intent, a pause stays a pause; a test |
| 3 | after an error and manual paging, "Listen" starts from the old place | accepted | `resume` from `stopped` takes the current saved position, from `paused` — the place of the pause; a test |
| 4 | "Close" writes the position while the controller is still active | accepted | a single command `close(screenPosition:)`: the session is finished, then the screen's position is given to the writer; a test that late steps do not overwrite it |
| 5 | clearing does not reset chapter readiness, samples and downloading; book deletion is assembled by the screen | accepted | controller commands `clearAllNarration`, `deleteBookNarration`, `deleteBook`: they stop tasks, reset readiness and samples, update the library; a test |
| 6 | a long heading is not split; a long image caption is drawn beyond the page | accepted | a general line-by-line split for the heading and the caption; the image is fitted together with the first caption line; a test on a synthetic book at 320 dp ×1.3, step 6, checking the rendered height |
| 7 | a chapter without blocks and an empty book break the pages | accepted; the simplest chosen | a section without blocks does not become a chapter (the `Book` model); a book without blocks is not created (`EmptyBookException`, refusal on adding — FR-B6); a test |
| 8 | "Read from here" may go past the edge or under the player | accepted | the position is limited to the visible area above the panel; a test with a paragraph longer than the page |
| 9 | "To current spot" overlaps text (screenshot 15) | accepted | the button inside the player panel; the page ends above the measured panel height; a test |
| 10 | the "Text appearance" and timer sheets do not scroll at 320 dp | accepted | all sheets are limited by the screen and scrollable; narrow sheet screenshots; a test with no overflow |
| 11 | "Listen" skips the visible tail of a paragraph | accepted (orchestrator's decision: as in FR-P3) | start from the first displayed narratable place, including the tail; the page does not go back; a test. **Replaced by the owner's rule of 2026-11-14 (FR-P3, A§5):** reading the tail did not save from paging back and did not remember where the person stopped; now the continuation is from the listening place if it is on the page, otherwise from the first sentence that starts on the page — the tail of a sentence from the previous page is not read |
| 12 | with the panels open a footnote mark only hides the panels | accepted | the footnote is checked before hiding the panels; a test |
| 13 | shared flags of automatic paging with no operation number | accepted | a transition number; the start of a finger drag cancels the automatic transition and following; an interruption test |
| 14 | the book's voice cannot be chosen before the first listening | accepted | a voice chip in the bottom reading panel; a test |
| 15 | chapter titles are cut by an ellipsis and repeated three times | accepted | the chapter only in the reading header, wrapped; removed above the slider and in the player; while the slider is dragged the header shows the destination chapter; a test |
| 16 | the "Sample" is 44 dp, the footnote area does not guarantee 48 | accepted | the "Sample" at least 48 dp, on a narrow screen an icon button; the footnote mark area at least 48 × 48; tests |
| 17 | "narrated" on the chosen chapter — ink2 on hl, 4.2 in sepia | accepted | the chosen row has the main text color; a test in sepia |
| 18 | the tariff date is hard-coded in the screens | accepted | the screens get the price and the estimate ready-made (`Tariffs`, `ChapterDownloads.estimate`), the date comes from the app clock; tests |
| 19 | the download row hides with the panels; the price is inside the button; there is no "Download again" | accepted | the row is always visible (footer, bottom panel, player panel); the estimate as a separate row; after an error — "Download again"; a test |
| 20 | the 402 text promises auto-continuation | accepted | "Top up your balance and tap “Listen” — we’ll continue from this paragraph."; a test |
| 21 | the quotation and the poetry are styled identically | accepted (orchestrator's decision) | poetry — italic with an indent; a quotation — upright, an indent and a line of the `line` color; the rule in the prototype README and FR-R3; a test |

Additionally on the "what will have to be rewritten" part of the answer: the voice sample got an error state with Google's
text; opening a book is protected against a double tap (a test with a slow `loadBook`). The weak tests from the "What the
tests prove" table were strengthened: the place after a font change — by block and offset; following — by the sounding
place inside a block; clearing — chapter readiness, samples and stopping the download; the narrow "player plays"
screenshot was taken in `playing`.

Not done from the answer: chunked pagination, segments instead of blocks, the real `AudioStore` (`has/file/put`) and the
`Library` on disk — this is the implementation of stages 1–2, not the prototype; surrogate pairs, RTL and combining marks
in pagination are not checked (there are none in the demo books).

## Codex's answer

*Translated from the Russian original.*

`lib/` — 31 files, `test/` — 7 files, `scripts/` — 6 files, the README, the spec, the architecture and AGENTS were read in
full. Commit `53c78d3` was checked; I made no changes, `git diff --check` is empty. **All 42 PNGs** actually present in
the directory were viewed: 34 regular, 6 narrow, one each of 360 and 393 dp.

I did not run Flutter. **76 passed tests and a clean analyzer are the operator's evidence**, not my run. Below "by the
code" means a verified execution chain; "forecast" requires the stated reproduction.

**Findings, in order of importance.** Frequency is an estimate of the conditions of occurrence, not usage statistics.

| # | Place and requirement | Defect, concrete input and consequence | Frequency and basis | Confidence | Minimal fix |
|---|---|---|---|---|---|
| 1 | [settings.dart:42](../../lib/library/settings.dart), [settings_screen.dart:87](../../lib/screens/settings_screen.dart); FR-P7 | Enter or paste the key `abc`: it is accepted, then `substring(length - 4)` gets a negative index. Building the settings ends with `RangeError`. | Always for a non-empty key shorter than four characters; code. | High | Safely obtain a tail of any length. A format check must not be the only protection of the display. |
| 2 | [reader_screen.dart:258](../../lib/screens/reader_screen.dart), [fake_narration.dart:65](../../lib/playback/fake_narration.dart); A§6.4, A§6.6 | Pause → long press → "Read from here" calls `start`, which releases the pause and goes to `preparing`, then `playing`. The "pause" intent must be kept. | Every such transition; code. | High | A separate place-change command that keeps the intent inside the controller. Do not fix with a `start(); pause()` sequence in the screen. |
| 3 | [player_panel.dart:55](../../lib/screens/player_panel.dart), [fake_narration.dart:81](../../lib/playback/fake_narration.dart); A§5 | After an error page through the book, then tap "Listen" in the error panel: the screen has already written the new place, but `resume()` starts the old `_block`. An explicit move after `stopped` is ignored. | Every such scenario; code. | High | For `stopped` take the current saved position; for `paused` continue the place of the pause. The difference belongs to the controller. |
| 4 | [reader_screen.dart:267](../../lib/screens/reader_screen.dart); A§5 | "Close" first writes the position **while the controller is still active**, then calls `close`. The order of handing over ownership is violated. With real deferred writes the controller's position may overwrite the user's page. | The order is always violated; the loss of the position is a forecast for asynchronous storage. | High for the violation; medium for the race | One controller operation: finish the session and hand the screen's position to a serialized writer. |
| 5 | [app.dart:61](../../lib/app/app.dart), [shelf_screen.dart:123](../../lib/screens/shelf_screen.dart); A§4, FR-M3, FR-D3 | Clearing changes only the `audio` counter, does not cancel the download and does not reset chapter readiness / the sample cache. After clearing, a previously narrated chapter stays "narrated"; a started task keeps running. Book deletion is split between independent screen calls. | Every corresponding scenario; code. This is already an inconsistency of the prototype, not the absence of real audio. | High | Route clearing/deletion through one controller operation; update tasks, readiness, samples and the library consistently. |
| 6 | [pagination.dart:119](../../lib/reader/pagination.dart), [pagination.dart:135](../../lib/reader/pagination.dart), [book_page.dart:89](../../lib/reader/book_page.dart); FR-R3 | A heading taller than the column is not split. For an image with a long caption only the **accounted** height of the fragment is limited, while `Column` draws the image and the caption in full. The text goes beyond the page and may end up under the panel. | Rare but allowed long headings/captions; amplified at 320 dp and step 6. Follows from the computation and rendering. | High | Split a long heading; fit the image with the caption taken into account, break a long caption into fragments. |
| 7 | [pagination.dart:67](../../lib/reader/pagination.dart), [pagination.dart:107](../../lib/reader/pagination.dart), [reader_screen.dart:116](../../lib/screens/reader_screen.dart); A§3, A§5 | A chapter with `blockCount == 0` gets no pages: its index points to the next chapter or past the end of the list. A book with no displayable blocks gives an empty `pages`, then an access `pages[_page]`. | Only empty structural sections/an empty model; code. There are no such chapters in the demo books. | High | Define the contract: an empty section turns into a heading or is excluded; a fully empty book is rejected before opening. |
| 8 | [reader_screen.dart:491](../../lib/screens/reader_screen.dart); FR-P3, FR-R8 | A long press on a paragraph that takes almost the whole page from its top: the button is placed at `bottom + 8`, with no limit by the screen. It may end up beyond the bottom or under the player. | Long paragraphs, especially a large font; a forecast from coordinates. | High for the absence of the limit | Limit the position to the available area; check a paragraph longer than the page with and without the player. |
| 9 | **Screenshot 15-listening-own-page**, [reader_screen.dart:321](../../lib/screens/reader_screen.dart), [reader_screen.dart:405](../../lib/screens/reader_screen.dart); FR-P4, decision 4 | "To current spot" overlaps the lines "Что ж за беда!" (What kind of trouble is that!) and the next line of dialogue. The page height accounts for the main player but not the return button and other additional elements. | Already visible in the screenshot; repeats on filled pages with following turned off. | High | Build the return into the reserved control area or account for its height in the layout. |
| 10 | [reader_sheets.dart:29](../../lib/screens/reader_sheets.dart), [reader_sheets.dart:270](../../lib/screens/reader_sheets.dart); FR-R8 | "Text appearance" and the timer are non-scrollable `Column`s in sheets with the default height limit. At 320×640 ×1.3, especially with an active timer with an extra row and a turn-off button, an overflow is forecast. There are no narrow screenshots of these states. | Depends on height and scale; a forecast from the tree and the Flutter contract. | Medium–high | A screen-limited scrollable sheet; take both states at 320 dp. |
| 11 | [reader_screen.dart:248](../../lib/screens/reader_screen.dart); FR-P3 | If at the top there is a continuation of paragraph A, and below B begins, "Listen" chooses B. The visible tail of A is skipped. This is a change of the requirement, not a technical necessity. | Every such page boundary; code. | High | Until the owner decides, choose the first displayed narratable block, as FR-P3 requires. |
| 12 | [reader_screen.dart:193](../../lib/screens/reader_screen.dart); FR-R3 | With the panels open, a tap on a visible footnote mark first hides the panels and returns, without checking the footnote. The priority of the link is not observed. | Every such tap; code. | High | Check the footnote before the branch that hides the panels. Test the center of the mark and the extended area. |
| 13 | [reader_screen.dart:124](../../lib/screens/reader_screen.dart); A§5, FR-R2, FR-P4 | The shared `_programmatic` and `_animatingTo` serve several asynchronous transitions with no operation number. If an automatic paging is interrupted by a gesture/a new transition, the old completion may reset the flags of the new transition; a user gesture may be taken for an automatic one. | Quick actions within 320 ms; a race forecast. | Medium | An operation/generation number and turning following off at the start of a user drag. A test with intermediate `pump`s, without waiting for each action to finish. |
| 14 | [reader_screen.dart:611](../../lib/screens/reader_screen.dart), **screenshot 07**; FR-V2 | In the bottom panel before the start there is only the slider and "Listen". The voice **of this book before the first listening** cannot be chosen. | Always in `idle`; code and screenshot. | High | Add an entry for choosing the book voice to this panel, using the existing screen. |
| 15 | [reader_screen.dart:464](../../lib/screens/reader_screen.dart), [reader_screen.dart:595](../../lib/screens/reader_screen.dart), [player_panel.dart:162](../../lib/screens/player_panel.dart); FR-R8 | Chapter titles are limited to one line with an ellipsis. On **n320-07** and **n320-14** this is visible. The FR-R8 exception allows an ellipsis only for the book title and author. | Ordinary long chapters on a narrow screen; screenshots. | High | Wrap the chapter, allow the panel to grow; remove the duplicate caption where it is already shown. |
| 16 | [voice_screen.dart:173](../../lib/screens/voice_screen.dart), [book_page.dart:159](../../lib/reader/book_page.dart); FR-R8 | For the "Sample" `minimumSize.height = 44` and `VisualDensity.compact` are set: there is no 48 dp guarantee. For the footnote `inflate(20)` guarantees only the glyph size +40, not a minimum of 48. A small visible button does not by itself prove a small hit area, so I do not present the exact size here as a measurement. | All samples at ordinary scale; narrow footnote marks. A forecast from the code and the Flutter design. | Medium for the actual area; high for the absence of a guarantee | For the button standard density and a minimum of 48; for the footnote an explicit minimum rectangle of 48×48. Check hit-testing at the edges. |
| 17 | [toc_screen.dart:98](../../lib/screens/toc_screen.dart), [architecture_test.dart:100](../../test/architecture_test.dart); README contrast | The chosen **narrated** chapter draws "narrated" in the `ink2` color on `hl`. In sepia the contrast is **4.1956:1**, and the test excludes this pair under the wrong explanation "not used". | Whenever a narrated chapter is chosen in sepia; code and my own computation. | High | For the chosen row use `ink`; restore the check of the pairs actually used. Changing the palette is not required. |
| 18 | [settings_screen.dart:188](../../lib/screens/settings_screen.dart), [settings_screen.dart:266](../../lib/screens/settings_screen.dart), [toc_screen.dart:126](../../lib/screens/toc_screen.dart); FR-V3, FR-M1 | The tariff date `2026-11-14` is hard-coded in the real screens. After the tariff change on 01.01.2027 stated in the project, the prices will stay the old ones even when the fake services are replaced. | Permanently after the tariff change; code. | High | Pass the clock/date through a simple callback or get a ready estimate from the service. |
| 19 | [reader_screen.dart:422](../../lib/screens/reader_screen.dart), [toc_screen.dart:173](../../lib/screens/toc_screen.dart); FR-D2 | Opening the panels hides the download row and its "Stop". In the table of contents the price is only inside the button, and after an error "Download chapter" remains instead of "Download again". | Every corresponding mode; code, screenshots 10/11. | High | Keep the download status with the panels; move the estimate before the button and distinguish a repeat. |
| 20 | [strings.dart:69](../../lib/screens/strings.dart), **screenshots 18-player-402 and n320-18-player-402**; FR-P6 | "После пополнения чтение продолжится…" (After the top-up, reading will continue…) promises an automatic continuation, directly forbidden by the spec. A separate button does not fix the promise of the text. | Every 402 error; screenshots. | High | "After the top-up tap “Listen”. We will continue from this paragraph." |
| 21 | [page_style.dart:64](../../lib/reader/page_style.dart), [pagination.dart:266](../../lib/reader/pagination.dart); FR-R3 | `verse` and `cite` have the same italic and indent. The internal representation distinguishes them, the visual one does not. | Any book with both kinds of blocks; code. | High | Approve one distinguishing rule for a quotation; apply it in both measurement and rendering. |

For forecasts #10, #13 and #16 primary sources were used: [modal bottom sheet constraints](https://api.flutter.dev/flutter/material/showModalBottomSheet.html), [completion and interruption of the scroll animation](https://api.flutter.dev/flutter/widgets/ScrollPositionWithSingleContext/animateTo.html), [computing a button's area with visual density](https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/button_style_button.dart). This is the justification of the checks, not the result of running the installed version of `material_ui`.

**What will have to be rewritten when the fake implementations are replaced.** The volume estimates refer to the affected
parts of the code, not to measured labor.

| Part | Volume and necessary changes |
|---|---|
| Chunked pagination | **Substantial:** `BookLayout` and the navigation part of `ReaderScreen`. Now the screen requires a full `pages`, final page numbers, `chapterFirstPage` and a synchronous `pageOf`. A window of pages around the position, readiness notifications, cancellation of the computation and transitions by position without knowing all the previous pages will be needed. `_Paginator` and the fragment geometry will largely be kept. |
| Segments instead of blocks | **Medium:** [narration.dart:53](../../lib/playback/narration.dart), following and highlighting in `ReaderScreen`. The pair `block + blockProgress` does not describe a segment of several blocks and a part of a long block. Mappings of a segment to text, its saved start and an estimate of the current place are needed. `BookPage.highlightBlocks` already takes a set — the highlight rendering itself need not be rewritten. |
| The real controller | **Medium:** the commands for starting/changing the place, the chapter, the profile and closing. Now the screen chooses a pause after `start` on a chapter change ([reader_screen.dart:282](../../lib/screens/reader_screen.dart)), passes the position itself on closing and assembles the position from the block progress. Keeping the intent, the session and the position must move into the controller. The visual branches of the six player states are kept. |
| The position on disk and `Library` | **Small in the screens, medium in the storage contract.** A synchronous `positionOf` is acceptable as a memory read; `savePosition` may queue a write. But an explicit guarantee of completion/flushing of the write and serialization are needed. `charsBefore` and `anchorText` can be computed inside the library — their absence in the UI object does not by itself require rewriting the screens. Deletion must be removed from the shelf's independent actions. |
| `AudioStore` | **An extension of the interface, a small change of the screens.** [audio_store.dart:3](../../lib/audio/audio_store.dart) — now only a size counter, not the A§6.5 contract: there is no `has/file/put/clear`. The queue needs these operations; the settings need a notification of a changed size and of the completion of clearing. |
| Voice samples | **Local but mandatory:** [voice_sample.dart:5](../../lib/playback/voice_sample.dart) contains only `idle/loading/playing`, with no error and no Google text. The real service has nowhere to report a permanent error. The state and the sample row in `VoiceScreen` will have to be extended. |
| Opening a book from disk | **Local:** [shelf_screen.dart:89](../../lib/screens/shelf_screen.dart). With a slow `loadBook` there is no protection against repeated opening and no handling of a refusal. A double tap will potentially create two transitions. Check with a controllable unfinished `Future`. |

`ChangeNotifier`, passing dependencies through constructors and `AppServices` are sufficient for this. Introducing a DI
framework or a new state system is not required.

**On the real reader module.**

- For the ordinary text of the demo books no confirmed skipping or duplication from the files was established. Measurement
  and rendering use the shared `fragmentSpan`; the height test has a useful negative check at another width.
- A very long paragraph does not create an obvious infinite loop: [pagination.dart:158](../../lib/reader/pagination.dart)
  forcibly advances by at least a line. This does not prove the correctness of all boundaries.
- **Surrogate pairs are not checked:** Python counted zero characters outside the BMP in both test books. There is no
  ground to claim the pairs break; nor can it be claimed they were checked.
- The weak spot of boundary determination is [pagination.dart:244](../../lib/reader/pagination.dart): the position nearest
  to the left edge is taken as the start of a line.
  [Flutter guarantees the nearest text position](https://api.flutter.dev/flutter/painting/TextPainter/getPositionForOffset.html),
  not the logical start of a line. Cases of RTL/mixed direction, an explicit `\n` at the boundary, emoji and combining
  marks are needed; take the start through the line boundary, then check the monotonicity of the ranges.
- An image by itself, with known natural sizes, is limited in height and keeps its proportions. The defect is the joint
  size with the caption, described above.
- Empty chapters are not handled; chapters with only a heading are handled separately. These are different cases.
- On a font change in ordinary reading the exact `_anchor.block/offset` is used, not a percentage. But while following the
  voice the saved screen anchor is the start of the previous page; after the recomputation the correction toward the voice
  depends on the next controller notification. A separate test is needed for a pause in the middle of a long block.
- Basic tap/swipe and long press are separated by the standard Flutter recognizers. There is no confirmed general conflict
  of these gestures; the concrete problems are the footnote priority and the interruption of the animation.

**The dependency graph was independently checked by imports.** No violations of the inter-module graph of A§2 were found:

| Module | Actual external modules |
|---|---|
| `app` | `audio`, `library`, `playback`, `screens`, `tts` |
| `screens` | `audio`, `book`, `library`, `playback`, `reader`, `tts` |
| `reader` | `book` |
| `playback` | `book`, `library`, `tts` |
| `library` | `book` |

`book` and `tts` do not import Flutter. However, a correct import graph does not prove a correct distribution of
responsibility: findings #4–5 remain violations of A§4–6.

**What the tests prove.**

The number of declared tests with loops unrolled adds up to 76: **7 architectural, 6 pagination, 28 behavior, 35 golden
tests**, creating 42 screenshots.

I do not consider the whole set vacuous. The checks of gestures, deletion from the shelf, display of states and text
height do check behavior. The shortcomings are more specific:

| Place | What is checked more weakly than declared |
|---|---|
| [reader_behavior_test.dart:105](../../test/reader_behavior_test.dart) | The "place is kept" check verifies the presence of the old **block**, but not the offsets. On a paragraph of several pages the test allows a jump inside it. The belonging of the source `(block, offset)` to the new page is needed. |
| [reader_behavior_test.dart:188](../../test/reader_behavior_test.dart) | Following is checked through `containsBlock`. A wrong page of the same long block will pass. The expected position inside the segment is needed. |
| [reader_behavior_test.dart:142](../../test/reader_behavior_test.dart) | The footnote is checked by tapping the mark; there is no neighboring area, open panels or competing paging. Therefore finding #12 goes unnoticed. |
| [reader_behavior_test.dart:262](../../test/reader_behavior_test.dart) | `demoShow` checks the display of an already set state. This is a useful panel test, but not of a transition after an error, buffer exhaustion or network recovery. |
| [reader_behavior_test.dart:243](../../test/reader_behavior_test.dart) | Setting 30 minutes is checked, not the timer expiry, wall-clock time, keeping the timer on a session change and the end of the chapter. |
| [reader_behavior_test.dart:353](../../test/reader_behavior_test.dart) | Clearing checks `totalBytes == 0`. It does not check the disappearance of chapter readiness, the clearing of samples and stopping the download — finding #5 passes. |
| [pagination_test.dart:61](../../test/pagination_test.dart) | The check of range adjacency is useful, but does not require positive progress of each non-empty fragment and does not prove a correct line boundary. The check of the rendered height does not cover all pages and skips images/headings. |
| [screens_golden_test.dart:251](../../test/screens_golden_test.dart) | The narrow test is called "player plays" but calls `demoShow('sleep')`: the screenshot shows a pause with a timer. The `playing` state at 320 dp is not checked by this test. |

There are no checks of a short key, pause → "Read from here", error → manual transition → "Listen", animation
interruption, an empty chapter, a long caption, a very long heading and the sizes of touch areas. At 320 dp the
appearance/timer/model sheets, the table of contents and the voice choice are absent.

**There are no signs of the main font failing to load.** `flutter_test_config.dart:9` waits for the fonts from the manifest
to load; the internal family names and the SHA-256 of all seven TTFs were checked, the sums match `SOURCES.txt`. In the
screenshots Roboto/Merriweather are readable. The golden tests here mask something else: they pin down overlaps and
truncations already present, rather than confirm conformance to the requirements.

**Appearance.** From the screenshots this is already a Material 3 interface: the sheets, buttons, chips, sliders, states
and dialogs are consistent. There is no ground to call the screens as a whole "drawn rectangles". The home-made theme
tiles and the play button use Material/InkWell and need no replacement merely for the sake of a standard class.

The shelf and settings at 320 dp are mostly rebuilt normally; a long book title is shortened within the allowed
exception. The 402 error correctly puts the buttons into a column. The real visual shortcomings are the overlap of the text
by the return button and the truncation of chapters. The overflow of the absent narrow sheets remains a forecast for now.

**Opinion on the 18 README decisions.**

| # | Decision |
|---|---|
| 1 | **Agree:** the frame with the sizes is useful for the web prototype and isolated from the app. |
| 2 | **Agree:** a page shift is simple and sufficient; correct handling of interruption is required. |
| 3 | **Disagree in the current wording:** the panels may overlap the text, but a visible footnote must keep the touch priority. |
| 4 | **Agree:** a permanent player must reduce the page; the whole occupied area must be counted, including additional elements. |
| 5 | **Disagree:** skipping the first visible block contradicts FR-P3 and loses part of the text on moving to listening. |
| 6 | **Agree:** the slider during listening is needed; three simultaneous chapter captions are not. |
| 7 | **Agree:** the shape of the central button distinguishes the states, the icon stays the main signal. |
| 8 | **Agree:** the chip and the inheritance of the voice are clear; the entry before start provided by the spec is additionally needed. |
| 9 | **Agree:** six speeds and a short timer list are sufficient; the timer sheet must scroll when there is not enough room. |
| 10 | **Disagree with the current placement:** a button with no limit by the screen may become inaccessible; a single highlight color is acceptable by itself. |
| 11 | **Agree:** finishing on leaving the book conforms to A§6.6; this is already recorded behavior. |
| 12 | **Agree:** the settings groups and the pencil save room without loss of function. |
| 13 | **Agree:** the states "Continue", "new", "100 %" are distinguishable and do not overload the shelf. |
| 14 | **Agree:** permanent add-error rows with an explicit close suit the task. |
| 15 | **Agree for the epigraph:** the author should not be guessed from the words; this does not cancel the requirement to distinguish a quotation from poetry. |
| 16 | **Agree:** a separate title page of a structural section is predictable; a zero `blockCount` needs separate handling. |
| 17 | **Agree for the prototype:** the built-in Roboto ensures reproducibility; changing the application identifier without a reason is not required. |
| 18 | **Agree:** the available set of rounded icons is sufficient, an additional dependency is not needed. |

**There are actually five contradictions in the README, not four.**

| # | Opinion |
|---|---|
| 1. Strings in `app`, which is forbidden for `screens` | **Agree:** placing them in `screens/strings.dart` is reasonable; A§2 should be clarified. Palettes through passed values keep the module boundary. |
| 2. The settings module | **Agree:** `library` suits storing settings; a string model identifier does not require a dependency on `tts`. |
| 3. The old NOTES versus new decisions | **Agree:** the book scale, the slider during listening and "100 %" must follow the later decision of the owner and the spec. |
| 4. Contrast | **Agree with the number, disagree with the claim of non-use:** 4.1956:1 is confirmed, the chosen narrated chapter uses this pair. |
| 5. FigCraft in AGENTS | **Agree:** if the Flutter prototype replaced the mock-up by the owner's decision, this must be recorded in AGENTS; the rule cannot be considered cancelled merely by the agent's README. |

In addition FR-R3 requires a separate styling of quotations, referring to NOTES, where there is no defining difference.
This must be decided explicitly, not kept as an identical style silently.

**What can be removed without loss of function.**

- The repetition of the chapter title in the header, above the slider and in the player row at once — especially visible
  on **n320-14**. Keep the caption where it explains the corresponding control.
- The tariff computation and the fixed date from the screens: the screen needs only a ready estimate.
- The screen-level session control sequences like `start → pause`: replace with one controller command.
- The duplication of the clearing state between the audio counter, the downloads and the samples: one readiness source
  will reduce the code and eliminate #5.
- At release — the demo menu, the browser frame and the fake implementations. Now they are useful for checking, there is
  no reason to remove them from the prototype.

Keep the palette, the built-in fonts, the simple passing of services and the main composition of the screens. The main
rework items are the position/controller contract, the page boundaries and the checks of awkward states available without
a phone.

REWORK

## Prompt

*The prompt was given in Russian; translated here.*

````text
You are in the same environment as the operator: read files by their paths and compute yourself, you have Python. WSL is closed to you, so you will not run Flutter, tests and the build. DO NOT INVENT measurements; what is not in the files is called a forecast, and you say how to check it. Change nothing.

TASK. An independent review of the clickable interface prototype in Flutter. The app is a book reader for Android with Google Gemini TTS narration, a single user. The prototype is real screen code with fake data: its screens and the pagination module will become part of the app, and the fake implementations (fake_*) will be replaced. Screenshots of the screens are attached to the message (412×915 dp and several 320×640 at font scale 1.3); all 35 are in docs/prototype/screens/.

Range: the repository root, commit 53c78d3 (you have git: `git show --stat 53c78d3`).

WHAT TO READ IN FULL:
- docs/prototype/README.md — what is done, what is simplified, 18 decisions for confirmation, the contradictions found
- all of lib/ (31 files, ≈ 210 KB) and test/
- scripts/
- docs/specs/001-first-version.md, docs/ARCHITECTURE.md (version 3), AGENTS.md

WHAT THE OPERATOR MEASURED: `scripts/test.sh` in WSL — the analyzer clean, 76 tests passed (re-run by the orchestrator after the agent); the web build answers 200 on 127.0.0.1:8642. Nothing was run on the phone. The agent claims that it viewed every screenshot; the orchestrator viewed two.

KNOWN SIMPLIFICATIONS (do not report them as findings, but say if a simplification is built in such a way that replacing it will require rewriting the screens): the book is split into pages whole, not in chunks (A§5); the position is only in memory; the narration unit is a block, not a segment of A§6.1; there is no audio and no media session; the Material system captions are not localized.

THE OWNER'S PRINCIPLES: simplicity (no state frameworks, DI, code generation — A§8, A§10); the minimum of interface elements; a failure is shown by a panel state, not a pop-up window; everything that can be, is checked without a phone; tests must not pass vacuously.

QUESTIONS:
1. Reusability. Which parts of the screen code and `reader` will have to be rewritten when the fake implementations are replaced with real ones (chunked pagination, segments instead of blocks, a real NarrationController with the states of A§6.6, the position on disk, the position owner of A§5)? Where does the screen itself take decisions that per A§6.6 belong to the controller? Where will the interfaces (`lib/playback/narration.dart`, `lib/library/library.dart`, `lib/audio/audio_store.dart`) not withstand a real implementation?
2. Correctness of what is already real: `lib/reader/pagination.dart` and `book_page.dart` (loss or duplication of text at a page boundary, surrogate pairs, a very long paragraph, an image taller than the page, an empty chapter, a font size change with keeping the position); the paging gestures in `reader_screen.dart` (a conflict of tap, long press, swipe and footnote link; paging during an animation); following the voice and "To current spot".
3. Conformance to the spec and the architecture: what is implemented contrary to FR-* or A§ (name the identifier); the dependency graph of A§2 — check the imports yourself by files.
4. Tests: which of the 76 pass vacuously or check the fake implementation instead of the screen behavior; which declared behavior is not covered; do the golden screenshots mask a defect (for example, the font did not load).
5. Appearance from the attached screenshots: cut off or overlapping text, touch targets smaller than 48 dp, inconsistency of identical elements, a place where the screen breaks at 320 dp. The owner called the previous static mock-up "outdated in its elements" (he kept the palette and fonts): are there screens that still look like hand-drawn rectangles rather than Material 3 components?
6. Eighteen decisions from the README and four contradictions in the documents: for each — agree / disagree, in one line with the reason.
7. Superfluous: what in the code and on the screens can be removed without loss of function.

ANSWER FORMAT (in Russian):
A table of findings from the most important to the least important: file:line (or screenshot number), requirement or section, what the defect is, under what concrete input or action it will show up and how it will end, how often (an estimate and what it rests on: code, Flutter documentation or assumption), confidence, minimal fix. A finding with no file:line or screenshot number does not count.
Separately: what will have to be rewritten (question 1) — as a list with a volume estimate; the opinion on the 18 decisions and 4 contradictions; superfluous.
If a part is fine — one line. An objection with a concrete reference is worth more than agreement.

The last line — the verdict, exactly one word in capitals: ACCEPT or REWORK.
````
