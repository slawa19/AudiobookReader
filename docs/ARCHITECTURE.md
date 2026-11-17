# Architecture

Version 3 of 2026-11-14: after the review of spec 001 ([reviews/CODEX_REVIEW_SPEC_2026-11-14.md](reviews/CODEX_REVIEW_SPEC_2026-11-14.md));
supplemented after the mock-up review ([reviews/CODEX_REVIEW_MOCKUP_2026-11-14.md](reviews/CODEX_REVIEW_MOCKUP_2026-11-14.md)).
Version 2 followed the architecture review ([reviews/CODEX_REVIEW_ARCH_2026-11-14.md](reviews/CODEX_REVIEW_ARCH_2026-11-14.md))
and the measurement of Gemini latency ([GEMINI_TTS.md](GEMINI_TTS.md), section "Latency and synthesis speed"). It
describes the first version of the app from [CONCEPT.md](CONCEPT.md): Flutter, Android, a single user.

The **[measurement]** mark stands where a number still awaits measurement on the phone; next to it are the starting
value and what it is derived from.

Package names are candidates. Versions and the choice itself are confirmed at installation against current
documentation; each package is hidden behind its own module.

## 1. Key decisions

| No. | Decision | Why |
|---|---|---|
| A1 | One book model for all formats | the screen, narration and position do not know about formats; a new format is one parser |
| A2 | Parsing happens once, at adding; the result is stored as a file | opening a book does not depend on the quirks of the source and does not repeat the parsing |
| A3 | No database: a folder per book with JSON files in it; they are written by one sequential writer | there are dozens of books on the shelf; no schema, migrations or code generation |
| A4 | The app draws the text itself, and pages are computed in portions as needed | we need to know which text is on the screen, highlight it and turn pages after the voice |
| A5 | The unit of narration is a segment: a group of short blocks, a block, or a part of a long block | one request shorter than ≈ 70 characters is synthesized slower than it sounds at 1×; a long one hits Gemini's limit |
| A6 | A segment's audio is stored under a name that is a fingerprint of the text and the voice profile | a repeat is free; a change of voice does not confuse old with new |
| A7 | The player plays ready files; the synthesis queue keeps a continuous reserve ahead | the network and Gemini are decoupled from playback; a network failure is not heard while there is reserve |
| A8 | Every asynchronous operation belongs to a listening session | a response that arrives after a pause, a chapter change or a voice change does not touch the player or the position |
| A9 | Everything platform-specific is in one module | the rest is tested in WSL without a phone |
| A10 | No state or dependency-injection frameworks | three screens and one player; `ChangeNotifier` and constructor passing are enough |

## 2. Modules

One Flutter package, directories in `lib/`. Below are all the direct imports allowed between modules; there are no
others.

```
app      ──► all modules (the composition root: creates the objects and wires them together)
screens  ──► reader, playback, library, audio, tts, book
reader   ──► book
playback ──► tts, audio, library, book
library  ──► book
tts      ──► book
platform ──► audio, library   (implements their interfaces)
audio, book — none
```

| Module | Responsible for | Does not know about |
|---|---|---|
| `book` | the book model, the FB2 / EPUB / TXT parsers, format and encoding detection, the speech text | Flutter, the app's file system |
| `library` | the shelf: adding, deleting, book folders; the sole writer of position, book settings and spending; app settings (theme, size, speed, voice, model, interface language) | screens, the player |
| `reader` | pagination, drawing a page, highlighting | narration, the network |
| `tts` | the Gemini client, the voice profile, the fingerprint, splitting into segments, error classes, fake synthesis, the voice list and model prices | the player, files |
| `audio` | the storage of segment and probe audio: write PCM, hand out a file, count and clear the space | Gemini, the book |
| `playback` | the listening state, the synthesis queue, the voice probe, the link with the player and the media session, today's tariffs and spending by month | drawing |
| `screens` | shelf, reading, table of contents, voice, settings; the interface strings (ARB, `lib/screens/l10n/`) | HTTP, formats |
| `platform` | Android code: the audio encoder, receiving a file from another app | the app's logic |
| `app` | dependency assembly, routes, theme | — |

- `book` and `tts` are pure Dart without Flutter.
- The interfaces of the encoder and of file receiving are declared in `audio` and `library`. `platform` implements
  them, `app` plugs the implementations in; apart from `app`, nobody depends on `platform`.
- `playback` saves the position and spending through `library` itself: with the screen off there are no screens.
- `screens` takes only the used space from `audio`; only `playback` deletes audio (section 4).
- The interface strings live in `screens`, not in `app`: the screens read them, and `screens` may not import `app`.
  The app settings are kept by `library`; the voice and model there are strings, because `library` does not know
  `tts`.

## 3. Book model

```
Book      { id, title, author, language, chapters[], parserVersion, totalChars }
Chapter   { title, level, firstBlock, blockCount }
Block     { index, kind, text, spans[], imageId? }
  kind:   heading | paragraph | image | verse | cite | separator
Span      { start, end, style: italic | bold | sup | sub | noteRef(noteId) }
Note      { id, blocks[] }
```

- **Blocks are numbered through the whole book**; the number is stable for a given `parserVersion`.
- **A block's text is a string without markup**; emphasis styles are stored separately as ranges.
- **The unit of all offsets** (`offset`, `Span.start/end`, `charsBefore`, segment boundaries) is the UTF-16 code unit,
  that is, a Dart string index. All offsets are counted over `Block.text`.
- **Read aloud:** `heading`, `paragraph`, `verse`, `cite`. Not read: `image` with a caption, `separator`, footnotes,
  the table of contents from the book file, FB2 service sections (`description`).
- Tables in the first version are turned into paragraphs, one per row.

**Speech text** is the pure function `speechText(block)`: the block's text without the `noteRef` ranges and without
the stress mark U+0301. Together with the text it returns the mapping of offsets back into `Block.text`. A block whose
speech text is empty or contains no letter and no digit ("* * *", "…", footnotes only) is not read aloud: it creates
no segment and does not go to Gemini as a request (a refinement from the 2026-11-15 review). The fingerprint is
computed from the speech text.

**Chapters are a linear partition.** Rules common to all formats:

- every block of the main text belongs to exactly one chapter and is read once;
- chapters follow one another with no gaps or overlaps; the text before the first heading is a chapter without a
  title;
- nesting is expressed only by the `level` field. A section that has its own text before the first subsection (a
  heading, an epigraph, an introduction) is itself a chapter; a subsection starts the next one;
- "until the end of the chapter" means "until the first block of the next chapter of any level".

