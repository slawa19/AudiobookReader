# Review of spec 001 — Codex, 2026-11-14

Subject: `docs/specs/001-first-version.md`, a draft (commit `0968fbb`), and a re-check of `docs/ARCHITECTURE.md` version 2
after the previous review. Codex 0.167.0-alpha.4.1, model `gpt-6-astra`, `--sandbox read-only`, 134,581 tokens.
Verdict: **REWORK**.

This file is a record of the review, not a source of truth; the spec, `ARCHITECTURE.md` and the code remain so.

The orchestrator took the decisions on the findings. None was rejected: all 22 findings and all four items of "what is
superfluous" were accepted. The edits were made in the architecture (version 3), the spec, `GEMINI_TTS.md`, `CONCEPT.md`,
`WHERE_WE_ARE.md` and `AGENTS.md`. Of the 18 findings of the previous review, Codex considered six not closed by version 2
(1, 3, 5, 12, 15, 17); their remainder went into findings 2, 3, 4, 7, 8, 9, 10, 18 of this review.

## Raised / verdict / where it landed

"A§N" is a section of `ARCHITECTURE.md` version 3; FR and SC are of spec 001.

| # | Raised | Verdict | Where it landed |
|---|---|---|---|
| 1 | the starting parts are not part of the general reuse rule; a start from the middle of a narrated group is unclear | accepted: one readiness rule for all consumers, only the missing parts are requested; the tail of a group is an independent segment | A§6.1 "Is the segment ready", "Parts of a segment", "Start from a block in the middle of a group"; FR-T4, FR-P3; SC-2, item 1 |
| 2 | while the nearest segment waits for a retry, the second slot pays for the distant ones | accepted | A§6.3; FR-Q1; SC-2, item 2 |
| 3 | a consumer of a new session waits for the request of the old one, and there is nothing to continue it with | accepted: a registry of requests at the queue, the request does not control the player, the consumer itself checks its session | A§6.3, A§6.4; FR-Q1, FR-Q2; SC-2, item 3 |
| 4 | deletion does not wait for network requests, a late response brings the audio back | accepted differently than proposed: the network is not waited for, only disk writes are; a late response — the spend is recorded, the audio is discarded | A§4, A§6.4; FR-Q4, FR-M3, FR-D3; SC-2, item 4; SC-3 |
| 5 | the tone of the fake build gets into the cache of the real one | accepted | A§6.2; FR-T5; SC-2, item 5; "Anti-regression" |
| 6 | handing the position over from narration to the screen is not described | accepted: "Close" on the player panel; with `stopped` the screen first shows the saved position | A§5 "Handing the position to the screen"; FR-P8 |
| 7 | there are no transitions for an error in `preparing`, a target change from `paused`, an error during a pause; the timer and the cause of `stopped` | accepted without new states | A§6.4, A§6.6; FR-P1, FR-P6, FR-V2, FR-D1 |
| 8 | auto-continuation after a call and the service in a pause are not defined | accepted: no auto-continuation; in `paused` the service stays a foreground service | A§6.6, A§10; D9, FR-P2, FR-P9 |
| 9 | the mapping of a segment to several blocks, lengths, an empty speech text | accepted | A§3, A§6.1 (the order of transformations, the list of mappings); FR-T4 |
| 10 | the resolution of EPUB chapter boundaries is incomplete | accepted | A§3, EPUB; FR-B4 |
| 11 | `encryption.xml` gives a false refusal on font obfuscation | accepted | A§3; FR-B2 |
| 12 | the "otherwise text" branch opens a PDF and a foreign ZIP as garbage | accepted | A§3, the order of format detection; FR-B2 |
| 13 | tolerant parsing without a verifiable result; the structural features of EPUB are not named | accepted: exactly three corruptions with samples of exact text; the EPUB features are listed | A§3, A§9; FR-B4, FR-B6, FR-B7 |
| 14 | ≈ 5 s is right only for ≈ 100 characters; a long first sentence; a pause at 2× | accepted | A§6.1 "Parts of a segment", "The starting segment"; `GEMINI_TTS.md`; SC-2 |
| 15 | proportional following is not proven | accepted: called approximate | A§5; FR-P4; SC-2 |
| 16 | the voice sample and "Download chapter" are outside the queue rules | accepted | A§4 (`samples/`), A§6.3, A§6.7, A§6.8; FR-V1, FR-D2; SC-3 |
| 17 | `usage` is lost in an error; the tariff of the period | accepted | A§6.2, A§6.3; FR-T1, FR-M2 |
| 18 | the dependency graph contradicts the app wiring | accepted | A§2 (the list of allowed direct imports); FR-E5 |
| 19 | the stage boundaries contradict the requirements; "five stages" | accepted | spec: D8, section 2; FR-L1, FR-L2, FR-M3, FR-D3 |
| 20 | FR-T6 forbids a needed client test | accepted | FR-T6; A§9 |
| 21 | acceptance lets defects through, `DEVICE_CHECKLIST.md` does not exist, the comparison with the mock-up is not defined | accepted | spec, section 4: SC-0–SC-3, the table "requirement → how it is checked"; FR-E2, FR-P9; A§9; `AGENTS.md`, "Interface" |
| 22 | the inputs for the executor contradict the decisions | accepted | `AGENTS.md`, "Stack and runtime", "Money"; `WHERE_WE_ARE.md`; `CONCEPT.md`, sections 8 and 10; `GEMINI_TTS.md`, "Rules for working with the paid API"; A§11; FR-E6 |

