# Spec 001. First version of the reader

Status: after the Codex reviews of 2026-11-14, of the spec ([CODEX_REVIEW_SPEC_2026-11-14.md](../reviews/CODEX_REVIEW_SPEC_2026-11-14.md))
and of the mock-up ([CODEX_REVIEW_MOCKUP_2026-11-14.md](../reviews/CODEX_REVIEW_MOCKUP_2026-11-14.md)); implementation
has been under way since 2026-11-15: stage 0 is done (except the FR-E6 measurement on a mobile network), stage 1 was
accepted by the owner on 2026-11-15 (SC-1), stages 2 and 3 are written and verified on the phone as far as a computer
can do it; their acceptance (SC-2, SC-3) is the owner's, by ear and by hand (see
[WHERE_WE_ARE.md](../WHERE_WE_ARE.md)).

What we are building: [CONCEPT.md](../CONCEPT.md). How it is built: [ARCHITECTURE.md](../ARCHITECTURE.md) version 3; the
spec does not retell it but refers to its sections ("A§6.3"). Facts about Gemini: [GEMINI_TTS.md](../GEMINI_TTS.md). The
look of the screens: the mock-up in `docs/mockup/`; font steps, typeface and the screen sizes to check are in
`docs/mockup/NOTES.md`; where the spec and the mock-up differ in layout and labels, the mock-up is right; in behavior,
the spec is.

## 1. Decisions

| No. | Decision | Who and when |
|---|---|---|
| D1 | Flutter, Android only, installed from an APK file | owner, 2026-11-14 |
| D2 | Formats: FB2, FB2.ZIP, EPUB, TXT. MOBI and AZW3 are a separate spec after this one | owner, 2026-11-14 |
| D3 | Gemini voice only; there is no Android system voice | owner, 2026-11-14 |
| D4 | Turning pages; there is no scroll mode | owner, 2026-11-14 |
| D5 | Books narrated in AudiobookStudio are a separate spec after this one | owner, 2026-11-14 |
| D6 | Default model `gemini-3.8-flash-tts`, voice Aoede | carried over from the studio |
| D7 | Gemini's streaming response is not played; the start goes through the start segment (A§6.1, A§10) | orchestrator, from the 2026-11-14 measurement |
| D8 | The work goes in four stages (section 2); each ends with its own acceptance and a merge into `main` | orchestrator |
| D9 | An interruption (a call, foreign audio, unplugged headphones) pauses; the user resumes by themselves | orchestrator, from the 2026-11-14 review |
| D10 | Portrait orientation only: fixed in the manifest and in code; no landscape in the first version (A§7) | orchestrator, from the 2026-11-14 gesture audit |
| D11 | System "Back" in reading: clear the paragraph selection → close a sheet, dialog, footnote → show hidden panels → close the book; the "Back" arrow in the header closes the book at once. Reason: the Android edge gesture: a swipe from the edge in immersive reading is "Back" (A§8.1) | orchestrator, from the 2026-11-14 gesture audit |
| D12 | Protection against a follow-up tap: after a layer change under the finger, the controls and the page do not accept taps for 350 ms (A§8.1) | orchestrator, from the 2026-11-14 gesture audit |

The owner's phone is a Samsung Galaxy S26 Ultra (named 2026-11-14; the implementer reads the Android version from the
device at stage 0 rather than taking it from memory). The minimum Android version is 12 (`minSdk 31`): the owner asked
to proceed from the realities of 2026, the app is installed on one modern phone, and compatibility branches for older
versions (notifications, foreground services, splash screen) are not needed. `targetSdk` and `compileSdk` are the
latest that the pinned Flutter version supports.

Decided from the mock-up review of 2026-11-14: "Download chapter" covers only the current chapter; the book slider is
available during listening too (FR-R5).

Decided by the owner on 2026-11-14: the progress of "Download chapter" is also visible on the reading screen (FR-D2);
the book text size is multiplied by the system font scale (FR-R6); a finished book on the shelf is marked "100 %"
(FR-L4).

Decided by the owner on 2026-11-14: the interface in ru, en, pl, de; the phone's language by default, a forced choice
in the settings (FR-I1). The look of the screens is set by the Flutter prototype (`docs/prototype/`): the FigCraft
mock-up was rejected on its interface elements, its palette and fonts were kept. Ukrainian (uk) was added as the fifth
interface language by the owner's decision of 2026-11-17 (FR-I1).

Decided by the owner on 2026-11-15: the prototype is accepted and implementation has begun; the permanent APK signing
key is created by the implementer outside the repository, the path and passwords are in `.env` (FR-E2). The phone was
connected the same day: SM-S948B, Android 17 (API 37), screen 1440 × 3120, three-button navigation rather than gestures.
SC-0 on the phone passed: the APK was installed, and a second build went on top of the first without uninstalling the
app.

## 2. Stages

| Stage | What appears | Acceptance |
|---|---|---|
| 0. Environment | a Flutter project, scripts, CI, an empty app on the phone, the stage 0 measurements from A§11 | SC-0 |
| 1. Reader | shelf, adding FB2, FB2.ZIP and EPUB, deleting a book, reading, position | SC-1 |
| 2. Narration | Gemini client, queue, player, background, voice and probe, spending, "Clear narration", `docs/DEVICE_CHECKLIST.md` | SC-2 |
| 3. Polish | TXT (parsing and accepting the file), sleep timer, "Download chapter", a book's "Delete narration" | SC-3 |

The mock-up is made before stage 1 and is not part of this spec. The stages go in order; within a stage, the work is
divided between agents by file ownership (modules of A§2).

## 3. Requirements

### Environment (stage 0)

- **FR-E1.** `scripts/setup-wsl.sh` installs Flutter and the Android build tools of the required versions in WSL
  Debian; the versions are recorded in the script and in `pubspec.yaml`, not "latest". Running it again breaks
  nothing.
- **FR-E2.** `scripts/test.sh [selector] [options]` runs the analyzer and the tests; `scripts/build-apk.sh` builds an
  APK signed with the permanent key. The key and its passwords are kept outside the repository; the path to them is in
  `.env`. The key is a precondition of the stage: it is created by the owner, or by the implementer with the owner's
  consent.
- **FR-E3.** CI on every commit to `main` and on every pull request: analyzer, tests, an APK build with the debug key.
- **FR-E4.** The "Stack and runtime" section in `AGENTS.md` is replaced with the actual commands, after each of them has
  been run and has worked.
- **FR-E5.** The directory structure of `lib/` matches the modules of A§2. A test checks direct imports: a module's file
  imports only the modules from the list in A§2.
- **FR-E6.** The stage 0 measurements from the table in A§11 are done and recorded in GEMINI_TTS.md with a date. The paid
  ones follow the `AGENTS.md` rule, "Money": a small measurement without asking, a larger one with the owner's consent.

### Book and parsing (stage 1; TXT is stage 3)

- **FR-B1.** The book model is A§3, including the offset unit and `speechText`.
- **FR-B2.** The format is determined by content, in the order of A§3; recognized unsupported containers and binary data
  are rejected before the TXT branch. The refusal is "This format is not supported"; an EPUB with an encrypted document
  from `spine`: "The book is copy-protected and can’t be opened". Obfuscated fonts do not cause a refusal. Any refusal,
  including for a protected book, is visible on the shelf as the same adding-error row as the others.
- **FR-B3. FB2.** From the file are taken: title, author, language, cover; body sections as chapters by the rules of
  linear splitting; headings, paragraphs, verse, quotes, epigraphs, empty separator lines, pictures (`binary`),
  footnotes (a `body` named `notes` and references to it), emphasis styles. The encoding is from the XML declaration.
  `.fb2.zip` is the same after unpacking.
- **FR-B4. EPUB 2 and 3.** Reading order, boundaries, titles and levels of chapters follow the EPUB rules of A§3. From
  XHTML the same kinds of blocks are taken as from FB2; footnotes, an in-body table of contents and captions are
  recognized only by the structural signs of A§3, and without them are plain text. The cover is from the package
  metadata. CSS styles are not applied, except for distinguishing italic and bold by tags.
