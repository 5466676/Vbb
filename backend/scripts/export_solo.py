"""Write the app's offline question pack (app/assets/questions/solo.json) from the seed's solo pack.

Questions already in the pack keep their ids (devices remember asked ids so they do not repeat);
new ones get the next free ids.

    python -m scripts.export_solo
"""

from __future__ import annotations

import json
from pathlib import Path

from app.models.question import SOLO_PACK
from app.questions.bank import seed_packs

OUT = Path(__file__).resolve().parents[2] / "app" / "assets" / "questions" / "solo.json"


def main() -> None:
    old = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else []
    ids = {q["text"]: q["id"] for q in old}
    next_id = 1 + max((int(q["id"][1:]) for q in old), default=-1)
    out = []
    for item in seed_packs()[SOLO_PACK]:
        qid = ids.get(item["text_ar"])
        if qid is None:
            qid, next_id = f"b{next_id}", next_id + 1
        q = {
            "id": qid,
            "kind": item["type"],
            "category": item["category"],
            "difficulty": item.get("difficulty", 2),
            "text": item["text_ar"],
            "unit": item.get("unit_ar", ""),
        }
        if item["type"] == "mcq":
            q |= {"options": item["options_ar"], "correct_index": item["correct_index"]}
        else:
            a = item["numeric_answer"]
            q["answer"] = int(a) if float(a).is_integer() else a
        out.append(q)
    OUT.write_text(json.dumps(out, ensure_ascii=False) + "\n", encoding="utf-8")
    kept = sum(1 for q in out if q["text"] in ids)
    print(f"{len(out)} offline questions ({kept} kept, {len(out) - kept} new) -> {OUT}")


if __name__ == "__main__":
    main()
