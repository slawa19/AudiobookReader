# Gemini TTS: what has been verified and how to call it

Carried over from AudiobookStudio (`docs/specs/001-gemini-tts.md`, `src/audiobook_studio/tts.py`, `profile.py`),
where everything below was verified with paid calls and reconciled with Google's invoice of 11–12.11.2026. Studio is
a server-side Python tool; here the same request goes out from the phone. What has not yet been measured for the phone
is collected in the last section.

Models, rates and shutdown dates change. Check Google's documentation before relying on them: the verification date
for all numbers here is 2026-11-11.

## Why Gemini

Blind test of one chapter in Russian, 2026-11-11: first place — Gemini 3.8 Flash TTS (voice Aoede with a style),
second — Cartesia Sonic 3.6. Rejected: MiniMax, Fish, Inworld, Qwen3-TTS, ESpeech, CosyVoice 3. The owner likes
ElevenLabs for quality, but it is expensive.

## Models

| ID | Name | Note |
|---|---|---|
| `gemini-3.8-flash-tts` | 3.8 Flash | default: better and faster by ear |
| `gemini-3.8-flash-lite-tts` | 3.8 Flash-Lite | a third cheaper |

Other TTS models are not supported: neither their request shape nor their rates have been verified.
`gemini-2.5-pro-preview-tts` rejects a request with a style ("Speech annotations are not supported").

## Request

`POST {base}/v1beta/interactions`, base `https://generativelanguage.googleapis.com`.
The key goes only in the `x-goog-api-key` header: not in the URL, so it does not end up in logs and error texts.

```json
{
  "model": "gemini-3.8-flash-tts",
  "input": [
    {
      "type": "user_input",
      "content": [
        {
          "type": "text",
          "text": "<paragraph text as is>",
          "annotations": [{"type": "speech_metadata", "style": "<style>"}]
        }
      ]
    }
  ],
  "response_format": {"type": "audio"},
  "generation_config": {"speech_config": [{"voice": "Aoede"}]}
}
```

Rules, each of which cost a mistake:

- **The style goes only in `speech_metadata.style`, never in the text.** The model reads the text verbatim, and an
  instruction inserted into it may be spoken aloud.
- **The stress mark U+0301 is stripped before sending.** Gemini reads homographs correctly from context without the
  mark. With the mark it stresses the word with intonation and obeys the mark, even a wrong one.
- **Speed and pitch are not set numerically** — only in words in the style. Playback speed is changed by the player.
- **The language is detected automatically**; Russian is supported by both models.

Response: in `steps[]` a step with `type: "model_output"`, in its `content[]` an element `type: "audio"` with `data`
(base64) and `mime_type`. The audio is WAV or raw 16-bit mono PCM; the sample rate is taken from the WAV header or from
`rate=` in `mime_type`, otherwise 24,000 Hz. If `status` is present and is not `completed`, the audio is incomplete —
such a take does not count as narrated.

## Limits

- Input — up to 8,192 tokens. Output — up to 16,384 audio tokens, about 655 s of audio; anything longer is silently
  truncated.
- Therefore a paragraph longer than 4,000 characters is split at sentence boundaries, and the audio of the pieces is
  joined into one take.
- Google does not publish rate limits (RPM/TPM) for TTS; the owner sees their own in AI Studio. 24 requests in a row
  produced no 429 errors.

## Errors

| Response | What to do |
|---|---|
| 408, 429, 5xx, timeout, network drop | retry the same request with a delay |
| 402 `payment_required` | do not retry; show the top-up link — always `https://aistudio.google.com/billing`; the address is not taken from Google's text (review of 2026-11-15: punctuation sticks to it, and a documentation URL may come first) |
| 404 on the model | the model has been shut down by Google — offer to choose another |
| other 4xx | do not retry; show Google's text as is |

The owner's billing is prepaid: at a zero balance a 402 "prepayment credits are depleted" arrives.
The key is scrubbed from any text shown.

## Voices

The set is fixed by the documentation and needs no network request. The default is **Aoede**.

Female: Achernar (soft), Aoede (light, easygoing), Autonoe (bright), Callirrhoe (calm), Despina (smooth), Erinome
(clear), Gacrux (mature), Kore (firm), Laomedeia (upbeat), Leda (youthful), Pulcherrima (forward), Sulafat (warm),
Vindemiatrix (gentle), Zephyr (bright).

Male: Achird (friendly), Algenib (gravelly), Algieba (smooth), Alnilam (firm), Charon (businesslike), Enceladus
(breathy), Fenrir (excitable), Iapetus (clear), Orus (firm), Puck (upbeat), Rasalgethi (businesslike), Sadachbia
(lively), Sadaltager (knowledgeable), Schedar (even), Umbriel (easygoing), Zubenelgenubi (casual).

The default style, verified on a popular-science book (Russian, as sent):

> Прочитай как опытная рассказчица научно-популярной аудиокниги: живо, естественно, с выразительной интонацией,
> без лишних пауз внутри фраз

