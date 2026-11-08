import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart' show RankBadge;
import '../../core/armies.dart';
import '../../core/map_template.dart';
import '../game/game_controller.dart';
import '../game/game_state.dart';
import 'duel_splash.dart';
import 'map_view.dart';
import 'question_arena.dart' show QuestionArena, Toon, categoryIcon;
import 'stage_sign.dart';
import 'results_view.dart';

/// The match: map in the middle, players on the side, question on top when one is open.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  MapTemplate? _template;
  String? _loadedFor;
  String? _territoryMode; // 'shield' or 'ability': the next tap on my territory uses it
  int? _target; // my chosen target while I pick the question category
  String? _lastHurry;
  int _targetPhase = -1;

  Future<void> _load(String mapId) async {
    if (_loadedFor == mapId) return;
    _loadedFor = mapId;
    final t = await MapTemplate.load(mapId);
    if (!mounted) return;
    setState(() => _template = t);
    // decode the end-of-match art early, so the results never open on a blank frame
    for (final a in const ['assets/ui/victory.webp', 'assets/ui/defeat.webp', 'assets/ui/question_card.webp']) {
      precacheImage(AssetImage(a), context);
    }
  }

  Set<int> _legalPicks(MatchView m) {
    final me = m.mySeat;
    if (me == null || (m.quota[me] ?? 0) == 0) return {};
    final t = _template!;
    final free = {
      for (final s in t.territories)
        if (m.territories[s.id]?.owner == null) s.id,
    };
    final mine = {
      for (final e in m.territories.entries)
        if (e.value.owner == me) e.key,
    };
    final near = {
      for (final id in mine) ...t.byId(id).neighbors,
      for (final l in t.seaLinks)
        if (mine.contains(l.a)) l.b else if (mine.contains(l.b)) l.a,
    }.intersection(free);
    if (near.isNotEmpty) return near;
    // none adjacent: only the free land the fewest steps away (GAME_RULES §6.1.5)
    List<int> links(int id) => [
      ...t.byId(id).neighbors,
      for (final l in t.seaLinks)
        if (l.a == id) l.b else if (l.b == id) l.a,
    ];
    var frontier = mine.toList();
    final seen = {...frontier};
    while (frontier.isNotEmpty) {
      final hit = frontier.where(free.contains).toSet();
      if (hit.isNotEmpty) return hit;
      frontier = [
        for (final id in frontier)
          for (final n in links(id))
            if (seen.add(n)) n,
      ];
    }
    return free;
  }

  void _tap(MatchView m, int id) {
    final game = ref.read(gameProvider.notifier);
    if (_territoryMode != null) {
      if (m.territories[id]?.owner == m.mySeat) {
        if (_territoryMode == 'shield') {
          game.usePowerup('shield', territory: id);
        } else {
          game.useAbility(territory: id);
        }
        setState(() => _territoryMode = null);
      }
      return;
    }
    if (m.phase == 'base_placement') {
      if (m.placer == m.mySeat && m.placeOptions.contains(id)) game.placeBase(id);
    } else if (m.phase == 'expansion_picks') {
      game.togglePick(id);
    } else if (m.myTurn) {
      if (!m.targets.contains(id)) return;
      if (m.offeredCategories.isEmpty) {
        game.chooseTarget(id);
      } else {
        setState(() {
          _target = id;
          _targetPhase = m.phaseId;
        });
        game.sound.play('ui_tap');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gs = ref.watch(gameProvider);
    final m = gs.match;
    if (m == null) return const SizedBox.shrink();
    _load(m.mapId);
    final t = _template;
    if (t == null || t.id != m.mapId) return const Center(child: CircularProgressIndicator());

    final highlight = _territoryMode != null
        ? {
            for (final e in m.territories.entries)
              if (e.value.owner == m.mySeat) e.key,
          }
        : m.phase == 'base_placement'
        ? (m.placer == m.mySeat ? m.placeOptions.toSet() : <int>{})
        : m.phase == 'expansion_picks'
        ? _legalPicks(m)
        : m.myTurn
        ? m.targets.toSet()
        : <int>{};

    // music follows the stage: calm map music, war drums in battle, silence for the results
    final track = m.ended ? null : (m.phase.startsWith('battle') ? (m.finalRound ? 'final' : 'battle') : 'map');
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(gameProvider.notifier).sound.music(track));
    final q = m.question;
    final asking = q != null && !m.ended;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(match: m),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      return Stack(
                        children: [
                          // open sea around the map
                          const Positioned.fill(
                            child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF05070F))),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 44,
                            bottom: 0,
                            child: _Shake(
                              match: m,
                              child: MapView(
                                template: t,
                                match: m,
                                version: gs.version,
                                highlight: highlight,
                                selected: {...m.myPicks, if (_target != null && _targetPhase == m.phaseId) _target!},
                                onTap: (id) => _tap(m, id),
                              ),
                            ),
                          ),
                          const Positioned.fill(child: _Motes()),
                          // dark edges frame the battlefield
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    radius: 0.95,
                                    colors: [Color(0x00000000), Color(0x00000000), Color(0xCC02040C)],
                                    stops: [0, 0.7, 1],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _PhaseBanner(match: m, mode: _territoryMode),
                            ),
                          ),
                          if (m.phase.startsWith('battle') && m.roundOrder.isNotEmpty)
                            Positioned(
                              top: 46,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: IgnorePointer(child: TurnStrip(match: m)),
                              ),
                            ),
                          if (!asking && !m.ended) Positioned(bottom: 8, right: 10, child: _LogToast(match: m)),
                          if (asking)
                            Positioned(
                              left: 6,
                              right: 6,
                              top: 44,
                              bottom: _ToolBar.usable(m).isEmpty ? 6 : 72,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: ScaleTransition(
                                    scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                                    child: child,
                                  ),
                                ),
                                child: QuestionArena(
                                  key: ValueKey(q.id),
                                  match: m,
                                  onChoice: ref.read(gameProvider.notifier).answerChoice,
                                  onValue: ref.read(gameProvider.notifier).answerValue,
                                  onTick: (urgent) {
                                    final sound = ref.read(gameProvider.notifier).sound;
                                    sound.play('tick', volume: urgent ? 1 : 0.4);
                                    if (urgent && _lastHurry != q.id) {
                                      _lastHurry = q.id; // once per question, at five seconds left
                                      sound.say('hurry', chance: 0.5);
                                    }
                                  },
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 6,
                            child: Center(
                              child: _ToolBar(
                                match: m,
                                mode: _territoryMode,
                                onMode: (mode) => setState(() => _territoryMode = _territoryMode == mode ? null : mode),
                              ),
                            ),
                          ),
                          if (m.myTurn && _target != null && _targetPhase == m.phaseId)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 84, // above the power-ups row
                              child: Center(
                                child: _CategoryChooser(
                                  categories: m.offeredCategories,
                                  onPick: (c) {
                                    ref.read(gameProvider.notifier).chooseTarget(_target!, category: c);
                                    setState(() => _target = null);
                                  },
                                  onCancel: () => setState(() => _target = null),
                                ),
                              ),
                            ),
                          if (m.me?.away ?? false)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 84,
                              child: Center(
                                child: Semantics(
                                  button: true,
                                  label: 'رجعت',
                                  child: GestureDetector(
                                    onTap: () => ref.read(gameProvider.notifier).back(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      decoration: Toon.chunky(Toon.gold, radius: 16),
                                      child: const Text(
                                        '🤖 عم نلعب عنك — اكبس لترجع',
                                        style: TextStyle(
                                          color: Color(0xFF05070F),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(left: 0, right: 0, top: 0, height: 56, child: _EmoteBubbles(match: m)),
                          // your move: the screen's edge breathes in cyan
                          Positioned.fill(child: _TurnGlow(active: m.myTurn && !asking && !m.ended)),
                          // a new stage: a bright scan line sweeps across before the sign drops
                          if (m.banner != null) Positioned.fill(child: _ScanWipe(key: ValueKey('wipe${m.bannerId}'))),
                          if (m.banner != null)
                            Positioned.fill(
                              child: StageSign(key: ValueKey('sign${m.bannerId}'), text: m.banner!, sub: m.bannerSub),
                            ),
                          if (m.phase == 'battle_duel' && m.attacker != null && m.defender != null)
                            Positioned.fill(
                              child: DuelSplash(
                                key: ValueKey('duel${m.phaseId}'),
                                attacker: m.players[m.attacker!],
                                defender: m.players[m.defender!],
                                // start so it ends as the question arrives (after the march)
                                delay: () {
                                  final left =
                                      (m.opensAt ?? DateTime.now()).difference(DateTime.now()) -
                                      const Duration(milliseconds: 1700);
                                  return left.isNegative ? Duration.zero : left;
                                }(),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            if (m.ended) Positioned.fill(child: ResultsView(match: m)),
            if (!gs.online) const Positioned(top: 0, right: 0, child: _Offline()),
          ],
        ),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: AppColors.bad, borderRadius: BorderRadius.circular(8)),
    child: const Text('عم نعيد الاتصال…', style: TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.match, required this.mode});
  final MatchView match;
  final String? mode;

  @override
  Widget build(BuildContext context) {
    final m = match;
    String name(int? s) => s == null ? '' : m.players[s].name;
    final text = switch (mode) {
      'shield' => 'اختار أرض من أراضيك لتحطلها درع',
      'ability' => 'اختار أرض من أراضيك',
      _ => switch (m.phase) {
        'base_placement' =>
          m.placer == m.mySeat
              ? 'اختار وين تبني قلعتك (مو لازقة بقلعة غيرك)'
              : '${name(m.placer)} عم يختار مكان قلعتو…',
        'expansion_question' => 'التوسّع — الجولة ${m.expansionRound}',
        'expansion_picks' =>
          (m.quota[m.mySeat] ?? 0) > 0
              ? 'اختار ${m.quota[m.mySeat]} أرض (${m.myPicks.length}/${m.quota[m.mySeat]})'
              : 'الباقين عم يختاروا أراضيهم…',
        'battle_target' =>
          m.myTurn
              ? 'دورك! اختار أرض لتهاجمها'
              : m.attackers.length == 1
              ? 'دور ${name(m.attackers.first)} بالهجوم'
              : m.attackers.contains(m.mySeat)
              ? 'اخترت هدفك… ناطرين الباقي (${m.targetLocked.length}/${m.attackers.length})'
              : 'الكل عم يختار أهدافهم… (${m.targetLocked.length}/${m.attackers.length})',
        'king_question' => m.king == m.mySeat ? '👑 إنت الملك! الباقيين عم يجاوبوا' : '👑 سؤال الملك: الأسرع بياخد 150',
        'battle_duel' => 'مبارزة: ${name(m.attacker)} ضد ${name(m.defender)}',
        'battle_tiebreak' => 'تعادل! سؤال الحسم',
        'results' => 'انتهت المعركة',
        _ => 'استعدّوا…',
      },
    };
    final win = m.winShare;
    final round = m.battleRound == 0
        ? ''
        : m.finalRound
        ? '  •  الجولة الأخيرة (الاحتلال ×2)'
        : win == null
        ? '  •  جولة المعارك ${m.battleRound}/${m.rounds}'
        : '  •  الجولة ${m.battleRound}  •  للفوز ${(win * 100).round()}٪ من الخريطة';
    final timed = m.phase == 'expansion_picks' || m.phase == 'battle_target' || m.phase == 'base_placement';
    return _Ribbon(
      highlight:
          m.myTurn ||
          (m.phase == 'expansion_picks' && (m.quota[m.mySeat] ?? 0) > 0) ||
          (m.phase == 'base_placement' && m.placer == m.mySeat),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$text$round',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink, height: 1.3),
          ),
          if (timed && m.deadline != null) ...[const SizedBox(width: 8), _Countdown(until: m.deadline!)],
        ],
      ),
    );
  }
}