From the "what is superfluous" list:

- "page N of M in the chapter" — removed: A§5, A§10; FR-R5; "Out of scope";
- a mandatory pause between segments — removed: it is added only after checking the joins by ear and never between parts
  of one block; A§6.6; "Out of scope";
- auto-continuation after a call — removed (finding 8);
- the promise about any wrongly declared encoding — removed (finding 13); "Out of scope".

Minor remarks from the answer:

- "shorter than ≈ 70 characters is slower than it sounds" — clarified: one request, speed 1×; at 2× ≈ 194 characters for
  one request and ≈ 66 for two, a calculation by the model (`GEMINI_TTS.md`, A§1);
- backup — `allowBackup="false"` and data extraction rules that exclude everything (A§4);
- changing the speed makes no requests (FR-P5, A§6.6);
- the font steps, the typeface and the combination "narrow screen + large system font" — from `docs/mockup/NOTES.md`
  (FR-R6, FR-R8);
- the sample phrase is one constant (A§6.8); the "Download chapter" estimate is by unique missing fingerprints (A§6.7,
  FR-D2);
- SC-0: a second build over the first without data loss; a permanent signing key is a precondition (FR-E2).

Decided while making the edits, without a separate orchestrator decision:

- A§2: `screens` also imports `audio` (only the occupied space), `tts` (voices, tariffs) and `book` (model types);
  deleting a book and clearing narration is done by `NarrationController`;
- A§3: the recognized unsupported containers — any ZIP except EPUB and FB2, and PDF by the `%PDF` signature;
- A§3: the rule for an unclosed tag; an unknown entity stays as written; any other XML error is a refusal;
- A§3: a fragment on an empty anchor — the next block; an element not found — the start of the document; an encrypted
  image is not shown;
- A§6.1: blocks that are not read aloud, and blocks with an empty speech text, do not interrupt a group;
- A§6.2: the `applicationId` suffix of the fake build is `.fake`;
- A§4: "Clear narration" deletes `samples/` too; if an affected book is being listened to — `idle`;
- A§6.4, A§6.6: "back" and "forward" from `paused` obey the same intent-keeping rule as a chapter change; a target change
  from `preparing`, `playing`, `waiting` leads to `preparing` (or straight to `playing` if the audio is ready); "until
  the end of the chapter" — the end of the chapter that is sounding;
- A§5: while listening, choosing a chapter in the table of contents is a chapter change (a new session), the slider only
  pages the screen;
- A§6.3, A§6.7: the "Download chapter" task does not depend on the session, covers all segments of the current chapter, is
  not stopped by a listening pause, and is stopped by a permanent error;
- A§6.8: a transient sample error is retried while the voice choice screen is open;
- A§11: the column "Stage of spec 001"; the mobile network is measured from the work computer through the phone's hotspot;
- FR-P9: the check of a pause with the screen off — after 10 minutes; FR-V2: the book's voice outranks the app's voice.

## Codex's answer

*Translated from the Russian original.*

The check was carried out on the current files in full, including the studio's reference code. The numbers below were
obtained by recomputing the published data. Behavior on the phone remains a subject of future checking.

## Findings

Frequency is a qualitative estimate of the scenario. Confidence refers to the existence of a gap in the documents.

