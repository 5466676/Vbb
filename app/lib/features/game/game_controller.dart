import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/armies.dart';
import '../../core/settings_store.dart';
import '../../core/socket.dart';
import '../../core/sound.dart';
import '../../local/local_game.dart';
import 'game_state.dart';

const _errors = {
  'no_room': 'ما في غرفة بهالرمز',
  'full': 'الغرفة مليانة',
  'started': 'المباراة بلّشت',
  'already_in_room': 'إنت أصلاً بغرفة',
  'not_host': 'بس صاحب الغرفة بيقدر يعمل هيك',
  'not_ready': 'في لاعبين مو جاهزين',
  'too_few': 'لازم يكون في لاعبين اتنين عالأقل',
  'teams_size': 'الفرق بدها 4 أو 6 أو 8 لاعبين',
  'rate_limited': 'شوي شوي!',
  'bad_settings': 'إعدادات غلط',
  'no_bots': 'البوتات مسكّرة بهالغرفة',
  'internal': 'صار خطأ بالسيرفر',
};

/// Builds [GameState] from server events and sends the player's actions.
class GameController extends Notifier<GameState> {
  late GameSocket socket;
  late SoundService sound;
  StreamSubscription<ServerMessage>? _sub;
  StreamSubscription<SocketStatus>? _statusSub;

  @override
  GameState build() {
    socket = GameSocket(ref.read(apiProvider));
    sound = ref.read(soundProvider);
    _sub = socket.messages.listen(_on);
    _statusSub = socket.statusStream.listen((s) {
      if (_local == null) state = state.copy(online: s == SocketStatus.online);
    });
    ref.onDispose(() {
      _sub?.cancel();
      _statusSub?.cancel();
      socket.close();
      stopOffline();
    });
    return const GameState();
  }

  SettingsStore get _settings => ref.read(settingsProvider);
  String? get myId => _local != null ? localPlayerId : _settings.playerId;

  // ------------------------------------------------------------------ offline play

  LocalGame? _local;
  StreamSubscription<ServerMessage>? _localSub;
  bool get offline => _local != null;
  GameTransport get _t => _local ?? socket;

  /// A whole match against bots inside the app (no server). [bots] = difficulty per bot.
  ({List<String> bots, String mapKind, bool teams})? _lastOffline;

  /// Same bots and map as the last offline match ("مباراة ثانية").
  Future<void> replayOffline() async {
    final l = _lastOffline;
    if (l != null) await startOffline(bots: l.bots, mapKind: l.mapKind, teams: l.teams);
  }

  Future<void> startOffline({required List<String> bots, required String mapKind, bool teams = false}) async {
    await stopOffline();
    _lastOffline = (bots: bots, mapKind: mapKind, teams: teams);
    final g = LocalGame(name: _settings.name, army: _settings.army, bots: bots, mapKind: mapKind, teams: teams);
    _local = g;
    _localSub = g.messages.listen(_on);
    state = state.copy(clearRoom: true, clearMatch: true, online: true);
    await g.connect();
  }

  Future<void> stopOffline() async {
    await _localSub?.cancel();
    _localSub = null;
    await _local?.close();
    _local = null;
  }

  Future<void> connect() => socket.connect();
  void clearError() => state = state.copy(clearError: true);

  // ------------------------------------------------------------------ actions

  void createRoom() => _t.send('create_room', {'army': _settings.army});
  void joinRoom(String code) => _t.send('join_room', {'code': code.trim().toUpperCase(), 'army': _settings.army});
  void quickMatch(String mode, int size) =>
      _t.send('quick_match', {'mode': mode, 'size': size, 'army': _settings.army});
  void cancelQuickMatch() => _t.send('cancel_quick_match');
  void leave() {
    _t.send('leave_room');
    if (_local != null) stopOffline();
    state = state.copy(clearRoom: true, clearMatch: true, online: socket.status == SocketStatus.online);
  }

  void setReady(bool ready) => _t.send('set_ready', {'ready': ready});
  void chooseArmy(String army) {
    _settings.setArmy(army);
    _t.send('choose_army', {'army': army});
  }

  void voteMap(String kind) => _t.send('vote_map', {'kind': kind});
  void updateSettings(Map<String, dynamic> s) => _t.send('update_settings', s);
  void addBot(String level) => _t.send('add_bot', {'difficulty': level});
  void removeBot(int seat) => _t.send('remove_bot', {'seat': seat});
  void startMatch() => _t.send('start_match');

