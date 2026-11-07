import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../../core/map_template.dart';
import '../game/game_controller.dart';
import '../game/game_state.dart';
import 'map_view.dart';
import 'question_panel.dart';
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
    if (mounted) setState(() => _template = t);
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

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                SizedBox(width: 210, child: _SidePanel(match: m)),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: AppColors.surface,
                          child: MapView(
                            template: t,
                            match: m,
                            highlight: highlight,
                            selected: m.myPicks.toSet(),
                            onTap: (id) => _tap(m, id),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _PhaseBanner(match: m, mode: _territoryMode),
                        ),
                      ),
                      if (m.question != null && !m.ended)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 8,
                          child: Center(
                            child: QuestionPanel(
                              match: m,
                              onChoice: ref.read(gameProvider.notifier).answerChoice,
                              onValue: ref.read(gameProvider.notifier).answerValue,
                              onTick: () => ref.read(gameProvider.notifier).sound.play('tick'),
                            ),
                          ),
                        ),
                      if (!m.ended)
                        Positioned(
                          left: 8,
                          top: 56,
                          child: _ToolBar(
                            match: m,
                            mode: _territoryMode,
                            onMode: (mode) => setState(() => _territoryMode = _territoryMode == mode ? null : mode),
                          ),
                        ),
                    ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: m.myTurn ? AppColors.gold : AppColors.glassBorder, width: m.myTurn ? 2 : 1),
      ),
      child: Text('$text$round', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    );
  }
}

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
    Widget tool(String asset, String label, bool enabled, VoidCallback onTap, {bool active = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: label,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background.withValues(alpha: 0.7),
                border: Border.all(color: active ? AppColors.gold : AppColors.glassBorder, width: active ? 3 : 1),
              ),
              child: Image.asset(asset),
            ),
          ),
        ),
      ),
    );
    bool has(String p) => me.powerups.contains(p);
    return Column(
      children: [
        tool(
          'assets/ui/powerups/remove_two.webp',
          'حذف جوابين',
          has('remove_two') && inQuestion && q.kind == 'mcq',
          () => game.usePowerup('remove_two'),
        ),
        tool(
          'assets/ui/powerups/hint.webp',
          'تلميح',
          has('hint') && inQuestion && q.kind == 'numeric',
          () => game.usePowerup('hint'),
        ),
        tool(
          'assets/ui/powerups/double.webp',
          'مضاعفة',
          has('double') && match.myTurn,
          () => game.usePowerup('double'),
        ),
        tool(
          'assets/ui/powerups/shield.webp',
          'درع',
          has('shield') && match.phase.startsWith('battle'),
          () => onMode('shield'),
          active: mode == 'shield',
        ),
        tool(army.abilityIcon, 'قدرة: ${army.abilityName}', !me.abilityUsed, () {
          if (army.abilityNeedsTerritory) {
            onMode('ability');
          } else {
            game.useAbility();
          }
        }, active: mode == 'ability'),
      ],
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    int land(int seat) => m.territories.values.where((t) => t.owner == seat).fold(0, (a, t) => a + t.value);
    final order = [...m.players]..sort((a, b) => land(b.seat).compareTo(land(a.seat)));
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                for (final p in order)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: p.seat == m.attacker || p.seat == m.defender
                          ? AppColors.seat(p.seat).withValues(alpha: 0.35)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.seat(p.seat), width: p.seat == m.mySeat ? 2.5 : 1),
                    ),
                    child: Opacity(
                      opacity: p.eliminated ? 0.4 : 1,
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.seat(p.seat)),
                            child: ClipOval(child: Image.asset(armyOf(p.army).commander, fit: BoxFit.cover)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name + (p.bot ? ' 🤖' : '') + (p.connected ? '' : ' ⚠'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${land(p.seat)}${p.eliminated ? ' — خرج' : ''}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (m.question?.locked.contains(p.seat) ?? false)
                            const Icon(Icons.check_circle, size: 16, color: AppColors.good),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                for (final t in m.ticker.take(12))
                  Text(
                    t.text,
                    style: TextStyle(
                      fontSize: 12,
                      color: t.seat == null ? AppColors.textSecondary : AppColors.seat(t.seat),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
