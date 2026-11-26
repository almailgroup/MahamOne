#!/usr/bin/env python3
"""Lists the words the app shows with t("…") or tp(…, "…", "…") that have no
Arabic in Shared/Resources/ar.json (the web's, generated) or
Shared/Resources/ar-native*.json (the app's own, by area).

usage: python3 scripts/missing_arabic.py [--strict]   (from ios/)
--strict exits 1 when some are missing.
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
table = {}
resources = root / "Shared" / "Resources"
for path in [resources / "ar.json"] + sorted(resources.glob("ar-native*.json")):
    if path.exists():
        table.update(json.loads(path.read_text()))

# t("…") and the plural (second) text of tp(n, "…", "…"); Swift string literals
# without interpolation.
literal = r'"((?:[^"\\]|\\.)*)"'
patterns = [re.compile(r'\bt\(\s*' + literal), re.compile(r'\btp\([^,]+,\s*' + literal + r'\s*,\s*' + literal)]
missing = {}
for file in sorted((root / "App").rglob("*.swift")):
    if "Preview" in file.parts:
        continue
    text = file.read_text()
    for pattern in patterns:
        for match in pattern.finditer(text):
            key = match.group(match.lastindex)
            if "\\(" in key:
                continue
            key = key.encode().decode("unicode_escape") if "\\" in key else key
            if key not in table:
                missing.setdefault(key, set()).add(str(file.relative_to(root)))

print(f"{len(missing)} words without Arabic")
for key in sorted(missing):
    print(f"  {key!r}  ({', '.join(sorted(missing[key]))})")
if "--strict" in sys.argv and missing:
    sys.exit(1)