- **FR-B5. TXT** (stage 3). The encoding is per A§3. A paragraph is the text between empty lines; if there are no empty
  lines, a paragraph is a line. There are no chapters: the book is one chapter without a title.
- **FR-B6.** Parsing tolerates exactly three kinds of damage listed in A§3: an unclosed tag, an unknown entity, a file
  declared UTF-8 with invalid sequences. Any other XML error, and a file from which not a single block of text could be
  obtained, is a refusal "Couldn’t read the book" with the technical reason in small print. A reference to a
  nonexistent footnote is plain text without `noteRef`.
- **FR-B7.** For each parsing rule and each kind of damage there is its own small sample with the exact expected text of
  blocks, chapters and footnotes. In addition, invariants checked on every sample and on every book from
  `test/local_books/`: block numbers run consecutively; chapters cover all blocks with no gaps or overlaps; every
  `noteRef` points to an existing footnote; `totalChars` equals the sum of the lengths of the block texts; range
  offsets lie inside the text.

### Shelf and storage (stage 1)

- **FR-L1.** Storage at stage 1 is per A§4: the book folder, adding through `tmp/` and renaming, the position writer
  (`state.json`), backup disabled. Spending (`usage.json`), the key and the coordination of deletion with narration are
  stage 2 (FR-M2, FR-T2, FR-Q4).
- **FR-L2.** Adding: the "+" button opens the system file picker; the app accepts a file from other apps ("Open with",
  "Share") for the extensions `.fb2`, `.fb2.zip`, `.epub` and the corresponding content types; `.txt` is stage 3
  together with FR-B5. Parsing runs outside the main isolate; meanwhile the shelf shows the book's row marked
  "Adding…".
- **FR-L3.** A file already on the shelf (the same `bookId`) is not added a second time: the existing book is opened.
- **FR-L4.** Shelf: the "Continue" card exists only for a book that has been opened, the last one opened. Never-opened
  books stand first in the list below the card, new ones on top, marked "new"; the rest are in descending order of last
  opening time. Each has a cover (or a placeholder with the first letter of the title), title, author, fraction read
  and, for the card, the chapter of the reading place (the one where the position is, whoever recorded it).
  **Finished** is "100 %": this is a separate fact in `state.json`, not derived from the recorded position. It is set
  by showing the last page (including the first layout of a one-page book) and by the end of listening; it is cleared
  only by showing a page earlier than the last. A re-layout (font, panel) and re-listening on the last page do not
  clear it. At the bottom of the last page and on the slider it is also "100 %". In other cases the fraction is by
  position. An empty shelf is an invitation to add a book.
- **FR-L5.** Deletion: long press → "Delete" → a confirmation with the title and the amount that will be freed. The
  book's folder is deleted entirely, together with its narration.
- **FR-L6.** Unfinished leftovers in `tmp/` are deleted at startup.

### Reading (stage 1)

- **FR-R1.** Pagination and display are A§5: in portions from the current position, the first page at once.
- **FR-R2.** Turning: a tap on the right third and a swipe left go forward; the left third and a swipe right go back; a
  tap on the center shows and hides the panels. Crossing a chapter boundary uses the same gesture. A second tap (or
  swipe) during the animation of the first is not lost: the first transition is completed instantly, and the second is
  performed from it. Only a gesture whose horizontal shift exceeds the vertical one at the moment of recognition turns
  pages (the angle to the horizontal is less than 45°); a predominantly vertical gesture does nothing. After a layer
  change under the finger (reading bottom panel ↔ player panel, the player panel's view, the download row, a closed
  sheet, dialog or screen), the page and the controls do not accept taps for 350 ms (protection against a follow-up
  tap, D12, A§8.1); two deliberate presses more than 350 ms apart work as usual.
- **FR-R3.** Headings, paragraphs with a first-line indent, verse, quotes, separators and pictures are distinguishable
  on the page. A quote is styled differently from verse, by the rule in `docs/prototype/README.md`, "Book text
  styling": verse is italic with a left indent and no line; a quote is upright with the same indent and a thin vertical
  line of the `line` color along the block. There is one rule for measuring and for drawing. A picture is fitted to the
  page width and height together with the first line of the caption; a long caption and a heading longer than a page
  continue on the next one. A footnote reference opens its text over the page; a footnote mark has an enlarged touch
  area, and a tap in it takes priority over turning and showing the panels. The areas of adjacent marks overlap: the
  mark nearest the touch point opens.
- **FR-R4.** Table of contents: a list of chapters indented by level, the current one marked; choosing opens the start
  of the chapter.
- **FR-R5.** The book slider: moving by the fraction of characters; on release the page with that spot opens. Of the
  position in the book only the fraction is shown; there are no page numbers. The slider is available during listening
  too: a tap on the center shows the header and the slider above the player panel. It then turns only the screen, like
  turning by hand (A§5): the voice's place does not change, and following is switched off if the slider is released on
  another page. Touching the thumb without moving changes nothing.
- **FR-R6.** Font size (steps in `docs/mockup/NOTES.md`) and theme (system default, light, sepia, dark). The setting is
  shared by all books. The book text font is bundled in the app; the typeface is from `docs/mockup/NOTES.md`. The book
  text size is the step multiplied by the system font scale (`NOTES.md` records the opposite; the spec governs). The
  look of the "Text appearance" sheet and of the other screens follows the Flutter prototype (`docs/prototype/`), not
  the mock-up.
- **FR-R7.** The position is A§5: saved automatically, survives a change of font and window size, a restart and
  re-parsing (there is no rotation in the first version, only portrait orientation, D10). On a re-layout (font, a change
  of the player panel's height; a theme change does not cause a re-layout) the anchor is the voice's place (sounding,
  pause place, stop place) if the screen follows the voice; otherwise the start of the visible page. More important than
  both is a held paragraph selection for "Read from here": the selected paragraph and the button stay on the screen.
  While the layout is being recomputed, the screen does not turn pages: the page does not jerk back and forth.
- **FR-R8.** A narrow screen and a large system font (the combination from `docs/mockup/NOTES.md`) break nothing on any
  screen: heights follow the content; text wraps rather than being cut off (an ellipsis only for a book's title and
  author); buttons standing in a row stack into a column when the width runs out; the touch target of every control is
  at least 48 dp regardless of the visible size; fixed panels, headers and sheets take the system areas into account
  (notch, gesture bar). The test combination and the list of places are in `docs/mockup/NOTES.md`; the look follows the
  Flutter prototype. The condition holds in all five interface languages (FR-I1). The touch target is a 48 × 48
  rectangle not cut off by the rounding of the shape (the download row, the header). Orientation is portrait only
  (D10).
- **FR-R9.** Transitions between screens are A§8.1: what opens over reading without closing the book, what pauses, what
  closes the book, where the settings open from and where they return to. Transitions to the narration screens come
  with stage 2. The system "Back" on the reading screen (D11): 1) clears the paragraph selection; 2) closes a sheet,
  dialog, footnote; 3) if the reading panels are hidden, shows them, and the book is not closed; 4) if the panels are
  shown, closes the book. During listening it is the same: the first "Back" shows the header and the slider. The
  reason is the Android edge gesture: a swipe from the screen edge with gesture navigation is "Back", and a reader who
  turns pages from the edge must not close the book. The "Back" arrow in the reading header closes the book at once.
  This replaces rule f of the user-journey audit ("first hide the panels").

### Interface language (stage 1)

