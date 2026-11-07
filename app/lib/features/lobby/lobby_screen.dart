import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../game/game_controller.dart';
import '../game/game_state.dart';

/// The room before the match: seats, army choice, map vote, host controls.
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gs = ref.watch(gameProvider);
    final room = gs.room;
    final game = ref.read(gameProvider.notifier);
    if (room == null) return const SizedBox.shrink();
    final me = room.seats.where((s) => s.playerId == game.myId).firstOrNull;
    final host = room.host == game.myId;
    final teams = room.settings['mode'] == 'teams';
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/ui/lobby/lobby_1.webp'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // seats
                Expanded(
                  flex: 5,
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Text('رمز الغرفة:', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            SelectableText(
                              room.code,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: AppColors.gold,
                                letterSpacing: 3,
                              ),
                            ),
                            IconButton(
                              tooltip: 'نسخ',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () => Clipboard.setData(ClipboardData(text: room.code)),
                            ),
                            const Spacer(),
                            Text('${room.seats.length}/${room.settings['max_players'] ?? 8}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final s in room.seats)
                                _SeatRow(seat: s, isHost: room.host == s.playerId, canKick: host, teams: teams),
                            ],
                          ),
                        ),
                        if (host) _HostBar(room: room),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // my choices
                Expanded(
                  flex: 4,
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('اختار جيشك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: GridView.count(
                            crossAxisCount: 4,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            children: [
                              for (final a in armies)
                                _ArmyTile(army: a, selected: me?.army == a.id, onTap: () => game.chooseArmy(a.id)),
                            ],
                          ),
                        ),
                        if (me != null) _ArmyInfo(army: armyOf(me.army)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('الخريطة:'),
                            const SizedBox(width: 8),
                            for (final k in const ['fantasy', 'world'])
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    '${k == 'fantasy' ? 'خيالية' : 'العالم'} (${room.votes.values.where((v) => v == k).length})',
                                  ),
                                  selected: room.votes[game.myId] == k,
                                  onSelected: (_) => game.voteMap(k),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(onPressed: game.leave, child: const Text('اطلع')),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: me == null ? null : () => game.setReady(!me.ready),
                                style: FilledButton.styleFrom(
                                  backgroundColor: (me?.ready ?? false) ? AppColors.good : AppColors.gold,
                                ),
                                child: Text((me?.ready ?? false) ? 'جاهز ✓' : 'أنا جاهز'),
                              ),
                            ),
                          ],
                        ),
                      ],
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
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.background.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.glassBorder),
    ),
    child: child,
  );
}

class _SeatRow extends ConsumerWidget {
  const _SeatRow({required this.seat, required this.isHost, required this.canKick, required this.teams});
  final Seat seat;
  final bool isHost;
  final bool canKick;
  final bool teams;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final army = armyOf(seat.army);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.seat(seat.seat), width: 1.5),
      ),
      child: Row(
        children: [
          ClipOval(child: Image.asset(army.commander, width: 44, height: 44, fit: BoxFit.cover)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${seat.name}${isHost ? ' 👑' : ''}${seat.bot != null ? ' 🤖 ${_bot(seat.bot!)}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(army.name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (teams) Text('فريق ${seat.seat % 2 + 1}  ', style: const TextStyle(color: AppColors.textSecondary)),
          if (seat.bot == null)
            Icon(
              seat.ready ? Icons.check_circle : Icons.hourglass_empty,
              color: seat.ready ? AppColors.good : AppColors.textSecondary,
            ),
          if (seat.bot != null && canKick)
            IconButton(
              tooltip: 'شيل البوت',
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(gameProvider.notifier).removeBot(seat.seat),
            ),
        ],
      ),
    );
  }

  String _bot(String level) => switch (level) {
    'easy' => 'سهل',
    'hard' => 'صعب',
    _ => 'متوسط',
  };
}

class _HostBar extends ConsumerWidget {
  const _HostBar({required this.room});
  final RoomView room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.read(gameProvider.notifier);
    final teams = room.settings['mode'] == 'teams';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('ضيف بوت:'),
            for (final l in const [('easy', 'سهل'), ('medium', 'متوسط'), ('hard', 'صعب')])
              ActionChip(label: Text(l.$2), onPressed: () => game.addBot(l.$1)),
            const SizedBox(width: 10),
            FilterChip(
              label: const Text('فرق'),
              selected: teams,
              onSelected: (v) => game.updateSettings({'mode': v ? 'teams' : 'ffa'}),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FilledButton(onPressed: game.startMatch, child: const Text('ابدأ المعركة')),
      ],
    );
  }
}

class _ArmyTile extends StatelessWidget {
  const _ArmyTile({required this.army, required this.selected, required this.onTap});
  final ArmyInfo army;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: army.name,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.gold : AppColors.glassBorder, width: selected ? 3 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(army.commander, fit: BoxFit.cover),
        ),
      ),
    ),
  );
}

class _ArmyInfo extends StatelessWidget {
  const _ArmyInfo({required this.army});
  final ArmyInfo army;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          army.name,
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.gold),
        ),
        Text('ميزة: ${army.perk}', style: const TextStyle(fontSize: 12)),
        Text('قدرة «${army.abilityName}»: ${army.ability}', style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
