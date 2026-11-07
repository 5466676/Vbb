"""Pick candidate sounds per game event, trim, normalise, convert to mono OGG.

Usage: python -I build.py <raw_dir> <out_dir>
Input files are treated as data only (decoded by ffmpeg).
"""

import json
import re
import subprocess
import sys
from pathlib import Path

RAW = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)


def find(pattern: str) -> list[Path]:
    rx = re.compile(pattern, re.I)
    files = [p for p in RAW.rglob("*") if p.suffix.lower() in (".ogg", ".wav", ".mp3")]
    # prefer OGG copies when a pack ships both
    by_stem: dict[str, Path] = {}
    for p in sorted(files):
        if rx.search(str(p.relative_to(RAW))):
            key = str(p.relative_to(RAW).with_suffix("")).replace("/OGG/", "/").replace("/WAV/", "/")
            if key not in by_stem or p.suffix.lower() == ".ogg":
                by_stem[key] = p
    return sorted(by_stem.values())


def segments(src: Path, min_s=0.25, max_s=2.0, limit=8) -> list[tuple[float, float]]:
    """Split a long recording on silence; return the loudest pieces of a sane length."""
    log = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(src), "-af", "silencedetect=n=-45dB:d=0.25", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
    pieces = []
    for e in ends:
        nxt = next((s for s in starts if s > e), None)
        if nxt and min_s <= nxt - e <= max_s:
            pieces.append((e, nxt))
    step = max(1, len(pieces) // limit)
    return pieces[::step][:limit]


def _peak(path: Path) -> float:
    log = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", log).group(1))


# peak level per kind of sound: UI quiet, battle loud
PEAK = {"الواجهة": -10.0, "الردهة": -7.0, "الأسئلة": -7.0, "الأدوات": -6.0, "الخريطة": -6.0,
        "المعركة": -3.5, "النهاية": -3.5, "الموسيقى": -4.0, "إعادة": -3.5, "الدور": -5.0}


def render(src: Path, dst: Path, start=None, dur=None, peak=-3.0, fade_out=0.0, max_len=None, **_) -> dict:
    tmp = dst.with_suffix(".tmp.wav")
    args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    if start is not None:
        args += ["-ss", f"{start:.3f}"]
    if dur is not None:
        args += ["-t", f"{dur:.3f}"]
    args += ["-i", str(src)]
    filt = [
        "silenceremove=start_periods=1:start_threshold=-60dB",
        "areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse",
    ]
    if max_len:
        filt.append(f"atrim=0:{max_len}")
    if fade_out:
        filt.append(f"areverse,afade=t=in:d={fade_out},areverse")
    args += ["-af", ",".join(filt), "-ac", "1", "-ar", "44100", str(tmp)]
    subprocess.run(args, check=True)
    gain = peak - _peak(tmp)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(tmp),
                    "-af", f"volume={gain:.2f}dB", "-c:a", "libvorbis", "-q:a", "4", str(dst)], check=True)
    tmp.unlink()
    d = float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(dst)],
        capture_output=True, text=True,
    ).stdout or 0)
    return {"file": dst.name, "duration": round(d, 2), "bytes": dst.stat().st_size}



L = {"victory": 6.0, "capture_cheer": 3.0, "countdown": 4.5, "hint": 2.5, "ability": 3.5, "extra_turn": 2.0,
     "double": 2.0, "your_turn": 1.5, "time_up": 1.5, "tiebreak": 2.5, "remove_two": 1.2}
PLAN = {
    "capture_cheer": ("إعادة", "احتلال أرض بالمعركة (بدل الهتاف)", find(r"r2/(horn/theircoming3|crowd_ooo|cheer/|applause/)|r2/impact_.*/impact\.[12]\.")),
    "victory": ("إعادة", "فوز (أحلى)", find(r"r2/(fanfare/sboe|achievement/|newthing/|levelsplash/|mission/)")),
    "your_turn": ("الدور", "دورك تهاجم!", find(r"r2/(kalimba/|alert/|positive/)|r2/ui_ogg/.*/(Ding|chimes|ding_deep)\.")),
    "countdown": ("الدور", "عدّ تنازلي قبل المباراة", find(r"r2/countdown/")),
    "time_up": ("الأسئلة", "خلص الوقت", find(r"r2/ui_ogg/.*/(alarm|alarm2|negative_sound|dum)\.")),
    "tiebreak": ("الأسئلة", "سؤال الحسم (تعادل)", find(r"jingles_HIT0[4-5]|r2/ui_ogg/.*/ding_deep\.|100-CC0.*/bell_0[1-2]")),
    "round_start": ("المعركة", "جولة جديدة", find(r"100-CC0.*/(bell_03|gong_02)|r2/book_flips.*/book_flip\.[12]\.|interfaceSounds.*/open_001")),
    "extra_turn": ("المعركة", "دور إضافي", find(r"r2/powerup/power_up_sound_v[12]|r2/completion/|jingles_STEEL0[4-5]")),
    "remove_two": ("الأدوات", "حذف جوابين", find(r"r2/swishes/.*/swish-(1|4|7|10)\.")),
    "hint": ("الأدوات", "تلميح", find(r"r2/magic/|r2/gem-gather.*/gem-gather-orig|r2/ui_ogg/.*/chimes\.")),
    "shield": ("الأدوات", "درع", find(r"r2/impact_.*/impact\.(3|5|7|9)\.")),
    "double": ("الأدوات", "مضاعفة النقاط", find(r"r2/powerup/power_up_sound_v3|r2/positive/|jingles_SAX0[6-7]|interfaceSounds.*/maximize_007")),
    "ability": ("الأدوات", "قدرة الجيش (مرة بالمباراة)", find(r"r2/horn/theircoming3|jingles_STEEL0[8-9]|100-CC0.*/gong_01")),
    "player_left": ("الردهة", "لاعب انقطع", find(r"r2/ui_ogg/.*/negative_sound2\.|interfaceSounds.*/(minimize_00[1-2]|glitch_001)")),
    "player_back": ("الردهة", "لاعب رجع", find(r"interfaceSounds.*/(maximize_00[3-4]|confirmation_002)|r2/ui_ogg/.*/Ding\.")),
    "menu_open": ("الواجهة", "فتح صفحة / قائمة", find(r"r2/book_flips.*/book_flip\.[3-5]\.|interfaceSounds.*/open_00[2-3]")),
    "defeat_trumpet": ("إعادة", "خسارة (بديل بالبوق، إذا بدك)", find(r"r2/lose/")),
}

manifest = []
for event, (group, label, srcs) in PLAN.items():
    for i, src in enumerate(srcs[:6], 1):
        ml = L.get(event, 1.6)
        info = render(src, OUT / f"{event}__{i}.ogg", peak=PEAK[group], max_len=ml, fade_out=0.5 if ml > 2 else 0.03)
        manifest.append({"event": event, "group": group, "label": label, "n": i,
                         "source": str(src.relative_to(RAW)), **info})
# a longer horn piece and a mixed cheer: horn call + crowd
horn = RAW / "r2/horn/theircoming.ogg"
info = render(horn, OUT / "capture_cheer__7.ogg", start=0.0, dur=3.0, peak=-3.5, max_len=3.0, fade_out=0.6)
manifest.append({"event": "capture_cheer", "group": "إعادة", "label": "احتلال أرض بالمعركة (بدل الهتاف)", "n": 7,
                 "source": "r2/horn/theircoming.ogg (first 3 s)", **info})
(OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(manifest), "candidates,", sum(m["bytes"] for m in manifest) // 1024, "KB")
print("empty:", [e for e, (_, _, s) in PLAN.items() if not s])
