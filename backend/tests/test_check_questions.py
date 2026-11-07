"""The offline question-file checker reports problems by spreadsheet row."""

import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
from app.questions.bank import CSV_COLUMNS  # noqa: E402

HEADER = ",".join(CSV_COLUMNS) + "\n"


def run(tmp_path: Path, body: str, *args: str) -> subprocess.CompletedProcess:
    f = tmp_path / "q.csv"
    f.write_text(HEADER + body, encoding="utf-8")
    return subprocess.run(
        [sys.executable, "-m", "scripts.check_questions", str(f), *args],
        cwd=BACKEND,
        capture_output=True,
        text=True,
    )


def test_reports_bad_rows_and_near_duplicates(tmp_path):
    r = run(
        tmp_path,
        "mcq,جغرافيا,1,ما عاصمة مصر؟,القاهرة,الجيزة,أسوان,الأقصر,0,,,\n"
        "mcq,فلك,1,ما أقرب كوكب للشمس؟,عطارد,الزهرة,المريخ,الأرض,0,,,\n"
        "mcq,علوم,2,سؤال بثلاث خيارات؟,أ,ب,ج,,0,,,\n"
        "mcq,جغرافيا,1,ما عاصمةُ مصرَ,القاهرة,الجيزة,أسوان,الأقصر,0,,,\n"
        "numeric,تاريخ,2,سنة بلا جواب؟,,,,,,,,\n",
    )
    assert r.returncode == 1
    out = r.stdout
    assert "row 3:" in out and "unknown category" in out
    assert "row 4:" in out and "4 different" in out
    assert "row 5: same question as row 2" in out
    assert "row 6:" in out and "numeric_answer" in out
    assert "5 rows, 1 valid, 4 with problems" in out


def test_split_writes_two_packs(tmp_path):
    rows = "".join(f"numeric,رياضيات,1,سؤال رقم {i} عن الأعداد؟,,,,,,{i},,\n" for i in range(1, 7))
    r = run(tmp_path, rows, "--split")
    assert r.returncode == 0, r.stdout
    assert (tmp_path / "q.general.json").exists() and (tmp_path / "q.solo.json").exists()
    assert "(4)" in r.stdout and "(2)" in r.stdout


def test_owner_format_is_understood(tmp_path):
    import json

    data = {
        "version": 1,
        "categories": [
            {"id": "tech", "name": "تكنولوجيا"},
            {"id": "math", "name": "رياضيات وألغاز"},
        ],
        "questions": [
            {
                "id": "q1",
                "category": "tech",
                "type": "choice",
                "question": "ما لغة Flutter؟",
                "difficulty": 1,
                "options": ["Dart", "Go", "Rust", "C"],
                "answer": 0,
            },
            {
                "id": "q2",
                "category": "math",
                "type": "number",
                "question": "كم ضلعاً للمخمّس؟",
                "difficulty": 1,
                "answer": 5,
            },
            {
                "id": "q3",
                "category": "tech",
                "type": "choice",
                "question": "سؤال ناقص؟",
                "difficulty": 1,
                "options": ["أ", "ب"],
                "answer": 0,
            },
        ],
    }
    f = tmp_path / "bank.json"
    f.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    r = subprocess.run(
        [sys.executable, "-m", "scripts.check_questions", str(f)],
        cwd=BACKEND,
        capture_output=True,
        text=True,
    )
    assert "3 rows, 2 valid, 1 with problems" in r.stdout
    assert "تكنولوجيا: 1 mcq, 0 numeric" in r.stdout and "رياضيات: 0 mcq, 1 numeric" in r.stdout
