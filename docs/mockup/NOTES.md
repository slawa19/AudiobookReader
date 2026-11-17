# The reader mock-up: what is in it and how to read it

Version of 2026-11-14. The mock-up's source is `build_mockup.py`; `reader.figcraft` and `png/` are built from it. The
generator is edited, not the mock-up file. The mock-up itself is drawn with Russian texts; the quotes below give the
English string of the same key from `lib/screens/l10n/app_en.arb`.

## Build

```
# in WSL, from docs/mockup (Python standard library only):
python3 build_mockup.py <scratch>/script.json
# in Windows:
figcraft-cli run <scratch>/script.json --out reader.figcraft --no-system-fonts > <scratch>/run.log
# in WSL — reconcile the layer numbers with the output of run:
python3 build_mockup.py --check <scratch>/script.json <scratch>/run.log
# in Windows:
figcraft-cli export reader.figcraft --out png --scale 2 --no-system-fonts
```

The `--no-system-fonts` flag is mandatory: then the picture is identical on any machine.

## Fonts

| Where | Typeface | Why |
|---|---|---|
| Interface | **Roboto** (the Android system font) | no need to embed |
| Book text, book titles, the shelf heading | **Merriweather** (OFL, embedded in the app) | a screen serif with Cyrillic and a large x-height, holds up at a small size |

Source Sans 3 and Source Serif 4 from the draft are absent from FigCraft's built-in set (checked with `text.fonts`),
and the mock-up does not use system fonts. If the owner wants Source Serif 4 — it can be embedded in the app, but then
the mock-up will stop matching the screen.

### Book text: the size steps

One typeface — Merriweather Regular (italic — Merriweather Italic, bold — Bold). There are six steps, a common
line-height multiplier of ≈ 1.7, left alignment, no hyphenation:

| Step | 1 | 2 | **3 (default)** | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Font size, sp | 14 | 15 | **16** | 18 | 20 | 22 |
| Line height, dp | 24 | 26 | **27** | 30 | 34 | 37 |

The size of the book text is set only by this setting and is **not multiplied by the system font scale** (a decision
that needs confirmation — see below); the interface respects the system scale.

### The check combination "narrow screen + large font" (FR-R8)

Screens are checked at **a width of 320 dp (height 640 dp) with a system font scale of 1.3** (`textScaleFactor` 1.3 —
"the largest" on Android before version 14), the book text at step 6. Criterion: no caption is cut off without an
ellipsis, the buttons do not overlap each other, the player and reading panels do not extend beyond the screen. The
mock-up itself was **not drawn** at this combination — only 360 × 800 at scale 1.0 was drawn.

### The interface scale (Roboto)

| Role | Weight | Size / line height |
|---|---|---|
| The shelf heading "Books" | Merriweather Bold | 26 / 32 |
| A screen, sheet, dialog heading | Medium | 20 / 26 |
| A heading in the reading header, an item with a title | Medium | 16 / 22 |
| Body text, setting values | Regular | 16 / 22 |
| Buttons | Medium | 15 / 20 |
| Secondary text | Regular / Medium | 14 / 20 |
| Captions, explanations | Regular | 13 / 18 |
| Section labels (FEMALE, SPENT) | Medium, uppercase, letter-spacing 6% | 12 / 16 |

Numbers with units ("96 МБ", "0,19 $", "34 %" in the Russian mock-up) use a non-breaking space.

## Palette

One accent — terracotta. Each theme is one set of tokens; the interface and the book page take their colors from one
theme.

| Token | Light | Sepia | Dark | Where |
|---|---|---|---|---|
| `bg` | `#F8F4EC` | `#F0E4CC` | `#16130F` | the background of the screen and the page |
| `surface` | `#FFFDF9` | `#F7EDDA` | `#221D18` | header, panels, sheets, cards, dialogs |
| `ink` | `#221D17` | `#3A2D1F` | `#E8E0D2` | main text |
| `ink2` | `#675E54` | `#6B5A45` | `#A09584` | secondary text, inactive icons |
| `line` | `#E3DBCE` | `#DCCBAE` | `#383029` | dividers, tracks, outlines |
| `accent` | `#A8431F` | `#9A3D1B` | `#E08A5B` | the main button, links, the current item, a footnote |
| `on_accent` | `#FFFDF9` | `#FFF8EC` | `#16130F` | text and icons on the accent |
| `hl` | `#F3DFCF` | `#E6C9AC` | `#3D2B1F` | highlight of the sounding / selected paragraph, the current item |
| scrim | `ink` × 0.42 | `ink` × 0.42 | `#000` × 0.55 | under sheets and dialogs |

