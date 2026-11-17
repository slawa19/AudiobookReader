# Concept: a reader with Gemini narration

Version 1 of 2026-11-14. The owner's decisions are in section 9. How it works inside —
[ARCHITECTURE.md](ARCHITECTURE.md).

## 1. What it is

An Android phone app. It opens a book from a file, shows it like an ordinary reader and reads it aloud with a Google
Gemini TTS voice — the one that won a blind test on Russian text. Reading with the eyes and listening can be mixed
freely: there is one position.

There is one user — the owner. There is no server, no accounts and no sync. The Gemini key is your own and is entered
once.

How it differs from ready-made readers: they narrate with the Android system synthesizer. Here the voice is a neural
narrator, and everything else is built just far enough to make that convenient to use.

## 2. Scenario

1. The owner downloaded an `.fb2` and tapped the file in downloads or in a messenger → "Open in the reader". The book
   is on the shelf.
2. Opens it and reads. Turns pages by tapping the screen edge or by swiping.
3. Taps "Listen". After a few seconds the voice starts from the place where it stopped last time, or, if that place is
   not on the screen, from the first sentence on the page. The current paragraph is highlighted, and pages turn by
   themselves.
4. Turns off the screen and puts the phone in a pocket. Pause and resume — from the lock screen and with the headset
   button.
5. In the evening opens the book — it is at the place where the voice fell silent.

## 3. Features of the first version

### Shelf

- A list of books with cover, title, author and the share read. The order is by last opening; the latest book is on
  top and larger than the others.
- Adding: the "+" button opens the system file picker; a file can also be opened from another app ("Open with"). The
  book is copied inside the app, and the source file can be deleted.
- Deleting: long press → "Delete". The book's narration is deleted with it; how much space will be freed is stated in
  the confirmation.
- There is no search, folders, tags or sorting: one person has dozens of books on the shelf, not thousands.

### Reading

- Paged display, turning by tap and swipe. The header and the bottom panel appear on a tap in the center.
- Table of contents and a slider across the book.
- Font size and theme: light, sepia, dark. By default the theme follows the system.
- Images from the book are in the text. Footnotes open over the page, without navigating away.
- The position is remembered automatically — by paragraph and the place within it, not by page number, so it survives
  a font change and screen rotation.

### Narration

- "Listen" continues from the place where the voice stopped if it is on the screen; otherwise it reads from the first
  sentence that begins on the page. Long press on a paragraph → "Read from here".
- Pause and resume; to the previous and next paragraph. There is no rewind by seconds: the unit of narration is the
  paragraph (several short lines in a row go as one unit).
- Speed 0.75–2× is changed by the player, with no new synthesis and no money.
- Works with the screen off and in the background: a notification with controls, the lock screen, headset buttons. A
  call or another app with sound pauses the reading; the user resumes it.
- Sleep timer: 15, 30, 60 minutes, until the end of the chapter.
- Voice choice: 30 Gemini voices in two groups, each with a "Sample" button (the voice probe) on the same phrase. The voice is common to
  the app; a book can have its own.
- What has been narrated is stored and not paid for a second time: repeating, going back and listening again are free.
- "Download chapter" narrates a chapter in advance — for a trip without a connection. A price estimate is shown before
  it starts.
- Footnotes, image captions and the table of contents are not read aloud.

### Settings

One screen: the Gemini key (with a link to where to get it), voice, model (3.8 Flash or Flash-Lite), spent this month,
space used by narration with a "Clear" button.

### Money in view

Narration is paid: about $0.8 per hour of audio now and about $1.6 from 01.01.2027 on the default model; a book of 500
thousand characters is about $8 and $15 (calculation — [GEMINI_TTS.md](GEMINI_TTS.md), section "Price"). Therefore:

- only a small reserve is narrated ahead, not the whole book: you stopped — you stop paying;
- a price estimate is shown before every action larger than the reserve ("Download chapter");
- the spent counter is computed from the billed tokens in Google's responses, not from an estimate;
- on an empty balance (a 402 response) reading stops with a "Top up" button and resumes from the same paragraph.

## 4. Formats

| Format | Version | Note |
|---|---|---|
| FB2, FB2.ZIP | 1 | the main format of Russian-language libraries; the encoding is taken from the XML header (often windows-1251) |
| EPUB 2 and 3 | 1 | no DRM |
| TXT | 1 | the encoding is detected from the content; paragraphs by blank lines |
| MOBI, AZW3 | 2 | no DRM; there is no ready-made parser for the chosen stack, so one is written — a separate spec |
| PDF, DJVU | out of scope | these are pages, not text: they are not reflowed on a phone, and there is nothing to read aloud without recognition |

Books with DRM do not open; this is stated when adding.

MOBI is deferred to the second version deliberately. FB2 and EPUB are XML and ZIP with a documented structure. MOBI is
a binary container with two generations of markup and its own compression; doing it "along the way" would delay
everything else.

## 5. How it works

**One book model for all formats.** The parser of any format produces the same thing: chapters, and in them blocks —
heading, paragraph, image, footnote. Every block has a permanent number. The reading screen, narration and position
work only with this model and know nothing about formats. A new format is a new parser and nothing more.

**Position** is a block number and an offset within it. One for reading and for narration.

**The app draws the text itself**, without an embedded browser. Otherwise one cannot reliably know which paragraph is
on the screen, highlight the one being read and turn the page after the voice.

**Narration is a queue of paragraphs.** One paragraph is one request and one audio file; a long paragraph is split by
sentences, short consecutive lines are merged. The file name is the fingerprint of the text and the voice profile
(model + voice + style), as in Studio: "the file exists" means "this paragraph has already been narrated with this
voice". The player plays the files in a row; the queue keeps a reserve of a few paragraphs ahead and stops together
with the player. A transient network or Gemini error is retried by itself, and as long as there is audio in reserve
the user does not notice it.

