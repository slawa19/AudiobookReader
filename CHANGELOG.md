# Changelog

What changed for the reader. Format — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Decisions and their
reasons are in the spec's Changelog ([docs/specs/001-first-version.md](docs/specs/001-first-version.md)); details are
in the git history.

## Unreleased — 0.1.0

The first version, in development; there have been no releases yet. The build number is 2: the state after the rework
following the review and the full phone check of 2026-11-16.

### Added

- The book shelf: adding with the "+" button, through "Open with" and "Share"; deleting a book and its narration.
- The formats FB2, FB2.ZIP, EPUB, TXT; table of contents, footnotes, images, verse.
- Paged reading: light and dark themes, font size, saving the position.
- Narration with Google Gemini TTS voices: "Listen" from any paragraph, highlight of the sounding paragraph, the page
  following the voice, speed, sleep timer, voice choice with a voice probe.
- The player's "back" and "forward" move by paragraphs.
- Background playback, controls from the notification, the lock screen and the headset.
- What has been narrated is stored on the phone and not paid for again; the spend is visible in settings; "Download
  chapter" with a price estimate.
- The interface in Russian, English, Polish, German and Ukrainian (Ukrainian added on 2026-11-17).
- The app icon: an open book whose lines turn into sound.
- The last row of the settings, "Open-source licenses", opens the standard Flutter license page: the notices of the
  libraries and the engine, the licenses of the Merriweather and Roboto fonts, the sources of the demo texts with the
  CC BY-SA attribution of their Wikisource notes, and the project's own license (GPL-3.0-or-later; the repository has
  the `LICENSE` file).

### Changed

- Diagnostic texts that are not part of a designed interface state (for example, the details of an error from the
  Gemini client) are in English, like Google's own error text that the app shows as is. The interface strings are
  unchanged and stay in the five ARB files.

### Project

- The public name of the app is **Book AudioReader**: the Android label, the license page, the web prototype and the
  README. The repository was renamed to `BookAudioReader` the same day; the Dart package and the applicationId keep
  `audiobook_reader`, so updating an installed app is not affected.
- The repository is prepared for open-source publication under GPL-3.0-or-later (`LICENSE`; the fonts and the demo
  texts keep their own licenses, see `assets/*/SOURCES.txt`). Documentation, code comments, test names and commit
  messages are in English ([spec 003](docs/specs/003-open-source.md)).
- Signed APKs are meant to be published in GitHub Releases from a `vX.Y.Z` tag with SHA-256 checksums and a
  build-provenance attestation (`.github/workflows/release.yml`, [docs/RELEASING.md](docs/RELEASING.md)). No release has
  been cut yet.
- The README has English screenshots (`docs/screenshots/`).

### Fixed

- After "forward" a one-line page could appear, and following the voice was turned off.
- The size of a book on the shelf counted the narration twice after the app restarted.
- The player notification stayed in the shade after the end of the book and after the player was closed.
- A long voice name was truncated on the player panel even though there was room.
- A program error during a request to Gemini stops narration instead of being retried as a network error.
- After pause, paging and "continue" the screen returns to the same page instead of laying the text out again.
- The chapter title on the "Continue" card and in the reading header takes no more than two lines.
- After choosing a chapter in the table of contents the panels do not flash: the page opens at once without them.
- The license page listed the app twice, as "Book AudioReader" and as "audiobook_reader"; now once.
- Android showed the app's notifications as blocked, and they could not be turned on in the system settings. The app
  now asks once, the first time listening starts, whether it may send notifications; listening does not wait for the
  answer, and the player card works either way.