Contrast (WCAG, computed by the generator): light — ink/bg 15.2, ink2/bg 5.8, accent/bg 5.5, on_accent/accent 5.9,
ink/hl 13.0; sepia — 10.6 / 5.3 / 5.5 / 6.5 / 8.5; dark — 14.1 / 6.3 / 7.0 / 7.0 / 10.2. All ≥ 4.5.

The placeholder covers (`#7A3B2E`, `#3D5A4C`, `#40506B`, `#6B5A3A`, `#5B3F5E`) are for the mock-up only; a book
without a cover gets a placeholder in the `line` color with the first letter of the title.

## Grid and sizes (dp)

- The screen is 360 × 800. Interface margins are **16**. The book text column is **24** from the edges (the page frame
  starts at x = 16, the paragraph has another 8 inside; those 8 are a reserve for the highlight).
- Touch targets are at least **48 × 48**. Icons are 24 in a 48 cell; the player's "back/forward" are 32 in a 48 cell.
- The status bar is 28. On the reading screen without panels there is none (full-screen mode).
- The header: 28 + 56, `surface` background, a 1 line below. The "back/close" icon at x = 16; the title at x = 64;
  the cells on the right are 48 each from a right margin of 4.
- **The page:** line step 27 at step 3; first-line indent 24; no spacing between paragraphs. The page height is a
  multiple of the line step — the last line is not cut. A chapter heading is a block of 4 lines (108), the text is
  pressed to the bottom of the block with an inset of 14 (so the panel header does not overlap it). The paragraph
  highlight is `hl`, radius 6, extends 8 beyond the column on the left and on the right and exactly by lines at the top
  and bottom. The footnote mark is `accent`, Bold.
- The bottom reading panel: 168. The slider: a track of 4 at 24 from the edges, a thumb of 20; the caption "34% of the
  book" below; "Listen" — full width minus 16, height 52.
- **The player panel: 152**, `surface` background, a 1 line on top. Row A: y + 4, height 48 — "Voice: Aoede ▾" on the
  left, "✕" on the right (icon x = 320, y + 16). Row B: y + 60, height 64 — speed (a 56 × 48 cell, x = 12), "back"
  (a 48 cell, x = 84), "play/pause" (a circle of 64 in the center, icon 32), "forward" (a 48 cell, x = 228), the sleep
  timer (a 56 × 48 cell, x = 292). The bottom — 28 for gestures.
- The error panel — by content: margins 16 / 16 / 20 / 16, 16 between the text and the buttons, two buttons of 160
  with a gap of 8 (or one full width).
- Buttons are pills of height 48 (radius 24), icon 20 + a gap of 8. A text button at the right edge pushes the caption
  to the margin of 16.
- The bottom sheet: radius 24 at the top, a handle of 32 × 4 at 10 from the top, the heading at 30 from the top and 24
  from the edge.
- The dialog: screen margins 24, radius 24, inner margins 24; the buttons at the bottom right, "Cancel" is a text
  button.
- The shelf: the "Continue" card 172 (cover 96 × 140, card radius 16); rows of 92 (cover 52 × 72, the divider from
  x = 84); the "+" button 56 × 56, radius 16, 16 from the right and 24 from the bottom edge.
- List rows: table of contents 48 (level indent 24), voices 64, settings 72, timer 52.

## Screens and requirements