(Gloss: "Read like an experienced narrator of a popular-science audiobook: lively, natural, with expressive
intonation, without extra pauses inside phrases.")

For a reader app the style must suit any book and agree with the voice's gender; this text is a starting point.

## Profile and fingerprint

"The same voice" means a match of the triple **model + voice + style**, not of the voice name alone.

A take's fingerprint is the sha256 of JSON with sorted keys `{text, model, voice_id, style, format}`. The take's file
is named by the fingerprint, so "the file exists" means "the paragraph was narrated exactly this way". This gives free
re-listening and a safe voice change: old takes are not confused with new ones.

## Price

Audio is 25 tokens per second of sound. Rates, $ per 1M tokens:

| Model | Audio output until 31.12.2026 | from 01.01.2027 | Text input until 31.12.2026 | from 01.01.2027 |
|---|---|---|---|---|
| `gemini-3.8-flash-tts` | 9 | 18 | 0.50 | 1.00 |
| `gemini-3.8-flash-lite-tts` | 6 | 12 | 0.50 | 1.00 |

Measured: 1.63–1.73 audio tokens per character of text, i.e. 0.065–0.069 s of audio per character. For estimates the
upper end is used — 0.069 s/char. Studio's formula matched Google's invoice for 11.11 to the cent ($0.262).

From this, ignoring the negligible text input (a calculation from the rate and the measurement, not a separate
measurement):

| | 3.8 Flash now | 3.8 Flash from 2027 | Flash-Lite now | Flash-Lite from 2027 |
|---|---|---|---|---|
| one hour of audio | $0.81 | $1.62 | $0.54 | $1.08 |
| a book of 500k characters (≈ 9.6 h) | ≈ $7.8 | ≈ $15.5 | ≈ $5.2 | ≈ $10.4 |

The actual number of billed tokens is taken from the response's `usage`: audio — from `output_tokens_by_modality` (the
element with `modality: "audio"`), otherwise `total_output_tokens`, otherwise an estimate from the duration. The
counters are not added together.

## Rules for working with the paid API

- Tests do not call Gemini. In tests and during screen development synthesis is fake (a tone instead of a voice).
- A small measurement (a few short requests, cents) is done without asking the owner; the price and the result are
  recorded here. Anything larger — only with the owner's consent and with an estimate named in advance. The full rule
  is in `AGENTS.md`, "Money".
- A whole book is never narrated for the sake of a check.
- Retrying a long paragraph after a transient error pays for the already finished pieces again; this is an accepted
  limitation.

## Latency and synthesis speed

Measurement of 2026-11-14: six requests from a work computer on a wired network, voice Aoede with the default style,
about $0.04. One request per row — an order of magnitude, not statistics.

| Mode | Model | Characters | Request, s | Audio, s | Audio tokens |
|---|---|---|---|---|---|
| regular | 3.8 Flash | 99 | 4.9 | 7.3 | 179 |
| regular | 3.8 Flash | 304 | 8.5 | 20.9 | 518 |
| regular | 3.8 Flash | 813 | 16.1 | 52.2 | 1,300 |
| regular | 3.8 Flash-Lite | 304 | 5.9 | 20.8 | 517 |
| streaming | 3.8 Flash | 304 | 7.8 (first audio — 2.1) | — | — |
| streaming | 3.8 Flash | 813 | 15.5 (first audio — 2.1) | — | — |

What follows from this:

- A **regular request** on Flash takes about 3.3 s + 0.016 s per character, and yields 0.066 s of audio per
  character. Long text is synthesized three times faster than it plays; text shorter than ≈ 70 characters is
  **slower than it plays** if there is a single request and the player runs at 1×. At 2× the threshold for one request
  is ≈ 194 characters, for two simultaneous ones ≈ 66; this is a calculation from the model, not a measurement. A
  dialogue of short lines narrated one at a time cannot be caught up with by the queue.
- **Time to first audio** in regular mode cannot be below ≈ 5 s: that is a request for a sentence of about 100
  characters.
- **Streaming works.** `"stream": true` is added to the request body; the response is `text/event-stream`. Events:
  `interaction.created`, `interaction.status_update`, `step.start`, many `step.delta`, `step.stop`,
  `interaction.completed`. Audio arrives in `step.delta` → `delta.data` (base64) with `delta.mime_type: "audio/l16"` —
  raw PCM with no WAV header. The first piece arrives after 2.1 s regardless of the text length; the whole response
  takes as long as a regular one. In regular mode `mime_type` is `audio/wav`.
- Flash-Lite is faster on the same text (5.9 s versus 8.5 s) — in this one measurement; in Studio, Flash sounded
  faster by ear.
- There were no 429 errors.

### Short text and simultaneous requests

Measurement of 2026-11-15 (FR-E6 of spec 001): eight requests from a work computer on a wired network, 3.8 Flash,
voice Aoede, its own text; 2,126 audio tokens, about $0.02. One request per row — an order of magnitude.

