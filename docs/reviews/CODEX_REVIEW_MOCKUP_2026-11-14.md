# Mock-up review — Codex, 2026-11-14

Subject: the interface mock-up in `docs/mockup/` (commit `eb49784`), 25 screens attached to the prompt as images;
checked against spec 001 and `ARCHITECTURE.md` version 3. Codex 0.167.0-alpha.4.1, model `gpt-6-astra`,
`--sandbox read-only`, 118,186 tokens. Verdict: **REWORK**.

This file is a record of the review, not a source of truth; the spec, `ARCHITECTURE.md`, the mock-up and its `NOTES.md`
remain so.

The orchestrator took the decisions on the findings. All 22 findings were accepted; they land in the spec and the
architecture, and the fixes to the mock-up itself and to `docs/mockup/NOTES.md` are made by the mock-up agent. Finding
numbers are the order of the rows of the table in Codex's answer.

## Raised / verdict / where it landed

| # | Screens | Raised | Verdict | Where it landed |
|---|---|---|---|---|
| 1 | 07, 14, 21 | the book's voice cannot be chosen before the first listening | accepted: a "Voice" entry both in the bottom reading panel and on the player panel | FR-V2 |
| 2 | 10–11 | there is no permanent "Download chapter" error, especially without listening | accepted: the error in the chapter block in the table of contents, "Download again" with a new estimate of the remainder, the player does not open; states after completion and manual stop | FR-D2; A§6.7 |
| 3 | 21 | the sample has no waiting state and no error | accepted: three states of the voice row | FR-V1; A§6.8 |
| 4 | 22–23 | saving the key and returning are not defined | accepted: "Paste" saves at once, the value is hidden, "Back" goes back to where you came from, narration does not start by itself | FR-P7; A§8.1 |
| 5 | 18 | two 160 dp buttons do not fit in 320 dp | accepted as a general rule | FR-R8 (buttons stack in a column); the places are in `NOTES.md` |
| 6 | 05, 25 | dialogs of fixed height | accepted as a general rule | FR-R8 (heights by content); `NOTES.md` |
| 7 | 14–17 | at 320 dp the player touch areas overlap | accepted as a general rule | FR-R8 (touch area ≥ 48 dp); `NOTES.md` |
| 8 | 10 | the price inside the "Download chapter" button will run past the edge | accepted: the estimate as a separate row before the button | FR-D2, FR-R8; A§6.7 |
| 9 | 02–03 | the empty shelf and the error row at fixed `y` values | accepted as a general rule | FR-R8; `NOTES.md` |
| 10 | 21–24 | voice descriptions, the key link, model prices will be cut off | accepted as a general rule | FR-R8 (wrapping instead of cutting); `NOTES.md` |
| 11 | 07, 14–16 | the slider is removed during listening contrary to A§5 | accepted: a tap in the center shows the header and the slider above the player, it pages only the screen | FR-R5, FR-P4; A§5, A§8.1 |
| 12 | 07, 10–11, 14, 18, 22, 24 | there is no transition diagram | accepted | new FR-R9; A§8.1; "Out of scope": a mini-player on the shelf |
| 13 | 21–22 | there is no screen variant for the shared voice | accepted: two variants of the screen | FR-V1 |
| 14 | 15, 21 | a visible 40 dp without a specified 48 dp touch area | accepted as a general rule | FR-R8; `NOTES.md` |
| 15 | 06–07, 12 | the touch area of a footnote mark and its priority | accepted | FR-R3 |
| 16 | 17, 20 | the "until the end of the chapter" mode is distinguishable only by color | accepted: a textual indicator on the panel | FR-D1 |
| 17 | 21, 24–25 | texts about the sample, clearing and model change | accepted, mock-up only | `docs/mockup/` (mock-up agent); nothing in the spec |
| 18 | 18 | the 402 text promises automatic continuation | accepted: from `stopped` — only by an explicit "Listen"; an explanation in our own words only for recognized causes | FR-P6, FR-P7 |
| 19 | 09, 19, 21, 24 | there is no rule for system areas | accepted as a general rule | FR-R8 (fixed panels take system areas into account); `NOTES.md` |
| 20 | 09 | the contrast of the available scale steps is 1.37:1 | accepted, mock-up only | `docs/mockup/` (mock-up agent); nothing in the spec |
| 21 | 03 | there is no refusal for a protected book; the example `unexpected EOF` is ambiguous | accepted: the refusal is the same shelf row; the error example is changed by the mock-up agent | FR-B2; `docs/mockup/` |
| 22 | 08 | there is no rule for styling a quotation | accepted: the rule is in `NOTES.md`, the spec refers to it | FR-R3 |

