import json, random, re, subprocess, sys
from pathlib import Path
SRC = Path(sys.argv[1]); OUT = Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
random.seed(11)
def run(*a): subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y",*a], check=True)
def peak(p):
    log = subprocess.run(["ffmpeg","-hide_banner","-i",str(p),"-af","volumedetect","-f","null","-"],capture_output=True,text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", log).group(1))
def dur(p): return float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",str(p)],capture_output=True,text=True).stdout)
def cut(start, length, dst):
    run("-ss", f"{start}", "-t", f"{length}", "-i", str(SRC), "-af", "afade=t=in:d=0.04,areverse,afade=t=in:d=0.2,areverse", "-ac", "1", "-ar", "44100", str(dst)); return dst
def army(src, dst, copies=8, spread=180):
    ins, fil = [], []
    for k in range(copies):
        ins += ["-i", str(src)]; r = random.uniform(0.95, 1.05); d = random.randint(0, spread); v = random.uniform(0.5, 1.0)
        fil.append(f"[{k}:a]asetrate={int(44100*r)},aresample=44100,adelay={d},volume={v:.2f}[a{k}]")
    fil.append("".join(f"[a{i}]" for i in range(copies)) + f"amix=inputs={copies}:normalize=0,aecho=0.8:0.6:60|140:0.35|0.2,alimiter=limit=0.9[o]")
    run(*ins, "-filter_complex", ";".join(fil), "-map", "[o]", str(dst)); return dst
items = []
def add(n, src, note):
    dst = OUT / f"takbir_film__{n}.ogg"
    run("-i", str(src), "-af", f"volume={-3.0-peak(src):.2f}dB", "-c:a", "libvorbis", "-q:a", "5", str(dst))
    items.append({"event": "takbir_film", "group": "«الله أكبر» من فيلم عمر المختار (نسخة بلا موسيقى)", "label": "التكبيرة",
                  "n": n, "source": note, "file": dst.name, "duration": round(dur(dst), 2), "bytes": dst.stat().st_size})
seq = cut(1126.5, 7.6, OUT / "seq.wav"); add(1, seq, "الجزء التاني، دقيقة 18:46 — خمس تكبيرات ورا بعض، كما هي")
one = cut(1126.6, 1.6, OUT / "one.wav"); add(2, one, "أول تكبيرة لحالها")
two = cut(1128.3, 1.2, OUT / "two.wav"); add(3, two, "تالت تكبيرة لحالها")
last = cut(1130.7, 3.2, OUT / "last.wav"); add(4, last, "آخر تكبيرة (أطول)")
add(5, army(one, OUT / "one_army.wav"), "أول تكبيرة مضاعفة لجيش، بلا موسيقى")
other = cut(1316.3, 3.9, OUT / "other.wav"); add(6, other, "الجزء التاني، دقيقة 21:56 — تكبيرة تانية")
(OUT / "manifest.json").write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(items))
