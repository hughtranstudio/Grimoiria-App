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
1. Copy the new `brand/tokens.json` over this file.
2. Set `version` and `commit` under `$codex` in `../tokens.json`.
3. Run `App/tools/gen-tokens.py`; fix any contrast failure it prints.
4. Open one pull request with Mac and Pixel screenshots, day and night.
