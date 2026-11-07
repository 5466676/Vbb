"""The owner's question-file format (made by his ``build_questions.py``) → our import rows.

    {"version": 1,
     "categories": [{"id": "geography", "name": "جغرافيا", ...}, ...],
     "questions": [
        {"id": "q0001", "category": "geography", "type": "choice", "question": "…",
         "difficulty": 1, "options": ["…" x4], "answer": 3},
        {"id": "q0013", "category": "geography", "type": "number", "question": "…",
         "difficulty": 1, "answer": 7, "tolerance": 0.001}]}

``tolerance`` is not needed: numeric questions are won by the closest answer.
"""

from __future__ import annotations

from typing import Any

from app.models.question import CATEGORIES

CATEGORY_IDS = {
    "geography": "جغرافيا",
    "history": "تاريخ",
    "science": "علوم",
    "sports": "رياضة",
    "islamic": "دين",
    "arabic": "لغة عربية",
    "tech": "تكنولوجيا",
    "math": "رياضيات",
    "culture": "ثقافة عامة",
    "nature": "حيوانات وطبيعة",
}


def is_owner_format(data: Any) -> bool:
    return isinstance(data, dict) and isinstance(data.get("questions"), list)


def convert(data: dict[str, Any]) -> list[dict[str, Any]]:
    names = {c.get("id"): c.get("name") for c in data.get("categories", []) if isinstance(c, dict)}
    rows = []
    for q in data["questions"]:
        cid = q.get("category")
        category = CATEGORY_IDS.get(cid) or names.get(cid) or cid
        if category not in CATEGORIES and names.get(cid) in CATEGORIES:
            category = names[cid]
        row: dict[str, Any] = {
            "category": category,
            "difficulty": q.get("difficulty", 2),
            "text_ar": q.get("question", ""),
            "source": q.get("source", ""),
        }
        if q.get("type") == "choice":
            row |= {"type": "mcq", "options_ar": q.get("options"), "correct_index": q.get("answer")}
        else:
            row |= {
                "type": "numeric",
                "numeric_answer": q.get("answer"),
                "unit_ar": q.get("unit", ""),
            }
        rows.append(row)
    return rows
