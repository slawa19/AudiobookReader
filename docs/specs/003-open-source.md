# Spec 003. Preparing the open-source publication

Status: started 2026-11-17; all of R1–R7 is merged into `main` the same day, except the owner's steps: the visibility
of the GitHub repository is switched to public by the owner, after which the first real release can be cut (R6, SC-4).
The state and the owner's list are in [WHERE_WE_ARE.md](../WHERE_WE_ARE.md).

The app's behavior for the reader does not change, except for the fifth interface language. No new features.

## 1. Decisions

| No. | Decision | Who and when |
|---|---|---|
| D1 | The license is **GPL-3.0** (the repository carries the `LICENSE` file; the license of the code is GPL-3.0-or-later) | the owner, 2026-11-17 |
| D2 | All documentation is **replaced** by English; no Russian copies are kept, Russian stays in git history | the owner, 2026-11-17 |
| D3 | Russian comments in code, scripts, CI and tests are translated to English; text that is data (strings of the Russian interface, book samples, fixtures, reading-style prompts) stays in its own language | the owner, 2026-11-17 |
| D4 | Ukrainian (`uk`) is the **fifth** interface language (ru, en, pl, de, uk); it is also a known book language for the TTS reading style and the voice-probe phrase (`lib/tts/book_language.dart`); unknown book languages still fall back to English | the owner, 2026-11-17 |
| D5 | Public APKs are built by GitHub Actions from a `vX.Y.Z` tag, signed with the owner's permanent key from GitHub Secrets, and published in Releases with SHA-256 checksums and a build-provenance attestation | the owner, 2026-11-17 |
| D6 | The public name of the app is **Book AudioReader**; the repository and the release file are named `BookAudioReader` (renamed 2026-11-17); the Dart package and the applicationId keep `audiobook_reader` | the owner, 2026-11-17 |

## 2. Requirements

- **R1.** Ukrainian interface and TTS book language. Done: merged on 2026-11-17 (commit 8c0a19d, merge fee3278). The
  golden screenshot sets include `l10n-uk-*` (seven files in `docs/prototype/screens/`: 01-shelf, 07-reading-panels,
  14-player, 18-player-402, 22-settings, n320-14-player, n320-22-settings).
- **R2.** All documentation is in English: `README.md`, `AGENTS.md`, `CHANGELOG.md`, everything in `docs/`. Anchors in
  links match the translated headings; the language count in the documents is five. Done 2026-11-17 (merges 5ca16c8,
  33dc69d, 8caca5f); a later consistency pass brought the status documents, the index and the links in line with the
  merged work.
- **R3.** Comments, test names and script and CI messages are in English. Behavior does not change; data that is text
  in a specific language (the exception in D3) is left as is. Done 2026-11-17 (merges a30ec79 tooling and CI, 037414a
  and a983d6a tests, d505c82 `lib/`, `android/`, `web/`). Technical, non-interface messages in production code (the
  Gemini client, exceptions, Kotlin channel errors) are English too, merge 0d4a45e; the Changelog records the rule and
  that it awaits the owner's confirmation.
- **R4.** Licensing. Done 2026-11-17. The GPL-3.0 `LICENSE` file; third-party notices shown in the app (Flutter's
  license page plus the OFL texts of Merriweather and Roboto, which are in `assets/fonts/`); attribution of the demo
  texts, which are public-domain works from Wikisource (`assets/demo/SOURCES.txt`). The app's own entries are in the
  `NOTICES` file at the repository root, in the flutter tool's NOTICES format: "Book AudioReader" (the copyright,
  GPL-3.0-or-later, the repository link and the text of `LICENSE`), the two OFL texts and "Demo texts" with
  `assets/demo/SOURCES.txt` (the Wikisource sources and the CC BY-SA attribution of three editorial notes). The flutter
  tool reads a package's `NOTICES` in place of its `LICENSE`, so the root package is no longer listed a second time
  under its Dart name `audiobook_reader` (2026-11-17; before that the entries were registered with `LicenseRegistry`
  at startup and the tool added `LICENSE` under the Dart name). The app has one last row in the settings,
  "Open-source licenses", that opens `showLicensePage`. The version on that page is
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

  Status: the workflow `.github/workflows/release.yml`, `docs/RELEASING.md` (with the published certificate
  fingerprint) and the pinning are done and merged on 2026-11-17 (merge e286b61, fingerprint d39037d). The four signing
  secrets and the variable `SIGNING_CERT_SHA256` are set in GitHub. The dry run of 2026-11-17 (run 44035431681)
  passed: tests, build, signing, certificate check, checksums; the attestation and release steps are skipped in a dry run. **No release has been cut:** an attestation needs a public repository, so the first real release
  waits for the visibility switch.
