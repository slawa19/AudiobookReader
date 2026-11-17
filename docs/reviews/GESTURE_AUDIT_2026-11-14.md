# Gesture check — 2026-11-14

Subject: the clickable prototype (`lib/`, commit `6315a74`), exercised with **real pointer events**: a finger with
timestamps (the speed is visible to the recognizers, as on a phone), follow-up taps, angled swipes, drags with a return,
a second finger, the slider, the system "Back", touch targets hit-tested at the corners of 48 × 48.
It was checked by an **isolated Claude Fable 5.2 agent, not the author of the code**, in a separate worktree.

**This is an internal check, not an independent review by another engine** (`AGENTS.md`, "Specs and acceptance"): it
does not replace the Codex acceptance review.

This file is a record of the check, not a source of truth; the sources remain spec 001, `ARCHITECTURE.md`, the
prototype code and its README.

## Summary in numbers

- 9 findings; 45 gesture tests (`test/gesture_page_test.dart`, `gesture_layers_test.dart`, `gesture_slider_test.dart`,
  `gesture_listening_test.dart`, `gesture_screens_test.dart`, `gesture_targets_test.dart`, helpers —
  `gesture_support.dart`); on `6315a74` 15 failed and 30 passed (re-verified by the executor after the transfer).
- After the fixes, 44 transferred tests and one replaced by decision F (see below) are green. For decisions A–J and the
  paths the checker did not walk — `test/gesture_decisions_test.dart` (22 tests).
- The causes named by the checker were verified by the executor against the code — all nine were confirmed.

## Finding / what was done

| # | Finding | Cause (verified against the code) | What was done | Failing tests |
|---|---|---|---|---|
| 1 | Double tap on "Listen": the second lands on whatever came up under the finger (speed, "back", pause, "forward", timer); the same for "Close", "Stop", a choice in the speed and timer sheets | the bottom panel is replaced by the player panel in the same frame; a closing sheet lets taps through to the screen under it | one general rule — protection against a follow-up tap (decision A): the reader screen absorbs taps for 350 ms after a layer change, a sheet — for the first 350 ms after opening, the screen — after a sheet, dialog or screen on top closes | `gesture_listening_test.dart`, `gesture_layers_test.dart`: "Listen" twice (412 and 320), "Listen" anywhere on the button, "Close" twice, a double choice in a sheet, "Stop" twice |
| 2 | Selected a paragraph → swiped: the selection is invisible, the first tap is swallowed, "Back" does nothing visible; while listening the screen gets stuck | the selection outlived the page it was made on; with a selection, following does not turn pages | the selection is cleared on any page change (decision B) | `gesture_page_test.dart`: selected a paragraph and swiped — the next tap turns the page; "To current spot" returns to the voice |
| 3 | The page moved after the voice, the finger returned it — a fraction of a second later it moves away again | a gesture that returned to the same page did not turn following off | a finger that lands on the page during an automatic page turn turns following off even if it returned the page (decision C); determined at the moment of the touch — by the start of the drag the turn has already stopped | `gesture_page_test.dart`: the page moved after the voice, the finger returned it |
| 4 | An almost vertical swipe (10° from vertical, 45 dp sideways) turns the page | the horizontal page recognizer accepts a gesture by its horizontal shift without looking at the vertical one | a recognizer of a "mostly vertical" gesture inside the page (deeper than paging, sees the movement first): it takes the gesture when the vertical shift exceeds the threshold and exceeds the horizontal one (decision D) | `gesture_page_test.dart`: a vertical swipe drifting sideways |
| 5 | No key → "Listen" → key typed by hand → "Back": the key is not saved | saving happened only on "Paste" and the keyboard action | a non-empty value is saved on any exit from the field and from the screen (decision E): `PopScope` of the settings screen and loss of the field's focus | `gesture_screens_test.dart`: the key typed into the field → the system "Back" |
| 6 | Landscape orientation: the text and the player sit under the side cutout | rotation is not decided anywhere | portrait only: the manifest and `lockPortrait()` at start (decision F) | landscape with a side cutout — replaced (see below) |
| 7 | Two footnote marks side by side: a tap on the second opens the first | the first mark whose 48 × 48 area contains the point was returned | the mark nearest to the touch point (decision G) | `gesture_targets_test.dart`: two footnote marks side by side |
| 8 | Touched the slider thumb and let go without moving: following is off | `onChangeEnd` always turned following off (a comment in the code claimed "even if the page is the same") | releasing on the same page changes nothing; the comment removed (decision H) | `gesture_slider_test.dart`: touched the thumb and let go without moving |
| 9 | The corners of the "Stop" area in the download strip are cut | a `Material` with a rounded shape hit-tests by the shape | the strip's shape is only drawn (`ShapeDecoration`), the "Stop" area is a 48 × 48 rectangle (decision I) | `gesture_targets_test.dart`: the player panel (412 × 915), "Stop" of the download strip |
| — | The corner of "Back" in the header is cut by ≈ 1 dp (a side remark) | the outermost buttons are 4 dp from the edge, the lower corner of the area reached into the 24 dp rounding | the header's side margins 8 dp — one line | — (within the test tolerance) |

