"""Generate war-themed sound candidates with the ElevenLabs sound-generation API (key injected by proxy)."""
import json, subprocess, sys
from pathlib import Path
OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
PLAN = {
 "victory": (4.0, [
   "Epic medieval army victory: two triumphant war horns blast together over big war drum hits, then a crowd of soldiers cheering, cinematic",
   "Short triumphant brass fanfare with heavy taiko war drums ending on a big cymbal crash, epic battle victory stinger",
   "Victorious army roar: hundreds of soldiers cheer and bang swords on shields, a war horn sounds at the end",
   "Cinematic Middle Eastern victory sting: powerful frame drums, a bright horn melody and a final big drum hit"]),
 "capture_cheer": (2.5, [
   "A large army of soldiers shouting a short battle cry together on a battlefield, deep male voices, no words",
   "Medieval soldiers roar as they storm a castle wall, swords clashing, a war horn in the distance",
   "Cavalry charge: horses galloping fast and riders yelling a war cry",
   "A crowd of warriors cheering after taking a fortress, banners flapping in the wind"]),
 "countdown": (4.0, [
   "Three slow heavy war drum hits, one second apart, building tension, then a short war horn blast",
   "Ancient battle countdown: deep drum, deeper drum, deepest drum, then an army shouts once",
   "Three metallic sword strikes on a shield one second apart, then a loud war horn",
   "Tense cinematic build: low drums getting faster for three beats, ending with a big impact and horn"]),
 "your_turn": (1.5, [
   "A single short low war horn call",
   "One deep war drum hit followed by a sword being drawn from its sheath",
   "Two quick battle drum hits and a metallic shing",
   "A commander's short sharp horn signal on a battlefield"]),
 "tiebreak": (2.5, [
   "Tense cinematic riser with war drums and a sharp sword unsheathing at the end",
   "Heartbeat-like slow war drums, suspenseful, two warriors facing each other",
   "Two swords clash once and grind against each other, tense silence, deep drum hit",
   "Ominous low horn and rolling war drums, dramatic duel tension"]),
 "extra_turn": (1.5, [
   "Quick sword unsheathing followed by a short battle shout from one warrior",
   "A horse neighs and starts galloping",
   "A rallying war horn short burst and a drum hit, energetic",
   "Soldiers shout 'hah!' together once and stamp the ground"]),
 "defeat": (3.5, [
   "Sad distant war horn over a slow low drum, an army retreating, mournful",
   "A broken sword falls on stone, then a slow sad horn note fades out",
   "Defeated army: a single slow mournful horn and a fading drum roll, wind blowing",
   "Low cinematic boom then a lonely sad flute note, battle lost"]),
}
manifest = []
for ev, (dur, prompts) in PLAN.items():
    for i, p in enumerate(prompts, 1):
        f = OUT / f"{ev}__{i}.mp3"
        if not f.exists():
            body = json.dumps({"text": p, "duration_seconds": dur, "prompt_influence": 0.5})
            r = subprocess.run(["curl", "-sS", "-f", "-X", "POST", "https://api.elevenlabs.io/v1/sound-generation",
                                "-H", "Content-Type: application/json", "-d", body, "-o", str(f)], capture_output=True, text=True)
            if r.returncode:
                print("FAIL", ev, i, r.stderr.strip()); f.unlink(missing_ok=True); continue
        manifest.append({"event": ev, "n": i, "prompt": p, "file": f.name})
        print("ok", f.name)
(OUT / "prompts.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