/// A parchment ribbon with folded ends for the phase line.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.child, required this.highlight});
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RibbonPainter(highlight),
      child: Padding(padding: const EdgeInsets.fromLTRB(34, 6, 34, 8), child: child),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.highlight);
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, tail = 18.0;
    final shade = Paint()..color = const Color(0xFF0B3A66);
    // folded tails behind
    for (final left in [true, false]) {
      final x0 = left ? 0.0 : w, dir = left ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(x0 + dir * tail, 6)
          ..lineTo(x0 - dir * 4, 6)
          ..lineTo(x0 + dir * 8, h / 2 + 3)
          ..lineTo(x0 - dir * 4, h)
          ..lineTo(x0 + dir * tail, h)
          ..close(),
        shade,
      );
    }
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(tail - 4, 0, w - 2 * tail + 8, h - 4), const Radius.circular(3));
    canvas.drawRRect(body.shift(const Offset(0, 2)), Paint()..color = const Color(0x88000000));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: highlight
              ? const [Color(0xFF2A1F6E), Color(0xFF140E40)]
              : const [Color(0xFF10234A), Color(0xFF081430)],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xCC3FD0FF),
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.highlight != highlight;
}

/// Power-ups and the army ability: a small row at the bottom that appears only when the player
/// can use something right now (their attack turn, or a question they are answering), so the map
/// stays clear the rest of the time.
class _ToolBar extends ConsumerWidget {
  const _ToolBar({required this.match, required this.mode, required this.onMode});
  final MatchView match;
  final String? mode;
  final void Function(String) onMode;