**Storage.** The book and its images are in the app's storage. The shelf and positions are files in the book's folder,
with no database. Audio is there too, compressed. The key is in Android's secure storage.

**Only Gemini needs the network.** No analytics, no crash reports, no book catalogs.

## 6. Stack

I propose agreeing to Flutter. The argument is not that it is cross-platform — there is one platform — but how the
agents' work is verified.

| | Flutter | Kotlin + Compose |
|---|---|---|
| Verification without a phone | logic and screen tests and screenshots run in WSL and in CI | screen tests need an emulator or Robolectric |
| Background playback | ready-made packages `just_audio` and `audio_service` | native Media3, the most reliable |
| FB2, EPUB, TXT parsing | pure Dart, verified on sample files without a device | the same in Kotlin |
| MOBI | write it ourselves | write it ourselves or pull in a C library |
| Own text rendering with pagination | text measurement tools exist | exist |
| Audio compression | through the Android system codec, a small Kotlin bridge | directly |

The project is written by agents, not by a human in Android Studio. An agent needs a fast verifiable "edit → run"
loop in the same WSL where it works; Flutter has it, while with Compose it is provided only by an emulator, which is
hard to run in WSL. That decides it.

The price of the choice: two places need native Android code (audio compression; possibly the subtleties of the media
session). They are isolated in one small module.

Kotlin is worth choosing if the owner ever wants to maintain the code by hand in Android Studio or considers the
background player the main risk. iOS is not planned and is not an argument.

Flutter and package versions are pinned at installation, from current documentation, not from memory.

## 7. Out of scope

Rejected deliberately; comes back only by the owner's decision.

- Sync, cloud, accounts, a server of our own.
- Book catalogs and stores, OPDS, built-in downloading from the network.
- Bookmarks, quotes, notes, highlights, dictionary, translation.
- Search in the book text — the first candidate for the second version, if needed.
- Reading statistics, goals, achievements.
- Customizing fonts, margins, spacing, alignment, gestures: one well-chosen set.
- PDF, DJVU, comics, DRM.
- Several voices in one book, roles, editing the text before narration — that is AudiobookStudio's job.
- Export of narration to mp3 — Studio as well.
- iOS, tablet layout, publication in Google Play: the app is installed as an APK file. (Since 2026-11-17 signed APKs
  are published on the GitHub Releases page of the open-source repository; Google Play and F-Droid are still out of
  scope — [specs/003-open-source.md](specs/003-open-source.md).)

## 8. Stages

Each stage ends with something you can hold in your hands. The order of implementation and the numbering of its
stages are in [spec 001](specs/001-first-version.md), section 2; here is the general plan.

0. **Measurements and environment.** The measurement of latency and synthesis speed from a work computer was done on
   2026-11-14 ([GEMINI_TTS.md](GEMINI_TTS.md), "Latency and synthesis speed"); the starting piece was chosen from it.
   Installing Flutter and building the APK in WSL, an empty app on the phone and the remaining measurements (mobile
   network, simultaneous requests, short text) — stage 0 of spec 001 ([ARCHITECTURE.md](ARCHITECTURE.md), section 11);
   the paid ones — with the owner's consent.
1. **Mock-up** in FigCraft: shelf, reading, reading panel, player, table of contents, voice choice, settings, empty
   shelf, no key, no money.
2. **Reader without sound:** the book model, FB2 and EPUB, shelf, reading, position. Already useful on its own.
3. **Narration:** the Gemini client, queue, player, background and lock screen, voice choice, money counter.
4. **Polish:** TXT, sleep timer, "Download chapter", clearing space.
5. **Second version:** MOBI and AZW3.

## 9. The owner's decisions

**All six proposals were accepted by the owner on 2026-11-14.**

| No. | Question | Decision |
|---|---|---|
| 1 | Stack | Flutter (section 6) |
| 2 | The free Android system voice as a second option — reading without money and without a connection | not in the first version: by quality it is among those already rejected, and a second engine doubles the player logic. The engine interface leaves the door open |
| 3 | MOBI | in the second version (section 4) |
| 4 | Listening on the phone to books already narrated in AudiobookStudio (the book file and the chapters' mp3) | after the first version, as a separate spec: the audio is already paid for, but it is a second source of books |
| 5 | Turning pages or scrolling | pages, as the owner asked; there is no scrolling mode |
| 6 | Repository | open source under GPL-3.0, `slawa19/AudiobookReader` (decision of 2026-11-17; it was private from 2026-11-14 until then) |

Interface languages: Russian, English, Polish and German (decision of 2026-11-14); Ukrainian added as the fifth
(decision of 2026-11-17). Everything about publication — [specs/003-open-source.md](specs/003-open-source.md).

## 10. Risks

- **Latency to first audio.** If a paragraph request takes ten seconds or more, "press and listen" will not work
  without a streaming response or splitting the first paragraph by sentences. The measurement from a computer on
  2026-11-14 was resolved by the starting piece ([ARCHITECTURE.md](ARCHITECTURE.md), section 6.1); the mobile network
  is checked at stage 0 of spec 001.
- **Android stops background apps.** Manufacturers cut the background differently; the player is built as a
  foreground service with a media notification and is verified on the owner's phone, not on an emulator.
- **The price doubles from 2027.** Flash-Lite is a third cheaper and available in settings; the counter shows the
  real spend.
- **Google's models are shut down on a schedule.** Model identifiers are in one place; a 404 response on a model
  leads to settings, not to a failure.
- **Dirty files.** FB2 from network libraries can have broken XML and a wrongly declared encoding. The parser is
  verified on the owner's real files, not only on sample ones.
