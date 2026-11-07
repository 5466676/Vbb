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
    return near.isEmpty ? free : near;
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
            Row(
              children: [
                SizedBox(width: 214, child: _SidePanel(match: m)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // the open question takes the lower part; the map moves up instead of being covered
                      const questionRoom = 0.0;
                      return Stack(
                        children: [
                          // the same painting, darkened, fills the space around the map
                          Positioned.fill(
                            child: Image.asset(
                              t.image,
                              fit: BoxFit.cover,
                              color: const Color(0xB0140C05),
                              colorBlendMode: BlendMode.darken,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 44,
                            bottom: questionRoom,
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
                              left: 70,
                              right: 0,
                              child: Center(
                                child: IgnorePointer(child: TurnStrip(match: m)),
                              ),
                            ),
                          if (asking)
                            Positioned(
                              left: 66,
                              right: 6,
                              top: 44,
                              bottom: 6,
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
                          if (!m.ended)
                            Positioned(
                              left: 6,
                              top: 52,
                              child: _ToolBar(
                                match: m,
                                mode: _territoryMode,
                                onMode: (mode) => setState(() => _territoryMode = _territoryMode == mode ? null : mode),
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

/// Power-ups and the army ability: round brass medallions with a name under each,
/// a count badge, and a lock when it cannot be used right now.
class _ToolBar extends ConsumerWidget {
  const _ToolBar({required this.match, required this.mode, required this.onMode});
  final MatchView match;
  final String? mode;
  final void Function(String) onMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = match.me;
    if (me == null || me.eliminated) return const SizedBox.shrink();
    final game = ref.read(gameProvider.notifier);
    final q = match.question;
    final inQuestion = q != null && q.participant && !q.answered && !q.resolved;
    final army = armyOf(me.army);
    Widget tool(
      String asset,
      String label, {
      required bool owned,
      required bool now,
      required VoidCallback onTap,
      bool active = false,
    }) {
      final usable = owned && now;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: usable ? onTap : null,
            borderRadius: BorderRadius.circular(30),
            child: SizedBox(
              width: 58,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: active || usable
                                ? const [Color(0xFFF0CF7A), Color(0xFF8A5A17)]
                                : const [Color(0xFF6B5A44), Color(0xFF3A2E20)],
                          ),
                          boxShadow: [
                            if (active) const BoxShadow(color: Color(0xAAFFD36B), blurRadius: 10, spreadRadius: 1),
                            const BoxShadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 2)),
                          ],
                        ),
                        child: ClipOval(
                          child: ColorFiltered(
                            colorFilter: owned
                                ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                                : const ColorFilter.matrix([
                                    0.3, 0.5, 0.1, 0, 0, //
                                    0.3, 0.5, 0.1, 0, 0,
                                    0.3, 0.5, 0.1, 0, 0,
                                    0, 0, 0, 0.6, 0,
                                  ]),
                            child: Image.asset(asset, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        left: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: owned ? AppColors.seal : const Color(0xFF3A2E20),
                            border: Border.all(color: AppColors.gold, width: 1),
                          ),
                          child: Center(
                            child: owned && !now
                                ? const Icon(Icons.lock_clock, size: 11, color: AppColors.textPrimary)
                                : Text(
                                    owned ? '1' : '0',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, height: 1.1),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: usable ? AppColors.textPrimary : AppColors.textSecondary,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    bool has(String p) => me.powerups.contains(p);
    return Column(
      children: [
        tool(
          'assets/ui/powerups/remove_two.webp',
          'حذف جوابين',
          owned: has('remove_two'),
          now: inQuestion && q.kind == 'mcq',
          onTap: () => game.usePowerup('remove_two'),
        ),
        tool(
          'assets/ui/powerups/hint.webp',
          'تلميح',
          owned: has('hint'),
          now: inQuestion && q.kind == 'numeric',
          onTap: () => game.usePowerup('hint'),
        ),
        tool(
          'assets/ui/powerups/double.webp',
          'مضاعفة',
          owned: has('double'),
          now: match.myTurn,
          onTap: () => game.usePowerup('double'),
        ),
        tool(
          'assets/ui/powerups/shield.webp',
          'درع',
          owned: has('shield'),
          now: match.phase.startsWith('battle'),
          onTap: () => onMode('shield'),
          active: mode == 'shield',
        ),
        tool(
          army.abilityIcon,
          army.abilityName,
          owned: !me.abilityUsed,
          now: true,
          onTap: () {
            if (army.abilityNeedsTerritory) {
              onMode('ability');
            } else {
              game.useAbility();
            }
          },
          active: mode == 'ability',
        ),
      ],
    );
  }
}

/// Player cards (portrait, land value, territories, share bar, turn badges) and the war log.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    int land(int seat) => m.territories.values.where((t) => t.owner == seat).fold(0, (a, t) => a + t.value);
    int count(int seat) => m.territories.values.where((t) => t.owner == seat).length;
    final order = [...m.players]..sort((a, b) => land(b.seat).compareTo(land(a.seat)));
    final top = order.isEmpty ? 1 : max(1, land(order.first.seat));
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2E1F10), Color(0xFF1B120A)],
        ),
        border: Border(left: BorderSide(color: Color(0xFF8A5A17), width: 2)),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              children: [
                for (var i = 0; i < order.length; i++)
                  _card(m, order[i], i, land(order[i].seat), count(order[i].seat), top),
              ],
            ),
          ),
          Container(
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF8A5A17))),
            ),
            child: const Text(
              'سجلّ المعركة',
              style: TextStyle(fontFamily: AppTheme.headingFont, color: AppColors.gold, fontSize: 15, height: 1.2),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              children: [
                for (final (i, t) in m.ticker.take(14).indexed)
                  Opacity(
                    opacity: max(0.35, 1 - i * 0.08),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Icon(
                            _logIcon(t.kind),
                            size: 14,
                            color: t.seat == null ? AppColors.gold : AppColors.seat(t.seat),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              t.text,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _logIcon(String kind) => switch (kind) {
    'attack' => Icons.gps_fixed,
    'capture' => Icons.flag,
    'held' => Icons.shield,
    'tower' => Icons.castle,
    'out' => Icons.heart_broken,
    'power' => Icons.auto_awesome,
    'round' => Icons.hourglass_bottom,
    _ => Icons.circle,
  };

  Widget _card(MatchView m, PlayerView p, int rank, int value, int lands, int top) {
    final c = AppColors.seat(p.seat);
    final fighting = p.seat == m.attacker || p.seat == m.defender;
    final answered = m.question?.locked.contains(p.seat) ?? false;
    return Opacity(
      opacity: p.eliminated ? 0.4 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [
              c.withValues(alpha: fighting ? 0.55 : 0.28),
              const Color(0xFF241709),
            ],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          border: Border.all(
            color: p.seat == m.mySeat ? AppColors.gold : c.withValues(alpha: 0.7),
            width: p.seat == m.mySeat ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                  child: ClipOval(child: Image.asset(armyOf(p.army).commander, fit: BoxFit.cover)),
                ),
                if (p.seat == m.attacker || p.seat == m.defender)
                  Positioned(
                    top: -4,
                    left: -4,
                    child: _Badge(icon: p.seat == m.attacker ? Icons.gps_fixed : Icons.shield, color: AppColors.seal),
                  ),
                if (answered)
                  const Positioned(
                    bottom: -3,
                    left: -3,
                    child: _Badge(icon: Icons.check, color: AppColors.good),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2),
                        ),
                      ),
                      if (p.bot) const Icon(Icons.smart_toy_outlined, size: 13, color: AppColors.textSecondary),
                      if (!p.connected) const Icon(Icons.wifi_off, size: 13, color: AppColors.bad),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        p.eliminated ? 'خرج' : '$value',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.gold,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.flag, size: 11, color: AppColors.textSecondary),
                      Text(
                        ' $lands',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: value / top,
                      minHeight: 5,
                      backgroundColor: const Color(0x33000000),
                      color: c,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
