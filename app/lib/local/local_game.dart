import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../core/map_template.dart';
import '../core/socket.dart';
import 'bots.dart';
import 'engine.dart';

const localPlayerId = 'local-me';

/// Bot names (fixed per seat) — same spirit as the server's bots.
const _botNames = ['صلاح', 'خالد', 'طارق', 'قطز', 'بيبرس', 'عقبة', 'سيف'];
const _armies = ['islamic', 'ayyubid', 'crusader', 'roman', 'pharaoh', 'mongol', 'ottoman', 'ww2'];

// pauses for animations before the next window opens (same as the server's room actor)
const _startPause = 3000, _revealPause = 2500, _claimPause = 1500, _duelPause = 3500;
const _networkSlack = 600;

/// A whole match against bots inside the app: no server, no internet.
/// Speaks the same messages as the server (docs/PROTOCOL.md), so the screens do not change.
class LocalGame implements GameTransport {
  LocalGame({
    required this.name,
    required this.army,
    required this.bots,
    required this.mapKind,
    this.teams = false,
    this.categories = const [],
  });

  final List<String> categories; // empty = all

  final String name;
  final String army;
  final List<String> bots; // difficulty per bot
  final String mapKind; // fantasy | world
  final bool teams;

  final _messages = StreamController<ServerMessage>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  final _rnd = Random();
  final _timers = <String, Timer>{};
  @override
  SocketStatus status = SocketStatus.offline;

  late MatchState _m;
  late MapTemplate _template;
  late List<Map<String, dynamic>> _seats; // room_state seats
  final _used = <String>{};
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _pool = [];
  DateTime? _questionSentAt;
  bool _closed = false;

  @override
  Stream<ServerMessage> get messages => _messages.stream;
  @override
  Stream<SocketStatus> get statusStream => _status.stream;

  void _out(String type, Map<String, dynamic> payload) {
    if (_closed) return;
    // a microtask so listeners never run inside our own call stack
    scheduleMicrotask(() => _messages.add(ServerMessage(type, payload)));
  }

  @override
  Future<void> connect() async {
    await prepare();
    begin();
  }

  /// Loads the map and the bundled questions (the only asynchronous part).
  Future<void> prepare() async {
    _all = [
      for (final q in jsonDecode(await rootBundle.loadString('assets/questions/solo.json')) as List)
        (q as Map).cast<String, dynamic>(),
    ]..shuffle(_rnd);
    _pool = categories.isEmpty ? _all : [for (final q in _all) if (categories.contains(q['category'])) q];
    final n = bots.length + 1;
    _template = await MapTemplate.load('$mapKind-${n}p');
  }

  /// Sets up the match and starts the timers.
  void begin() {
    status = SocketStatus.online;
    _status.add(status);
    _out('welcome', {'player_id': localPlayerId, 'name': name, 'server_time_ms': DateTime.now().millisecondsSinceEpoch});
    final n = bots.length + 1;
    final teamSize = teams ? n ~/ 2 : 0;
    final setups = <PlayerSetup>[
      PlayerSetup(0, name.isEmpty ? 'أنا' : name, army, team: teams ? 0 : null),
      for (var i = 0; i < bots.length; i++)
        PlayerSetup(i + 1, _botNames[i % _botNames.length], _armies[_rnd.nextInt(_armies.length)],
            team: teams ? (i + 1) ~/ teamSize : null, isBot: true),
    ];
    _seats = [
      for (final s in setups)
        {
          'seat': s.seat,
          'player_id': s.isBot ? null : localPlayerId,
          'name': s.name,
          'army': s.army,
          'ready': true,
          'bot': s.isBot ? bots[s.seat - 1] : null,
          'connected': true,
        },
    ];
    _m = MatchState.create(
      mapId: _template.id,
      neighbors: {
        for (final t in _template.territories) t.id: [...t.neighbors],
        // sea routes are links like land borders (the engine treats them as neighbours)
      },
      bases: _template.bases,
      setups: setups,
      teams: teams,
      rng: _rnd,
    );
    for (final s in _template.seaLinks) {
      _m.neighbors[s.a] = {..._m.neighbors[s.a]!, s.b}.toList()..sort();
      _m.neighbors[s.b] = {..._m.neighbors[s.b]!, s.a}.toList()..sort();
    }
    _out('room_state', _roomState('playing'));
    _out('match_started', {
      'map_id': _template.id,
      'map_kind': mapKind,
      'mode': teams ? 'teams' : 'ffa',
      'rounds': _m.battleRounds,
      'base_towers': _m.baseTowers,
      'players': [
        for (final p in _m.players) {'seat': p.seat, 'name': p.name, 'army': p.army, 'team': p.team, 'bot': p.isBot},
      ],
      'bases': _template.bases.take(n).toList(),
    });
    _after(_m.start(), forcePause: _startPause);
  }