  void answerChoice(int i) {
    final q = state.match?.question;
    if (q == null || q.answered || !q.participant) return;
    q.myChoice = i;
    _t.send('answer', {'question_id': q.id, 'choice': i});
    sound.play('answer_locked');
    _bump();
  }

  void answerValue(double v) {
    final q = state.match?.question;
    if (q == null || q.answered || !q.participant) return;
    q.myValue = v;
    _t.send('answer', {'question_id': q.id, 'value': v});
    sound.play('answer_locked');
    _bump();
  }

  /// Toggle a pick during `expansion_picks` (the server fills what you leave out).
  void togglePick(int territory) {
    final m = state.match;
    if (m == null || m.phase != 'expansion_picks') return;
    final quota = m.quota[m.mySeat] ?? 0;
    if (m.myPicks.contains(territory)) {
      m.myPicks.remove(territory);
    } else if (m.myPicks.length < quota) {
      m.myPicks.add(territory);
    } else if (quota > 0) {
      m.myPicks = [...m.myPicks.skip(1), territory];
    }
    _t.send('pick_territory', {'territories': m.myPicks});
    sound.play('ui_tap');
    _bump();
  }

  void chooseTarget(int territory) {
    final m = state.match;
    if (m == null || !m.myTurn || !m.targets.contains(territory)) return;
    _t.send('choose_target', {'territory': territory});
    sound.play('sword_swing');
  }

  void usePowerup(String name, {int? territory}) => _t.send('use_powerup', {'powerup': name, 'territory': ?territory});
  void useAbility({int? territory}) => _t.send('use_ability', {'territory': ?territory});

  // ------------------------------------------------------------------ events

  void _bump() => state = state.copy();

  @visibleForTesting
  void handle(ServerMessage msg) => _on(msg);

  void _on(ServerMessage msg) {
    final p = msg.payload;
    final m = state.match;
    switch (msg.type) {
      case 'welcome':
        state = state.copy(online: true);
      case 'error':
        final code = p['code'] as String? ?? '';
        if (code == 'rule' || code == 'duplicate' || code == 'no_question') return; // harmless races
        sound.play('ui_error');
        state = state.copy(error: _errors[code] ?? (p['message'] as String? ?? code));
      case 'queued':
        state = state.copy(queued: p);
      case 'quick_match_cancelled':
        state = state.copy(clearQueued: true);
      case 'match_found':
        sound.play('match_found');
        state = state.copy(clearQueued: true);
      case 'room_state':
        final room = RoomView.fromJson(p);
        final before = state.room?.seats.length ?? 0;
        if (room.seats.length > before && before > 0) sound.play('match_found');
        state = state.copy(room: room, clearMatch: room.status == 'lobby' && (m?.ended ?? false));
      case 'left_room':
        state = state.copy(clearRoom: true, clearMatch: true);
      case 'full_state':
        _fullState(p);
      case 'match_started':
        _matchStarted(p);
      default:
        if (m != null) {
          _matchEvent(m, msg.type, p);
          _bump();
        }
    }
  }

  void _matchStarted(Map<String, dynamic> p) {
    final room = state.room;
    final match = MatchView(
      mapId: p['map_id'] as String,
      mapKind: p['map_kind'] as String,
      mode: p['mode'] as String,
      rounds: p['rounds'] as int,
      baseTowers: p['base_towers'] as int,
      players: [
        for (final x in p['players'] as List)
          PlayerView(
            seat: x['seat'] as int,
            name: x['name'] as String,
            army: x['army'] as String,
            team: x['team'] as int,
            bot: (x['bot'] ?? false) as bool,
            powerups: const ['remove_two', 'hint', 'shield', 'double'],
          ),
      ],
      bases: [for (final b in p['bases'] as List) b as int],
    );
    match.mySeat = room?.seats.indexWhere((s) => s.playerId == myId);
    if (match.mySeat == -1) match.mySeat = null;
    for (var seat = 0; seat < match.bases.length; seat++) {
      match.terr(match.bases[seat])
        ..owner = seat
        ..isBase = true
        ..towers = match.baseTowers;
    }
    sound.play('countdown');
    sound.preload();
    state = state.copy(match: match);
    _t.send('resync'); // exact values, towers and my power-ups
  }

