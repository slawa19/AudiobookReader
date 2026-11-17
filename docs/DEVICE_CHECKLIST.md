# Phone check

The owner's phone: **Samsung SM-S948B, Android 17**, **three-button** navigation. It has no system edge "Back"
gesture. All items are awaiting a check; the tick is put by the person checking. In the report give the date, SHA, APK
version, the result and the measured values; do not write down or screenshot the key.

The fake build: `build-apk.sh --debug --fake`, named "Book AudioReader (fake)", applicationId
`io.github.slawa19.audiobook_reader.fake`. The real one: `build-apk.sh --debug`, without the `.fake` suffix. Both work
with the real files, encoder, player and media service. Instead of speech the fake engine produces a tone and needs no
key. Its synthesis delay is constant — 2 s for audio that is not there yet; a repeat from the cache has no delay. There
are no delay or error settings in the app. To re-check the preparation in the fake build, choose a place that has not
sounded yet or run "Clear narration" in its settings beforehand.

Order: first the free checks, then the agreed paid SC-2, then the checks of real audio that is already ready and of
updating. Before the paid part one cannot count on real audio being in the cache. Clearing the fake build does not
affect the real one. A debug build is installed over a debug build with the same signature; do not delete an installed
release with a different signature for this check. A new version over a release is checked separately with an APK
signed with the permanent key.

## Free preparation, files and gestures

- [ ] **Two builds side by side (SC-2.5).** Install both APKs, add different books to them. In the fake one create a
  tone, restart both, clear narration of the fake one only. Expected: different app names, the "Fake voice" line only
  in fake; each one's books and changes are not visible to the other. Open the real one without narration for now.
  Build: both. Money: no.
- [ ] **"Open with".** From a file app open FB2, FB2.ZIP and EPUB, including an FB2 as a binary file with an opaque
  content URI; repeat with the reader closed and over another open book. Expected: the right book opens, a repeat does
  not create a duplicate; after the source is deleted the added book can be read. Build: both, without narration.
  Money: no.
- [ ] **Edge swipes.** In reading and while listening make 20 page turns each way starting from the very edge; repeat
  in a case. Expected: one page per gesture, the book does not close. Build: fake. Money: no.
- [ ] **Cancelling an edge movement.** Slowly pull from the edge and return the finger to the start; repeat from both
  edges. Expected: the book is open, the page is the same. The edge "Back" is not checked here: the phone has three
  buttons. Build: fake. Money: no.
- [ ] **Vertical movement.** Make 20 vertical movements over the page. Expected: the page does not turn.
  Build: fake. Money: no.
- [ ] **System "Back" button.** With the panels hidden press "Back": the panels appear, the sound continues; pressing
  again closes the book. Check separately closing a footnote, a sheet and a paragraph selection: first the temporary
  element disappears, the book stays. Build: fake. Money: no.
- [ ] **Safe areas and a large font.** Open reading and the player panel at the normal and at a large system font.
  Expected: the text is outside the camera cutout, the bottom buttons are above the system bar and can be tapped;
  nothing is cut off. Build: fake. Money: no.

- [ ] **License page.** Settings → the last row, "Open-source licenses". Expected: the app is listed once, as "Book
  AudioReader"; the other entries include "Demo texts", "Merriweather" and "Roboto"; there is no `audiobook_reader`
  entry. Build: both. Money: no.
  *Result, 2026-11-17 (SM-S948B, by an agent over adb): as expected in both the fake and the real app. Not checked: a
  large system font on this page.*

## Fake audio: background, service and card

- [ ] **Waiting for the first file in the background.** At a place that has not been narrated press "Listen" and turn
  the screen off immediately, while "Preparing the voice…" is visible. Expected: the media card is already active, after
  the constant synthesis delay of 2 s and encoding the tone starts without unlocking. Build: fake. Money: no.
- [ ] **Background playback.** Start listening, go home, turn the screen off for several pieces. Expected: the sound
  passes between files, after returning the voice's place is current. Build: fake. Money: no.
- [ ] **Closed window and audio writing.** Clear the fake narration, start listening to a long place and immediately
  remove the window from "Recents". Wait for the tone and the following pieces, open the app again. Expected: the
  service has not stopped, synthesis and writing of new files continue without an Activity; the amount of narration in
  settings has grown. Build: fake. Money: no.
- [ ] **Receiving a file while the service is alive.** During a background tone open another book through a file app;
  repeat after removing the reader window from "Recents". Then open the reader by its icon. Expected: one reader
  screen, a correct import without duplicates, the new book is open; the old listening is closed, the channels work.
  Build: fake. Money: no.
- [ ] **A 10-minute pause.** On the lock screen pause, wait 10 minutes, press "Listen" there. Repeat pausing right
  after the start at a new place, while preparation is in progress. Expected: the notification stays, a late file does
  not sound by itself; resuming works without opening the window, a ready file — from the place of the pause.
  Build: fake. Money: no.