- **R7.** Pre-publication audit. On 2026-11-17 the audit of the history found no secrets, keystores or third-party
  copyrighted content (the audit recorded 179 commits; `git rev-list --count` gives 181 for the commit before the one
  that wrote the audit into this spec, 6df6e62). Later that day the history was **rewritten once**, for a reason the
  audit had not looked at: by the owner's decision the personal author and committer e-mail was replaced with the
  owner's GitHub noreply address in every commit (210 commits at the rewrite), and the next commit, 3e73e6f, remapped
  the commit hashes quoted in the documents to the new ones. The old commits may stay reachable on GitHub by a direct hash
  until GitHub garbage-collects them; the owner chose to publish as is. The independent review of 2026-11-17 (finding 5)
  found one more item in the reachable history: two old revisions of `AGENTS.md` (commits 3a77332 and 6df6e62) name the
  Windows user account in the absolute path of the permanent keystore. They hold no key material and the current tree
  does not contain the path. The owner decided on 2026-11-17 to publish with the history as rewritten that day, without
  a second rewrite; the risk is judged low. What remains is the owner's: switching the repository visibility to public.

## 3. Acceptance criteria

- **SC-1.** The full `scripts/test.sh` is green in the main worktree after every merge; `git status --porcelain` is
  empty; CI on GitHub is green. Verified locally at `9210fdc` (the merge of R5): analyzer clean, 914 tests passed. CI on
  GitHub: not verified here; check with `gh run list` after the push.
- **SC-2.** No Cyrillic remains in documentation, comments, test names and script messages, except text that is data
  (D3). Verified on 2026-11-17 by a scan of all tracked text files: what remains is quoted interface strings, book and
  test text, reading-style prompts, sentence-boundary examples and the Russian page names in the source notes, each with
  a gloss in documents; one leftover (the comment in `docs/logo.svg`) was translated.
- **SC-3.** The links between documents resolve, including anchors; `git diff --check` is clean. Verified on 2026-11-17
  by a script over all tracked `*.md` files: 326 relative links and anchors, none broken; the quoted names of
  documents' sections and the `A§N` references all point to existing headings.
- **SC-4.** A tag `vX.Y.Z` produces a release with the APK, `SHA-256` checksums and an attestation, and the commands in
  `docs/RELEASING.md` verify it. **Not verified:** no release exists yet (the dry run does not attest).
- **SC-5.** The `LICENSE` file is present, the README names the license, and the in-app licenses page lists Flutter's
  packages, the two font licenses and the demo-text attribution. The file and the README are verified;
  `test/licenses_test.dart` checks the root `NOTICES` file against `LICENSE`, the two OFL texts and
  `assets/demo/SOURCES.txt`, checks the NOTICES that the flutter tool builds for the test bundle (the app listed once,
  as "Book AudioReader", never as `audiobook_reader`), and the settings row that opens the page. The NOTICES inside the
  fake debug APK built on 2026-11-17 has the app once and no `audiobook_reader`; the page itself has not yet been looked
  at on the phone with this build.

## 4. Out of scope

- Publication in Google Play or F-Droid. Signed APKs from GitHub Releases are the only distribution channel;
  [GOOGLE_PLAY_PLAN.md](../GOOGLE_PLAY_PLAN.md) stays a plan for later.
- Bit-for-bit reproducible builds verified by third parties. The provenance attestation proves that the APK was built
  by the repository's workflow from the tagged commit; independent bit-for-bit reproduction is not claimed.
- Rewriting git history to remove content. The audit (R7) found nothing that had to go; the one rewrite of 2026-11-17
  replaced only the author and committer e-mail. A second rewrite to remove the keystore path with the Windows user
  account from two old `AGENTS.md` revisions was declined by the owner on 2026-11-17 (R7).
- Keeping Russian copies of the documents next to the English ones.

## 5. Changelog

