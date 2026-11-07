import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:harb_al_oqool/core/socket.dart';
import 'package:harb_al_oqool/local/bots.dart';
import 'package:harb_al_oqool/local/engine.dart';
import 'package:harb_al_oqool/local/local_game.dart';

const _armies = ['islamic', 'ayyubid', 'crusader', 'roman', 'pharaoh', 'mongol', 'ottoman', 'ww2'];

/// Plays a whole match with every seat a bot, driving the engine directly (no timers).
Map<String, dynamic> _simulate(int n, int seed, {bool teams = false}) {
  final tpl = jsonDecode(File('assets/maps/templates/fantasy-${n}p.json').readAsStringSync()) as Map<String, dynamic>;
  final neighbors = {
    for (final t in tpl['territories'] as List) int.parse('${t['id']}'): [for (final x in t['neighbors'] as List) x as int],
  };
  final r = Random(seed);
  final setups = [
    for (var i = 0; i < n; i++) PlayerSetup(i, 'p$i', _armies[(i + seed) % 8], team: teams ? i ~/ (n ~/ 2) : null, isBot: true),
  ];
  final m = MatchState.create(
    mapId: tpl['id'] as String,
    neighbors: neighbors,
    bases: [for (final b in tpl['bases'] as List) b as int],
    setups: setups,
    teams: teams,
    rng: r,
  );
  final events = <Ev>[...m.start()];
  var q = 0;
  for (var step = 0; step < 20000 && m.phase != 'results'; step++) {
    if (m.pendingQuestion != null) {
      final kind = m.pendingQuestion!;
      events.addAll(m.provideQuestion(Question(
        id: 'q${q++}',
        kind: kind,
        text: '?',
        options: kind == 'mcq' ? const ['a', 'b', 'c', 'd'] : const [],
        correctIndex: kind == 'mcq' ? r.nextInt(4) : null,
        answer: kind == 'numeric' ? (r.nextInt(2000) - 100).toDouble() : null,
      )));
      continue;
    }
    final seat = r.nextInt(n);
    final level = const ['easy', 'medium', 'hard'][seat % 3];
    try {
      for (final extra in botExtras(m, seat, level, r)) {
        events.addAll(extra());
      }
    } on RuleError {
      // not legal now
    }
    final aq = m.active;
    try {
      if (aq != null) {
        final open = [for (final s in aq.participants) if (!aq.answers.containsKey(s)) s];
        if (open.isEmpty) continue;
        final s = open[r.nextInt(open.length)];
        if (r.nextDouble() < 0.1) {
          events.addAll(m.timeout(m.phaseId)); // someone never answers
        } else {
          final a = botAnswer(aq.question, aq.limitsMs[s]!, level, r);
          events.addAll(m.answer(s, choice: a.choice, value: a.value, elapsedMs: a.elapsedMs));
        }
      } else if (m.phase == 'expansion_picks') {
        final open = [for (final s in m.pickQuota.keys) if (!m.picks.containsKey(s)) s];
        if (open.isEmpty || r.nextDouble() < 0.1) {
          events.addAll(m.timeout(m.phaseId));
        } else {
          final s = open[r.nextInt(open.length)];
          events.addAll(m.pick(s, botPicks(m, s, m.pickQuota[s]!, r)));
        }
      } else if (m.phase == 'battle_target') {
        final t = botTarget(m, m.attacker!, level, r);
        events.addAll(t == null || r.nextDouble() < 0.1 ? m.timeout(m.phaseId) : m.chooseTarget(m.attacker!, t));
      }
    } on RuleError {
      // a bot tried something illegal: fine, the engine refused it
    }
  }
  return {'state': m, 'events': events};
}

void main() {
  test('engine: full bot matches end with a winner for 2-8 players and teams', () {
    for (var n = 2; n <= 8; n++) {
      for (var seed = 0; seed < 6; seed++) {
        final out = _simulate(n, seed * 31 + n);
        final m = out['state'] as MatchState;
        final events = out['events'] as List<Ev>;
        expect(m.phase, 'results', reason: '$n players, seed $seed');
        expect(m.freeTerritories(), isEmpty, reason: 'expansion fills the map');
        expect(events.where((e) => e.type == 'match_ended').length, 1);
        final rows = m.standings();
        expect(rows.length, n);
        expect(rows.first['team'], m.winnerTeam);
        // eliminated players own nothing; towers never go negative
        for (final p in m.players.where((p) => p.eliminated)) {
          expect(m.owned(p.seat), isEmpty);
        }
        expect(m.territories.values.every((t) => t.towers >= 0), isTrue);
      }
    }
    for (final n in [4, 6, 8]) {
      final m = _simulate(n, 7, teams: true)['state'] as MatchState;
      expect(m.phase, 'results');
      expect(m.players.map((p) => p.team).toSet().length, 2);
    }
  });

  test('engine rules: attacker must be right; a captured territory gains value', () {
    final m = MatchState.create(
      mapId: 't',
      neighbors: {0: [1], 1: [0, 2], 2: [1]},
      bases: [0, 2],
      setups: [PlayerSetup(0, 'a', 'roman'), PlayerSetup(1, 'b', 'mongol')],
      teams: false,
      rng: Random(1),
    );
    m.start();
    m.provideQuestion(Question(id: 'n', kind: 'numeric', text: '?', answer: 10));
    m.answer(0, value: 10, elapsedMs: 1000);
    m.answer(1, value: 50, elapsedMs: 900);
    expect(m.phase, 'expansion_picks');
    expect(m.pickQuota, {0: 2});
    m.pick(0, [1]);
    expect(m.territories[1]!.owner, 0);
    expect(m.phase, 'battle_target', reason: 'the map is full');
    final attacker = m.attacker!;
    final target = m.legalTargets(attacker).first;
    final before = m.territories[target]!.value;
    m.chooseTarget(attacker, target);
    m.provideQuestion(Question(id: 'm', kind: 'mcq', text: '?', options: const ['a', 'b', 'c', 'd'], correctIndex: 2));
    final defender = m.duel!.defender;
    m.answer(attacker, choice: 0, elapsedMs: 500); // wrong
    m.answer(defender, choice: 1, elapsedMs: 600); // also wrong: the defender holds
    expect(m.territories[target]!.owner, defender);
    expect(m.territories[target]!.value, greaterThan(before));
  });

  testWidgets('local game: a whole match against bots runs to the results', (tester) async {
    final g = LocalGame(name: 'سامي', army: 'roman', bots: const ['hard', 'easy', 'medium'], mapKind: 'fantasy');
    final types = <String>[];
    Map<String, dynamic>? ended;
    g.messages.listen((m) {
      types.add(m.type);
      if (m.type == 'match_ended') ended = m.payload;
      // play our seat badly but legally: answer every question we are in
      if (m.type == 'question' && m.payload['participant'] == true) {
        g.send('answer', {
          'question_id': m.payload['id'],
          if (m.payload['kind'] == 'mcq') 'choice': 0 else 'value': 1,
        });
      }
    });
    Object? err;
    await tester.runAsync(() async {
      try {
        await g.prepare();
      } catch (e, st) {
        err = '$e\n$st';
      }
    });
    expect(err, isNull);
    g.begin(); // timers run on the test's fake clock
    for (var i = 0; i < 3000 && ended == null; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(ended, isNotNull, reason: 'events seen: ${types.toSet()}');
    expect((ended!['standings'] as List).length, 4);
    expect(types, containsAll(['welcome', 'room_state', 'match_started', 'phase_changed', 'question', 'question_result', 'territory_claimed', 'battle_started']));
    expect(g.status, SocketStatus.online);
    await g.close();
  });
}
