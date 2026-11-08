"""Levantine (Syrian) commentator lines with Gemini TTS, voice Enceladus (owner's pick).

Writes app/assets/audio/voice/<id>_<n>.ogg (mono, 44.1 kHz, about -16 LUFS, high-passed so it
carries on phone speakers). The Gemini key is injected by the proxy as x-goog-api-key.

    python tools/audio/commentator_shami.py /tmp/voice_wav app/assets/audio/voice
"""

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gemini_tts import say  # noqa: E402

VOICE = "Enceladus"
STYLE = (
    "Speak in Levantine Syrian Arabic dialect (Damascus accent), like an excited, playful battle "
    "commentator shouting to a family playing a war game: short, punchy, energetic, warm and a bit "
    "funny. Read only the Arabic text:\n"
)

LINES = {
    "start": ["يلّا يا أبطال، بلّشت المعركة!", "شدّوا حيلكم، الحرب بلّشت!"],
    "castles": ["ابنوا قلاعكم، كل واحد بدورو!"],
    "expansion": ["تقاسموا الأرض! الأقرب بياخد!"],
    "your_turn": ["دورك! وين بدك تضرب؟", "يلّا، هجوم!"],
    "duel": ["سيف بسيف! مين الأقوى؟", "جاوبوا يا شباب!"],
    "capture": ["احتلّها! ما شاء الله!", "أرض جديدة! عفيه!"],
    "held": ["صمد! ولا شبر!", "ردّوه على عقبو!"],
    "tower": ["وقع برج! ضربة موجعة!"],
    "last_tower": ["آخر برج! انتبه يا بطل!"],
    "eliminated": ["طار من المعركة!"],
    "tiebreak": ["تعادل! الحسم بالأرقام!"],
    "final_round": ["الجولة الأخيرة! كل شي ممكن!"],
    "hurry": ["يلّا يلّا، الوقت عم يخلص!"],
    "too_slow": ["خلص الوقت!"],
    "treasure": ["لقى الكنز! يا محلاها!"],
    "fastest": ["برافو! أسرع واحد!"],
    "lead": ["صرت بالمقدمة!"],
    "victory": ["نصر عظيم! مبروك يا بطل!", "ربحنا! ارفعوا الرايات!"],
    "defeat": ["معلش، المرة الجاية منربحها!"],
}


def main() -> None:
    wav_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    wav_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    for key, variants in LINES.items():
        for i, text in enumerate(variants, 1):
            wav = wav_dir / f"{key}_{i}.wav"
            ogg = out_dir / f"{key}_{i}.ogg"
            if not wav.exists():
                try:
                    say(text, VOICE, wav, style=STYLE)
                except Exception as e:  # keep going; rerun fills the gaps
                    print("FAIL", key, i, e)
                    continue
            subprocess.run(
                [
                    "ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-af",
                    "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=1:"
                    "stop_threshold=-45dB:stop_duration=0.3,highpass=f=120,"
                    "loudnorm=I=-16:TP=-1.5",
                    "-ar", "44100", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", str(ogg),
                ],
                check=True,
            )
            print("ok", ogg.name)


if __name__ == "__main__":
    main()
