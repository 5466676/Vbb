import json, random, re, subprocess, sys
from pathlib import Path
D = Path(sys.argv[1]); BEDS = Path(sys.argv[2]); OUT = Path(sys.argv[3]); OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)
def run(*a): subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y",*a], check=True)
def peak(p):
    log = subprocess.run(["ffmpeg","-hide_banner","-i",str(p),"-af","volumedetect","-f","null","-"],capture_output=True,text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", log).group(1))
def dur(p): return float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",str(p)],capture_output=True,text=True).stdout)
TRIM = "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse"
takes = sorted(D.glob("v*_t*.mp3"))
clean = []
for t in takes:
    c = OUT / (t.stem + ".wav"); run("-i", str(t), "-af", TRIM, "-ac", "1", "-ar", "44100", str(c)); clean.append(c)
def crowd(dst, copies=2, spread=180, reverb="aecho=0.8:0.6:60|120:0.35|0.25"):
    ins, fil = [], []
    k = 0
    for c in clean:
        for _ in range(copies):
            ins += ["-i", str(c)]
            rate = random.uniform(0.94, 1.06); delay = random.randint(0, spread); vol = random.uniform(0.6, 1.0)
            fil.append(f"[{k}:a]asetrate={int(44100*rate)},aresample=44100,adelay={delay},volume={vol:.2f}[a{k}]"); k += 1
    fil.append("".join(f"[a{i}]" for i in range(k)) + f"amix=inputs={k}:normalize=0,{reverb},acompressor=threshold=-18dB:ratio=4,alimiter=limit=0.9[o]")
    run(*ins, "-filter_complex", ";".join(fil), "-map", "[o]", str(dst))
def finish(src, name, pk=-3.0):
    dst = OUT / f"{name}.ogg"; run("-i", str(src), "-af", f"volume={pk-peak(src):.2f}dB", "-c:a", "libvorbis", "-q:a", "5", str(dst)); return dst
items = []
def add(ev, label, n, src, name, note):
    f = finish(src, name); items.append({"event": ev, "group": "«الله أكبر»: اسمع كيف طالعة", "label": label, "n": n,
        "source": note, "file": f.name, "duration": round(dur(f), 2), "bytes": f.stat().st_size})
add("takbir_voice", "التكبيرة لحالها", 1, clean[0], "takbir_voice__1", "صوت واحد (ElevenLabs TTS)")
c1 = OUT / "crowd_dry.wav"; crowd(c1, copies=2, spread=150, reverb="aecho=0.8:0.5:40:0.2")
add("takbir_voice", "التكبيرة لحالها", 2, c1, "takbir_voice__2", "جماعة صغيرة: 5 أصوات × 4 تسجيلات")
c2 = OUT / "crowd_army.wav"; crowd(c2, copies=4, spread=260, reverb="aecho=0.8:0.7:80|160|320:0.4|0.3|0.2")
add("takbir_voice", "التكبيرة لحالها", 3, c2, "takbir_voice__3", "جيش: 5 أصوات × 8، مع صدى وادي")
for i, s in enumerate(sorted(D.glob("sfx_*.mp3")), 4):
    w = OUT / f"sfx{i}.wav"; run("-i", str(s), "-ac", "1", "-ar", "44100", str(w))
    add("takbir_voice", "التكبيرة لحالها", i, w, f"takbir_voice__{i}", "نموذج المؤثرات الصوتية مباشرة (بدون نص مقروء)")
for army, label in (("islamic", "جيش الفتوحات"), ("ayyubid", "الأيوبيون"), ("ottoman", "العثمانيون")):
    bed = BEDS / f"capture_{army}__1.ogg"
    for n, voice in ((1, c2), (2, c1)):
        mix = OUT / f"mix_{army}_{n}.wav"
        run("-i", str(bed), "-i", str(voice), "-filter_complex",
            "[0:a]volume=0.55[b];[1:a]adelay=250,volume=1.0[v];[b][v]amix=inputs=2:normalize=0:duration=longest,alimiter=limit=0.9[o]",
            "-map", "[o]", str(mix))
        add(f"takbir_{army}", f"{label}: الخلفية + التكبيرة", n, mix, f"takbir_{army}__{n}",
            "خلفية الجيش رقم 1 + " + ("تكبيرة جيش" if n == 1 else "تكبيرة جماعة صغيرة"))
(OUT / "manifest.json").write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(items), "demo sounds")
