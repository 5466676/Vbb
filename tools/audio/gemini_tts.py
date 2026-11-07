"""Gemini TTS (key injected by the proxy as x-goog-api-key). Writes 24 kHz WAV files."""
import base64, json, subprocess, sys, time, wave
from pathlib import Path
URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent"
STYLE = ("Read in Modern Standard Arabic like an excited Arab football commentator in a packed stadium: "
         "fast, loud, passionate, with rising energy. Read only the Arabic text:\n")
def say(text, voice, dst, style=STYLE):
    body = {"contents": [{"parts": [{"text": style + text}]}],
            "generationConfig": {"responseModalities": ["AUDIO"],
                                 "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}}}
    for attempt in range(6):
        r = subprocess.run(["curl", "-sS", "-X", "POST", URL, "-H", "Content-Type: application/json", "-d", json.dumps(body)],
                           capture_output=True, text=True)
        d = json.loads(r.stdout)
        if "error" in d:
            if d["error"].get("code") == 429:
                time.sleep(20 * (attempt + 1)); continue
            raise RuntimeError(d["error"]["message"][:200])
        pcm = base64.b64decode(d["candidates"][0]["content"]["parts"][0]["inlineData"]["data"])
        with wave.open(str(dst), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(pcm)
        return dst
    raise RuntimeError("rate limited")
if __name__ == "__main__":
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    text = "لِتبدأِ المعركة! ... سقطتِ الأرض! احتلالٌ جديد! ... الجولةُ الأخيرة! كلُّ شيءٍ ممكن!"
    for v in ["Fenrir", "Puck", "Orus", "Algenib", "Alnilam", "Charon", "Rasalgethi", "Sadaltager"]:
        f = out / f"{v}.wav"
        if not f.exists():
            try: say(text, v, f); print("ok", v)
            except Exception as e: print("FAIL", v, e)
