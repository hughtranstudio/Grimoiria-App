#!/usr/bin/env python3
"""Validates bundled definitions and the test fixtures against schemas/.
Optionally also a grimoire.jsonl: python3 tools/validate_schemas.py path/to/grimoire.jsonl
Needs: pip install jsonschema"""
import glob, json, os, sys
from jsonschema import Draft202012Validator

ROOT = os.path.join(os.path.dirname(__file__), "..")
def schema(name): return Draft202012Validator(json.load(open(os.path.join(ROOT, "schemas", name))))

checks = [
    (schema("deck.schema.json"), glob.glob(os.path.join(ROOT, "Sources/GrimoireCore/Resources/Definitions/decks/*.json"))),
    (schema("spread.schema.json"), glob.glob(os.path.join(ROOT, "Sources/GrimoireCore/Resources/Definitions/spreads/*.json"))),
    (schema("capture-sidecar.v1.schema.json"), glob.glob(os.path.join(ROOT, "Tests/GrimoireCoreTests/Fixtures/capture/*.json"))),
]
failed = 0
for v, files in checks:
    for f in sorted(files):
        errs = list(v.iter_errors(json.load(open(f))))
        failed += len(errs)
        print(("FAIL " if errs else "ok   ") + os.path.relpath(f, ROOT))
        for e in errs: print("     ", e.message)
for jsonl in sys.argv[1:]:
    v = schema("export-record.v1.schema.json")
    for n, line in enumerate(open(jsonl), 1):
        errs = list(v.iter_errors(json.loads(line)))
        failed += len(errs)
        for e in errs: print(f"FAIL {jsonl}:{n}: {e.message}")
    print(f"ok   {jsonl}" if not failed else "")
sys.exit(1 if failed else 0)
