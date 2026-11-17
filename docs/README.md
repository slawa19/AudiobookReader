# Project documents

The index. The source of truth is the code and the git history; a document that has drifted from the code is fixed in
the same commit.

## Where to start

1. [WHERE_WE_ARE.md](WHERE_WE_ARE.md) — what has been done, what is next, the environment.
2. [CONCEPT.md](CONCEPT.md) — what we build and what we do not.
3. [ARCHITECTURE.md](ARCHITECTURE.md) — how it is built.

## What we build

| Document | What it is about |
|---|---|
| [CONCEPT.md](CONCEPT.md) | the idea, the reader, the set of features, "Out of scope" |
| [ARCHITECTURE.md](ARCHITECTURE.md) | modules and their dependencies, the book model, page layout, narration, storage, measurements |
| [specs/001-first-version.md](specs/001-first-version.md) | the first-version spec: decisions, requirements by stage, acceptance criteria, the decision log (Changelog) |
| [specs/002-cleanup-after-reviews.md](specs/002-cleanup-after-reviews.md) | the spec of the rework after the architecture review: defects, repetitions, removing the superfluous |
| [specs/003-open-source.md](specs/003-open-source.md) | the spec of preparing the open-source publication: GPL-3.0, English documentation, the fifth language, the release workflow |
| [GEMINI_TTS.md](GEMINI_TTS.md) | the shape of the Gemini TTS request, voices, rates, latency measurements |
| [GOOGLE_PLAY_PLAN.md](GOOGLE_PLAY_PLAN.md) | plans for later: publication in Google Play and a paid service; not a decision |

## What it looks like

| Document | What it is about |
|---|---|
| [prototype/README.md](prototype/README.md) | the Flutter screen prototype — it sets the look; running, gestures, palette, screenshots |
| [screenshots/](screenshots/) | the README screenshots: the English interface and an English book, taken by `test/readme_screenshots_test.dart` (not the prototype goldens) |
| [mockup/](mockup/) | the static mock-up: a reference for the composition of screens and texts, not a standard of the look |
| [logo.svg](logo.svg) | the app's mark; the same outlines are in the Android icon |

## How we verify

| Document | What it is about |
|---|---|
| [DEVICE_CHECKLIST.md](DEVICE_CHECKLIST.md) | manual phone check: background, lock screen, headset, a call |
| [CODEX_INDEPENDENT_REVIEW.md](CODEX_INDEPENDENT_REVIEW.md) | how to run an independent review |
| [RELEASING.md](RELEASING.md) | public releases: how users verify a signed APK (checksum, attestation, certificate); how the maintainer cuts a release |

## Reviews and checks (`reviews/`)

Records of what was found and what was done about it. They are not a source of truth.

| Record | What was checked |
|---|---|
| [CODEX_REVIEW_ARCH_2026-11-14.md](reviews/CODEX_REVIEW_ARCH_2026-11-14.md) | the architecture |
| [CODEX_REVIEW_SPEC_2026-11-14.md](reviews/CODEX_REVIEW_SPEC_2026-11-14.md) | the first-version spec |
| [CODEX_REVIEW_MOCKUP_2026-11-14.md](reviews/CODEX_REVIEW_MOCKUP_2026-11-14.md) | the static mock-up |
| [CODEX_REVIEW_PROTOTYPE_2026-11-14.md](reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md) | the screen prototype |
| [CODEX_REVIEW_LOGIC_2026-11-14.md](reviews/CODEX_REVIEW_LOGIC_2026-11-14.md) | the prototype's screen logic |
| [JOURNEY_AUDIT_2026-11-14.md](reviews/JOURNEY_AUDIT_2026-11-14.md) | user journeys |
| [GESTURE_AUDIT_2026-11-14.md](reviews/GESTURE_AUDIT_2026-11-14.md) | gestures |
| [FABLE_REVIEW_001_STAGE1_2026-11-15.md](reviews/FABLE_REVIEW_001_STAGE1_2026-11-15.md) | the code of stage 1 "Reader" |
| [FABLE_REVIEW_001_STAGE2_2026-11-15.md](reviews/FABLE_REVIEW_001_STAGE2_2026-11-15.md) | the code of stage 2 "Narration" |
| [FABLE_REVIEW_001_NAV_TXT_2026-11-15.md](reviews/FABLE_REVIEW_001_NAV_TXT_2026-11-15.md) | jumps by paragraph, page return, TXT |
| [READER_SCREEN_REVIEW_2026-11-15.md](reviews/READER_SCREEN_REVIEW_2026-11-15.md) | the reading screen during narration: two independent reviews (Opus 5.5 and gpt-6-astra) |
| [ARCH_REVIEW_2026-11-16.md](reviews/ARCH_REVIEW_2026-11-16.md) | the architecture, separation of responsibility, repetitions, the quality of Codex's code: two independent reviews |
| [EXPERIMENT_CODEX_IMPL.md](reviews/EXPERIMENT_CODEX_IMPL.md) | the experiment log: Codex agents write the code, the orchestrator accepts |

## Naming rules

- A spec is `specs/NNN-<slug>.md`; it holds decisions, requirements, acceptance, "Out of scope", Changelog.
- A review record is `reviews/<WHO>_REVIEW_<what>_<date>.md`.
- The owner's decision is recorded in the spec or the concept on the same day, with the date.
- Documentation, code comments and commit messages are in English (decision of 2026-11-17).