FB2: a chapter is a `section`; the heading, epigraph and annotation of a section are its blocks.

EPUB: the order is by `spine`; the table of contents (`nav` or `toc.ncx`) gives titles and levels. A table-of-contents
entry sets a chapter boundary as follows:

- the relative path of the link is resolved from the table-of-contents document;
- a link without a fragment is the start of the document;
- a fragment points to an element: the boundary is at the first block that starts at or after that element (the block
  itself; the first block inside a container; for an empty anchor, the next block). Element not found: the start of
  the document;
- several entries for the same start produce one chapter with the title and level of the first entry in order;
- an entry that has no block of main text before the next entry (a document with a cover alone) creates no chapter and
  does not take someone else's start; an entry linking to an external address is skipped;
- a `spine` document with no entry in the table of contents continues the current chapter.

Structural signs of EPUB; an element without them is plain text:

- a footnote is an element with `epub:type` `footnote`, `endnote` or `rearnote`, including an `aside` with such a type;
  a reference to it is `epub:type="noteref"`;
- an in-body table of contents is a `nav` document and elements with `epub:type="toc"`; they yield no blocks of main
  text;
- a picture caption is `figcaption`.

Footnote identifiers are unique within an EPUB document, so `noteId` includes its name. In both formats a reference to
a nonexistent footnote remains plain text without `noteRef`.

**Format detection is by content, not by extension**, in this order:

1. a ZIP with an EPUB `mimetype`: EPUB;
2. a ZIP with a single `.fb2` inside: FB2;
3. XML with the root `FictionBook`: FB2;
4. any other ZIP and PDF (the file starts with `%PDF`): the refusal "This format is not supported";
5. no bytes 0x00–0x08 in the first 64 KB of the file: TXT; otherwise the refusal "This format is not supported".

The FB2 encoding is taken from the XML declaration; TXT is UTF-8 with BOM or valid UTF-8, otherwise windows-1251. An
EPUB is rejected as protected only if `encryption.xml` encrypts at least one document from `spine`; font obfuscation
and encryption of unused resources are ignored, an encrypted picture is not shown.

**Parsing tolerance is exactly three kinds of damage**, each with a small sample and the exact expected text of blocks
(section 9):

- an unclosed tag: a closing tag closes all the tags opened after its pair; those unclosed by the end of the file are
  closed at the end;
- an unknown entity stays in the text as written (`&name;`); named XHTML entities (`&nbsp;`, `&mdash;`…) are not
  considered unknown: they are part of the format and are expanded into characters;
- an XML file is declared UTF-8 but contains invalid sequences: the whole file is read as windows-1251.

Any other XML error is a refusal "Couldn’t read the book" with the technical reason. A new kind of damage found on the
owner's book (section 9) is added the same way: by a general rule and a sample.

## 4. Storage

An app folder inaccessible to other apps:

```
books/<bookId>/
  original.<ext>     the source file as added
  book.json          the book model (section 3)
  meta.json          title, author, character count, whether there is a cover: everything the shelf needs
  state.json         reading position, listening place (5), the "finished" flag, the book's own voice, the time of
                     adding and of last opening (absent: the book has not been opened)
  cover.jpg
  images/<imageId>
  audio/<fingerprint>.<extension>
samples/<fingerprint>.<extension>   the audio of voice probes (6.8), shared by all books
usage.json           paid tokens by month and model
tmp/                 unfinished things; cleaned at startup
```

- `bookId` is the first 12 characters of the sha256 of the source file. The same file is not added a second time but
  opened.
- **Corrupted data does not crash startup.** A book folder whose files cannot be read does not reach the shelf and does
  not hinder the others; an unreadable `settings.json` or a key missing from it means defaults. Deleting a book is
  symmetric to adding: the folder is renamed into `tmp/` and deleted from there.
- **Adding a book ends with a single rename.** The file is copied and parsed in `tmp/<random name>/`; the finished
  folder is renamed to `books/<bookId>/`. The shelf and the duplicate check see only the folders in `books/`. A
  process killed in the middle of adding leaves garbage in `tmp/`, not half a book on the shelf.
- **Re-parsing** prepares a new `book.json` alongside and replaces the old one by renaming; until then the old one
  applies.
- **One writer.** `state.json` and `usage.json` are changed only by `Library`, one operation at a time: a change is
  applied to the current content, the file is written to a temporary one and renamed. Two Gemini responses that arrive
  simultaneously do not lose each other's spending; writing the position does not overwrite a voice change, and
  writing the reading position does not overwrite the listening place, and vice versa.
- The position is written no more than once a second, but the last change is always written; a pause and the app going
  to the background write at once.
- **Deleting a book and "Clear narration" do not wait for network requests.** They are carried out by
  `NarrationController`: if the affected book is being listened to, it changes the session number (state `idle`); it
  forbids new work for the affected books, including "Download chapter"; it waits only for the disk writes in flight
  and deletes at once. A Gemini response that arrives later for a deleted book or cleared narration: the spending is
  recorded, the audio is discarded. "Clear narration" deletes `audio/` of all books and `samples/`.
- App settings (voice, model, theme, font size, speed) are in the ordinary settings storage; the Gemini key is in the
  protected one (`flutter_secure_storage`).
- **Android backup is turned off for the whole app**: `allowBackup="false"` and data extraction rules
  (`dataExtractionRules`) that exclude everything, both cloud backup and transfer to another device. Books, positions,
  spending and the key do not go to the Google cloud.

`book.json` is read and decoded outside the main isolate. The opening time of a large book and the memory are checked
on a synthetic book (section 9); if a single file turns out to be heavy, the model is split by chapter: a replacement
inside `library`.

**The source is kept so that the book can be re-parsed after a parser fix**: a `parserVersion` in `book.json` older
than the current one → re-parsing on opening. The position therefore stores, besides the block number, the first 64
characters of its text and `charsBefore`. After re-parsing, the block with the same text start closest to the old
`charsBefore` is looked for; if none is found, the block at `charsBefore` is taken, and this is knowingly approximate.
Narration survives re-parsing by itself: it is tied to the text.

## 5. Reading

- **Pages are computed in portions from the current position**, by measuring the text with Flutter's tools, yielding
  control between portions. The first page is shown at once; the other pages of the chapter are completed in the
  background of the main isolate. A change of font or screen size cancels the computation in progress and starts a new
  one from the saved position. A change of theme colors does not require recomputation.
- A page is a pair: a "start: block and offset" and an "end". A paragraph is carried across pages by line.
- **There are no page numbers.** Only the fraction of the book by characters is shown.
- There is no syllable hyphenation in the first version; left alignment.
- **A position** is `{block, offset, charsBefore, anchorText}`. A book has two of them, both in `state.json`
  (section 4): the **reading position**, what is on the screen, and the **listening place**, the start of the segment
  that was sounding (6.1).
