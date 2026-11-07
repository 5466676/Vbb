/// Offline port of the game engine (backend/app/engine/core.py), rule for rule.
/// docs/GAME_RULES.md is the authority; keep this in step with the Python engine.
library;

import 'dart:math';

class RuleError implements Exception {
  RuleError(this.message);
  final String message;
  @override
  String toString() => message;
}

// --- army perks (backend/app/engine/armies.py) ----------------------------------------------
const islamicCaptureBonus = 50;
const ayyubidBaseValue = 1100;
const crusaderHoldGain = 150;
const romanBattleStartGain = 25;
const pharaohNumericExtraMs = 2000;
const mongolAttackTimeBonusMs = 200;
const ottomanCaptureGain = 150;
const pharaohPyramidGain = 300;
const crusaderSiegeTowers = 2;

const defaultBattleRounds = {2: 19, 3: 13, 4: 9, 5: 8, 6: 6, 7: 5, 8: 4};

class Settings {
  int mcqMs = 10000;
  int numericMs = 15000;
  int pickMs = 5000;
  int targetMs = 8000;
  int latencyGraceMs = 150;
  int tieWindowMs = 500;
  int normalValue = 200;
  int baseValue = 1000;
  int captureGain = 100;
  int holdGain = 100;
  int doubleGain = 200;
}

class Question {
  Question({required this.id, required this.kind, required this.text, this.options = const [], this.correctIndex, this.answer, this.unit = ''});
  final String id;
  final String kind; // mcq | numeric
  final String text;
  final List<String> options;
  final int? correctIndex;
  final double? answer;
  final String unit;
}

class AnswerRecord {
  AnswerRecord(this.seat, {this.choice, this.value, required this.elapsedMs});
  final int seat;
  final int? choice;
  final double? value;
  final int elapsedMs;
  Map<String, dynamic> toJson() => {'choice': choice, 'value': value, 'elapsed_ms': elapsedMs};
}

class TerritoryState {
  TerritoryState(this.id, this.value);
  final int id;
  int? owner;
  int value;
  bool isBase = false;
  int towers = 0;
  bool shielded = false;
}

class PlayerState {
  PlayerState({required this.seat, required this.name, required this.army, required this.team, required this.isBot});
  final int seat;
  final String name;
  final String army;
  final int team;
  final bool isBot;
  bool connected = true;
  bool eliminated = false;
  int bonus = 0;
  List<String> powerups = ['remove_two', 'hint', 'shield', 'double'];
  bool abilityUsed = false;
  bool doubleArmed = false, fathArmed = false, sumudArmed = false, siegeArmed = false;
  bool turtleArmed = false, raidArmed = false, janissaryArmed = false, airdropArmed = false;
  bool firstPickDone = false;
  int answered = 0, correct = 0, totalAnswerMs = 0;
}

class ActiveQuestion {
  ActiveQuestion(this.question, this.participants, this.limitsMs);
  final Question question;
  final List<int> participants;
  final Map<int, int> limitsMs;
  final Map<int, AnswerRecord> answers = {};
}

class Duel {
  Duel(this.attacker, this.defender, this.territory);
  final int attacker, defender, territory;
}

class Ev {
  Ev(this.type, [this.data = const {}, this.to]);
  final String type;
  final Map<String, dynamic> data;
  final List<int>? to;
}

class PlayerSetup {
  PlayerSetup(this.seat, this.name, this.army, {this.team, this.isBot = false});
  final int seat;
  final String name;
  final String army;
  final int? team;
  final bool isBot;
}

const battlePhases = {'battle_target', 'battle_duel', 'battle_tiebreak'};

class MatchState {
  MatchState._(this.settings, this.mapId, this.neighbors, this.territories, this.players, this.battleRounds, this.baseTowers, this.rng);

  final Settings settings;
  final String mapId;
  final Map<int, List<int>> neighbors;
  final Map<int, TerritoryState> territories;
  final List<PlayerState> players;
  final int battleRounds;
  final int baseTowers;
  final Random rng;

  String phase = 'starting';
  int phaseId = 0;
  int expansionRound = 0;
  List<int> ranking = [];
  Map<int, int> pickQuota = {};
  Map<int, List<int>> picks = {};
  int battleRound = 0;
  List<int> turnQueue = [];
  List<int> roundOrder = []; // this round's attackers, in order
  int? attacker;
  Duel? duel;
  bool extraTurn = false;
  int firstSeat = 0;
  String? pendingQuestion;
  List<int> pendingParticipants = [];
  ActiveQuestion? active;
  int? winnerTeam;

