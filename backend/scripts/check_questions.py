"""Check a question file (CSV or JSON) without touching any database.

    python -m scripts.check_questions questions.csv [--split]

Prints one line per problem (row number as in the spreadsheet, header = row 1), a summary per
category / type / difficulty, near-duplicate texts inside the file, and how the correct answers
are spread over the four positions. ``--split`` also writes <name>.general.json and
<name>.solo.json (every third valid question per category goes to solo).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from pydantic import ValidationError

from app.models.question import CATEGORIES
from app.questions.bank import QuestionIn, parse_csv

_TASHKEEL = re.compile(r"[ً-ٰٟـ]")


def norm(text: str) -> str:
    """Compare texts ignoring diacritics, tatweel, hamza forms, punctuation and spaces."""
    t = _TASHKEEL.sub("", text)
    t = re.sub("[إأآا]", "ا", t).replace("ى", "ي").replace("ة", "ه")
    return re.sub(r"[\W_]+", "", t)


def load(path: Path) -> list[dict]:
    raw = path.read_bytes().decode("utf-8-sig")
    if path.suffix.lower() == ".csv":
        return parse_csv(raw)
    data = json.loads(raw)
    if not isinstance(data, list):
        raise SystemExit("a JSON file must be an array of questions")
    return data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("file", type=Path)
    ap.add_argument("--split", action="store_true")
    args = ap.parse_args()
    try:
        rows = load(args.file)
    except (ValueError, KeyError) as e:
        print(f"cannot read the file: {e}")
        return 2
    first_row = 2 if args.file.suffix.lower() == ".csv" else 1
    good: list[dict] = []
    seen: dict[str, int] = {}
    problems = 0
    for i, row in enumerate(rows):
        n = i + first_row
        try:
            q = QuestionIn.model_validate(row)
        except ValidationError as e:
            problems += 1
            msgs = "; ".join(
                f"{'.'.join(map(str, err['loc'])) or 'row'}: {err['msg']}" for err in e.errors()
            )
            print(f"row {n}: {msgs}")
            continue
        key = norm(q.text_ar)
        if key in seen:
            problems += 1
            print(f"row {n}: same question as row {seen[key]}")
            continue
        seen[key] = n
        if len(q.text_ar) > 160:
            print(
                f"row {n}: long question ({len(q.text_ar)} characters) — hard to read under a timer"
            )
        good.append(q.model_dump(mode="json"))
    print()
    print(f"{len(rows)} rows, {len(good)} valid, {problems} with problems")
    by = Counter((q["category"], q["type"]) for q in good)
    for cat in CATEGORIES:
        print(f"  {cat}: {by[(cat, 'mcq')]} mcq, {by[(cat, 'numeric')]} numeric")
    diff = Counter(q["difficulty"] for q in good)
    print(f"  difficulty 1/2/3: {diff[1]} / {diff[2]} / {diff[3]}")
    pos = Counter(q["correct_index"] for q in good if q["type"] == "mcq")
    print(f"  right answer at option 1/2/3/4: {pos[0]} / {pos[1]} / {pos[2]} / {pos[3]}")
    if args.split and good:
        packs: dict[str, list] = {"general": [], "solo": []}
        count: dict[str, int] = defaultdict(int)
        for q in good:
            count[q["category"]] += 1
            packs["solo" if count[q["category"]] % 3 == 0 else "general"].append(q)
        for name, items in packs.items():
            out = args.file.with_suffix(f".{name}.json")
            out.write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
            print(f"wrote {out} ({len(items)})")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
