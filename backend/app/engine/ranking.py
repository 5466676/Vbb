"""The single ranking rule used everywhere (GAME_RULES §4).

MCQ: correct before wrong; among correct, faster first; wrong answers by speed.
Numeric: closer first, then faster. No answer is always last.
"""

from __future__ import annotations

from app.engine.models import AnswerRecord, Question, QuestionKind


def is_correct(question: Question, answer: AnswerRecord | None) -> bool:
    if answer is None:
        return False
    if question.kind is QuestionKind.MCQ:
        return answer.choice is not None and answer.choice == question.correct_index
    return (
        answer.value is not None and question.answer is not None and answer.value == question.answer
    )


def sort_key(question: Question, answer: AnswerRecord | None, time_bonus_ms: int = 0) -> tuple:
    """Smaller key = better rank. ``time_bonus_ms`` is subtracted from the answer time."""
    if answer is None or (answer.choice is None and answer.value is None):
        return (1, 0.0, 0)
    t = answer.elapsed_ms - time_bonus_ms
    if question.kind is QuestionKind.MCQ:
        return (0, 0.0 if is_correct(question, answer) else 1.0, t)
    distance = abs((answer.value or 0.0) - (question.answer or 0.0))
    return (0, distance, t)


def rank(
    question: Question,
    seats: list[int],
    answers: dict[int, AnswerRecord],
    time_bonus_ms: dict[int, int] | None = None,
) -> list[int]:
    """Return ``seats`` ordered best first. Exact ties keep seat order (stable)."""
    bonus = time_bonus_ms or {}
    return sorted(seats, key=lambda s: sort_key(question, answers.get(s), bonus.get(s, 0)))