  /// GAME_RULES §3: towers 5 for 2-4 players, 3 otherwise; teams share `team`.
  factory MatchState.create({
    required String mapId,
    required Map<int, List<int>> neighbors,
    required List<int> bases,
    required List<PlayerSetup> setups,
    required bool teams,
    Random? rng,
  }) {
    final s = Settings();
    final n = setups.length;
    if (n < 2 || n > 8) throw RuleError('a match needs 2-8 players');
    final terr = {for (final id in neighbors.keys) id: TerritoryState(id, s.normalValue)};
    final towers = n <= 4 ? 5 : 3;
    final players = <PlayerState>[];
    for (final p in setups..sort((a, b) => a.seat.compareTo(b.seat))) {
      players.add(PlayerState(seat: p.seat, name: p.name, army: p.army, team: teams && p.team != null ? p.team! : p.seat, isBot: p.isBot));
      terr[bases[p.seat]]!
        ..owner = p.seat
        ..isBase = true
        ..towers = towers
        ..value = p.army == 'ayyubid' ? ayyubidBaseValue : s.baseValue;
    }
    return MatchState._(s, mapId, {for (final e in neighbors.entries) e.key: (e.value.toSet().toList()..sort())}, terr, players,
        defaultBattleRounds[n]!, towers, rng ?? Random());
  }

  // ------------------------------------------------------------------ queries

  List<int> aliveSeats() => [for (final p in players) if (!p.eliminated) p.seat];
  List<int> owned(int seat) => [for (final t in territories.values) if (t.owner == seat) t.id];
  List<int> freeTerritories() => ([for (final t in territories.values) if (t.owner == null) t.id])..sort();
  bool allies(int a, int b) => players[a].team == players[b].team;
  int score(int seat) => territories.values.where((t) => t.owner == seat).fold(0, (a, t) => a + t.value) + players[seat].bonus;

  Map<int, int> teamScores() {
    final out = <int, int>{};
    for (final p in players) {
      out[p.team] = (out[p.team] ?? 0) + score(p.seat);
    }
    return out;
  }

  bool _touches(int seat, int tid) => neighbors[tid]!.any((n) => territories[n]!.owner == seat);

  List<int> legalPicks(int seat) {
    final free = freeTerritories();
    final p = players[seat];
    if (p.army == 'ww2' && !p.firstPickDone) return free;
    final adj = free.where((t) => _touches(seat, t)).toList();
    return adj.isEmpty ? free : adj;
  }

  List<int> legalTargets(int seat) {
    final enemy = [
      for (final t in territories.values)
        if (t.owner != null && !allies(t.owner!, seat) && !players[t.owner!].eliminated) t.id,
    ]..sort();
    if (players[seat].airdropArmed) return enemy;
    return enemy.where((t) => _touches(seat, t)).toList();
  }

  // ------------------------------------------------------------------ plumbing

  void _setPhase(String p, List<Ev> ev, [Map<String, dynamic> data = const {}]) {
    phase = p;
    phaseId++;
    ev.add(Ev('phase_changed', {'phase': p, 'phase_id': phaseId, ...data}));
  }

  void _requestQuestion(String kind, List<int> seats, List<Ev> ev) {
    pendingQuestion = kind;
    pendingParticipants = [...seats];
    active = null;
    ev.add(Ev('question_needed', {'kind': kind, 'participants': [...seats], 'phase_id': phaseId}));
  }

  int limitMs(String kind, int seat) {
    if (kind == 'mcq') return settings.mcqMs;
    return settings.numericMs + (players[seat].army == 'pharaoh' ? pharaohNumericExtraMs : 0);
  }

  // ------------------------------------------------------------------ actions

  List<Ev> start() {
    final ev = <Ev>[];
    if (phase != 'starting') throw RuleError('match already started');
    _startExpansionRound(ev);
    return ev;
  }

  List<Ev> provideQuestion(Question q) {
    final ev = <Ev>[];
    final kind = pendingQuestion;
    if (kind == null) throw RuleError('no question is needed now');
    if (q.kind != kind) throw RuleError('expected a $kind question');
    final seats = pendingParticipants;
    active = ActiveQuestion(q, [...seats], {for (final s in seats) s: limitMs(kind, s)});
    pendingQuestion = null;
    pendingParticipants = [];
    ev.add(Ev('question', {'id': q.id, 'participants': [...seats]}));
    return ev;
  }