- **FR-I1.** The interface in five languages: Russian, English, Polish, German, Ukrainian (Ukrainian added by the
  owner's decision of 2026-11-17). By default the phone's language; if it is not one of the five, English. In the
  settings a "Language" item: "System default" and the five languages, each named in itself; the choice applies at once
  and is remembered. The strings are in ARB (`lib/screens/l10n/`), with the same keys in all five files; plural forms
  are ICU plural; numbers, percentages and money use the locale's format with a non-breaking space. The system Material
  labels are in the chosen language. The descriptions of the voices' character are interface strings and are
  translated. Google's error texts are shown as they are, untranslated. The book's language does not depend on the
  interface language.

### Gemini client (stage 2)

- **FR-T1.** The request, response parsing, limits, error classes: GEMINI_TTS.md, sections "Request", "Limits",
  "Errors"; the interface is A§6.2. An error carries `usage` if it was in the response. The client does not retry
  requests itself.
- **FR-T2.** The key goes only in a header; from any error text, shown or recorded, the key is scrubbed.
- **FR-T3.** The voice profile and the fingerprint are A§6.2. The audio format is part of the fingerprint.
- **FR-T7.** The reading-style text and the voice-probe phrase depend on the **book's** language, not on the
  interface's or the voice's: a per-language table in the `tts` module next to the voices
  (`lib/tts/book_language.dart`): ru, en, pl, de, uk; English for other languages. The style does not name the
  reader's gender (the voice may be female or male). The style is part of the profile, so the audio of a book in
  another language is not confused with the earlier one. The probe phrase for the app's voice (no book) is in the
  interface language.
- **FR-T4.** Splitting into segments is A§6.1: rules 1–4, skipping blocks with no speech text, the correspondence list,
  the readiness rule, parts and the start segment, the group tail. `L` and `Lmin` are named constants.
- **FR-T5.** `FakeTtsEngine` with controllable delay and errors. A build with fake synthesis is switched on by a build
  parameter, has a separate `applicationId` (A§6.2) and is visible in the settings by the "Fake voice" row.
- **FR-T6.** A real network transport is forbidden in the tests. The real client class with a dummy key and a fake HTTP
  is allowed and needed: it is used to check FR-T1, FR-T2, FR-P7.

### Queue, session, player (stage 2)

- **FR-Q1.** The queue is A§6.3 in full: a continuous reserve in listening time, priority of the nearest segment and a
  ban on new far requests while it waits for a retry, the finite boundary, up to two requests in the common count, the
  registry of in-flight requests held by the queue and one request per fingerprint, pause, retries, a permanent error,
  spending.
- **FR-Q2.** The session is A§6.4: the result of a previous session is saved and accounted for but does not change the
  player, position or state; a consumer of the current session that was waiting for someone else's request continues
  once the file appears.
- **FR-Q3.** The audio storage is A§6.5: a file is visible only when ready; a repeated write does not cause a new
  request.
- **FR-Q4.** Deleting a book and "Clear narration" during synthesis are A§4: they do not wait for network requests; a
  response that arrives later records the spending, the audio is discarded, the folder is not restored.
- **FR-P1.** The states and transitions of `NarrationController` are A§6.6: the table, the diagram and the items under
  it. There are no other states.
- **FR-P2.** Media session: a notification with the book and chapter title, pause/resume, previous/next; the same from
  the lock screen and the headset buttons. A call, foreign audio, unplugged headphones pause; the user resumes by
  themselves. In `paused` the notification is not removed and the service remains a foreground service (A§6.6).
  "Listen", "previous" and "next" from the notification, the lock screen and the headset turn on following the voice in
  the same way as from the player panel: these are controller commands, and the screen learns about them from its
  explicit-command counter (FR-P4, A§5). The player card in the notification and on the lock screen shows the book's
  cover; for a book without a cover, the same placeholder with the first letter as on the shelf (the owner's decision
  2026-11-14). There is no paragraph text and no seeking by seconds on the card.
- **FR-P3.** The start place is the rule of A§5 "Listen from `idle`" (from the owner's remark of 2026-11-14):
  - the listening place, the start of the segment that was sounding, is stored in `state.json` separately from the
    reading position and is not forgotten on pause, stop, "Close" and restart;
  - "Listen" from `idle`: (1) a listening place on the current page: continue from it; (2) otherwise from the first
    sentence that begins on the current page, the tail of a sentence from the previous page is not read; (3) if no
    sentence begins on the page, from the beginning of that sentence, and only then does the page move there.
    Sentence boundaries are A§6.1, rule 2 with clarifications (i) and (ii), over the speech text (a footnote mark after
    the period that begins the next sentence does not hide it). An accepted limitation: an abbreviation longer than one
    letter ("см. рис.", the Russian "see fig.") counts as the end of a sentence: the start comes slightly earlier or
    later, no text is lost;
  - after "Listen" the page is not turned back (except in case 3), following is on, and there is no "To current spot"
    button right after the start;
  - a long press on a paragraph → "Read from here" starts from the beginning of the paragraph. A start from a block in
    the middle of a group is the group tail; from a sentence inside a block, the start segment from that sentence
    (A§6.1). After a pause, ▶ continues from the pause place.
- **FR-P4.** Following the voice and highlighting are A§5; following is approximate. Following is **turned on** by any
  action with which the user themselves starts or changes the sound's place: "Listen" (including after a pause and from
  the error panel), "Read from here", the player's "previous" and "next", choosing a chapter in the table of contents,
  "To current spot", wherever the command comes from: the screen, the notification, the headset (the controller keeps
  a counter of explicit commands, and the screen turns following on when it changes; automatic transitions, the next
  segment or the end of a chapter, do not change the counter). It is **turned off** only by manual turning and the
  slider, including with the `stopped` panel open (an error or the end of the book), and only when the gesture really
  changed the page or the slider was released on another page: a small drag with a return to the same page, a
  cancelled gesture and touching the thumb without moving change nothing. The exception is a finger that grabbed the
  page during an automatic turn after the voice: it turns following off even if the page returned to the previous one
  (the reader held the page they were finishing). Choosing in the table of contents during listening always moves the
  voice to the start of the chosen chapter, including the current one. While a paragraph is selected for "Read from
  here", the page does not move away after the voice and a re-layout does not move it away; once the selection is
  cleared, the screen catches up with the voice. A paragraph selection is cleared on any page change: by a gesture, a
  tap, the slider, the table of contents, the voice; there is no invisible selection. The "To current spot" button is
  visible when following is off, in the control panel, in `preparing`, `playing`, `waiting`, `paused`. In `stopped` it
  is absent: in the error panel, "Listen" returns to the voice's place; in the "End of the book" panel there is only
  "Close". The slider during listening is FR-R5.
- **FR-P5.** Speed: 0.75; 1; 1.25; 1.5; 1.75; 2. It is remembered; every listening immediately sounds at the saved
  speed, both in the caption and in the voice's movement (there is one source of speed). A speed change makes no
  requests.
- **FR-P6.** The state on the reading screen is always named in words when there is no sound: "Preparing the voice…"
  (`preparing`), "Waiting for connection…" (`waiting`), the error text (`stopped` by error), "End of the book"
  (`stopped` by the end of the book). In `preparing` and `waiting` the state caption is in the top row of the panel,
  next to the voice chip and the "To current spot" icon; the panel's height does not depend on the state (A§5, the
  2026-11-15 decision). An explanation in our own words is given only for recognized causes: 402, 404 on the model, an
  invalid key (400/403 with a key refusal), no network; for other errors, Google's response as it is. From `stopped` a
  new session starts only by an explicit user command, "Listen" or "Read from here"; it does not start by itself,
  "previous" and "next" from the notification do nothing in `stopped`; no text promises an automatic continuation,
  including after topping up the balance. The "End of the book" panel has only "Close": neither "previous" and "next"
  nor "Listen".
- **FR-P7.** No key: "Listen" leads to the settings, to the key field. "Paste" saves the key from the clipboard at once;
  the field shows the saved key masked; a non-empty value in the field is saved on any departure from the field and
  from the screen, the keyboard's "Done", on-screen and system "Back", loss of focus; an empty field does not touch the
  key (there is no key deletion in the interface); "Back" returns to where the user came from; narration does not
  start by itself after the return. Response 402: a stop with a "Top up" button that opens the address from
  GEMINI_TTS.md. Response 404 on the model: a stop with a "Choose model" button; the panel names the model on which
  the error happened, not the one chosen afterwards; from the settings "Back" returns to the same book. An invalid key:
  an explanation in our own words and a "Change key" button leading to the open key field in the settings; "Back"
  returns to the book.
- **FR-P8.** "Close" (the cross on the player panel) ends listening: `idle`, the sleep timer cleared, the reading
  position is the place on the screen (the sounding place if the screen followed the voice; otherwise the start of the
  page the user turned to themselves, including after a stop), and then the screen writes it (A§5). "Finished" does not
  change at that (FR-L4). The listening place remains (FR-P3). On the transition to `stopped` the position is handed to
  the screen by the rule of A§5.