Of what was proposed in the findings, rejected: a screen variant of the key with an open keyboard (finding 19) and
separate mock-ups for 320 dp — the width is checked by the general rule FR-R8 and the list of places in `NOTES.md`.

From the "what is superfluous" list:

- "To read with your own eyes, close the panel" (17) — accepted, removed from the mock-up;
- the voice counts in the group headings (21) — accepted, removed from the mock-up;
- "a third cheaper" (24) — accepted, removed from the mock-up;
- the progress bar in the "Continue" card (01, 03) — rejected, stays;
- the note that changing the speed is free (19) — rejected, stays.

Codex's opinions on the 14 designer decisions and the 4 questions to the owner are in the verbatim part below. On the
questions: (a) "Download chapter" only for the current chapter and (d) the slider during listening were decided by the
orchestrator the same way Codex advises; (b) the download progress on the reader screen, (c) multiplying the book text by
the system scale and the choice between "read" and "100 %" on the shelf (designer decision 12) were put to the owner as
open questions in section 1 of the spec, with the orchestrator's recommendation.

Decided while making the edits, without a separate orchestrator decision:

- FR-D2: "narrated" — by the readiness rule of A§6.1 for the active voice profile (Codex's addition to decision 8);
- FR-R5: the slider during listening turns following off, like paging by hand (A§5);
- A§8.1: from settings opened from the reader screen ("Listen" without a key, "Choose model"), "Back" returns to the book
  without starting narration — both for the key and for the model;
- FR-R9 stands in the "Reading" section (stage 1); transitions to the narration screens are checked from stage 2;
- "Out of scope": downloading any chapter other than the current one was added (the settled question "a").

## Codex's answer

*Translated from the Russian original. The mock-up screen texts quoted in it were in Russian; those that match a button
or label of the app are given here by their English strings from `lib/screens/l10n/app_en.arb`, and the others are kept in
Russian with an English gloss.*

The mock-up needs rework primarily in the transitions between states and in adapting to a narrow screen. All the listed
FRs were checked against the images, [NOTES.md](../mockup/NOTES.md), [the mock-up source](../mockup/build_mockup.py), the
spec and the architecture.

Below are only the findings. Sizes are taken from the source; contrast was recomputed from the hex values. **The
estimates for 320 dp and scale 1.3 are a forecast, not a check on a phone.** The files were not changed.

| Screen | Requirement / section | Defect | Consequence | Confidence | Minimal fix |
|---|---|---|---|---|---|
| **07, 14, 21** | FR-V2; NOTES, decision 5 | A specific book's voice is available only after the player appears. In `idle` there is no entry. | To choose a voice before the first listening you first have to start narration with another voice, potentially paid. The shared setting does not replace the book's setting. | High | Give an entry to the book voice choice before "Listen" is tapped, keeping the main screen simple. |
| **10–11** | FR-D2; A§6.7 | For downloading, the start and the progress are shown, but there is no permanent error with Google's text. The case of downloading **without listening**, when there is no player panel, is especially undefined. | The task will stop without an explanation, or a developer will invent a notification or wrongly open the player. | High | Draw the error inside the existing chapter block: the cause and the option to start again with a new estimate of the remaining cost. Clarify the transition after completion and manual stop. |
| **21** | FR-V1; A§6.8 | The "Sample" has the normal and playing states, but no synthesis wait, no transient-error retries and no permanent error. | After the paid tap it is unclear whether it was accepted; on a refusal it is unclear why there is no voice. | High | Add variants of the same row: the wait and the error with Google's text. A separate screen is not needed. |
| **22–23** | FR-P7; CONCEPT §3 "Settings" | Saving a pasted key, editing an existing one and returning after going from "Listen" are not defined. The picture of the focused field does not explain this. | The layout designer has to decide when the key is saved and whether narration starts after returning. | High | Annotate the scenario: what saves the key, which state confirms the saving, where "Back" returns. Show the field with the entered, hidden value. |
| **18** | FR-R8 | In `player_stopped()` two buttons have a fixed width of 160 dp: **160 + 8 + 160 = 328 dp**. At a width of 320 the space between the margins is **288 dp**. | When the sizes are carried over from the mock-up, the buttons run past the available area even without enlarging the text. | High | For a narrow width arrange the actions vertically; compute the panel height from the content. |
| **05, 25** | FR-R8; FR-L5, FR-M3 | The dialogs have a fixed height; the text starts at `y + 64`, the buttons at `y + h − 72`. For 05 there are only **68 dp** between the start of the text and the buttons. At 320 the text column is **224 dp**, at scale 1.3 there will be more lines. | **Forecast:** the warning text will run into the actions; a long title will also affect the main text. | High | A vertical layout by content, wrapping of the title and the buttons; a height limit with scrolling when needed. |
| **14–17** | FR-R8; NOTES "Grid and sizes" | If the player formulas are kept at 320 dp, the "back" cell takes `84…132`, the play circle `128…192`, the "forward" cell `188…236`. The targets overlap by **4 dp on each side**. | **Forecast:** neighboring actions will get overlapping touch areas. | High | Distribute the five targets adaptively across the width, keeping their minimum sizes and no overlap. |
| **10** | FR-R8; FR-D2 | The button "Download chapter · ≈ 0.19 $" uses a width by content with no limit. 48 dp on the left are already taken. | **Forecast:** at 320 × 1.3 a long action with the price will run past the edge. The price is an essential part of the decision, it cannot be hidden by an ellipsis. | High | Move the price estimate to a row directly before the button; leave the button "Download chapter" and limit its width. |
| **02–03** | FR-R8; FR-L2, FR-B2, FR-B6 | In the empty state the explanation and the button are placed at fixed `y` values. In the error row 03 the cause starts at `y + 38`, the technical detail already at `y + 60`. | **Forecast:** an enlarged explanation will overlap the button; a multi-line error will overlap the technical cause. | High | The height and position of the following elements must depend on the text. The error row grows with the message. |
| **21–24** | FR-R8; FR-V1, FR-V3, FR-P7 | A voice description at 320 gets only **140 dp** and `maxLines=1`; the key-getting link has a width by content; the model notes are not limited in width. | **Forecast:** the voice character will be cut off, the link and the model price will run past the edge. An ellipsis does not suit an essential price and an action explanation. | High | Allow wrapping of descriptions and growth of rows; name the link shorter — "Где взять ключ" (Where to get a key); place the model price in a limited column. |
| **07, 14–16** | FR-R5; A§5; NOTES, decision 4 | The slider is removed entirely during listening, although A§5 explicitly describes its work in this mode: it moves only the page, not the voice. | A quick jump through the text without changing the listening is lost; the mock-up silently narrows the intended behavior. | High | Show the slider when the panels are called up during listening, or separately agree a change of the spec and the architecture. |
| **07, 10–11, 14, 18, 22, 24** | FR-P8; A§6.6, §8 | There is no single description of transitions: the table of contents over reading, exit to the shelf, going to settings, choosing a model directly from the error. It is not stated where only the panel hides and where the book closes. | A developer may stop the audio when the table of contents opens or keep it after the book is closed, contrary to A§6.6. | High | Add a transition diagram: the table of contents does not close the book; exit to the shelf closes it → `idle`; settings from the shelf open after that; choosing a model from 18 returns to the same book. A new mini-player is not needed. |
| **21–22** | FR-V1, FR-V2 | Only the choice **for the book** is drawn, with the item "Same as in Settings". The shared voice choice variant is absent. | A literal reuse of the screen from settings will create a self-reference "Same as in Settings" and a wrong subtitle. | High | Specify the second variant of the same screen: without the book title and without the inheritance row, with the shared voice marked. |
| **15, 21** | NOTES "Touch targets" | The visible frames "To current spot" and "Sample" are **40 dp** high. Extending their touch area to the declared 48 dp is not specified separately. | If the button bounds are implemented literally, the targets will be smaller than the accepted minimum. | High | Specify explicitly a touch area ≥ 48 dp; the look may stay 40 dp. The size of the drawing and the size of the target are different things. |
| **06–07, 12** | FR-R2, FR-R3 | The touch area of a small footnote mark and its priority over paging/showing the panels are not described. | An attempt to open a footnote may turn the page or call up the panels. | Medium | Specify an extended area and the priority of the link over the page gesture; check the proximity of several links. |
| **17, 20** | FR-D1 | A turned-on timer is shown only by a number of minutes. The look of the player with "Until the end of the chapter" chosen is not defined. | The layout designer may leave just a colored moon: the reader will not tell the mode from a minute timer. | High | Add a variant of the same button with a short caption "До конца" (To the end) or "Глава" (Chapter) and a full accessible name. |
| **21, 24–25** | FR-V1, FR-M3; A§6.8 | "The sample … is paid once" does not take into account a profile change and clearing. The clearing confirmation mentions only books, although FR-M3 deletes samples too. In 24 "books are narrated again" does not explain when exactly. | The reader gets a wrong expectation of a free sample and may understand a model change as an immediate narration of the whole library. | High | "Сохранённая проба повторно бесплатна" (A saved sample is free again); in clearing — "озвучка книг и пробы голосов" (book narration and voice samples); for the model — "При дальнейшем прослушивании звук для этой модели создаётся заново, если ещё не сохранён" (On further listening the audio for this model is created anew if not yet saved). |
| **18** | FR-P6, FR-P7; A§6.6 | "После пополнения чтение продолжится" (After the top-up, reading will continue) sounds like a promise of automatic continuation. From `stopped` the architecture requires a new "Listen". | The reader will top up the balance and wait for an automatic start. | High | "Пополните счёт и нажмите «Слушать» — продолжим с этого места" (Top up the balance and tap "Listen" — we will continue from this place). |
| **09, 19, 21, 24** | FR-R8; NOTES "Grid" | The bottom margins are given as numbers, there is no general rule for accounting for system insets. For example, the two-line theme caption in 09 ends about **22 dp from the bottom**, the note of 19 — at **24 dp**. | On a device with a larger bottom system area, or when the text grows, the content may end up under it. The fixed top 28 dp also does not prove protection against a cutout. | Medium | Write down: the mock-up sizes are the base ones; headers, sheets and fixed panels take the actual system areas into account. Add a variant with the keyboard for 23. |
| **09** | FR-R6; NOTES palette | The available but not yet chosen size steps and part of the scale are colored `line`. The contrast of `#DCCBAE` / `#F7EDDA` is **1.37:1**. They look almost disabled. | The remaining steps and the range of the setting are poorly visible. | High | Use a higher-contrast token for the available steps and the significant part of the scale. Decorative separators need not be changed. |
| **03** | FR-B2, FR-B6; A§3 | There is no refusal variant for a protected book. The example `unexpected EOF` is ambiguous: the architecture requires recovering tags not closed by the end of the file. | An identical refusal may be wrongly implemented for DRM and an unsupported format, or an acceptably corrupted FB2 rejected. | High for the missing variant; medium for EOF | Add the DRM variant of the existing row. Replace the technical example with an unambiguously unrecoverable error, for example a duplicate XML attribute. |
| **08** | FR-R3 | A poetic epigraph is shown, but there is no sample or rule for styling a separate quotation block. | The layout designer will choose indents and typeface by themselves; the requirement that quotations be distinguishable stays underspecified. | High | Add a small fragment of a quotation and the rule for its styling. A separate full-screen mock-up is not needed. |

On accessibility checks: the minimum of **48 dp** refers to the touch area, not to the icon size — this matches the
[Android recommendations](https://support.google.com/accessibility/android/answer/7101858?hl=en). The **3:1** contrast
is needed for significant non-text control indicators; it is not required for every decorative outline of a button with a
readable caption. Therefore the remark above concerns the scale, not all pale borders.
[W3C explanation](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).

A recomputation of the text pairs confirmed NOTES: `ink/bg` — **15.24 / 10.59 / 14.13**, `ink2/bg` — **5.79 / 5.25 /
6.28**, `on_accent/accent` — **5.93 / 6.51 / 7.01** for the light, sepia and dark themes respectively. No lack of contrast
of the main text was found.

From the superfluous, the following can be removed:

- **01, 03 — the progress bar in the "Continue" card.** The percentage next to it already conveys the position; the bar
  gives no separate action.
- **17 — "Чтобы читать глазами, закройте панель" (To read with your eyes, close the panel).** A message about the end of
  the book and a cross are enough; the instruction takes up the space of text.
- **21 — the voice counts in the group headings.** "ЖЕНСКИЕ" (FEMALE) and "МУЖСКИЕ" (MALE) are enough for the choice.
- **24 — "на треть дешевле" (a third cheaper).** Two prices already allow comparing the cost.
- **19 — the permanent note that changing the speed is free.** It is a useful note on first acquaintance, but not a
  mandatory part of every opening of the sheet.

I do not propose removing a whole functional screen. Boards 17–18 are documentation of states: their service captions
are not user jargon.

Opinion on the fourteen designer decisions:

| # | Opinion and reason |
|---|---|
| **1. Roboto + Merriweather** | **I support:** a single verifiable typeface of the mock-up and the implementation is more important than returning to the original variant. |
| **2. A lighter theme and a separate sepia** | **I support:** the themes differ, the text pairs have sufficient contrast. |
| **3. Panels over the page** | **I support:** the place of the text does not jump; the ability to hide the panels with one tap must be kept. |
| **4. The player instead of the reading panel, no slider** | **In part:** a permanent player is appropriate, the slider must stay available when the panels are called up per A§5. |
| **5. The voice only from the player** | **I do not support the restriction:** the book's voice must be chosen before the first paid start. |
| **6. Speed in a separate sheet** | **I support:** the needed value is chosen in one action, without going through six variants in turn. |
| **7. Add errors as shelf rows** | **I support:** the error stays next to the file and does not disappear until read. |
| **8. Download only the current chapter; a readiness mark** | **I support:** matches A§6.7; the mark is needed but must refer to the active voice and model. |
| **9. The "Paste" button** | **I support:** it shortens entering a long key; saving must additionally be defined. |
| **10. Ignore the system scale for the book** | **I do not support in the current form:** the user's large font is ignored, and the own scale ends at 22 sp. |
| **11. Confirm deleting a book's narration** | **I support:** deletion deprives of already paid audio; the dialog needs the book, the volume and the consequence of paying again. |
| **12. "New" and "read" instead of 0/100 %** | **In part:** "new" is clear; reaching the end does not prove reading — "100 %" or "end" is more precise. |
| **13. The moon color and the remaining minutes** | **I support with an addition:** the "Until the end of the chapter" mode must also have a textual indicator, not only color. |
| **14. A short explanation plus Google's reply** | **I support with a restriction:** a concrete explanation only for a recognized cause; do not interpret an unknown error and do not promise automatic recovery. |

Opinion on the four questions to the owner:

| Question | Opinion |
|---|---|
| **a. The current chapter or any?** | **The current:** this is already defined by A§6.7; downloading any chapter requires deciding separately the choice without moving the reading. For the first version the complication is not needed. |
| **b. The download progress on the reader screen?** | **Yes, only while the task is active:** a short progress row with a way to stop the paid work; the expanded block stays in the table of contents. |
| **c. Not to multiply the book text by the system scale?** | **No with the current scale:** either take the scale into account or agree a much wider own range. A 22 sp ceiling does not replace the system enlargement. |
| **d. The slider during listening?** | **Yes, in the panels that are called up:** it moves only the page, as A§5 requires; starting the voice from a new place stays an explicit action. |

REWORK

## Prompt

*The prompt was given in Russian; translated here.*

```text
You are in the same environment as the operator: read files by their paths, you have Python. WSL is closed to you. There is no app code yet. DO NOT INVENT measurements. Change nothing in the files.

TASK. An independent review of the interface mock-up of a mobile app before layout begins. The app is a book reader for Android with Google Gemini TTS narration, a single user. 25 screen images (360×800 dp, scale 2×) are attached to the message in the order of numbers 01…25. The same files are in docs/mockup/png/ — if the attachments are not visible, say so in the first line of the answer and review from the mock-up source.

WHAT TO READ:
- docs/mockup/NOTES.md — the palette, fonts, grid, the "screen → requirement" table, the designer's decisions for confirmation
- docs/mockup/build_mockup.py — the mock-up source (exact coordinates, sizes, texts)
- docs/specs/001-first-version.md — the requirements (FR-*) and "Out of scope"
- docs/ARCHITECTURE.md — sections 5, 6.6, 6.7, 6.8 (following the voice, player states, chapter download, voice probe)
- docs/CONCEPT.md — sections 2, 3, 7

THE OWNER'S PRINCIPLES: the minimum of elements, nothing "just in case"; the interface from the reader's point of view; a failure is not closed with pop-up notifications; a paid action larger than the usual reserve shows the price in advance. A superfluous element is as much a finding as a missing one.

QUESTIONS:
1. Conformance to the spec: for every requirement with visible behavior (FR-L2…L5, FR-B2, FR-B6, FR-R2…R6, FR-R8, FR-P2…P8, FR-V1…V3, FR-M2, FR-M3, FR-D1…D3) — is there a screen or state from which the layout designer will understand what to draw? What is missing? What is drawn contrary to the spec or the architecture (for example, an action that per A§6.6 must not exist in this state)?
2. Superfluous: which elements and screens can be removed without loss of function.
3. Fitness for a phone: touch targets smaller than 48 dp, contrast (recompute from the hex values in NOTES.md if in doubt), text that will not fit at a system font scale of 1.3 at a width of 320 dp (estimate by line lengths and the sizes from build_mockup.py — this is a forecast, call it so), elements under the gesture bar and in the cutout zone.
4. Consistency: the same action looks different on different screens; different actions look the same; captions the reader will not understand (jargon: "segment", "session", state codes).
5. Navigation: from which screen it is impossible to return or unclear how; is there an action that cannot be reached; what happens to the player panel on moving to the table of contents, settings, the shelf.
6. Fourteen designer decisions and four questions to the owner (below): your opinion on each, in one line, with the reason.
   Questions: (a) "Download chapter" only for the current chapter or for any; (b) whether to show the download progress on the reader screen; (c) the book text is not multiplied by the system font scale — is that right; (d) whether a slider through the book is needed during listening.

ANSWER FORMAT (in Russian):
A table of findings, from the most important to the least important: screen (number), requirement or section, what the defect is, how it will end for the reader or for the layout designer, confidence (high/medium/low), minimal fix. A finding with no screen number or requirement identifier does not count.
Separately: a "superfluous" list; the opinion on the 14 decisions and 4 questions.
If a screen is fine — do not mention it. An objection with a concrete reference is worth more than agreement.

The last line — the verdict, exactly one word in capitals: ACCEPT or REWORK.
```
