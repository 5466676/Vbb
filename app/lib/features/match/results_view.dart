import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/armies.dart';
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
        image: DecorationImage(
          image: AssetImage(won ? 'assets/ui/victory.webp' : 'assets/ui/defeat.webp'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken),
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
                child: RuqaaTitle(
                  won ? 'نصر!' : 'هزيمة',
                  size: 64,
                  color: won ? AppColors.gold : const Color(0xFFD9C7A0),
                ),
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
    const medal = [Color(0xFFF0CF7A), Color(0xFFCFD3D6), Color(0xFFC98B4E)];
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
            if (first) const Icon(Icons.workspace_premium, color: Color(0xFFF0CF7A), size: 34),
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
                decoration: BoxDecoration(shape: BoxShape.circle, color: c),
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
                  colors: [c.withValues(alpha: 0.95), Color.lerp(c, Colors.black, 0.55)!],
                ),
                border: Border.all(color: medal[rank], width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${rank + 1}',
                    style: TextStyle(
                      fontFamily: AppTheme.headingFont,
                      fontSize: first ? 40 : 30,
                      color: medal[rank],
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