- **FR-P9.** Before acceptance SC-2, `docs/DEVICE_CHECKLIST.md` is created: the list of manual checks of A§9, one item
  for each "owner's phone" row; it includes: a pause with the screen off and, 10 minutes later, "Listen" from the lock
  screen; a second local build on top of the first without data loss. The gestures (the 2026-11-14 gesture audit) are
  **already at stage 1, on the first installation on the phone**, not only at SC-2:
  - 20 swipe-turns from the very edge of the screen in both directions, in reading and during listening, including
    with a phone case on: the book does not close (the edge "Back" gesture only shows the panels, D11);
  - slowly pull from the edge and return: the book does not close, the page stays in place;
  - 20 vertical thumb movements over the page: the page does not turn;
  - the page text is not under the camera cutout; the bottom row of the player panel is not in the "home" gesture zone.

### Voice and money (stage 2)

- **FR-V1.** Voice selection: 30 voices in two groups with a description of character; the current one is marked.
  Opening the screen pauses listening. The screen exists in two variants: a book's voice, with the book's title and a
  "Same as in Settings" row (the book has no voice of its own, the shared one applies); the shared voice from the
  settings, without this row. "Sample" is A§6.8: the phrase and the style follow the book's language (FR-T7), narrated
  with the full current profile (voice, model, style), a separate player, audio in `samples/`; a second time is free
  only for the same profile: after a model change the sample is narrated again; a voice row has three visible sample
  states: waiting, sounding, an error with Google's text.
- **FR-V2.** The app's voice is in the settings; a book may have its own, and it takes priority over the app's voice.
  The "Voice" entry for a book is both in the reading bottom panel and on the player panel: a book's voice is chosen
  even before the first listening. A change during listening is a new session from the start of the current segment
  (including a start one, begun from a sentence inside a block) with the previous intent (A§6.4). Touching the already
  chosen voice or model changes nothing and does not restart the session; choosing another row with the same effective
  voice ("Same as in Settings" and the same voice explicitly) does not either.
- **FR-V3.** Model: 3.8 Flash or Flash-Lite, in the settings, with the price per hour of audio by the tariff on today's
  date.
- **FR-M1.** Tariffs are constants with a check date and a change date (01.01.2027), as in GEMINI_TTS.md.
- **FR-M2.** `usage.json` accumulates audio and input tokens by month and model from the `usage` of responses and
  errors, each response once. The settings show the sum for the current and the previous month in dollars, each month
  at the tariff of its own period.
- **FR-M3.** The settings show the space taken by narration and a "Clear narration" button (all books and samples) with
  a confirmation; the order is A§4.

### Polish (stage 3)

- **FR-D1.** Sleep timer: 15, 30, 60 minutes, "until the end of the chapter", "turn off". The timer belongs to the
  controller: a change of place, chapter and voice in the same book does not reset it; minutes run by wall clock from
  the moment it was set (A§6.6). The timer is cleared when it fires, on "Close", on closing the book and on changing the
  book. A deadline that expired when no sound was playing: on pause the timer is simply cleared (the next "Listen"
  sounds); in `preparing` and `waiting`, a pause, and the timer is cleared. Before every explicit start ("Listen",
  "Read from here", "previous", "next", choosing a chapter) an expired deadline is cleared, including after a stop by
  error. "Until the end of the chapter" is the end of the chapter that is sounding at the moment of firing; the end of
  the last chapter (the end of the book) is also a firing. The queue's finite boundary accounts for the timer (A§6.3).
  An enabled timer is visible on the player panel: a minute one by the remaining minutes, "until the end of the
  chapter" by a text marker, not only by color.
- **FR-D2.** "Download chapter" is A§6.7. There is one task per app. The offer to download is in the current chapter's
  block in the table of contents and only when no task is running; the block with progress or an error belongs to the
  chapter the task belongs to, even if the reader is already in another. Before the button, on a separate line, an
  estimate: the sum of characters of the chapter's unique missing fingerprints × 0.069 s × the price per second, that
  is, after "Stop" and after an error only the unready remainder. In progress: the fraction ready and a "Stop" button.
  A permanent error is shown in the same block: the cause, Google's response and "Download again" with an estimate of
  the remainder; the player panel does not open. A chapter's readiness ("narrated") is the readiness rule of A§6.1 for
  the current voice profile: the readiness and estimate contract takes a profile. A change of voice or model stops the
  task (what is ready is kept), and the current chapter gets an offer with an estimate for the new profile. While the
  download is running, a short row with the fraction ready and a "Stop" button is visible on the reading screen; it
  disappears when the task has finished, been stopped or failed (the error is in the table of contents). The touch
  target of "Stop" is a 48 × 48 rectangle not cut off by the rounding of the row; a second follow-up tap on "Stop" when
  the row has already disappeared presses nothing (D12).
- **FR-D3.** A book has "Delete narration" in the shelf menu, with the amount; the order is A§4. The amount is computed
  from what is in the storage now: after "Clear narration", a new download and new probes take space again, and the
  deletion item and the clearing are available again.

## 4. Acceptance

Before each acceptance: the full `scripts/test.sh` is green in the main tree, `git status --porcelain` is empty, the
Codex review of the affected modules is done and its findings landed (`AGENTS.md`, "Specs and acceptance"). Each SC
includes all the checks of its stage from the table below.

- **SC-0.** A clean WSL after `setup-wsl.sh` passes `test.sh` and `build-apk.sh`. CI is green. The app with an empty
  shelf is installed on the owner's phone from the APK; a second local build goes on top of the first without
  uninstalling the app. The FR-E6 measurements are recorded.
- **SC-1.** Automatically: the FR-B7 samples with exact expected text and the invariants; the pagination of a
  300-thousand-character chapter shows the first page without waiting for the end of the computation; a killed adding
  leaves no book on the shelf; the screen screenshots match the golden (A§9: the owner approved the stage's screens on
  the phone, after which the screenshots were recorded as the golden). On the phone: the owner adds three of their own
  books (FB2, FB2.ZIP, EPUB) from a messenger and from downloads, reads, changes the font and theme, rotates the phone,
  closes the app; each opens at its own place.
- **SC-2.** Automatically, on fake synthesis: the scenarios of A§9 and in addition:
  1. a segment narrated in two parts at the start is not requested again in continuous reading; with one part ready,
     only the missing one is requested; "Read from here" from the middle of an already narrated group requests only
     the group tail;
  2. the nearest segment waits for a retry: no new requests for far segments, those begun are completed;
  3. a return to a fingerprint whose request was begun by a previous session: one request, the current session
     continues once the file appears;
  4. deleting a book and "Clear narration" during an in-flight request: deletion at once, the late response records
     the spending, no file or folder is left after it;
  5. the fake-synthesis build and the real one stand on the phone side by side; the real one does not see the fake
     one's books and audio.

  On the phone: `docs/DEVICE_CHECKLIST.md` passed on fake synthesis. Paid, with the owner's consent and an estimate
  named in advance: one chapter of one book listened to with the screen off; the sum in the settings matches the
  calculation from the responses' `usage`; re-listening to the same chapter from the start makes no request at all;
  the start pair at 2× speed: a pause between the parts is acceptable, its length is written into the report; with a
  large font, on a segment of several pages, the pages turn after the real voice.
- **SC-3.** Automatically: the 15/30/60 minute timers on a fake clock, including across a session change; the "until
  the end of the chapter" timer does not request segments of the next chapter; "Download chapter" after leaving and
  returning continues from the first unready segment, and after a manual "Stop" does not; the estimate counts identical
  text once; a book's "Delete narration" during an in-flight request. On the phone: a TXT book opens; a chapter is
  downloaded and listened to in airplane mode.

### Requirement → how it is verified

"Test" is an automated test in `scripts/test.sh`; "phone" is an SC item on the owner's phone.

