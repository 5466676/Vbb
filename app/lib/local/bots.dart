/// Offline port of backend/app/bots/simple.py. Bots see the answer; skill is simulated.
library;

import 'dart:math';

import 'engine.dart';

class BotProfile {
  const BotProfile(this.pCorrect, this.numericSigma, this.minMs, this.maxMs, this.extras);
  final double pCorrect;
  final double numericSigma;
  final int minMs;
  final int maxMs;
  final bool extras;
}

const botProfiles = {
  'easy': BotProfile(0.45, 0.45, 3500, 9000, true),
  'medium': BotProfile(0.65, 0.25, 2500, 7500, true),
  'hard': BotProfile(0.85, 0.10, 1500, 5500, true),
};

int randInt(Random r, int lo, int hi) => lo + r.nextInt(hi - lo + 1);

double _gauss(Random r) {
  // Box-Muller
  final u1 = max(r.nextDouble(), 1e-12), u2 = r.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

/// (choice or value, elapsed ms)
({int? choice, double? value, int elapsedMs}) botAnswer(Question q, int limitMs, String level, Random r) {
  final p = botProfiles[level]!;
  final elapsed = min(limitMs, randInt(r, p.minMs, p.maxMs));
  if (q.kind == 'mcq') {
    if (r.nextDouble() < p.pCorrect) return (choice: q.correctIndex, value: null, elapsedMs: elapsed);
    final wrong = [for (var i = 0; i < 4; i++) if (i != q.correctIndex) i];
    return (choice: wrong[r.nextInt(wrong.length)], value: null, elapsedMs: elapsed);
  }
  final truth = q.answer ?? 0.0;
  final spread = max(truth.abs() * p.numericSigma, 1.0);
  return (choice: null, value: (truth + _gauss(r) * spread).roundToDouble(), elapsedMs: elapsed);
}

List<int> botPicks(MatchState s, int seat, int count, Random r) {
  final legal = [...s.legalPicks(seat)]..shuffle(r);
  return legal.take(min(count, legal.length)).toList();
}

int? botTarget(MatchState s, int seat, String level, Random r) {
  final options = s.legalTargets(seat);
  if (options.isEmpty) return null;
  if (level == 'hard') {
    // a base that is nearly down, otherwise the most valuable target
    int score(int tid) {
      final t = s.territories[tid]!;
      return (t.isBase && t.towers == 1 ? 1000000 : 0) + t.value;
    }

    return options.reduce((a, b) => score(b) > score(a) ? b : a);
  }
  return options[r.nextInt(options.length)];
}

/// Occasionally use a power-up or the army ability when legal right now.
List<List<Ev> Function()> botExtras(MatchState s, int seat, String level, Random r) {
  if (!botProfiles[level]!.extras || r.nextDouble() > 0.25) return [];
  final p = s.players[seat];
  final out = <List<Ev> Function()>[];
  final aq = s.active;
  if (aq != null && aq.participants.contains(seat) && !aq.answers.containsKey(seat)) {
    if (aq.question.kind == 'mcq' && p.powerups.contains('remove_two')) out.add(() => s.usePowerup(seat, 'remove_two'));
    if (aq.question.kind == 'numeric' && p.powerups.contains('hint')) out.add(() => s.usePowerup(seat, 'hint'));
  }
  final mine = s.owned(seat);
  if (battlePhases.contains(s.phase) && mine.isNotEmpty) {
    if (p.powerups.contains('double')) out.add(() => s.usePowerup(seat, 'double'));
    final busy = s.duel?.territory;
    final safe = mine.where((t) => t != busy).toList();
    if (p.powerups.contains('shield') && safe.isNotEmpty) {
      final t = safe[r.nextInt(safe.length)];
      out.add(() => s.usePowerup(seat, 'shield', territory: t));
    }
  }
  if (!p.abilityUsed) {
    if (p.army == 'islamic' && (s.phase == 'expansion_question' || s.phase == 'expansion_picks')) {
      out.add(() => s.useAbility(seat));
    } else if (p.army == 'pharaoh' && mine.isNotEmpty && s.phase != 'results') {
      final t = mine[r.nextInt(mine.length)];
      out.add(() => s.useAbility(seat, territory: t));
    } else if (p.army != 'islamic' && p.army != 'pharaoh' && battlePhases.contains(s.phase)) {
      out.add(() => s.useAbility(seat));
    }
  }
  return out;
}
