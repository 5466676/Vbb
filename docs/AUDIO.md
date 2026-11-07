# AUDIO — sound effects, music and the commentator

Everything here is client-side: the app plays sounds when **server events** arrive
(`docs/PROTOCOL.md`). The server knows nothing about audio.

## 1. Mix and rules

| bus | default volume | notes |
|---|---|---|
| music | 60 % | one track at a time; 1.5 s crossfade between tracks |
| effects | 90 % | short sounds, preloaded in a pool (low-end Android: no decoding while playing) |
| commentator | 100 % | music ducks −8 dB while a line plays |

- Settings: three sliders (music, effects, commentator) and a master mute. Saved per device.
- The app respects the phone's silent/Do-Not-Disturb mode for music and the commentator.
- Pause everything when the app goes to the background.
- **The commentator never speaks while a question is open**: it would distract and could sound like
  a hint. It talks only in the pauses the server already leaves for animations: match start (3 s),
  answer reveal (2.5 s), claims (1.5 s), duel result (3.5 s), match end.
- At most one line every 6 s; a queue keeps only the newest line of each priority
  (high: match start/end, elimination, last round; normal: attack, capture, defence; low: the rest).
  Low-priority lines are dropped rather than delayed. "Commentator: fewer lines" in settings plays only high.
- The commentator never names players (no text-to-speech at runtime, so nothing can be read out
  wrongly or offensively). It names **armies**, which are fixed recordings.
- Formats: OGG Vorbis, mono for effects and voice (44.1 kHz), stereo for music. Effects peak between
  −10 dBFS (UI) and −3.5 dBFS (battle); music −16 LUFS integrated; voice −16 LUFS.

## 2. Sound effects (event → sound)

Chosen in the sound picker (candidates are CC0). `id` is the file name in `app/assets/audio/sfx/`.

| id | when | trigger |
|---|---|---|
| `ui_tap`, `ui_back`, `ui_toggle`, `ui_error` | buttons, closing, switches, refused action | UI, `error` |
| `army_select` | choosing an army | `choose_army` sent |
| `ready` | ready / start pressed | `set_ready` |
| `match_found` | a player joins, quick match found | `room_state` (new seat), `match_found` |
| `question_show` | a question appears | `question` |
| `tick` | each of the last 5 seconds of a question | client timer from `time_ms` |
| `answer_locked` | I answered | `answer` sent |
| `other_answered` | someone else answered | `answer_locked` |
| `correct` / `wrong` | my answer at the reveal | `question_result` |
| `claim` | a territory is taken in expansion | `territory_claimed` |
| `march` | an army moves on the map (looped footsteps) | `target_chosen` animation |
| `battle_start` | battle phase begins | `battle_started` |
| `sword_swing`, `sword_clash`, `battle_impact` | duel scene | `battle_duel` / `battle_result` |
| `capture_<army>` | attacker wins a territory: a war cry per army (see below) | `territory_captured` |
| `base_guarded` | defence holds, shield blocks | `territory_held`, `base_guarded`, `shield_blocked` |
| `tower_hit` | a base loses a tower | `tower_hit` |
| `eliminated` | a player is out | `player_eliminated` |
| `powerup` | power-up or ability used | `powerup_used`, `ability_used` |
| `coins` | gold / reward | results screen |
| `victory` / `defeat` | end of match, from my point of view | `match_ended` |

### War cries on capture (owner's decision)

The game is about war across eras, so effects should sound like a battlefield (horns, war drums,
army shouts, swords), never like arcade or UI chimes.

| army | `capture_<army>` |
|---|---|
| islamic, ayyubid, ottoman | a group shouting «الله أكبر» — **recorded by real people** (the owner and 4–5 relatives on a phone; we clean it and layer it to sound like an army). Not AI: a generated takbir sounds wrong and the phrase deserves care |
| crusader, roman, mongol, pharaoh, ww2 | a wordless army war cry (ElevenLabs candidates). No "Deus vult": it is used by extremists today |

Recording tips: a quiet room, phone 1–2 m away, 3–4 short takes of «الله أكبر» together, plus one
take with everyone a bit farther away (gives depth when layered).