| How | Characters | Request, s | Audio, s | Audio tokens |
|---|---|---|---|---|
| one | 3 ("Да.") | 3.6 | 1.5 | 34 |
| one | 24 | 3.4 | 2.9 | 68 |
| one | 56 | 5.0 | 5.9 | 144 |
| two at once | 297 | 9.1 | 23.9 | 594 |
| two at once | 314 | 9.3 | 23.6 | 586 |
| three at once | 100 | 5.4 | 9.2 | 225 |
| three at once | 111 | 6.4 | 10.2 | 252 |
| three at once | 102 | 5.2 | 9.1 | 223 |

- **The lower bound of a request is about 3.5 s**, however short the text: three characters take 3.6 s to synthesize
  and play for 1.5 s. Text shorter than ≈ 50 characters is synthesized slower than it plays at 1×; this agrees with the
  earlier estimate of "≈ 70 characters" and with merging short blocks into groups (A§6.1).
- **Short text sounds proportional to its length** (1.5 s for "Да."): the model adds no extra duration. Not checked by
  ear.
- **Two and three simultaneous requests do not slow each other down** (9.1–9.3 s versus 8.5 s for a single one at 304
  characters; 5.2–6.4 s versus 4.9 s at 99 characters), there were no 429 errors. The limit of "up to two requests"
  from A§6.3 is confirmed from this side; the measurement did not show where rate limits begin.
- Not measured: the same on a mobile network — needs a computer connected through the phone's hotspot.

## Does the price depend on the number of requests

There is no per-request fee: audio output tokens and text input tokens are billed. From the same six requests:

- **Input** grows strictly with the text length — 24, 75 and 200 tokens for 99, 304 and 813 characters, i.e. ≈ 0.25
  tokens per character with no constant per-request addition. The style does not noticeably count toward the input.
  Input is under 1% of the price.
- **Audio.** Measurement of 2026-11-14 (≈ $0.04): the same text of eight sentences, 3.8 Flash, Aoede.

  | How it was sent | Audio tokens | Audio, s | Request time, s |
  |---|---|---|---|
  | in one request, 813 characters (three runs in a day) | 1,300 / 1,324 / 1,425 | 52.2 / 53.1 / 57.2 | ≈ 16 |
  | in eight requests, one per sentence, 92–109 characters | 1,397 in total | 57.2 in total | 38.3 in total |

  The total of the eight requests lies within the scatter of the single one: the same text in one request varies by
  ≈ 9% from run to run, and eight requests are more expensive than the average by ≈ 3.5%. There is no noticeable fee
  for the number of requests.

The forecast written here before the measurement ("≈ 1.1 s of extra audio per request", up to 16% of the price on
short pieces) was derived from three points on different texts and **was not confirmed**: the difference was explained
by speech tempo, not by the number of requests.

Conclusion: the piece size does not affect the price. It is chosen by speed — a 100-character request takes ≈ 4.8 s
for ≈ 7 s of audio, which is why eight short requests in a row took 38 s against 16 s for one — and by convenience:
the back/forward step, highlighting, the wait after a jump (A§6.1).

A side fact: the audio duration of the same text is not constant (52–57 s), so a price estimate from the character
count is no more accurate than ± 5%.

## Other languages

Voices are not tied to a language: the set of 30 is the same for all, and the model detects the text's language by
itself. Probe of 2026-11-14 (five requests, ≈ $0.02, 3.8 Flash): English text with the voices Aoede and Charon,
German with Aoede, a Russian phrase with English and German insertions with Aoede. All five responses — 200,
`completed`, audio of normal length (0.059–0.068 s per character). A Russian style does not interfere with English
and German text.

Polish, the same day (four requests, ≈ $0.02): a 408-character text with the voice Aoede with the style in Russian and
in Polish, with the voice Charon with the style in Polish, and a Russian phrase with Polish lines. All four — 200,
`completed`; 27.9–28.6 s of audio for 408 characters (≈ 0.069 s per character).

Quality by ear has not been assessed: the files are in `.run/voice-lang/` (outside git), and the owner listens to
them. Until the owner's assessment it is unknown whether a voice has an accent in a foreign language, whether the
reading differs when the style is in the text's language, and how insertions sound.

What in the app depends on the book's language, not on the voice and not on the interface language: the style text and
the voice-probe phrase. They are set by a table keyed by the book's language in the code — `lib/tts/book_language.dart`
(ru, en, pl, de, uk; English for other languages, e.g. `cs`; spec 001, FR-T7). The style there is gender-neutral: the
earlier "Прочитай как опытная рассказчица…" ("Read like an experienced narrator…", feminine form) agreed only with a
female voice. The new wordings have not been checked by ear.

## What has not yet been measured for the phone

Where and at which stage this is measured — [ARCHITECTURE.md](ARCHITECTURE.md), section 11.

1. **The same on a mobile network** — latency and synthesis speed from the phone.
2. ~~Very short text~~ — measured 2026-11-15, section "Short text and simultaneous requests"; not checked by ear.
3. **Storage.** 24 kHz mono PCM is about 170 MB per hour. Studio re-encodes to mp3 through ffmpeg; the phone needs its
   own encoder (AAC or Opus through Android's facilities), and it has to be chosen and verified.
4. ~~Rate limits with two or three simultaneous requests~~ — measured 2026-11-15 in the same place: no 429 errors.