| Requirement | Verified by | SC |
|---|---|---|
| FR-E1–E3 | clean WSL, build, CI | 0 |
| FR-E4 | the section's commands run from a clean WSL | 0 |
| FR-E5 | the direct-imports test | 0 |
| FR-E6 | the numbers are recorded in GEMINI_TTS.md | 0 |
| FR-B1 | a test of `speechText` and of the offset correspondences | 1 |
| FR-B2 | a test on samples: EPUB, FB2, FB2.ZIP, a foreign ZIP, PDF, a binary file, an EPUB with an obfuscated font, an EPUB with an encrypted document; a screenshot of the refusal row on the shelf for a protected book | 1 |
| FR-B3, FR-B4 | samples with the exact text of blocks, chapters and footnotes; for EPUB, one for each boundary rule and each structural sign of A§3 | 1 |
| FR-B5 | TXT samples: UTF-8, UTF-8 with BOM, windows-1251, with and without empty lines | 3 |
| FR-B6 | three samples of damage, a sample with another XML error, a sample with no text, a reference to a nonexistent footnote | 1 |
| FR-B7 | invariants on the samples and on `test/local_books/` | 1 |
| FR-L1 | tests: a killed adding, the last position change is recorded; manifest: `allowBackup="false"` and the extraction rules | 1 |
| FR-L2 | phone: the file picker and "Open with"; a test of the "Adding…" row | 1 |
| FR-L3 | test: adding again opens the existing book; the same file twice in a row is one book; a deleted book is added anew | 1 |
| FR-L4 | a shelf-order test (the card on the last opened one, unopened ones first below it, new ones on top; a new book does not take the card), the chapter on the card after a chapter change during listening, "100 %" after the last page (including a one-page book on first opening) and after the end of listening, "Close" at the end and re-listening to the last paragraph on the last page do not roll it back, moving to an earlier page does; cover placeholders, empty shelf | 1 |
| FR-L5 | test: a confirmation with the amount, the folder deleted | 1 |
| FR-L6 | a test of `tmp/` cleanup at startup | 1 |
| FR-R1 | test: the first page of a 300-thousand-character chapter before the computation ends | 1 |
| FR-R2, FR-R3 | gesture tests with real pointer events (`test/gesture_*_test.dart`): the boundaries of the thirds, slow and fast swipes, two swipes and a swipe with a tap in a row give +2 pages, a second tap after 40 ms gives +2 pages; a swipe at 10°, 30°, 44° to the horizontal turns, at 46°, 60°, 80° does not; a second finger during a swipe gives at most one page; a double tap on "Listen", "Close", "Stop", a choice in the speed and timer sheet: the second tap presses nothing, and after 400 ms the press works; two footnote marks side by side: the nearest opens; a tap near a footnote mark opens the footnote rather than turning or showing the panels; screenshots, including quotes and verse; phone: edge and vertical gestures (FR-P9) | 1 |
| FR-R4 | a table-of-contents test on an EPUB sample: levels, current chapter, navigation | 1 |
| FR-R5 | test: the slider opens the page with the chosen place; dragging past the edge gives the first and last page; during listening it turns only the screen and does not change the voice's place; touching the thumb without moving does not switch following off | 1; 2 |
| FR-R6, FR-R8 | screenshots at the font steps and in the `NOTES.md` combination, in all themes, with system areas; test: the touch target of every control is at least 48 dp, by hitting the corners of the 48 × 48 area, including "Stop" of the download row, and adjacent areas do not overlap; test: the app requests only portrait orientation, the manifest has `screenOrientation="portrait"` | 1 |
| FR-R9 | a test of each transition of A§8.1: the table of contents does not stop the sound, the "Voice" screen pauses, "Back" to the shelf is `idle`, return from the settings to the same book; system "Back": clears the paragraph selection, closes a sheet and dialog, with hidden panels shows them (including during listening, the sound goes on), with shown ones closes the book; the arrow in the header closes at once; phone: the edge gesture (FR-P9) | 1; 2 |
| FR-R7 | tests: the position after a font change, restart, re-parsing; a re-layout on pause near the bottom of the page (font, error panel, "Preparing the voice…") leaves the voice's place on the screen, and after manual turning (including after an error and the end of the book) the start of the visible page; a selected paragraph survives a change of the panel's height; a window-size change there and back gives the same place; phone: landscape orientation does not turn on | 1 |
| FR-I1 | test: all five ARBs have the same keys and placeholders; the phone's language by default, one not among the five gives English; the choice in the settings changes the labels at once, including the system Material ones; plural forms ru/pl/uk; screenshots of the shelf, reading, player, settings in en, pl, de, uk and narrow ones in de, pl and uk | 1 |
| FR-T1–T3 | tests of the real client with a dummy key and a fake HTTP: the request shape, error classes, `usage` in an error, the key scrubbed, the fingerprint changes with each profile field and the format | 2 |
| FR-T4 | tests of splitting, correspondences, readiness, parts, the group tail | 2 |
| FR-T7 | a test of the style table and the probe phrase: five languages (ru, en, pl, de, uk), others give English, a style without gender; the fingerprint changes with the style's language | 2 |
| FR-T5 | phone: SC-2, item 5 | 2 |
| FR-T6 | review before SC-2: there is no real transport in `test/` | 2 |
| FR-Q1–Q4 | queue and session tests: the scenarios of A§9 and SC-2, items 1–4 | 2 |
| FR-P1 | a test of each transition of A§6.6 on a fake player | 2 |
| FR-P2 | phone: `DEVICE_CHECKLIST.md`, including the cover (or the placeholder with a letter) on the notification and lock-screen card; test: "Listen" and "next" by a controller call bypassing the screen turn following on | 2 |
| FR-P3 | tests of the start place by the rule of A§5: the owner's scenario (a pause on a paragraph in the middle of a page → "Close" → "Listen": the same paragraph, the same page, following on); the listening place not on the page → the first sentence of the page, the same page; the tail of a sentence from the previous page is not read; a page inside one sentence → its start; right after "Listen" there is no "To current spot"; "Close" does not erase the listening place; "Read from here" starts from the beginning of the paragraph; continuing after a pause; a footnote mark after a period does not hide the start of the sentence; "fires / stays silent" pairs for rules (i) and (ii); the expected start of a sentence in the page tests is an independent check, not the same function; already in the prototype: `test/listen_owner_scenario_test.dart`, `test/listen_rule_test.dart`, `test/logic_review_test.dart`. The listening place in `state.json` after a restart: a test of the real `Library` | 2 |
| FR-P4 | a test of highlighting by the correspondence list; tests: following is turned on by "Listen" from pause and from the error panel, "previous", "next", the table of contents (including the same chapter: the voice goes to its start), "To current spot"; turned off only by turning and the slider, including after an error and the end of the book; a small drag with a return, a cancelled gesture and a gesture while the panel is appearing do not turn following off; an automatic transition to the next paragraph does not turn it on; a finger that grabbed the page during an automatic turn and returned it turns following off; a selected paragraph does not run away after the voice and is cleared by a page change; "To current spot" and the voice chip in `preparing` and `waiting`; phone: following with a large font | 2 |
| FR-P5 | test: a speed change makes zero requests, the speed is saved; the saved speed applies from the first sound, both in the caption and in the voice's advance over a second | 2 |
| FR-P6 | a test of the caption for each state without sound and both causes of `stopped`; an unrecognized error is shown as Google's response without an explanation; an invalid key gets an explanation; "End of the book" has only "Close"; from `stopped` the sound does not start without "Listen" or "Read from here" | 2 |
| FR-P7 | tests: no key, "Paste" saves, an entered key is saved on system "Back", the "Back" arrow and loss of focus, "Done" and "Back" on an empty key field do not erase the key, "Back" returns to the book without starting narration; 402, 404 on a fake HTTP; after 404 and choosing another model the panel names the previous one; an invalid key → "Change key" → the key field → "Back" to the book | 2 |
| FR-P8 | a test of "Close" (when following and after manual turning) and of handing over the position at `stopped`; "Close" clears the sleep timer | 2 |
| FR-P9 | the file exists and has been passed; the gesture items were passed already at the first installation at stage 1 | 1 (gestures); 2 |
| FR-V1 | test: the voice screen pauses; a second sample without a request; after a model change the same voice's sample is narrated again; the sample is within the common limit; three states of a sample row; screenshots of both screen variants | 2 |
| FR-V2 | test: a book's voice takes priority over the app's; choosing a book's voice in `idle` from the bottom panel; a change from `paused` keeps the pause; a profile change after a start from a sentence inside a block starts from the same sentence; touching the already chosen voice or model does not reset the pause place | 2 |
| FR-V3, FR-M1 | a price test on a fake date before and after 01.01.2027 | 2 |
| FR-M2 | a test of the sums for the current and the previous month at the tariff boundary; an error with `usage` is counted once | 2 |
| FR-M3 | test: the space is shown, after clearing `audio/` and `samples/` are empty; clearing during a request | 2 |
| FR-D1 | timer tests on a fake clock: "Close", leaving for the shelf and changing the book clear the timer, a change of place does not; the deadline expired on pause: "Listen" sounds; expired in `preparing` and `waiting`: a pause; expired after an error: "Read from here" sounds; "until the end of the chapter" from the sheet: a pause at the start of the next chapter; the end of the last chapter clears the timer; a screenshot of the panel with the "until the end of the chapter" timer | 3 |
| FR-D2 | tests of the estimate, the fraction ready, "Stop", leaving and returning; the estimate after "Stop" is exactly the unready remainder and a proportional price; the task's block at its chapter when the reader is in another, and no second offer; a change of the book's voice: "narrated" is cleared, the task stopped, an estimate for the new profile; the chapter's block on a permanent error, after completion and after a stop, the player panel does not open; phone: airplane mode | 3 |
| FR-D3 | a test of deleting a book's narration, including during a request; after "Clear narration" a chapter downloaded anew takes space again | 3 |