- **The reading position has one owner.** While listening is not active (`idle`), the reading position is written by
  the screen: the start of the first line on the screen. While it is active (any state except `idle` and `stopped`),
  only by `NarrationController`: the estimate of the sounding place inside a segment (a refinement of 2026-11-15: this
  is how the prototype and the real controller behave; it is written on a block change, on pause, stop and "Close",
  not on every player event). A page that the user turns to themselves meanwhile is a temporary state of the screen and
  does not go to the file.
- **The listening place is written only by `NarrationController`**, at the start of each segment. Pause, stop, "Close"
  and an app restart do not erase it; deleting a book deletes it together with the book. The screen never writes it.
- **The fraction of the book and the chapter title for the shelf are derived from the position by `Library` itself**:
  whoever recorded the position, the shelf shows the chapter and the fraction of that place.
- **"Finished" (FR-L4) is a separate fact in `state.json`, not derived from the recorded position.** It is set by
  showing the last page (including the first layout of a one-page book) and by the end of listening; it is cleared only
  by showing a page earlier than the last one, by turning, the slider, the table of contents or following the voice. A
  re-layout (font, panel) and re-listening on the last page do not clear it. While it is set, the fraction on the shelf
  is 100 %.
- **Handing the position to the screen.** "Close" (the cross on the player panel) ends listening: the state is `idle`,
  the reading position is the place on the screen: the sounding place (the estimate from following) if the screen
  followed the voice; the start of the page if the user turned pages themselves. The panel goes away, the page becomes
  longer and is recomputed so that this place stays on the screen, not from the start of the previous page: otherwise
  the recomputation takes the screen back to where the sounding place is no longer (the owner's remark of 2026-11-14).
  After that the reading position is written by the screen; the listening place remains. On the transition to `stopped`
  the screen first shows the page with the saved position (turns following on) and gets the right to write the
  position only at the user's next explicit move: turning, going through the table of contents, or the slider. Such a
  move with the `stopped` panel open turns following off, as during sound: a re-layout and "Close" after it keep the
  place chosen by the reader, not the stop place.
- **"Listen" from `idle`** (FR-P3; the owner's remark of 2026-11-14). The screen only reports the visible page to the
  controller, its start and end; the place is chosen by `NarrationController`:
  1. the listening place is on this page: continue from it;
  2. otherwise from the first sentence that begins on the page; the tail of a sentence from the previous page is not
     read;
  3. if no sentence begins on the page (the page is inside one long sentence), from the beginning of that sentence;
     only in this case does the page move there.

  Sentence boundaries are rule 2 of 6.1 with clarifications (i) and (ii), over the speech text (section 3) with the
  offsets translated back into the block; there are no word lists. Non-narrated blocks and pictures are skipped. A
  begun sentence is a start segment (6.1). The page is not turned back (except in case 3), following is on from the
  first frame: there is no "To current spot" button right after the start. While the player panel appears and the
  layout is being recomputed, the page is set at once at the sounding place; page-change messages from the replaced
  layout do not turn following off.
- **Following the voice is approximate.** The screen shows the page with the place that is sounding now and highlights
  the sounding paragraph (`narration.block`) and the paragraph selected by the reader. The place inside a segment is
  estimated proportionally: the fraction of the file's time played, applied to the length of the segment's text.
  Numbers, abbreviations and pauses sound out of proportion to their length, so on a segment of several pages the page
  may turn earlier or later than the voice. There is no word-by-word highlighting and no exact place.
- **What turns following on and what turns it off** (rule a of the user-journey audit, accepted by the owner
  2026-11-14). It is turned on by any action with which the user themselves starts or changes the sound's place:
  "Listen" (including after a pause and from the error panel), "Read from here", the player's "previous" and "next",
  choosing a chapter in the table of contents, "To current spot". **It is turned on by a controller event, not by a
  wrapper screen:** `NarrationController` keeps a counter of the user's explicit commands that start or move the sound,
  wherever they come from: the screen, the notification, the headset; the screen turns following on when the counter
  has changed. Automatic transitions (the next segment, the end of a chapter, a change of voice or model) do not touch
  the counter. "To current spot" is the screen's own action. Following is turned off only by manual turning and the
  slider, with any open player panel of this book, including in `stopped`; the voice is not interrupted. A finger
  gesture turns it off only when it really changed the page: the start of a drag by itself changes nothing, a small
  drag with a return to the same page and a cancelled gesture do not either; while the gesture is going on and the
  page has not settled after it, the voice does not turn the page. An exception (decision C of the gesture audit): a
  finger that landed on the page during an automatic turn after the voice has grabbed it: following is turned off even
  if the page returned to the previous one: otherwise the page being finished cannot be held. The slider turns following
  off only if it is released on another page; touching the thumb without moving changes nothing. Choosing in the table
  of contents during listening (and on pause) always moves the voice to the start of the chosen chapter, including the
  current one; the voice then drives the page on: the transition does not count as manual turning.
- **While a paragraph is selected** for "Read from here", the page does not move away after the voice: the button waits
  for a press. Once the selection is cleared, the screen catches up with the voice. The selection is cleared on any page
  change: by a gesture, a tap, the slider, the table of contents, the voice; there is no invisible selection (decision
  B of the gesture audit).
- **What turns pages.** Only a gesture whose horizontal shift exceeds the vertical one at the moment of recognition
  (the angle to the horizontal is less than 45°). A predominantly vertical gesture does nothing: the vertical
  recognizer sits deeper than the turning recognizer, sees every movement first and takes the gesture when the finger
  has gone up or down farther than the touch threshold and farther than sideways (decision D). A tap on a third or a
  swipe during the animation of the previous transition is not lost.
- **Re-layout** (font, screen size, a change of the player panel's height, including from the download row; a theme
  change does not cause it): the anchor is the held paragraph selection, if there is one; otherwise, if the screen
  follows the voice, the voice's place (sounding, pause place, stop place); otherwise the start of the visible page.
  While the layout is being recomputed, the screen does not turn pages: the page does not jerk back and forth. A
  gesture over the previous layout is lost together with it. The anchor answers the question "what must stay on the
  screen", not "what does the page start with" (a refinement of 2026-11-15): if the held place lies on the shown page,
  the new layout is computed from the start of that same page: the text above the sounding paragraph stays; if the
  place has left the first page, the next one, on which it lies, is shown. The layout is computed from the place itself
  only when it was not on the shown page (opening a book, the table of contents, the slider, "To current spot",
  catching up with the voice).
- **The layout is computed from a place, not from the start of the book** (2026-11-15): opening at a saved position and
  any transition show the page at once, however much text lies before it; forward, pages are completed in portions,
  backward, as needed, gathering pages from the start place toward the start of the chapter (below). This is exactly
  why there are no page numbers. The layout's start place is always the start of a line that the reader has already
  seen (the saved reading position, the start of the shown page), or the start of a block: for any other target (the
  slider, the end of the book, a voice place off the shown page, "To current spot") the layout is computed from the
  start of the block with the target, and the page of it on which the target lies is shown. A page that begins in the
  middle of a word or consists of a single character does not occur.
- **A return to an already seen place shows the same page** (the owner's remark of 2026-11-15: pause → turning →
  "resume" returned to a page where the sounding fragment stood at the top although it had been in the middle; this is
  disorienting). If the target of a transition (the voice's place, "To current spot", a return after turning) lies on
  any already computed page of the current layout, exactly that page is shown, with the same text position; the layout
  is computed from the place or from the start of the block only when the target is on no computed page and is not
  near.
- **A near target continues the previous layout** (the owner's question of 2026-11-15: "why can't we keep that view with
  the text that was before turning back?"). A programmatic target (the voice's place, the player's "previous/next",
  "resume", "To current spot") in the same chapter and no farther than 30 000 characters from the edge of the computed
  pages (`_nearbyLayoutChars`) does not start a new layout: the previous one is completed up to the target, and the page
  of it on which the target lies is shown. The sounding paragraph therefore need not stand at the first line of a page,
  and the pages behind stay those that the reader saw. A far target, another chapter, the table of contents and the
  slider: a layout from the place.
- **The pages before the layout's start place are gathered backward from it** (the owner's remark of 2026-11-15: after
  "next", turning back showed a page of a few lines). Each such page is full and ends where the next one begins; a
  shortened page before the start place no longer exists. At the start of a chapter the remaining lines may not suffice
  for a page; then the chapter's first page is laid out forward from the start of the chapter, full, and its last few
  lines are repeated on the second; an overlap is possible only at this boundary. A place in the overlap is looked for
  on the second page, except when the reader stands on the first.
- **The player panel's height is constant** (2026-11-15, from two independent reviews of the reading screen). While the
  panel is open in the states with control buttons (`preparing`, `playing`, `waiting`, `paused`), its height depends
  neither on following, nor on audio preparation, nor on the system bars: "To current spot" is an icon in the top row
  (the owner's decision), the state caption ("Preparing the voice…", "Waiting for connection…") is in the same row, on
  one line with an ellipsis, the bottom inset is a stable maximum. The reason: any change of height changed the page
  size and re-laid the text: at every "next", at the first turning, on a return to the voice; hence four remarks of
  the owner in one day. Only the error panel, "End of the book" and the chapter download row may change the height; for
  them the usual "a re-layout keeps the start of the current page" applies.
- **Following is turned off only when the page has really changed**, not at the moment a not-yet-computed page is
  requested. The reader's taps and swipes are not lost: neither because of waiting for the computation nor because of an
  audio event.
- **The voice itself reached the shown page: following turns on** (added 2026-11-15 when fixing the page return;
  approved by the owner the same day): the reader has paged ahead, the sound goes on, and the sounding place has
  entered the page on the screen: from then on the screen again turns pages after the voice, and the "To current spot"
  button disappears.
- A tap on a third of the page during the animation of the previous transition is not lost: the previous transition is
  completed instantly, the new one goes from it.
- "Listen" after a pause continues from the pause place. Starting from another place is only by an explicit "Read from
  here" (from the beginning of a paragraph), by changing the chapter in the table of contents, the player's "previous"
  and "next" (6.4), "Listen" from `idle` by the rule above, or "Listen" from `stopped` (from the saved reading position
  or from a new one if the user turned pages after the stop). From `stopped` a new session is started only by "Listen"
  and "Read from here"; "previous" and "next" do nothing there. The slider during listening is available (8.1) and only
  turns the screen, like turning by hand: following is turned off.

## 6. Narration

### 6.1 Segment

A segment is what goes out in one request and lands in one file. The segments of a chapter are a pure function of its
blocks and two numbers, always computed from the start of the chapter and independent of where listening began. First
the speech text is computed for each block (section 3), then the rules are applied to these texts:

1. A heading is always a separate segment.
2. A block longer than `L` is split into parts no longer than `L`: at a sentence boundary; if a sentence is longer than
   `L`, at the last space; if there is no space, at `L` characters, without breaking a surrogate pair. The split keeps
   all the text and always makes progress.

   **A sentence boundary** is an end mark (`.` `!` `?` `…`), possibly closing quotes and brackets, then a whitespace
   character, and two general rules by form, without word lists:
   - (i) a period after a one-letter word is not a sentence end: "г. Москве" ("in the city of Moscow"), "А. С. Пушкин"
     (a name with initials), "т. е." ("i.e.");
   - (ii) the next word (after the space, and if there is a dash with a space, after the dash) must begin with a capital
     letter, a digit, or an opening quote or bracket; a lowercase letter means the sentence continues: "…потом
     заговорил" ("…then he started talking"), "— Стой! — крикнул он" ("'Stop!' he shouted"). For scripts without case,
     rule (ii) does not apply.

   Boundaries are looked for in the speech text (section 3): a footnote mark after the period that begins the next
   sentence does not hide it; the offsets found are translated back into `Block.text`. There is one rule for splitting
   into segments and for choosing the start place (section 5). **Accepted limitation:** an abbreviation longer than one
   letter ("см. рис.", "see fig.") counts as an end, and a real end after a one-letter word ("…сказал я. Потом",
   "…I said. Then") does not; the start comes slightly earlier or later, no text is lost.
3. Consecutive blocks, each shorter than `Lmin`, are merged into one segment until the sum exceeds `L`; the texts are
   joined with a newline.
4. The other blocks go one per segment.

Blocks that are not read aloud (section 3) and blocks with empty speech text are skipped: they create no segments, do
not enter groups and do not interrupt a group. All lengths in the rules are by the speech text; the newlines between a
group's blocks count toward the length.

**A segment carries a correspondence list**: a range of the request text → (block, range in `Block.text`). With it,
highlighting, following and the position translate a place in a segment into a place on the screen.

`L` = 600 and `Lmin` = 200 are starting values. They are derived from a measurement: a request to Flash takes
≈ 3.3 s + 0.016 s per character, the audio yields 0.066 s per character, that is, at 200 characters synthesis is twice
as fast as the audio, and at 600 a request takes ≈ 13 s. They will be refined by a measurement on a mobile network
(section 11). The numbers enter the result of the split, not the fingerprint: when they change, part of the old audio
simply stops being found.

**Whether a segment is ready** is one rule for all consumers (start, continuous reading, "Download chapter"): a
segment is ready if the storage has its whole file or all of its parts. If it is not ready, only the missing parts are
requested; if there are no parts, the whole segment, and if it is a start segment, in two parts.

**Segment parts.** The first is the smallest number of whole sentences from the start of the segment that gives at
least `firstPartMin` = 80 characters (a refinement from the 2026-11-15 review: a first sentence like "— Да." ("'Yes.'")
gave a second of audio and eight seconds of silence; a request is never shorter than ≈ 3.5 s). If the first sentence is
longer than 200 characters, it is split by rule 2 with a limit of 200, and the first chunk becomes the first part. The
second is the remainder. An empty remainder, or a segment shorter than `firstPartMin`: one request. Each part is stored
under its own fingerprint.

**A start segment** is the one from which the user expects sound: pressed "Listen" or "Read from here", moved to
another place. The first part of about 100 characters arrives in ≈ 5 s (a forecast from one measurement at 99
characters), instead of ≈ 13 s for a whole 600-character segment. If the remainder is not ready by the end of the first
part (especially at 2×), a pause occurs; it is acceptable, it is the `waiting` state.

**A start from a block in the middle of a group**: the start segment is the group tail from this block. It is a
separate segment with its own fingerprint, even if the whole group is already narrated: reading begins exactly at the
chosen place. Ordinary segments of the chapter follow it.

**A start from a sentence inside a block** ("Listen" from `idle`, section 5): the start segment begins with this
sentence (the boundary by rule 2) and runs to the end of the segment that the block belongs to (the block tail and, if
the block is in a group, the group's other blocks). It is also a separate segment with its own fingerprint; the split
into parts applies to it (the first sentence is the first part). The listening place is its start. Ordinary segments
of the chapter follow it.

### 6.2 Client and fingerprint

The request shape, the voices, the limits, the error classes and the tariffs are in [GEMINI_TTS.md](GEMINI_TTS.md). The
client repeats in full what was proven in the studio: handling of 404 on the model, checking the response `status`, the
sample rate from the response, scrubbing the key from error texts.

```
TtsEngine.synthesize(text, profile) → { pcm, sampleRate, usage }
  usage: { audioTokens, inputTokens? }
  errors: TemporaryTtsError (408, 429, 5xx, timeout, network) | TtsError (everything else; for 402, a top-up link)
          an error carries usage if it was in the response
VoiceProfile { model, voiceId, style }
fingerprint(text, profile, audioFormat) → sha256
```

- The client does not retry requests itself: it only marks a temporary error, the queue retries.
- Spending is accounted once: from the result or from the error.
- `FakeTtsEngine` returns a tone of a length proportional to the text, with controllable delay and errors. All the
  tests and screen development use it.
- **A build with fake synthesis** has a separate `applicationId` (the suffix `.fake`) and therefore a separate storage:
  its tone never gets into the real build's cache.
- The model identifiers, the voice list and the prices with the check date are in `lib/tts/voices.dart`. Today's tariff
  (`Tariffs`) and spending by month (`spentByMonth`) are in `lib/playback/tariffs.dart`.

### 6.3 Synthesis queue

The queue knows the current segment and the end boundary of listening and keeps ready audio ahead.

- **The reserve is continuous ready audio from the current place.** Segments beyond the first unready one do not count
  toward the reserve. The reserve is measured in listening time: seconds of audio divided by the player's speed.
  Synthesis goes on while the reserve is below the target. The target is 120 s **[measurement]**.
- **The purchase limit is all the audio ahead, not only the continuous one** (review of 2026-11-15). A new listening
  request does not begin if the audio ahead of the current place, ready and already requested, including audio beyond
  an unready segment, has reached the reserve target. Otherwise, with a segment that fails again and again, the queue
  would buy the book to the end without playing a second. The player's list is also appended with audio only up to the
  reserve target.
- **The nearest unready segment is requested first**, including its retry after an error. While it waits for a retry,
  new requests for far segments do not begin; those already begun are completed.
- **The end boundary**: the end of the book, and with the "until the end of the chapter" sleep timer, the end of the
  chapter. The queue does not request beyond the boundary. A time-based timer limits the reserve target to the
  remaining time.
- Up to two requests at a time **[measurement: rate limits]**. The count is common: a place is taken by a request of a
  previous session that is still finishing, by "Download chapter", and by a voice probe.
- **The registry of in-flight requests belongs to the queue, not to the session.** One request per fingerprint: before
  a request the queue checks the storage and the registry; a second consumer of the same fingerprint waits for the
  in-flight request rather than paying again. A request only publishes the file and records the spending; it never
  controls the player. A consumer of the current session that was waiting for this fingerprint, after the file appears,
  itself checks whether its session is still current and continues.
- **Pause**: in-flight requests are completed and saved, new listening requests do not begin, scheduled listening
  retries are cancelled. A listening pause does not stop "Download chapter" (6.7).
- **A temporary error** is retried with a growing delay up to 30 s while a task that needs the segment is active:
  listening not on pause, "Download chapter", or a voice probe (6.8). While there is reserve, it is not visible. In
  `preparing` the state does not change; if the reserve ran out during `playing`, the state is `waiting`, which gives
  way to playback by itself.
- **A permanent error**: new requests stop at once, the ready continuous audio is played out, then the state is
  `stopped` with the reason "error" and Google's text; for 402, a "Top up" button. If it arrived during a pause, then
  `stopped` at once. The position is the first unnarrated segment.
- **Spending** is recorded on receiving a response or an error with `usage`, regardless of whether the audio could then
  be saved and played. The monthly sum in dollars is computed at the tariff that was in force in that month.

### 6.4 Session

A listening session is a book, a voice profile, a start point and a number that grows with each action that changes what
should sound: start, "Read from here", a move back or forward, a chapter change, a voice or model change, "Close",
deleting a book, "Clear narration".

- The session number is checked by the listening and voice-probe controllers; the previous queue task is cancelled. The
  queue does not store session numbers: publishing after a deletion or clearing is forbidden by the generations
  `generation` and `bookGeneration` and by the book-deletion mark.
- The result of a previous session: the audio is saved in the storage under its fingerprint, the spending is recorded,
  and that is all. It does not enter the player's list, and does not change the position or the state. The exception is
  a deleted book and cleared narration (section 4): the audio is discarded.
- A pause does not change the session: "Listen" continues from the same place with the same list.
- A change of chapter, voice or model, "Read from here", "previous" and "next" start a new session and keep the intent:
  if it was on pause, it stays on pause at the new place; if it was playing, it plays. A change of voice or model starts
  from the current segment.
- The sleep timer belongs to the controller, not to the session (6.6).

### 6.5 Audio storage

```
AudioStore.formatId
AudioStore.has(fingerprint, bookId: …) / file(fingerprint, bookId: …) / put(fingerprint, pcm, sampleRate, bookId: …)
AudioStore.bytesForBook(bookId) / totalBytes / removeBook(bookId) / clearAll()
```

- Gemini returns 24 kHz mono PCM: about 170 MB per hour. On the phone the audio is compressed by the Android system
  codec through the `platform` module. The codec **[measurement]**: AAC in an M4A container, unless a check by ear and
  at file joins shows otherwise. The format is part of the fingerprint.
- **A file appears under its own name only when ready**: writing goes to a temporary file, and after the codec
  finishes, a rename. `has` sees only ready files.
- A ready file that cannot be read (the duration cannot be determined, the player does not play it) is deleted and
  counts as unready: the segment is requested again once; a second failure is a stop with a technical error at this
  segment, without skipping over the text (review of 2026-11-15).
- If a write fails, it is retried with the same PCM while it is in memory, with no new request to Gemini. If the
  process is killed between the response and the write, the paid response is lost; this is an accepted limitation, as in
  the studio.
- Voice probes are stored in the same way in `samples/` (section 4), outside the book folders.
- Only for the tests there is an encoder without compression (`WavAudioEncoder`), with the same interface.

### 6.6 Playback

- The player (`just_audio`) plays a list of files; the queue appends to it the ready segments of the current session in
  order. Each item carries a segment number.
- The media session (`audio_service`): a foreground service with a media notification, the lock screen, the headset
  buttons.
- A call, foreign audio and unplugged headphones pause (`audio_session`). The user resumes by themselves; there is no
  automatic resumption.
- Speed is changed by the player; a speed change makes no requests. "Previous" and "next" move by paragraphs (the
  owner's decision of 2026-11-15, after the first listening: moving by segments is confusing, sometimes several
  sentences within a paragraph, sometimes several lines at once): "next" goes to the start of the next readable block,
  "previous" to the start of the current block, and if the sound is already at its start, to the start of the previous
  one. "At the start" means: by the place estimate, less than 3 seconds have sounded from the start of the block
  (`blockStartWindow`), or the sound after the previous command has not yet begun; a pause in the middle of a paragraph
  does not count as the start. Ready audio is used where the start of the block coincides with the start of a segment or
  of its part; a paid request arises only on a move into the middle of a group of short blocks (the group tail, 6.1).
- The player adds no pauses between segments. If a check of the joins by ear shows a need **[measurement]**, a pause is
  added between segments of different blocks, and never between parts of one block.
- The sleep timer is a pause by time or at the end of the chapter that is sounding at the moment of firing. The timer
  belongs to the controller, not to the session: a change of place, chapter and voice in the same book does not reset
  it. Minutes are counted by wall clock from the moment it was set. The timer is cleared when it fires, on "Close", on
  closing the book and on changing the book. A deadline that expired when no sound was playing: on pause the timer is
  simply cleared, it has nothing to stop, and the next "Listen" sounds; in `preparing` and `waiting`, a pause, and the
  timer is cleared. Before every explicit start ("Listen", "Read from here", "previous", "next", choosing a chapter) an
  expired deadline is cleared by one and the same handling, including after a stop by error. The end of the last
  chapter (the end of the book) is also a firing of "until the end of the chapter".
- Speed is a setting: each session sounds at the saved speed from the first sound; there is one source of speed, for
  the caption and for the player.
- **The explicit-command counter.** The controller increments it on every explicit user command that starts or moves
  the sound: "Listen" (from `idle`, `paused`, `stopped`), "Read from here", "previous", "next", choosing a chapter,
  wherever it comes from: the screen, the media session (notification, lock screen), the headset. By a change of the
  counter the screen turns following on (section 5). Automatic transitions (the next segment, the end of a chapter, a
  profile change) do not change it. The real controller publishes the new place synchronously together with the
  counter, so that the screen does not go to the old place.
- A change of voice or model is a new session from the start of the current unit, including a start segment begun from
  a sentence inside a block (6.1): the start of the block is not read again, the listening place does not shift.

`NarrationController` is the only place where the queue, the player, the session and the position come together. The
screen subscribes to its state and decides nothing itself.

| State | What is happening | Media session | Foreground service |
|---|---|---|---|
| `idle` | there is no listening | no | no |
| `preparing` | waiting for the first segment; temporary errors are retried | "playing", loading | yes |
| `playing` | sound is going | "playing" | yes |
| `waiting` | the reserve ran out, retries are in progress | "playing", loading | yes |
| `paused` | a pause by the user, by an interruption or by the timer | "paused" | yes, the notification is not removed (`androidStopForegroundOnPause: false`) |
| `stopped` | the reason is "error" or "end of the book" | no session: the notification disappears, the reason is on the reading screen (2026-11-15: the `audio_service` package cannot keep a card with text without a foreground service; we did not replace its code) | no |

Transitions:

```
idle ──start──► preparing ──first sound──► playing ◄──────────► paused
                    │                        │  ▲                  ▲
                    │                        ▼  │ sound ready      │ pause
                    │                      waiting ────────────────┘
                    ├──pause──► paused
                    └──permanent error──► stopped ◄── permanent error or end of book ── playing, waiting
paused ──permanent error──► stopped
paused ──"Listen"──► playing, or preparing if there is no reserve
stopped ──"Listen"──► preparing (a new session from the saved position)
stopped ──"Read from here"──► preparing (a new session from the start of the paragraph)
any ──"Close", closing the book──► idle
```

- A temporary error in `preparing` leaves `preparing`: retries go on.
- A change of chapter, voice or model, "Read from here", "previous" and "next" from `paused` is a new session, state
  `paused` at the new place; from `preparing`, `playing`, `waiting` a new session, `preparing` (or `playing` at once if
  the audio is ready). Touching the already chosen voice or model (and another row with the same effective voice) is not
  a change: the session is not restarted, the pause place is not reset.
- A permanent error carries its class and what it relates to: 404, the model on which it happened (the panel names it,
  not the one chosen afterwards); an invalid key (400/403 with a key refusal), a recognized cause with a "Change key"
  button. The "End of the book" panel has only "Close". "To current spot" is in the control panel (`preparing`,
  `playing`, `waiting`, `paused`), including in `preparing` and `waiting`, where the state caption stands in the same top
  row (section 5) and the voice chip stays; in `stopped` it is absent: in the error panel, "Listen" returns to the
  voice's place. From `stopped` a new session is started only by "Listen" and "Read from here"; "previous" and "next"
  (including from the notification) do nothing there.
- The end of the book reached by listening makes the book finished (FR-L4): the controller sets the separate "finished"
  fact (section 5), and neither "Close" nor re-listening on the last page clears it.
- **The service becomes active at the moment "Listen" is pressed**, while the app is on the screen, and audio focus is
  requested after it starts. `preparing` and `waiting` are published as "playing, loading", not as a pause: otherwise
  Android may stop the app while it waits for Gemini's response with the screen off. In `paused` the service remains a
  foreground service so that "Listen" from the lock screen works with the screen off.
- **The player list is played out and the end boundary has not been reached**: this is `waiting`, not the end of the
  book. The end of the book is declared only by the controller.
- A pause remembers the place inside the file; "Listen" in the running app continues from it. After an app restart,
  listening begins from the start of the segment where it stopped: this is the listening place from `state.json`, and
  "Listen" from `idle` takes it if it is on the open page (section 5).
- A pause in `preparing` and `waiting` removes the intent to play: audio that arrives later goes into the list but does
  not sound.

### 6.7 "Download chapter"

A queue task: the far boundary is the end of the current chapter, the goal is all its segments ready (the readiness rule,
6.1) in place of the reserve. It is available both during listening and without it; it does not depend on the session
and ends when the chapter is ready, on "Stop", on deleting the book, on "Clear narration" or on a permanent error (with
Google's text). Retries of temporary errors go on while the task is active.

In the first version it works while the app is on the screen; the screen does not go dark during that time. If the user
leaves the app, it stops; on return, it continues from the first unready segment. A manual "Stop" cancels this
continuation too.

The price estimate before the start is computed over the chapter's unique missing fingerprints: after "Stop" and after
an error it is the unready remainder, not the price of the whole chapter.

**Profile.** The task belongs to a chapter and to the voice profile (6.2) with which it was begun. A chapter's readiness
("narrated") and the estimate are computed for the book's current profile: the `isVoiced`/`estimate`/`start` contract
takes a profile: audio in another voice or model does not suit the new profile. A change of the book's voice, of the
app's voice or of the model stops the task (what is ready is kept), and the current chapter gets an offer with an
estimate for the new profile.

**One task.** The offer to download is in the current chapter's block and only when no task is running. The block with
progress (the fraction ready and "Stop") or an error is at the chapter the task belongs to, even if the reader is
already in another. The estimate is on a separate line before the button. A permanent error is shown in the same block:
the cause, Google's response, "Download again" with an estimate of the remainder; the player panel does not open; a new
start replaces the failed task. After completion the block shows "narrated"; after a manual stop, an offer to download
again with an estimate of the remainder. The recorded audio takes space in the storage (6.5): after "Clear narration" a
new download and new probes are again visible in the volume of the book and of all narration, and "Delete narration" and
"Clear" are available again.

### 6.8 Voice probe

- Opening the voice selection screen pauses listening.
- The probe's phrase and style follow the book's language, from the table in the `tts` module (FR-T7); for the app's
  voice, the interface language. The probe is narrated with the **full current profile** (6.2): voice, model, style.
- The probe plays through a separate short player, not through the listening list.
- The audio is in `samples/<fingerprint>` (section 4); the fingerprint is computed from the phrase and the full
  profile, so a probe of the same profile is free the second time, and after a change of model (or language) the same
  voice is narrated again.
- The request goes through the queue: one request per fingerprint, a place in the common limit, spending accounted as
  usual. A temporary error is retried while the voice selection screen is open.
- A voice row has three visible probe states: waiting (including retries), sounding, an error with Google's text.

## 7. Platform

The `platform` module is the only place with Kotlin code and the channels to it:

- the encoder PCM → compressed file (`MediaCodec` + `MediaMuxer`);
- receiving a file from another app ("Open with") and from the system file picker; the file is copied at once into the
  temporary adding folder, permanent rights to the source are not requested.

Permissions: internet; the foreground service and its "media playback" type (`FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_MEDIA_PLAYBACK`). The notification permission is not requested: the app's only notification is the
media session, for which Android makes an exception. There is no access to shared storage, contacts or location.
Unencrypted HTTP is forbidden; the app contacts only `generativelanguage.googleapis.com`.

The statements of this section about Android's behavior and of section 6.6 about the service are from the
documentation; on the owner's phone they are checked by the manual checklist (section 9).

The minimum Android version is 12 (`minSdk 31`); the owner's phone is a Samsung Galaxy S26 Ultra (spec 001, section 1).

**Orientation is portrait only** (spec 001, D10; decision F of the gesture audit). It is fixed in the manifest
(`android:screenOrientation="portrait"`) and in code (`SystemChrome.setPreferredOrientations` at startup). There is no
landscape in the first version: the camera cutout at the side and the "home" gesture zone are unresolved in landscape.
A window-size change (split screen) recomputes the layout, the reading place is kept (section 5).

## 8. Screens and state

- Routes: shelf → reading; over reading: the table of contents, text appearance, voice, speed, timer, footnote;
  settings from the shelf. Transitions are 8.1.
- The screens' state is held by `_ShelfScreenState` and `ReaderScreenState`. `NarrationController` and `Library` live
  for the whole run of the app and are created in `app`.
- Dependencies are passed into constructors. There is no code generation: reading and writing JSON for a few classes is
  written by hand. The only exception is the interface-string classes generated by `flutter gen-l10n` from ARB (part of
  the Flutter tool, it runs by itself on `pub get`, tests and build; the owner's decision of 2026-11-14).
- The interface strings are in the ARB files `lib/screens/l10n/app_<language>.arb` in five languages (ru, en, pl, de,
  uk; Ukrainian added by the owner's decision of 2026-11-17); the language is the phone's if it is one of the five,
  otherwise English; a choice in the settings takes priority. The system Material labels are the
  `GlobalMaterialLocalizations` delegates from `material_ui`.
- Book parsing at adding runs in a separate isolate: the shelf does not freeze.

### 8.1 Transitions

- The table of contents, text appearance, voice, speed and timer open over reading and do not close the book.
- The table of contents does not stop the sound. The "Voice" screen pauses listening (6.8).
- **The system "Back" on the reading screen** (spec 001, D11; decision J of the gesture audit, replaces rule f of the
  journey audit): 1) clears the paragraph selection; 2) closes a sheet, dialog, footnote; 3) if the reading panels are
  hidden, shows them, and the book is not closed; 4) if the panels are shown, closes the book: listening → `idle`, the
  sleep timer cleared (6.6). During listening it is the same: the first "Back" shows the header and the slider above
  the player panel, the sound goes on. **The reason is the Android edge gesture:** with gesture navigation a swipe from
  the screen edge is "Back"; a reader who turns pages from the edge would otherwise close the book and cut off the
  sound. The "Back" arrow in the reading header closes the book at once. Checked only on the phone (spec 001, FR-P9).
- **Protection against a follow-up tap** (spec 001, D12; decision A of the gesture audit). After the layer under the
  finger has changed (reading bottom panel ↔ player panel, the player panel's view (controls, error, end of the book),
  the download row, a sheet, dialog or screen over reading closed, a sheet opened), the new controls and the page under
  them do not accept taps for `layerSettleTime` = 350 ms. There is one mechanism: the reading screen absorbs taps after
  a layer change, a sheet for the first 350 ms after opening. The second tap of a double press comes after 100–250 ms;
  two deliberate presses more than 350 ms apart work as usual. Showing and hiding the reading panels by a tap on the
  center is not counted as a layer change under the finger: the panels appear at the edges.
- The settings open from the shelf. From the reading screen only from "Listen" without a key, from "Choose model" on a
  404 error and from "Change key" on a key refusal (straight to the open key field); "Back" from them returns to the
  same book, narration does not start by itself. A non-empty value in the key field is saved on any departure from the
  field and from the screen ("Done", on-screen and system "Back", loss of focus); an empty field does not touch the key.
- The player panel is visible only on the reading screen; there is no mini-player on the shelf.
- During listening, a tap on the center of the page shows the header and the slider above the player panel; the slider
  turns only the screen (5).

## 9. Verification

| What | By what | Where |
|---|---|---|
| parsers: each rule and each of the three kinds of damage is a sample with the exact expected text of blocks, chapters and footnotes; format detection; the linearity of chapters; speech text; splitting into segments and the correspondence list; the fingerprint | unit tests | WSL, CI |
| the Gemini client: the real class with a dummy key and a fake HTTP on responses recorded in the studio's shape | unit tests | WSL, CI |
| pagination, including a chapter of hundreds of thousands of characters | tests with a bundled font | WSL, CI |
| queue, sessions, states: a late response after a pause and a chapter change, two identical paragraphs, an error of the nearest segment with far ones ready, the end of the player list before the end of the book, the readiness rule and parts, the group tail, a consumer of someone else's request, deletion and clearing during a request, a probe and "Download chapter" in the common limit, the timer on a fake clock; "Listen" from pause and "previous/next" without ready audio go through `preparing`/`waiting`, not straight to `playing`; a late result of a request or of a disk write after "Close", deletion and a session change, by a double to which the response is returned after a new command | tests with `FakeTtsEngine` (controllable delays and errors) and a fake player | WSL, CI |
| storage: a killed adding, an unfinished audio file, simultaneous writes of spending | unit tests | WSL, CI |
| screens | screenshots against a golden: the owner approves the screens on the phone, after which their screenshots are recorded as the golden and from then on protect against regressions; they are not compared with the FigCraft mock-up automatically | WSL, CI |
| background and waiting with the screen off, a pause with the screen off and "Listen" from the lock screen, the headset, a call during waiting and during sound, "Open with", the codec and the file joins, appending to the player list, a second build on top of the first | the manual checklist `docs/DEVICE_CHECKLIST.md`, created at stage 2 of spec 001 before its acceptance SC-2 | the owner's phone |

- The tests contain no real network transport: they do not call Gemini.
- The book samples in `test/fixtures/` are our own small files, one per parsing rule, with a "fires / must stay silent"
  pair. Other people's books are not put into the repository.
- The owner's real books are in `test/local_books/` (outside git). A smoke test parses each of them, checks the
  linearity of chapters and is skipped if the folder is absent.
- CI: the analyzer, the tests, an APK build as a check that the project builds.
- **The APK for the phone is built locally with one permanent signing key**, which is kept outside the repository. CI
  builds are signed with another key and cannot be installed over an installed app.

## 10. What the architecture deliberately lacks

- A database, a repository layer on top of files, migrations.
- A state framework, a dependency container, code generation (except gen-l10n for the interface strings, section 8).
- An embedded browser for showing the book.
- A second narration engine. `TtsEngine` is an interface for the sake of fake synthesis in the tests; the Android
  system voice was rejected by the owner for the first version.
- **Playing Gemini's streaming response.** A measurement showed that the stream gives the first sound after 2.1 s
  against ≈ 5 s for a start segment. But to take advantage of this, the audio would have to be played before the file is
  ready: the player's source, the notion of a ready segment, the queue, the reserve accounting and the recovery from a
  break in the middle of a response all change. Three seconds is not worth it until the owner says otherwise after using
  the app.
- Word-by-word highlighting and the exact place inside a segment: Gemini does not return timestamps (5).
- Page numbers: only the fraction of the book is shown (5).
- Automatic resumption after a call and other interruptions (6.6).
- Background chapter download without the app on the screen (6.7).
- Analytics, crash reports, network calls other than to Gemini.

## 11. What still awaits measurement

Paid measurements follow the `AGENTS.md` rule, "Money": a small one (cents) is done without asking the owner, a larger
one with his consent and an estimate named in advance. Latency from the work computer over a wired network was measured
on 2026-11-14 ([GEMINI_TTS.md](GEMINI_TTS.md)); below is the rest.

| What | Where it is checked | Stage of spec 001 | What changes on a bad result |
|---|---|---|---|
| latency and synthesis speed on a mobile network | the work computer connected to the internet through the phone's hotspot; paid | 0 | `L`, `Lmin`, the reserve target |
| two simultaneous requests: rate limits | the working environment; paid | 0 | the number of simultaneous requests |
| a very short text in one request | the working environment; paid | 0 | the lower bound of the first part's length |
| the codec: quality by ear, size, file joins | phone; a few paid paragraphs | 2 | the storage format, a pause between segments |
| the service with the screen off during waiting and pause | phone, fake synthesis | 2 | the correspondence of the media-session states (6.6) |
| appending to the `just_audio` list before and after it has been played out | phone, fake synthesis | 2 | the way the list is replenished |
| opening time and memory on a book of several megabytes of text | phone, a synthetic book | 1 | splitting `book.json` by chapter |
