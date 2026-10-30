# Grimoire for Android (Pixel)

Started as a capture app; now four tabs: **Capture**, **Library**, **Session** and **Today**. The
capture flow below is unchanged. What the other tabs do, and the files behind them, are at the end
of this page and in [phone-library.md](phone-library.md).

The capture app It writes into the same Inbox folder the Mac app watches, using the same files as the iPhone Shortcut (sidecar contract v1), so the Mac side doesn't change.

## What it does

1. **Pick what it is** (card draw, Yi Jing, omen, insight, vision, contact, dream, ritual, meditation, journal), add tags if you like.
2. **Record** (or type). Recording keeps running with the screen locked; stop it from the app or the notification.
3. **Transcribed on the phone** with Android's offline speech model. Nothing goes to a server. The app has no internet permission at all.
4. **Check it.** The transcript is editable. The reading is parsed with the same rules as the Mac (a Kotlin port of `ReadingParser`, checked against the same golden cases). Every deck, spread, card, reversal and Yi Jing line can be corrected; anything the parser was unsure of is outlined, and words it couldn't place are listed. Missing cards and wrong spread counts are flagged but never block saving.
5. **Save to Inbox.** The capture goes into an on-phone outbox first, then is copied into `GrimoireInbox/incoming/`: audio first, sidecar last, each written under a hidden `.part` name and renamed. If the folder isn't reachable the capture waits and is retried on the next save or app start, or from **Captures → Send now**.

On the Mac it lands in the Inbox like any phone capture, and **still has to be confirmed there** before anything is filed. Because the phone already transcribed it and you already checked the reading, the sidecar carries both (`transcript`, `draft`), so the Mac doesn't transcribe or parse again.

If transcription can't run (model not downloaded, recognizer busy), the capture still goes out with its audio and the Mac transcribes it with Whisper as usual.

Shortcuts for one-tap recording: the **Grimoire capture** Quick Settings tile (swipe down, edit tiles, drag it in), or long-press the app icon → **Record**.

## Why Syncthing

The Pixel can't run iCloud Drive, and the practice records are private, so the sync route should not go through anyone's cloud. **Syncthing** syncs a folder directly between the phone and the Mac (peer to peer, encrypted, works on the home network and over the internet via relays). It is offline-first by nature: files written while away sync when both devices next see each other. The app doesn't depend on Syncthing itself, only on a folder, so another sync tool that exposes a folder would also work.

## Setup (once, about 10 minutes)

**Mac**

1. Install Syncthing (`brew install --cask syncthing`, or the macOS app from syncthing.net) and open its web UI.
2. Add a folder: label `GrimoireInbox`, path `~/GrimoireInbox`. Keep it outside iCloud Drive.
3. In the Grimoire Mac app: **Settings → Ingest folders → Add** `~/GrimoireInbox`. The iCloud one stays for the iPhone Shortcut; both can be active.

**Pixel**

