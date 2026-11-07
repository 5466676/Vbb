"""War cry candidates per army (ElevenLabs). Islamic armies: battle bed without voices (takbir is recorded)."""
import json, subprocess, sys
from pathlib import Path
OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
ARMIES = {
 "islamic": "Early Arab cavalry charge in the desert: horses and camels galloping on sand, swords drawn, war drums pounding, no voices, no words",
 "ayyubid": "Medieval Saracen army attack: big kettle drums and long brass horns, horses galloping, swords clashing on shields, no voices, no words",
 "ottoman": "Ottoman mehter military band: loud zurna shawm melody over huge kos drums and crashing cymbals, marching army, no voices",
 "crusader": "Medieval European knights charge: armored horses galloping, chain mail clanking, knights roar a wordless battle cry, a trumpet call",
 "roman": "Roman legion: soldiers shout a short unified 'Ha!' together and strike their shields with swords in rhythm, then a Roman cornu horn blast",
 "pharaoh": "Ancient Egyptian army charge: war chariot wheels rumbling, horses, soldiers shouting a wordless cry, a ram's horn and sistrum rattle",
 "mongol": "Mongol horde cavalry war cry: many horses galloping, riders shouting high-pitched wordless ululations, horse neighs, arrows whistling",
 "ww2": "World War Two infantry charge: soldiers shouting a wordless 'hurrah!' together as they run, boots on mud, distant artillery booms",
}
STYLE = ["", ", close up, loud and punchy", ", epic and cinematic with reverb across a valley", ", short and sharp, two seconds"]
man = []
for army, base in ARMIES.items():
    for i, extra in enumerate(STYLE, 1):
        f = OUT / f"capture_{army}__{i}.mp3"
        prompt = base + extra
        if not f.exists():
            body = json.dumps({"text": prompt, "duration_seconds": 3.5 if army == "ottoman" else 3.0, "prompt_influence": 0.55})
            r = subprocess.run(["curl", "-sS", "-f", "-X", "POST", "https://api.elevenlabs.io/v1/sound-generation",
                                "-H", "Content-Type: application/json", "-d", body, "-o", str(f)], capture_output=True, text=True)
            if r.returncode:
                print("FAIL", army, i, r.stderr.strip()); f.unlink(missing_ok=True); continue
        man.append({"event": f"capture_{army}", "n": i, "prompt": prompt, "file": f.name})
(OUT / "prompts.json").write_text(json.dumps(man, ensure_ascii=False, indent=1))
print(len(man), "generated")
