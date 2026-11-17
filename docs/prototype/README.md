# Clickable interface prototype

Version 2026-11-14, after the Codex review ([CODEX_REVIEW_PROTOTYPE_2026-11-14.md](../reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md),
all 21 findings applied), the owner's start rules and the user-journey audit
([JOURNEY_AUDIT_2026-11-14.md](../reviews/JOURNEY_AUDIT_2026-11-14.md), 16 findings). Real Flutter code (`lib/`) on fake
data: books, narration, download and the voice probe are fake implementations behind the module interfaces of А§2.
There is no network, no Gemini key, nothing is paid for. The prototype screens later become the app's screens; the
fake classes are replaced by real ones with the same contract.

The look is set by this prototype (owner's decision 2026-11-14: the FigCraft mock-up was rejected on its elements, its
palette and fonts were kept). The mock-up in `docs/mockup/` is a reference for the set of screens and their states.

## How to run

From Windows (PowerShell):

```
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/setup-wsl.sh        # once: Flutter 3.50.0 in ~/sdk
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/prototype.sh start   # build + server
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/prototype.sh status
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/prototype.sh stop
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/test.sh              # analyzer + all tests
```

Address: **http://127.0.0.1:8642/** (it opens from the Windows browser too). The server is
`scripts/prototype-server.py`, with no cache: after `start` it is enough to refresh the page.

In the browser the app sits inside a phone frame. Above it are two switchers: size (360 × 800, 393 × 852, 412 × 915
and 320 × 640 with a system font scale of 1.3) and **interface language** (System, RU, EN, PL, DE, UK). The "System
default" theme follows the theme of the browser and Windows; to change it, use "Aa" on the reading screen. The mouse
works like a finger: a click is a tap, holding is a long press, dragging is a swipe.

## "Demo states"

A long press on the **"Books"** title on the shelf or on the **book title** in the reading screen header. From there
you switch on the states that in real life are caused by the network: "Preparing the voice…", "Waiting for
connection…", "Playing", "Pause + sleep timer", errors 402, 404, invalid key and the other one, "End of the book", the
progress and the error of "Download chapter", the adding rows ("Adding…", three refusals), the error of the next
Aoede voice probe, an empty shelf, no key, and the **interface language**. The player and download states are switched
on for the open book (from the shelf, for the top one, and the reading screen opens by itself). The panel and its
labels are prototype-only (`lib/app/prototype/`, in Russian); the real app does not have it: the screens are passed
`openDemoStates: null`.

"+" on the shelf opens an imitation of the system file picker: five "files", each with its own outcome: a book that is
already on the shelf (it is opened, FR-L3; if it was deleted, it is added again), a new book (after 2 s it appears on
the shelf below the card, marked "new"; the same file a second time opens it instead of adding a copy), a PDF, a
corrupted FB2, a copy-protected EPUB.

## Gestures that work

| Gesture | Where | What it does |
|---|---|---|
| tap on the right third / swipe left | page | next page, with a slide animation; across a chapter boundary the same; a second tap or swipe during the animation is not lost |
| tap on the left third / swipe right | page | previous page |
| swipe at more than 45° to the horizontal (predominantly vertical) | page | nothing: the page does not turn, the panels do not appear |
| tap on the center | page | show the panels; a tap anywhere while the panels are open hides them |
| tap on a footnote mark (area at least 48 × 48 dp) | page | the footnote as a sheet over the page; takes priority over turning and over the panels, including when the panels are open; of two adjacent marks, the one nearest the finger |
| long press on a paragraph | page | the paragraph is highlighted, the "Read from here" button is in the visible part of the screen; while it is selected, the page does not move away following the voice; a tap elsewhere, the system "Back" or any page change cancels it |
| system "Back" (including the Android edge gesture) | reading | 1) clears the paragraph selection; 2) closes a sheet, dialog, footnote; 3) panels hidden: shows them (the book is not closed, the sound keeps playing); 4) panels shown: closes the book. The "Back" arrow in the header closes the book at once |
| slider | bottom panel, player panel | fraction of the book; the header shows the chapter under the finger; on release on another page, the page with that spot and following switched off; touching the thumb without moving changes nothing |
| dragging the page while the page is being turned automatically after the voice | page | the finger wins: the transition is cancelled, following is switched off, even if the finger returned the page to its place |
| dragging the page outside of an automatic turn, returned to the same page | page | nothing: following is not switched off |
| a second tap at the same point right after a layer change (double press on "Listen", "Close", "Stop", a choice in a sheet) | panels, sheets, page | nothing: for 350 ms after a layer change, taps are not accepted; after 350 ms, as usual |
| swipe a sheet down | all sheets | close the sheet |
| long press on a book | shelf | the book menu: "Delete narration", "Delete book" |