- 2026-11-17 — the owner decided to open-source the repository under GPL-3.0, to write all documentation, comments and
  commit messages in English, to add Ukrainian as the fifth interface language, and to publish signed APKs from
  GitHub Actions (D1–D5).
- 2026-11-17 — R1 done and merged: Ukrainian as the fifth interface language (8c0a19d, merge fee3278).
- 2026-11-17 — pre-publication audit (R7): the history contains no secrets, keystores or third-party copyrighted
  content; nothing to remove. (The history was later rewritten once for the e-mail; see the entry on the rewrite.)
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
- 2026-11-17 — the owner named the app **Book AudioReader** (D6): the Android label (`Book AudioReader`,
  `Book AudioReader (fake)`), the license page, the web prototype (`web/`, the device frame title) and the
  documentation use it; the package and the applicationId (changing it would break updating the installed app) are unchanged.
- 2026-11-17 — The owner had the repository switched to public and renamed to `slawa19/BookAudioReader`; the release
  file is `BookAudioReader-<version>.apk`. Links, the attestation command and the license notice follow.
- 2026-11-17 — spec written; documentation translated to English (R2) by a separate agent working in its own worktree.
- 2026-11-17 — R2 and R3 done and merged: documentation, then tests, tooling and CI messages, then `lib/`, `android/`
  and `web/` comments in English; section references are written `A§N` and spec decisions `D1…D12` with Latin letters.
- 2026-11-17 — R6 done and merged: `release.yml` (tag `vX.Y.Z` → tests → signed APK → certificate check →
  `SHA256SUMS` → attestation → GitHub Release), `docs/RELEASING.md`, the Gradle distribution checksum,
  `pub get --enforce-lockfile` in the scripts, actions pinned by commit SHA; the certificate fingerprint is published in
  `RELEASING.md`. The signing secrets and `SIGNING_CERT_SHA256` were set in GitHub; the dry run of 2026-11-17 passed (attestation
  and release steps are skipped in a dry run). No release had been cut at that point and the repository was still private.
- 2026-11-17 — consistency pass over the documents after the merges: status documents, index, changelog and links
  brought in line; `scripts/prototype.sh` now runs `pub get --enforce-lockfile` like the other scripts.
- 2026-11-17 — the history was rewritten once (the owner's decision): the personal author and committer e-mail was
  replaced with the GitHub noreply address in all 210 commits; the commit hashes quoted in the documents were remapped
  (3e73e6f). Old commits may stay reachable on GitHub by a direct hash until GitHub garbage-collects them; the owner
  chose to publish as is. R7 and "Out of scope" corrected after the review (finding 6).
- 2026-11-17 — the independent Codex review of the spec ([CODEX_REVIEW_003_2026-11-17.md](../reviews/CODEX_REVIEW_003_2026-11-17.md),
  verdict REWORK, nine findings, none rejected) landed: a release now fails unless the tagged commit is on `main`
  (`release.yml`, before any secret is read; a dry run may still run on a branch); the attestation command in
  `RELEASING.md` enforces the signer workflow, the source tag and a GitHub-hosted runner; the license page has a fourth
  entry, "Demo texts", with `assets/demo/SOURCES.txt` and its CC BY-SA attribution (R4); `RELEASING.md` says that the
  platform package revision is not pinned and that Android refuses only a lower build number; the "no Cyrillic" test
  covers the whole Cyrillic block; the Ukrainian chapter mark is «озвучено». Finding 5 (the keystore path with the
  Windows user account in two old `AGENTS.md` revisions) is a recorded refusal: the owner decided on 2026-11-17 to
  publish without a second history rewrite (R7).
- 2026-11-17 — seen on the owner's phone: the license page listed the app twice, as "Book AudioReader" (our entry,
  registered with `LicenseRegistry`) and as "audiobook_reader" (the flutter tool puts every package's `LICENSE` into
  the app's NOTICES under the package name, the root package included; `flutter_tools`
  `lib/src/license_collector.dart`). Fixed: the app's own entries moved from `LicenseRegistry` into a `NOTICES` file
  at the repository root, which the tool reads in place of `LICENSE` and whose entries carry their own names; the
  startup registration and the license assets in `pubspec.yaml` are removed. `test/licenses_test.dart` checks the file
  against its sources and the tool-built NOTICES of the test bundle; the NOTICES inside the built fake debug APK has the
  app once (R4, SC-5). The page in the new build is not yet looked at on the phone: the phone locked during the check.