- [ ] **Notification permission.** On a fresh install (or one that has never listened) press "Listen". Expected: the
  system asks once whether the app may send notifications, and the sound starts without waiting for the answer. After
  "Don't allow": the card is still in the shade with working buttons, App info shows notifications blocked, its switch
  can be turned on; the next "Listen", also after a restart, does not ask again. After "Allow": App info shows
  notifications allowed. Build: fake. Money: no.
  *Result, 2026-11-17 (SM-S948B, by an agent over adb, fake build): the dialog appeared on the first "Listen" while
  narration was already playing; after "Allow" App info showed notifications allowed; the media card in the shade had
  working pause and play; later listens showed no second dialog. Not checked: the lock-screen card and the dialog in
  the real app (the owner will see it on the next "Listen"); the "Don't allow" branch and the restart case are not
  recorded in this run.*
- [ ] **Card contents.** Listen to a book with a cover and without one, change the chapter, check the notification and
  the lock screen. Expected: the correct book and chapter titles, for an unnamed chapter — the start of its text; the
  cover or a placeholder with the first letter, as on the shelf; no paragraph and no rewind by seconds.
  Build: fake. Money: no.
- [ ] **Card commands.** Check pause, resume, back and forward from the notification and from the lock screen. Before
  resuming/jumping, page the reading away from the voice. Expected: the commands control the same controller; jumps go
  to the start of the neighboring piece, after returning following is on and the new place is visible.
  Build: fake. Money: no.
- [ ] **End of the book and the notification.** Go to the last few paragraphs and wait for the tone to end. Expected:
  "End of the book" on the reading screen, the notification disappeared. Compare with an ordinary pause: there the
  card stays. Build: fake. Money: no.
- [ ] **Timer until the end of the chapter.** Turn on the "Until the end of the chapter" timer and listen to its short
  end. Expected: an immediate pause without an intermediate "Waiting for connection…", the timer is cleared, the card
  stays; resuming starts the next chapter. On the last chapter — the end of the book and the notification disappears.
  Build: fake. Money: no.

## Headset, interruptions and file transitions

- [ ] **Headset buttons.** Check pause/resume and back/forward with the screen on and off. Before resuming/jumping,
  page away from the voice. Expected: jumps by pieces, following is restored. Build: fake. Money: no.
- [ ] **A phone call during preparation and during sound.** At a new place, right after "Listen", answer an incoming
  call; repeat separately during the tone. Expected: pause; after the call ends, including after the first file
  becomes ready, silence until an explicit "Listen". The preparation delay is only 2 s: if the call did not make it,
  repeat at another place that has not been narrated. Build: fake. Money: Gemini — no; the call is billed by the
  carrier.
- [ ] **Another app's sound during preparation and during sound.** Right after "Listen" at a new place start a local
  recording in another app; repeat separately during the tone. Expected: pause, after the other sound stops there is
  no automatic resume. Build: fake. Money: no.
- [ ] **Headphones pulled out.** Unplug the headphones during the tone; repeat during the two-second preparation at a
  new place. Expected: pause, a late file is silent, plugging back in does not resume by itself.
  Build: fake. Money: no.
- [ ] **A pause at a file transition.** Choose a place with short pieces, turn on 2×. When the highlight changes press
  pause several times from the screen, the card and the headset; separately unplug the headphones at a transition.
  Expected: after the pause there is no burst of the next tone into the headphones or speaker. Record the audible
  delay, if there is one. This also checks the window of a file's completion inside the native insertion of the next
  one. Build: fake. Money: no.
- [ ] **Refilling until exhausted.** Listen continuously to several unnarrated pieces at 1× while the next files
  manage to prepare within the constant 2 s. Expected: continuation without a repeat or a skip, with a reserve there is
  no stop between files. Build: fake. Money: no.

## "Download chapter" without paid requests

- [ ] **Screen and lifecycle of the download.** On a long unnarrated chapter press "Download chapter". Do not touch
  the phone for longer than the usual screen timeout: the screen does not go off. Go home and turn the screen off,
  wait, come back: the download continues from the ready remainder. After "Stop" the screen goes off by the usual
  timeout again; leaving and coming back do not resume the stopped task. Expected: in the background new requests do
  not start; the share may grow because of the two responses already started. There is no request counter in the
  interface: by hand we observe the progress, the screen being held and the continuation; the ban on new requests is
  covered separately by `test/app_playback_test.dart`. Build: fake. Money: no.

## Paid SC-2 and waiting for the network

