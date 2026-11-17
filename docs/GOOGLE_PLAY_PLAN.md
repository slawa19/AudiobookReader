# Google Play and a paid service: plans for later

Written on 2026-11-15 in response to the owner's question: whether it is realistic to put the app in Google Play and
what to rework for it; it may become a paid service — with the purchase of narration tokens or a subscription.

**Status: not a decision and not a work plan.** The first version is still built for a single user
([CONCEPT.md](CONCEPT.md)). We return to this document when the owner says the time has come. (Since 2026-11-17 the
repository is open source and signed APKs are published on GitHub Releases; Google Play stays out of scope —
[specs/003-open-source.md](specs/003-open-source.md).)

**Where the information comes from.** The Google Play requirements below were written from the assistant's memory,
without checking against the current rules. The numbers (fee, number of testers, timelines, commissions) and the
wording of policies must be checked against the Play Console help before any decision — that is the first item on the
to-do list.

## 1. Short answer

Putting it in Google Play is realistic. Moderation is not the main barrier: it is a reader of the user's own files,
without its own content, ads or accounts. The main question is not "will it pass" but **who pays Google for the
narration**:

- **A. The user's key** (as now). The person gets a Gemini key themselves, turns on billing and pastes it into the
  settings. The app hardly changes. The audience is narrow: a stranger from the store will most likely not go through
  this path.
- **B. A paid service.** Narration goes through the owner's server with the owner's key; the user buys minutes or a
  subscription. This is a different product: a server, accounts, payments, support, responsibility for other people's
  money and data.

The options can be passed in turn: first A as a free app "for those who know how", then B.

## 2. What is needed in both options

### In the app

