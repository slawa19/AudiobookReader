# AGENTS.md

Rules for assistants and automation in this repository. `CLAUDE.md` includes this same file.

## What this is

A book reader for an Android phone: shelf, reading, narration of the text with Google Gemini TTS voices. An app for a
single user (the owner), with no server and no accounts.

Sources of truth, in order of seniority:

1. the code and the git history;
2. [docs/WHERE_WE_ARE.md](docs/WHERE_WE_ARE.md) — what has been done and what is next; read first;
3. [docs/CONCEPT.md](docs/CONCEPT.md) — what we build and what we do not;
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the current spec in `docs/specs/` — how it is built and what is
   required;
5. [docs/GEMINI_TTS.md](docs/GEMINI_TTS.md) — how to call Gemini and what it costs;
6. the screen prototype ([docs/prototype/README.md](docs/prototype/README.md)) — the look of the interface;
7. [docs/RELEASING.md](docs/RELEASING.md) — how a public release is cut and how users verify it.

The index of all documents is [docs/README.md](docs/README.md).

Markdown lags behind the code. If a document and the code disagree, the code is right, and the document is fixed in the
same commit.

## The owner's principles

Carried over from DocxAICorrector and AudiobookStudio, where each was paid for with a mistake.

- **Simplicity.** A basic set of features without excess. Do not add features from the concept's "Out of scope"
  section without the owner's decision. Do not polish edge cases until they have been met on a real book.
- **The interface from the reader's point of view:** the minimum of elements, nothing "just in case", no manual
  settings where the app can decide itself.
- **A failing step is designed so that it does not crash.** A transient network or Gemini error (408, 429, 5xx,
  timeout) is retried by itself. A failure is not closed with notifications and "degraded" branches. An unclear error
  stops narration and shows Google's text as is.
- **General rules, not fitting.** Book parsing works from the shape and structure of the file. There are no literals
  from a specific book, word lists or thresholds tuned to one file in the code. If no general rule can be found, the
  honest answer is "we do not build it", not a fitted rule.
- **Evidence is fresher than the fix.** A conclusion about a defect is drawn from a fresh run or file, not from memory
  and not from an old report.
- **Money.** Tests never call Gemini: synthesis in tests is fake. A small measurement — a few short requests costing
  cents — is done without asking the owner (his decision of 2026-11-14: the question costs more than the measurement);
  afterwards the report names the price and the result. The boundary "up to ≈ $0.10 per measurement" is the
  orchestrator's interpretation; the owner did not name numbers. Anything larger — a chapter, acceptance SC-2 of spec
  001 — only with the owner's consent and with an estimate named in advance. Never narrate a whole book for the sake of
  a check.
- **Keys.** The Gemini key is kept in the app in Android's secure storage, in the working environment — in `.env`. The
  key is not printed, not committed, and does not get into logs, request URLs or error texts.
- **Information about the owner and his books does not go to external services**, except the text of a paragraph sent
  for narration.
- **Language.** Documentation, code comments, test names and commit messages are written in English (the owner's
  decision of 2026-11-17, when the repository was prepared for open-source publication under GPL-3.0; see
  [docs/specs/003-open-source.md](docs/specs/003-open-source.md)). Text that is data stays in its own language:
  strings of the Russian interface, book samples, test fixtures, reading-style prompts.

## Stack and runtime

The workstation specifics below (WSL Debian, `D:\…` paths, `adb` location) are the maintainer's own working setup; the
scripts in `scripts/` also run on plain Linux, which is how CI uses them.

The stack is Flutter, Android: **approved by the owner on 2026-11-14** (the concept, section 9).

The canonical runtime is WSL Debian, directory `/mnt/d/Work/Projects/AudiobookReader` (Windows:
`D:\Work\Projects\AudiobookReader`). Flutter **3.50.0** (stable, Dart 3.14.0) is installed in WSL at
`~/sdk/flutter-3.50.0`; the version and the archive checksum are pinned in `scripts/env.sh`. There is no Flutter in
Windows. Tests, the analyzer and the build are run by the scripts from `scripts/`, not by hand-typed commands. The
commands (from PowerShell; each was run and worked on 2026-11-14):

```
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/setup-wsl.sh
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/test.sh [selector] [options]
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/prototype.sh start|stop|status
```

- `setup-wsl.sh` installs the pinned Flutter, JDK and Android SDK into `~/sdk` and fetches the packages; a repeated run
  uses the ready installation without downloading the SDK again. The scripts also work on ordinary Linux (CI), without
  WSL commands.