  static List<(String asset, String label, String id)> usable(MatchView m) {
    final me = m.me;
    if (me == null || me.eliminated || m.ended) return const [];
    final q = m.question;
    final inQuestion = q != null && q.participant && !q.answered && !q.resolved;
    final army = armyOf(me.army);
    bool has(String p) => me.powerups.contains(p);
    final abilityNow = me.army == 'islamic'
        ? m.phase.startsWith('expansion') && (inQuestion || (m.quota[m.mySeat] ?? 0) > 0)
        : m.myTurn;
    return [
      if (has('remove_two') && inQuestion && q.kind == 'mcq')
        ('assets/ui/powerups/remove_two.webp', 'حذف جوابين', 'remove_two'),
      if (has('hint') && inQuestion && q.kind == 'numeric') ('assets/ui/powerups/hint.webp', 'تلميح', 'hint'),
      if (has('double') && m.myTurn) ('assets/ui/powerups/double.webp', 'مضاعفة', 'double'),
      if (has('shield') && m.myTurn) ('assets/ui/powerups/shield.webp', 'درع', 'shield'),
      if (!me.abilityUsed && abilityNow) (army.abilityIcon, army.abilityName, 'ability'),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = usable(match);
    if (items.isEmpty) return const SizedBox.shrink();
    final game = ref.read(gameProvider.notifier);
    final army = armyOf(match.me!.army);
    void use(String id) {
      switch (id) {
        case 'shield':
          onMode('shield');
        case 'ability':
          if (army.abilityNeedsTerritory) {
            onMode('ability');
          } else {
            game.useAbility();
          }
        default:
          game.usePowerup(id);
      }
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.translate(offset: Offset(0, 30 * (1 - v)), child: child),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1D3D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3FD0FF), width: 1.6),
          boxShadow: const [BoxShadow(color: Color(0x803FD0FF), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (asset, label, id) in items)
              Semantics(
                button: true,
                label: label,
                child: GestureDetector(
                  onTap: () => use(id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (id == 'shield' && mode == 'shield') || (id == 'ability' && mode == 'ability')
                                ? const Color(0xFFFFCF4A)
                                : const Color(0xFF3FD0FF),
                          ),
                          child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover)),
                        ),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFFE6F7FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _logIcon(String kind) => switch (kind) {
  'attack' => Icons.gps_fixed,
  'capture' => Icons.flag,
  'held' => Icons.shield,
  'tower' => Icons.castle,
  'out' => Icons.heart_broken,
  'power' => Icons.auto_awesome,
  'round' => Icons.hourglass_bottom,
  _ => Icons.circle,
};

/// The players as a strip across the top (the map keeps the full width), richest first,
/// and a button that opens the whole war log.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    int land(int seat) => m.scoreOf(seat);
    int count(int seat) => m.territories.values.where((t) => t.owner == seat).length;
    final order = [...m.players]..sort((a, b) => land(b.seat).compareTo(land(a.seat)));
    final top = order.isEmpty ? 1 : max(1, land(order.first.seat));
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      // neon: a dark navy strip with a glowing cyan rail
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.08, 0.5, 1],
          colors: [Color(0xFF0E1D3D), Color(0xFF0A1630), Color(0xFF081228), Color(0xFF060E22)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF3FD0FF), width: 1.6)),
        boxShadow: [BoxShadow(color: Color(0x993FD0FF), blurRadius: 10)],
      ),
      child: Row(
        children: [
          // cards slide to their new place when the ranking changes (richest on the right)
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final w = min(236.0, box.maxWidth / max(1, order.length));
                return Stack(
                  children: [
                    for (final (i, p) in order.indexed)
                      AnimatedPositioned(
                        key: ValueKey('card${p.seat}'),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutBack,
                        top: 0,
                        bottom: 0,
                        width: w,
                        right: i * w,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _ScoreDelta(score: land(p.seat), child: _card(m, p, land(p.seat), count(p.seat), top)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          _RoundButton(icon: Icons.emoji_emotions_outlined, tooltip: 'وجوه وكلمات', onTap: () => _showEmotes(context)),
          const SizedBox(width: 4),
          _RoundButton(icon: Icons.receipt_long, tooltip: 'سجلّ المعركة', onTap: () => _showLog(context)),
        ],
      ),
    );
  }

  void _showEmotes(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (c) => Align(
        alignment: const Alignment(-0.95, -0.7),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(8),
            decoration: Toon.chunky(Toon.paper, radius: 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final e in emoteFaces.entries)
                  Semantics(
                    button: true,
                    label: e.value,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(c);
                        ProviderScope.containerOf(context).read(gameProvider.notifier).emote(e.key);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: Toon.chunky(Toon.card, radius: 10, depth: 2),
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: e.value.length <= 2 ? 24 : 14,
                            fontWeight: FontWeight.w900,
                            color: Toon.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1D3D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF3FD0FF), width: 1.8),
            ),
            child: Column(
              children: [
                const Text(
                  'سجلّ المعركة',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: Color(0xFF3FD0FF)),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final t in match.ticker)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                _logIcon(t.kind),
                                size: 16,
                                color: t.seat == null ? const Color(0xFF8FB3C9) : AppColors.seat(t.seat),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  t.text,
                                  style: const TextStyle(color: Color(0xFFE6F7FF), fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(MatchView m, PlayerView p, int value, int lands, int top) {
    final c = AppColors.seat(p.seat);
    final now = p.seat == m.attacker || p.seat == m.defender;
    final answered = m.question?.locked.contains(p.seat) ?? false;
    return Opacity(
      opacity: p.eliminated ? 0.45 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12284F), Color(0xFF0A1630)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.seat == m.mySeat ? AppColors.gold : c, width: p.seat == m.mySeat ? 2.4 : 1.6),
          boxShadow: [
            BoxShadow(color: (p.seat == m.mySeat ? AppColors.gold : c).withValues(alpha: 0.55), blurRadius: 8),
            if (now) BoxShadow(color: c, blurRadius: 14, spreadRadius: 1),
          ],
        ),
        child: Row(
          children: [
            // colour tab with the portrait
            Container(
              width: 48,
              // seat tab: the seat colour sunk into the navy, with a bright thread on its inner edge
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(c, AppColors.panelDeep, 0.35)!, Color.lerp(c, AppColors.panelDeep, 0.7)!],
                ),
                borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(7))
                    .resolve(TextDirection.rtl),
              ),
              alignment: Alignment.center,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.panelDeep,
                      border: Border.all(color: c, width: 1.5),
                      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)],
                    ),
                    child: ClipOval(child: Image.asset(armyOf(p.army).commander, fit: BoxFit.cover)),
                  ),
                  if (now)
                    Positioned(
                      top: -5,
                      left: -5,
                      child: _Badge(icon: p.seat == m.attacker ? Icons.gps_fixed : Icons.shield, color: AppColors.seal),
                    ),
                  if (answered)
                    const Positioned(
                      bottom: -4,
                      left: -4,
                      child: _Badge(icon: Icons.check, color: AppColors.good),
                    ),
                ],
              ),
            ),
            Container(width: 1.6, color: c),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RankBadge(p.xp, size: 15),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFE6F7FF),
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (m.onFire.contains(p.seat)) const Text('🔥', style: TextStyle(fontSize: 12, height: 1)),
                        if (m.king == p.seat) const Text('👑', style: TextStyle(fontSize: 12, height: 1)),
                        if (p.bot || p.away) const Icon(Icons.smart_toy_outlined, size: 12, color: Color(0xFF8FB3C9)),
                        if (!p.connected) const Icon(Icons.wifi_off, size: 12, color: AppColors.bad),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          p.eliminated ? 'خرج' : '$value',
                          style: TextStyle(
                            color: Color.lerp(c, Colors.white, 0.15),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.flag, size: 11, color: Color(0xFF8FB3C9)),
                        Text(
                          ' $lands',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8FB3C9),
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: value / top,
                        minHeight: 4,
                        backgroundColor: const Color(0x22000000),
                        color: c,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.panel,
            border: Border.all(color: const Color(0xFF3FD0FF), width: 1.6),
            boxShadow: const [BoxShadow(color: Color(0x803FD0FF), blurRadius: 8)],
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF3FD0FF)),
        ),
      ),
    ),
  );
}

