# Spec 003. Preparing the open-source publication

Status: in progress, started 2026-11-17. The work is split between agents by file ownership; Ukrainian (R1) is merged,
the rest is in branches. The visibility of the GitHub repository is switched to public by the owner after acceptance.

The app's behavior for the reader does not change, except for the fifth interface language. No new features.

## 1. Decisions

| No. | Decision | Who and when |
|---|---|---|
| D1 | The license is **GPL-3.0** (the repository carries the `LICENSE` file; the license of the code is GPL-3.0-or-later) | the owner, 2026-11-17 |
| D2 | All documentation is **replaced** by English; no Russian copies are kept, Russian stays in git history | the owner, 2026-11-17 |
| D3 | Russian comments in code, scripts, CI and tests are translated to English; text that is data (strings of the Russian interface, book samples, fixtures, reading-style prompts) stays in its own language | the owner, 2026-11-17 |
| D4 | Ukrainian (`uk`) is the **fifth** interface language (ru, en, pl, de, uk); it is also a known book language for the TTS reading style and the voice-probe phrase (`lib/tts/book_language.dart`); unknown book languages still fall back to English | the owner, 2026-11-17 |
| D5 | Public APKs are built by GitHub Actions from a `vX.Y.Z` tag, signed with the owner's permanent key from GitHub Secrets, and published in Releases with SHA-256 checksums and a build-provenance attestation | the owner, 2026-11-17 |

## 2. Requirements

- **R1.** Ukrainian interface and TTS book language. Done: merged on 2026-11-17 (commit 76d49bb, merge 5ddfeb6). The
  golden screenshot sets include `l10n-uk-*` (seven files in `docs/prototype/screens/`: 01-shelf, 07-reading-panels,
  14-player, 18-player-402, 22-settings, n320-14-player, n320-22-settings).
- **R2.** All documentation is in English: `README.md`, `AGENTS.md`, `CHANGELOG.md`, everything in `docs/`. Anchors in
  links match the translated headings; the language count in the documents is five.
- **R3.** Comments, test names and script and CI messages are in English. Behavior does not change; data that is text
  in a specific language (the exception in D3) is left as is.
- **R4.** Licensing. Done 2026-11-17. The GPL-3.0 `LICENSE` file; third-party notices shown in the app (Flutter's
  license page plus the OFL texts of Merriweather and Roboto, which are in `assets/fonts/`); attribution of the demo
  texts, which are public-domain works from Wikisource (`assets/demo/SOURCES.txt`). The app registers the project's own
  entry and the two OFL texts with `LicenseRegistry` (`lib/screens/licenses.dart`; the texts are bundled as assets) and
  has one last row in the settings, "Open-source licenses", that opens `showLicensePage`. The version on that page is
  the constant `appVersion`, which `test/licenses_test.dart` keeps equal to `version:` in `pubspec.yaml`.
- **R5.** English screenshots of the main screens in `README.md`. Done 2026-11-17. The existing `l10n-en-*` goldens
  were not enough: the interface was English, but the shelf and the book text were Russian. So the test
  `test/readme_screenshots_test.dart` takes eight goldens into `docs/screenshots/` (shelf, reading, reading with
  panels, listening, table of contents with narration state, voice, settings, listening in the dark theme) over an
  English demo shelf and the opening of *Alice's Adventures in Wonderland* (Project Gutenberg, public domain;
  `test/fixtures/screenshots_en/`, with `SOURCES.txt` and the script that builds the book JSON). The prototype takes
  that content through the optional `DemoContent` argument of `Prototype.create`; without it nothing changes.
- **R6.** The release workflow:
  - a tag-triggered CI build (`vX.Y.Z`) that produces the signed release APK;
  - the signed APK is published in GitHub Releases, with SHA-256 checksums;
  - a build-provenance attestation for the published APK;
  - `docs/RELEASING.md` with verification instructions for users: `gh attestation verify`,
    `apksigner verify --print-certs` against the published certificate fingerprint, and the checksum;
  - toolchain pinning: the Gradle distribution checksum, `--enforce-lockfile`, GitHub Actions pinned by commit SHA.
- **R7.** Pre-publication audit. On 2026-11-17 the audit of the 179-commit history found no secrets, keystores or
  third-party copyrighted content, so the history is not rewritten. The repository visibility is switched to public by
  the owner.

## 3. Acceptance criteria

- **SC-1.** The full `scripts/test.sh` is green in the main worktree after every merge; `git status --porcelain` is
  empty; CI on GitHub is green.
- **SC-2.** No Cyrillic remains in documentation, comments, test names and script messages, except text that is data
  (D3).
- **SC-3.** The links between documents resolve, including anchors; `git diff --check` is clean.
- **SC-4.** A tag `vX.Y.Z` produces a release with the APK, `SHA-256` checksums and an attestation, and the commands in
  `docs/RELEASING.md` verify it.
- **SC-5.** The `LICENSE` file is present, the README names the license, and the in-app licenses page lists Flutter's
  packages and the two font licenses.

## 4. Out of scope

- Publication in Google Play or F-Droid. Signed APKs from GitHub Releases are the only distribution channel;
  [GOOGLE_PLAY_PLAN.md](../GOOGLE_PLAY_PLAN.md) stays a plan for later.
- Bit-for-bit reproducible builds verified by third parties. The provenance attestation proves that the APK was built
  by the repository's workflow from the tagged commit; independent bit-for-bit reproduction is not claimed.
- Rewriting git history. The audit (R7) found nothing to remove.
- Keeping Russian copies of the documents next to the English ones.

## 5. Changelog

- 2026-11-17 — the owner decided to open-source the repository under GPL-3.0, to write all documentation, comments and
  commit messages in English, to add Ukrainian as the fifth interface language, and to publish signed APKs from
  GitHub Actions (D1–D5).
- 2026-11-17 — R1 done and merged: Ukrainian as the fifth interface language (76d49bb, merge 5ddfeb6).
- 2026-11-17 — pre-publication audit (R7): the 179-commit history contains no secrets, keystores or third-party
  copyrighted content; no history rewrite.
- 2026-11-17 — R4 done: `LICENSE` (GPL-3.0, the unmodified official text), `assets/demo/SOURCES.txt` (Wikisource page
  names and revision ids; the three editorial notes of the Pushkin text are CC BY-SA 4.0), the in-app license page with
  the font and project entries, the settings row.
- 2026-11-17 — R5 done: eight English README screenshots in `docs/screenshots/` over an English demo shelf and book
  (`test/readme_screenshots_test.dart`, `test/fixtures/screenshots_en/`); `README.md` shows them, links
  `docs/RELEASING.md` and the Releases page in the install section.
- 2026-11-17 — rule for technical text (the orchestrator's decision for the open-source release, awaiting the owner's
  confirmation): diagnostic text that is not part of a designed interface state is written in English, like Google's
  own error text that the app already shows as is. The hard-coded Russian messages of `lib/tts/gemini.dart`, the
  exceptions in `lib/` and the Kotlin channel errors were translated; the interface strings stay in the ARB files.
- 2026-11-17 — spec written; documentation translated to English (R2) by a separate agent working in its own worktree.
