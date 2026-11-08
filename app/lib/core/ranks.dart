/// Ranks and levels (GAME_RULES §9): cosmetic progression, the same formula as the server.
library;

import 'dart:ui' show Color;

const xpPlayed = 10, xpPerCorrect = 5, xpWin = 30;

/// Lowest total experience for each rank, lowest first.
const ranks = [('E', 0), ('D', 200), ('C', 600), ('B', 1500), ('A', 3500), ('S', 7000)];

/// Bots show a rank that matches how well they play.
const botXp = {'easy': 250, 'medium': 900, 'hard': 3800};

int matchXp(int correct, bool won) => xpPlayed + xpPerCorrect * (correct < 0 ? 0 : correct) + (won ? xpWin : 0);

String rankOf(int xp) {
  var letter = ranks.first.$1;
  for (final (name, low) in ranks) {
    if (xp >= low) letter = name;
  }
  return letter;
}

int levelOf(int xp) => 1 + (xp < 0 ? 0 : xp) ~/ 100;

/// Progress (0..1) from the current rank to the next one (1 at S).
double rankProgress(int xp) {
  for (var i = 0; i < ranks.length - 1; i++) {
    final low = ranks[i].$2, high = ranks[i + 1].$2;
    if (xp < high) return ((xp - low) / (high - low)).clamp(0.0, 1.0);
  }
  return 1;
}

/// Experience still needed for the next rank (0 at S).
int toNextRank(int xp) {
  for (final (_, low) in ranks) {
    if (xp < low) return low - xp;
  }
  return 0;
}

/// Each rank glows in its own colour; S is gold.
Color rankColor(String r) => switch (r) {
  'S' => const Color(0xFFFFCF4A),
  'A' => const Color(0xFFFF5A7A),
  'B' => const Color(0xFFB06BFF),
  'C' => const Color(0xFF3FD0FF),
  'D' => const Color(0xFF3DFFA0),
  _ => const Color(0xFF8FB3C9),
};