- `test.sh` — the analyzer with no findings (infos included) and the tests; the selector and options go to
  `flutter test`. To retake the prototype's screen screenshots:
  `bash scripts/test.sh test/screens_golden_test.dart --update-goldens`; to retake the README screenshots in
  `docs/screenshots/`: `bash scripts/test.sh test/readme_screenshots_test.dart --update-goldens`.
  The scripts run `flutter pub get --enforce-lockfile`: a dependency change starts with `flutter pub get` and a
  committed `pubspec.lock`.
- `prototype.sh start` builds the web version and serves it at http://127.0.0.1:8642/ (it also opens from Windows).
- Android: Temurin JDK **21.0.13+9**, cmdline-tools **22.0** (archive **15859902**), platform **android-36**
  (revision 2), build-tools **36.0.0**, NDK **28.2.13676358**, platform-tools **37.0.3**. Versions and archive sums are
  in `scripts/env.sh`; `flutter doctor -v` confirmed the Android toolchain and the acceptance of all licenses. CMake was
  not needed for the current build. `minSdk=31`, compile/target SDK — 36, from the pinned Flutter.
- `build-apk.sh` with no flags builds a release with the key from `.env` (the four `ANDROID_KEY*` from `.env.example`);
  without the file or the signing parameters it stops. `--debug` uses the debug key and does not read `.env`. The APK
  is in `build/app/outputs/flutter-apk/`.
- `build-apk.sh --fake` turns on `FAKE_TTS=true`, a separate applicationId `.fake` and a separate name;
  `--debug --fake` was verified on 2026-11-15. APK copies: `app-real-<mode>.apk` and `app-fake-<mode>.apk`; without
  `--debug` the same permanent key from `.env` is used.

APK build (both commands were run and worked on 2026-11-15; release — in the main worktree with the permanent key, the
signature verified with `apksigner verify --print-certs`):

```
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/build-apk.sh
wsl.exe -d Debian --cd "D:\Work\Projects\AudiobookReader" -- bash scripts/build-apk.sh --debug
```

- The permanent signing key was created on 2026-11-15; it is kept outside the repository, and its path and parameters
  are in `.env`. Losing the key or the password means reinstalling the app, losing the books and positions; do not
  recreate the key.
- WSL runs as root: Flutter from the archive requires `safe.directory` in WSL's global git — `setup-wsl.sh` sets it
  itself.
