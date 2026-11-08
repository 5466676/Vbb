/// Client-side view of the room and the match, built only from server events.
library;

class Seat {
  Seat({
    required this.seat,
    required this.playerId,
    required this.name,
    required this.army,
    required this.ready,
    required this.bot,
    required this.connected,
  });
  final int seat;
  final String? playerId;
  final String name;
  final String army;
  final bool ready;
  final String? bot;
  final bool connected;

  factory Seat.fromJson(Map<String, dynamic> j) => Seat(
    seat: j['seat'] as int,
    playerId: j['player_id'] as String?,
    name: (j['name'] ?? '') as String,
    army: (j['army'] ?? 'islamic') as String,
    ready: (j['ready'] ?? false) as bool,
    bot: j['bot'] as String?,
    connected: (j['connected'] ?? true) as bool,
  );
}

class RoomView {
  RoomView({
    required this.code,
    required this.host,
    required this.status,
    required this.settings,
    required this.seats,
    required this.votes,
    required this.quick,
  });
  final String code;
  final String? host;
  final String status; // lobby | playing | ended
  final Map<String, dynamic> settings;
  final List<Seat> seats;
  final Map<String, String> votes;
  final bool quick;

  factory RoomView.fromJson(Map<String, dynamic> j) => RoomView(
    code: j['code'] as String,
    host: j['host'] as String?,
    status: (j['status'] ?? 'lobby') as String,
    settings: (j['settings'] as Map?)?.cast<String, dynamic>() ?? {},
    seats: [for (final s in (j['seats'] as List? ?? [])) Seat.fromJson((s as Map).cast<String, dynamic>())],
    votes: ((j['votes'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')),
    quick: (j['quick'] ?? false) as bool,
  );
}

class Territory {
  Territory({
    required this.id,
    this.owner,
    this.value = 200,
    this.isBase = false,
    this.towers = 0,
    this.shielded = false,
  });
  final int id;
  int? owner;
  int value;
  bool isBase;
  int towers;
  bool shielded;
}

class PlayerView {
  PlayerView({
    required this.seat,
    required this.name,
    required this.army,
    required this.team,
    required this.bot,
    this.score = 0,
    this.eliminated = false,
    this.connected = true,
    this.abilityUsed = false,
    this.powerups = const [],
    this.powerupCount = 4,
  });
  final int seat;
  final String name;
  final String army;
  final int team;
  final bool bot;
  int score;
  int bonus = 0; // points not tied to land (army perks, right answers to other duels)
  bool away = false; // the autopilot is playing for them
  bool eliminated;
  bool connected;
  bool abilityUsed;
  List<String> powerups; // only known for me
  int powerupCount;
}

class QuestionView {
  QuestionView({
    required this.id,
    required this.kind,
    required this.text,
    required this.unit,
    required this.options,
    required this.participant,
    required this.participants,
    required this.timeMs,
    required this.receivedAt,
    this.category = '',
  });
  final String id;
  final String category;
  final String kind; // mcq | numeric
  final String text;
  final String unit;
  final List<String> options;
  final bool participant;
  final List<int> participants;
  final int timeMs;
  final DateTime receivedAt;
  int? myChoice;
  double? myValue;
  final Set<int> locked = {}; // seats that answered
  Set<int> removed = {}; // remove_two result
  double? hintLow, hintHigh;

  // after question_result
  int? correctIndex;
  double? answer;
  List<int> ranking = const [];
  Map<int, Map<String, dynamic>> answers = const {};
  bool get resolved => correctIndex != null || answer != null;
  bool get answered => myChoice != null || myValue != null;
}

class Ticker {
  Ticker(this.text, this.seat, [this.kind = 'info']);
  final String text;
  final int? seat;
  final String kind; // info | attack | capture | held | tower | out | power | round
  final DateTime at = DateTime.now();
}

/// One map animation: `march` (attacker → target), `capture` (flag planted, colour spreads),
/// `held` (the defender's shield flashes), `tower` (a base tower falls), `claim` (expansion pick).
class Fx {
  Fx(this.kind, this.territory, {this.seat, this.value = 0});
  final String kind;
  final int territory;
  final int? seat;
  final int value;
  final DateTime at = DateTime.now();
}

class MatchView {
  MatchView({
    required this.mapId,
    required this.mapKind,
    required this.mode,
    required this.rounds,
    required this.baseTowers,
    required this.players,
    required this.bases,
  });
  final String mapId;
  final String mapKind;
  final String mode;
  final int rounds;
  final int baseTowers;
  final List<PlayerView> players;
  final List<int> bases;
  final Map<int, Territory> territories = {};
  int? mySeat;

  String phase = 'starting';
  int phaseId = 0;
  DateTime? opensAt;
  DateTime? deadline;
  int expansionRound = 0;
  int battleRound = 0;
  int? attacker;
  int? placer; // castle placement: whose turn it is
  int? treasure; // the territory with the chest, until someone takes it
  final Set<int> ruins = {}; // fallen castles: they smoulder on the map for the rest of the match
  List<int> placeOptions = const [];
  List<int> roundOrder = const []; // this battle round's attackers, in turn order
  bool finalRound = false; // fixed-rounds matches: the last round, captures count double
  double? winShare; // open length: owning this share of the map wins (eases over time); null = fixed rounds
  final Set<int> turnDone = {}; // seats that already had their turn this round
  int? defender;
  int? duelTerritory;
  List<int> targets = const []; // my legal targets while I choose
  List<int> attackers = const []; // who is choosing a target now
  final Set<int> targetLocked = {}; // who already chose
  int? king; // the king's question: the leader left out of it
  final Set<int> onFire = {}; // 3+ right answers in a row
  List<String> offeredCategories = const []; // the attacker picks the duel's category from these
  Map<int, int> quota = const {};
  List<int> myPicks = [];
  QuestionView? question;
  final List<Ticker> ticker = [];
  int? lastCaptured;
  int? flash; // territory to highlight briefly (claim, capture, hit)
  final List<Fx> fx = []; // short map animations, drawn by the map's effects layer
  // a big stage announcement ("الحرب!", "الجولة 3"…); the id changes for every new one
  String? banner;
  String? bannerSub;
  int bannerId = 0;

  void announce(String text, [String? sub]) {
    banner = text;
    bannerSub = sub;
    bannerId++;
  }

  // results
  List<Map<String, dynamic>>? standings;
  int? winnerTeam;

  bool get ended => standings != null;
  PlayerView? get me => mySeat == null ? null : players[mySeat!];

  /// How many turns before mine in this round: 0 = mine now, 1 = I am next, null = not this round.
  int? turnsUntilMine() {
    final me = mySeat;
    if (me == null || !roundOrder.contains(me) || turnDone.contains(me)) return null;
    if (attacker == me && phase.startsWith('battle')) return 0;
    final waiting = [
      for (final s in roundOrder)
        if (!turnDone.contains(s) && s != attacker && !players[s].eliminated) s,
    ];
    final i = waiting.indexOf(me);
    return i < 0 ? null : i + 1;
  }

  /// What the scoreboard shows: land value plus bonus points (the server's score).
  int scoreOf(int seat) =>
      territories.values.where((t) => t.owner == seat).fold(0, (a, t) => a + t.value) + players[seat].bonus;

  /// Choosing a target (everyone picks at once; I'm one of them and have not locked mine yet).
  bool get myTurn =>
      phase == 'battle_target' && mySeat != null && attackers.contains(mySeat) && !targetLocked.contains(mySeat);

  Territory terr(int id) => territories.putIfAbsent(id, () => Territory(id: id));

  void log(String text, [int? seat, String kind = 'info']) {
    ticker.insert(0, Ticker(text, seat, kind));
    if (ticker.length > 30) ticker.removeLast();
  }

  void effect(Fx f) {
    fx.add(f);
    fx.removeWhere((e) => DateTime.now().difference(e.at) > const Duration(seconds: 4));
  }
}

class GameState {
  const GameState({this.online = false, this.room, this.match, this.queued, this.error, this.version = 0});
  final bool online;
  final RoomView? room;
  final MatchView? match;
  final Map<String, dynamic>? queued; // quick match waiting
  final String? error;
  final int version; // bumps on every change (match is mutated in place)

  GameState copy({
    bool? online,
    RoomView? room,
    MatchView? match,
    Map<String, dynamic>? queued,
    String? error,
    bool clearRoom = false,
    bool clearMatch = false,
    bool clearQueued = false,
    bool clearError = false,
  }) {
    return GameState(
      online: online ?? this.online,
      room: clearRoom ? null : (room ?? this.room),
      match: clearMatch ? null : (match ?? this.match),
      queued: clearQueued ? null : (queued ?? this.queued),
      error: clearError ? null : (error ?? this.error),
      version: version + 1,
    );
  }
}
