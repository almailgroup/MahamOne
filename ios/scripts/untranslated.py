#!/usr/bin/env python3
"""Lists the app's strings that have no Arabic yet.

CI runs `xcodebuild -exportLocalizations -exportLanguage ar` (which reads
every string the compiler finds in the code) and then this script on the
.xcloc it wrote. Each line printed is a key to add to the String Catalog
(App/Localizable.xcstrings or Widgets/Localizable.xcstrings) with its Arabic.

usage: untranslated.py <localization folder>
"""
import glob
import json
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def main() -> int:
    folder = sys.argv[1]
    missing: dict[str, list[str]] = {}
    total = 0
    for xliff in glob.glob(f"{folder}/**/*.xliff", recursive=True):
        root = ET.parse(xliff).getroot()
        for file in root.findall("x:file", NS):
            original = file.get("original", "")
            # Info.plist keys and the like are fine in English.
            if not original.endswith((".xcstrings", ".strings", ".stringsdict")):
                continue
            for unit in file.iter(f"{{{NS['x']}}}trans-unit"):
                total += 1
                target = unit.find("x:target", NS)
                if target is None or not (target.text or "").strip() or target.get("state") == "new":
                    # The id is the catalog's key; the source can differ
                    # (positional %1$@ for a key written with %@).
                    missing.setdefault(original, []).append(unit.get("id", ""))
    count = sum(len(v) for v in missing.values())
    print(f"{total} strings, {count} without Arabic")
    for original, keys in sorted(missing.items()):
        print(f"\n{original}:")
        for key in sorted(set(keys)):
            print("  " + json.dumps(key, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