**Tests brought in line with the decisions** (the checker's expectation differed from the decision):

- `gesture_layers_test.dart`, the test of the panels + footnote combination (sheet, then panels, then book) → "sheet,
  then book": by decision J, with panels shown "Back" closes the book, and "Back" must no longer hide the panels.
- `gesture_layers_test.dart`, the test of "Back" in the middle of the speed sheet animation and in the middle of a page
  turn: after a tap on the third the panels are hidden — by decision J the first "Back" shows them, the second closes
  the book.
- `gesture_screens_test.dart`, the test of the book touched twice in a row: the same change — two "Back" taps to the
  shelf.
- `gesture_screens_test.dart`, the landscape orientation with a side cutout test, was replaced by a test that landscape
  is not enabled (decision F): the app asks the system only for portrait, the manifest has
  `screenOrientation="portrait"`.

Also brought in line with the decisions were the tests of earlier checks: rule f of the journey check
(`journey_decisions_test.dart`) — to decision J; three tests that touched a just-appeared panel or strip 400 ms after an
event (`reader_behavior_test.dart` — two, `screens_golden_test.dart` — 19–20 and 21) now wait 600 ms: the panel appears
on screen a frame after the event, and the tap fell inside the 350 ms.

## Orchestrator's decisions

Entered into spec 001 (decisions D10–D12, FR-R2, FR-R3, FR-R5, FR-R7, FR-R8, FR-R9, FR-P4, FR-P7, FR-P9, FR-D2, "Out
of scope"), `ARCHITECTURE.md` (A§5, A§7, A§8.1) and the prototype README.

- **A.** Protection against a follow-up tap is one general rule: after a layer changes under the finger (reading panel ↔
  player panel, a sheet or dialog closed, the player panel disappeared, the download strip disappeared, the screen
  changed), the new controls and the page accept no touches for 350 ms; a named constant `layerSettleTime`; a normal
  pace (an interval over 350 ms) works.
- **B.** A paragraph selection is cleared on any page change — by gesture, tap, slider, table of contents, voice.
- **C.** A finger that grabs the page during an automatic turn after the voice turns following off even if the page came
  back; outside an automatic turn, a gesture that returned to the same page changes nothing.
- **D.** Only a gesture whose horizontal shift is greater than the vertical one at the moment of recognition turns pages
  (the angle to the horizontal below 45°); verified at 10°, 30°, 44° (turns) and 46°, 60°, 80° (does not turn).
- **E.** Key: a non-empty value is saved on any exit from the field and from the screen; an empty field does not touch
  the key.
- **F.** Portrait orientation only — manifest, code, spec (decisions and "Out of scope").
- **G.** Footnotes: the mark nearest to the touch point opens.
- **H.** Slider: a touch without a shift changes nothing.
- **I.** "Stop" of the download strip: the 48 × 48 area is a rectangle.
- **J.** The system "Back" while reading: clear the paragraph selection → close a sheet, dialog, footnote → panels
  hidden — show them → panels shown — close the book; the arrow in the header closes at once; the same while listening.
  The reason is the Android edge gesture. Replaces rule f of the journey check.
- **K.** The manual phone check list (FR-P9) is extended with gestures; they are checked already at stage 1 on the first
  install.

## Paths the checker did not walk (added by the executor)

A second finger during a swipe — no more than one page, no exceptions; scrolling the table of contents with a finger and
tapping a chapter — that chapter is open; the book deletion dialog under the system "Back" — the dialog is closed, the
book stays on the shelf; a language change with the "Text appearance" sheet open — the sheet is open and already in the
new language. All four passed the first time.

## Forecasts for the phone and how to check them

The main risk by the checker's estimate: with Android gesture navigation, a swipe from the screen edge is the system
"Back"; before decision J it closed the book in immersive reading and cut the audio, and a reader paging from the edge
would close the book. After J the first "Back" only shows the panels. Confirmed only on the phone — the FR-P9 items, at
stage 1 already:

- 20 page turns by a swipe from the very edge in both directions — while reading and while listening, including in a
  case: the book does not close;
- slowly pull from the edge and return: the book does not close, the page stays in place;
- 20 vertical thumb movements: the page does not turn (rule D is verified in tests on straight lines; the arc of a
  thumb on glass — only on the phone);
- the text is not under the camera cutout, the bottom row of the player panel is not in the "home" gesture zone.

## The checker's assessment (verbatim)

"the state logic is checked sufficiently, the gestures are not... what is missing is a check on the owner's phone — the
edge "back" gesture and the vertical swipe are decided only there".
