# Architecture review — Codex, 2026-11-14

Subject: `docs/ARCHITECTURE.md` version 1 (commit `3a02c4f`), before the spec and the code. Codex 0.167.0-alpha.4.1, model
`gpt-6-astra`, `--sandbox read-only`, 142,889 tokens. Verdict: **REWORK**.

This file is a record of the review, not a source of truth; `ARCHITECTURE.md` and the code remain so.

The orchestrator checked every finding against the text of the architecture. None was rejected: all eighteen pointed to
a real gap, and finding 4 was independently confirmed by a latency measurement made the same day (`GEMINI_TTS.md`,
"Latency and synthesis speed").

## Raised / verdict / what was done

| # | Raised | Verdict | Where it landed in version 2 |
|---|---|---|---|
| 1 | a late response or a retry after a pause, chapter change or voice change affects the player and the position; some transitions are missing from the diagram | accepted | decision A8, section 6.4 "Session"; the state table and transitions in 6.6 |
| 2 | two identical paragraphs or a return to a request in flight are paid for twice | accepted | 6.3: one request per fingerprint, a shared count of concurrent requests |
| 3 | the reserve is not defined as continuous; the "until the end of the chapter" timer pays for the next chapter | accepted | 6.3: a continuous reserve, priority of the nearest segment, a final boundary |
| 4 | two requests do not close the lag on short lines; merging can be built from the start of the chapter | accepted, confirmed by measurement: a request shorter than ≈ 70 characters takes longer than it sounds | decision A5, 6.1: groups of short blocks, the split is computed from the start of the chapter |
| 5 | the controller states are not mapped to the media session; a played-out list will be taken for the end of the book | accepted | 6.6: the table "state / media session / service", the rule about a played-out list |
| 6 | the position has two authors when paging during listening | accepted | 5: "the position has one owner", continuing after a pause |
| 7 | an unfinished audio file counts as narrated | accepted | 6.5: a temporary file and a rename; the residual risk is named |
| 8 | a killed book add leaves half a book | accepted | 4: adding via `tmp/` and a single rename; re-parsing likewise |
| 9 | concurrent writes of spend and position lose updates | accepted | decision A3, 4: one sequential writer in `Library` |
| 10 | only the key is excluded from backup | accepted | 4: backup is turned off entirely |
| 11 | splitting a large chapter into pages on the main isolate will delay the interface | accepted | decision A4, 5: in chunks from the current position, `M` later |
| 12 | "text as is" contradicts "footnote references are not read" | accepted | 3: `speechText(block)` with a reverse mapping of offsets; the unit of offsets |
| 13 | splitting by sentences alone does not guarantee the limit | accepted | 6.1, rule 2: sentence → space → hard boundary |
| 14 | `charsBefore` does not restore the position after a parser fix | accepted in a minimal form | 4: the start of the block text as an anchor, `charsBefore` as a fallback |
| 15 | the turning of the FB2 and EPUB structure into chapters is not defined | accepted | 3: "chapters are a linear partition" and rules for FB2 and EPUB |
| 16 | following the voice only on a segment change | accepted differently than proposed: not a limitation but a proportional estimate of the place inside the segment | 5: "following the voice" |
| 17 | there is no `playback → library` dependency; the arrows to `platform` disagree with the text | accepted | 2: the graph and the notes under the table |
| 18 | the amount of rework for a streaming response is understated | accepted; supplemented by a measurement (first audio 2.1 s) | 10: a refusal with a list of what would have to change |

From the "can be removed" list: recomputing pages when only colors change — removed (5); a mandatory `M` before the text
is shown — removed (5); a notification permission request — removed (7). The remark on A2 being worded too strongly —
fixed.

The Android remarks (the service type, the order of starting the service and requesting audio focus) are recorded in 6.6
and 7 as "per the documentation" and moved to the manual phone check.

## Codex's answer

*Translated from the Russian original.*

## Findings

The four mandatory documents and four AudiobookStudio reference files were read in full. The frequency below is a
qualitative estimate of scenarios. Confidence refers to the existence of a gap in the document.

