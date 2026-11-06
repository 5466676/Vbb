# GAME_RULES — حرب العقول

**This file is authoritative.** If code and this file disagree, one of them is a bug.
Values marked *(config)* live in match settings and can be changed per room.
Decisions that clarified or changed the original brief are logged in `DECISIONS.md`.

---

## 1. Modes and player counts
- **Free-for-all (FFA):** 2–8 players.
- **Teams:** 2v2, 3v3, 4v4. Teammates share a colour family, cannot attack each other, and score as a team.
- Empty seats can be filled with bots (host option, three difficulties: easy / medium / hard).

## 2. Map
- A graph of territories (polygon + neighbour list).
- Territory count ≈ `players × 5`, same scaling for teams.
- Pre-generated templates per player count (2–8), stored as JSON in `backend/maps`.
  Every territory is reachable; bases are placed as far apart as possible.
- Territory values: normal **200**, base **1000**.
- Each player starts with one **base** (قلعة) with **3 towers** (lives).

## 3. Question types
- **MCQ:** 4 options, one correct, **10 s** timer. Options shuffled per player.
- **Numeric guess (تخمين):** number answer, **15 s** timer.

**Ranking rule (used everywhere):**
1. MCQ: correct before wrong; among correct, faster first. Wrong answers rank among themselves by speed.
2. Numeric: closer to the true value first, then faster.
3. No answer always ranks last.

## 4. Match flow

```
LOBBY → STARTING → EXPANSION (×N) → BATTLE (×R) → RESULTS
```

### 4.1 EXPANSION (فتح الأراضي) — repeat until no free territory is left
1. One numeric question to **all** players.
2. Rank everyone.
3. The **top half** of the ranking picks territories. Top half = `ceil(players / 2)`
   (5 players → top 3). 1st picks **2**, everyone else in the top half picks **1**.
4. **Picks are simultaneous:** all pickers choose at the same time within one **5 s** window.
   If two players pick the same territory, the better-ranked player gets it; the other
   player's pick falls back to an auto-pick (see 6).
   The 1st-ranked player submits both picks in the same window.
5. A pick must touch the player's own land if any adjacent free territory exists;
   otherwise any free territory is allowed.
6. On timeout (or a lost conflict) the server auto-picks a legal territory.
7. If fewer free territories remain than picks, they are handed out in rank order and the rest get nothing.

### 4.2 BATTLE (الحرب) — R rounds
R *(config)* defaults by player count:

| Players | 2 | 3 | 4 | 5–8 |
|---|---|---|---|---|
| R (default) | 6 | 5 | 4 | 3 |

(Raised for 2–3 players so small matches still last close to 8 minutes; see DECISIONS.md.
To be re-checked by the phase-2 simulation.)

Each round:
1. **Targeting (8 s):** every living player, at the same time, picks one enemy territory
   adjacent to their land, or chooses to **defend**. No choice = defend.
2. **Question:** one MCQ to all living players at once.
3. **Resolve every attack against pre-round ownership:**
   - The attacker wins if they rank above the territory's owner (the defender). Otherwise the defender holds.
   - If both are correct and their answer times differ by **< 0.5 s**, it's a **tie**.
     All ties of the round go to **one** shared numeric tiebreak question; only tied players answer,
     everyone else sees a spectator view. The tiebreak decides each tied pair.
   - Several successful attackers on the same territory: the best-ranked one takes it.
   - A captured normal territory changes owner and its value goes **+100**.
   - A successful hit on a base removes **one tower**. At 0 towers the base falls and the defender is eliminated.
   - A defender who holds gains **+100** on that territory's value.
   - A player who chose to defend and answered correctly gets **+50 bonus points**.
4. **Apply all changes at once**, in this order:
   1. normal-territory captures and holds,
   2. tower hits,
   3. fallen bases: the base and **every territory the eliminated player still owns after step 1**
      go to the player who took the base.
   Then animate and start the next round.

### 4.3 Score and end of match
- **Score = sum of owned territory values + bonus points.** In team modes the team score is the sum of its members.
- The match ends after R battle rounds, or when only one player (or team) remains.
- Highest score wins. Ties: most correct answers, then lowest average answer time.

## 5. Elimination and disconnects
- Eliminated players become spectators and can leave without penalty.
- On disconnect: **30 s** reconnect grace. Meanwhile a bot plays the seat (random answer, auto-pick).
  On reconnect the player receives the full current state.

## 6. Timing and fairness
- The correct answer is never sent before the deadline.
- Answer time is measured server-side from when the question was sent to that client,
  with a latency grace of at most **150 ms**.
- Late and duplicate answers are rejected.