- `adb` for the phone is in Windows: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` (installed 2026-11-15). The
  phone disappeared from `adb devices` although Windows saw it as a storage device — "USB debugging" had turned off on
  it: it is turned off by Samsung's "Auto Blocker" (Security and privacy); the owner turned it off on 2026-11-15. The
  phone falls asleep and locks — the screenshot is then black; only the owner can unlock it.
- CI — `.github/workflows/ci.yml`: the same scripts on a clean Ubuntu, the APK with the debug key. Third-party actions
  in both workflows are pinned by commit SHA.

Public release (spec 003, R6): a tag `vX.Y.Z` that matches `version:` in `pubspec.yaml` triggers
`.github/workflows/release.yml`, which runs the tests, builds the APK with the permanent key from GitHub Secrets,
checks its certificate, and publishes the signed APK, `SHA256SUMS` and a build-provenance attestation in GitHub
Releases. Setup, cutting a release, the dry run and recovery are in [docs/RELEASING.md](docs/RELEASING.md). Local
`build-apk.sh` stays for the owner's own phone and for debugging; it is not how public builds are made.

The shell is determined by the first command (`uname`): Git Bash — `MINGW64_NT`, WSL — `Linux …WSL2`. Do not nest
`wsl.exe` inside WSL. Do not use a bare `wsl`: it may be missing from the PATH of Git Bash.

Pitfalls of this workplace:

- `$VAR` at the Git Bash → `wsl.exe` boundary collapses to an empty string even in single quotes. In such commands
  only literal paths and no loops.
- A heredoc in the agent's Bash tool breaks. Multi-line code is written to a file and run from there.
- Windows git in Git Bash has no author name. A commit goes with `GIT_AUTHOR_NAME="Slawa Gorobets"`,
  `GIT_AUTHOR_EMAIL="11042798+slawa19@users.noreply.github.com"` (the owner's GitHub noreply address; owner decision
  2026-11-17: no personal email in commits, the history was rewritten that day) and the same committer values; do not
  change `git config`.

## Verifying work

- **An agent's report is a claim, not proof.** "The tests are green" is confirmed by the output of a command run after
  the last edit.
- **Before "all green" — `git status --porcelain`.** A non-empty output means the local run proves nothing about the
  commit: CI runs on a clean checkout.
- **Incomplete output is a transport problem, not a result.** One cannot say "passed" or "failed" from truncated
  output. Narrow the selector, do not widen the run.
- **One run per tree.** Do not start a second one "to double-check" in parallel.
- **Moving a branch onto a fresh `main` requires a repeated full run.** Neither the diff nor a matching test count
  replaces it.
- **A test must not pass vacuously.** A test for a parsing rule shows both sides: an input where the rule fires, and a
  similar input where it must stay silent.
- **A test waits for an event, not for a number of frames or a pause.** The CI server is several times slower than a
  work computer: a test with a fixed wait is green locally and red there. After pushing to GitHub the CI result is
  checked (`gh run list`), not assumed.
- **What is visible only on the phone is checked on the phone.** Background playback, control from the lock screen,
  the headset, behavior on a call. If there is no device or emulator in the session, say so in the report, rather than
  inferring the result from widget tests.
- Line endings are LF (`.gitattributes`, `.editorconfig`). Check: `git diff --check`.

## Orchestrator and agents

- **The main session manages agents and does not write code.** Spec-level work goes to an agent. The exception is an
  edit for which the setup is costlier than the edit itself.
- **The orchestrator's part:** the setup with already measured facts and paths, merging branches, the full run in the
  main worktree, checking every agent claim against the code, acceptance review.
- **The model by task level.** Mechanics (copying, counting, searching) — Haiku. Bounded engineering work (a screen
  from a mock-up, glue code, scripts) — Sonnet. Format parsers, the player and the narration queue, handling review
  findings — Opus. The orchestrator's model is for the orchestrator only. Between two tiers the cheaper is taken; raise
  it when a report has shown that the task was beyond it.
- **An agent that writes gets its own worktree** outside the repository (`D:\Temp\claude\wt-<slug>`). The built-in
  isolation puts the worktree inside the tree, and git refuses. In a side worktree `git` under WSL does not work:
  `.git` there is a file with a Windows path.
- **Only non-overlapping work runs in parallel.** Split by file ownership, not by topic.
- **Before removing a worktree** copy everything that must outlive it: `git worktree remove --force` erases untracked
  files.

## Specs and acceptance

Spec Kit is not used here.

- A small edit — straight into `main` with a test run.
- Large work (a screen, a format parser, the player) — a short spec `docs/specs/NNN-<slug>.md`: decisions,
  requirements, acceptance criteria, "Out of scope", Changelog. The work goes in its own branch. Before merging — the
  full run green and `git status --porcelain` empty.
- **After large work, before merging into `main`, an independent Codex review** of all the affected modules in full,
  not of the diff. The recipe is [docs/CODEX_INDEPENDENT_REVIEW.md](docs/CODEX_INDEPENDENT_REVIEW.md). The
  orchestrator checks each finding against the code himself: about one in six is weaker than claimed. A finding lands
  as a fix with a test, an entry in the spec's Changelog, or a recorded refusal with the reason. The report goes to
  `docs/reviews/CODEX_REVIEW_<NNN>_<date>.md`.
- An internal second pass is not called an independent review. If Codex is unavailable, this is said in the report.
- The owner's decision is recorded in the spec or the concept on the same day, with the date. A rejected proposal is
  recorded in "Out of scope" — otherwise it comes back.
- A commit subject names the spec number only if the commit is work under it.
- At the end of the work on a spec everything is merged into `main` and pushed to GitHub.

## Interface

- **The look is set by the Flutter prototype** (`docs/prototype/README.md`, http://127.0.0.1:8642/). The owner's
  decision of 2026-11-14: the FigCraft mock-up was rejected over interface elements, its palette and fonts were kept.
  The mock-up in `docs/mockup/` is a reference for the composition of screens, states and texts, not a standard of the
  look. The screens are approved by the owner on the phone, after which their screenshots are recorded as the test
  goldens.
- The interface is in five languages — Russian, English, Polish, German, Ukrainian: four by the owner's decision of
  2026-11-14, Ukrainian added by the owner's decision of 2026-11-17. The strings are in the ARB files
  `lib/screens/l10n/app_<language>.arb` (gen-l10n), not in the screen code; all five files have the same keys (a test
  checks this). Plural forms are ICU plural in ARB, numbers and money are formatted by locale.
- A screen is checked on a narrow phone and with a large system font.
