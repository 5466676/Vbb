"""Turn the owner's questions.json (from his build.py) into the built-in seed file.

    python -m scripts.import_owner_bank path/to/questions.json

Writes app/questions/seed/owner_bank.json: every valid question except those already in
seed_ar.json (compared ignoring diacritics and hamza forms) and those held back below.
The server imports it on every start (new questions only). Run the tests after.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from pydantic import ValidationError

from app.questions.bank import SEED_DIR, SEED_FILE, QuestionIn
from app.questions.owner_format import convert
from scripts.check_questions import norm

OUT = SEED_DIR / "owner_bank.json"

# questions kept out until the owner rewords them (normalised text -> reason)
HELD_BACK = {
    norm("ما أطول نهر في العالم؟"): "disputed: Nile or Amazon depending on the source",
    norm("كم عدد قارات العالم حسب التقسيم الشائع؟"): "6 or 7 depending on the school system",
    norm(
        "ما البحيرة الصناعية الأكبر في سوريا التي شكّلها سد الفرات؟"
    ): "the answer's name (بحيرة الأسد) is politically loaded since 2024; many say بحيرة الفرات",
}


def main() -> int:
    src = Path(sys.argv[1])
    data = json.loads(src.read_text(encoding="utf-8"))
    bank = {norm(q["text_ar"]) for q in json.loads(SEED_FILE.read_text(encoding="utf-8"))}
    out, dup, held, bad = [], 0, [], []
    for row, raw in zip(convert(data), data["questions"], strict=True):
        key = norm(row["text_ar"])
        if key in bank:
            dup += 1
            continue
        if key in HELD_BACK:
            held.append(f"{row['text_ar']} — {HELD_BACK[key]}")
            continue
        try:
            q = QuestionIn.model_validate(row)
        except ValidationError as e:
            bad.append(f"{raw.get('id')}: {e.errors()[0]['msg']}")
            continue
        item = q.model_dump(mode="json", exclude_none=True)
        item["source"] = item.get("source") or f"owner:{raw.get('id', '')}"
        out.append(item)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(
        f"{len(out)} written to {OUT.name}; {dup} already in seed_ar; "
        f"{len(held)} held back; {len(bad)} invalid"
    )
    for line in held:
        print("  held:", line)
    for line in bad:
        print("  invalid:", line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
