"""Modern Standard Arabic commentator, rough war-commander style, Gemini TTS voice Enceladus
(owner's pick). Same line ids as the earlier Levantine set, so the app needs no change.

Lines are generated in batches (the free tier allows 10 requests a day), split on silences:

    python tools/audio/commentator_fusha.py /tmp/voice_wav app/assets/audio/voice
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gemini_tts import say  # noqa: E402

VOICE = "Enceladus"
STYLE = (
    "Speak in Modern Standard Arabic as a tough, battle-hardened war commander: a deep, rough, "
    "gravelly, raspy low voice, powerful and commanding, shouting short orders over the noise of "
    "battle, not playful. Read each line as a separate shout with a clear one-second pause between "
    "lines. Read only the Arabic text:\n"
)

LINES = {
    "start": ["لِتبدأِ المعركة!", "استعدّوا… إلى القتال!"],
    "castles": ["ابنوا قلاعَكم!"],
    "expansion": ["تقاسموا الأرض! الأسرعُ يأخذ!"],
    "your_turn": ["دورُك! اختر هدفك!", "هجوم!"],
    "duel": ["سيفٌ بسيف! من الأقوى؟", "أجيبوا!"],
    "capture": ["سقطتِ الأرض!", "أرضٌ جديدة!"],
    "held": ["صمدَ المدافع!", "ارتدَّ الهجوم!"],
    "tower": ["سقطَ برج! ضربةٌ موجعة!"],
    "last_tower": ["آخرُ برج! احذر!"],
    "eliminated": ["خرجَ من المعركة!"],
    "tiebreak": ["تعادل! الحسمُ بالأرقام!"],
    "final_round": ["الجولةُ الأخيرة! كلُّ شيءٍ ممكن!"],
    "hurry": ["أسرِع! الوقتُ ينفد!"],
    "too_slow": ["انتهى الوقت!"],
    "treasure": ["وجدَ الكنز!"],
    "fastest": ["أسرعُ جواب!"],
    "lead": ["أنت في المقدّمة!"],
    "victory": ["نصرٌ عظيم!", "ارفعوا الرايات! النصرُ لنا!"],
    "defeat": ["هُزِمنا… لكنّ الحربَ لم تنتهِ!"],
}

FILTER = (
    "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=1:stop_threshold=-45dB:"
    "stop_duration=0.3,highpass=f=100,loudnorm=I=-16:TP=-1.5"
)


def split(big: Path, n: int) -> list[tuple[float, float]]:
    """Cut a batch recording at its n-1 longest pauses."""
    err = subprocess.run(
        ["ffmpeg", "-i", str(big), "-af", "silencedetect=noise=-40dB:d=0.25", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    h, m, sec = re.search(r"Duration: (\d+):(\d+):([\d.]+)", err).groups()
    dur = int(h) * 3600 + int(m) * 60 + float(sec)
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", err)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", err)]
    gaps = [(e - s, (s + e) / 2) for s, e in zip(starts, ends) if 0.3 < s and (s + e) / 2 < dur - 0.3]
    if len(gaps) < n - 1:
        raise RuntimeError(f"{big.name}: {len(gaps)} pauses for {n} lines")
    cuts = sorted(mid for _, mid in sorted(gaps, reverse=True)[: n - 1])
    edges = [0.0, *cuts, dur]
    return list(zip(edges, edges[1:]))


def main() -> None:
    wav_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 7
    wav_dir.mkdir(parents=True, exist_ok=True)
    todo = [(k, i, t) for k, vs in LINES.items() for i, t in enumerate(vs, 1)
            if not (wav_dir / f"{k}_{i}.wav").exists()]
    for b in range(0, len(todo), size):
        batch = todo[b : b + size]
        big = wav_dir / f"batch_{batch[0][0]}_{batch[0][1]}.wav"
        if not big.exists():
            say("\n...\n".join(t for _, _, t in batch), VOICE, big, style=STYLE)
        for (k, i, _), (a, z) in zip(batch, split(big, len(batch))):
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(big), "-ss", str(a), "-to", str(z),
                            str(wav_dir / f"{k}_{i}.wav")], check=True)
    for k, vs in LINES.items():
        for i in range(1, len(vs) + 1):
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav_dir / f"{k}_{i}.wav"), "-af", FILTER,
                            "-ar", "44100", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5",
                            str(out_dir / f"{k}_{i}.ogg")], check=True)
            print("ok", k, i)


if __name__ == "__main__":
    main()