## 5. Out of scope

Everything from section 7 of the concept and section 10 of the architecture. Separately, so that it does not come back
during implementation:

- text search, bookmarks, highlights, notes;
- hyphenation by syllables, justification, choice of typeface;
- applying CSS from EPUB, tables as tables, formulas, audio and video inside EPUB;
- a bookshelf with folders, sorting and search;
- playing the streaming response, word-by-word highlighting;
- a page number within a chapter or book: only the fraction of the book;
- automatic resumption after a call and other interruptions;
- a pause between segments without a need confirmed by ear; between parts of one block, never;
- recovery from any wrongly declared encoding: only the three kinds of damage of A§3;
- background chapter download while the app is closed; downloading any chapter except the current one;
- a mini-player on the shelf: the player panel exists only on the reading screen;
- a home-screen widget; paragraph text and seeking by seconds on the notification card (owner's decision 2026-11-14);
- landscape orientation: the first version is portrait only (D10);
- user editing of the reading style: there is one style, chosen in code;
- a spending statistics screen more detailed than two sums;
- app update checks, crash reports;
- keeping data when the app is uninstalled (`hasFragileUserData`): on uninstall Android erases everything: books,
  positions, narration, the key; there is no "keep data?" question (owner's decision 2026-11-15: the standard behavior
  is more correct).
- A separate color for a paragraph selected by long press: it is highlighted in the same color as the sounding one
  (owner's decision 2026-11-16).
- Fixing the shift of the "Text appearance" sheet on a theme change (owner's decision 2026-11-16: do not fix).

## 6. Anti-regression

- The tests do not call Gemini: there is no real network transport in the tests. Paid calls follow the `AGENTS.md`
  rule, "Money": a small measurement without asking, SC-2 acceptance with the owner's consent.
- The parsing rules are general, by the structure of the file; no test and no rule names a particular book.
- The key does not appear in logs, error texts, screen screenshots or the repository.
- Other people's books do not enter the repository: the samples are our own, the owner's books are in
  `test/local_books/` outside git.
- What is visible only on the phone is not declared verified by widget tests.
- The tone of the fake build does not enter the real one's storage.

## Changelog

- 2026-11-14 — a draft from architecture version 2.
- 2026-11-14 — after the Codex review ([CODEX_REVIEW_SPEC_2026-11-14.md](../reviews/CODEX_REVIEW_SPEC_2026-11-14.md)),
  all 22 findings accepted, the architecture raised to version 3. Four stages; FR-L1, FR-L2, FR-M3, FR-D3 distributed
  across the stages; FR-E6, FR-Q4, FR-P8, FR-P9 added; FR-B2, FR-B4, FR-B6, FR-B7, FR-T1, FR-T4–T6, FR-P2, FR-P5,
  FR-P6, FR-V1, FR-M2, FR-D1, FR-D2 rewritten; automatic resumption after a call and the promise about any encoding
  removed; acceptance supplemented with the scenarios of findings 1–5 and the "requirement → how it is verified" table.
- 2026-11-14 — after the Codex mock-up review ([CODEX_REVIEW_MOCKUP_2026-11-14.md](../reviews/CODEX_REVIEW_MOCKUP_2026-11-14.md)):
  open questions to the owner in section 1; FR-R9 added (transitions, A§8.1); FR-R8 rewritten (narrow screen, touch
  targets, system areas); FR-B2, FR-R3, FR-R5, FR-P4, FR-P6, FR-P7, FR-V1, FR-V2, FR-D1, FR-D2 and the table of checks
  supplemented; in "Out of scope": a mini-player on the shelf and downloading a chapter other than the current one.
- 2026-11-14 — after the Flutter prototype and its Codex review
  ([CODEX_REVIEW_PROTOTYPE_2026-11-14.md](../reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md)) and the owner's decisions:
  the look of the screens is set by the prototype (`docs/prototype/`), the FigCraft mock-up is a reference for the set
  of screens; FR-R3: the quote and verse styling rule from the prototype README, the picture together with the first
  line of the caption, a long heading and caption continue; FR-R6, FR-R8: the steps and the test combination are still
  from `NOTES.md`, the look from the prototype; FR-I1 (the interface in ru, en, pl, de) and FR-T7 (style and probe
  phrase by the book's language) and rows of the checks table added.
- 2026-11-14 — from the owner's remark of 2026-11-14 (prototype, "Ионыч" — "Ionych" — a pause on a paragraph in the
  middle of a page → "Close" → "Listen": the page turned back, the previous long paragraph sounded, "To current spot"
  is visible): FR-P3 rewritten: the listening place is stored separately from the reading position and is not
  forgotten; "Listen" from `idle` continues from it if it is on the page, otherwise starts from the first sentence that
  begins on the page, does not turn back and turns following on. The earlier "from the first block on the screen" and
  the decision on finding No. 11 of the prototype review ("from the visible tail of a paragraph") are replaced. FR-P8
  refined: "Close" when following writes the sounding place. A§4 (`state.json`), A§5, A§6.1 (the start segment from a
  sentence inside a block) and a row of the checks table aligned.
- 2026-11-14 — from the independent user-journey audit of 2026-11-14
  ([JOURNEY_AUDIT_2026-11-14.md](../reviews/JOURNEY_AUDIT_2026-11-14.md); an internal audit by an agent, not a review by
  another engine): 16 findings and rules a–k for the gaps (accepted by the owner 2026-11-14). Rewritten: FR-L4 (the
  "Continue" card only for a book that has been opened, unopened ones first, the card's chapter by position,
  "finished"), FR-P4 (what turns following on and what turns it off; the table of contents during listening moves the
  voice to the start of the chapter; a selected paragraph does not run away), FR-P6 (the state caption on a separate
  row, an invalid key is a recognized cause, "End of the book" only "Close"), FR-P7 (an empty "Done" does not erase the
  key, 404 names the model of the error, "Change key"), FR-D1 (when the timer is cleared and what an expired deadline
  does without sound), FR-D2 (one task, the block at its chapter, the remainder, the profile in the readiness contract,
  a voice change stops the task). Supplemented: FR-R2 (a second tap during the animation), FR-R7 (the re-layout
  anchor), FR-R9 (the system "Back" first closes the temporary), FR-P2, FR-P5 (the saved speed from the first sound),
  FR-P8 (clears the timer, does not roll back "finished"), FR-V2 (touching the selected one), rows of the checks table.
- 2026-11-14 — after the Codex behavior-logic review
  ([CODEX_REVIEW_LOGIC_2026-11-14.md](../reviews/CODEX_REVIEW_LOGIC_2026-11-14.md)), 10 findings accepted, and by the
  owner's decisions of 2026-11-14. FR-L4: "finished" is a separate fact (set by the last page, including the first
  layout of a one-page book, and by the end of listening; cleared only by showing a page earlier than the last): the
  contradiction with the old "earlier than the finishing place" in A§5 is removed. FR-P4: following is turned on by the
  controller's explicit-command counter (including from the notification and the headset), turned off only by a gesture
  that changed the page, or by the slider, including in `stopped`; "To current spot" only in the control panel, absent
  in `stopped` (the contradiction with the "End of the book" panel is removed). FR-P6: from `stopped` a new session is
  "Listen" or "Read from here" (the contradiction of "only an explicit 'Listen'" with the contract is removed). FR-V1:
  the probe phrase follows the book's language (FR-T7), the probe uses the full profile (the contradiction with "one
  constant phrase" is removed). FR-P3: sentence boundaries are rules (i) and (ii) of A§6.1 over the speech text, the
  accepted limitation is recorded. Supplemented: FR-R7 (a paragraph selection beats the re-layout anchor), FR-P2
  (commands from outside; a cover or placeholder on the notification card, the owner's decision), FR-P5 (one source of
  speed), FR-P8, FR-V2 (a profile change starts from the start segment), FR-D1 (an expired deadline before any explicit
  start, the end of the last chapter), FR-D3 (the amount by the storage after clearing), "Out of scope" (a home-screen
  widget, paragraph text and seeking on the notification card), rows of the checks table. Rules a–k of the journey audit
  and the implementer's interpretations of them were accepted by the owner on 2026-11-14.
- 2026-11-14 — from the gesture audit of 2026-11-14 ([GESTURE_AUDIT_2026-11-14.md](../reviews/GESTURE_AUDIT_2026-11-14.md);
  an internal audit by an isolated agent, not a review by another engine): 9 findings, the orchestrator's decisions A–K.
  Added decisions D10 (portrait orientation only), D11 (the order of the system "Back" in reading: show the panels
  rather than close the book; reason: the Android edge gesture; replaces rule f), D12 (protection against a follow-up
  tap, 350 ms). Supplemented: FR-R2 (what turns pages: an angle under 45° to the horizontal; the follow-up tap), FR-R3
  (the nearest footnote mark), FR-R5 (touching the thumb without moving changes nothing), FR-R7 (there is no
  rotation), FR-R8 (the touch target is not cut off by the shape, portrait), FR-R9 (the new "Back" order), FR-P4 (a
  finger during an automatic turn; the selection is cleared by a page change), FR-P7 (the key is saved on any departure
  from the field and the screen), FR-P9 (gestures on the phone already at stage 1), FR-D2 ("Stop"), "Out of scope"
  (landscape orientation), rows of the checks table.
- 2026-11-15 — implementation of stages 0 and 1 (Codex agents, an experiment: [EXPERIMENT_CODEX_IMPL.md](../reviews/EXPERIMENT_CODEX_IMPL.md))
  and an external review of stage 1 by two Fable 5.2 agents ([FABLE_REVIEW_001_STAGE1_2026-11-15.md](../reviews/FABLE_REVIEW_001_STAGE1_2026-11-15.md)):
  21 groups of findings, the accepted ones fixed with tests, the rejections recorded there with reasons. The
  architecture refined: named XHTML entities are expanded; an EPUB table-of-contents entry for a document without
  chapter text creates no entry; corrupted data does not crash startup, book deletion goes through `tmp/`; the layout
  is computed from the place, the start is from the seen line or the start of the block; a re-layout keeps the start of
  the shown page. Implementers' decisions accepted by the orchestrator: a book file larger than 256 MiB is rejected as
  unsupported; a book opened from another app opens at once after adding, one chosen with the "+" button stays on the
  shelf; the system "bold text" does not apply to the book text (measuring and drawing use one style);
  `launchMode="singleTask"`. 36 golden screenshots were retaken: three because of the shelf's bottom inset, 33 because
  of the layout from the place (a scene's page starts from the start of a paragraph); the styling did not change. SC-0
  passed, except for the FR-E6 measurements. SC-1 not passed: the phone and the owner's books.
- 2026-11-15 — a check of stage 1 on the owner's phone (via `adb`, the owner's books in FB2) and on `test/local_books/`
  (three FB2: parsing without refusals, the FR-B7 invariants hold). Working: adding with the "+" button, "Open with"
  into the live app (one instance), turning, the table of contents, the slider, font and theme, the place after a
  killed process, the system "Back", deletion, returning from "Recents" without reopening the file. Five defects found
  and fixed. The orchestrator's decisions: `VIEW` and `SEND` accept `application/octet-stream` with no condition on the
  name: otherwise the app is not offered for an FB2 from the file manager (type "binary file", an opaque address); the
  price is that the app is in "Open with" also for foreign binary files (FR-L2). A chapter without a title is shown in
  the table of contents, on the shelf card and in the header by the beginning of its text (FR-R4). The fraction of an
  unfinished book is at most 99 %, "100 %" only for a finished one (FR-L4). Not checked on the phone: the footnote
  window, the system "bold text", EPUB and FB2.ZIP (the owner has no such books in the set), the FR-P9 gestures by the
  owner's hand.
- 2026-11-15 — a repeat check on the phone after the fixes: an FB2 as a "binary file" with an opaque address is accepted
  by the app (while a ZIP, PDF and picture with such an address are not), the system bars follow the theme, the table of
  contents ends above the button panel, a chapter without a title is captioned by the beginning of its text, the
  footnote window opens. From the owner's book: the `title` of an FB2 footnote section is its mark and does not go into
  the footnote text (FR-B3); the parsing version is 3.
- 2026-11-15 — **stage 1 accepted by the owner (SC-1)**. Stage 2 "Narration" begun. The owner will turn on the
  measurement on a mobile network (FR-E6) when it is needed; `L`, `Lmin` and the reserve target before it are the
  starting values of A§6.1, A§6.3.
- 2026-11-15 — the owner's decision on the paid SC-2 acceptance: it is not necessary to read a whole chapter: the owner
  selectively listens to different paragraphs with the real voice themselves. The SC-2 items "the sum in the settings
  matches the calculation from `usage`", "repeating the same place makes no requests", "the start pair at 2×" and "the
  pages turn after the voice" are checked on those same paragraphs, without a separate chapter.
- 2026-11-15 — the owner's question about cleanup on app uninstall. Checked in the code: everything is stored in the
  app's internal folder and its cache (books, audio, settings, spending; temporary files in `tmp/` and the cache,
  cleaned at startup), the key in the protected storage; the app writes nothing to shared storage. Android deletes this
  together with the app. We will not keep data on uninstall: recorded in "Out of scope". Not checked on the phone.
- 2026-11-15 — the first check of stage 2 on the phone, a build with a fake voice (`.fake`), via `adb`. Found and fixed:
  the app crashed at startup: `MainActivity` accessed the platform channels in `onCreate`, while
  `FlutterFragmentActivity` configures the engine later; the tests could not show this. After the fix, working: taking
  a book through "Open with", "Listen" (waiting, then sound), highlighting and the page following the voice, sound with
  the app minimized by a service of the "media playback" type, the system card with the cover, title and buttons
  (seeking is not enabled), pause, resume and "next" by media keys, the notification stays on pause, "Close" removes
  the session; the AAC encoder writes audio (≈ 1 MB per several minutes); the fake build stands next to the real one.
  The owner by ear: the tone is continuous. Noticed: the fake build shows in "Spent" a sum from fake tokens: there is
  no money behind it. Not checked: the real voice, the screen off, the lock screen, the headset, a call, "Download
  chapter", uninstalling the app.
- 2026-11-15 — the owner's first listening with the real voice on the phone. **Voice and speed accepted:** "the voice
  sounds great, the pauses are only for preparing an audio segment, no complaints about the speed or the voice". Found:
  after "next" a one-line page and following switched off (being fixed). The owner's decision: "previous" and "next"
  move by paragraphs, not by segments (A§6.6); a paid request only when moving to the middle of a group of short
  paragraphs.
- 2026-11-15 — the owner's clarification by ear (real voice, home network): in the middle of steady listening there are
  no pauses, the transitions between paragraphs are natural; waiting only at a new start. The AAC file joins and the
  120 s reserve are confirmed on this network; there is no need to add a pause between segments (A§6.6, A§11).
- 2026-11-15 — the owner's remark: after a pause, turning and "resume" the screen returned to a page re-laid out from
  the voice's place (the sounding fragment at the top). The rule in A§5: returning to a place that lies on an
  already computed page shows that page without changing the text's position (FR-P4, FR-R7).
- 2026-11-15 — from the owner's remarks from the phone (branch `s002-nav`): "next" showed a one-line page: the target
  chosen was a shortened page before the layout's start place; after a player command following was switched off: it
  was switched off by the completion of the earlier turning. Fixed. "Previous/next" moved to paragraphs, returning to a
  seen place shows the same page (A§5, A§6.6). The chapter title on the "Continue" card and in the reading header is at
  most two lines with an ellipsis (on the phone a long title took eight lines); the earlier "wraps without limit" is
  cancelled. Not yet checked on the phone.
- 2026-11-15 — stage 3, TXT books (branch `s003-txt`): parsing per FR-B5, accepting `.txt` / `text/plain` by the "+"
  button, "Open with" and "Share" of a file; text without a file (`EXTRA_TEXT`) is not accepted. The book's title is
  the file name without the extension. FR-B5 refined: the "a paragraph is a line" rule turns on when there is no empty
  line between lines of text; empty lines only at the beginning and end of the file do not count. Left by the rule,
  without heuristics: a hyphenated word break at the end of a line becomes "Пере- нос" (a word split across a line
  break, "Pere- nos"), a heading without an empty line is glued to the text. Not checked on the phone.
- 2026-11-15 — a check on the phone (fake build): "previous/next" go by paragraphs, the pages are full, following after
  the commands is on; a windows-1251 TXT book opens through "Open with". Returning to a seen page at first did not work
  on the phone: the "To current spot" button changes the panel's height, and the layout was recomputed; the screen now
  keeps the previous layout (branch `s002-nav3`), the repeat check on the phone passed. Added along the way: following
  turns on by itself when the voice has reached the shown page (A§5): awaiting the owner's word.
- 2026-11-15 — an external review of the "transitions and TXT" batch
  ([FABLE_REVIEW_001_NAV_TXT_2026-11-15.md](../reviews/FABLE_REVIEW_001_NAV_TXT_2026-11-15.md)): NEEDS WORK, no
  blockers. Fixed (branch `s003-revfix`): the language of a book without a language in the file is fixed at adding:
  the interface language at that moment, books already on the shelf do not change (the owner's decision 2026-11-15:
  "ok, especially since txt will hardly ever be needed"); "Share" without a file is silently ignored; of a TXT title
  only `.txt` is cut off; an empty title does not crash the cover placeholder. Findings on the reading screen fixed
  (branch `s002-nav3`).
- 2026-11-15 — the owner's remark: after "next", turning back shows a cut-off page (half a screen or a few lines); and
  his question: "why can't we keep that view with the text that was before turning back?". Both done (branch
  `s002-nav5`, A§5): a nearby target continues the previous layout instead of starting a new one; the pages before the
  start place of a far layout are collected backwards and are full, with a repeat of a few lines only between the
  first and second page of a chapter. The earlier assumption "a short page before the start place" is cancelled. Not
  checked on the phone. The owner asked for an app icon of their own and to leave one app on the phone: the icon is made
  (`docs/logo.svg`), the fake-voice build is removed from the phone.
- 2026-11-15 — CI on GitHub had been red for about fifteen pushes in a row: the APK build ran out of disk space on the
  runner ever since the player and the media service appeared. The orchestrator did not notice: it only compared the
  local run. Disk cleanup added to CI; the run is green.
- 2026-11-15 — the owner's decision: following turns on by itself when the voice has reached the shown page: keep
  (A§5).
- 2026-11-15 — the owner doubted that the cause of the defects "the text is not what I saw" had been found and asked for
  two independent reviews of the reading screen (Opus 5.5 and gpt-6-astra, both high;
  [READER_SCREEN_REVIEW_2026-11-15.md](../reviews/READER_SCREEN_REVIEW_2026-11-15.md)). Both agreed: the page height
  depended on the player panel's state, and the transition between pages has no single owner. The owner's decision: the
  "To current spot" button as an icon. Done (branch `s004-stable`): the panel's height is constant, the state caption
  moved to the top row (FR-P6 changed), the code around the changing height removed, the control defects found by the
  review fixed, a frame-by-frame screen property test added. Not done: lazy backward computation deep in a long
  chapter; a full replacement of the navigation model was not needed in the scenarios checked. Not checked on the
  phone.
- 2026-11-16 — the reading screen after the `s004-stable` work was checked on the owner's phone (fake build from
  `b50dae1`, the orchestrator via adb): on "Listen" the text is not re-laid out either for "Preparing the voice…", or
  when the sound starts, or when the system bars hide; after "next" ×3 and a pause the very first "previous" tap turns,
  the pages are full, the text between adjacent pages is not torn; "resume" returns the same page with the same
  boundaries; "To current spot" is an icon, the panel's height does not change. Not measured: the delay of the first
  "previous" deep in a long chapter. The fake build is removed from the phone: there is one app on it. The real voice
  is checked by the owner.
