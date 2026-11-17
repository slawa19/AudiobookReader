# Behavior logic review — Codex, 2026-11-14

Subject: the behavior logic of the clickable prototype (screens, the narration controller contract, fake
implementations, user journey tests) and the consistency of spec 001 with `ARCHITECTURE.md`; commit `2fc63a4`. Codex
0.167.0-alpha.4.1, model `gpt-6-astra`, `--sandbox read-only`, 268,800 tokens. Verdict: **REWORK**.

This file is a record of the review, not a source of truth; the spec, `ARCHITECTURE.md`, the prototype code and its
README remain so.

Decisions on the findings: #1–4, 7–10 — the "minimal fix" from the answer; #5 and #6 and the "To current spot" section
are orchestrator decisions; the sentence boundary rules (i) and (ii) are an orchestrator decision; the sections on
documents, uncovered paths and weak tests were handled by the executor. The executor checked each finding against the
code before the fix — all ten were confirmed. The tests are `test/logic_review_test.dart` (one for each of the ten
findings and for dragging): 18 of 20 failed on `2fc63a4` for the stated reason; two control tests (an automatic
transition does not turn following on; a drag that changed the page turns following off) passed both before and after —
they guard against the fix overshooting. A unit test of `speechText` was added afterwards (this function did not exist on
`2fc63a4`). The result of `scripts/test.sh` after the fixes: the analyzer clean, 225 tests passed. The numbers are the
order of the rows of the table in Codex's answer.

## Raised / verdict / what was done