/// The latest war-log line, shown briefly in the corner of the map.
class _LogToast extends StatelessWidget {
  const _LogToast({required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context) {
    final t = match.ticker.isEmpty ? null : match.ticker.first;
    if (t == null || DateTime.now().difference(t.at) > const Duration(seconds: 5)) return const SizedBox.shrink();
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(t),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1D3D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3FD0FF), width: 1.4),
            boxShadow: const [BoxShadow(color: Color(0x803FD0FF), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _logIcon(t.kind),
                size: 16,
                color: t.seat == null ? const Color(0xFF8FB3C9) : AppColors.seat(t.seat),
              ),
              const SizedBox(width: 6),
              Text(
                t.text,
                style: const TextStyle(color: Color(0xFFE6F7FF), fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: AppColors.gold, width: 1),
    ),
    child: Icon(icon, size: 11, color: Colors.white),
  );
}

/// This round's attack order: portraits left to right in reading order, the current attacker
/// large and glowing, finished turns greyed with a check, and how long until my turn.
class TurnStrip extends StatelessWidget {
  const TurnStrip({super.key, required this.match});
  final MatchView match;

  static String? untilText(int? n) => switch (n) {
    null || 0 => null,
    1 => 'إنت الجاي!',
    2 => 'دورك بعد دورين',
    _ => 'دورك بعد $n أدوار',
  };

