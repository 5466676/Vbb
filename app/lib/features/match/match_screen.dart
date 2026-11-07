import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../../core/map_template.dart';
import '../game/game_controller.dart';
import '../game/game_state.dart';
import 'duel_splash.dart';
import 'map_view.dart';
import 'question_arena.dart';
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
    if (m.phase == 'expansion_picks') {
      game.togglePick(id);
    } else if (m.myTurn) {
      game.chooseTarget(id);
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
        : m.phase == 'expansion_picks'
        ? _legalPicks(m)
        : m.myTurn
        ? m.targets.toSet()
        : <int>{};

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
                            child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF77B9C5))),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 44,
                            bottom: 0,
                            child: MapView(
                              template: t,
                              match: m,
                              version: gs.version,
                              highlight: highlight,
                              selected: m.myPicks.toSet(),
                              onTap: (id) => _tap(m, id),
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
                                  onTick: () => ref.read(gameProvider.notifier).sound.play('tick'),
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
        'expansion_question' => 'التوسّع — الجولة ${m.expansionRound}',
        'expansion_picks' =>
          (m.quota[m.mySeat] ?? 0) > 0
              ? 'اختار ${m.quota[m.mySeat]} أرض (${m.myPicks.length}/${m.quota[m.mySeat]})'
              : 'الباقين عم يختاروا أراضيهم…',
        'battle_target' => m.myTurn ? 'دورك! اختار أرض لتهاجمها' : 'دور ${name(m.attacker)} بالهجوم',
        'battle_duel' => 'مبارزة: ${name(m.attacker)} ضد ${name(m.defender)}',
        'battle_tiebreak' => 'تعادل! سؤال الحسم',
        'results' => 'انتهت المعركة',
        _ => 'استعدّوا…',
      },
    };
    final round = m.battleRound > 0 ? '  •  جولة المعارك ${m.battleRound}/${m.rounds}' : '';
    return _Ribbon(
      highlight: m.myTurn || (m.phase == 'expansion_picks' && (m.quota[m.mySeat] ?? 0) > 0),
      child: Text(
        '$text$round',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink, height: 1.3),
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
    final shade = Paint()..color = const Color(0xFF8C6A3A);
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
              ? const [Color(0xFFFFE7A6), Color(0xFFE2B85A)]
              : const [Color(0xFFF4E6C6), Color(0xFFD9C29A)],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x884A3418),
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
          color: const Color(0xFFFFF3D6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3A2414), width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0xFF3A2414), offset: Offset(0, 3))],
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
                                ? const Color(0xFFFFC233)
                                : const Color(0xFF3A2414),
                          ),
                          child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover)),
                        ),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF2B1A0E),
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
    int land(int seat) => m.territories.values.where((t) => t.owner == seat).fold(0, (a, t) => a + t.value);
    int count(int seat) => m.territories.values.where((t) => t.owner == seat).length;
    final order = [...m.players]..sort((a, b) => land(b.seat).compareTo(land(a.seat)));
    final top = order.isEmpty ? 1 : max(1, land(order.first.seat));
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB57A43), Color(0xFF8A5528)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF3A2414), width: 3)),
      ),
      child: Row(
        children: [
          for (final p in order)
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _card(m, p, land(p.seat), count(p.seat), top),
                ),
              ),
            ),
          const SizedBox(width: 4),
          _RoundButton(icon: Icons.receipt_long, tooltip: 'سجلّ المعركة', onTap: () => _showLog(context)),
        ],
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
              color: const Color(0xFFFFF3D6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF3A2414), width: 3),
            ),
            child: Column(
              children: [
                const Text(
                  'سجلّ المعركة',
                  style: TextStyle(fontFamily: AppTheme.headingFont, fontSize: 26, color: Color(0xFF6E1A12)),
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
                                color: t.seat == null ? const Color(0xFF8A5528) : AppColors.seat(t.seat),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  t.text,
                                  style: const TextStyle(color: Color(0xFF2B1A0E), fontWeight: FontWeight.w700),
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
          color: const Color(0xFFFFF3D6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: p.seat == m.mySeat ? const Color(0xFFFFC233) : const Color(0xFF3A2414),
            width: p.seat == m.mySeat ? 3 : 2,
          ),
          boxShadow: [
            const BoxShadow(color: Color(0xFF3A2414), offset: Offset(0, 2)),
            if (now) BoxShadow(color: c, blurRadius: 10, spreadRadius: 1),
          ],
        ),
        child: Row(
          children: [
            // colour tab with the portrait
            Container(
              width: 48,
              decoration: BoxDecoration(
                color: c,
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
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFF3A2414), width: 1.5),
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
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2B1A0E),
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (p.bot) const Icon(Icons.smart_toy_outlined, size: 12, color: Color(0xFF8A5528)),
                        if (!p.connected) const Icon(Icons.wifi_off, size: 12, color: AppColors.bad),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          p.eliminated ? 'خرج' : '$value',
                          style: TextStyle(
                            color: Color.lerp(c, Colors.black, 0.25),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.flag, size: 11, color: Color(0xFF8A5528)),
                        Text(
                          ' $lands',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A5528),
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
            color: const Color(0xFFFFC233),
            border: Border.all(color: const Color(0xFF3A2414), width: 2.5),
            boxShadow: const [BoxShadow(color: Color(0xFF3A2414), offset: Offset(0, 2))],
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF3A2414)),
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
            color: const Color(0xFFFFF3D6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3A2414), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFF3A2414), offset: Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _logIcon(t.kind),
                size: 16,
                color: t.seat == null ? const Color(0xFF8A5528) : AppColors.seat(t.seat),
              ),
              const SizedBox(width: 6),
              Text(
                t.text,
                style: const TextStyle(color: Color(0xFF2B1A0E), fontWeight: FontWeight.w900),
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
        color: const Color(0xCC1B120A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x99D4A64A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'الأدوار',
            style: TextStyle(fontFamily: AppTheme.headingFont, color: AppColors.gold, fontSize: 15, height: 1.2),
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
        color: urgent ? AppColors.seal : const Color(0xFF3B2610),
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
