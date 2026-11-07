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
        "المعركة": -3.5, "النهاية": -3.5, "الموسيقى": -4.0}


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


# event -> (group, Arabic label, list of sources)
PLAN = {
    "ui_tap": ("الواجهة", "ضغطة زر", find(r"interfaceSounds.*/click_00[1-3]|UI_SFX.*/click[1-2]\.")),
    "ui_back": ("الواجهة", "رجوع / إغلاق", find(r"interfaceSounds.*/(back_00[1-2]|close_001)")),
    "ui_toggle": ("الواجهة", "تبديل خيار", find(r"interfaceSounds.*/toggle_00[1-3]")),
    "ui_error": ("الواجهة", "خطأ / غير مسموح", find(r"interfaceSounds.*/error_00[2-4]")),
    "army_select": ("الردهة", "اختيار جيش (سحب سيف)", find(r"RPGsounds.*/drawKnife[1-3]")),
    "ready": ("الردهة", "جاهز", find(r"interfaceSounds.*/confirmation_00[1-3]")),
    "match_found": ("الردهة", "لقينا مباراة / لاعب انضم", find(r"interfaceSounds.*/(bong_001|maximize_00[1-2])")),
    "question_show": ("الأسئلة", "ظهور السؤال", find(r"interfaceSounds.*/question_00[1-3]|RPGsounds.*/bookFlip1")),
    "tick": ("الأسئلة", "عدّاد آخر 5 ثواني", find(r"interfaceSounds.*/tick_00[1-2]|UI_SFX.*/rollover[1-2]\.")),
    "answer_locked": ("الأسئلة", "قفلت جوابي", find(r"interfaceSounds.*/select_00[1-3]")),
    "other_answered": ("الأسئلة", "لاعب تاني جاوب", find(r"interfaceSounds.*/(pluck_00[1-2]|drop_001)")),
    "correct": ("الأسئلة", "جواب صح", find(r"interfaceSounds.*/(confirmation_004|glass_00[1-2])|jingles_STEEL0[0-1]")),
    "wrong": ("الأسئلة", "جواب غلط", find(r"interfaceSounds.*/error_00[5-7]")),
    "claim": ("الخريطة", "احتلال أرض بالتوسع", find(r"RPGsounds.*/(chop|dropLeather|bookPlace1)")),
    "march": ("الخريطة", "مشي الجيش", find(r"RPGsounds.*/footstep0[0-2]")),
    "sword_swing": ("المعركة", "ضربة سيف", find(r"starninjas_1/.*sword\.[1-3]\.")),
    "sword_clash": ("المعركة", "تصادم سيوف (المبارزة)", find(r"sword_clash.*/sword_clash\.[1-3]\.")),
    "tower_hit": ("المعركة", "ضربة برج", find(r"100-CC0.*/(explosion|slam_0[1-2])")),
    "base_guarded": ("المعركة", "القاعدة صمدت / درع", find(r"100-CC0.*/(gong_0[1-2]|metal_0[1-2])")),
    "eliminated": ("المعركة", "إقصاء لاعب", find(r"single/(mystery_sting|nenadsimic)")),
    "powerup": ("الأدوات", "استعمال أداة مساعدة", find(r"interfaceSounds.*/(maximize_00[5-6]|glass_00[4-5])")),
    "coins": ("الأدوات", "ذهب / مكافأة", find(r"RPGsounds.*/handleCoins")),
    "victory": ("النهاية", "فوز", find(r"single/(fanfare_3|Win sound)|jingles_(SAX|STEEL)0[2-3]")),
    "defeat": ("النهاية", "خسارة", find(r"jingles_(PIZZA|NES)1[0-1]")),
}

manifest = []
for event, (group, label, srcs) in PLAN.items():
    for i, src in enumerate(srcs[:4], 1):
        long = event in ("victory", "defeat", "eliminated")
        info = render(src, OUT / f"{event}__{i}.ogg", peak=PEAK[group],
                      max_len=4.5 if long else 1.6, fade_out=0.4 if long else 0.02)
        manifest.append({"event": event, "group": group, "label": label, "n": i,
                         "source": str(src.relative_to(RAW)), **info})

# pieces cut from long recordings
med = RAW / "single" / "medieval-weapons-impacts.ogg"
for i, (s, e) in enumerate(segments(med, 0.3, 1.5, 6), 1):
    info = render(med, OUT / f"battle_impact__{i}.ogg", start=max(s - 0.02, 0), dur=e - s + 0.1, peak=-3.5)
    manifest.append({"event": "battle_impact", "group": "المعركة", "label": "ضربة سلاح / سقوط أرض",
                     "n": i, "source": f"single/medieval-weapons-impacts.ogg @ {s:.1f}s", **info})
crowd = RAW / "single" / "crowd_shouting.ogg"
for i, start in enumerate((2.0, 9.0, 16.0), 1):
    info = render(crowd, OUT / f"capture_cheer__{i}.ogg", start=start, dur=2.5, peak=-6.0, max_len=2.5, fade_out=0.6)
    manifest.append({"event": "capture_cheer", "group": "المعركة", "label": "هتاف بعد احتلال أرض",
                     "n": i, "source": f"single/crowd_shouting.ogg @ {start}s", **info})
drums = RAW / "single" / "horde_war_drums_by_william_hector.wav"
info = render(drums, OUT / "battle_drums__1.ogg", peak=-4.0)
manifest.append({"event": "battle_drums", "group": "الموسيقى", "label": "طبول الحرب (حلقة متكررة وقت المعارك)",
                 "n": 1, "source": "single/horde_war_drums_by_william_hector.wav", **info})
info = render(drums, OUT / "battle_start__1.ogg", dur=3.2, peak=-3.5, max_len=3.2, fade_out=0.5)
manifest.append({"event": "battle_start", "group": "المعركة", "label": "بداية المعارك",
                 "n": 1, "source": "single/horde_war_drums… (first 3 s)", **info})
for i, src in enumerate(find(r"100-CC0.*/gong_0[1-2]"), 2):
    info = render(src, OUT / f"battle_start__{i}.ogg", peak=-3.5, max_len=3.0, fade_out=0.8)
    manifest.append({"event": "battle_start", "group": "المعركة", "label": "بداية المعارك",
                     "n": i, "source": str(src.relative_to(RAW)), **info})

(OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(manifest), "candidates,", sum(m["bytes"] for m in manifest) // 1024, "KB")
missing = [e for e, (_, _, s) in PLAN.items() if not s]
print("events without candidates:", missing)
