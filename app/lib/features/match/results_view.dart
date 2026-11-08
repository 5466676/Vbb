import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/armies.dart';
import '../../core/ranks.dart';
import '../game/game_controller.dart';
import '../game/game_state.dart';

/// End of match: victory or defeat art, a podium for the top three, the rest below,
/// scores counting up. Everything comes from the server's standings.
class ResultsView extends ConsumerWidget {
  const ResultsView({super.key, required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final won = m.me != null && m.me!.team == m.winnerTeam;
    final rows = m.standings ?? const [];
    final game = ref.read(gameProvider.notifier);
    final podium = rows.take(3).toList();
    final rest = rows.skip(3).toList();
    int lands(int seat) => m.territories.values.where((t) => t.owner == seat).length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background, // until the painting has loaded
        image: DecorationImage(
          image: AssetImage(won ? 'assets/ui/victory.webp' : 'assets/ui/defeat.webp'),
          fit: BoxFit.cover,
          colorFilter: const ColorFilter.mode(Color(0xCC05070F), BlendMode.srcATop),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (context, s, child) => Transform.scale(scale: s, child: child),
                child: RuqaaTitle(won ? 'نصر!' : 'هزيمة', size: 64, color: won ? AppColors.gold : AppColors.bad),
              ),
              const SizedBox(height: 4),
              // podium: 2nd, 1st, 3rd (1st in the middle and highest)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final i in const [1, 0, 2])
                    if (i < podium.length)
                      _Step(match: m, rank: i, row: podium[i], lands: lands(podium[i]['seat'] as int)),
                ],
              ),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: WoodPanel(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Column(children: [for (var i = 0; i < rest.length; i++) _row(m, i + 3, rest[i])]),
                  ),
                ),
              ],
              if (m.xpBefore != null) ...[const SizedBox(height: 10), _XpPanel(before: m.xpBefore!, gain: m.xpGain)],
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (game.offline) ...[
                    SizedBox(
                      width: 190,
                      child: WarButton(
                        label: 'مباراة ثانية',
                        kind: WarButtonKind.seal,
                        icon: Icons.replay,
                        onPressed: () => game.replayOffline(),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  SizedBox(
                    width: 190,
                    child: WarButton(label: 'رجوع للقائمة', icon: Icons.home_outlined, onPressed: () => game.leave()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(MatchView m, int rank, Map<String, dynamic> r) {
    final seat = r['seat'] as int;
    final p = m.players[seat];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${rank + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          ClipOval(child: Image.asset(armyOf(p.army).commander, width: 28, height: 28, fit: BoxFit.cover)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.name,
              style: TextStyle(color: AppColors.seat(seat), fontWeight: FontWeight.w800),
            ),
          ),
          _CountUp(
            value: r['score'] as int,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          Text('✓ ${r['correct']}', style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.match, required this.rank, required this.row, required this.lands});
  final MatchView match;
  final int rank;
  final Map<String, dynamic> row;
  final int lands;

  @override
  Widget build(BuildContext context) {
    final seat = row['seat'] as int;
    final p = match.players[seat];
    final c = AppColors.seat(seat);
    final first = rank == 0;
    final portrait = first ? 96.0 : 72.0;
    final height = const [150.0, 112.0, 88.0][rank];
    const medal = [AppColors.gold, Color(0xFFCFE6F5), Color(0xFFFF8A3D)];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + 250 * (2 - rank)),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 60 * (1 - t)),
        child: Opacity(opacity: t.clamp(0, 1), child: child),
      ),
      child: SizedBox(
        width: first ? 180 : 150,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first) const Icon(Icons.workspace_premium, color: AppColors.gold, size: 34),
            Container(
              width: portrait,
              height: portrait,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: medal[rank],
                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: first ? 18 : 8)],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.panelDeep),
                child: ClipOval(child: Image.asset(armyOf(p.army).commander, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: first ? 18 : 15,
                color: AppColors.textPrimary,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(c, AppColors.panelDeep, 0.45)!, Color.lerp(c, AppColors.panelDeep, 0.85)!],
                ),
                border: Border.all(color: medal[rank], width: 1.6),
                boxShadow: [BoxShadow(color: medal[rank].withValues(alpha: 0.6), blurRadius: 12)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${rank + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: first ? 40 : 30,
                      color: medal[rank],
                      shadows: [Shadow(color: medal[rank], blurRadius: 12)],
                      height: 1,
                    ),
                  ),
                  _CountUp(
                    value: row['score'] as int,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                  ),
                  Text(
                    '✓ ${row['correct']}  •  🚩 $lands',
                    style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 12, fontWeight: FontWeight.w700),
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

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 1400),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text('${v.round()}', style: style),
  );
}

/// Experience from this match: the bar fills, the level ticks up, and a «RANK UP» notice glows
/// when a new rank is reached (GAME_RULES §9).
class _XpPanel extends StatelessWidget {
  const _XpPanel({required this.before, required this.gain});
  final int before, gain;

  @override
  Widget build(BuildContext context) {
    final after = before + gain;
    final up = rankOf(after) != rankOf(before);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final xp = before + (gain * t).round();
        final c = rankColor(rankOf(xp));
        return Container(
          width: 420,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: AppColors.window(edge: up && t >= 1 ? rankColor(rankOf(after)) : AppColors.neon),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (up)
                AnimatedOpacity(
                  opacity: t >= 1 ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RankBadge(before, size: 34),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'RANK UP',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 26,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(color: c, blurRadius: 16),
                                Shadow(color: c, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                        RankBadge(after, size: 34),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  RankBadge(xp, size: 26),
                  const SizedBox(width: 10),
                  Text('المستوى ${levelOf(xp)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const Spacer(),
                  Text(
                    '+${(gain * t).round()} خبرة',
                    style: const TextStyle(color: AppColors.good, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: AppColors.panelDeep,
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: rankProgress(xp),
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.violet, c]),
                        boxShadow: [BoxShadow(color: c, blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                toNextRank(xp) == 0 ? 'وصلت لأعلى رتبة!' : 'باقي ${toNextRank(xp)} خبرة للرتبة ${_next(xp)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _next(int xp) => ranks.firstWhere((r) => r.$2 > xp, orElse: () => ranks.last).$1;
}
