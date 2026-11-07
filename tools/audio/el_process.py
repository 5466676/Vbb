import json, re, subprocess, sys
from pathlib import Path
RAW, OUT = Path(sys.argv[1]), Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
LABEL = {"victory": ("فوز", -3.0), "capture_cheer": ("احتلال أرض: صيحة جيش (للجيوش غير الإسلامية)", -3.5),
         "countdown": ("عدّ تنازلي قبل المباراة", -3.5), "your_turn": ("دورك تهاجم!", -4.0),
         "tiebreak": ("سؤال الحسم (تعادل)", -3.5), "extra_turn": ("دور إضافي", -4.0), "defeat": ("خسارة", -4.0),
         "capture_islamic": ("جيش الفتوحات: خيل وجمال بالصحراء (+ «الله أكبر» مسجّلة)", -3.5),
         "capture_ayyubid": ("الأيوبيون: طبول وأبواق وسيوف (+ «الله أكبر» مسجّلة)", -3.5),
         "capture_ottoman": ("العثمانيون: فرقة المهتر (+ «الله أكبر» مسجّلة)", -3.5),
         "capture_crusader": ("الصليبيون: فرسان مدرّعين وبوق", -3.5),
         "capture_roman": ("الرومان: «ها!» جماعية وضرب على التروس", -3.5),
         "capture_pharaoh": ("الفراعنة: عربات حرب وبوق قرن", -3.5),
         "capture_mongol": ("المغول: خيالة وصيحات", -3.5),
         "capture_ww2": ("الحرب العالمية: هجوم مشاة", -3.5)}
def peak(p):
    log = subprocess.run(["ffmpeg","-hide_banner","-i",str(p),"-af","volumedetect","-f","null","-"],capture_output=True,text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", log).group(1))
GROUP = sys.argv[3] if len(sys.argv) > 3 else 'أصوات حرب (ElevenLabs)'
man = []
for item in json.loads((RAW/"prompts.json").read_text()):
    src = RAW/item["file"]; tmp = OUT/(src.stem+".wav"); dst = OUT/(src.stem+".ogg")
    label, pk = LABEL[item["event"]]
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(src),"-af",
      "silenceremove=start_periods=1:start_threshold=-55dB,areverse,silenceremove=start_periods=1:start_threshold=-55dB,afade=t=in:d=0.08,areverse",
      "-ac","1","-ar","44100",str(tmp)],check=True)
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(tmp),"-af",f"volume={pk-peak(tmp):.2f}dB",
      "-c:a","libvorbis","-q:a","5",str(dst)],check=True); tmp.unlink()
    d = float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",str(dst)],capture_output=True,text=True).stdout)
    man.append({"event":item["event"],"group":GROUP,"label":label,"n":item["n"],
                "source":"ElevenLabs: "+item["prompt"],"file":dst.name,"duration":round(d,2),"bytes":dst.stat().st_size})
(OUT/"manifest.json").write_text(json.dumps(man,ensure_ascii=False,indent=1),encoding="utf-8")
print(len(man), sum(m["bytes"] for m in man)//1024, "KB")