  List<Ev> answer(int seat, {int? choice, double? value, required int elapsedMs}) {
    final ev = <Ev>[];
    final aq = active;
    if (aq == null || !{'expansion_question', 'battle_duel', 'battle_tiebreak'}.contains(phase)) {
      throw RuleError('no question is open');
    }
    if (!aq.participants.contains(seat)) throw RuleError('you are not answering this question');
    if (aq.answers.containsKey(seat)) throw RuleError('duplicate answer');
    if (elapsedMs < 0 || elapsedMs > aq.limitsMs[seat]! + settings.latencyGraceMs) throw RuleError('late answer');
    if (aq.question.kind == 'mcq') {
      if (choice == null || choice < 0 || choice > 3) throw RuleError('choice must be 0-3');
      aq.answers[seat] = AnswerRecord(seat, choice: choice, elapsedMs: elapsedMs);
    } else {
      if (value == null || !value.isFinite) throw RuleError('a numeric answer is required');
      aq.answers[seat] = AnswerRecord(seat, value: value, elapsedMs: elapsedMs);
    }
    ev.add(Ev('answer_locked', {'seat': seat}));
    if (aq.answers.length == aq.participants.length) _resolveQuestion(ev);
    return ev;
  }

  List<Ev> timeout(int forPhaseId) {
    final ev = <Ev>[];
    if (forPhaseId != phaseId) return ev;
    if ({'expansion_question', 'battle_duel', 'battle_tiebreak'}.contains(phase)) {
      if (active == null) return ev;
      _resolveQuestion(ev);
    } else if (phase == 'expansion_picks') {
      _resolvePicks(ev);
    } else if (phase == 'battle_target') {
      final targets = legalTargets(attacker!);
      if (targets.isEmpty) {
        ev.add(Ev('turn_skipped', {'seat': attacker}));
        _nextTurn(ev);
      } else {
        _startDuel(targets[rng.nextInt(targets.length)], ev, auto: true);
      }
    }
    return ev;
  }

  List<Ev> pick(int seat, List<int> chosen) {
    final ev = <Ev>[];
    if (phase != 'expansion_picks') throw RuleError('picks are not open');
    final quota = pickQuota[seat] ?? 0;
    if (quota == 0) throw RuleError('you have no picks this round');
    if (picks.containsKey(seat)) throw RuleError('picks already submitted');
    final unique = <int>[];
    for (final t in chosen) {
      if (!unique.contains(t)) unique.add(t);
    }
    final take = unique.take(quota).toList();
    if (take.any((t) => !territories.containsKey(t))) throw RuleError('unknown territory');
    picks[seat] = take;
    ev.add(Ev('pick_locked', {'seat': seat}));
    if (pickQuota.keys.every(picks.containsKey)) _resolvePicks(ev);
    return ev;
  }

  List<Ev> chooseTarget(int seat, int territory) {
    final ev = <Ev>[];
    if (phase != 'battle_target' || seat != attacker) throw RuleError('it is not your turn to attack');
    if (!legalTargets(seat).contains(territory)) throw RuleError('illegal target');
    _startDuel(territory, ev, auto: false);
    return ev;
  }

