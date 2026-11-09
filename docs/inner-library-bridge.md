# The Inner Library bridge

Hugh's Inner Library (hughtranstudio.com/intima, behind his passkey) talks to Grimoiria. Grimoiria stays the one home for the practice record; the room never keeps a copy (my-website `docs/adr/0005-inner-library-speaks-grimoiria-contracts.md`, vault `palace/decisions/Decision - Inner Library and Grimoiria.md`).

| Direction | What travels | Contract |
|---|---|---|
| Site → Mac | Captures sent from the room (*Send to Grimoiria* on a Journal page, or the room's quick capture) | capture sidecar v1, `device: "inner-library"`, never audio, never a reading |
| Mac → site | The status card: Inbox, check-ins due, open inquiries, last practice | `grimoire-status.json` (StatusSummary v1); counts only |
| Links | `grimoire://today`, `grimoire://inbox` | `GrimoireLink` |

**Counts travel, contents stay.** Words only ever go into Grimoiria, and only once: the site deletes each capture as soon as the bridge says it is on disk.

## How it runs

`grimoire bridge sync` (in `InnerLibraryBridge`):
1. pulls the captures waiting in the room's sealed outbox;
2. writes each into `~/GrimoireInbox/incoming/<id>.json`, where the app's normal ingest files it in the **Inbox** to confirm (source `phone:inner-library`). A capture already in `incoming/` or `processed/` is not written twice, and the ingest ignores a known capture id;
3. tells the site which ones arrived (the site forgets them);
4. sends `~/HT-Press-Vault/Grimoire/grimoire-status.json`, which the app already writes.

A capture that fails the checks (unsafe id, wrong device, audio, bad contract) is left on the site and listed as refused.

launchd runs it every 15 minutes through `tools/inner-library-bridge.sh`, which reads the token from the Keychain.

## Set up (once)

1. Make the token and put it in the Keychain (it is also copied, so you can paste it in Netlify):
   `T=$(openssl rand -hex 32) && security add-generic-password -U -a "$USER" -s grimoiria-inner-library -w "$T" && printf %s "$T" | pbcopy && echo "Token copied; paste it into Netlify as INTIMA_BRIDGE_TOKEN"`
2. In Netlify (site htstudio-site): Site configuration, Environment variables, add `INTIMA_BRIDGE_TOKEN` with the pasted value, then redeploy.
3. Build the CLI and start the timer:
   `cd ~/grimoiria-app && git pull && swift build -c release && sed "s|HOME_DIR|$HOME|g" tools/com.hughtran.grimoiria.inner-library-bridge.plist > ~/Library/LaunchAgents/com.hughtran.grimoiria.inner-library-bridge.plist && launchctl unload ~/Library/LaunchAgents/com.hughtran.grimoiria.inner-library-bridge.plist 2>/dev/null; launchctl load ~/Library/LaunchAgents/com.hughtran.grimoiria.inner-library-bridge.plist`
4. Check it: `INTIMA_BRIDGE_TOKEN=$(security find-generic-password -a "$USER" -s grimoiria-inner-library -w) ~/grimoiria-app/.build/release/grimoire bridge hello`

The log is `~/Library/Logs/grimoiria-inner-library.log`.

## When it says no

- **401**: the Keychain token and Netlify's `INTIMA_BRIDGE_TOKEN` differ. Run step 1 again and paste into Netlify.
- **423**: *Lock everywhere* was pressed in the room. Open the room with your passkey and the bridge starts again.
- **503**: the site has no token (or no Journal key) yet.

Without the bridge, every capture in the room can still be saved as a file (**File**) and dropped into `~/GrimoireInbox/incoming/` by hand.