| Screen | What it covers |
|---|---|
| 01 Shelf | FR-L4 (order, cover or letter, author, share), "the latest is larger" (CONCEPT §3), FR-L2 "+" |
| 02 Shelf — empty | FR-L4 "an invitation to add" |
| 03 Shelf — adding | FR-L2 "Adding…", the refusals FR-B2 and FR-B6 (with the technical reason in small print) |
| 04 Shelf — book menu | FR-L5 "Delete", FR-D3 "Delete narration" with the size |
| 05 Shelf — deletion | FR-L5 confirmation with the title and size |
| 06 Reading | FR-R1, FR-R2, FR-R3 (heading, first-line indent, footnote mark), the share of the book |
| 07 Reading — panels | FR-R2 (tap in the center), entries to FR-R4 and FR-R6, FR-R5 slider, FR-P3 "Listen" |
| 08 Reading — verse and an image | FR-R3 (epigraph verses, an image fitted to the page, a caption) |
| 09 Text appearance | FR-R6 (size steps, four themes); the page behind the sheet is already in sepia |
| 10 Table of contents | FR-R4 (levels, the current one), FR-D2 estimate before the start |
| 11 Table of contents — downloading | FR-D2 the ready share and "Stop", A§6.7 (runs while the app is open) |
| 12 Footnote | FR-R3 a footnote over the page |
| 13 Read from here | FR-P3 long press |
| 14 Listening | FR-P1 `playing`, FR-P4 highlight of the sounding paragraph |
| 15 Listening — paging myself | FR-P4 "to the reading place" |
| 16 Listening — dark | FR-R6 the dark theme on the main screen |
| 17 Player — states | FR-P1, FR-P6: `preparing` "Preparing the voice…", `waiting` "Waiting for connection…", `paused` with the sleep timer on (FR-D1), "End of the book" |
| 18 Player — stop | FR-P6, FR-P7: 402 "Top up", 404 "Choose model", others — Google's text |
| 19 Speed | FR-P5 |
| 20 Sleep timer | FR-D1 |
| 21 Voice | FR-V1 (groups, character, "Sample", the current one), FR-V2 the book's voice |
| 22 Settings | FR-V2, FR-V3, FR-M2 (two months), FR-M3 |
| 23 Settings — no key | FR-P7 "Listen" without a key leads here, the key field is focused |
| 24 Settings — model | FR-V3, FR-M1 (the price now and from 01.01.2027) |
| 25 Settings — clearing | FR-M3 confirmation |

17 and 18 are state boards, not phone screens: the panel is drawn separately in every state, with the state code above
it. On the phone the panel sits at the bottom of the reading screen, as in 14.

Taken into account from the spec review: "page N of M in the chapter" removed (the panel has only the share of the
book); the "✕" on the player panel is present in all states — it ends listening, the panel disappears; "End of the
book" added; there is nothing about a phone call in the interface; there is no player panel on the "Voice" screen
(choosing a voice pauses the reading).

## Decisions I made that need confirming

1. **Fonts** Roboto + Merriweather instead of Source Sans 3 + Source Serif 4 (the reason is above).
2. **The light theme is lighter than the draft** (`#F8F4EC` instead of `#F7F2E8`), to differ from sepia; sepia got its
   own palette.
3. **Panels over the page:** a tap in the center does not shift the text. The status bar is visible only together with
   the panels.
4. **While listening is under way**, the player panel stands at the bottom instead of the bottom reading panel; a tap
   in the center shows only the header (not drawn). There is no slider across the book during listening.
5. **The book's voice is chosen from the player panel** ("Voice: Aoede ▾"), not from the bottom reading panel: there
   is only the slider and "Listen", as asked. The first row of the voice screen is "Same as in Settings".
6. **Speed is a separate sheet** of six buttons, not cycling by taps (six values by cycling are inconvenient).
7. **Add errors are rows on the shelf**, they hang until "✕", no pop-up windows.
8. **"Download chapter" is only for the current chapter**, a block under it in the table of contents; fully narrated
   chapters are marked "narrated". This mark is not from the spec, but without it one cannot see what has already been
   downloaded.
9. **A "Paste" button in the key field**: the key on a phone is entered only by pasting.
10. **The book text does not follow the system font scale** — it has its own setting (FR-R6).
11. **"Delete narration" of one book also asks for confirmation** with the same dialog as 05 and 25 (not drawn).
12. **The share read on the shelf**: "new" instead of 0% and "read" ("прочитана" in the mock-up) instead of 100%.
13. **The sleep timer is on** — a moon icon in the accent color and the remaining minutes under it (17, `paused`).
14. **The error text** — in our own words on one line, below it Google's response as is (FR-P6 requires "the error
    text"; Google's English response without an explanation is unclear).

## What is not drawn

- The "Fake voice" line in settings (FR-T5) — only in the debug build.
- The header over the listening screen; sheets and dialogs in the dark theme and sepia (the colors are the same
  tokens).
- The male group of voices (the list scrolls; the heading "MALE · 16" is built like "FEMALE · 14").
- The media notification and the lock screen — system ones, drawn by Android.
- The divider "* * *" on the page: centered in the column, `ink2`, with a line of space above and below.
- The check combination 320 dp × 1.3.