- 2026-11-16 — a full check on the phone per [DEVICE_CHECKLIST.md](../DEVICE_CHECKLIST.md), at the owner's request ("so
  that I do not find primitive bugs myself"); two tester agents (Sonnet) went through it via adb, release builds. Fake
  build: shelf, "Open with" (FB2, no duplicate), reading (gestures, table of contents, slider, font, themes, footnote,
  the place after a restart), player (following, pause, transitions, "To current spot", "Read from here", speed, sleep
  timer, voice and probe, end of chapter and book, "Download chapter", "Delete narration"), background (notification,
  headset buttons by emulation, return): no functional remarks, except for one defect. The defect: the notification
  and the foreground service remained after the end of the book, closing the player and closing the listening with
  another book: the `audio_service` package on idle calls only `stopSelf`, and drops the foreground in `onDestroy`,
  which does not occur while the app is bound. Fixed (`s009-notification`): a `stopForeground` command in
  `MediaServiceChannel.kt` (reflection to the `instance` field of the pinned `audio_service` 0.18.19: check it when
  updating the package), a new "Listen" waits for the removal. Checked on the phone on a release build: seven scenarios,
  three "listen → close" cycles. Also fixed: the voice chip cut off a long name with free space available
  (`s008-voice-chip`; two golden screenshots of the narrow screen retaken: the name now fits there). Real build: one
  "Listen", sound after 6.8 s, spending 0.38 $ → 0.40 $. Not checked: the screen off and the lock screen, a call,
  headphones, foreign audio, a large system font, EPUB / FB2.ZIP / TXT on the phone (there are no such files on it),
  the speech by ear. Open remarks on the look, without the owner's decision: the selected and the sounding paragraph are
  highlighted in one color; the "Text appearance" sheet shifts on a theme change.
