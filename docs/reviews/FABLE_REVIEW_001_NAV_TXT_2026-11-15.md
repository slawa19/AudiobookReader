# External review of the "transitions and TXT" batch of spec 001 — Fable 5.2, 2026-11-15

The owner's experiment ([EXPERIMENT_CODEX_IMPL.md](EXPERIMENT_CODEX_IMPL.md)): the code was written by Codex agents,
the external review by a separate Fable 5.2 agent. The review ran on `main` at `df93061`, in a separate worktree; the
batch is the branches `s002-nav` (the stub page, following after commands, "back/forward" by paragraphs, returning to a
seen page) and `s003-txt` (TXT parsing and file intake). The reviewer proved the findings with temporary tests. This
file is not a source of truth: the spec and the code remain so.

Verdict — **REWORK**; there are no blocking defects.

| # | Raised | Confirmed | Orchestrator's decision |
|---|---|---|---|
| 1 | a TXT has an empty book language: the reading style and the probe phrase are English even for a Russian book; the style is part of the audio fingerprint | reading | fix: a book language missing from the file is fixed at add time — the interface language at that moment; books already on the shelf are not touched |
| 2 | "Share" with text and no file: an error, the open book closes, the audio stops | reading; on the phone — forecast | fix: a share without a file is silently ignored |
| 3 | after returning to a computed page the layout may be left without a listener: "page back" leads to the start of the chapter | test (three targets in a row on blocks of 33,000 characters) | fix |
| 4 | the test "an explicit command cancels the earlier paging" passes without the fix | temporary revert | fix the test |
| 5 | "To the reading place" during the animation of manual paging to the same page does not turn following on | test | fix |
| 6 | a tap on the page in the first 320 ms after "forward" on pause: the screen is not at the voice, and there is no "To the reading place" button | test | fix |
| 7 | a TXT title is cut at the last period ("Война и мир. Том 1" → "Война и мир"); an empty title crashes the cover stub | test | fix |
| 8 | in a group of short lines, five "forward" taps produced six paid requests for the same text (≈ 1–3 cents) | test | **rejected**: a jump into the middle of a group allowed by A§6.6; the price is cents |
| 9 | a TXT "paragraph is one line, blank lines only at headings" gives blocks as large as a whole chapter | test | **rejected**: rule FR-B5, we do not build heuristics |
| 10 | HTML, RTF, JSON are accepted as TXT with markup in the text | test | **rejected**: rule 5 of A§3 |
| — | fake controller: "back" before the first sound after a start from the middle of a block leads to the start of the block, the real one — to the previous block | test | **rejected**: the fake one is needed only for the prototype and the screen tests |

Checked with no findings: a shortened page is not chosen as a target; the tests of returning to the same page are not
vacuous; 15 random runs of the screen with 70 actions each on the real controller; the three-second window at speeds
0.75× and 2×; TXT parsing (BOM, cp1251, a lone CR, an empty file), 40 MiB in 0.8–2.0 s on the computer; the TXT title
survives re-parsing.

Separately from the review, the orchestrator found on the phone: returning to a seen page does not work, because the
"To the reading place" button changes the height of the player panel and the layout is recomputed. The fix is in the
same rework.

All accepted findings were fixed on 2026-11-15 (branches `s003-revfix`, `s002-nav3`), each with a test that failed
before the fix.