  Map<String, dynamic> _roomState(String status) => {
        'code': 'LOCAL',
        'host': localPlayerId,
        'status': status,
        'settings': {'mode': teams ? 'teams' : 'ffa', 'max_players': _seats.length},
        'seats': _seats,
        'votes': <String, String>{},
        'quick': false,
      };

  // ------------------------------------------------------------------ client messages

  @override
  void send(String type, [Map<String, dynamic> p = const {}]) {
    if (_closed) return;
    try {
      switch (type) {
        case 'answer':
          final q = _m.active;
          if (q == null || q.question.id != p['question_id']) return;
          final elapsed = DateTime.now().difference(_questionSentAt ?? DateTime.now()).inMilliseconds;
          _after(_m.answer(0, choice: p['choice'] as int?, value: (p['value'] as num?)?.toDouble(), elapsedMs: elapsed));
        case 'pick_territory':
          if (_m.phase != 'expansion_picks') return;
          // the client sends its whole selection each time; lock it once complete
          final chosen = [for (final t in (p['territories'] as List? ?? [])) t as int];
          if (chosen.length >= (_m.pickQuota[0] ?? 0)) _after(_m.pick(0, chosen));
          _lastPicks = chosen;
        case 'choose_target':
          _after(_m.chooseTarget(0, p['territory'] as int));
        case 'use_powerup':
          _after(_m.usePowerup(0, p['powerup'] as String, territory: p['territory'] as int?));
        case 'use_ability':
          _after(_m.useAbility(0, territory: p['territory'] as int?));
        case 'resync':
          _out('full_state', _fullState());
        case 'leave_room':
          _out('left_room', {'code': 'LOCAL'});
          close();
      }
    } on RuleError catch (e) {
      _out('error', {'code': 'rule', 'message': e.message});
    }
  }

  List<int> _lastPicks = [];

  // ------------------------------------------------------------------ engine events

  void _after(List<Ev> events, {int forcePause = 0}) {
    if (_closed) return;
    final types = {for (final e in events) e.type};
    var pause = forcePause;
    if (types.contains('question_result')) pause = max(pause, _revealPause);
    if (types.contains('territory_claimed')) pause = max(pause, _claimPause);
    if (types.contains('battle_result') || types.contains('shield_blocked')) pause = max(pause, _duelPause);
    if (types.contains('phase_changed')) {
      for (final k in _timers.keys.where((k) => k.startsWith('phase:') || k.startsWith('bot:') || k == 'provide').toList()) {
        _timers.remove(k)?.cancel();
      }
    }
    for (final e in events) {
      _emit(e, pause);
    }
    if (_m.phase == 'results') {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
      return;
    }
    if (_m.pendingQuestion != null && !_timers.containsKey('provide')) {
      _schedule('provide', pause, _provide);
    } else if (_m.phase == 'expansion_picks') {
      final id = _m.phaseId;
      _schedule('phase:$id', pause + _m.settings.pickMs, () {
        // whatever the player selected so far counts
        if (!_m.picks.containsKey(0) && (_m.pickQuota[0] ?? 0) > 0 && _lastPicks.isNotEmpty) {
          try {
            _after(_m.pick(0, _lastPicks));
          } on RuleError {
            // ignore
          }
          if (_m.phaseId != id) return;
        }
        _after(_m.timeout(id));
      });
      _lastPicks = [];
    } else if (_m.phase == 'battle_target') {
      final id = _m.phaseId;
      _schedule('phase:$id', pause + _m.settings.targetMs, () => _after(_m.timeout(id)));
    }
    _scheduleBots(pause);
  }

