# Art pipeline tools

Offline helpers for processing AI-generated art (need numpy, scipy, pillow).

| Script | What it does |
|---|---|
| `cutout.py SRC DST MAXSIZE` | Removes the white background of a fort / soldier / decoration image, crops and resizes it to a transparent PNG. |
| `seafix.py SRC DST WIDTH` | Replaces the grey margins of a painted map with the painting's own sea colour. |

Map paintings are made from the guide images in `backend/maps/shapes/`; check alignment by drawing
the matching `*-mask.png` coastline over the painting before accepting it.