Before the first real request the orchestrator names an estimate for the chosen paragraphs with a margin for the
look-ahead queue, and the owner agrees. This includes network recovery and the starting pair. Do not narrate a whole
book or a whole chapter for acceptance. After the chosen places stop, do not leave real reading unattended. If there
is a risk of exceeding the agreed amount, pause, record the result and agree on continuing. Do not include the key and
the book texts in the report. Use airplane mode with Wi-Fi and mobile data turned off, then restore the network.

- [ ] **Error and the notification disappearing.** At a new place of the real build, before entering the working key,
  save a deliberately wrong non-empty key, press "Listen". Expected: a recognized key error on the screen, the
  notification disappeared, no automatic retries. Then enter the working key from its safe source; the entry itself
  does not start sound. Build: real, within the agreed check. No synthesis is expected on a key rejection.
- [ ] **The key after a restart.** Save the working key, close the process and open the app, check the key's tail.
  Expected: no need to enter it again; the next agreed paragraph is narrated. Do not close the process until the
  started requests complete. Build: real. Money: the call — in the SC-2 estimate.
- [ ] **Different paragraphs.** Listen selectively to several different paragraphs, some with the screen off.
  Expected: the chosen places sound without skips and repeats. Build: real. Money: yes, in the agreed estimate.
- [ ] **Waiting in the middle of listening and recovery.** At a new place during speech turn on airplane mode. Wait
  until the reserve plays out and "Waiting for connection…" appears; turn the screen off, restore the network.
  Expected: transient errors are retried in the background, the notification shows the intent to play and loading, the
  ready audio continues by itself without unlocking. This is also a check of topping up the list after exhaustion.
  Build: real. Money: new responses after recovery are paid, in the estimate of the chosen paragraphs.
- [ ] **A pause during "Waiting for connection…".** Repeat the network disconnect at an agreed new place. After the
  reserve is exhausted pause from the card and restore the network. Expected: the notification stays, late responses
  do not start sound; an explicit "Listen" continues. Build: real. Money: in the agreed SC-2 estimate.
- [ ] **Interruptions during "Waiting for connection…".** With the network disconnected and the reserve exhausted
  unplug the headphones or start another app's local sound, then restore the network. For a separate check of a call
  after "Waiting for connection…" appears, turn airplane mode off, leaving Wi-Fi and mobile data off: voice cellular
  service is available, the internet for synthesis is still off. Answer the call, end it, turn the data on. Expected:
  the pause persists after the network is restored and the interruption ends, no automatic resume.
  Build: real. Money: the responses — in the SC-2 estimate; the call is billed by the carrier.
- [ ] **The starting pair at 2×.** Choose a new agreed place with two starting parts, before "Listen" set 2×.
  Expected: the first sound is already at 2×, both parts in order; a pause is acceptable, record its length.
  Build: real. Money: in the SC-2 estimate.
- [ ] **Following with a large font.** On an agreed paragraph of several pages turn on a large font and listening.
  Expected: pages follow the voice, the sounding place stays visible. Build: real. Money: new audio — in the SC-2
  estimate; a ready repeat is free.
- [ ] **Codec and joins by ear (A§11).** On the same paragraphs listen to the start and end of neighboring files,
  including the two parts of a block. Expected: intelligible speech without clicks, cut-off words, duplicates and an
  added pause between parts. Record the amount of narration in settings before/after and the audible gaps. The PCM is
  deleted after encoding, there is no comparison with it on the phone. Build: real. No additional paid paragraphs are
  needed for this.
- [ ] **Spend.** Record the amount in settings before and after the agreed requests; reconcile the spend line in the
  Google AI Studio console by the actual model and date. Expected: the amounts agree with the rate, allowing for
  rounding. Build: real. No new requests are needed for the reconciliation.

## After the paid part: repeat, isolation and reinstall

- [ ] **A repeat of the same place.** Without changing the voice and model, repeat exactly the same places from which
  listening was already started; before the repeat record the amount in settings. Expected: the amount after the
  repeat has not grown. On a few paragraphs the increase may be smaller than the display step: then reconcile the
  spend line in the Google AI Studio console after its data updates. There is no request counter in the app.
  Build: real. Money: zero expected.
- [ ] **Isolation of ready audio.** Repeat a ready real place; in fake create and clear a tone, then repeat the real
  place once more. Expected: the real speech was preserved, the fake tone did not get into it, the amount has not grown
  (for a small increase — a console reconciliation, as above). Build: both. No new synthesis is needed.
- [ ] **Reinstall without deleting.** In the ordinary debug build save a book, the reading place, settings, ready
  audio and the amount, then reinstall the same ordinary debug APK over it. Expected: the data and the key's tail are
  preserved, the ready place sounds for free. Build: real debug. Money: zero expected; the ready audio appeared in the
  paid part above. Checking the update of a changed version is carried out when the next APK with the same signature
  appears; the current reinstall does not prove compatibility of future changes.
