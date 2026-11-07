import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../game/game_controller.dart';
import '../game/game_state.dart';

/// End of match: victory or defeat art and the final standings (from the server).
class ResultsView extends ConsumerWidget {
  const ResultsView({super.key, required this.match});
  final MatchView match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final won = m.me != null && m.me!.team == m.winnerTeam;
    final rows = m.standings ?? const [];
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(won ? 'assets/ui/victory.webp' : 'assets/ui/defeat.webp'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken),
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? 'النصر!' : 'انتهت المعركة',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: won ? AppColors.gold : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < rows.length; i++) _row(m, i, rows[i]),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => ref.read(gameProvider.notifier).leave(),
                    child: const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('رجوع للقائمة')),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: seat == m.mySeat ? AppColors.seat(seat).withValues(alpha: 0.35) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${rank + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ),
          ClipOval(child: Image.asset(armyOf(p.army).commander, width: 30, height: 30, fit: BoxFit.cover)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.name,
              style: TextStyle(color: AppColors.seat(seat), fontWeight: FontWeight.w800),
            ),
          ),
          Text('${r['score']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Text('✓ ${r['correct']}', style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
