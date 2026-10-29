# Grimoire Capture for Android (Pixel)

A small capture app for the phone. It writes into the same Inbox folder the Mac app watches, using the same files as the iPhone Shortcut (sidecar contract v1), so the Mac side doesn't change.

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

## Installing the APK

There is no Play Store listing. Every push that touches `android/` builds the app in GitHub Actions (**Actions → Android capture app → latest run → Artifacts → grimoire-capture-apk**). Download it on the Pixel (or `adb install -r app-debug.apk` from the Mac) and allow installing from that source when asked. The build is signed with a fixed key kept in the repo (`android/app/debug.keystore`), so new builds install over old ones and keep your captures and settings.

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

Browsing past entries, decks with no card list yet (Quareia, Mystagogos: the phone flags them and the cards are entered on the Mac until their card lists exist), location, photos of notebook pages.
