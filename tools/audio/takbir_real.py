import json, random, re, subprocess, sys
from pathlib import Path
SRC = Path(sys.argv[1]); SFX = Path(sys.argv[2]); OUT = Path(sys.argv[3]); OUT.mkdir(parents=True, exist_ok=True)
random.seed(3)
def run(*a): subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y",*a], check=True)
def peak(p):
    log = subprocess.run(["ffmpeg","-hide_banner","-i",str(p),"-af","volumedetect","-f","null","-"],capture_output=True,text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", log).group(1))
def dur(p): return float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",str(p)],capture_output=True,text=True).stdout)
CUTS = {"group": (0.9, 3.8, "تسجيل جماعي حقيقي (تكبيرات العيد، archive.org)"),
        "pd": (0.7, 4.0, "تسجيل حقيقي، ملكية عامة (haramainrecordings.com)"),
        "ccby": (3.5, 7.2, "تسجيل حقيقي، CC BY 3.0 (الشيخ علي أحمد ملا)")}
clips = {}
for k, (s, e, _) in CUTS.items():
    c = OUT / f"{k}.wav"
    run("-ss", str(s), "-t", str(e - s), "-i", str(SRC / f"{k}.ogg"), "-af", "afade=t=in:d=0.05,areverse,afade=t=in:d=0.25,areverse", "-ac", "1", "-ar", "44100", str(c))
    clips[k] = c
def faster(src, dst, tempo): run("-i", str(src), "-af", f"atempo={tempo}", str(dst)); return dst
def crowd(src, dst, copies=10, spread=200):
    ins, fil = [], []
    for k in range(copies):
        ins += ["-i", str(src)]
        r = random.uniform(0.92, 1.08); d = random.randint(0, spread); v = random.uniform(0.5, 1.0)
        fil.append(f"[{k}:a]asetrate={int(44100*r)},aresample=44100,adelay={d},volume={v:.2f}[a{k}]")
    fil.append("".join(f"[a{i}]" for i in range(copies)) + f"amix=inputs={copies}:normalize=0,aecho=0.8:0.7:70|150|300:0.4|0.3|0.2,acompressor=threshold=-18dB:ratio=4,alimiter=limit=0.9[o]")
    run(*ins, "-filter_complex", ";".join(fil), "-map", "[o]", str(dst)); return dst
items = []
def add(ev, label, n, src, name, note, pk=-3.0):
    dst = OUT / f"{name}.ogg"; run("-i", str(src), "-af", f"volume={pk-peak(src):.2f}dB", "-c:a", "libvorbis", "-q:a", "5", str(dst))
    items.append({"event": ev, "group": "«الله أكبر»: تسجيلات حقيقية", "label": label, "n": n, "source": note,
                  "file": dst.name, "duration": round(dur(dst), 2), "bytes": dst.stat().st_size})
L = "التكبيرة لحالها"
add("takbir_real", L, 1, clips["group"], "takbir_real__1", CUTS["group"][2] + " — كما هي")
g_fast = faster(clips["group"], OUT / "group_fast.wav", 1.45)
add("takbir_real", L, 2, g_fast, "takbir_real__2", CUTS["group"][2] + " — أسرع، كصيحة")
g_army = crowd(g_fast, OUT / "group_army.wav")
add("takbir_real", L, 3, g_army, "takbir_real__3", CUTS["group"][2] + " — أسرع ومضاعفة لجيش مع صدى")
p_army = crowd(faster(clips["pd"], OUT / "pd_fast.wav", 1.5), OUT / "pd_army.wav")
add("takbir_real", L, 4, p_army, "takbir_real__4", CUTS["pd"][2] + " — أسرع ومضاعفة لجيش")
c_army = crowd(faster(clips["ccby"], OUT / "ccby_fast.wav", 1.5), OUT / "ccby_army.wav")
add("takbir_real", L, 5, c_army, "takbir_real__5", CUTS["ccby"][2] + " — أسرع ومضاعفة لجيش")
for army, label in (("islamic", "جيش الفتوحات"), ("ayyubid", "الأيوبيون"), ("ottoman", "العثمانيون")):
    bed = SFX / f"capture_{army}.ogg"
    for n, (voice, note) in enumerate(((g_army, "التسجيل الجماعي كجيش"), (g_fast, "التسجيل الجماعي أسرع")), 1):
        mix = OUT / f"mix_{army}_{n}.wav"
        run("-i", str(bed), "-i", str(voice), "-filter_complex",
            "[0:a]volume=0.5[b];[1:a]adelay=200,volume=1.0[v];[b][v]amix=inputs=2:normalize=0:duration=longest,alimiter=limit=0.9[o]",
            "-map", "[o]", str(mix))
        add(f"takbir_{army}", f"{label}: صيحة الجيش + التكبيرة", n, mix, f"takbir_{army}__{n}", f"صيحة {label} يلي اخترتها + {note}")
(OUT / "manifest.json").write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(items), "sounds")