  @override
  Widget build(BuildContext context) {
    final m = match;
    final until = m.turnsUntilMine();
    final note = untilText(until);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE6081430),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x993FD0FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'الأدوار',
            style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.gold, fontSize: 15, height: 1.2),
          ),
          const SizedBox(width: 6),
          for (final (i, s) in m.roundOrder.indexed) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 14, color: AppColors.textSecondary),
            _turnFace(m, s),
          ],
          if (note != null) ...[const SizedBox(width: 8), _NextNote(text: note, urgent: until == 1)],
        ],
      ),
    );
  }

  Widget _turnFace(MatchView m, int seat) {
    final now = seat == m.attacker;
    final done = m.turnDone.contains(seat) || m.players[seat].eliminated;
    final mine = seat == m.mySeat;
    final d = now ? 34.0 : 26.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: done ? 0.4 : 1,
          child: Container(
            width: d,
            height: d,
            padding: EdgeInsets.all(now ? 2.5 : 1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mine ? AppColors.gold : AppColors.seat(seat),
              boxShadow: [if (now) BoxShadow(color: AppColors.seat(seat), blurRadius: 10, spreadRadius: 1)],
            ),
            child: ClipOval(child: Image.asset(armyOf(m.players[seat].army).commander, fit: BoxFit.cover)),
          ),
        ),
        if (done)
          const Positioned(
            bottom: -2,
            left: -2,
            child: Icon(Icons.check_circle, size: 13, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _NextNote extends StatelessWidget {
  const _NextNote({required this.text, required this.urgent});
  final String text;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: urgent ? AppColors.seal : const Color(0xFF0B1730),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold, width: urgent ? 1.5 : 1),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, height: 1.2)),
    );
    if (!urgent) return chip;
    // "you're next" beats gently so it is noticed
    return TweenAnimationBuilder<double>(
      key: const ValueKey('next'),
      tween: Tween(begin: 1.3, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: chip,
    );
  }
}