  List<Ev> usePowerup(int seat, String powerup, {int? territory}) {
    final ev = <Ev>[];
    final p = players[seat];
    if (p.eliminated || phase == 'starting' || phase == 'results') throw RuleError('power-ups are not available now');
    if (!p.powerups.contains(powerup)) throw RuleError('power-up already used');
    final aq = active;
    Map<String, dynamic> private = {};
    if (powerup == 'remove_two' || powerup == 'hint') {
      final want = powerup == 'remove_two' ? 'mcq' : 'numeric';
      if (aq == null || aq.question.kind != want || !aq.participants.contains(seat)) {
        throw RuleError('no matching question is open for you');
      }
      if (aq.answers.containsKey(seat)) throw RuleError('you already answered');
      final q = aq.question;
      if (powerup == 'remove_two') {
        final wrong = [for (var i = 0; i < 4; i++) if (i != q.correctIndex) i]..shuffle(rng);
        private = {'removed': (wrong.take(2).toList()..sort())};
      } else {
        final ans = q.answer ?? 0.0;
        final width = max(ans.abs() * 0.25, 2.0);
        final low = ans - rng.nextDouble() * width;
        private = {'low': low.floor(), 'high': (low + width).ceil()};
      }
    } else if (powerup == 'shield') {
      if (!battlePhases.contains(phase)) throw RuleError('shields are used during the battle');
      final t = territories[territory ?? -1];
      if (t == null || t.owner != seat) throw RuleError('shield one of your own territories');
      if (duel != null && duel!.territory == t.id) throw RuleError('this territory is already under attack');
      t.shielded = true;
      private = {'territory': t.id};
    } else if (powerup == 'double') {
      p.doubleArmed = true;
    }
    p.powerups.remove(powerup);
    ev.add(Ev('powerup_used', {'seat': seat, 'powerup': powerup}));
    if (private.isNotEmpty) ev.add(Ev('powerup_result', {'powerup': powerup, ...private}, [seat]));
    return ev;
  }

  List<Ev> useAbility(int seat, {int? territory}) {
    final ev = <Ev>[];
    final p = players[seat];
    if (p.eliminated || p.abilityUsed) throw RuleError('ability not available');
    final data = <String, dynamic>{'seat': seat, 'army': p.army};
    if (p.army == 'islamic') {
      if (phase == 'expansion_question') {
        p.fathArmed = true;
      } else if (phase == 'expansion_picks') {
        pickQuota[seat] = (pickQuota[seat] ?? 0) + 1;
        picks.remove(seat);
      } else {
        throw RuleError('فتح is used during expansion');
      }
    } else if (p.army == 'pharaoh') {
      if (phase == 'starting' || phase == 'results') throw RuleError('not now');
      final t = territories[territory ?? -1];
      if (t == null || t.owner != seat) throw RuleError('choose one of your territories');
      t.value += pharaohPyramidGain;
      data['territory'] = t.id;
    } else {
      if (!battlePhases.contains(phase)) throw RuleError('this ability is used during the battle');
      switch (p.army) {
        case 'ayyubid':
          p.sumudArmed = true;
        case 'crusader':
          p.siegeArmed = true;
        case 'roman':
          p.turtleArmed = true;
        case 'mongol':
          p.raidArmed = true;
        case 'ottoman':
          p.janissaryArmed = true;
        case 'ww2':
          p.airdropArmed = true;
      }
    }
    p.abilityUsed = true;
    ev.add(Ev('ability_used', data));
    return ev;
  }

  // ------------------------------------------------------------------ questions

  bool isCorrect(Question q, AnswerRecord? a) {
    if (a == null) return false;
    if (q.kind == 'mcq') return a.choice != null && a.choice == q.correctIndex;
    return a.value != null && q.answer != null && a.value == q.answer;
  }

  List<num> _sortKey(Question q, AnswerRecord? a, [int bonus = 0]) {
    if (a == null || (a.choice == null && a.value == null)) return [1, 0.0, 0];
    final t = a.elapsedMs - bonus;
    if (q.kind == 'mcq') return [0, isCorrect(q, a) ? 0.0 : 1.0, t];
    return [0, ((a.value ?? 0) - (q.answer ?? 0)).abs(), t];
  }

