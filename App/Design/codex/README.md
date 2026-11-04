# The Brand Codex, pinned

`tokens.json` here is a verbatim copy of `brand/tokens.json` from hughtranstudio/my-website: the Brand Codex,
Hugh's Master Brand Style, in the W3C design-token format. The version and commit are recorded under `$codex` in
`../tokens.json`. Do not edit this copy.

Grimoiria uses the `hughtran` pack (Hugh Tran and HT Press, day and night). `../tokens.json` names a Codex role
for each palette entry (`"codex": "hughtran.color.ink"`); `../../tools/gen-tokens.py` resolves the roles and writes
the Mac and Pixel token files.

Entries marked `legacy` are not in the Codex yet. They keep today's look and are replaced step by step
(plan: vault `palace/decisions/Decision - Grimoiria follows the Brand Codex.md`). Entries marked `app` are
app-only shades for Material container slots.

## Taking a new Codex version

One command, after a Codex pull request merges in my-website:

    App/tools/sync-codex.py --from ~/Desktop/my-website     # a local checkout, at its HEAD
    App/tools/sync-codex.py --ref main                      # or fetch with the GitHub CLI

It copies the new `brand/tokens.json` here, records the version and commit under `$codex` in
`../tokens.json`, regenerates the Mac and Pixel token files, runs the contrast check, and prints a
before/after table of every app colour that changed. Paste that table into one pull request named
"Codex <old> -> <new>", with Mac and Pixel screenshots, day and night, and Arbiter's taste pass.
If a text colour fails 4.5:1 it stops and says so; fix the map first.
