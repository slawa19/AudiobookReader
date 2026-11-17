# How to call Codex for an independent review

Carried over from DocxAICorrector, where the recipe took shape over several months. After a large piece of work it is
handed to another model: Codex runs on a different engine and sees what the internal loop does not. There it found
real defects in work that had already passed three internal passes.

## 1. Find the binary — anew every time

Codex is installed on the Windows host. The version directory changes with every update, and a `codex.exe` directly in
`bin\` is a separate old build that crashes on the current config. You need the newest of the version subdirectories:

```powershell
$codex = (Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter codex.exe |
          Where-Object { $_.DirectoryName -ne "$env:LOCALAPPDATA\OpenAI\Codex\bin" } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
& $codex --version
```

The model and effort are set in `~/.codex/config.toml`; no model flags are needed.

## 2. Run

The prompt is always a file through stdin, the answer goes to a file, run in the background (5–20 minutes):

```powershell
Get-Content "<prompt.txt>" -Raw | & $codex exec --sandbox read-only - 2>&1 |
  Out-File -FilePath "<answer.txt>" -Encoding utf8
```

`--sandbox read-only` — it will change nothing in the repository, but it can execute commands.

Read the answer from the end and by searching, not in full: Codex repeats the prompt at the start, and the file runs to
thousands of lines. The final report comes after the last line consisting of the single word `codex`. That is why the
prompt requires a verdict on one line from a fixed set, for example `MERGE` / `REWORK`.

## 3. What it can do

| can | cannot |
|---|---|
| read any file by absolute path, including those excluded from git | work in WSL |
| execute commands, including Python | run the project's tests and build if they live in WSL |
| compute from the data itself | — |

Give it absolute paths to the data and ask it to compute. The phrasing "you cannot run anything" turns it into a
generator of hypotheses where it could have given a fact.

## 4. What to write in the prompt

- **The range:** base and head SHA, the commands `git diff <base>..<head> --stat` and
  `git log --oneline <base>..<head>` — let it run them itself.
- **Surfaces — not the diff.** A literal list of absolute paths: every module with a changed fragment in full, its
  callers and callees, its tests. Reviewing the diff alone misses defects that the change created in unchanged lines.
- **What the change does** — in your own words, and the path to the spec.
- **Project rules:** general parsing rules without literals from books; tests do not go to Gemini; the key does not
  end up in logs and error texts; simplicity instead of "just in case" mechanisms.
- **Its capabilities as the first paragraph:** "you are in the same environment: read files by absolute paths and
  compute yourself. WSL is closed to you, you cannot run the project's tests. Do not invent measurements; call a number
  that is not in the files a forecast and say how to verify it".
- **What the operator has already measured and how.**
- **The answer format:** `file:line` for each finding; on what specific input it shows up; the frequency and how it
  was measured, or that it is a forecast; confidence; the verdict on the last line.
- **Ask it to object:** "an objection with a concrete reference is worth more than agreement; if everything is fine,
  say so briefly".

Do not write the words "attack", "break", "find holes": the safety filter triggers and the request is rejected,
having spent context. Write "check correctness", "robustness analysis".

## 5. What to do with the answer

- **Check every finding against the code yourself.** About one in six is weaker than claimed.
- **Re-rank.** It ranks by reasoning, not by frequency: a rare case and a daily one get the same priority.
- **Land every one:** a fix with a test, an entry in the spec's Changelog, or a recorded refusal with the reason in its
  "Out of scope". For a single-user tool a refusal is a normal outcome: findings are sorted, not all fixed.
- The report with the prompt and a table "raised / verdict / what was done" goes to
  `docs/reviews/CODEX_REVIEW_<NNN>_<date>.md`. It is not a source of truth; the spec and the code remain one.

## 6. When

- After a large piece of work, not after every task: all branches merged into the integration one, the full run green,
  `git status --porcelain` empty. Before merging into `main`.
- The best moment is when the decision has been formulated but not yet built: a review of the spec before
  implementation is cheaper than the same remarks after it.

## 7. If Codex is unavailable

There are three honest options: the owner runs the prompt themselves; the work continues without a review, and this is
said aloud in the report; the owner decides to set Codex up differently. An internal second pass is not called an
independent review — all the value is in the different engine.