  int _cmp(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  List<int> _rank(Question q, List<int> seats, Map<int, AnswerRecord> answers, Map<int, int> bonus) {
    final indexed = [for (var i = 0; i < seats.length; i++) (i, seats[i])];
    indexed.sort((x, y) {
      final c = _cmp(_sortKey(q, answers[x.$2], bonus[x.$2] ?? 0), _sortKey(q, answers[y.$2], bonus[y.$2] ?? 0));
      return c != 0 ? c : x.$1.compareTo(y.$1); // stable
    });
    return [for (final e in indexed) e.$2];
  }

  void _resolveQuestion(List<Ev> ev) {
    final aq = active!;
    active = null;
    for (final r in aq.answers.values) {
      final p = players[r.seat];
      p.answered++;
      p.totalAnswerMs += r.elapsedMs;
      if (isCorrect(aq.question, r)) p.correct++;
    }
    final bonus = <int, int>{};
    if (duel != null && players[duel!.attacker].army == 'mongol') bonus[duel!.attacker] = mongolAttackTimeBonusMs;
    final order = _rank(aq.question, aq.participants, aq.answers, bonus);
    final q = aq.question;
    ev.add(Ev('question_result', {
      'id': q.id,
      'correct_index': q.correctIndex,
      'answer': q.answer,
      'ranking': order,
      'answers': {for (final e in aq.answers.entries) '${e.key}': e.value.toJson()},
    }));
    if (phase == 'expansion_question') {
      _openPicks(order, ev);
    } else if (phase == 'battle_duel') {
      _resolveDuel(aq, bonus, ev);
    } else if (phase == 'battle_tiebreak') {
      final d = duel!;
      final bothSilent = aq.answers.isEmpty;
      var attackerFirst = order.first == d.attacker && !bothSilent;
      if (attackerFirst && order.length == 2) {
        if (_cmp(_sortKey(q, aq.answers[d.attacker], bonus[d.attacker] ?? 0), _sortKey(q, aq.answers[d.defender])) == 0) {
          attackerFirst = false; // identical keys favour the defender
        }
      }
      _applyDuelOutcome(attackerFirst, ev, tiebreak: true);
    }
  }

  // ------------------------------------------------------------------ expansion (§6.1)

  void _startExpansionRound(List<Ev> ev) {
    expansionRound++;
    ranking = [];
    pickQuota = {};
    picks = {};
    _setPhase('expansion_question', ev, {'expansion_round': expansionRound});
    _requestQuestion('numeric', aliveSeats(), ev);
  }

  void _openPicks(List<int> order, List<Ev> ev) {
    ranking = order;
    final top = (order.length / 2).ceil();
    final quota = <int, int>{for (var i = 0; i < top; i++) order[i]: i == 0 ? 2 : 1};
    for (final p in players) {
      if (p.fathArmed && !p.eliminated) {
        quota[p.seat] = (quota[p.seat] ?? 0) + 1;
        p.fathArmed = false;
      }
    }
    pickQuota = quota;
    picks = {};
    _setPhase('expansion_picks', ev, {
      'deadline_ms': settings.pickMs,
      'quota': {for (final e in quota.entries) '${e.key}': e.value},
      'ranking': order,
    });
  }

  void _resolvePicks(List<Ev> ev) {
    final order = [for (final s in ranking) if (pickQuota.containsKey(s)) s];
    order.addAll(pickQuota.keys.where((s) => !order.contains(s)));
    for (final seat in order) {
      final requested = picks[seat] ?? const <int>[];
      for (var i = 0; i < pickQuota[seat]!; i++) {
        if (freeTerritories().isEmpty) break;
        final legal = legalPicks(seat);
        final want = i < requested.length ? requested[i] : null;
        final auto = want == null || !legal.contains(want);
        final tid = auto ? legal[rng.nextInt(legal.length)] : want;
        final t = territories[tid]!..owner = seat;
        players[seat].firstPickDone = true;
        ev.add(Ev('territory_claimed', {'seat': seat, 'territory': tid, 'auto': auto, 'value': t.value}));
      }
    }
    pickQuota = {};
    picks = {};
    if (freeTerritories().isNotEmpty) {
      _startExpansionRound(ev);
    } else {
      _startBattle(ev);
    }
  }

  // ------------------------------------------------------------------ battle (§6.2)

  void _startBattle(List<Ev> ev) {
    for (final p in players) {
      if (p.army == 'roman' && !p.eliminated) {
        for (final t in territories.values) {
          if (t.owner == p.seat) t.value += romanBattleStartGain;
        }
      }
    }
    final alive = aliveSeats()..sort((a, b) => score(a) != score(b) ? score(a).compareTo(score(b)) : a.compareTo(b));
    firstSeat = alive.first;
    battleRound = 0;
    turnQueue = [];
    ev.add(Ev('battle_started', {'rounds': battleRounds}));
    _nextTurn(ev);
  }

  Set<int> _aliveTeams() => {for (final p in players) if (!p.eliminated) p.team};

  void _buildQueue() {
    final seats = [for (final p in players) p.seat];
    final start = (seats.indexOf(firstSeat) + battleRound - 1) % seats.length;
    final order = [...seats.sublist(start), ...seats.sublist(0, start)];
    turnQueue = [for (final s in order) if (!players[s].eliminated) s];
    roundOrder = [...turnQueue];
  }

  void _nextTurn(List<Ev> ev) {
    duel = null;
    while (true) {
      if (_aliveTeams().length <= 1) return _finish(ev);
      int? seat;
      if (extraTurn && attacker != null) {
        extraTurn = false;
        if (!players[attacker!].eliminated) seat = attacker;
      }
      if (seat == null) {
        if (turnQueue.isEmpty) {
          battleRound++;
          if (battleRound > battleRounds) return _finish(ev);
          _buildQueue();
          ev.add(Ev('round_started', {'round': battleRound, 'order': [...roundOrder]}));
          continue;
        }
        seat = turnQueue.removeAt(0);
        if (players[seat].eliminated) continue;
      }
      final targets = legalTargets(seat);
      if (targets.isEmpty) {
        ev.add(Ev('turn_skipped', {'seat': seat}));
        continue;
      }
      attacker = seat;
      _setPhase('battle_target', ev, {'attacker': seat, 'round': battleRound, 'targets': targets, 'deadline_ms': settings.targetMs});
      return;
    }
  }

  void _startDuel(int tid, List<Ev> ev, {required bool auto}) {
    final att = attacker!;
    final a = players[att];
    final t = territories[tid]!;
    final dfd = t.owner!;
    if (a.airdropArmed) a.airdropArmed = false;
    duel = Duel(att, dfd, tid);
    ev.add(Ev('target_chosen', {'attacker': att, 'defender': dfd, 'territory': tid, 'auto': auto}));
    if (t.shielded) {
      t.shielded = false;
      ev.add(Ev('shield_blocked', {'territory': tid, 'defender': dfd}));
      _finishTurn(false, ev);
      return;
    }
    _setPhase('battle_duel', ev, {'attacker': att, 'defender': dfd, 'territory': tid});
    _requestQuestion('mcq', [att, dfd], ev);
  }

  void _resolveDuel(ActiveQuestion aq, Map<int, int> bonus, List<Ev> ev) {
    final d = duel!;
    final q = aq.question;
    final ra = aq.answers[d.attacker], rd = aq.answers[d.defender];
    final aOk = isCorrect(q, ra), dOk = isCorrect(q, rd);
    if (aOk && dOk) {
      final ta = ra!.elapsedMs - (bonus[d.attacker] ?? 0);
      final td = rd!.elapsedMs;
      if ((ta - td).abs() < settings.tieWindowMs) {
        final pa = players[d.attacker], pd = players[d.defender];
        if (pa.janissaryArmed && !pd.turtleArmed) {
          pa.janissaryArmed = false;
          ev.add(Ev('tie_won_by_ability', {'seat': d.attacker}));
          return _applyDuelOutcome(true, ev);
        }
        if (pd.turtleArmed && !pa.janissaryArmed) {
          pd.turtleArmed = false;
          ev.add(Ev('tie_won_by_ability', {'seat': d.defender}));
          return _applyDuelOutcome(false, ev);
        }
        pa.janissaryArmed = false;
        pd.turtleArmed = false;
        _setPhase('battle_tiebreak', ev, {'attacker': d.attacker, 'defender': d.defender, 'territory': d.territory});
        _requestQuestion('numeric', [d.attacker, d.defender], ev);
        return;
      }
      return _applyDuelOutcome(ta < td, ev);
    }
    _applyDuelOutcome(aOk, ev); // the attacker must answer correctly to win
  }

  void _applyDuelOutcome(bool attackerWon, List<Ev> ev, {bool tiebreak = false}) {
    final d = duel!;
    final t = territories[d.territory]!;
    final att = players[d.attacker], dfd = players[d.defender];
    if (attackerWon) {
      if (t.isBase) {
        if (dfd.sumudArmed) {
          dfd.sumudArmed = false;
          ev.add(Ev('base_guarded', {'territory': t.id, 'defender': dfd.seat}));
        } else {
          var dmg = 1;
          if (att.siegeArmed) {
            att.siegeArmed = false;
            dmg = crusaderSiegeTowers;
          }
          t.towers = max(0, t.towers - dmg);
          ev.add(Ev('tower_hit', {'territory': t.id, 'towers': t.towers, 'attacker': att.seat}));
          if (t.towers == 0) _baseFalls(att.seat, dfd.seat, t.id, ev);
        }
      } else {
        var gain = att.army == 'ottoman' ? ottomanCaptureGain : settings.captureGain;
        if (att.doubleArmed) {
          att.doubleArmed = false;
          gain = settings.doubleGain;
        }
        t
          ..owner = att.seat
          ..shielded = false
          ..value += gain;
        if (att.army == 'islamic') att.bonus += islamicCaptureBonus;
        ev.add(Ev('territory_captured', {'territory': t.id, 'attacker': att.seat, 'defender': dfd.seat, 'value': t.value}));
      }
    } else {
      var gain = dfd.army == 'crusader' ? crusaderHoldGain : settings.holdGain;
      if (dfd.doubleArmed) {
        dfd.doubleArmed = false;
        gain = settings.doubleGain;
      }
      t.value += gain;
      ev.add(Ev('territory_held', {'territory': t.id, 'defender': dfd.seat, 'value': t.value}));
    }
    ev.add(Ev('battle_result', {'attacker_won': attackerWon, 'tiebreak': tiebreak, 'territory': t.id}));
    _finishTurn(attackerWon, ev);
  }

  void _baseFalls(int attackerSeat, int defenderSeat, int baseId, List<Ev> ev) {
    final taken = <int>[];
    for (final t in territories.values) {
      if (t.owner == defenderSeat) {
        t
          ..owner = attackerSeat
          ..shielded = false;
        taken.add(t.id);
      }
    }
    territories[baseId]!
      ..isBase = false
      ..towers = 0;
    players[defenderSeat].eliminated = true;
    if (players[attackerSeat].army == 'islamic') players[attackerSeat].bonus += islamicCaptureBonus;
    ev.add(Ev('player_eliminated', {'seat': defenderSeat, 'by': attackerSeat, 'territories': taken}));
  }

  void _finishTurn(bool attackerWon, List<Ev> ev) {
    final att = players[attacker!];
    if (attackerWon && att.raidArmed) {
      att.raidArmed = false;
      extraTurn = true;
      ev.add(Ev('extra_turn', {'seat': att.seat}));
    }
    _nextTurn(ev);
  }

  // ------------------------------------------------------------------ end (§6.3)

  List<Map<String, dynamic>> standings() {
    double avg(PlayerState p) => p.answered == 0 ? double.infinity : p.totalAnswerMs / p.answered;
    final teams = <int, Map<String, num>>{};
    for (final p in players) {
      final t = teams.putIfAbsent(p.team, () => {'score': 0, 'correct': 0, 'ms': 0, 'answered': 0});
      t['score'] = t['score']! + score(p.seat);
      t['correct'] = t['correct']! + p.correct;
      t['ms'] = t['ms']! + p.totalAnswerMs;
      t['answered'] = t['answered']! + p.answered;
    }
    double tAvg(int team) => teams[team]!['answered'] == 0 ? double.infinity : teams[team]!['ms']! / teams[team]!['answered']!;
    final teamOrder = teams.keys.toList()
      ..sort((a, b) {
        final ta = teams[a]!, tb = teams[b]!;
        for (final c in [tb['score']!.compareTo(ta['score']!), tb['correct']!.compareTo(ta['correct']!), tAvg(a).compareTo(tAvg(b)), a.compareTo(b)]) {
          if (c != 0) return c;
        }
        return 0;
      });
    final rankOf = {for (var i = 0; i < teamOrder.length; i++) teamOrder[i]: i};
    final rows = [...players]
      ..sort((a, b) {
        for (final c in [
          rankOf[a.team]!.compareTo(rankOf[b.team]!),
          score(b.seat).compareTo(score(a.seat)),
          b.correct.compareTo(a.correct),
          avg(a).compareTo(avg(b)),
          a.seat.compareTo(b.seat),
        ]) {
          if (c != 0) return c;
        }
        return 0;
      });
    return [
      for (final p in rows)
        {
          'seat': p.seat,
          'team': p.team,
          'score': score(p.seat),
          'correct': p.correct,
          'avg_answer_ms': p.answered == 0 ? null : avg(p).round(),
          'eliminated': p.eliminated,
        },
    ];
  }

  void _finish(List<Ev> ev) {
    final rows = standings();
    winnerTeam = rows.first['team'] as int;
    attacker = null;
    duel = null;
    _setPhase('results', ev);
    ev.add(Ev('match_ended', {
      'winner_team': winnerTeam,
      'standings': rows,
      'team_scores': {for (final e in teamScores().entries) '${e.key}': e.value},
    }));
  }
}
