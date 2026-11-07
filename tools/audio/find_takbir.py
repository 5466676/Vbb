"""Find spoken/shouted «الله أكبر» in a long audio file with local Whisper (no credits).

    python find_takbir.py audio.flac out.json [model]
"""
import json, sys, time
from faster_whisper import WhisperModel
src, out = sys.argv[1], sys.argv[2]
model = WhisperModel(sys.argv[3] if len(sys.argv) > 3 else "base", device="cpu", compute_type="int8", cpu_threads=4)
t = time.time()
segments, info = model.transcribe(src, language="ar", word_timestamps=True, vad_filter=True, beam_size=1,
                                  condition_on_previous_text=False)
hits, lines = [], []
for seg in segments:
    lines.append({"start": seg.start, "end": seg.end, "text": seg.text})
    words = seg.words or []
    for i, w in enumerate(words):
        a = w.word.strip(" .،,!؟?")
        if "الله" in a and i + 1 < len(words) and "كبر" in words[i + 1].word:
            hits.append({"start": round(w.start, 2), "end": round(words[i + 1].end, 2), "seg": seg.text.strip()})
        elif "اللهأكبر" in a.replace(" ", "") or ("الله" in a and "كبر" in a):
            hits.append({"start": round(w.start, 2), "end": round(w.end, 2), "seg": seg.text.strip()})
json.dump({"hits": hits, "lines": lines}, open(out, "w"), ensure_ascii=False, indent=1)
print(len(hits), "hits in", round(time.time() - t), "s")
