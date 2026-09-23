"""Import the supplied PTW Word pack into the shared mobile app assets.

Usage: python build_work_permit_library.py /path/to/ISGADA_Calisma_Izni_WORD_56_2026-09
The source manifest is checked before any asset is published.
"""

import csv
import hashlib
import json
import shutil
import sys
import unicodedata
from pathlib import Path


DESTINATION = Path(__file__).resolve().parents[2] / "App/WorkPermitAssets/work_permits"
SECTORS = {
    "İnşaat ve altyapı": ("inşaat", "şantiye", "yapı", "çatı", "cephe", "retrofit", "altyapı"),
    "Sanayi ve bakım": ("üretim", "endüstri", "sanayi", "imalat", "bakım", "duruş", "proses", "boru", "kap", "tank", "çok ekipli", "ndt"),
    "Enerji": ("enerji", "elektrik", "güneş", "rüzgar", "gaz dağıtım", "akaryakıt"),
    "Kimya ve petrokimya": ("kimya", "petrokimya", "rafineri", "ex saha", "akaryakıt", "terminal"),
    "Lojistik ve ulaşım": ("lojistik", "depo", "demiryolu", "liman", "denizcilik", "tersane"),
    "Su ve atıksu": ("su ve atıksu", "belediye"),
    "Madencilik": ("maden", "madencilik", "taş"),
    "Sağlık ve ilaç": ("sağlık", "ilaç", "laboratuvar"),
    "Gıda": ("gıda",),
    "Veri merkezi": ("veri merkez",),
}


def search_key(value: str) -> str:
    return "".join(char for char in unicodedata.normalize("NFKD", value.casefold())
                   if not unicodedata.combining(char)).replace("ı", "i")


def main(source: Path) -> None:
    manifest_path = source / "MANIFEST_SHA256.csv"
    with manifest_path.open(encoding="utf-8-sig", newline="") as stream:
        manifest = {row["relative_path"]: row for row in csv.DictReader(stream)}
    with (source / "REHBER_VE_KATALOG/01_Katalog.csv").open(encoding="utf-8-sig", newline="") as stream:
        catalog = list(csv.DictReader(stream))
    if len(catalog) != 56 or {row["Kod"] for row in catalog} != {f"PTW-{n:03}" for n in range(1, 57)}:
        raise ValueError("The catalog must contain exactly PTW-001 through PTW-056")

    entries = []
    verified = []
    for row in catalog:
        filename = row["Word dosyası"]
        if Path(filename).name != filename or not filename.endswith(".docx") or not filename.startswith(row["Kod"] + "_"):
            raise ValueError(f"Invalid Word filename for {row['Kod']}")
        original = source / "WORD" / filename
        expected = manifest.get("WORD/" + filename)
        data = original.read_bytes()
        if expected is None or len(data) != int(expected["size_bytes"]) or hashlib.sha256(data).hexdigest() != expected["sha256"]:
            raise ValueError(f"Source checksum mismatch: {filename}")
        use = row["Kullanım alanı"]
        sectors = [name for name, words in SECTORS.items() if any(search_key(word) in search_key(use) for word in words)]
        if not sectors:
            sectors = ["Tüm sektörler"]
        jobs = [part.strip() for part in row["İş grubu"].split(",") if part.strip()]
        entries.append({
            "code": row["Kod"], "title": row["Form başlığı"],
            "usage": use, "jobs": jobs, "sectors": sectors,
            "filename": filename, "note": row["Kullanım notu"],
        })
        verified.append((original, filename))

    DESTINATION.mkdir(parents=True, exist_ok=True)
    for old in DESTINATION.glob("PTW-*.docx"):
        old.unlink()
    for original, filename in verified:
        shutil.copyfile(original, DESTINATION / filename)
    (DESTINATION / "catalog.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported and verified {len(entries)} Word templates into {DESTINATION}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]))
