# Question bank format

Send questions as **CSV** (Excel / Google Sheets → "Download as CSV, UTF-8") or **JSON**.
Template: [`questions_template.csv`](questions_template.csv). One question per row.

## Columns

| column | required | values |
|---|---|---|
| `type` | yes | `mcq` (4 options) or `numeric` (the answer is a number) |
| `category` | yes | exactly one of: `دين`, `تاريخ`, `جغرافيا`, `علوم`, `رياضيات`, `لغة عربية`, `رياضة`, `ثقافة عامة` |
| `difficulty` | no (default 2) | `1` easy, `2` medium, `3` hard |
| `text_ar` | yes | the question, 3–500 characters, must be unique in the bank |
| `option_1` … `option_4` | mcq | four **different** options |
| `correct_index` | mcq | position of the right option: **0** = option_1, 1 = option_2, 2 = option_3, 3 = option_4 |
| `numeric_answer` | numeric | the exact number (e.g. `1453`, `3.14`) |
| `unit_ar` | no | shown next to the answer box (e.g. `كم`, `م`, `سنة`) |
| `source` | no | where the fact comes from (book, site) — helps review |

## Rules that keep the game fair

- **One clearly right answer.** No "it depends", no answers that changed recently (populations, records,
  "the current…"), no opinions.
- **Wrong options must be believable** and of the same kind (four cities, four years…).
  Don't always put the right answer first: spread `correct_index` over 0–3.
- **Numeric questions** need answers where "closest wins" makes sense: years, counts, distances,
  heights. Avoid tiny decimals and huge numbers that nobody can estimate.
- Short questions: they are read under a timer on a phone (aim for under ~120 characters).
- Nothing sectarian, political or about current conflicts; religion questions stay on widely
  agreed facts (e.g. number of surahs), never on disputed rulings.
- Everyone in the room sees the same question, so mix difficulties: roughly 40 % easy, 40 % medium,
  20 % hard.

## What happens to the file

1. `python -m scripts.check_questions file.csv` checks every row and lists problems by row number
   (wrong category, three options, duplicate text, missing answer…). Nothing is imported yet.
2. Duplicates of questions already in the bank are skipped automatically.
3. The good rows are imported unreviewed (`reviewed=false`) into a pack:
   - `general` — online matches (answers never reach the phone before the deadline);
   - `solo` — offline training, downloaded **with answers** to phones.
   A question is in one pack only. By default, one in three goes to `solo`.
4. Review them in the admin API (mark `reviewed`), then turn on "reviewed only" for launch.
