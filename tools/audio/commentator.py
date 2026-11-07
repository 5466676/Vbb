"""Generate the commentator lines (docs/AUDIO.md §4) with ElevenLabs text-to-speech.

    python tools/audio/commentator.py VOICE_ID MODEL OUT_DIR     # MODEL: eleven_v3 | eleven_multilingual_v2

The key is injected by the session's network proxy (never in code). Files: OUT_DIR/<id>.mp3.
"""
import json
import subprocess
import sys
from pathlib import Path

GENERAL = {
    "start_1": "لِتبدأِ المعركة!", "start_2": "استعدّوا... انطلقنا!", "start_3": "ليبدأ صراعُ العقول!",
    "expansion_1": "الكلُّ يتسابقُ على الأرض!", "expansion_2": "سؤالٌ جديد، والأرضُ للأسرع!",
    "battle_1": "انتهى التوسّع... وبدأتِ الحرب!", "battle_2": "الآن تتكلّمُ السيوف!",
    "duel_1": "مبارزة!", "duel_2": "وجهاً لوجه!",
    "tiebreak_1": "تعادل! سؤالُ الحسم!", "tiebreak_2": "لا غالبَ ولا مغلوب... إلى سؤالِ الحسم!",
    "capture_1": "سقطتِ الأرض!", "capture_2": "احتلالٌ جديد!", "capture_3": "ضربةٌ موفّقة!",
    "held_1": "صمدَ المدافع!", "held_2": "دفاعٌ أسطوري!", "held_3": "ارتدَّ الهجوم!",
    "tower_1": "سقطَ برج!", "tower_2": "القلعةُ تهتزّ!",
    "shield_1": "الدرعُ يصدُّ الهجوم!",
    "eliminated_1": "خرجَ من المعركة!", "eliminated_2": "سقطتِ القلعة... وانتهى الحلم!",
    "last_round_1": "الجولةُ الأخيرة! كلُّ شيءٍ ممكن!",
    "comeback_1": "يا لها من عودة!",
    "end_1": "انتهتِ المعركة!", "end_2": "وانتهى صراعُ العقول!",
    "you_win_1": "النصرُ لك!", "you_lose_1": "حظّاً أوفر في المعركةِ القادمة!",
    "team_win_1": "الفريقُ المنتصر... يا له من تعاون!",
}
ARMIES = {
    "islamic": ("جيشُ الفتوحاتِ يتقدّم!", "النصرُ لجيشِ الفتوحات!"),
    "ayyubid": ("الأيوبيّون يهاجمون!", "النصرُ للأيوبيّين!"),
    "crusader": ("الصليبيّون يزحفون!", "النصرُ للصليبيّين!"),
    "roman": ("الرومانُ يتقدّمون بتشكيلِهم!", "النصرُ للرومان!"),
    "pharaoh": ("جيشُ الفراعنةِ يهاجم!", "النصرُ للفراعنة!"),
    "mongol": ("المغولُ يجتاحون!", "النصرُ للمغول!"),
    "ottoman": ("العثمانيّون يهاجمون!", "النصرُ للعثمانيّين!"),
    "ww2": ("جيشُ الحربِ العالميةِ يتحرّك!", "النصرُ لجيشِ الحربِ العالمية!"),
}
LINES = dict(GENERAL)
for army, (attack, win) in ARMIES.items():
    LINES[f"attack_{army}"] = attack
    LINES[f"win_{army}"] = win
HIGH = {"start", "eliminated", "last_round", "end", "you_win", "win", "team_win"}


def body(text: str, key: str, model: str) -> dict:
    if model == "eleven_v3":
        tag = "[shouting]" if key.split("_")[0] in HIGH else "[excited]"
        return {"text": f"{tag} {text}", "model_id": model}
    return {"text": text, "model_id": model,
            "voice_settings": {"stability": 0.35, "similarity_boost": 0.8, "style": 0.7, "use_speaker_boost": True}}


def main() -> None:
    voice, model, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    for key, text in LINES.items():
        f = out / f"{key}.mp3"
        if f.exists():
            continue
        r = subprocess.run(["curl", "-sS", "-f", "-X", "POST",
                            f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128",
                            "-H", "Content-Type: application/json", "-d", json.dumps(body(text, key, model)),
                            "-o", str(f)], capture_output=True, text=True)
        print(("ok  " if r.returncode == 0 else "FAIL") + f" {key}: {text}")
    (out / "lines.json").write_text(json.dumps(LINES, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
