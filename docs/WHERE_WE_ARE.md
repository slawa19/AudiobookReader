# Where we are

Navigation through the project's state. The source of truth is the code and git history; this file is edited in the
same commit that changes the state. Commit hashes and test counts are not written here: they go stale before anyone
reads them.

## State

The repository was created on 2026-11-14. Spec 001 (the first version) is being implemented.

| Spec 001 stage | Written | Verified on the phone | Accepted by the owner |
|---|---|---|---|
| 0. Environment, build, CI | yes | yes | closed, except the FR-E6 measurement on a mobile network |
| 1. Reader: FB2, FB2.ZIP, EPUB, shelf, reading | yes | yes, on the owner's FB2 books; the set had no real EPUB or FB2.ZIP files | **yes, 2026-11-15 (SC-1)** |
| 2. Narration: Gemini, queue, player, background, spend, key | yes | yes, 2026-11-16 by checklist through adb: player, jumps, page return, background, notification, headset buttons by emulation; screen off, lock screen, real headphones, a phone call — no | **no (SC-2)**; the owner accepted the voice, speed and paragraph joins on 2026-11-15 |
| 3. Polish: TXT, sleep timer, "Download chapter", "Delete narration" | yes | sleep timer, "Download chapter", "Delete narration" — yes, 2026-11-16 on the fake build; TXT on the phone — no (there was no such file on it) | no (SC-3) |

External code review was done for stages 1 and 2, for the "jumps and TXT" batch, for the reading screen and for the
architecture as a whole; the findings have been landed ([reviews/](reviews/)), the rework after the architecture
review is spec 002, merged. The full phone check of 2026-11-16 found two defects — the notification after listening
ended and a truncated voice name; both were fixed and re-verified on the phone. The app has its own icon
([logo.svg](logo.svg)).

Since 2026-11-17 the repository has been prepared for open-source publication under GPL-3.0 (owner decisions of
2026-11-17; [specs/003-open-source.md](specs/003-open-source.md)). Merged into `main`: Ukrainian as the fifth interface
language; documentation, code comments, test names and technical messages in English; the `LICENSE`, the in-app
"Open-source licenses" page and the demo-text attribution; English README screenshots; the tag-triggered release
workflow with the pinned toolchain ([RELEASING.md](RELEASING.md)). The four signing secrets and the variable
`SIGNING_CERT_SHA256` are set in GitHub. The dry run of the release workflow passed on 2026-11-17 (run 44035431681);
its attestation and release steps are skipped in a dry run and have never run. The repository was switched to public and
renamed to `slawa19/BookAudioReader` on 2026-11-17 (owner decisions); the first release is cut from the tag `v0.1.0`. The independent Codex
review of spec 003 (REWORK, nine findings) has been landed
([reviews/CODEX_REVIEW_003_2026-11-17.md](reviews/CODEX_REVIEW_003_2026-11-17.md)); one finding, the keystore path with
the Windows user account in two old commits, stays in the history by the owner's decision (spec 003, R7).

The public name of the app is **Book AudioReader** (owner decision of 2026-11-17): the Android label, the license page,
the web prototype and the README use it. The repository and the release file are named `BookAudioReader`; the Dart package and the
applicationId keep `audiobook_reader`.

Two defects seen on the owner's phone on 2026-11-17 are fixed: the license page listed the app twice (as "Book
AudioReader" and as "audiobook_reader"; the app's entries now live in the root `NOTICES` file), and App info showed
the app's notifications as "Blocked" with a switch that could not be turned on (the app now declares
`POST_NOTIFICATIONS` and asks once, the first time listening starts; the media card worked without it and still does).
On the phone, the fake debug build showed the cause of the second defect (the card works, the switch is disabled); the
fixed builds' permission dialog and license page are not yet looked at on the phone. After the update the real app
asks on its next "Listen".

**What is next, on the phone** — all with the owner, none of it can be verified from a computer:

1. listening with the real voice: speech by ear, "back/forward", page return;
2. the remaining items of [DEVICE_CHECKLIST.md](DEVICE_CHECKLIST.md): screen off and lock screen, headphones, a phone
   call, another app's sound, airplane mode, a large system font;
3. EPUB, FB2.ZIP and TXT books on the phone;
4. the FR-E6 measurement on a mobile network — the computer is connected through the phone's hotspot;
5. acceptance of SC-2 and SC-3, the outcome of the experiment with Codex agents.

**What is next, publication** — the owner's steps, in this order:

1. have the Ukrainian strings (`lib/screens/l10n/app_uk.arb`) read by a native speaker; they were written by an agent;
2. look at Settings → "Open-source licenses" on the phone: the app should be listed once;
3. confirm the rule of spec 003 (Changelog) that technical text, as distinct from interface strings, is in English;
4. switch the GitHub repository to public;
5. cut the first release: bump `version:` in `pubspec.yaml` if needed, push the tag `v0.1.0` (or the bumped version),
   verify the published APK as in [RELEASING.md](RELEASING.md), "For users".

The owner's phone has one build installed — the real one, signed with the permanent key. The build with the fake voice
(`build-apk.sh --fake`) is installed alongside only for the duration of a check. The web prototype: its tests pass; on
2026-11-17 `scripts/prototype.sh start` built it and the server answered HTTP 200, but the page was not opened in a
browser in that check.

The order of work set by the owner on 2026-11-14:

1. architecture → Codex review — done;
2. the first-version spec → Codex review — done, findings incorporated;
3. the screen prototype → review by Codex and the owner. The owner rejected the static FigCraft mock-up
   (`docs/mockup/`) over interface elements; the look is now set by the Flutter prototype
   (`docs/prototype/README.md`), which is started by `scripts/prototype.sh` and opens at http://127.0.0.1:8642/. The
   interface is in Russian, English, Polish and German (Ukrainian was added as the fifth language on 2026-11-17). The
   Codex review of the prototype was done (REWORK, 21 findings), the findings were incorporated; **the prototype was
   accepted by the owner on 2026-11-15** ([specs/001-first-version.md](specs/001-first-version.md), "Decisions");
4. implementation — begun on 2026-11-15 under spec 001; the state by stages is in the table above.

**How the implementation is going (an experiment, the owner's decision of 2026-11-15).** The order differs from
`AGENTS.md`, "Orchestrator and agents": the code is written by Codex agents (`gpt-6.1-sol`, effort high; the requested
`gpt-6.2-sol` is unavailable to the account) without a sandbox — otherwise they cannot see WSL and the tests — each in
its own worktree `D:\Temp\claude\wt-<slug>`; the orchestrator (Claude) sets the tasks, accepts the work and merges;
the external review of a batch is done by Fable 5.2, not Codex. After it finishes the owner assesses the efficiency;
the log of launches is [reviews/EXPERIMENT_CODEX_IMPL.md](reviews/EXPERIMENT_CODEX_IMPL.md). The owner, 2026-11-15:
the orchestrator leads development and testing itself, accepts the agents' work itself, and gives a large batch to a
separate Fable for review.

Documents (the full index is [README.md](README.md)):

- [CONCEPT.md](CONCEPT.md) — the concept; all proposals of section 9 were accepted by the owner on 2026-11-14
  (Flutter; MOBI in the second version; no system voice; books from Studio — later).
- [ARCHITECTURE.md](ARCHITECTURE.md) — the architecture, version 3.
- [specs/001-first-version.md](specs/001-first-version.md) — the first-version spec; being implemented.
- [specs/002-cleanup-after-reviews.md](specs/002-cleanup-after-reviews.md) — the rework after the architecture review
  of 2026-11-16; done and merged on 2026-11-16; verified on the phone with the fake build.
- [specs/003-open-source.md](specs/003-open-source.md) — preparation for open-source publication (2026-11-17).
- [RELEASING.md](RELEASING.md) — signed releases from GitHub Actions: how users verify the APK, how the maintainer cuts
  a release.
- [reviews/](reviews/) — review records: of documents and the prototype (Codex, 2026-11-14), of code by stages, of the
  reading screen and of the architecture (2026-11-15 and 2026-11-16), of the open-source preparation (2026-11-17), the
  experiment log.
- [prototype/README.md](prototype/README.md) — the prototype: running, gestures, palette, languages, screenshots.
- [screenshots/](screenshots/) — the English README screenshots (`test/readme_screenshots_test.dart`).
- [GEMINI_TTS.md](GEMINI_TTS.md) — the request shape, voices and rates verified in AudiobookStudio.
- [GOOGLE_PLAY_PLAN.md](GOOGLE_PLAY_PLAN.md) — plans for later: publication in Google Play and a paid service; not a
  decision.
- [CODEX_INDEPENDENT_REVIEW.md](CODEX_INDEPENDENT_REVIEW.md) — how to run an independent review.
- `AGENTS.md` — the agents' working rules.

## Environment

- Flutter 3.50.0 is installed in WSL Debian (`~/sdk/flutter-3.50.0`, `scripts/setup-wsl.sh`); there is no Flutter in
  Windows. The JDK and Android SDK are there too (`~/sdk`), versions in `scripts/env.sh`; commands in `AGENTS.md`,
  "Stack and runtime". `scripts/build-apk.sh` builds an APK signed with the permanent key (created 2026-11-15, outside
  the repository, parameters in `.env`). `adb` is installed in Windows.
- Stage 0 of spec 001: the environment, build and CI are done, the first CI run is green. The owner's phone was
  connected by USB on 2026-11-15 (SM-S948B, Android 17, API 37; three-button navigation; debugging allowed): the APK
  was installed through `adb`, the second build went over the first. The FR-E6 measurements were done on 2026-11-15
  (short text, simultaneous requests — `GEMINI_TTS.md`), except the measurement on a mobile network: for it the
  computer must be connected through the phone's hotspot.
- FigCraft: `D:\Program Files\ArtCraft\FigCraft\`. Its MCP server is `figcraft-cli.exe mcp`, configured in a local
  `.mcp.json` that is not tracked in the repository; it connects for a session started from the project directory.
  Without MCP the same engine is available as `figcraft-cli.exe run <scenario.json>` and `render`.
- The Gemini latency measurement from a work computer was done on 2026-11-14 ([GEMINI_TTS.md](GEMINI_TTS.md)); from the
  phone and a mobile network — not. The remaining measurements and their stages — [ARCHITECTURE.md](ARCHITECTURE.md),
  section 11; the paid ones only with the owner's consent.
- The Gemini key is in the project's `.env`.

## What not to do

- Do not bring back what was rejected in the concept's "Out of scope" section and in section 10 of the architecture.
