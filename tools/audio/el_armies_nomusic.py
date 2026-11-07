"""War cry candidates per army (ElevenLabs). Islamic armies: battle bed without voices (takbir is recorded)."""
import json, subprocess, sys
from pathlib import Path
OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
NO_MUSIC = ", no music, no drums, no horns, no instruments, no voices"
ARMIES = {
 "islamic": "Early Arab cavalry charge in the desert: horses and camels galloping on sand, swords drawn from sheaths, armor rattling" + NO_MUSIC,
 "ayyubid": "Medieval heavy cavalry charge: many horses galloping, swords clashing on round shields, chain mail rattling" + NO_MUSIC,
 "ottoman": "A large disciplined army advancing: thousands of marching footsteps, horses, swords drawn together, banners flapping in the wind" + NO_MUSIC,
}
STYLE = ["", ", close up, loud and punchy", ", epic and cinematic with reverb across a valley", ", short and sharp, two seconds"]
man = []
for army, base in ARMIES.items():
    for i, extra in enumerate(STYLE, 1):
        f = OUT / f"nomusic_{army}__{i}.mp3"
        prompt = base + extra
        if not f.exists():
            body = json.dumps({"text": prompt, "duration_seconds": 3.0, "prompt_influence": 0.55})
            r = subprocess.run(["curl", "-sS", "-f", "-X", "POST", "https://api.elevenlabs.io/v1/sound-generation",
                                "-H", "Content-Type: application/json", "-d", body, "-o", str(f)], capture_output=True, text=True)
            if r.returncode:
                print("FAIL", army, i, r.stderr.strip()); f.unlink(missing_ok=True); continue
        man.append({"event": f"capture_{army}", "n": i, "prompt": prompt, "file": f.name})
(OUT / "prompts.json").write_text(json.dumps(man, ensure_ascii=False, indent=1))
print(len(man), "generated")
