# External review of stage 1 of spec 001 — Fable 5.2, 2026-11-15

By the owner's decision of 2026-11-15 (an experiment, [EXPERIMENT_CODEX_IMPL.md](EXPERIMENT_CODEX_IMPL.md)), the stage 1
code was written by Codex agents, and the external review of the batch was done by two separate Fable 5.2 agents — not
Codex, as `AGENTS.md` requires in the usual order. The review ran on `main` at `c0caaa6`, in a separate worktree; the
reviewers were allowed to prove findings with temporary tests. This file is not a source of truth: the spec and the code
remain so.

The brief to both: the code was written by another engine, the orchestrator accepted it from reports and green tests;
find correctness errors against A§2–8 and the stage 1 FRs; each finding with `file:line`, a concrete input, a
"confirmed by test / forecast" mark and a frequency estimate; verdict MERGE or REWORK.

Both verdicts — **REWORK**. No vacuous tests were found in the parsers, one check in the app.

## Reviewer 1: `lib/book`

| # | Raised | Confirmed | Orchestrator's decision |
|---|---|---|---|
| 1 | EPUB: named XHTML entities (`&nbsp;`, `&mdash;`…) stay in the text and go into narration; `<p>&nbsp;</p>` is a readable paragraph | test | fix; A§3 clarified: an unknown entity is one outside the XML and XHTML sets |
| 2 | an unclosed empty element (`br`, `hr`, `empty-line`, `image`) silently loses the rest of the section | test | fix |
| 3 | FB2: a `binary` with invalid base64 rejects the whole book | test | fix: the image is considered absent |
| 4 | FB2: a chapter title made of several `<p>` is glued without a space; a footnote mark in the title | test | fix |
| 5 | EPUB: `mimetype` with a line feed — "format not supported" | test | fix |
| 6 | EPUB: text in `div`/`li`/`td` is split into blocks by inline tags outside a short list | test | fix: only block elements break a block |
| 7 | EPUB: a table-of-contents entry for a document without blocks gives its title to the next chapter | test | fix; A§3 clarified |
| 8 | EPUB: an external link in the table of contents rejects the whole book | test | fix: the entry is skipped |
| 9 | EPUB: a fragment with a non-ASCII identifier is not found | test | fix |
| 10 | FB2: windows-1250, windows-1252, koi8-r — rejected | test | add 1250 and 1252 (the interface is in pl and de); koi8-r — rejected, waits for a real book |
| 11 | XML strictness: an undeclared prefix, a bare `&`, `--` in a comment, a lowercase `doctype`, a blank line before `<?xml`, a control character, an `itemref` without an item | test | **rejected**: per A§3 a new corruption is added as a rule and a sample when it turns up on the owner's book |
| 12a | EPUB: a link without `noteref` to a footnote element — the footnote text is unreachable | test | fix: a link to a footnote element is a `noteRef` |
| 12b | `<br/>` and a space at the start of the next line | test | fix |
| 12c | a document twice in `spine`; quadratic behavior on a one-megabyte paragraph; the whole archive in memory; `body name="comments"`; stanzas | test / estimate | **rejected**: rarity or the letter of the spec; the file size is limited at input (finding 4 of reviewer 2) |

## Reviewer 2: `library`, `platform`, `app`, `reader`

| # | Raised | Confirmed | Orchestrator's decision |
|---|---|---|---|
| 1 | one corrupted book folder or `settings.json` — the app does not start; deleting a book is not symmetric with adding | test | fix all: skip the book, default settings, deletion via `tmp/`, a startup error screen |
| 2 | `singleTop`: "Open with" while the app is alive creates a second Activity and a second library over the same folder | Dart — test; Android — forecast | fix (`singleTask`); check on the phone |
| 3 | one write error poisons the writer: a repeat of the old error, three failure lines and a closed book on every move to the background, a lost change | test | fix |
| 4 | adding: ≈ 22 MB of memory per 1 MB of file, size not limited | test (memory) | fix: adding by path, a size limit |
| 5 | the system "bold font": drawing is wider than the measurement, a line goes under the bottom of the page | widget test; Samsung — forecast | fix in `reader` after the screen is ported |
| 6 | a page boundary inside a word longer than a line: the piece is drawn one line above the computed one | test | fix in `reader` after the screen is ported |
| 7 | an FB2 from "My Files" with an opaque URI will not offer the app | forecast | two MIME types added; the rest is acceptance FR-L2 on the phone, the workaround is "+" |
| 8 | the launch intent is processed on every Activity recreation | forecast | fix; check on the phone |
| 9 | minor: "+" is silent during parsing; the `DISPLAY_NAME` requirement; copies in `cacheDir` are not cleaned; `deletionBytes` has no consumer; a vacuous check of the deletion dialog; deletion without error handling; the position at the very end of a block | test / forecast | fix |
| 9 | a lost file-pick result on Activity recreation; `loadBook` right after `deleteBook`; CRLF in `.env` | forecast / test | **rejected**: rarity, or unreachable from the screen |

What was done for the accepted findings is in the git history (branches `s001-bookfix`, `s001-storefix`, `s001-pages`
and the `reader` fix that followed it) and in the Changelog of spec 001.