Sounds that no CC0 pack had (victory, war cries, countdown, your turn, tiebreak, extra turn, defeat)
were generated with ElevenLabs sound generation (`tools/audio/el_gen.py`, owner's key, personal use only).

## 3. Music

Generated with an AI music tool by the owner (licence must allow commercial use: on Suno or Udio
that means a paid plan at the time of generation). Keep the **same key and tempo** for the three
in-match tracks so they crossfade cleanly. All instrumental, no vocals.

| track | length | when |
|---|---|---|
| `menu` | 60–90 s loop | menus, lobby |
| `match_calm` | 90 s loop | expansion phase |
| `match_battle` | 90 s loop | battle phase (crossfade from calm on `battle_started`) |
| `final_rounds` | 30–45 s loop | last two battle rounds |
| `victory` / `defeat` | 5–8 s stinger | results screen |
| `battle_drums` (CC0, already picked from candidates) | 15 s loop | optional layer under `match_battle` |

Prompts (English works best in these tools; paste one per track):

- **menu** — *Instrumental cinematic Middle Eastern adventure theme, oud melody, qanun, ney flute,
  soft frame drums, warm strings, majestic and inviting, 90 BPM, D Hijaz, seamless loop, no vocals.*
- **match_calm** — *Instrumental strategy game background, light darbuka and riq rhythm, plucked oud
  ostinato, low strings, curious and focused, not distracting, 90 BPM, D Hijaz, seamless loop, no vocals.*
- **match_battle** — *Instrumental epic battle music, heavy war drums and darbuka, driving oud and
  strings, brass hits, tense and energetic, 90 BPM, D Hijaz, seamless loop, no vocals.*
- **final_rounds** — *Instrumental climax, fast taiko-like frame drums, rising strings, urgent,
  90 BPM double-time feel, D Hijaz, seamless loop, no vocals.*
- **victory** — *Short triumphant fanfare, brass and oud, big drum hit at the end, D major, 6 seconds.*
- **defeat** — *Short sad ending sting, solo ney flute over a low drone, D Hijaz, 5 seconds.*

Send the files as they come out (WAV or MP3); they get trimmed to clean loops, levelled and converted.

## 4. Commentator (المعلّق)

Modern Standard Arabic (understood everywhere), energetic sports-commentator style, one male
voice to start. Recorded by a person, or generated with a text-to-speech tool whose terms allow
commercial use (e.g. Google AI Studio speech generation, ElevenLabs paid plan). Each line is a
separate file `app/assets/audio/voice/<id>.ogg`; several variants of a line are played at random.

Style prompt for a TTS tool: *"Read in Arabic as an excited football commentator in a stadium:
fast, loud, clear, rising at the end."*

### General lines

| id | line | when |
|---|---|---|
| `start_1` / `start_2` / `start_3` | لِتبدأِ المعركة! · استعدّوا… انطلقنا! · ليبدأ صراع العقول! | `match_started` |
| `expansion_1` / `expansion_2` | الكلّ يتسابق على الأرض! · سؤالٌ جديد، والأرضُ للأسرع! | first `expansion_question` |
| `battle_1` / `battle_2` | انتهى التوسّع… وبدأت الحرب! · الآن تتكلّم السيوف! | `battle_started` |
| `duel_1` / `duel_2` | مبارزة! · وجهاً لوجه! | `battle_duel` (low) |
| `tiebreak_1` / `tiebreak_2` | تعادل! سؤالُ الحسم! · لا غالبَ ولا مغلوب… إلى سؤال الحسم! | `battle_tiebreak` |
| `capture_1` / `capture_2` / `capture_3` | سقطت الأرض! · احتلالٌ جديد! · ضربةٌ موفّقة! | `territory_captured` |
| `held_1` / `held_2` / `held_3` | صمدَ المدافع! · دفاعٌ أسطوري! · ارتدّ الهجوم! | `territory_held` |
| `tower_1` / `tower_2` | سقط برج! · القلعة تهتزّ! | `tower_hit` |
| `shield_1` | الدرع يصدّ الهجوم! | `shield_blocked` |
| `eliminated_1` / `eliminated_2` | خرجَ من المعركة! · سقطت القلعة… وانتهى الحلم! | `player_eliminated` (high) |
| `last_round_1` | الجولة الأخيرة! كلّ شيءٍ ممكن! | last `round_started` (high) |
| `comeback_1` | يا لها من عودة! | a player moves from last to first in standings (low) |
| `end_1` / `end_2` | انتهت المعركة! · وانتهى صراع العقول! | `match_ended` (high) |
| `you_win_1` / `you_lose_1` | النصرُ لك! · حظاً أوفر في المعركة القادمة! | results screen, my result |

### Lines per army (8 armies × 2)

| army | `attack_<army>` (normal, on `target_chosen`) | `win_<army>` (high, on `match_ended`) |
|---|---|---|
| islamic | جيشُ الفتوحات يتقدّم! | النصرُ لجيش الفتوحات! |
| ayyubid | الأيوبيّون يهاجمون! | النصرُ للأيوبيين! |
| crusader | الصليبيّون يزحفون! | النصرُ للصليبيين! |
| roman | الرومانُ يتقدّمون بتشكيلهم! | النصرُ للرومان! |
| pharaoh | جيشُ الفراعنة يهاجم! | النصرُ للفراعنة! |
| mongol | المغولُ يجتاحون! | النصرُ للمغول! |
| ottoman | العثمانيّون يهاجمون! | النصرُ للعثمانيين! |
| ww2 | جيشُ الحرب العالمية يتحرّك! | النصرُ لجيش الحرب العالمية! |

In team matches `win_<army>` is replaced by `team_win_1`: «الفريقُ المنتصر… يا له من تعاون!».

That is 45 files in total. Generate 2–3 sample lines with a few voices first and pick the voice
before recording the rest.

## 5. Credits

Sound effects: CC0 (public domain) — Kenney (www.kenney.nl), StarNinjas, William Hector,
Nenad Simic, "100 CC0 SFX" (OpenGameArt). Credit is optional for CC0 but we list it on the
credits screen. Music and voice: listed with the tool and plan used to make them.
