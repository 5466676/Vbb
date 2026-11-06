# GAME_RULES — حرب العقول

**This file is authoritative.** If code and this file disagree, one of them is a bug.
Values marked *(config)* live in match settings and can be changed per room.
Values marked *(draft)* are first guesses that the phase-2 simulation will tune.
Decisions that clarified or changed the original brief are logged in `DECISIONS.md`.

---

## 1. Modes and player counts
- **Free-for-all (FFA):** 2–8 players.
- **Teams:** 2v2, 3v3, 4v4. Teammates share a colour family, cannot attack each other, and score as a team.
- Empty seats can be filled with bots (host option, three difficulties: easy / medium / hard).
- The game is played in **landscape** orientation.

## 2. Armies (الجيوش)
- Before a match every player picks an **army**. Two players may pick the same army;
  the player's seat colour (flag, borders, name bar) tells them apart.
- An army sets the player's **look**: the commander portrait, the base (castle) art for its era,
  the soldiers shown in attack animations, and its flag emblem.
- Each army also has **one small passive perk** (always on) and **one active ability**
  (usable once per match). Both are kept small so that no army is clearly stronger.
- Some armies are free; the rest are unlocked with gold earned by playing (cosmetic unlocks only,
  see economy rules in the brief §7). Perks are identical whether an army was free or unlocked.

### 2.1 Launch armies *(draft — perks to be tuned by simulation)*

| Army | Passive perk | Active ability (once per match) |
|---|---|---|
| الفتوحات الإسلامية | +50 bonus points for every capture | **فتح** — one extra pick in one expansion round |
| الأيوبيون | Base starts at value 1100 | **صمود** — the next successful hit on your base removes no tower |
| الصليبيون | A successful defence adds +150 (not +100) | **حصار** — your next successful hit on a base removes 2 towers |
| الرومان | At the start of the battle phase every territory you own gains +25 | **تشكيل السلحفاة** — you win your next tie as defender without a tiebreak |
| الفراعنة | Numeric questions give you +2 s on the timer | **الهرم** — +300 to the value of one of your territories |
| المغول | Your answer time counts 0.2 s faster when you attack | **اجتياح** — after a successful attack, attack again at once |
| العثمانيون | A capture adds +150 (not +100) | **الإنكشارية** — you win your next tie as attacker without a tiebreak |
| الحرب العالمية الثانية | Your first expansion pick may be any free territory | **إنزال جوي** — attack any enemy territory, even non-adjacent |

Later armies (not at launch): الآشوريون والبابليون، تدمر، الفرس، الإغريق، قرطاج، الأمويون،
العباسيون، المماليك، الأندلس، الفايكنغ، الساموراي، نابليون، الحرب العالمية الأولى، جيش المستقبل.
No present-day armies or current conflicts. No Nazi symbols.

## 3. Map
- A graph of territories (polygon + neighbour list).
- Territory count ≈ `players × 5`, same scaling for teams.
- **Map types**, chosen by **player vote** in the lobby (majority wins, ties broken at random;
  quick match picks at random):
  - **Fantasy** — invented continents, pre-generated per player count.
  - **World**, **Arab world**, **Levant (بلاد الشام)** — real geography. Real regions are grouped
    into `players × 5` territories per player count.
  - **Historical** — real geography with the borders of a past era (e.g. the time of the Crusades).
- For every map and player count: every territory is reachable and bases are as far apart as possible.
- Territory values: normal **200**, base **1000**.
- Each player starts with one **base** (قلعة) with **3 towers** (lives). The base art follows the player's army.

## 4. Question types
- **MCQ:** 4 options, one correct, **10 s** timer. Options shuffled per player.
- **Numeric guess (تخمين):** number answer, **15 s** timer.

**Ranking rule (used everywhere):**
1. MCQ: correct before wrong; among correct, faster first. Wrong answers rank among themselves by speed.
2. Numeric: closer to the true value first, then faster.
3. No answer always ranks last.

## 5. Power-ups (أدوات مساعدة)
Every player starts **every match** with **one of each**. They cannot be bought, carried over or earned with gold.

| Power-up | Effect |
|---|---|
| حذف إجابتين | Removes two wrong options from the current MCQ (for this player only). |
| تلميح | Shows a range that contains the answer of the current numeric question. |
| درع | Protects one of your territories: the next attack on it fails automatically. |
| مضاعفة | Your next successful capture or defence adds +200 instead of the normal amount. |

## 6. Match flow

```
LOBBY → STARTING → EXPANSION (×N, simultaneous) → BATTLE (×R rounds, turn-based) → RESULTS
```

### 6.1 EXPANSION (فتح الأراضي) — simultaneous, repeat until no free territory is left
1. One numeric question to **all** players at the same moment.
2. Rank everyone.
3. The **top half** of the ranking picks territories. Top half = `ceil(players / 2)`.
   1st picks **2**, everyone else in the top half picks **1**.
4. **Picks are simultaneous** within one **5 s** window. If two players pick the same territory,
   the better-ranked player gets it; the other gets an auto-pick.
5. A pick must touch the player's own land if any adjacent free territory exists;
   otherwise any free territory is allowed.
6. On timeout (or a lost conflict) the server auto-picks a legal territory.
7. If fewer free territories remain than picks, they are handed out in rank order.

### 6.2 BATTLE (الحرب) — turn-based duels, R rounds
In every round each living player (or team member) gets **one turn**. Turn order rotates:
round 1 starts with the lowest score, and each later round starts one seat further.

R *(config, draft)* by player count, chosen so a match stays near 8–12 minutes:

| Players | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| R | 7 | 5 | 4 | 3 | 3 | 2 | 2 |

A turn:
1. **Choose target (8 s):** the attacker picks one enemy territory adjacent to their land.
   On timeout the server picks one at random. If no target exists the turn is skipped.
2. **Duel question:** one MCQ to the **attacker and the defender only**. Everyone else watches.
3. **Resolve:**
   - The attacker wins if they rank above the defender; otherwise the defender holds.
   - Both correct with an answer-time gap **< 0.5 s** → tie → one numeric tiebreak question for the two of them.
   - Captured normal territory: changes owner, value **+100**.
   - Successful hit on a base: removes **one tower**. At 0 towers the base falls, the defender is
     eliminated, and the base and **all** their territories go to the attacker.
   - Defender holds: territory value **+100**.
4. Animate (army marches, short battle scene, flag raised or tower falls), then the next turn.

### 6.3 Score and end of match
- **Score = sum of owned territory values + bonus points.** In team modes the team score is the sum of its members.
- The match ends after R battle rounds, or when only one player (or team) remains.
- Highest score wins. Ties: most correct answers, then lowest average answer time.

## 7. Elimination and disconnects
- Eliminated players become spectators and can leave without penalty.
- On disconnect: **30 s** reconnect grace. Meanwhile a bot plays the seat (random answer, auto-pick,
  no power-ups or abilities). On reconnect the player receives the full current state.

## 8. Timing and fairness
- The correct answer is never sent before the deadline.
- Answer time is measured server-side from when the question was sent to that client,
  with a latency grace of at most **150 ms**.
- Late and duplicate answers are rejected.