## What really works

Turning by tap and swipe, the transition across a chapter boundary, the slider over the book; shelf → book → back; the
table of contents with two levels (the Chekhov collection) and navigation; "Text appearance": six size steps and four
themes, applied at once, the reading position is kept when the size changes; "Listen" → the player panel, pause,
back/forward by paragraph, "Close"; highlighting of the "sounding" paragraph and the page turning after it; "To current
spot"; "Read from here" (from pause, a pause at the new spot); a footnote; speed; the sleep timer (15/30/60 minutes,
until the end of the chapter); choosing the voice of the book (even before the first listening) and of the app with the
"Sample" and its error; settings, the model choice, language, the key (entry, "Change", an empty "Done" does not erase
the key; "Change key" from the error panel); the dialogs for deleting a book, deleting a book's narration and clearing;
"Download chapter" with an estimate of the remainder, progress, "Stop" and "Download again", the "narrated" readiness by
voice and model; the download row on the reading screen with "Stop"; "100 %" on a finished book.

"Narration" is a timer: paragraph duration = characters × 0.069 s ÷ speed ÷ 4. The ×4 acceleration is so that the page
turning after the voice can be seen within a minute. There is no sound.

### The narration controller contract

The screen does not assemble actions from several calls: each action is one `NarrationController` command
(`lib/playback/narration.dart`), and the fake implementation fulfills the same contract as the real one will
(А§6.4–6.6): `listen(book, PageRange)`: the screen only reports the visible page (start and end), and the controller
chooses the spot by the rule of А§5 "Listen from `idle`" (the owner's remark 2026-11-14): if the page has a listening
spot, start from it; otherwise the first sentence that begins on the page (the tail of a sentence from the previous
page is not read); if no sentence begins on the page, the beginning of that sentence. Sentence boundaries come from
`lib/tts/sentences.dart` (А§6.1, rule 2 with clarifications (i) and (ii)) over the speech text
`lib/book/speech_text.dart` (without footnote marks and stress marks, with offsets mapped back into the block; the
same pure function will serve the app for segments).
`resume` (from pause, from the pause spot; from stop, from the current saved position), `readFrom` (from the start of
a paragraph) and `moveIfListening` (a change of place with the previous intent: a pause stays a pause),
`close(screenPosition:)` (the session is ended, the sleep timer cleared, then the reading position is handed to the
screen; the listening spot remains), `restartSession` (only when the voice or model really changed; from the start of
the current unit, including a sentence-start one), `clearAllNarration`, `deleteBookNarration`, `deleteBook` (stop the
tasks, reset chapter and probe readiness, update the library). Before each explicit start, an expired sleep timer is
cleared. `commandRevision` is a counter of the user's explicit commands (starting and moving the sound, wherever they
come from); automatic transitions do not change it. The listening spot is the controller's `unitStart` (the start of
the sounding unit); the controller writes it to `Library.saveListeningPosition` next to the reading position and reads
it with `listeningPositionOf`. `Library.savePosition` derives the fraction and chapter for the shelf from the position
itself; "finished" is a separate fact, `Library.isFinished`/`setFinished`. An error (`NarrationError`) carries the model
on which it happened (404) and the "invalid key" class. The speed is single, from the settings: both for the caption
and for the movement of the voice.