| # | Place in ARCHITECTURE.md | Defect and concrete scenario | How often and the basis of the estimate | Confidence | Minimal change to the document |
|---|---|---|---|---|---|
| 1 | [§6.3–6.5, lines 165–206](../ARCHITECTURE.md) | **It is not defined which operation completions are still valid after a user command.** The user pressed pause during the first request, chose another chapter or voice. The old response or a retry timer may resume playback, append the old segment to the new list or shift the position. The diagram lacks a pause from `preparing` and `waiting`, a restart from `stopped`, and transitions on movement. | Presumably a frequent class of scenarios in everyday control. The gap itself is directly visible in the diagram and the queue rules. | High | Write down the priority of commands and the ownership of asynchronous results by the current session. An old successful response is saved and accounted by its original profile, its influence on the current player and position ends. A pause cancels scheduled retries. For deleting a book and clearing audio, define the order of finishing writes and deletion. |
| 2 | [§6.3, lines 163–164](../ARCHITECTURE.md) | **Checking for a ready file is not enough to rule out double payment.** Two identical paragraphs simultaneously get `has=false`. A similar case is a return to a segment whose first request is still running. Both requests are paid for. | Presumably occasional on returns and repeated lines. The reference code already has a separate fingerprint claim before the request. AudiobookStudio `src/audiobook_studio/worker.py`, lines 374–390 | High | Add the rule "one running request per fingerprint". A second consumer waits for the request already started. The shared concurrency limit applies to old requests that are still finishing after the target changed. |
| 3 | [§6.3, lines 158–170; §6.5, line 197](../ARCHITECTURE.md) | **The continuity and the boundary of the reserve are not defined.** The nearest segment is retried after an error, the distant ones are already ready. Their total duration may reach the target although there is nothing to play further. With the "until the end of the chapter" timer the queue may pay in advance for the next chapter that the player will certainly stop listening to. | The gap shows when responses are reordered and the nearest request fails transiently. Going beyond the chapter happens with such a timer and a short remainder of the chapter. How often the timer is used is an assumption. | High | Define the reserve as audio continuously available from the current position. A retry of the nearest missing segment has priority. Limit advancing beyond a gap and take the final boundary of listening into account when issuing new requests. After a permanent error new requests stop at once, the ready continuous part plays out. |
| 4 | [§6.1, lines 135–137; §10–11](../ARCHITECTURE.md) | **The claim that the reserve and two requests close the lag on short lines is wrong without a performance condition.** If an average line sounds for `d` seconds, a request takes `t`, and the player speed is `v`, then even the ideal throughput of two requests is bounded by `2d/t`. At `2d/t < v` any finite reserve will run out. Constant 429s make the condition worse. | A conditional forecast for dialogues and 2× speed. The basis is queue arithmetic and the allowed speed from CONCEPT §3. The value of `t` itself is still to be substituted from a measurement. | High | Make the rejection of merging short paragraphs conditional on the measurement result. Remove the argument that merging necessarily depends on the start place — the groups can be built deterministically from the start of the chapter. If performance is unsatisfactory, revisit the request unit. In the measurement take into account 2× speed and request rate limits. |
| 5 | [§6.5, lines 189–206; §7](../ARCHITECTURE.md) | **The controller life cycle is not mapped to the media session and player states.** The user turns the screen off before the first response, or the reserve runs out. If waiting is published as a pause or `idle`, the service may lose its foreground state. The end of the current file list may also be wrongly taken as the end of the book. | Waiting for the first response happens on every cold start of narration. **I know from the documentation** — `audio_service` ties startup to `PlaybackState.playing`, and `just_audio` separates `playing` and `processingState`, including `completed`. | High | Define the mapping of `preparing` and `waiting` to the intent to play with a loading state. Exhaustion of the temporary list puts the controller into waiting and allows a later continuation. A user pause removes the intent to play. Define explicitly the foreground policy for pause and resume. [audio_service](https://pub.dev/documentation/audio_service/latest/audio_service/BaseAudioHandler-class.html), [PlaybackState.playing](https://pub.dev/documentation/audio_service/latest/audio_service/PlaybackState/playing.html), [just_audio](https://pub.dev/packages/just_audio) |
| 6 | [§5, lines 118–122; §6.5, lines 195–209](../ARCHITECTURE.md) | **The single position has two potential authors.** During listening the user pages forward. Paging saves the start of the page, a segment change saves the voice's place. The result depends on the order of events. After a pause it is also unclear whether "Listen" continues the segment or starts from the page being viewed. | Presumably an ordinary mixed-reading scenario. Both writes and the manual turning off of following are directly provided for by §5. | High | While listening is active, the saved position is owned by `NarrationController`, the page being viewed stays a temporary state of the screen. Define separately the continuation after a pause and an explicit "Read from here". In a running process a pause keeps the player's temporary position inside the file. After a restart define the allowed return to the start of the segment. |
| 7 | [§6.4, lines 176–185; §4](../ARCHITECTURE.md) | **Atomicity of the audio file is absent from the contract.** The process is killed while encoding M4A — a file with the right fingerprint exists but is unfinished. The next launch counts it as narrated. With a local write error a retry of the whole operation may call paid synthesis again. | Presumably a rare but real class of interruptions on a phone. In the studio atomic audio publication is already implemented. AudiobookStudio `src/audiobook_studio/worker.py`, lines 428–437 | High | Extend `tmp → codec finish → rename` to audio. `has` confirms the published result. While the process is alive, a retry of the local save uses the PCM already received. Describe the residual risk of losing a paid response when the process dies, which the studio has already accepted. AudiobookStudio `docs/ARCHITECTURE.md`, §2 |
| 8 | [§4, lines 87–108; §7, lines 223–224](../ARCHITECTURE.md) | **Adding a book has no completion point.** The process died after creating the folder, copying part of the source or writing `meta.json`, but before `book.json`. Adding again under the same `bookId` may open an unfinished book. A similar risk arises when re-parsing over the previous result. | Presumably rare. The basis is multi-file import and the duplicate check by identifier. | High | Publish the import only after full copying and a successful parse, for example by renaming a prepared temporary folder. The shelf and the duplicate check count only completed books. When re-parsing, publish the new result after successful preparation, keeping the previous one until then. |
| 9 | [§4, line 100; §5, line 119; §6.3, line 172](../ARCHITECTURE.md) | **An atomic JSON replacement does not rule out lost updates.** Two responses simultaneously add spend to the same previous value — the last file loses the first payment. A position write may overwrite a simultaneously changed book voice. The limit of one write per second also does not define saving the last deferred change. | Potentially regular with two requests. The race is assumed for independent asynchronous reads and writes that the document allows. | High | Assign a single sequential writer of state and spend in `Library`. Changes are applied to the current state. Fix saving the last deferred change and writing the position on pause. The spend of a received response is accounted regardless of the further success of encoding and playback. |
| 10 | [§4, lines 102–103; §7, lines 226–228](../ARCHITECTURE.md) | **Only the key is excluded from backup.** With standard Auto Backup the internal folder with books and state may be sent to Google Drive. This contradicts the ban in AGENTS.md on passing information about books on. | **I know from the documentation** — internal files and settings are part of the standard Auto Backup set. Actual triggering depends on phone settings and backup conditions. [Android Auto Backup](https://developer.android.com/identity/data/autobackup) | High | Extend the exclusion from cloud backup to books, images, audio, positions and spend. Specify the configuration for the supported Android versions. [AGENTS.md, line 41](../../AGENTS.md) |
| 11 | [§5, lines 112–116; §8, line 240](../ARCHITECTURE.md) | **A chapter is used as a bound on the amount of synchronous layout, although its size is not bounded.** A chapter of hundreds of thousands of characters, or a TXT without chapters, will require a full measurement before `M` is obtained. The main isolate will delay the interface, pause handling and queue refills. A separate isolate is provided only for import. | A conditional forecast for long chapters. **I know from the Flutter documentation** — UI work is tied to the main isolate and cannot be arbitrarily moved to an ordinary isolate. The duration of the delay requires profiling. [Flutter isolates](https://docs.flutter.dev/perf/isolates) | High | Allow showing the current pages before the computation of the whole chapter finishes. Compute in chunks that yield control and cancel a stale computation after the parameters change. The exact `M` appears on completion. For `book.json` provide separately for decoding off the main isolate. |
| 12 | [§3, lines 65–70; §6.1–6.2](../ARCHITECTURE.md) | **The requirements on speech text contradict each other.** Narration takes the block string "as is", but a footnote reference stays a range inside this string and must not be read aloud. As a result footnote numbers will reach Gemini. If they are removed, the segment offsets will no longer automatically match the offsets of the screen text. | With every textual footnote reference in such a representation. The frequency of footnotes depends on the book. The basis is a direct contradiction within §3 and the requirement of CONCEPT §3. | High | Define a single preparation of speech text that excludes `noteRef`, the order of splitting and of computing the fingerprint. A segment must keep its binding to the source ranges of the block. Fix the units of `offset`, `Span.start/end` and `charsBefore` so that text transformations keep the position correct. |
| 13 | [§6.1, lines 128–133](../ARCHITECTURE.md) | **Splitting only by sentences does not ensure the limit `L`.** A single sentence longer than `L`, text without punctuation or a long sequence without spaces leave the algorithm with no allowed boundary. Exceeding the limit, a hung splitter or skipped text are possible. | Presumably occasional, especially at the initial `L=600`. In the studio this case is already closed by a general rule. AudiobookStudio `src/audiobook_studio/tts.py`, lines 89–108 | High | Add the sequence of boundaries — sentence, then space, then a safe character boundary. The split must keep all the text and always make progress. This is a transfer of an existing studio rule. |
| 14 | [§4, lines 105–108; §5](../ARCHITECTURE.md) | **`charsBefore` does not guarantee recovery after a parser fix.** The new parse excluded a table of contents or footnotes that had earlier been wrongly included in the main flow. Everything after the removed text shifted, and the old character count points past the place that was read. | On parser updates that change the text before the saved position. Presumably rare, the consequences are deterministic for such a change. | High | Save a text anchor of the current block and the offset. On re-parsing look for an exact match, with several matches use proximity to the old position. Leave `charsBefore` as an explicitly approximate fallback recovery method. |
| 15 | [§3, lines 55–75](../ARCHITECTURE.md) | **The turning of the book structure into chapters is not defined enough.** A nested FB2 part may contain a title and an epigraph before child sections. An EPUB may have several chapters inside one XHTML and a table of contents with fragment links. Without a rule for the current chapter, intro text may be skipped, overlapping ranges read twice, and the "until the end of the chapter" timer made ambiguous. | The possibility is confirmed by the format structures. How common it is in the owner's library is unknown. [FB2 schema](https://github.com/gribuser/fb2/blob/master/FictionBook.xsd), [EPUB 3.3](https://www.w3.org/TR/epub-33/) | Medium | Add the invariants of a linear traversal — every main block is read once, the intro is covered, the current chapter under nesting is determined unambiguously. For EPUB specify the order by `spine`, the resolution of `path#fragment` links and the scope of footnote identifiers per document. The flat block model is suitable. |
| 16 | [§5, lines 120–122; §6.5, lines 189–190](../ARCHITECTURE.md) | **Following the voice is defined only on a segment change.** On a narrow screen with a large font one segment occupies several pages. While the file plays, there are no events to move to the next page. The user stops seeing the text being spoken. | A conditional forecast for large fonts and long segments. The gap follows from the single stated page update event. | High | Honestly limit the first version to a jump to the page of the segment start and reconcile this with the promise of automatic page turning in CONCEPT §2. Include checking large fonts in the choice of `L`. If exact following inside the file is required, admit the need for a time binding of the text and a separate change of the decision. |
| 17 | [§2, lines 26–48; §6.5, line 199](../ARCHITECTURE.md) | **The dependency graph does not allow the declared duties to be carried out.** `NarrationController` manages the position and spend that `Library` owns, but there is no dependency between them. Moving the saving into the screen will break work with the screen off. The arrow to `platform` also disagrees with the statement that interfaces belong to the calling modules. | It will show up at the first implementation of background saving. The basis is the duties of the modules and the forbidden reverse dependencies. | High | Add an explicit `playback → library` dependency or pass the save operations in. Clarify that `platform` implements the interfaces of the corresponding modules and `app` wires the implementations together. Screens receive the already saved state. |
| 18 | [§10, lines 268–269; §6.4–6.5](../ARCHITECTURE.md) | **The amount of rework on moving to a streaming response is understated.** For streaming to shorten the wait for the first audio, playback must start before the full file is ready. The current contracts return a whole PCM and put only ready files in the list. Plain streaming reception with the previous wait for the full result will not give this effect. | A conditional scenario if the latency is unacceptable. The basis is the current interfaces of the document. **I know from the documentation** — the `just_audio` dynamic source has a separate contract. [StreamAudioSource](https://pub.dev/documentation/just_audio/latest/just_audio/StreamAudioSource-class.html) | High | Keep the deferred decision about streaming. State that it may affect the player source, the boundaries of playable parts, the queue, readiness accounting and recovery after a drop. Remove the promise to limit the rework to the client and the storage. |

### Clarifications on Android and consistency of the documents

- **I know from the Android documentation.** For target SDK 34+ the `mediaPlayback` type and the
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission are needed together with the base service permission. For target SDK 35+
  an audio focus request requires a top app or an already running foreground service. In §7 the order of starting the
  service and obtaining focus should be fixed. On Android 15 the ban on starting `mediaPlayback` from `BOOT_COMPLETED`
  concerns the corresponding way of starting, which the architecture does not currently provide for.
  [Starting a service](https://developer.android.com/develop/background-work/services/fgs/launch),
  [service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
  [audio focus](https://developer.android.com/media/optimize/audio-focus)
- **I know from the Android 13+ documentation.** Starting a foreground service does not require the `POST_NOTIFICATIONS`
  permission, and media session notifications have an exception. The permission request in §7 can be removed if all the
  app's notifications belong to the media session.
  [Notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- **§6.2 is mostly consistent with GEMINI_TTS.md.** The reference to the client rules should be taken as including 404
  handling, a check of response completeness, scrubbing the key from errors and obtaining the sample rate from the
  response. These rules are already described in the source. [GEMINI_TTS.md, lines 61–82](../GEMINI_TTS.md)
- **File storage, the fake synthesis interface and the checking strategy of §9 suit the first version.** Scenarios of
  races, write interruptions and response reordering are checked with fake dependencies without a phone.
- **A single `book.json` can stay.** The claim of A2 that opening is independent of size is too strong — reading and
  decoding the full model depends on its volume. The sufficiency of the chosen storage is determined by the opening time
  and the memory peak. [§1, A2](../ARCHITECTURE.md)

## What can be removed without loss

- Recomputing pages when only the theme colors change. It is needed when the text geometry changes.
  [§5, line 116](../ARCHITECTURE.md)
- The mandatory obtaining of the exact number of pages of a chapter before the text is shown. The concept requires
  page-by-page reading and saving the position. The computation of `M` may finish later.
  [§5, lines 112–115](../ARCHITECTURE.md)
- The notification permission request, provided exclusively the media session notification is used, as stated above.

## What needs a measurement or a phone

- **Synthesis throughput on short lines and at 2×.** Check the steady rate of producing ready audio, taking into account
  encoding, retries and limits. If throughput is insufficient, the request unit changes. Increasing the reserve only
  postpones the stop. The planned 120 seconds of audio at 2× give 60 seconds of playback — this is a calculation from the
  document's parameters.
- **The first wait and returning from a pause with the screen off.** First a fake response with a controllable delay,
  then a check on the owner's phone. Also check a call during the wait, a manual pause during a call and the later
  arrival of a response. A failure will require changing the media session management, the foreground state or the
  platform adapter.
- **Appending to the list and the joints of compressed segments.** Check appending before and after `completed`,
  replacing the list on a chapter change, transitions between parts of one paragraph. Support for changing the list I
  know from the `just_audio` documentation. The absence of audible defects of a specific codec remains an assumption
  until checked. With defects, the encoding, the handling of encoder delay/padding or the format will have to change.
  [just_audio](https://pub.dev/packages/just_audio),
  [MediaFormat](https://developer.android.com/reference/android/media/MediaFormat#KEY_ENCODER_DELAY)
- **A large chapter and a full `book.json`.** On synthetic text check the time to the first page, responsiveness during
  recomputation and memory. Logical checks are available without a phone, the final time budget is determined on the
  device. An unsatisfactory result will require chunked layout, and with a confirmed memory problem — a revision of model
  loading.

There are no results of phone runs in this review.

REWORK

## Prompt

*The prompt was given in Russian; translated here.*

```text
You are in the same environment as the operator: read files by their paths and compute yourself, you have Python. WSL is closed to you. The app code does not exist yet — a design document is being reviewed. DO NOT INVENT measurements: a number that is not in the files is called a forecast, and you say how to check it. Change nothing in the files.

TASK. An independent review of the architecture of a new app before the spec and the code are written. The app is a book reader for Android (Flutter) for a single user, which reads text aloud through paid Google Gemini TTS.

WHAT TO READ IN FULL:
- docs/ARCHITECTURE.md   — the subject of the review
- docs/CONCEPT.md        — what we build and what we do not (the owner's decisions are made, section 9)
- docs/GEMINI_TTS.md     — verified facts about Gemini TTS and the tariffs
- AGENTS.md              — the owner's principles
For reference, this is a working server tool of the same owner, from which the Gemini client and the idea of the fingerprint were carried over (project AudiobookStudio):
- src/audiobook_studio/tts.py
- src/audiobook_studio/profile.py
- src/audiobook_studio/worker.py
- docs/ARCHITECTURE.md

WHAT IS ALREADY KNOWN TO THE OPERATOR:
- There are no measurements for the phone (section 11 of the architecture): request latency, synthesis speed relative to audio duration, the codec. The [measurement] marks in the document are forecasts, this is stated directly. You need not report that they are unmeasured; you need to say which architecture decision will fall apart at a bad measurement value and what will then have to be redone.
- Flutter and the Android SDK are not yet installed; the package names (just_audio, audio_service, audio_session, flutter_secure_storage) are candidates.

PRINCIPLES TO CHECK AGAINST:
1. Simplicity: this is an app for one user. The owner directly asked for "no overengineering, but in best practices". An extra mechanism is as much a finding as a missing one. Do not propose a database, a state framework, DI, code generation, a second narration engine, synchronization, unless you show a concrete scenario where the first version breaks without them.
2. A failing step is designed so as not to fail (retries), and is not closed with notifications.
3. Money: every request to Gemini is paid (tariffs in GEMINI_TTS.md). The architecture must not pay twice for the same thing and must not pay for what is not being listened to.
4. Book parsing — by general rules over the file structure, with no fitting to a specific book.
5. Everything that can be, is checked without a phone.

WHAT TO LOOK AT FIRST (check correctness and robustness):
a) Section 6 (narration): the segment as a unit, the fingerprint, a queue with a reserve in seconds, up to two parallel requests, pause, retries, voice change, the NarrationController states. Are there states or transitions that are not described and in which the app will hang, pay twice or lose the position? Races between the queue, the player and user actions (rewind back/forward, "read from here", chapter change during synthesis).
b) Android: a foreground service and a media session while waiting for the first response; the Android 13–15 restrictions on starting and on service types; how just_audio works with a list that is appended to on the fly; joints of compressed files. Mark statements about the behavior of specific Android versions and packages as "I know from the documentation" or "assumption", and say how to check.
c) Section 5 (reading): splitting a chapter into pages on the main isolate — what happens on a chapter of hundreds of thousands of characters; the position {block, offset, charsBefore} and recovery after re-parsing; following the voice.
d) Sections 3–4 (model and storage): what the model lacks for FB2 and EPUB from real libraries; a single book.json per book; writing state.json; what happens with a killed process in the middle of adding a book or writing audio.
e) Section 2: module boundaries — is there a dependency that will turn out in fact to be reversed.
f) What in the document contradicts CONCEPT.md or GEMINI_TTS.md.
g) Section 10 ("deliberately not"): which of the refusals is wrong — with a concrete scenario.

ANSWER FORMAT (in Russian):
A table of findings, from the most important to the least important. For each:
- where: file and section number or lines (a finding with no reference to a concrete place of the document does not count);
- what the defect or gap is;
- under what concrete scenario it will show up and how it will end for the user or for the money;
- how often (estimate) and what the estimate rests on: a fact from the files, knowledge of the platform documentation or an assumption;
- confidence: high / medium / low;
- what you propose — a minimal change to the document, not a new mechanism.
As a separate short list: what in the architecture is superfluous and can be thrown out without loss.
As a separate short list: what cannot be decided from the document and must be checked by measurement or on a phone.
An objection with a concrete reference is worth more than agreement. If a section is fine — say so in one line, do not invent findings for volume.

The last line of the answer — the verdict, exactly one of two words in capitals: ACCEPT or REWORK.
```
