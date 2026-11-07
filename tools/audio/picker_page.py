import base64, json, sys
from pathlib import Path
out = Path(sys.argv[1]); dst = Path(sys.argv[2])
m = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
events = {}
for x in m:
    e = events.setdefault(x["event"], {"id": x["event"], "group": x["group"], "label": x["label"], "c": []})
    e["c"].append({"n": x["n"], "d": x["duration"], "src": x["source"],
                   "u": "data:audio/ogg;base64," + base64.b64encode((out / x["file"]).read_bytes()).decode()})
order = ["الواجهة", "الردهة", "الأسئلة", "الخريطة", "المعركة", "الأدوات", "النهاية", "الموسيقى"]
data = sorted(events.values(), key=lambda e: order.index(e["group"]))
html = Path(sys.argv[3]).read_text(encoding="utf-8").replace("/*DATA*/[]", json.dumps(data, ensure_ascii=False))
dst.write_text(html, encoding="utf-8")
print(len(data), "events", round(dst.stat().st_size / 1e6, 2), "MB")