The screen turns following the voice on by a change of `commandRevision`, the same for commands from the screen, from
the notification and from the headset, and by "To current spot"; only turning (a gesture that changed the page) and the
slider switch it off, including with the stop panel (А§5).

"Download chapter" (`ChapterDownloads`): `profileFor(bookId)` is the book's current voice profile; `isVoiced`,
`estimate` (the unready remainder) and `start` take a profile; changing the voice or model stops the task (what is
ready is kept). Downloaded audio and new probes take space in the fake storage (`FakeAudioStore.addBook`,
`addSamples`). The probe (`VoiceSampler.play`) takes the full profile: after a model change the same voice is narrated
again. The screens get prices and estimates ready-made (`Tariffs`, `ChapterDownloads.estimate`); the date is provided
by the build root.

## Book text styling

- A paragraph has a first-line indent of 1.5 em, no spacing between paragraphs, left-aligned, no hyphenation.
- **Verse** (`verse`): italic, 0.92 em, 2 em left indent, **no line**.
- **Quote** (`cite`): **upright style**, 0.92 em, the same indent and a **thin vertical line** of the `line` color
  along the block (2 dp, 0.6 em from the column edge). The epigraph attribution ("Княжнин." — Knyazhnin.) is a quote
  in the model.
- A chapter heading is centered: the first line large, the following ones italic; a heading longer than a page
  continues on the next one.
- A picture is fitted to the page width and height together with the first line of the caption; a long caption
  continues.
- A footnote mark is a superscript digit of the font (`sups`) in the accent color.

There is one rule for measuring and for drawing (`lib/reader/`); FR-R3 of the spec refers to it.

## Interface languages

