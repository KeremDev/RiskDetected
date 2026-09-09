#!/usr/bin/env python3
"""Generate Android English resources from the reviewed iOS translation memory.

The iOS string catalogs are the product's canonical Turkish/English copy source. Android-only
copy lives in ``localization/android_en_overrides.json``. The generator intentionally fails when
an Android string has no unambiguous English value or when printf placeholders drift.
"""

from __future__ import annotations

import html
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ANDROID_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ANDROID_ROOT.parent
CATALOG_ROOT = REPOSITORY_ROOT / "App" / "Localization"
OVERRIDE_FILE = ANDROID_ROOT / "localization" / "android_en_overrides.json"
ANDROID_STRING_FILES = (
    ANDROID_ROOT / "app" / "src" / "main" / "res" / "values" / "strings.xml",
    ANDROID_ROOT / "core" / "data" / "src" / "main" / "res" / "values" / "strings.xml",
    ANDROID_ROOT / "core" / "designsystem" / "src" / "main" / "res" / "values" / "strings.xml",
)

PLACEHOLDER_RE = re.compile(r"%(?:(\d+)\$)?(?:@|lld|ld|[dfs])|%\.\d+f")


def normalized(value: str) -> str:
    value = html.unescape(value)
    value = (
        value.replace("\\'", "'")
        .replace("…", "...")
        .replace("–", "-")
        .replace("—", "-")
        .replace("“", '"')
        .replace("”", '"')
        .replace("’", "'")
    )
    value = PLACEHOLDER_RE.sub("%#", value)
    value = value.strip().strip('"').strip()
    return re.sub(r"\\n|\s+", " ", value).strip().casefold()


def translation_memory() -> dict[str, set[str]]:
    memory: dict[str, set[str]] = {}
    for catalog in sorted(CATALOG_ROOT.glob("*.xcstrings")):
        data = json.loads(catalog.read_text(encoding="utf-8"))
        for key, entry in data.get("strings", {}).items():
            localizations = entry.get("localizations", {})
            turkish = localizations.get("tr", {}).get("stringUnit", {}).get("value")
            english = localizations.get("en", {}).get("stringUnit", {}).get("value")
            if english:
                memory.setdefault(normalized(turkish or key), set()).add(english)
    return memory


def android_placeholders(value: str) -> list[str]:
    return [match.group(0) for match in PLACEHOLDER_RE.finditer(value)]


def align_placeholders(english: str, turkish_android: str) -> str:
    expected = android_placeholders(turkish_android)
    actual_matches = list(PLACEHOLDER_RE.finditer(english))
    if len(expected) != len(actual_matches):
        return english

    expected_by_position: dict[str, str] = {}
    for index, placeholder in enumerate(expected, start=1):
        position_match = re.match(r"%(?:(\d+)\$)?", placeholder)
        position = position_match.group(1) if position_match and position_match.group(1) else str(index)
        expected_by_position[position] = placeholder

    replacements: list[tuple[int, int, str]] = []
    for index, match in enumerate(actual_matches, start=1):
        position = match.group(1) or str(index)
        replacements.append((match.start(), match.end(), expected_by_position.get(position, expected[index - 1])))

    aligned = english
    for start, end, replacement in reversed(replacements):
        aligned = aligned[:start] + replacement + aligned[end:]
    return aligned


def android_xml_text(value: str) -> str:
    # aapt treats apostrophes as quoting syntax even in XML text nodes.
    escaped = html.escape(value.replace("'", "\\'"), quote=False)
    # Android trims leading/trailing whitespace in unquoted string resources. Cross-sell
    # fragments deliberately carry boundary spaces around the styled plan name, so preserve
    # those fragments with Android's quoted-resource syntax.
    return f'"{escaped}"' if value != value.strip() else escaped


