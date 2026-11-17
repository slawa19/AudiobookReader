# Two independent reviews of the reader screen during narration — 2026-11-15

Requested by the owner after the fourth remark of one kind in a day ("the text on the page is not what I saw"): he doubted
that the cause had been found. The reviewers — Claude Opus 5.5 (high) and Codex `gpt-6-astra` (high) — worked in
parallel on `main` at `6e8a62b`, each in its own worktree, from one brief, without knowing about each other; they proved
the findings with temporary widget tests on the real controller. This file is not a source of truth.

## Where they agreed

1. The page height depended on the volatile state of the player panel (the "To the reading place" button as a separate
   row, the "Preparing the voice…" row, the bottom system inset); any change of height re-flowed the text and cancelled
   the transition.
2. The transition between pages has no single owner: about 40 mutable fields, seven ways to show a page, four
   cancellation mechanisms; the invariants hold on the order of calls. Each point fix closed one sequence of events.
3. The tests of the latest fixes are not vacuous (both broke the fixes — the tests failed), but they check particular
   scenarios. The tests waited until everything settled and looked at the outcome; the defects live between frames.

## Findings and decisions

| # | Raised | Who | Confirmed | Orchestrator's decision |
|---|---|---|---|---|
| 1 | the first "back" tap is lost: following was turned off before the page changed, the button changed the height, the re-layout erased the request | both | test | fixed |
| 2 | at every audio start the text jumps twice: the status line changes the height by 24 dp | Opus | test | fixed: the panel height is constant |
| 3 | a "back" tap during following shows a page two lines shorter than the one seen | Opus | test | fixed by the same change |
| 4 | the voice reached the open page → the button disappeared → the page changed its boundaries | Opus | an existing test required it | fixed by the same change; the test rewritten |
| 5 | "To the reading place" 16 ms after paging starts does not return; the height is constant meanwhile | Astra | test | fixed |
| 6 | "forward" during an unfinished gesture: following is on, the sounding place is not on screen | Astra | test | fixed |
| 7 | while a near target is awaited, taps are lost, swipes are disabled | Opus | reading | fixed |
| 8 | the first "back" deep in a long chapter waits for a recomputation of the whole start of the chapter (≈ 0.6 s on the computer) | Opus | test | **deferred**: a bounded fix did not work out; measurement on the phone |
| 9 | the bottom system inset changes the page height when panels are shown and hidden | Opus | forecast | fixed in the panel; checked on the phone 2026-11-16: when the system bars are hidden the page does not change |
| 10 | the test helper counted "the page changed" by a change of object | Astra | reading | fixed: comparison of the text boundaries |

## Where they diverged

Astra: there are few point fixes available, the transition control should be reduced to a single operation (3–5 working
days, medium risk). Opus: first a constant height and removal of the code that has grown around it; replacing the
navigation model (400–600 lines, high risk) only if a property test finds new violations after that. Opus's order was
accepted. After the work, the frame-by-frame property test (10 seeds × 40 actions) is green; before it, it failed on 12
seeds on two invariants. The question of replacing the model stays open until checked on the phone.
