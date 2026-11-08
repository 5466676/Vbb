"""Build seed/extra_bank.json from the compact question sources in scripts/qsrc/*.txt.

Each source line is one question:
    M|category|difficulty|question|correct|wrong1|wrong2|wrong3
    N|category|difficulty|question|answer|unit
The correct option is written first and moved to a stable pseudo-random position here, so the
answers are spread over the four positions. Texts already in the seed are skipped.

    python -m scripts.build_extra_questions
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from app.questions.bank import SEED_DIR, QuestionIn
from scripts.check_questions import norm

SRC = Path(__file__).parent / "qsrc"
OUT = SEED_DIR / "extra_bank.json"
EXISTING = [SEED_DIR / "seed_ar.json", SEED_DIR / "owner_bank.json"]


def parse(line: str, tag: str) -> dict:
    kind, cat, diff, text, *rest = (p.strip() for p in line.split("|"))
    item: dict = {
        "category": cat,
        "difficulty": int(diff),
        "text_ar": text,
        "source": f"claude:{tag}",
    }
    if kind == "M":
        correct, *wrong = rest
        pos = int(hashlib.sha1(text.encode()).hexdigest(), 16) % 4
        options = wrong[:pos] + [correct] + wrong[pos:]
        item |= {"type": "mcq", "options_ar": options, "correct_index": pos, "unit_ar": ""}
    else:
        answer, unit = (rest + [""])[:2]
        item |= {"type": "numeric", "numeric_answer": float(answer), "unit_ar": unit}
    QuestionIn.model_validate(item)  # fail loudly on a bad line
    return item


def main() -> None:
    seen = {norm(q["text_ar"]) for f in EXISTING for q in json.loads(f.read_text(encoding="utf-8"))}
    out, skipped = [], []
    for src in sorted(SRC.glob("*.txt")):
        for line in src.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            item = parse(line, src.stem)
            key = norm(item["text_ar"])
            if key in seen:
                skipped.append(item["text_ar"])
                continue
            seen.add(key)
            out.append(item)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(out)} questions -> {OUT.name}; {len(skipped)} already in the seed")
    for t in skipped:
        print("  dup:", t)


if __name__ == "__main__":
    main()