  void _emit(Ev e, int pause) {
    if (e.to != null && !e.to!.contains(0)) return; // private to a bot
    switch (e.type) {
      case 'question_needed' || 'match_started':
        return;
      case 'phase_changed':
        final d = {...e.data, 'opens_in_ms': pause};
        if (e.data['phase'] == 'expansion_picks') d['deadline_ms'] = _m.settings.pickMs;
        if (e.data['phase'] == 'battle_target') d['deadline_ms'] = _m.settings.targetMs;
        _out('phase_changed', d);
      case 'question':
        final aq = _m.active!;
        final q = aq.question;
        _questionSentAt = DateTime.now();
        _out('question', {
          'id': q.id,
          'kind': q.kind,
          'text': q.text,
          'unit': q.unit,
          'category': q.category,
          'options': q.kind == 'mcq' ? q.options : <String>[],
          'participant': aq.participants.contains(0),
          'participants': aq.participants,
          'time_ms': aq.limitsMs[0] ?? aq.limitsMs.values.reduce(max),
          'phase_id': _m.phaseId,
        });
        final longest = aq.limitsMs.values.reduce(max);
        final id = _m.phaseId;
        _schedule('phase:$id', longest + _m.settings.latencyGraceMs + _networkSlack, () => _after(_m.timeout(id)));
      default:
        _out(e.type, e.data);
    }
  }

  void _provide() {
    final kind = _m.pendingQuestion;
    if (kind == null) return;
    // the chosen categories may have no question of this kind: then any category will do
    final pool = _pool.any((x) => x['kind'] == kind) ? _pool : _all;
    var q = pool.firstWhere((x) => x['kind'] == kind && !_used.contains(x['id']), orElse: () => {});
    if (q.isEmpty) {
      _used.removeWhere((id) => pool.any((x) => x['id'] == id && x['kind'] == kind)); // ran out: reuse
      q = pool.firstWhere((x) => x['kind'] == kind);
    }
    _used.add(q['id'] as String);
    _after(_m.provideQuestion(Question(
      id: q['id'] as String,
      kind: kind,
      text: q['text'] as String,
      options: [for (final o in (q['options'] as List? ?? [])) '$o'],
      correctIndex: q['correct_index'] as int?,
      answer: (q['answer'] as num?)?.toDouble(),
      unit: (q['unit'] ?? '') as String,
      category: (q['category'] ?? '') as String,
    )));
  }

  void _schedule(String name, int ms, void Function() fn) {
    _timers.remove(name)?.cancel();
    _timers[name] = Timer(Duration(milliseconds: max(0, ms)), () {
      _timers.remove(name);
      if (_closed) return;
      try {
        fn();
      } on RuleError {
        // a race with the player's own action: harmless
      }
    });
  }

  void _scheduleBots(int pause) {
    for (final p in _m.players) {
      if (!p.isBot || p.eliminated) continue;
      final level = bots[p.seat - 1];
      final name = 'bot:${p.seat}:${_m.phaseId}';
      if (_timers.containsKey(name)) continue;
      final prof = botProfiles[level]!;
      int? delay;
      final aq = _m.active;
      if (aq != null && aq.participants.contains(p.seat) && !aq.answers.containsKey(p.seat)) {
        delay = min(aq.limitsMs[p.seat]! - 200, randInt(_rnd, prof.minMs, prof.maxMs));
      } else if (_m.phase == 'expansion_picks' && _m.pickQuota.containsKey(p.seat) && !_m.picks.containsKey(p.seat)) {
        delay = pause + randInt(_rnd, 800, 3000);
      } else if (_m.phase == 'battle_target' && _m.attacker == p.seat) {
        delay = pause + randInt(_rnd, 1000, 3000);
      }
      if (delay != null) {
        final phaseId = _m.phaseId;
        _schedule(name, delay, () => _botAct(p.seat, level, phaseId));
      }
    }
  }