| What | Why | Scope |
|---|---|---|
| AAB build and Play App Signing | the store accepts AAB and signs it itself; the current permanent key becomes the upload key | an edit to `scripts/build-apk.sh` |
| Name, icon, splash screen | the name is "Book AudioReader" (the owner's decision of 2026-11-17); the app has its own icon | the splash screen and the store graphics |
| Privacy policy | the app sends the book's text to Gemini; a public page is needed | the text and hosting of the page |
| The "Data safety" form | what is collected, where it goes, whether it is encrypted, whether it can be deleted | a questionnaire in the console |
| Foreground service declaration | background playback is a service of the "media playback" type; the store asks to explain the purpose, usually with a video | a questionnaire + a short video |
| Age rating questionnaire | mandatory | a questionnaire |
| Store listing | description, screenshots in the five interface languages | texts + screenshots (the tests' golden screenshots are a starting point) |
| Check on other people's phones | so far verified on one Samsung, Android 17, `minSdk 31`; narrow screens, other vendor skins, gesture navigation | closed testing |
| Crash reports | in the first version's "Out of scope"; without them other people's crashes cannot be seen | a revision of the decision |
| Generative AI rules | the store has requirements for apps with AI content (for example, the ability to report a result); whether they apply to narrating someone else's text is unknown | find out from the current rules |

### Outside the app

- A developer account: a one-time fee and identity verification.
- For new personal accounts — closed testing with a group of testers for the set period before publication. This
  condition determines the timeline; check it first.
- A legal entity or an individual: affects taxes, payouts and what buyers see in the store.

### What is already in order

A recent target Android version; of permissions — only the internet and the playback service; data backup is turned
off; one network address; the key in secure storage; books do not leave the phone, except the text sent for narration.

## 3. Option A: the user's key

In addition to section 2:

- **The entry to narration for a newcomer.** A step-by-step explanation of where to get a key and what it costs;
  validating the key on entry; plain words for Google's refusals (some already exist: 402, 404, a wrong key).
- **Reading without narration** must be complete: a person without a key gets an ordinary reader.
- **A price estimate before pressing** — how much a chapter and a book will cost (partly there: "Download chapter").
- Check the Gemini API terms: whether an app where the end user enters their own key is permitted, and the service's
  age restrictions.

The price of the option: weeks, not months; no server needed; no narration costs for the owner.

## 4. Option B: a paid service

Here the architecture changes. Now the app calls Gemini directly and keeps the key on the phone; in a paid service the
owner's key cannot be on the phone — it would go to the first person who takes the app apart.

### What will have to be built

1. **An intermediary server.** Accepts the piece's text and the voice profile, calls Gemini with the owner's key,
   returns the audio. Checks that the request came from a paying user; counts the spend; limits the rate.
2. **Accounts or their replacement.** The balance has to be tied to something: an account (sign-in with Google) or a
   store purchase without registration. Whether the balance survives a change of phone depends on this.
3. **Payments.** For digital services inside the app the store requires its own payment system and takes a commission.
   Needed: products in the console, server-side purchase verification, purchase restoration, refunds.
4. **Accounting and abuse protection.** Per-user limits, protection against reuse of a purchase, against fraud, and
   against use of the server by other people's apps.
5. **An audio cache on the server — or not.** The same text with the same voice need not be narrated twice for
   different people; this saves money but means storing the texts and audio of other people's books on the server — a
   different level of responsibility for data and for copyright.
6. **Support and operations.** Server monitoring, alerts, answering users, refunds, updates when Google's rates and
   models change.
7. **Legal.** A user agreement, a privacy policy for a service that processes book texts; personal data requirements
   in the countries where the app is sold; sales taxes.
8. **In the app.** A purchase and balance screen; sign-in; working offline and with an empty balance; the choice "own
   key or service" — whether to keep both paths.

### Economics — calculate before starting

Known as of 2026-11-15 ([GEMINI_TTS.md](GEMINI_TTS.md)): an hour of audio on 3.8 Flash costs the owner $0.81, from
01.01.2027 — $1.62; a book of 500 thousand characters (≈ 9.6 hours) — ≈ $7.8 now and ≈ $15.5 from 2027; Flash-Lite is
a third cheaper. On top — the store's commission, taxes, the server, refunds.

Hence the questions, without answers to which the payment model cannot be chosen:

- Is a person ready to pay more for narrating one book than a ready-made audiobook costs?
- An "unlimited" subscription at a price of about a dollar per hour is unprofitable on an active listener; so the
  subscription has to include a limited number of hours — then how is it better than a package of minutes?
- What will happen to prices and users' balances when Google changes the rate (a doubling from 2027 has already been
  announced)?
- Is another narration model or another provider not cheaper at the same quality?

## 5. Questions to settle

First about the product, then about the technology.

1. **Who it is for.** For the owner and people like them, or for a wide audience? Everything else depends on the
   answer.
2. **A, B, or A then B.**
3. **Packages of minutes, a subscription, or both.** What happens to the unused balance.
4. **In which countries it is sold.** Affects taxes, legal texts, the availability of Gemini and payments.
5. **An individual or a legal entity.**
6. **Accounts: needed or not.** Transferring the balance and books between phones.
7. **Whether the server stores texts and audio.** Savings against responsibility.
8. **Whether the own-key path stays** next to the paid service.
9. **Android only or iPhone too.** Flutter allows it, but the platform part (the audio encoder, file intake, the
   playback service) is written only for Android, and the App Store has its own rules and commission.
10. **Name and look.** The name, the icon, the store page.
11. **What from the first version's "Out of scope" comes back** for the sake of other people's users: crash reports,
    update checks, search in the text, bookmarks, shelf folders, MOBI.
12. **Who answers users** and how much time there is for it.

## 6. The order, when the time comes

1. Check this document against the current Google Play rules and the Gemini API terms; fix the numbers.
2. Answer questions 1–5 of section 5.
3. Use the first version yourself long enough to know what bothers you in it.
4. If option A is chosen — a separate "publication" spec: section 2 and section 3.
5. If option B — first the economics calculation (section 4), then the server architecture as a separate document
   with a review, then specs: the server, payments, changes in the app.

## 7. What in the current architecture will help and what will get in the way

- **Will help:** synthesis is hidden behind the `TtsEngine` interface — replacing the direct Gemini call with a call
  to our own server does not touch the queue, the player and the screens; audio is stored by the fingerprint of the
  text and profile — repeating is free with any source; the spend is already counted from the responses.
- **Will get in the way:** the absence of accounts and a server is a deliberate decision of the first version; the
  interface is designed for a person who entered the key themselves; verification was done on one phone.
