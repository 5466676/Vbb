# Map shapes (coastlines)

Each map template starts from a **land mask** (`*-mask.png`, 2048×1024, white = land).
The mask is the source of truth for the coastline:

1. The painted base (in `app/assets/maps/`) is generated from the guide image (`<name>.png`:
   white land, grey sea, black coast) and later clipped to this mask.
2. The phase-3 generator partitions the land of the mask into `players × 5` territories,
   adds sea links between islands, and places bases far apart.

| Name | Use |
|---|---|
| `fantasy-2p` … `fantasy-8p` | Fantasy continents per player count (4p lives in the original mockup) |
| `real-world` (used), `real-arab-world`, `real-levant` (not used — dropped) | Real geography from Natural Earth 1:50m land (public domain). The `.json` next to each holds the lon/lat window and projection. |