/// Seconds left in the current stage, as a small seal that turns red at the end.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.until});
  final DateTime until;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = (widget.until.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 99);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: left <= 3 ? AppColors.bad : const Color(0xFF3FD0FF),
        border: Border.all(color: const Color(0xFFFFCF4A), width: 1.5),
      ),
      child: Center(
        child: Text(
          '$left',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, height: 1.1),
        ),
      ),
    );
  }
}

/// After tapping a target: pick the duel question's category from three.
class _CategoryChooser extends StatelessWidget {
  const _CategoryChooser({required this.categories, required this.onPick, required this.onCancel});
  final List<String> categories;
  final void Function(String) onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(
        scale: 0.8 + 0.2 * v,
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: Toon.chunky(Toon.paper, radius: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'شو نوع سؤال الهجوم؟',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Toon.ink, height: 1.3),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'رجوع',
                  child: GestureDetector(
                    onTap: onCancel,
                    child: const Icon(Icons.close, color: Toon.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Semantics(
                      button: true,
                      label: c,
                      child: GestureDetector(
                        onTap: () => onPick(c),
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          decoration: Toon.chunky(const Color(0xFF3B2A86), radius: 12),
                          child: Column(
                            children: [
                              Icon(categoryIcon(c), color: Colors.white, size: 28),
                              const SizedBox(height: 2),
                              Text(
                                c,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shakes the battlefield briefly when a tower falls (hard) or land is taken (light).
class _Shake extends StatefulWidget {
  const _Shake({required this.match, required this.child});
  final MatchView match;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  Fx? _seen;
  double _amp = 0;

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    final fx = widget.match.fx;
    final last = fx.isEmpty ? null : fx.last;
    if (last != null && !identical(last, _seen)) {
      _seen = last;
      final amp = switch (last.kind) {
        'tower' => 9.0,
        'capture' => 5.0,
        'held' => 3.0,
        _ => 0.0,
      };
      if (amp > 0) {
        _amp = amp;
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        if (!_c.isAnimating) return child!;
        final k = (1 - t) * _amp;
        return Transform.translate(offset: Offset(sin(t * 50) * k, cos(t * 37) * k * 0.6), child: child);
      },
    );
  }
}

/// Floats «+150» / «−150» over a player card whenever their score changes.
class _ScoreDelta extends StatefulWidget {
  const _ScoreDelta({required this.score, required this.child});
  final int score;
  final Widget child;

  @override
  State<_ScoreDelta> createState() => _ScoreDeltaState();
}

class _ScoreDeltaState extends State<_ScoreDelta> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  int _delta = 0;

  @override
  void didUpdateWidget(_ScoreDelta old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _delta = widget.score - old.score;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: widget.child),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            if (!_c.isAnimating || _delta == 0) return const SizedBox.shrink();
            final t = _c.value;
            return Positioned(
              left: 8,
              top: 18 - 26 * Curves.easeOut.transform(t),
              child: Opacity(
                opacity: t < 0.7 ? 1 : (1 - t) / 0.3,
                child: Text(
                  _delta > 0 ? '+$_delta' : '−${-_delta}',
                  style: TextStyle(
                    color: _delta > 0 ? const Color(0xFF5DFFB0) : AppColors.bad,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 3),
                      Shadow(color: Colors.black, blurRadius: 6),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

const emoteFaces = {
  'laugh': '😂',
  'clap': '👏',
  'angry': '😡',
  'shock': '😱',
  'strong': '💪',
  'deal': '🤝',
  'cool': '😎',
  'think': '🤔',
  'bravo': 'برافو!',
  'go': 'يلّا!',
  'luck': 'حظ أوفر!',
  'watch': 'انتبه!',
};

/// Speech bubbles under the player cards for recent emotes (same layout as the top strip).
class _EmoteBubbles extends StatelessWidget {
  const _EmoteBubbles({required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final order = [...m.players]..sort((a, b) => m.scoreOf(b.seat).compareTo(m.scoreOf(a.seat)));
    final now = DateTime.now();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final w = min(236.0, (box.maxWidth - 12 - 92) / max(1, order.length));
          return Stack(
            children: [
              for (final (i, p) in order.indexed)
                if (m.emotes[p.seat] case (final id, final at) when now.difference(at).inMilliseconds < 2600)
                  Positioned(
                    right: 6 + i * w + w / 2 - 40,
                    top: 2,
                    width: 80,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(at),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) => Transform.scale(scale: v, child: child),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: Toon.chunky(Toon.card, radius: 14, depth: 2),
                          child: Text(
                            emoteFaces[id] ?? '',
                            style: TextStyle(
                              fontSize: (emoteFaces[id] ?? '').length <= 2 ? 26 : 14,
                              fontWeight: FontWeight.w900,
                              color: Toon.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// The screen's edge glows and breathes while it is my move (no blur: four edge gradients).
class _TurnGlow extends StatefulWidget {
  const _TurnGlow({required this.active});
  final bool active;

  @override
  State<_TurnGlow> createState() => _TurnGlowState();
}

class _TurnGlowState extends State<_TurnGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_TurnGlow old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedOpacity(
          opacity: widget.active ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) =>
                CustomPaint(painter: _EdgeGlowPainter(0.35 + 0.45 * Curves.easeInOut.transform(_c.value))),
          ),
        ),
      ),
    );
  }
}

class _EdgeGlowPainter extends CustomPainter {
  _EdgeGlowPainter(this.k);
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final w = min(size.width, size.height) * 0.09;
    final c = AppColors.neon.withValues(alpha: 0.55 * k);
    const clear = Color(0x003FD0FF);
    void edge(Rect r, Alignment from) => canvas.drawRect(
      r,
      Paint()..shader = LinearGradient(begin: from, end: -from, colors: [c, clear]).createShader(r),
    );
    edge(Rect.fromLTWH(0, 0, size.width, w), Alignment.topCenter);
    edge(Rect.fromLTWH(0, size.height - w, size.width, w), Alignment.bottomCenter);
    edge(Rect.fromLTWH(0, 0, w, size.height), Alignment.centerLeft);
    edge(Rect.fromLTWH(size.width - w, 0, w, size.height), Alignment.centerRight);
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) => old.k != k;
}

/// A new stage: a bright vertical scan line sweeps right to left (the reading direction) with a
/// fading trail and a faint flash, once.
class _ScanWipe extends StatefulWidget {
  const _ScanWipe({super.key});

  @override
  State<_ScanWipe> createState() => _ScanWipeState();
}

class _ScanWipeState extends State<_ScanWipe> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => _c.value >= 1
            ? const SizedBox.shrink()
            : CustomPaint(painter: _ScanPainter(Curves.easeInOut.transform(_c.value))),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * (1.1 - 1.2 * t);
    // a faint flash of the whole screen at the start
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.neon.withValues(alpha: 0.10 * (1 - t)));
    final trail = Rect.fromLTWH(x, 0, size.width * 0.35, size.height);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(colors: [AppColors.neon.withValues(alpha: 0.28), const Color(0x003FD0FF)])
            .createShader(trail),
    );
    canvas.drawRect(Rect.fromLTWH(x - 2, 0, 4, size.height), Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawRect(Rect.fromLTWH(x - 8, 0, 16, size.height), Paint()..color = AppColors.neon.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t;
}

/// Slow drifting motes of light over the map: a few dozen dots that twinkle (its own layer).
class _Motes extends StatefulWidget {
  const _Motes();

  @override
  State<_Motes> createState() => _MotesState();
}

class _MotesState extends State<_Motes> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _MotesPainter(_c.value * 60)),
        ),
      ),
    );
  }
}

class _MotesPainter extends CustomPainter {
  _MotesPainter(this.t);
  final double t; // seconds

  static final _seeds = [
    for (var i = 0; i < 36; i++)
      (Random(i * 7919).nextDouble(), Random(i * 104729).nextDouble(), 0.4 + Random(i * 31).nextDouble()),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final (i, (x0, y0, s)) in _seeds.indexed) {
      final y = ((y0 - t * 0.008 * s) % 1.0) * size.height; // rise slowly
      final x = (x0 + 0.015 * sin(t * 0.4 * s + i)) * size.width;
      final a = 0.25 + 0.35 * (0.5 + 0.5 * sin(t * 1.7 * s + i * 1.3));
      p.color = (i % 5 == 0 ? AppColors.violet : AppColors.neon).withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), 1.1 + s, p);
    }
  }

  @override
  bool shouldRepaint(_MotesPainter old) => old.t != t;
}