| # | Where | Defect, scenario and consequences | Frequency and basis | Confidence | Minimal change of text |
|---|---|---|---|---|---|
| **1** | `ARCHITECTURE.md`, A§6.1, lines 191–195. FR-T4, FR-P3, FR-D2. [Place](../ARCHITECTURE.md) | **The starting parts are not included in the general reuse contract.** A segment was narrated in two parts. Later the queue gets to it during continuous reading or chapter downloading. Checking parts is prescribed only "for the start place", so a new paid request for the whole segment is allowed. For a start from the middle of a group it is also unknown which parts to check. If the whole group is already ready, the priority of the whole file may start reading earlier than the chosen block. | An ordinary scenario of returning and downloading after listening. The frequency is an assumption, the contradiction follows from the text. | High | Define a single way to obtain ready audio for all consumers, including a partially ready pair. Request only the missing part. Separately choose the behavior of a start inside an already narrated group and reconcile it with FR-P3. |
| **2** | A§6.3, lines 219–232. FR-Q1. [Place](../ARCHITECTURE.md) | **The priority of the nearest segment does not limit paying for the distant ones.** The nearest request waits for a retry, the second slot sequentially narrates further segments. The continuous reserve stays zero, the condition "less than 120 s" stays true. The queue may pay for a large remainder of the book while the user hears nothing. | With long errors of one request and successful neighbors. An assumption about frequency, a logical result of the given conditions. | High | Limit advancing beyond the first gap. The simplest rule — while waiting for a retry of the nearest segment, do not start new distant requests, finish the ones already started. |
| **3** | A§6.3–6.4, lines 227–245. FR-Q1, FR-Q2. [Place](../ARCHITECTURE.md) | **Waiting for a shared request conflicts with the ban on using an old result.** The request belongs to session A. The user leaves and returns, session C waits for the same fingerprint. The response of A is allowed only to be saved. The event that must continue C is not defined. An eternal wait or a violation of the ban on an old session changing the new player is possible. | Occasionally on returns during synthesis. The basis is directly allowed actions. | High | Separate the ownership of the request from the relevance of the consumer. After the file is published, the current waiting consumer re-checks its session and continues. The old callback does not control the player directly. |
| **4** | A§4, lines 131–132, A§6.4–6.5, lines 244–261. FR-L5, FR-M3, FR-D3. [Deletion](../ARCHITECTURE.md), [late response](../ARCHITECTURE.md) | **Deletion waits for writes but skips still-running network requests.** There are no writes at the moment, the folder is deleted, then a paid response arrives. It must be saved. The result is a restored folder, returned narration or endless attempts to write to a deleted place. | Occasionally on clearing during audio preparation. A fact about the order of operations from the documents. | High | Before deletion forbid new work and wait for all requests already started, their accounting and saving, then delete. The alternative requires an explicitly written rule of discarding the audio after deletion. |
| **5** | FR-T5, lines 110–111, SC-2, lines 170–172, A§6.2, lines 204–207. [Spec](../specs/001-first-version.md) | **The fake build may contaminate the real cache.** On the phone the tone is saved with the same text, profile and format. After the ordinary build is installed over the fake one, the file has a matching fingerprint. A tone sounds instead of the book, there is no repeat request, the formal cache check passes. | With the intended switch from the fake build to the real one keeping the data. An assumption about the build, isolation is not specified. | High | The fake build gets a separate `applicationId` and a separate storage. Fix this in FR-T5 and SC-2. |
| **6** | A§5, lines 159–169, A§6.6, lines 295–306. FR-R7, FR-P3. [Place](../ARCHITECTURE.md) | **The position owner is defined, the handing over of ownership is not.** After a pause the user reads several pages with their eyes, but the saving is still owned by the narration controller. The available action "stop listening and continue reading" is not described. On a permanent error the controller saves the first un-narrated segment and goes to `stopped`, after which the screen may write its earlier viewed page over it. | An ordinary mixed reading and listening scenario. The frequency is an assumption, the ownership rules are explicit. | High | Name the available action of ending listening and the order of handing the position to the screen. On the transition to `stopped` first synchronize the screen with the saved position, or keep it saved until the next explicit move by the user. |
| **7** | A§6.4, lines 239–247, A§6.6, lines 277–307. FR-P1, FR-P6, FR-V2, FR-D1. [Table](../ARCHITECTURE.md) | **The table does not set the result of a number of ordinary events.** There is no explicit transition for a first transient error in `preparing`, a chapter/voice change from `paused`, a late permanent error after a pause. The timer is tied to the session number, but carrying over its deadline after a voice change is not described. `stopped` merges the end of the book and an error, while FR-P6 requires an error text. | Preparation occurs at every cold start, the other scenarios are occasional. The basis is the missing transitions. | High | Add these events, keeping the existing states. State keeping the intent to play on a target change, carrying over the timer deadline and a separate cause of `stopped`. The normal end of the book gets its own caption. |
| **8** | FR-P2, lines 123–125, A§6.6, lines 283, 300–302. [Spec](../specs/001-first-version.md), [architecture](../ARCHITECTURE.md) | **Auto-continuation after a call and the foreground policy of a pause are underdefined.** The user sets a manual pause during a call, and its end starts the audio again. Besides, `audio_session` reports the interruption type, without the promised "call" flag. "The notification stays" does not define the foreground state. | Depends on interruptions. I know it from the package documentation, the concrete behavior of the device requires checking. [audio_session](https://pub.dev/packages/audio_session), [audio_service](https://pub.dev/packages/audio_service) | High | For the first version remove the mandatory auto-continuation after a call, or define it through the available events and the previous intent to play. A manual pause always cancels auto-continuation. Choose `androidStopForegroundOnPause` explicitly and check resuming with the screen off. |
| **9** | A§3, lines 72–80, A§6.1, lines 175–195. FR-B1, FR-T4, FR-P4. [Model](../ARCHITECTURE.md), [splitting](../ARCHITECTURE.md) | **The reverse mapping is set for one block, and a segment now contains several.** After removing `noteRef`, stress marks and inserting line feeds, one index of the request text cannot be interpreted as an offset of a single `Block.text`. It is also not defined by which string `L/Lmin` are counted, whether separators are included in the length and what to do with an empty `speechText`. The error affects splitting, highlighting and the position. | With merged blocks and footnotes. The scenario is provided for by the architecture. | High | Set the order of transformations and a list of mappings of request text ranges to the source block ranges. Count the request lengths after speech preparation, together with the separators. Skip an empty speech text. |
| **10** | A§3, lines 82–93. FR-B4, FR-R4. [Place](../ARCHITECTURE.md) | **The EPUB linearity is described by an invariant, but the boundary resolution is incomplete.** A link leads to a `<section id>` containing several blocks, or the parent and child table-of-contents entries lead to the same start. The resulting boundary, title and level are not defined. For a link without a fragment the start of the document must also be named explicitly. Different implementations will give different chapters and timer boundaries. | Depends on the EPUB. How common it is in the library is unknown. The admissibility of nested XHTML structures follows from the standard. [EPUB 3.3](https://www.w3.org/TR/epub-33/) | High | State the resolution of a relative path, the binding of a container element to the first child block, the start of the document for a link without a fragment and the rule of merging coinciding boundaries. For FB2 the described traversal with the intro is sufficient. |
| **11** | A§3, lines 95–98. FR-B2. [Place](../ARCHITECTURE.md) | **The presence of `encryption.xml` allows a wrong refusal of an ordinary EPUB.** This file is also used for the obfuscation of embedded fonts. The app uses its own font, but may show a DRM message and refuse to read open text. | For an EPUB with obfuscated fonts. The frequency is unknown, the basis is the standard. [EPUB, encryption.xml](https://www.w3.org/TR/epub-33/#sec-container-metainf-encryption.xml) | High | Check the entries and algorithms inside the file. Ignore unused obfuscated fonts. Tie the refusal to protected resources that the book needs. |
| **12** | A§3, lines 95–97. FR-B2, FR-B5. [Place](../ARCHITECTURE.md) | **The "otherwise text" branch contradicts the refusal of an unknown format.** A PDF, MOBI or a foreign ZIP gets into TXT decoding and may open as garbage. After that the garbage is allowed to be sent to paid narration. | When an unsupported file is chosen. The frequency is an assumption, the conflict is direct. | High | Before TXT exclude the recognized unsupported containers and binary formats. Write down the criterion for accepting content as TXT and the expected refusal for the other data. |
| **13** | FR-B3–B7, lines 58–72, A§3, lines 100–102. [Place](../specs/001-first-version.md) | **The tolerant parsing has no verifiable recovery result.** "What could be parsed" allows losing almost the whole book and passing FR-B7. A broken link creates a conflict with the mandatory existence of every footnote. For EPUB the phrase "the same kinds of blocks" does not define the structural recognition of a footnote, a caption and a table of contents that must not be read aloud. | For dirty files and different EPUBs. The frequency is unknown, the risk of dirty files is named in the concept. | High | For the declared corruptions give small samples with exact expected text. Keep an unresolved link as plain text without `noteRef`. List the supported structural features of the EPUB elements to exclude. |
| **14** | A§6.1, lines 186–195, `GEMINI_TTS.md`, lines 158–161. FR-T4. [Architecture](../ARCHITECTURE.md), [latency model](../GEMINI_TTS.md) | **The wait of about 5 s has been extended from one short sentence to an arbitrary one.** The first sentence may take almost the whole segment. For a short first part and a long remainder at 2× a pause right after the speech begins is possible. The lower group threshold also does not guarantee a minimum length of all requests. | A conditional forecast, the arithmetic is given below. The real frequency depends on the texts and the network. | High | Call 5 s a forecast for about 100 characters. Define the start for a long sentence and an empty remainder. In SC-2 include the starting pair at 2× and either explicitly accept the admissibility of a pause or change the start rule per the check result. |
| **15** | A§5, lines 162–165. FR-P4. [Place](../ARCHITECTURE.md) | **A proportional estimate does not prove timely page turning.** Numbers, abbreviations and a long pause take a disproportionate number of seconds. On a small screen the page will leave earlier or later than the spoken place. A fake tone with a proportional duration hides this defect. | Depends on speech and layout. This is an assumption about quality, there are no measurements in the files. | High for the absence of proof | Replace "this is enough" with an explicitly approximate following. In acceptance check several pages of real audio with a large font. Leave exact following outside the promise of version 1. |
| **16** | A§6.3, lines 229–232, A§6.7, lines 311–312. FR-V1, FR-D2. [Download](../ARCHITECTURE.md), [sample](../specs/001-first-version.md) | **The voice sample and downloading are not built into the rules of the shared queue.** During a download the user is not listening, while retries are allowed "while the user is listening". The result is not chosen for the command "Download" during playback, a sample during preparation, a manual "Stop" followed by leaving and returning. The place of storing samples without an open book is not named. | Occasionally, all the actions are part of the first version. The basis is incomplete contracts. | High | Define the mutual exclusion of these operations, the shared request limit and spend accounting. Retries depend on the active task. A manual stop forbids auto-continuation on return. Name the directory of the sample cache. |
| **17** | A§6.2–6.3, lines 204–205, 235. FR-M2. For reference `tts.py`, lines 244–264. [Contract](../ARCHITECTURE.md), studio client: AudiobookStudio `src/audiobook_studio/tts.py` | **Accounting of any received response is not expressed by the client interface.** If a response contains `usage` but the audio is incomplete or unusable, the client throws an error before returning the tokens. The controller will not be able to carry out the spend recording rule. In the studio exactly this order of checks is used. | On erroneous responses with `usage`. The possibility and frequency of such responses are not measured here. | High for the interface gap | Pass the available `usage` also with a response processing error and account for it once. For monthly totals apply explicitly the tariff of the corresponding period. |
| **18** | A§2, lines 30–56, A§8, lines 335–338. FR-E5. [Graph](../ARCHITECTURE.md) | **The test of allowed imports will forbid the prescribed app wiring.** `app` creates `Library`, `NarrationController` and the platform implementations, but the graph allows it only `screens`. `platform` implements the interfaces of `audio/library`, there are no arrows. The splitter in `tts` receives the book's blocks, there is no `tts → book` dependency either. | At the first implementation of FR-E5. A direct mismatch of the graph with the duties. | High | Supplement the graph with the actual allowed dependencies, including the composition root `app`, and define the direct imports. Only after that write the architecture test. |
| **19** | Section 2 and FR-L1, FR-L2, FR-M3, lines 28–35, 76–81, 145–146. [Stages](../specs/001-first-version.md), [storage](../specs/001-first-version.md) | **The stage boundaries contradict the requirements.** FR-L1 includes A§4 in full already at stage 1, together with spend, the key and stopping narration. FR-L2 already accepts TXT, whose parsing is deferred. Clearing all narration is in stage 2, the table assigns clearing to stage 3. The executor is forced to cut the stage requirements itself. | Mandatory when planning the implementation. A fact from the text. | High | List the storage items applicable to stage 1. Move the TXT intake together with its parsing. Assign the clearing stage unambiguously. Correct "five stages" to four. |
| **20** | FR-T6, lines 112–113, A§9, lines 346, 353. [Place](../specs/001-first-version.md) | **The ban is worded through creating a client with a non-empty key.** Contract tests of the real client with a fake HTTP usually use a non-empty dummy string, including to check key scrubbing. A literal FR-T6 forbids a needed test, while the absence of a real key does not by itself block the network. | When writing the client tests. A direct conflict of wordings. | High | Forbid a real network transport in tests. Allow the real client class with a dummy key and a fake HTTP. |
| **21** | SC-1–SC-3, lines 163–175, A§9, lines 346–357. [Acceptance](../specs/001-first-version.md) | **Acceptance lets significant defects through and contains undefined checks.** The parsing invariants pass after text loss. SC-2 checks the repetition of a chapter from the same start but skips #1–5. The reference to `DEVICE_CHECKLIST.md` now leads to a missing file. A match of screenshots with FigCraft has no established way of comparison. | At every acceptance. A fact by the criteria and the file set. | High | Add the expected content of the samples, scenarios #1–5 and an explicit mapping of FRs to checks. Assign the creation of the checklist before SC-2. For the mock-up define a manual approval and subsequent golden tests, or another concrete way of comparison. |
| **22** | `AGENTS.md`, lines 45–49, `WHERE_WE_ARE.md`, the section "Environment", spec §6, line 193, concept §8, lines 159–162. [AGENTS](../../AGENTS.md), [call limit](../specs/001-first-version.md), [measurement stage](../CONCEPT.md) | **The inputs for the new executor contradict the accepted decisions.** AGENTS still forbids code until Flutter is chosen. WHERE_WE_ARE speaks of the absence of latency measurements. The spec allows paid calls only in SC-2, the concept requires a measurement before the player mock-up, A§11 leaves separate paid checks. The executor will get several incompatible constraints. | At the start of a separate agent. A fact from the files. | High | Record the accepted Flutter decision, separate the completed computer measurement from the future phone one and choose one place for the remaining agreed measurements. |

## Recomputation of A§6.1

The document's model was used

\[
t(n)=3.3+0.016n,\qquad d(n)=0.066n.
\]

`t` is the request time, `d` is the audio duration. This is an approximation from three ordinary Flash requests. The
other three requests are of Flash-Lite and of the streaming mode. [Source data, lines 144–158](../GEMINI_TTS.md)

| Length | Request by the model | Audio by the model | Ratio `d/t` | Listening at 2× |
|---:|---:|---:|---:|---:|
| 100 characters | 4.90 s | 6.60 s | 1.35 | 3.30 s |
| 200 characters | 6.50 s | 13.20 s | 2.03 | 6.60 s |
| 600 characters | 12.90 s | 39.60 s | 3.07 | 19.80 s |

- **"At 200 characters twice as fast as the audio" is arithmetically correct within the model.** At 2× one request has only
  0.10 s of margin for such a segment. Encoding, the network and retries are not part of this computation.
- **"At 600 a request takes about 13 s" is correct as a forecast.**
- **"The starting sentence about 5 s" is correct only for a length of about 100 characters.** The file measures 99
  characters, 4.9 s of request and 7.3 s of audio. The length of an arbitrary first sentence is not limited by this
  measurement.
- **Two requests can ensure steady playback at 2×** if `2d/t ≥ 2` holds. By the model the boundary lies at about 66
  characters. For one request at 2× — about 194 characters. This is a forecast of ideal performance, without limits and
  retries.
- **Steady throughput does not remove the pause at the start.** For notional parts of 100 + 500 characters launched
  simultaneously, the first is ready in 4.9 s and at 2× ends 8.2 s after the requests began. The remainder is ready in
  11.3 s. The forecast gap is **3.1 s**.
- **`Lmin=200` sets the merging condition, it does not ensure a lower bound for each request.** A separate heading, the
  remainder of a group and the starting part may be shorter.

The check of these forecasts is first the controllable delays of the fake synthesis, then an agreed short run on the phone
at 1× and 2× taking the encoding time into account. The wording in `GEMINI_TTS.md` about the impossibility of catching up
with any lines shorter than about 70 characters also requires stating the number of parallel requests and the player
speed.

## Verifiability of each FR

"Yes" means that significant expected results can be formulated from the documents. This does not mean that the
corresponding check is already included in the SC.

| Requirements | Assessment |
|---|---|
| **FR-E1, FR-E2, FR-E3, FR-E4** | **Yes.** For SC-0 the advance transfer of the permanent signing key must be named. Versions are chosen at the installation stage, then fixed. The contradiction of the current AGENTS is #22. |
| **FR-E5** | **No**, until the graph is fixed — #18. |
| **FR-B1** | **Partly**, the reverse mapping of merged segments — #9. |
| **FR-B2** | **No**, a conflict of the TXT definition and a wrong DRM flag — #11–12. |
| **FR-B3** | **Partly.** An ordinary linear FB2 is defined. Corruptions and unresolved links require an expected result — #13. |
| **FR-B4** | **Partly**, the EPUB boundaries and the rules for extracting special elements — #10, #13. |
| **FR-B5** | **Yes** for an accepted TXT. Separately fix the format detection — #12. |
| **FR-B6** | **No**, "could be parsed" does not set the expected content — #13. |
| **FR-B7** | **Yes**, all the listed invariants are verifiable. They do not establish the completeness and correctness of the extracted text. |
| **FR-L1** | **Partly**, deletion and the stage scope — #4, #19. |
| **FR-L2** | **Yes** for the import, the separate isolate and the "Adding" state. The TXT stage needs correcting — #19. |
| **FR-L3, FR-L4, FR-L6** | **Yes.** The duplicate, the shelf order and the clearing of `tmp/` have a defined result. |
| **FR-L5** | **Partly**, deletion with an unfinished request — #4. |
| **FR-R1, FR-R2** | **Yes.** Chunking is checked by the order of events, gestures — by transitions between pages and chapters. |
| **FR-R3** | **Yes** after the mock-up is approved. The correctness of footnotes depends on #13. |
| **FR-R4** | **Partly**, the expected EPUB table of contents depends on #10. |
| **FR-R5** | **Yes**, by the character position and its falling into the open page. |
| **FR-R6** | **Partly.** The theme behavior and saving the setting are defined. The typeface, the size steps and the default value should be fixed in the mock-up. |
| **FR-R7** | **Partly**, handing the position between reading and narration — #6. Recovery after re-parsing has a described approximate fallback. |
| **FR-R8** | **Partly.** Before the test the width and the system font scale must be fixed in the mock-up matrix. |
| **FR-T1** | **Partly.** The form of requests and the classification of HTTP errors are verifiable. Passing `usage` with an erroneous response — #17. |
| **FR-T2, FR-T3** | **Yes.** A dummy key, the fingerprint and a change of each profile field give direct tests. |
| **FR-T4** | **No** for the full contract — #1, #9, #14. |
| **FR-T5** | **Partly**, the fake behavior is defined, isolation of the saved data — #5. |
| **FR-T6** | **No** in the current wording — #20. |
| **FR-Q1** | **Partly**, the limit on distant requests and the shared consumer — #2–3. |
| **FR-Q2** | **Partly**, a new consumer of an old request and deletion — #3–4. |
| **FR-Q3** | **Yes** for atomic publication and a retry of the local write with the same PCM. |
| **FR-P1** | **No** for the full table of events — #7. |
| **FR-P2** | **Partly**, the source of the interruption, a manual pause and the foreground policy — #8. |
| **FR-P3** | **Partly**, a start from a ready group and the end of listening — #1, #6. |
| **FR-P4** | **Partly**, the mapping of several blocks and the promise of timeliness — #9, #15. |
| **FR-P5** | **Yes.** The set of speeds and saving are given. Add a check that no requests are made when the speed changes. |
| **FR-P6** | **No** for all cases of absent audio — #7. |
| **FR-P7** | **Yes.** The branches of an absent key, 402 and 404 are checked with a fake transport. |
| **FR-V1** | **Partly**, the queue and the storage of the sample — #16. The sample phrase must be fixed as one constant. |
| **FR-V2** | **Partly**, a voice change from a pause and other states — #7. |
| **FR-V3, FR-M1** | **Yes**, by the tariff table and a fake date. |
| **FR-M2** | **Partly**, accounting of erroneous responses and the historical tariff — #17. |
| **FR-M3** | **Partly**, clearing on request and the stage — #4, #19. |
| **FR-D1** | **Partly**, carrying the timer between sessions — #7. The counting of minutes during a pause and waiting for the network must also be named. |
| **FR-D2** | **No** for the full behavior — #1, #16. The estimate should be counted by unique missing fingerprints so that identical text is not estimated several times. |
| **FR-D3** | **Partly**, deletion with an unfinished request — #4. |

## What acceptance lets through

| Criterion | A defect that may pass | What to clarify |
|---|---|---|
| **SC-0** | Updating the APK requires uninstalling the app and losing the library, although the first installation is successful. | Install a second local build over the first and check that the data is kept. Name providing the signing key as a precondition of a clean environment. |
| **SC-1** | The parser lost text but produced consecutive indices, a consistent `totalChars` and non-overlapping chapters. Or it wrongly shows the EPUB order that did not occur in the three books. | Check the exact expected blocks, text, footnotes and chapters on structural samples. Leave the invariants as an additional check. |
| **SC-2** | A repeat is paid for after a change of the start place, a download or a partially ready starting pair. An old response brings back deleted audio. A fake tone stays in the real cache. | Add scenarios #1–5. For reuse check several ways of entering the same text. |
| **SC-2** | At 2× a pause appears right after the starting sentence, proportional page turning takes the page away. One chapter at standard speed does not reveal this. | Check the starting pair at 2× and following on several pages with a large font. |
| **SC-3** | The timers 15/30/60 minutes are broken, a manual stop of downloading is cancelled by returning to the app, clearing is restored by a late response. | Add tests with a fake clock, a manual stop and an unfinished request. |

The following requirements have no **explicit sufficient criterion** in SC-0…SC-3, even taking the general reference to
A§9 into account:

- **FR-L3–L5** — the duplicate, the shelf order, deletion and its confirmation.
- **FR-R4–R5, FR-R7–R8** — the table of contents, the slider, re-parsing, rotation, the given combination of a narrow
  screen and a large font.
- **FR-P5, FR-P7** — saving the speed, no synthesis when it changes, the user branches no key/402/404.
- **FR-V1–V3** — a repeated sample, the priority of the book's voice, switching the model and the tariff captions.
- **FR-M1–M3** — the tariff boundary, the previous month and clearing all narration.
- **FR-D1–D3** — the time modes of the timer, the price estimate and stopping the download, deleting a book's narration.

At present it is impossible to execute unambiguously the check "the `DEVICE_CHECKLIST.md` list is passed", since the file is
absent. For "the screenshots match the mock-up" the reference, the render parameters and the comparison rule are absent.
These are future mandatory inputs of acceptance, they need to be given a place in the plan.
[SC-1–SC-2](../specs/001-first-version.md)

## Stages

**The reader can technically be finished without stage 2.** The book model, `speechText`, parsing, position storage and
the screen are self-contained. `speechText` is appropriate already at stage 1, since it fixes the link between the source
text and the narrated representation.

The formal acceptance of stage 1 requires correcting the references that include later duties.

- FR-L1 must list the storage of the book and the position of stage 1, and assign spend, the key and coordination with
  narration to stage 2.
- The TXT intake through an external intent must appear together with the TXT parsing.
- FR-M3 needs to be reconciled with stage 3, or the stage table corrected.
- The measurements on which the starting strategy depends must get an unambiguous stage. Now the concept, A§11 and the ban
  on paid calls outside SC-2 diverge.

## Re-check of the 18 previous findings

The numbering corresponds to the saved review. [Original list](CODEX_REVIEW_ARCH_2026-11-14.md)

1. **Not closed** — the session is introduced, but a new consumer of an old request, deletion and incomplete transitions
   remain. Findings #3–4, #7.
2. **Closed** — for an identical fingerprint one request and a shared concurrency limit are set explicitly. A§6.3, lines
   225–228.
3. **Not closed** — continuity and the final boundary are defined, advancing beyond a gap is not limited. #2.
4. **Closed** — a deterministic merging of short blocks is introduced. The stability of the start at 2× requires a separate
   check, #14.
5. **Not closed** — `preparing`, `waiting` and the end of the list are clarified, the foreground policy of `paused` stayed
   undefined. #8.
6. **Closed** — the single position owner and the continuation after a pause are set. A separate gap of handing over
   ownership remained, #6.
7. **Closed** — a temporary file, publication by rename and a retry of the write with the same PCM are described. A§6.5,
   lines 258–261.
8. **Closed** — adding has an atomic publication point, re-parsing keeps the previous result until the replacement. A§4,
   lines 122–125.
9. **Closed** — a sequential writer applies changes to the current state, the last position change is saved. A§4, lines
   126–130.
10. **Closed** for the original cloud backup problem — `allowBackup=false` extends to the whole app. The phrase about
    "empty rules" should be clarified at implementation, empty rules by themselves do not exclude transferring data
    between devices. [Android Auto Backup](https://developer.android.com/identity/data/autobackup)
11. **Closed** — chunked layout with yielding control, cancellation and a separate decoding of the model is described.
    A§4–5, lines 138–153.
12. **Not fully closed** — speech cleaning and UTF-16 are defined, the mapping of a merged segment to several blocks is
    absent. #9.
13. **Closed** — for a long block a sentence, a space, a safe hard boundary and mandatory progress are provided. A§6.1,
    lines 179–181.
14. **Closed** in the accepted minimal scope — a text anchor, the nearest match and an approximate fallback are recorded.
    A§4, lines 142–146.
15. **Not fully closed** — FB2 and the linearity invariants are clarified, part of the EPUB boundary resolution is left to
    the executor. #10.
16. **Closed** as the absence of a paging mechanism inside a file — such a mechanism appeared. The claim of sufficiency of
    its accuracy requires weakening and checking, #15.
17. **Not closed** — the `playback → library` dependency is added, the full graph still contradicts the dependency wiring.
    #18.
18. **Closed** — the scope of a possible move to streaming is described correctly, the refusal is fixed. A§10, lines
    369–372.

## What is superfluous

- **Mandatory auto-continuation specifically after a call.** The concept requires a pause. The new duty adds
  distinguishing interruption sources and a risk of starting against a manual pause. For the first version manual
  continuation is sufficient. [FR-P2](../specs/001-first-version.md), [concept](../CONCEPT.md)
- **A mandatory artificial pause between all segments.** A segment boundary may fall inside a sentence because of `L`. An
  additional pause then spoils the speech. It is enough to check the joins and add a pause only when a necessity is
  confirmed. [A§6.6, line 271](../ARCHITECTURE.md)
- **"Page N of M in the chapter".** This is an additional duty of background recounting that is not among the necessary
  functions of the concept. The share of the book and the table of contents are already provided.
  [A§5, lines 155–156](../ARCHITECTURE.md)
- **The promise to recover any file with a wrongly declared encoding.** With a plausible wrong decoding the true encoding
  cannot be unambiguously derived from this requirement. The scope should be limited to general rules and concrete
  reproducible corruptions. [FR-B6](../specs/001-first-version.md)

File-based storage, one sequential writer, fake synthesis, chunked layout and the refusal of streaming suit the scope of
the first version.

REWORK

## Prompt

*The prompt was given in Russian; translated here.*

```text
You are in the same environment as the operator: read files by their paths and compute yourself, you have Python. WSL is closed to you. There is no app code yet — project documents are being reviewed. DO NOT INVENT measurements: a number that is not in the files is called a forecast, and you say how to check it. Change nothing in the files.

TASK. An independent review of the spec of the first version before implementation begins, and a re-check of the architecture after the edits made on your previous review. A separate executor agent will work from this spec, who will not have the context of this conversation: everything that is not in the documents he will make up himself.

WHAT TO READ IN FULL:
- docs/specs/001-first-version.md   — the subject of the review
- docs/ARCHITECTURE.md              — version 2, the spec refers to it as "A§N"
- docs/reviews/CODEX_REVIEW_ARCH_2026-11-14.md — your previous review and where each finding landed
- docs/CONCEPT.md
- docs/GEMINI_TTS.md                — including the new section "Latency and synthesis speed" with a measurement
- AGENTS.md
For reference (a working tool of the same owner, project AudiobookStudio):
- src/audiobook_studio/tts.py
- src/audiobook_studio/worker.py

WHAT THE OPERATOR HAS ALREADY MEASURED: only what is in GEMINI_TTS.md, the section "Latency and synthesis speed" (six requests from the work computer). Flutter and the Android SDK are not installed; nothing was run on the phone.

PRINCIPLES: simplicity (an app for one user; the owner asked for "no overengineering, but in best practices" — a superfluous requirement is as much a finding as a missing one); a failing step is designed so as not to fail; paid requests are not repeated and not made in vain; book parsing by general rules; everything that can be, is checked without a phone.

QUESTIONS:
1. Architecture version 2. For each of the 18 previous findings: is it actually closed by the text of version 2, or only named? Check especially the new parts that were not in version 1, for correctness and robustness: A§6.1 (groups of short blocks, a starting segment of two parts and the "is it narrated" check), A§6.4 (the session), A§6.6 (the state table and transitions), A§5 (the proportional estimate of the place inside a segment, the position owner), A§3 (speechText with a reverse mapping of offsets when several blocks are merged into one segment; the linear split into chapters for FB2 and EPUB).
   Check the arithmetic of A§6.1 yourself from the numbers of GEMINI_TTS.md: is it true that at Lmin=200 synthesis is twice as fast as the audio, at L=600 a request takes about 13 s, and the starting sentence about 5 s; what results at a player speed of 2×.
2. The spec. For each requirement FR-*: can a test be written from it and from the architecture section it refers to without asking questions? Where will the executor be forced to make things up? Which requirements contradict each other, the architecture, the concept or GEMINI_TTS.md?
3. Acceptance SC-0…SC-3: which defect will pass acceptance unnoticed? Which requirement is covered by no criterion? Which criterion cannot be checked the way it is written?
4. Stages: can stage 1 (the reader) be finished without what is assigned to stage 2? Is there a requirement put in the wrong stage?
5. What in the spec is superfluous for the first version of an app for one user.

ANSWER FORMAT (in Russian):
A table of findings, from the most important to the least important. For each:
- where: file, requirement identifier or section, line numbers (a finding with no reference to a concrete place does not count);
- what the defect or gap is;
- under what concrete scenario it will show up and how it will end (for the user, for the money or for the executor);
- how often (an estimate) and what it rests on: a fact from the files, knowledge of the platform documentation or an assumption;
- confidence: high / medium / low;
- the minimal change of text.
Separately — a short list for question 1: the number of the previous finding → "closed" or "not closed: why".
Separately — what is superfluous.
An objection with a concrete reference is worth more than agreement. If a section is fine — say so in one line, do not invent findings for volume.

The last line of the answer — the verdict, exactly one of two words in capitals: ACCEPT or REWORK.
```