  void _botAct(int seat, String level, int phaseId) {
    if (_m.phaseId != phaseId) return;
    for (final extra in botExtras(_m, seat, level, _rnd)) {
      try {
        _after(extra());
      } on RuleError {
        // not legal right now
      }
      if (_m.phaseId != phaseId) return;
    }
    final aq = _m.active;
    if (aq != null && aq.participants.contains(seat) && !aq.answers.containsKey(seat)) {
      final a = botAnswer(aq.question, aq.limitsMs[seat]!, level, _rnd);
      _after(_m.answer(seat, choice: a.choice, value: a.value, elapsedMs: a.elapsedMs));
    } else if (_m.phase == 'expansion_picks' && _m.pickQuota.containsKey(seat) && !_m.picks.containsKey(seat)) {
      _after(_m.pick(seat, botPicks(_m, seat, _m.pickQuota[seat]!, _rnd)));
    } else if (_m.phase == 'battle_target' && _m.attacker == seat) {
      final t = botTarget(_m, seat, level, _rnd);
      if (t != null) _after(_m.chooseTarget(seat, t));
    }
  }

  // ------------------------------------------------------------------ full state

  Map<String, dynamic> _fullState() {
    final aq = _m.active;
    final me = _m.players[0];
    return {
      'room': _roomState(_m.phase == 'results' ? 'ended' : 'playing'),
      'match': {
        'map_id': _template.id,
        'map_kind': mapKind,
        'phase': _m.phase,
        'phase_id': _m.phaseId,
        'deadline_in_ms': null,
        'expansion_round': _m.expansionRound,
        'battle_round': _m.battleRound,
        'round_order': _m.roundOrder,
        'rounds': _m.battleRounds,
        'base_towers': _m.baseTowers,
        'attacker': _m.attacker,
        'duel': _m.duel == null
            ? null
            : {'attacker': _m.duel!.attacker, 'defender': _m.duel!.defender, 'territory': _m.duel!.territory},
        'pick_quota': {for (final e in _m.pickQuota.entries) '${e.key}': e.value},
        'your_seat': 0,
        'territories': [
          for (final t in _m.territories.values)
            {
              'id': t.id,
              'owner': t.owner,
              'value': t.value,
              'is_base': t.isBase,
              'towers': t.towers,
              'shielded': t.shielded && t.owner != null && _m.allies(t.owner!, 0),
            },
        ],
        'players': [
          for (final p in _m.players)
            {
              'seat': p.seat,
              'name': p.name,
              'army': p.army,
              'team': p.team,
              'score': _m.score(p.seat),
              'eliminated': p.eliminated,
              'connected': true,
              'ability_used': p.abilityUsed,
              'powerups': p.seat == 0 ? [...me.powerups] : p.powerups.length,
            },
        ],
        'question': aq == null
            ? null
            : {
                'id': aq.question.id,
                'kind': aq.question.kind,
                'text': aq.question.text,
                'unit': aq.question.unit,
                'options': aq.question.kind == 'mcq' ? aq.question.options : <String>[],
                'participant': aq.participants.contains(0),
                'participants': aq.participants,
                'answered': aq.answers.containsKey(0),
                'time_ms': aq.limitsMs[0] ?? aq.limitsMs.values.reduce(max),
                'elapsed_ms': DateTime.now().difference(_questionSentAt ?? DateTime.now()).inMilliseconds,
              },
        'winner_team': _m.winnerTeam,
        'standings': _m.phase == 'results' ? _m.standings() : null,
      },
    };
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    status = SocketStatus.offline;
  }
}
