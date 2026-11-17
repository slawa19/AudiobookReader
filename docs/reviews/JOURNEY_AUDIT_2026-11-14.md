# User journey check — 2026-11-14

Subject: the clickable prototype (`lib/`, commit `1af7332`), exercised with sequences of two to four reader actions:
reading × listening, shelf ↔ book, "Download chapter", key settings. It was checked by an **independent Claude Opus
agent, not the author of the code**, in a separate worktree; it proved each finding with a failing test and named the
cause in the code at `1af7332`.

**This is an internal check, not an independent review by another engine** (`AGENTS.md`, "Specs and acceptance"): the
model is the same as the author's, so it does not replace the Codex acceptance review.

This file is a record of the check, not a source of truth; the sources remain spec 001, `ARCHITECTURE.md`, the
prototype code and its README.

## Summary in numbers

- 16 findings; 25 user journey tests, of which 20 failed on `1af7332`.
- The tests were transferred to the main worktree without changing the expectations: `test/journey_listening_test.dart`
  (14), `test/journey_shelf_test.dart` (9), `test/journey_download_test.dart` (2), helpers —
  `test/journey_support.dart` (including a controllable clock). Only the comment of one test about FR-P8 was corrected
  (the expectation is the same).
- On the code at `8146607` (the owner's start rule A–E already in) 17 failed and 8 passed before the fixes. Finding 6 —
  all three of its tests — was already closed by the start rule: while the screen follows the voice, the layout is set
  at the voice's place, and while it is being recomputed the screen does not turn pages.
- After the fixes all 25 are green. For decisions a–k and two unchecked hypotheses — `test/journey_decisions_test.dart`
  (20 tests).
- Two hypotheses that the checker did not verify were confirmed by a test on `8146607` and fixed: a second tap on the
  third 40 ms after the first was lost (page +1 instead of +2); the speed from the settings was not taken at start (1×
  instead of the saved 1.5×).

## Finding / what was done

| # | Finding | Cause (verified against the code) | What was done | Test |
|---|---|---|---|---|
| 1 | Listening → pages by hand → table of contents → another chapter: following is off | `_openContents`: `_following = true`, then `goToPage(user: true)` — the manual transition turned it off again | while listening, choosing a chapter is a controller command that turns following on; the voice leads the page, the transition is not manual | `journey_listening_test.dart`: paged by hand → table of contents… |
| 2 | The chapter changed while listening → shelf: "Continue" with the old chapter | the controller wrote the position without the chapter title | `Library.savePosition` derives the chapter and the share from the position itself | `journey_shelf_test.dart`: two tests about the chapter |
| 3 | Timer → "Close" or shelf → later "Listen": a pause at once, "0 min"; the timer carries over to another book | the timer was not cleared when listening ended | the timer is cleared on "Close", on closing the book, on changing the book and when it fires | `journey_listening_test.dart`: timer 15 min → "Close"… |
| 4 | The timer expired on pause → "Listen": a pause again | the expired timer waited for the first audio step | a deadline that expired without audio is cleared (on pause — simply cleared; in `preparing`/`waiting` — pause) | `journey_listening_test.dart`: the timer expired while paused |
| 5 | "Waiting for connection…"/"Preparing the voice…" + paged by hand: no "To current spot" and no chip | the indicator occupied the row | the chip and "To current spot" are always there, the state caption is a separate row | `journey_listening_test.dart`: "Waiting for connection…"; `journey_decisions_test.dart`: k |
| 6 | Re-layout from the start of the page: pause at the bottom + font, pause + 402, "Read from here" at the bottom | the anchor is the start of the page | closed by the start rule (`8146607`), see above; recorded as decision b | `journey_listening_test.dart`: three tests — passed before the fixes |
| 7 | Pause → "Voice" → tap on the selected row: the paragraph restarts | `restartSession` on any tap | restart only when the active voice changes; the same for the model | `journey_listening_test.dart`: the "Voice" screen; `journey_decisions_test.dart`: j |
| 8 | A long press before a page turn: the page leaves, "Read from here" disappears | following turned pages under the selected paragraph | while a paragraph is selected the page does not leave after the voice; when cleared, it catches up | `journey_listening_test.dart`: the long press… |
| 9 | A paragraph selected → the system "Back": the book is closed, the audio cut off | "Back" closed the screen at once | `PopScope`: first the paragraph selection and the panels, then the book; the header button closes at once | `journey_listening_test.dart`: the system "Back"; `journey_decisions_test.dart`: f |
| 10 | The last page → shelf "98 %"; "Close" at the end: 100 % → 98 % | the share is by the start of the page | a "finished" flag in `Library`: set by the last page and the end of listening, cleared by a position earlier than the finishing place | `journey_shelf_test.dart`: "100 %"; `journey_decisions_test.dart`: d |
| 11 | 404 → "Choose model" → another model → back: the just-chosen one is unavailable | the panel took the model from the settings | the error carries the model it occurred on | `journey_listening_test.dart`: error 404… |
| 12 | A new book got the "Continue" card | the shelf sorted the new one as just opened | the card only for a book that has been opened; unopened ones first under it, new ones on top | `journey_shelf_test.dart`: "Continue" is not on an unopened one; `journey_decisions_test.dart`: e |
| 13 | Changed the voice or model — the chapter is still "narrated" | readiness without a profile | the voice profile is in the `isVoiced`/`estimate`/`start` contract; changing the profile stops the task | `journey_download_test.dart`: the first test; `journey_decisions_test.dart`: g |
| 14 | "Stop" at 50 %: the estimate is the price of the whole chapter | what was ready was not counted | the estimate is the not-ready remainder (also after an error) | `journey_download_test.dart`: the second test |
| 15 | Deleted a book → the same file → `Null check`; "+" twice → two instances | the imitation always returned the deleted id; a repeat added a copy | a deleted one is added anew; an existing one is opened; an adding in progress is not duplicated | `journey_shelf_test.dart`: two tests |
| 16 | "Change" → "Done" on an empty field: the key is erased | an empty input was saved as the absence of a key | an empty "Done" does not touch the key | `journey_shelf_test.dart`: the last test |

## Rules for document gaps (proposed by the orchestrator, accepted by the owner on 2026-11-14)

Entered into spec 001 and `ARCHITECTURE.md` and implemented in the prototype. The owner accepted them on 2026-11-14
together with the executor's interpretations (`docs/prototype/README.md`, decisions 22–23); the criterion for clearing
"finished" was refined by the logic review (CODEX_REVIEW_LOGIC_2026-11-14.md, #4): only showing a page earlier than the
last one clears it.

- **a.** Following is turned on by any action by which the user themselves changes or starts the audio place: "Listen"
  (including after a pause and from the error panel), "Read from here", the player's "back/forward", choosing a chapter
  in the table of contents, "To current spot". Only manual paging and the slider turn it off. Choosing in the table of
  contents while listening always moves the voice to the start of the chosen chapter, including the current one. —
  FR-P4, A§5.
- **b.** Re-layout (font, panel height; the theme does not count): while following, the anchor is the voice's place
  (sounding, paused, stopped), otherwise the start of the visible page; while the layout is being recomputed the screen
  does not turn pages. — FR-R7, A§5.
- **c.** The sleep timer is cleared when it fires, on "Close", on closing the book and on changing the book. A deadline
  that expired not during audio: on pause — simply cleared; in `preparing`/`waiting` — pause and cleared. Changing the
  place, the chapter and the voice within the same book does not clear the timer; "until the end of the chapter" is the
  end of the chapter sounding at the moment it fires. — FR-D1, FR-P8, A§6.6.
- **d.** "Finished" is "100 %" when the last page is shown or listening has reached the end; it does not roll back until
  the person has gone back further than the last page. — FR-L4, A§5, A§6.6.
- **e.** The "Continue" card is only on a book that has been opened (the last opened); unopened ones come first under it,
  new ones on top, marked "new"; the rest by opening time. — FR-L4.
- **f.** The system "Back" first closes the temporary things: the paragraph selection, the reading panels, a sheet, a
  dialog; then the book. — FR-R9, A§8.1.
- **g.** "Download chapter": one task; the progress or error block is at the task's chapter even if the reader is in
  another; the offer is at the current chapter and only with no task running; changing the voice or model stops the task
  (what is ready is kept), the offer with a new estimate; after "Stop" and an error the estimate is for the remainder;
  readiness is for the active profile, the contract takes a profile. — FR-D2, A§6.7.
- **h.** A wrong key (400/403 with a key refusal) is a recognized cause: an explanation and "Change key" leading to the
  key field in the settings; "Back" — into the book. — FR-P6, FR-P7, A§6.6, A§8.1.
- **i.** The "End of the book" panel — only "Close". — FR-P6, A§6.6.
- **j.** A tap on an already chosen voice or model changes nothing and does not restart the session. "Done" on an empty
  key field does not touch the key. — FR-V2, FR-P7.
- **k.** In `preparing`/`waiting` the voice chip and "To current spot" stay on the panel; the state caption is a separate
  row. — FR-P4, FR-P6.

## Test expectations the executor disagrees with

None: all 25 were transferred without changing the expectations and run as written.

## Screenshots

Re-shot: the shelf (`01`, `03`, `04`, `05`, `n320-01`, `w360-01`, `l10n-*-01`) — "Война и мир" (War and Peace) in the
demo data is now a never-opened book and stands first under the card; `11` — the text of the demo download error;
`17-player-preparing`, `17-player-waiting` — the voice chip and the caption as a separate row; `18-player-error-other` —
the demo error "other" is no longer about the key. New: `18-player-error-key`.
