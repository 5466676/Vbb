# Taking a shout out of a film scene (personal use)

1. `find_takbir.py` (local Whisper) lists where «الله أكبر» is said.
2. Fetch ~14 s around each hit in full quality: `ffmpeg -ss <t> -i <video url> -t 14 -vn -ac 2 -ar 44100 clip.wav`.
3. Remove the music: `python -m demucs --two-stems=vocals -n htdemucs clip.wav` → `vocals.wav`.
4. Find the exact words with speech-to-text timestamps and cut them (`film_cuts.py` pattern).

Film audio is copyrighted: the clips stay out of this public repository.
