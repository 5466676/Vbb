# Audio tools

Offline helpers for picking sound effects (see `docs/AUDIO.md`).

- `build_candidates.py <raw_dir> <out_dir>` — cuts, trims, levels and converts CC0 source packs into
  numbered candidates per game event (`manifest.json`). `..._round2.py` is the second round.
- `picker_page.py <out_dir> <page.html> <template.html>` — builds the listening page (audio embedded)
  where the owner picks one candidate per event. Picks are read back and copied to
  `app/assets/audio/sfx/<event>.ogg`, with the source in `app/assets/audio/CREDITS.json`.

Needs `ffmpeg`. Source packs come from OpenGameArt (CC0 only) and are not committed.