| # | Raised | Verdict | What was done | Failed on 2fc63a4 |
|---|---|---|---|---|
| 1 | After a stop, manual paging does not turn following off: a re-layout and "Close" bring back the place of the stop | accepted, confirmed (`_onPageChanged` checked `isActive`) | manual movement turns following off with any open panel of this book, including `stopped`; three tests: error → paging → "Close", error → paging → font, end of the book → paging back → "Close" | yes, all three |
| 2 | Changing the voice or model after a start from a sentence inside a block reads the paragraph from its beginning | accepted, confirmed (`restartSession` → `_moveKeepingIntent(block)` zeroed `_unitStart`) | restart with the full unit start position (block and offset) | yes |
| 3 | A held paragraph selection is lost on a re-layout caused by a change of the panel height | accepted, confirmed (the re-layout went from the voice's place) | the selection remembers its place (`_selectedAt`), the re-layout sets it ahead of following | yes |
| 4 | "Finished": a one-page book does not get 100 %; listening again to the last paragraph clears 100 % | accepted, confirmed; plus a contradiction between the spec and A§5 | "finished" is a separate fact `Library.isFinished/setFinished`: set by showing the last page (including by the first layout) and by the end of listening, cleared only by showing a page earlier than the last; `atEnd`/`screenAtEnd` removed | yes, both |
| 5 | Commands from outside (headset, notification) do not turn following on — the screen turned it on in its wrappers | accepted (contract) | `NarrationController.commandRevision` — a counter of explicit commands; the screen turns following on when it changes; automatic transitions do not touch it; recorded in A§5, A§6.6 | yes, both; the "automatic transition" control passed |
| 6 | A footnote mark after a period hides the start of the next sentence | accepted, confirmed | `lib/book/speech_text.dart` — a minimal `speechText` (without `noteRef` and stress marks, with offsets mapped back); the boundaries are searched in it | yes |
| 7 | A: the "until the end of the chapter" timer is not cleared at the end of the last chapter; B: an expired minute timer after an error pauses a new "Read from here" | accepted, confirmed (the end-of-book branch exited earlier; `readFrom` did not clear the expired deadline) | the end of the last chapter clears the timer; before every explicit command an expired deadline is cleared by a single handler | yes, both |
| 8 | The saved speed is shown in the caption, but the voice moves at speed 1 | accepted, confirmed (`_duration` took `_speed`) | a single source of speed | yes |
| 9 | After "Clear narration" new narration is not visible in the volume — deletion is unavailable | accepted, confirmed | the fake storage counts what was downloaded and the samples (`FakeAudioStore.addBook/addSamples`) | yes |
| 10 | The sample is cached by voice and phrase without the model | accepted (contract), confirmed | `VoiceSampler.play(VoiceProfile, bookLanguage:)`, the cache by profile and language | yes |
| — | "To current spot" right after "Listen": the start of a drag turned following off even before the page changed | accepted (orchestrator's decision) | following is turned off only by a gesture that changed the page, and by the slider; while a gesture is in progress, the voice does not turn the page; tests: a small drag with a return, a cancelled gesture, a gesture during the appearance of the panel; the control "the gesture changed the page" | yes, three; the control passed |
| — | Sentence boundaries: "г. Москве", initials, "… потом", "— Стой! — крикнул" | accepted (orchestrator's decision) | rules (i) and (ii) of A§6.1, general by form; the residual limitation is recorded; "fires / stays silent" pairs in `listen_rule_test.dart` | — (a rule, not a defect) |

### Contradictions between documents (handled by the executor)

| Where | What was chosen (the simplest) |
|---|---|
| FR-L4 versus A§5 on clearing "finished" | one criterion — showing a page earlier than the last (the decision on #4); A§5 rewritten |
| FR-P4 "'To current spot' in all panel states" versus the "End of the book" panel | "To current spot" only in the control panel (`preparing`, `playing`, `waiting`, `paused`); in `stopped` it is absent: in the error panel "Listen" returns to the voice's place, in the end panel only "Close" |
| FR-P6 "from `stopped` — only by an explicit 'Listen'" versus the `readFrom` contract | from `stopped` a new session is started by "Listen" and "Read from here"; "back" and "forward" in `stopped` do nothing (the fake controller was brought in line with this) |
| FR-V1 and A§6.8 "one constant phrase" versus FR-T7 | the phrase and the style are by the book language, the sample is by the full profile (with #10) |

### Uncovered paths: what was added and what was deemed exotic

Added (paths of a live reader): a one-page book → shelf; a footnote at a sentence boundary; speed with a movement check;
a start inside a block → a profile change; a paragraph selection → a change of the panel height; "until the end of the
chapter" from a sheet and in the last chapter; the end of the book → a repeat of the last paragraph; a timer deadline in
`waiting`; pause → paging → commands from outside; error → paging/font/"Close"; end of the book → paging → "Close"; an
expired timer → "Read from here"; clearing → downloading; sample → model change → sample.

Exotic for the fake controller (recorded as a check to make on replacement, A§9 and the prototype README): late
completion of an old asynchronous operation after a session change; a late response of an old request after a new place
in `waiting`; keeping the pause on a profile change with no ready audio; partial download → deletion or a profile change
→ a late result. Updating the remaining minutes without an extraneous rebuild of the screen is exotic (visible only on
the panel, a rebuild error does not affect behavior).

### Weak tests (strengthened by the executor)

| Test | What was done |
|---|---|
| `journey_decisions_test.dart` — speed | a check that the voice advances in half a second was added; a separate test in `logic_review_test.dart` (#8) |
| `journey_decisions_test.dart` — error → paging → "Listen" | a check, before the tap, that the paging turned following off, and that the screen returned to the voice |
| `journey_shelf_test.dart` — deleted and added the same file | the book is on the shelf again, new and opens |
| `listen_rule_test.dart` (b) and `review_fixes_test.dart` #11 | the expected sentence start by an independent check (`test/support/sentence_oracle.dart`, regular expressions over the text of the rules), not by the same `sentenceStarts` |
| `journey_download_test.dart` — the estimate after "Stop" | the remainder equals "the whole chapter minus what is ready", the price is proportional, the text matches |
| `journey_decisions_test.dart` — timer and exit to the shelf | the path is continued: back into the book, "Listen", audio without a timer |

## Codex's answer (verbatim, lines 969–1067 of the output; two service lines "tokens used" in the middle of the table
removed)

*Translated from the Russian original.*

HEAD `2fc63a4` was checked. The files were not changed; `git status --porcelain` and `git diff --check` showed no
changes. I did not run Flutter, tests, the build or the phone. The stated 196 passed tests are the operator's result.
Below are conclusions from the code; frequency means an estimate of probable reader behavior, not measured statistics.

**Findings — from the most significant.**

| #, type and path | Expectation and basis | What happens per the code | Frequency / confidence | Minimal fix |
|---|---|---|---|---|
| **1. Prototype defect.** Error → page manually → change the font **or** tap "Close". Likewise after the end of the book. | After a stop an explicit movement passes the position to the screen; closing saves the chosen place, a re-layout holds it. A§5, FR-P4, FR-P8. | Manual movement turns following off only when `isActive`, which does not include `stopped`: [reader_screen.dart:207](../../lib/screens/reader_screen.dart), [reader_screen.dart:220](../../lib/screens/reader_screen.dart). The new position is saved, but `_following` stays `true`. A re-layout picks the old voice place — [reader_screen.dart:125](../../lib/screens/reader_screen.dart); "Close" writes it over the one chosen by the reader — [reader_screen.dart:373](../../lib/screens/reader_screen.dart). **The previous fix is incomplete:** a direct "Listen" after paging works, the intermediate closing and re-layout do not. | **Sometimes:** after an error the person goes on reading with their eyes. **High**, a direct trace of the conditions. | Turn following off on manual movement also for `stopped` with an open panel of this book. Check both stop branches, closing and a font change. |
| **2. Prototype defect.** Open a page inside a long paragraph → "Listen" from a sentence inside it → choose another voice → continue. Likewise on a model change in an active session. | Restarting with the new profile starts from the beginning of the **current segment**, including the starting tail of the paragraph. FR-P3, FR-V2, A§6.1/6.4. | The starting offset is correctly written in `_unitStart`, but `restartSession()` calls a move by block number only: [fake_narration.dart:250](../../lib/playback/fake_narration.dart). It zeroes both the progress and `_unitStart`: [fake_narration.dart:191](../../lib/playback/fake_narration.dart). The start of the paragraph is read again, the screen may go back; the listening place is also overwritten. | **Sometimes:** choosing a voice while reading. **High.** | Restart the profile with the saved full unit-start position — `block + offset`. Do not use a move to the start of the block for this. |
| **3. Prototype defect.** Start a download → listen → select a paragraph with a long press → wait until the voice moves on and the download finishes. | While a paragraph is selected, the page and the "Read from here" button wait for the user. FR-P4, A§5. | Ordinary following takes `_selectedBlock` into account: [reader_screen.dart:256](../../lib/screens/reader_screen.dart). A re-layout does not take it into account and picks the voice place: [reader_screen.dart:125](../../lib/screens/reader_screen.dart). Download completion removes a panel row, changes the measured height and triggers a re-layout: [player_panel.dart:108](../../lib/screens/player_panel.dart), [player_panel.dart:127](../../lib/screens/player_panel.dart), [reader_screen.dart:445](../../lib/screens/reader_screen.dart). If the selected paragraph disappeared from the new page, the button hides but the selection stays: [reader_screen.dart:603](../../lib/screens/reader_screen.dart). **The fix for holding the selection protects only one update path.** | **Rarely:** a held selection and a panel height change are needed; a change of state to an error is also possible. **High by the code**, the concrete geometry should be checked by a widget test. | On a re-layout take the held selection into account before following; keep the selected paragraph and its action visible. |
| **4. Prototype defect + a contradiction between documents.** **A:** open a new one-page book → return to the shelf. **B:** listen to the book to the end → close the panel → listen again to the last short paragraph on the last page. | The last shown page means 100 %; the flag is cleared only on returning **earlier than the last page**. FR-L4. | **A:** the first layout does not save the fact of showing the last page; saving is in the movement handling: [reader_screen.dart:117](../../lib/screens/reader_screen.dart), [reader_screen.dart:228](../../lib/screens/reader_screen.dart). `markOpened` sets 0 for a new book: [fake_library.dart:123](../../lib/library/fake_library.dart). **B:** the end of the audio fixes a threshold near the end of the last block. A new start at the beginning of the same block lies before the threshold and clears "finished": [fake_library.dart:99](../../lib/library/fake_library.dart), [fake_narration.dart:443](../../lib/playback/fake_narration.dart). There was no transition to an earlier page. | **Sometimes:** short books and repeating the end. **High**, B requires a last paragraph that fits on the last page. | Separate the fact of completion from an arbitrary recorded position. Take the initial showing of the last page into account; align the clearing criterion with FR-L4, not with the last audio offset. |
| **5. Contract defect, will carry over into the app.** Pause → manually go to another page → continue from the headset/notification. | Any explicit start or move of the audio turns following on, including external control. FR-P2, A§5. | Following is turned on by the wrappers of the **screen**: [reader_screen.dart:357](../../lib/screens/reader_screen.dart). A direct `narration.resume()` changes the state, but `_onNarration` does not recognize a user command and does not turn following on: [reader_screen.dart:245](../../lib/screens/reader_screen.dart). The contract does not pass the source/fact of such an action: [narration.dart:97](../../lib/playback/narration.dart). A similar problem with external next/previous. | **Often in the future app**, if reading apart from the audio and using a headset. **High for the insufficiency of the current contract**; device operation was not checked. | Pass the screen an event or a revision of an explicit user move/start. Do not turn following on simply at every `playing`: that would cancel manual paging during automatic transitions. |
| **6. Prototype defect, a risk on carrying over into the real choice of the starting segment.** The text `Фраза.1 Следующее предложение.`, where `1` is a structural footnote reference; a new page starts with the word "Следующее" → "Listen". | A footnote mark must not hide the start of the next sentence. The start is from the first new sentence on the page. FR-P3, the `speechText` model in the architecture. | The boundaries are searched in the raw `block.text`: [fake_narration.dart:105](../../lib/playback/fake_narration.dart). The algorithm looks before the space and sees `1`, not a period: [sentences.dart:14](../../lib/tts/sentences.dart). The calculation of this algorithm gives only the start `0`; a fallback to the previous sentence is applied: [fake_narration.dart:114](../../lib/playback/fake_narration.dart). This is a structural case, **not** a proposal to add a dictionary of abbreviations. | **Sometimes in books with footnotes**, when coinciding with a page boundary. **High for the given input**; this is a computed example, not a run of a book in Flutter. | Search for boundaries in the spoken text with offsets mapped back to the block, or explicitly skip the structural `noteRef` when determining the boundary. |
| **7. Prototype defect.** **A:** the "until the end of the chapter" timer in the last chapter → end of the book → do not tap "Close" → "Read from here" earlier. **B:** a minute timer → error → the deadline passed → "Read from here". | A fired timer is cleared; a new explicit start must not unexpectedly inherit an already expired stop. FR-D1, rule c. | **A:** the end-of-book branch returns before the chapter timer is cleared: [fake_narration.dart:407](../../lib/playback/fake_narration.dart), [fake_narration.dart:420](../../lib/playback/fake_narration.dart). The old timer stays for subsequent reading. **B:** `resume()` first clears the expired timer — [fake_narration.dart:139](../../lib/playback/fake_narration.dart), while `readFrom()` does not — [fake_narration.dart:163](../../lib/playback/fake_narration.dart). The new session enters `preparing`, then the check of the old deadline pauses it: [fake_narration.dart:377](../../lib/playback/fake_narration.dart). | **Rarely**, but the result looks like a refusal to start with no reason. **High by the transitions**; the behavior of the minute timer in `stopped` is insufficiently documented. | Clear the chapter timer also at the end of the last chapter. Perform the unified handling of an expired timer before all allowed explicit starts. |
| **8. Prototype defect.** Create a controller with a saved speed 1.5 → tap "Listen" for the first time without changing the speed in the menu. | The first audio and movement match the saved speed. FR-P5. | The getter and the caption return `settings.speed`: [fake_narration.dart:80](../../lib/playback/fake_narration.dart). The duration is computed through a separate `_speed`, initially equal to 1: [fake_narration.dart:51](../../lib/playback/fake_narration.dart), [fake_narration.dart:391](../../lib/playback/fake_narration.dart). Before `setSpeed` is called, the caption and the actual movement diverge. | **Every launch with a non-default saved speed**, once restoring settings appears; it already shows on the corresponding controller input. **High.** | Use a single source of speed in the getter and in the duration computation. |
| **9. Prototype defect.** "Clear narration" → download the chapter again → try to delete its narration or clear everything. | New ready narration makes the deletion actions available again. FR-D2/FR-D3, A§4. | A download changes only its own readiness maps: [chapter_download.dart:153](../../lib/playback/chapter_download.dart). The `FakeAudioStore` counters stay zero after clearing: [audio_store.dart:42](../../lib/audio/audio_store.dart). By them the book deletion item is hidden — [shelf_screen.dart:435](../../lib/screens/shelf_screen.dart), and the general clearing is disabled — [settings_screen.dart:242](../../lib/screens/settings_screen.dart). **The earlier fix tied clearing to readiness, but the reverse direction stayed inconsistent.** | **Sometimes:** downloading again after freeing space. **High.** | Tie the fake readiness and the fake volume to one state or update the counters on download/samples. Real files are not needed to fix the prototype. |
| **10. Contract and prototype defect.** Listen to a voice sample → change the model → repeat the sample of the same voice and language. | The sample must represent the chosen profile; another profile has another fingerprint. A§6.8. | The contract itself promises a cache only by voice and phrase: [voice_sample.dart:25](../../lib/playback/voice_sample.dart). The implementation does exactly that: [voice_sample.dart:65](../../lib/playback/voice_sample.dart). The model does not take part; the app creates the sampler without settings: [app.dart:64](../../lib/app/app.dart). After a model change the previous sample is reused. | **Sometimes:** comparing models and voices. **High.** | Bind the sample request and cache to the full effective profile, including the model and the parameters affecting the sound. |

**The effect of "To current spot" right after the start.**

A path to such a state exists: any `ScrollStartNotification` with a non-zero `dragDetails` turns following off at once,
even **before the page changes** — [reader_screen.dart:213](../../lib/screens/reader_screen.dart). Therefore a recognized
drag that then returned to the same page leaves the "To current spot" button.

But the claim **"1 px is enough" is not proven**: first the gesture must be recognized by Flutter. The page handler is
protected by the layout generation, the scroll notification handler has no such check. This is an additional candidate to
check when replacing `PageView`, not an established cause of the owner's observation.

It should be checked with a real mouse/pointer scenario: tapping "Listen", a small movement with release, a cancelled
drag and a drag during the appearance of the panel. Record the sequence of notifications, the layout generation, the page
number and the change of `_following`.

**Sentence boundaries.**

Below is a calculation of the current algorithm [sentences.dart:11](../../lib/tts/sentences.dart), not a Flutter
measurement:

| Input | Result and meaning for the reader |
|---|---|
| `Он жил в г. Москве. Потом уехал.` | `Москве` is counted as a sentence start. If a page starts there, a start from the middle of a semantic sentence is possible. |
| `А. С. Пушкин вошёл. Все встали.` | Each part of the initials creates a boundary. A start from `С.` or `Пушкин` is possible. |
| `Он молчал... потом заговорил.` | `потом` is counted as a new start. |
| `— Стой! — крикнул он. — Подожди.` | `— крикнул он` is also counted as a start. Reading from the author's remark is possible. |
| A poetry block `Первая строка\nвторая строка без точки` | Only the block start. On a page inside such a block a return to its start fires. |
| A heading or the last block without a terminating mark | The block start stays available; the absence of a period does not by itself lose text. |
| A page inside a long sentence with no new starts | A return to the sentence start is provided by FR-P3; this is not a new error. |
| Period + a structural footnote mark + the next sentence | A real structural skipping of the boundary — finding #6. |

The first four results follow from **the already chosen formal rule**, not from a new regression. They should be
explicitly accepted as a limitation or the general rule changed. There is no ground to fit abbreviation lists to a
particular book.

**Contradictions and gaps in documents.**

| Place | Discrepancy | What to reconcile |
|---|---|---|
| [Spec:108](../specs/001-first-version.md) and [Architecture:210](../ARCHITECTURE.md) | FR-L4 clears completion on returning earlier than the **last page**; the architecture — earlier than **the place where reading was finished**. These are different conditions after the audio finishes. | One criterion; exactly this difference shows in finding #4. |
| [Spec:216](../specs/001-first-version.md) and [Spec:226](../specs/001-first-version.md) | "To current spot" is required in all panel states, but the end panel allows only "Close". The code does not pass the return action to either the end panel or the error panel: [player_panel.dart:74](../../lib/screens/player_panel.dart). | Define explicitly the exceptions for both kinds of `stopped`. |
| [Spec:224](../specs/001-first-version.md) and [narration.dart:103](../../lib/playback/narration.dart) | From `stopped` continuing "only by an explicit 'Listen'" is allowed, but the contract and the screen allow a new session through "Read from here". | List the allowed explicit commands. At present both wordings cannot be taken as strict at once. |
| [Spec:170](../specs/001-first-version.md), [Spec:244](../specs/001-first-version.md), [Architecture:485](../ARCHITECTURE.md) | FR-T7 sets phrases by the book language, the old sections still speak of one constant phrase. | Replace the old wording with a reference to the language table and the full sample profile. |

A count of identifiers gave **58 FR requirements and 58 identifiers present in the checks table**. There are no entirely
missing FR rows. There are missed **branches of requirements**: for example, the FR-D1 row does not provide checks for the
end of the last chapter, `waiting` and a stop with an expired timer.

**Uncovered paths of the matrix.**

This is the absence of a corresponding scenario in the tests read, not a statement about the results of running them.

| State | Significant missing combinations |
|---|---|
| `idle` | The initial showing of a single/last page → shelf; a start with a footnote at a sentence boundary; the first launch with a non-default speed with a movement check. |
| `preparing` | A start inside a block → a profile change → keeping `unitStart`; a session change → the late completion of an old asynchronous operation. |
| `playing` | A selected paragraph → a change of the panel height; "until the end of the chapter" in the last chapter; completion → a repeat of the same last screen fragment. |
| `waiting` | A timer expiring with no additional actions; choosing a new place → a late response of an old request; keeping the pause on a profile change and absent ready audio. |
| `paused` | Manual paging → external resume/next/previous; a non-zero starting offset → another voice; updating the remaining minutes without an extraneous rebuild of the screen. |
| `stopped`, error | Paging/table of contents/slider → a font change or "Close"; an expired timer → "Read from here". |
| `stopped`, end | Manual movement → closing/re-layout; repeating the last paragraph without leaving the last page; clearing the timer of the last chapter. |
| Between screens and services | Clearing → a new download → deletion; sample → model change → repeating the sample; a partial download → deletion/profile change → a late result. |

Choosing the **"until the end of the chapter"** mode and checks of its execution were not found in the tests. For the real
controller both sides of the boundaries are also needed: the first/last segment of a chapter and of the book, including
the starting tail of a block.

**Vacuous and insufficient checks.**

Not all the listed tests are entirely vacuous. I name the concrete claim that they do not prove.

| Test | Why it lets the defect through |
|---|---|
| [journey_decisions_test.dart:45](../../test/journey_decisions_test.dart) | Checks the speed getter and the caption, but not the advance in equal time. It passes with the duration computed at speed 1 — finding #8. |
| [journey_decisions_test.dart:95](../../test/journey_decisions_test.dart) | After a stop it checks that following is on at start, but does not prove that manual paging turned it off before that. **The check of turning it on again is vacuous:** the value is already `true`. |
| [journey_shelf_test.dart:104](../../test/journey_shelf_test.dart) | After deletion and re-adding, the absence of an exception is checked. There is no proof that the book was actually added and opens; a silent refusal to add would also satisfy the check. |
| [listen_rule_test.dart:149](../../test/listen_rule_test.dart) | The expected start is computed by the same production `sentenceStarts` that the controller uses. This is a check of the connection of components, not of the correctness of the boundaries. Both computations will share the footnote error. |
| [journey_download_test.dart:44](../../test/journey_download_test.dart) | An inequality of the new estimate to the original does not prove the correct remainder: a wrong increase or zero could also pass. |
| [journey_decisions_test.dart:144](../../test/journey_decisions_test.dart) | The name promises exit, reopening and start; the checks end with clearing the timer after closing. The continuation of the path is absent. |

The check of the owner's original scenario in [listen_owner_scenario_test.dart:30](../../test/listen_owner_scenario_test.dart)
is useful and not vacuous. But it does not cover a profile change, a stop followed by paging, and a mouse drag.

**What needs checking when the fake controller is replaced.**

Besides the contract findings #5 and #10:

- `resume()` from a pause immediately puts the fake into `playing`, and a move to the neighboring block assumes instant
  readiness: [fake_narration.dart:147](../../lib/playback/fake_narration.dart),
  [fake_narration.dart:200](../../lib/playback/fake_narration.dart). Tests on these transitions do not prove the
  correctness of the sequence `paused → preparing/waiting → playing`.
- Checking the cancellation of a `Timer` does not check the completion of an already sent request or a disk write after
  closing, deletion and a session change. A controllable asynchronous double is needed to which an old result can be
  returned **after** a new command.
- The screen calls the following handling right after the command:
  [reader_screen.dart:357](../../lib/screens/reader_screen.dart). The real controller must synchronously publish the new
  intent/target place, or the screen must wait for the corresponding event. Otherwise an intermediate move to the old
  place is possible. This is a **forecast** depending on the future implementation.
- The limitation "one block instead of a segment mapped to several blocks" is already known from the previous review; I
  do not count it as a new finding. The current tests are not a check of such a mapping and of disk robustness.

In the other branches checked I found no new discrepancy: a repeated choice of the same voice/model, keeping the pause on
"Read from here", clearing the timer on closing and on changing the book, keeping the listening place on deleting only
the audio, and deleting both positions together with the book. Returning to a chapter on whose page the saved listening
place lies deliberately gives it priority — this matches the current start rule. Re-parsing a book is not yet
implemented: the actual stability of the position after it cannot be confirmed.

REWORK

## Prompt

*The prompt was given in Russian; translated here.*

```text
You are in the same environment as the operator: read files by their paths and compute yourself, you have Python. WSL is closed to you, so you will not run Flutter, tests and the build. DO NOT INVENT measurements; what is not in the files is called a forecast, and you say how to check it. Change nothing.

TASK. An independent re-check of the BEHAVIOR LOGIC of the screens of the clickable prototype (Flutter) — not code style and not appearance. The app is a book reader for Android with Google Gemini TTS narration, a single user; in the prototype the narration is fake (a timer moves the highlight), there is no network. The screens and the controller contract will become the basis of the real app.

WHY YET ANOTHER PASS. The prototype has already passed your code review (21 findings, all fixed) and an internal check by user journeys (16 defects, all fixed). Both times defects of one nature were found: two rules, each correct on its own, give a wrong result in a sequence of two to four actions, while the tests checked the rules one at a time. The first such defect was found by the owner by hand: listened to a paragraph → pause → "Close" → "Listen" — reading started from the previous paragraph and the page went back. After that a new start rule and eleven more rules (a–k) were introduced that were not in the documents before. The new rules may also conflict with each other and with the old ones — this is what needs checking.

Range: repository root, HEAD 2fc63a4. Changes since your previous review: `git log --oneline 53c78d3..2fc63a4`, `git diff --stat 53c78d3..2fc63a4` (you have git).

WHAT TO READ IN FULL:
- lib/playback/ (the contract narration.dart, the fake controller fake_narration.dart, chapter_download.dart, voice_sample.dart)
- lib/screens/ (all files except the generated l10n/app_localizations*.dart)
- lib/reader/, lib/library/, lib/app/, lib/tts/sentences.dart
- test/ — especially journey_*.dart, listen_*.dart, review_fixes*.dart
- docs/specs/001-first-version.md (FR-L*, FR-R*, FR-P*, FR-V*, FR-M*, FR-D*, FR-I1, Changelog)
- docs/ARCHITECTURE.md — sections 4, 5, 6.3–6.8, 8, 8.1
- docs/reviews/JOURNEY_AUDIT_2026-11-14.md — what has already been found and which rules a–k were introduced
- docs/reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md — your previous review
- docs/prototype/README.md

WHAT THE OPERATOR MEASURED: `scripts/test.sh` in WSL on 2fc63a4 — the analyzer clean, 196 tests passed (the orchestrator's run). Nothing was run on the phone. One effect that the owner saw in the browser (right after "Listen" the "To current spot" button is visible, i.e. following is off) could not be reproduced in tests; the agent's hypothesis — a mouse drag with a 1 px shift is taken for manual paging. If you see in the code a path to this state — that is a valuable finding.

WHAT TO LOOK FOR:
1. Sequences of actions where the result contradicts the reader's expectation or the documents. Walk yourself through the matrix "controller state (idle, preparing, playing, waiting, paused, stopped-error, stopped-end) × action" by the code: "Listen", pause, back/forward (at the start and end of a chapter and of the book), "Read from here", choosing a chapter, the slider, paging by hand, "To current spot", a change of font/theme/language, a change of the book voice and the shared one, a change of model, speed, the sleep timer (all modes, expiry in each state), "Download chapter"/"Stop"/error, "Delete narration", "Clear narration", deleting a book, "Close", the system "Back", exit to the shelf, opening another book. For each discrepancy found give the path step by step.
2. Conflicts between rules: the start rule (listening place / the first sentence on the page) against the "owner of the position" and "passing the position to the screen" (A§5); the re-layout anchor (rule b) against following (rule a); "finished — 100 %" (rule d) against the reading position and the listening place; the sleep timer (rule c) against a session change; the single download task (rule g) against a profile change and deletion; two positions (reading and listening) after "Read from here", choosing a chapter, the slider, deleting narration.
3. The listening place: where it may become stale or point to a nonexistent place (re-parsing a book, a font change does not count, deleting narration, the end of the book, "Read from here" earlier than it); what happens on "Listen" if the saved place is on the screen but the person has just chosen another chapter and returned.
4. Sentence boundaries (lib/tts/sentences.dart): abbreviations, initials, an ellipsis, direct speech with a dash, a sentence with no terminating mark at the end of a block, a heading, poetry; a page on which there is not a single sentence start. Which of this gives a defect noticeable to the reader (reading from the middle, skipped text, a page jump) — with a concrete text example.
5. What of the fake controller's logic will NOT survive replacement with the real one (asynchronous responses, errors, segments instead of blocks, writing to disk): where the screen or a test relies on the synchrony or instantaneity of the fake implementation.
6. Tests: which of the journey_*/listen_* tests pass vacuously, check the fake implementation instead of the behavior or pin down wrong behavior; which path of the matrix in item 1 is covered by nothing.
7. Discrepancies between the spec and the architecture after four rounds of edits (they were edited by different agents): the same rule worded differently; a requirement without a row in the checks table.

ANSWER FORMAT (in Russian):
A table of findings from the most important: the path step by step (or file:line for a code/document defect) → the expectation and what it is based on (FR-*/A§/the reader's common sense) → what happens per the code (file:line) → how often a live reader will run into it (often/sometimes/rarely, one phrase on why) → confidence → minimal fix. A finding with no file:line does not count. Mark separately: "prototype defect", "contract defect (will carry over into the app)", "gap or contradiction in documents".
Separately: uncovered paths of the matrix; vacuous tests.
Do not repeat findings already closed per JOURNEY_AUDIT and your previous review, unless you see that the fix is incomplete — then say exactly how. If an area is fine — one line. Ten real findings are worth more than forty doubtful ones.

The last line — the verdict, exactly one word in capitals: ACCEPT or REWORK.
```