  void _fullState(Map<String, dynamic> p) {
    final room = RoomView.fromJson((p['room'] as Map).cast<String, dynamic>());
    final mj = (p['match'] as Map?)?.cast<String, dynamic>();
    if (mj == null) {
      state = state.copy(room: room, clearMatch: true);
      return;
    }
    final old = state.match;
    final match = MatchView(
      mapId: mj['map_id'] as String,
      mapKind: mj['map_kind'] as String,
      mode: (old?.mode ?? room.settings['mode'] ?? 'ffa') as String,
      rounds: mj['rounds'] as int,
      baseTowers: mj['base_towers'] as int,
      players: [
        for (final x in mj['players'] as List)
          PlayerView(
            seat: x['seat'] as int,
            name: x['name'] as String,
            army: x['army'] as String,
            team: x['team'] as int,
            bot: room.seats.length > (x['seat'] as int) && room.seats[x['seat'] as int].bot != null,
            score: (x['score'] ?? 0) as int,
            eliminated: (x['eliminated'] ?? false) as bool,
            connected: (x['connected'] ?? true) as bool,
            abilityUsed: (x['ability_used'] ?? false) as bool,
            powerups: x['powerups'] is List ? [for (final s in x['powerups'] as List) '$s'] : const [],
            powerupCount: x['powerups'] is List ? (x['powerups'] as List).length : (x['powerups'] as int? ?? 0),
          ),
      ],
      bases: old?.bases ?? const [],
    );
    match.mySeat = mj['your_seat'] as int?;
    for (final t in mj['territories'] as List) {
      match.territories[t['id'] as int] = Territory(
        id: t['id'] as int,
        owner: t['owner'] as int?,
        value: (t['value'] ?? 200) as int,
        isBase: (t['is_base'] ?? false) as bool,
        towers: (t['towers'] ?? 0) as int,
        shielded: (t['shielded'] ?? false) as bool,
      );
    }
    match.phase = mj['phase'] as String;
    match.phaseId = mj['phase_id'] as int;
    final left = mj['deadline_in_ms'] as int?;
    match.deadline = left == null ? null : DateTime.now().add(Duration(milliseconds: left));
    match.expansionRound = (mj['expansion_round'] ?? 0) as int;
    match.battleRound = (mj['battle_round'] ?? 0) as int;
    match.roundOrder = [for (final s in (mj['round_order'] as List? ?? const [])) s as int];
    match.attacker = mj['attacker'] as int?;
    // turns already taken this round: everyone listed before the current attacker
    final at = match.attacker == null ? -1 : match.roundOrder.indexOf(match.attacker!);
    if (at > 0) match.turnDone.addAll(match.roundOrder.take(at));
    final duel = (mj['duel'] as Map?)?.cast<String, dynamic>();
    match.defender = duel?['defender'] as int?;
    match.duelTerritory = duel?['territory'] as int?;
    match.quota = ((mj['pick_quota'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse('$k'), v as int));
    match.targets = old?.targets ?? const [];
    match.myPicks = old?.myPicks ?? [];
    for (final t in old?.ticker.reversed ?? const <Ticker>[]) {
      match.ticker.insert(0, t);
    }
    final q = (mj['question'] as Map?)?.cast<String, dynamic>();
    if (q != null) {
      final elapsed = (q['elapsed_ms'] ?? 0) as int;
      match.question = QuestionView(
        id: q['id'] as String,
        kind: q['kind'] as String,
        text: q['text'] as String,
        unit: (q['unit'] ?? '') as String,
        options: [for (final o in (q['options'] as List? ?? [])) '$o'],
        participant: (q['participant'] ?? false) as bool,
        participants: [for (final s in (q['participants'] as List? ?? [])) s as int],
        timeMs: q['time_ms'] as int,
        receivedAt: DateTime.now().subtract(Duration(milliseconds: elapsed)),
      );
      if ((q['answered'] ?? false) == true) match.question!.myChoice = -1;
    }
    if (mj['standings'] != null) {
      match.standings = [for (final s in mj['standings'] as List) (s as Map).cast<String, dynamic>()];
      match.winnerTeam = mj['winner_team'] as int?;
    }
    state = state.copy(room: room, match: match);
  }

  String _name(MatchView m, int? seat) => seat == null || seat >= m.players.length ? '' : m.players[seat].name;

  void _matchEvent(MatchView m, String type, Map<String, dynamic> p) {
    switch (type) {
      case 'phase_changed':
        m.phase = p['phase'] as String;
        m.phaseId = p['phase_id'] as int;
        final opens = (p['opens_in_ms'] ?? 0) as int;
        m.opensAt = DateTime.now().add(Duration(milliseconds: opens));
        final dl = p['deadline_ms'] as int?;
        m.deadline = dl == null ? null : m.opensAt!.add(Duration(milliseconds: dl));
        switch (m.phase) {
          case 'expansion_question':
            m.expansionRound = (p['expansion_round'] ?? m.expansionRound) as int;
          case 'expansion_picks':
            m.quota = ((p['quota'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse('$k'), v as int));
            m.myPicks = [];
            m.question = null;
          case 'battle_target':
            final prev = m.attacker;
            m.attacker = p['attacker'] as int?;
            if (prev != null && prev != m.attacker) m.turnDone.add(prev);
            if (m.turnsUntilMine() == 1) sound.play('ready'); // you're next
            m.battleRound = (p['round'] ?? m.battleRound) as int;
            m.targets = [for (final t in (p['targets'] as List? ?? [])) t as int];
            m.defender = null;
            m.duelTerritory = null;
            m.question = null;
            if (m.myTurn) sound.play('your_turn');
          case 'battle_duel' || 'battle_tiebreak':
            m.attacker = p['attacker'] as int?;
            m.defender = p['defender'] as int?;
            m.duelTerritory = p['territory'] as int?;
            if (m.phase == 'battle_tiebreak') sound.play('tiebreak');
        }
      case 'question':
        final q = QuestionView(
          id: p['id'] as String,
          kind: p['kind'] as String,
          text: p['text'] as String,
          unit: (p['unit'] ?? '') as String,
          options: [for (final o in (p['options'] as List? ?? [])) '$o'],
          participant: (p['participant'] ?? false) as bool,
          participants: [for (final s in (p['participants'] as List? ?? [])) s as int],
          timeMs: p['time_ms'] as int,
          receivedAt: DateTime.now(),
        );
        m.question = q;
        m.deadline = DateTime.now().add(Duration(milliseconds: q.timeMs));
        sound.play('question_show');
      case 'answer_locked':
        final seat = p['seat'] as int;
        m.question?.locked.add(seat);
        if (seat != m.mySeat) sound.play('other_answered');
      case 'question_result':
        final q = m.question;
        if (q != null && q.id == p['id']) {
          q.correctIndex = p['correct_index'] as int?;
          q.answer = (p['answer'] as num?)?.toDouble();
          q.ranking = [for (final s in (p['ranking'] as List? ?? [])) s as int];
          q.answers = ((p['answers'] as Map?) ?? {}).map(
            (k, v) => MapEntry(int.parse('$k'), (v as Map).cast<String, dynamic>()),
          );
          if (q.participant) {
            final won = q.ranking.isNotEmpty && q.ranking.first == m.mySeat;
            final right = q.correctIndex != null ? q.myChoice == q.correctIndex : won;
            sound.play(q.answered ? (right ? 'correct' : 'wrong') : 'time_up');
          }
        }
      case 'territory_claimed':
        final t = m.terr(p['territory'] as int)
          ..owner = p['seat'] as int
          ..value = (p['value'] ?? 200) as int;
        m.flash = t.id;
        m.effect(Fx('claim', t.id, seat: t.owner));
        sound.play('claim');
      case 'battle_started':
        m.log('بدأت المعارك! ${p['rounds']} جولات', null, 'round');
        sound.play('battle_start');
        _t.send('resync'); // army bonuses change values at the start of battle
      case 'round_started':
        m.battleRound = p['round'] as int;
        m.roundOrder = [for (final s in (p['order'] as List? ?? const [])) s as int];
        m.turnDone.clear();
        m.attacker = null;
        m.log('الجولة ${p['round']}', null, 'round');
        sound.play('round_start');
      case 'turn_skipped':
        if (p['seat'] is int) m.turnDone.add(p['seat'] as int);
        m.log('${_name(m, p['seat'] as int?)} ما عندو هدف', p['seat'] as int?);
      case 'target_chosen':
        m.attacker = p['attacker'] as int?;
        m.defender = p['defender'] as int?;
        m.duelTerritory = p['territory'] as int?;
        m.flash = m.duelTerritory;
        if (m.duelTerritory != null) m.effect(Fx('march', m.duelTerritory!, seat: m.attacker));
        m.log('${_name(m, m.attacker)} هاجم ${_name(m, m.defender)}', m.attacker, 'attack');
        sound.play('march');
      case 'shield_blocked':
        m.log('الدرع صدّ الهجوم', p['defender'] as int?, 'held');
        if (m.duelTerritory != null) m.effect(Fx('held', m.duelTerritory!, seat: p['defender'] as int?));
        sound.play('shield');
      case 'tie_won_by_ability':
        m.log('${_name(m, p['seat'] as int?)} ربح التعادل بقدرة جيشو', p['seat'] as int?);
      case 'territory_captured':
        final attacker = p['attacker'] as int;
        m.effect(Fx('capture', p['territory'] as int, seat: attacker, value: (p['value'] ?? 200) as int));
        m.terr(p['territory'] as int)
          ..owner = attacker
          ..value = (p['value'] ?? 200) as int
          ..shielded = false;
        m.flash = p['territory'] as int;
        m.lastCaptured = m.flash;
        m.log('${_name(m, attacker)} احتلّ أرض', attacker, 'capture');
        sound.play('sword_clash');
        sound.capture(m.players[attacker].army);
      case 'territory_held':
        m.terr(p['territory'] as int).value = (p['value'] ?? 200) as int;
        m.effect(Fx('held', p['territory'] as int, seat: p['defender'] as int?));
        m.log('${_name(m, p['defender'] as int?)} صمد', p['defender'] as int?, 'held');
        sound.play('base_guarded');
      case 'tower_hit':
        m.terr(p['territory'] as int).towers = p['towers'] as int;
        m.flash = p['territory'] as int;
        m.effect(Fx('tower', p['territory'] as int, seat: p['attacker'] as int?));
        m.log('سقط برج!', p['attacker'] as int?, 'tower');
        sound.play('tower_hit');
      case 'base_guarded':
        sound.play('base_guarded');
      case 'player_eliminated':
        final seat = p['seat'] as int;
        final by = p['by'] as int?;
        m.players[seat].eliminated = true;
        for (final t in (p['territories'] as List? ?? [])) {
          m.terr(t as int)
            ..owner = by
            ..isBase = false
            ..towers = 0;
        }
        m.log('${_name(m, seat)} خرج من المعركة', seat, 'out');
        sound.play('eliminated');
      case 'extra_turn':
        sound.play('extra_turn');
      case 'powerup_used':
        final seat = p['seat'] as int;
        final name = p['powerup'] as String;
        final pl = m.players[seat];
        if (seat == m.mySeat) {
          pl.powerups = [...pl.powerups]..remove(name);
        }
        pl.powerupCount = (pl.powerupCount - 1).clamp(0, 4);
        m.log('${pl.name}: ${powerupNames[name] ?? name}', seat, 'power');
        sound.play(name);
      case 'powerup_result':
        final q = m.question;
        switch (p['powerup']) {
          case 'remove_two':
            q?.removed = {for (final i in (p['removed'] as List? ?? [])) i as int};
          case 'hint':
            q?.hintLow = (p['low'] as num?)?.toDouble();
            q?.hintHigh = (p['high'] as num?)?.toDouble();
          case 'shield':
            m.terr(p['territory'] as int).shielded = true;
        }
      case 'ability_used':
        final seat = p['seat'] as int;
        m.players[seat].abilityUsed = true;
        m.log('${m.players[seat].name}: ${armyOf(p['army'] as String?).abilityName}!', seat, 'power');
        sound.play('ability');
        _t.send('resync');
      case 'player_connection':
        final seat = p['seat'] as int;
        final up = p['connected'] as bool;
        m.players[seat].connected = up;
        sound.play(up ? 'player_back' : 'player_left');
      case 'match_ended':
        m.standings = [for (final s in p['standings'] as List) (s as Map).cast<String, dynamic>()];
        m.winnerTeam = p['winner_team'] as int?;
        m.phase = 'results';
        m.question = null;
        final myTeam = m.me?.team;
        sound.play(myTeam != null && myTeam == m.winnerTeam ? 'victory' : 'defeat');
    }
  }
}

final gameProvider = NotifierProvider<GameController, GameState>(GameController.new);