- 2026-11-16 — the owner's decisions on two look remarks from the phone check: the selected paragraph stays the same
  color as the sounding one; the shift of the "Text appearance" sheet on a theme change is not fixed. Both recorded in
  "Out of scope".
- 2026-11-16 — the owner's decision: after choosing a chapter in the table of contents, the reading screen's panels (the
  header and the bottom panel with "Listen") do not flash, the screen shows at once without them; which paragraph to
  listen from, the reader chooses themselves. Done (`s011-toc-panels`): on choosing a chapter in `reader_screen.dart`
  the keys of two `_Slide`s change, the panels are recreated already hidden (+6/−1 lines); the test
  `test/reader_screen_toc_panels_test.dart` has three frame-by-frame cases: choosing a chapter (no panels in any
  frame), the cross and the system "Back" (the panels stay). Checked on the phone the same day (release build, number
  2, a screen recording of two transitions frame by frame): no panels in any frame.
- 2026-11-17 — Ukrainian (uk) added as the fifth interface language by the owner's decision: FR-I1 (five languages, the
  "Language" item, five ARB files), FR-R8 and FR-T7 (the book-language table: ru, en, pl, de, uk; an unknown language
  such as cs still falls back to English), rows FR-I1 and FR-T7 of the checks table. The documents were also translated
  into English in preparation for open-source publication.