def resolve_translation(
    key: str,
    turkish: str,
    memory: dict[str, set[str]],
    overrides: dict[str, str],
) -> str | None:
    if key in overrides:
        return overrides[key]

    candidates = memory.get(normalized(turkish), set())
    if len(candidates) == 1:
        return next(iter(candidates))
    if candidates:
        trimmed = {candidate.strip() for candidate in candidates}
        if len({candidate.casefold() for candidate in trimmed}) == 1:
            if "upper" in key or turkish.isupper():
                upper = [candidate for candidate in trimmed if candidate.isupper()]
                if len(upper) == 1:
                    return upper[0]
            if "kucuk" in key or (turkish and turkish[0].islower()):
                lower = [candidate for candidate in trimmed if candidate and candidate[0].islower()]
                if len(lower) == 1:
                    return lower[0]
            sentence = [candidate for candidate in trimmed if candidate and candidate[0].isupper()]
            if len(sentence) == 1:
                return sentence[0]

    # Android storefront copy says Google Play where the canonical iOS copy says App Store.
    app_store_source = turkish.replace("Google Play", "App Store")
    store_candidates = {
        candidate.replace("App Store", "Google Play")
        for candidate in memory.get(normalized(app_store_source), set())
    }
    if len(store_candidates) == 1:
        return next(iter(store_candidates))
    return None


def generate(check: bool = False) -> int:
    memory = translation_memory()
    overrides = json.loads(OVERRIDE_FILE.read_text(encoding="utf-8"))
    failures: list[str] = []
    used_overrides: set[str] = set()
    generated: dict[Path, str] = {}

    for source in ANDROID_STRING_FILES:
        strings = ET.parse(source).getroot().findall("string")
        output_lines = [
            '<?xml version="1.0" encoding="utf-8"?>',
            "<!-- Generated by scripts/generate_android_english_resources.py. Do not edit by hand. -->",
            "<resources>",
        ]
        for element in strings:
            key = element.attrib["name"]
            turkish = "".join(element.itertext())
            english = resolve_translation(key, turkish, memory, overrides)
            if english is None:
                failures.append(f"{source.relative_to(ANDROID_ROOT)}: {key} = {turkish}")
                continue
            if key in overrides:
                used_overrides.add(key)
            english = align_placeholders(english, turkish)
            if sorted(android_placeholders(english)) != sorted(android_placeholders(turkish)):
                failures.append(
                    f"placeholder mismatch {key}: {android_placeholders(turkish)} != "
                    f"{android_placeholders(english)}"
                )
                continue
            output_lines.append(f'    <string name="{key}">{android_xml_text(english)}</string>')
        output_lines.append("</resources>")
        target = source.parent.parent / "values-en" / "strings.xml"
        generated[target] = "\n".join(output_lines) + "\n"

    unused = sorted(set(overrides) - used_overrides)
    if unused:
        failures.extend(f"unused override: {key}" for key in unused)
    if failures:
        print("English resource generation failed:", file=sys.stderr)
        print("\n".join(f"- {failure}" for failure in failures), file=sys.stderr)
        return 1

    if check:
        stale = [
            path.relative_to(ANDROID_ROOT)
            for path, expected in generated.items()
            if not path.is_file() or path.read_text(encoding="utf-8") != expected
        ]
        if stale:
            print("English resources are missing or stale:", file=sys.stderr)
            print("\n".join(f"- {path}" for path in stale), file=sys.stderr)
            print("Run scripts/generate_android_english_resources.py and commit the result.", file=sys.stderr)
            return 1
        print(f"Verified English resources for {len(generated)} modules.")
        return 0

    for target, output in generated.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(output, encoding="utf-8")
    print(f"Generated English resources for {len(generated)} modules.")
    return 0


if __name__ == "__main__":
    unknown = [argument for argument in sys.argv[1:] if argument != "--check"]
    if unknown:
        print(f"Unknown arguments: {' '.join(unknown)}", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(generate(check="--check" in sys.argv[1:]))