1. Install a maintained Syncthing app for Android (the original Syncthing Android app was discontinued at the end of 2024; use the community fork, *Syncthing-Fork*, from F-Droid or the Play Store).
2. Pair it with the Mac (scan the Mac's device ID QR code), accept the `GrimoireInbox` share, and put it at `/storage/emulated/0/GrimoireInbox`.
3. Install **Grimoire Capture** (APK below), open **Settings → Choose folder**, pick `GrimoireInbox`, and allow access.
4. **Settings → Download speech model** once, so transcription works offline.
5. Optional: in Syncthing, add `.*.part` to the folder's ignore patterns. The Mac ignores these anyway; it just saves syncing them.

Test: record an omen saying a sentence, Save. Within a minute `GrimoireInbox/incoming/` on the Mac has a `.wav` and a `.json` with the same name, and the Mac app shows it in the Inbox.

## Installing and updating the app

There is no Play Store listing. Every push that touches `android/` builds the app in GitHub Actions and publishes it as a GitHub release named **Grimoire Capture 0.1.N** (the five newest are kept). The build is signed with a fixed key kept in the repo (`android/app/debug.keystore`), so each new build installs over the last one and keeps your captures and settings.

**Easiest: Obtainium (one-tap updates).** Obtainium is a free app that watches GitHub releases and installs updates.

1. Make a read-only GitHub token (once): github.com → your photo → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**. Name it `Obtainium`, set **Repository access** to *Only select repositories* → `Grimoiria-App`, and under **Repository permissions** set **Contents** to *Read-only*. Generate and copy it.
2. On the Pixel, install **Obtainium** (from F-Droid or its GitHub releases page).
3. In Obtainium: **Settings → GitHub → Personal access token**, paste the token.
4. **Add app** → URL `https://github.com/hughtranstudio/Grimoiria-App` → **Add**. Obtainium installs the newest build; allow it to install apps when asked.
5. From then on Obtainium shows a notification when a new build is out; tap **Update**.

**Manual:** open the repo's **Releases** page on the phone, download the newest `grimoire-capture-0.1.N.apk`, and open it.

To build locally instead: Android Studio (or the command-line SDK) with JDK 17, then `cd android && ./gradlew :app:assembleDebug`.

## Files the app writes

| File | When | Notes |
|---|---|---|
| `incoming/<id>.wav` | voice captures | 16 kHz mono 16-bit PCM WAV, Whisper's native rate |
| `incoming/<id>.json` | always, last | sidecar v1; `device` is the name from Settings (default `pixel`) |

The id is `yyyyMMdd-HHmmss-NNNN`, the same shape the Shortcut uses. Sidecar fields beyond the Shortcut's: `text` for typed captures, `transcript` and `draft` for checked voice captures (see `schemas/capture-sidecar.v1.schema.json`).

## Code

- `android/core` is plain Kotlin (no Android): definitions loader, tokenizer, `NameMatcher`, `ReadingParser`, Yi Jing derivation, the corrections editor, sidecar model and the offline outbox (`CaptureStore`). It reads the deck JSON straight from `Sources/GrimoireCore/Resources/Definitions` and runs the Swift golden cases in `Tests/GrimoireCoreTests/Fixtures/parser-golden/`. Run it anywhere with a JDK: `cd android && ./gradlew -PcoreOnly :core:test`.
- `android/app` is the Compose UI, recorder (foreground service, microphone type), on-device transcriber (`SpeechRecognizer` fed from the recorded file) and the folder writer (Storage Access Framework).
- **When you change the Swift parser**, regenerate the golden file (`GRIMOIRE_REGENERATE_GOLDEN=1 swift test --filter ParserGoldenTests`) and make the same change in `android/core`; CI fails until both agree.

## Not in this version

Browsing past entries, decks with no card list yet (Mystagogos: the phone flags it and the cards are entered on the Mac until its card list exists), location, photos of notebook pages.


## Library, sessions and check-ins (the grimoire on the phone)

The Syncthing folder now carries files both ways. The Mac writes a read-only copy of everything
filed into `GrimoireInbox/library/` (see [phone-library.md](phone-library.md)); the phone writes
captures, sessions and outcomes into `incoming/` as before. Nothing else links the two, and the phone
still has no internet permission.

- **Library**: every reading and entry filed on the Mac, newest first. Search by words (questions,
  card and hexagram names, outcomes, observations), `#tag` (a parent finds its children), or tap a
  card or hexagram in a reading to see every reading it appears in. Filter chips by type. **Decks**
  lists the cards of each deck with their meanings (Quareia has them; RWS and Mystagogos have none
  yet) and the 64 hexagrams. Pull down to look for a newer library.
- **Readings without a deck**: on Capture, **Draw cards** or **Cast Yi Jing** opens the check
  screen with an empty reading; **Draw on phone** shuffles the chosen deck into the spread, **Cast
  on phone** throws three coins per line (or uses yarrow odds). They are tagged `method/phone-cast`
  and still go through check on the phone and Confirm on the Mac.
- **Session**: ritual, meditation or vision. Set intention, technique and how you feel going in,
  then **Begin**. The microphone runs throughout (screen can be locked; stop from the
  notification). A big **Mark** button drops "something happened here", phase chips mark
  preparation, opening, working and closing, and **Write an observation** adds a typed one with a
  kind and tags. **End session**, rate how you feel coming out, add an outcome, **Save to Inbox**.
  The Mac transcribes the audio with timestamps, turns it into timed observations and puts the
  session in its Inbox (docs/session-recording.md). A session in progress survives the app closing.
- **Today**: check-ins due (7, 30 and 90 days after a reading), from the Mac's reminders. **Add
  outcome** sends a short outcome (with yes / partly / no / unclear) to the Mac's Inbox; Confirm there
  adds it to the reading. **In 3 days** puts one off on the phone only. A notification each morning
  at about 9 says when something is due (Settings can turn it off).
- **Calendar** (Settings, off by default): check-ins as all-day events in a "Grimoire" calendar
  that lives only on the phone. Google Calendar shows it, but it is a local calendar, so nothing
  syncs to the Google account.
- **Look**: HT Press house style, A · Codex: vellum ground, EB Garamond text, Cormorant Garamond
  titles, square corners, rubric red only for marks. Fonts are bundled (SIL OFL, `android/fonts-license/`).

To see the library on the phone, the Mac app needs the matching update (PR with `PhoneLibrary`),
with **Settings → Inbox → Share a read-only library with the phone** on (the default) and
`~/GrimoireInbox` as an ingest folder.
