#!/usr/bin/env python3
"""Take a new Brand Codex version into Grimoiria, in one command.

The Brand Codex (hughtranstudio/my-website, brand/seed.json) is Hugh's Master
Brand Style. This copies its generated brand/tokens.json over the pinned copy
in Design/codex/, records the version and commit, regenerates every Mac and
Pixel token file, runs the contrast check, and prints what changed on screen,
ready to paste into the pull request.

Usage:
  App/tools/sync-codex.py --from ~/Desktop/my-website        a local my-website checkout (its HEAD)
  App/tools/sync-codex.py --from path/to/tokens.json --commit <sha>
  App/tools/sync-codex.py --ref main                         fetch with the GitHub CLI (gh)
Then open one pull request named "Codex <old> -> <new>" with Mac and Pixel
screenshots, day and night.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent.parent
pinned = here / "Design/codex/tokens.json"
app_map = here / "Design/tokens.json"
generator = here / "tools/gen-tokens.py"
REPO = "hughtranstudio/my-website"


def version_of(text):
    m = re.search(r"Brand Codex (\d+\.\d+\.\d+)\.", json.loads(text)["$description"])
    if not m:
        sys.exit("that file is not a Brand Codex tokens.json")
    return m.group(1)


def fetch(args):
    if args.ref:
        out = subprocess.run(["gh", "api", f"repos/{REPO}/contents/brand/tokens.json?ref={args.ref}"],
                             capture_output=True, text=True, check=True).stdout
        sha = subprocess.run(["gh", "api", f"repos/{REPO}/commits/{args.ref}", "--jq", ".sha"],
                             capture_output=True, text=True, check=True).stdout.strip()
        return base64.b64decode(json.loads(out)["content"]).decode(), sha
    src = Path(args.source).expanduser()
    if src.is_dir():
        sha = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        return (src / "brand/tokens.json").read_text(), sha
    if not args.commit:
        sys.exit("--commit is needed with a bare tokens.json")
    return src.read_text(), args.commit


def resolved():
    css = (here / "Design/tokens.css").read_text()
    return dict(re.findall(r"--ht-(\w+): (#[0-9A-F]{6});", css))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--from", dest="source")
    g.add_argument("--ref")
    ap.add_argument("--commit")
    args = ap.parse_args()

    text, sha = fetch(args)
    new = version_of(text)
    old = version_of(pinned.read_text())
    before = resolved()

    pinned.write_text(text)
    raw = app_map.read_text()
    raw = re.sub(r'("version": )"[^"]*"', rf'\1"{new}"', raw, count=1)
    raw = re.sub(r'("commit": )"[^"]*"', rf'\1"{sha}"', raw, count=1)
    app_map.write_text(raw)

    gen = subprocess.run([sys.executable, str(generator)], capture_output=True, text=True)
    print(gen.stdout, end="")
    after = resolved()

    changed = [(k, before.get(k), v) for k, v in after.items() if before.get(k) != v]
    print(f"\nCodex {old} -> {new} (commit {sha[:7]})")
    if changed:
        print("| Colour | Before | After |\n| --- | --- | --- |")
        for k, a, b in changed:
            print(f"| {k} | {a or 'new'} | {b} |")
    else:
        print("No app colour changed: this Codex version touches other packs or roles Grimoiria doesn't use.")
    if gen.returncode:
        print(gen.stderr, end="")
        sys.exit("\nA text colour fails 4.5:1 after this change. Fix the app map before opening the pull request.")


if __name__ == "__main__":
    main()