Russian, English, Polish, German (owner's decision 2026-11-14), Ukrainian added as the fifth by the owner's decision
2026-11-17. By default, the phone's language; if it is not one of the five, English; in the settings, "Language":
"System default" and the five languages, the choice applies at once. The strings are
`lib/screens/l10n/app_<language>.arb`, and the classes are generated by `flutter gen-l10n` (the one exception to the
rule "no code generation", А§8). Plural forms are ICU plural ("1 минута / 2 минуты / 5 минут", Polish "minuta / minuty /
minut"); money, percentages, megabytes and speed use the locale's format with a non-breaking space. The system Material
labels are the `material_ui` delegates. Google's texts are not translated. Titles of books, authors and chapters are
the book's text, not the interface's. The en, pl, de translations were made by the implementer and accepted as is
(owner's decision 2026-11-14), then proofread by an editor the same day: the edits are point ones, and the glossary
terms below are after the proofreading.

The voice-probe phrase and the reading style depend on the **book's** language (`lib/tts/book_language.dart`, FR-T7):
ru, en, pl, de, uk; English for the others; the style has no gender. For the app's voice from the settings (there is no
book) the phrase is in the interface language.

Glossary (what the reader sees; within a language, one word):

| Russian | English | Polski | Deutsch |
|---|---|---|---|
| Книги (полка) | Books | Książki | Bücher |
| Слушать | Listen | Słuchaj | Anhören |
| Проба | Sample | Próbka | Hörprobe |
| Озвучка | Narration | Nagranie / nagrania | Vertonung |
| озвучена (глава) | narrated | nagrany | vertont |
| Оглавление | Contents | Spis treści | Inhaltsverzeichnis |
| Голос | Voice | Głos | Stimme |
| Глава | Chapter | Rozdział | Kapitel |
| Скачать главу | Download chapter | Pobierz rozdział | Kapitel herunterladen |
| Вид текста | Text appearance | Wygląd tekstu | Textdarstellung |
| Таймер сна | Sleep timer | Wyłącznik czasowy | Schlaftimer |
| Скорость | Speed | Prędkość | Tempo |
| Читать отсюда | Read from here | Czytaj stąd | Ab hier lesen |
| Продолжить (карточка книги) | Continue | Czytaj dalej | Weiterlesen |
| К месту чтения | To current spot | Do bieżącego miejsca | Zur aktuellen Stelle |
| Ключ Gemini | Gemini key | Klucz Gemini | Gemini-Schlüssel |
| Потрачено | Spent | Wydano | Ausgegeben |
| Как в системе | System default | Jak w systemie | Systemstandard |

## Palette

The palette and fonts are taken from the earlier mock-up (`docs/mockup/NOTES.md`) **by the owner's decision
2026-11-14**; the components and composition are new (Material 3: sheets with a handle, Filled/Tonal/Outlined buttons,
chips, the discrete 2024 slider, rounded settings groups, Android 14+ transitions, Material rounded icons).

Tokens (`lib/app/theme.dart`):

| Token | Light | Sepia | Dark | Material 3 role |
|---|---|---|---|---|
| `bg` | `#F8F4EC` | `#F0E4CC` | `#16130F` | `surface` (screen and page background) |
| `surface` | `#FFFDF9` | `#F7EDDA` | `#221D18` | `surfaceContainerLowest/Low/–` (panels, sheets, cards, dialogs), `surfaceBright` |
| `ink` | `#221D17` | `#3A2D1F` | `#E8E0D2` | `onSurface`, `onPrimaryContainer`, `onSecondaryContainer`, `inverseSurface` |
| `ink2` | `#675E54` | `#6B5A45` | `#A09584` | `onSurfaceVariant`, `tertiary` |
| `line` | `#E3DBCE` | `#DCCBAE` | `#383029` | `outlineVariant` (dividers, tracks, the quote line) |
| `accent` | `#A8431F` | `#9A3D1B` | `#E08A5B` | `primary`, `secondary` |
| `on_accent` | `#FFFDF9` | `#FFF8EC` | `#16130F` | `onPrimary`, `onSecondary` |
| `hl` | `#F3DFCF` | `#E6C9AC` | `#3D2B1F` | `primaryContainer`, `secondaryContainer` (paragraph highlight, selected, tonal buttons) |
| scrim | `ink` × 0.42 | `ink` × 0.42 | `#000` × 0.55 | `scrim` |

Derived roles (token blends): `surfaceContainerHigh` = surface→line 35 % (`#F5F1EA`, `#EEE1CB`, `#2A241E`),
`surfaceContainerHighest` = 70 % (`#EBE5DB`, `#E4D5BB`, `#312A24`), `outline` = ink2→line 25 % (`#867D72`, `#87765F`,
`#867C6D`), `surfaceDim` = bg→line 50 %. Errors are the base Material 3 reds (`#B3261E` / `#F2B8B5`). `surfaceTint`
is transparent.

Contrast (WCAG; checked by `test/architecture_test.dart`):

| Pair | Light | Sepia | Dark |
|---|---|---|---|
| ink / bg | 15.2 | 10.6 | 14.1 |
| ink2 / bg | 5.8 | 5.3 | 6.3 |
| accent / bg | 5.5 | 5.5 | 7.0 |
| on_accent / accent | 5.9 | 6.5 | 7.0 |
| ink / hl | 13.0 | 8.5 | 10.2 |
| ink2 / surface | 6.3 | 5.7 | 5.7 |
| accent / surface | 5.9 | 5.9 | 6.3 |
| **ink2 / hl** | 4.9 | **4.2** | 4.6 |

`ink2` on `hl` in sepia is below 4.5 (NOTES.md did not compute this pair). I did not change the palette: on the
highlight of a selected row (voice, model, language, a chapter in the table of contents marked "narrated") the labels
are drawn in the `ink` color; for the table of contents a test in sepia checks this.

## Fonts

| Where | Typeface | Files |
|---|---|---|
| book text, book titles, shelf heading | **Merriweather** Regular / Italic / Bold / Bold Italic | `assets/fonts/`, OFL 1.1 |
| interface | **Roboto** Regular / Medium / Bold | `assets/fonts/`, OFL 1.1 |

Sources, commit, checksums and the Cyrillic check are in `assets/fonts/SOURCES.txt`. Roboto is the system font on
Android; it is bundled so that the browser and the test screenshots do not fetch a font from the network and look like
the phone. Polish and German letters are present in both fonts (the `l10n-*` screenshots).

The book text steps are from NOTES.md: 14/24, 15/26, **16/27**, 18/30, 20/34, 22/37 (font size/line height, dp),
multiplied by the system font scale (owner's decision 2026-11-14, FR-R6).

## Screens

Screenshots are in `docs/prototype/screens/`, 412 × 915 dp (PNG ×2), plus `n320-*` (320 × 640, font ×1.3), `w360`,
`w393` and `l10n-<language>-*` (en, pl, de, uk; the narrow ones are `l10n-de-n320-*`, `l10n-pl-n320-*`,
`l10n-uk-n320-*`). They are taken by the test `test/screens_golden_test.dart` and compared by it on every
`scripts/test.sh`; to retake them, run `bash scripts/test.sh test/screens_golden_test.dart --update-goldens`. These are
prototype screenshots for evaluation, **not an approved golden** (the golden is recorded after the screens are approved
on the phone, AGENTS.md "Interface").

The Ukrainian set `l10n-uk-*` (added 2026-11-17) consists of `01-shelf`, `07-reading-panels`, `14-player`,
`18-player-402`, `22-settings`, `n320-14-player` and `n320-22-settings`.

| Screenshot | Screen | Requirements |
|---|---|---|
| 01 | shelf | FR-L4, CONCEPT §3 "the last one larger", FR-L2 "+" |
| 02 | empty shelf | FR-L4 |
| 03 | adding and refusals | FR-L2, FR-B2, FR-B6 |
| 04, 05 | book menu, deletion | FR-L5, FR-D3 |
| 06 | reading: start of a chapter (verse and quote) and the middle | FR-R1–R3, fraction of the book |
| 07 | reading with panels: slider, book voice, "Listen" | FR-R2, FR-R4/R6 (entry points), FR-R5, FR-P3, FR-V2 |
| 08 | picture with a caption | FR-R3 |
| 09 | text appearance (sepia, step 4) | FR-R6 |
| 10, 11 | table of contents: estimate, progress, error and "Download again" | FR-R4, FR-D2 |
| 12 | footnote | FR-R3 |
| 13 | "Read from here" | FR-P3 |
| 14, 15, 16 | listening; I turn pages myself ("To current spot" in the panel); dark | FR-P1, FR-P4, FR-R6 |
| 17 | "Preparing the voice…", "Waiting for connection…", pause + timer, "End of the book" | FR-P1, FR-P6, FR-D1 |
| 18 | 402 "Top up", 404 "Choose model", invalid key "Change key", other | FR-P6, FR-P7 |
| 19, 20 | speed, sleep timer | FR-P5, FR-D1 |
| 21, 27 | book voice (a probe is playing), app voice | FR-V1, FR-V2 |
| 22–25 | settings (including "Language"), no key, model, clearing | FR-V3, FR-M1–M3, FR-P7, FR-I1 |
| 26 | the "Downloading chapter" row on the reading screen | FR-D2 (owner's decision 2026-11-14) |
| n320-* | shelf, reading, `playing` player with panels, 402, settings, text appearance, timer (on), model, table of contents, voice | FR-R8 |
| l10n-* | shelf, reading with panels, player, 402, settings in en, pl, de, uk; narrow de (player) and pl (settings), uk (player and settings) | FR-I1, FR-R8 |

## Prototype decisions (made by the owner 2026-11-14)

1. **A phone frame in the browser** with size and language switchers: only in the prototype's web build.
2. **The page-turn animation is a page slide** (like "Slide" in Play Books), not a page curl.
3. **Panels over the text**, the text under them does not shift; a tap while the panels are open hides them, except a
   tap on a footnote mark, which opens the footnote.
4. **While the player panel is visible, the page is shorter** and ends above the measured height of the panel (together
   with the download row and "To current spot"). While the screen follows the voice, the recomputation puts the page
   right at the sounding spot; "Close" recomputes the page from the spot that was on the screen (the sounding one when
   following, otherwise the start of the page), so it does not move backwards (owner's remark 2026-11-14).
5. **The slider during listening** is above the player in the same panel, on a tap of the center (FR-R5).
6. **The chapter title is only in the reading header**, it wraps; it is absent above the slider and in the player
   panel.
7. **The player's central button** is a circle on pause, a rounded square while sound plays (Material 3 Expressive).
8. **The book's voice** is the chip "Aoede ▾", both in the bottom reading panel (before listening) and in the player
   panel.
9. **"To current spot"** is a tonal button in the player panel row next to the voice chip, not a floating one over the
   text.
10. **Speed** is a sheet of six buttons, 3 × 2; **sleep timer** is a list sheet with a check mark; an enabled timer is a
    moon in the accent color and the remaining minutes under it.
11. **"Read from here"** is a floating button by the paragraph, always in the visible part above the panel; the
    selected paragraph is highlighted with the same `hl` as the sounding one.
12. **Leaving the book ends listening** (А§6.6: "closing the book → idle"): listening while browsing the shelf is not
    possible.
13. **Settings are rounded groups**; "Change" of the key is a pencil icon; the key mask is "•••• " and no more than the
    last four characters.
14. **Shelf**: "Continue" is a tonal tag in the card; "new" is an outlined label; "100 %" comes with a check mark.
15. **The adding error rows** are outlined cards with "✕".
16. **A section without its own text** ("Ионыч" — "Ionych" — before chapter I) is a separate title page; **a section
    without blocks** (`blockCount 0`) does not become a chapter; **a book without blocks** is not created: a refusal on adding
    (FR-B6).
17. **On a narrow screen with a large font** the theme tiles in "Text appearance" stack two per row if the label word
    does not fit; the "Sample" becomes a 48 × 48 icon button with a tooltip: otherwise voice names broke in the middle
    of a word.
18. **Roboto is bundled**; the `applicationId` from `flutter create` is `io.github.slawa19.audiobook_reader`.
19. Icons are the built-in Material Icons set, the `_rounded` variants (Material Symbols require a third-party
    package).
20. **Translations** en, pl, de and the glossary are the implementer's, accepted as is and proofread by an editor on
    2026-11-14: "Text appearance" = "Text appearance / Wygląd tekstu / Textdarstellung", "To current spot" = "To
    current spot / Do bieżącego miejsca / Zur aktuellen Stelle" (it used to be "Back to narration / Wróć do lektora /
    Zur Vorlesestelle": the rule is about a place in the text, not about the narration or a human reader).
21. **The gender-neutral reading style** ("in the manner of a professional audiobook") has not been checked by ear.
22. **The start spot of "Listen"** is the owner's rule of 2026-11-14 (FR-P3, А§5), which replaced the earlier "from the
    first visible place, including the tail of a paragraph" (finding No. 11). Where the rule is silent: "Listen" from a
    stop (the error panel) starts from the saved reading position; "Close" writes the sounding spot as the reading
    position if the screen was following, otherwise the start of the visible page; "the current page" is the one on
    the screen at the moment of the press (with the panels open the layout is the same, the panels are over the text).
23. **Rules a–k of the user-journey audit** ([JOURNEY_AUDIT_2026-11-14.md](../reviews/JOURNEY_AUDIT_2026-11-14.md)) are
    incorporated into the spec and А§. Where they are silent: "finished" is a separate fact: it is set by showing the
    last page (including the first layout of a one-page book) and by the end of listening, and cleared only by showing
    a page earlier than the last (a correction from the logic review, No. 4); "100 %" is also at the bottom of the last
    page and on the slider; "Back" in the reading header closes the book at once, the system one first closes the
    temporary; choosing "Same as in Settings" and explicitly the same voice is not a voice change; a failed download
    does not prevent offering a download for the current chapter; the demo "other" error is "Request contains an
    invalid argument.", because "API key not valid" is a separate recognized reason; "Война и мир" ("War and
    Peace") in the demo data is a never-opened book.
24. **From the Codex logic review of 2026-11-14** ([CODEX_REVIEW_LOGIC_2026-11-14.md](../reviews/CODEX_REVIEW_LOGIC_2026-11-14.md)):
    following is switched off only by a gesture that changed the page (a small drag with a return and a cancelled
    gesture change nothing), and by the slider on release; a re-layout (font, panel) does not clear "finished"; a held
    paragraph selection takes priority over following, including on re-layout.
25. **From the gesture audit of 2026-11-14** ([GESTURE_AUDIT_2026-11-14.md](../reviews/GESTURE_AUDIT_2026-11-14.md)):
    the protection against a follow-up tap is 350 ms after a layer change (`layerSettleTime`, `FreshLayerGuard` on the
    sheets, absorption of taps by the reading screen); a layer change counts as bottom panel ↔ player panel, the player
    panel's view, the download row, a sheet, a dialog, a screen over the reading one, but not showing the reading
    panels by a tap on the center: they appear at the edges, not under the finger (my interpretation). A vertical
    gesture is rejected by the recognizer inside the page. A finger that landed on the page during an automatic turn is
    determined at the moment of the touch. A slider without a page change is "without a move" (my interpretation: a
    move within the same page also changes nothing). Orientation is portrait only. The reading header got 8 dp side
    margins: the corners of the "Back" and "Text appearance" areas do not reach into the rounding.

## What the prototype lacks or simplifies

- The pagination computes the whole book at once, not in portions from the position (А§5, FR-R1). The reading position
  and the listening spot live in memory (`FakeLibrary`): a restart does not remember them; in the app both are in
  `state.json` (А§4).
- The unit of "narration" is a block, not a segment of А§6.1; there is no splitting of long paragraphs and no merging
  of short lines. Starting from a sentence inside a block: the fake narration starts the block from that offset
  (highlighting by block, the fraction played counted from the offset); in the app this is the start segment of А§6.1.
- `AudioStore` is only size counters and deletion; there are no file operations (`has/file/put`). Only "Download
  chapter" and probes take space; sound "synthesized" during listening takes no space in the prototype.
- **What needs checking when the fake controller is replaced** (logic review 2026-11-14, А§9): the fake `resume()` from
  pause and "back/forward" give `playing` at once: the sound of the "neighboring" segment is always ready; the real one
  must pass through `preparing`/`waiting`. The fake sends no requests and writes nothing to disk: the checks "a late
  result after "Close", deletion and a session change" need a controllable asynchronous double. The real controller
  publishes the explicit-command counter together with the new spot, synchronously.
- No sound, media session, background or lock screen: this can only be seen on the phone.
- There is no "Fake voice" row (FR-T5) in the settings.
- Texts: "Капитанская дочка" ("The Captain's Daughter"), chapters I–III, and "Ионыч" + "Дама с собачкой" ("Ionych" and
  "The Lady with the Dog"; Wikisource, public domain; assembled by `scripts/prototype-texts.py`). The picture "Степь
  перед бураном" ("The steppe before the blizzard") and the covers were drawn by a script. The other four books on the shelf have no text: a placeholder page
  opens.
- The "* * *" separator is drawn, but these texts do not contain it (it is in the synthetic book of the pagination
  test).
- Surrogate pairs, right-to-left writing and combining marks are not tested in the pagination: the demonstration books
  do not have them.
- No rotation: the first version is portrait only (the manifest and `lockPortrait()`); in the browser the orientation
  is not locked, and the phone frame is portrait anyway. Changing the window size keeps the reading place (a test).
- The edge "Back" gesture, vertical thumb movements, the notch and the "home" gesture zone are checked only on the phone
  (spec 001, FR-P9, already in stage 1).
- The "Demo states" and the captions of the browser frame are in Russian only (this is not the app's interface).
