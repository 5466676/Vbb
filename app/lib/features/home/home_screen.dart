import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/settings_store.dart';
import '../game/game_controller.dart';

/// Main menu over one of the four painted backgrounds.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static final _bg = 1 + Random().nextInt(4);
  bool? _serverUp;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final up = await ref.read(apiProvider).health();
    if (!mounted) return;
    setState(() => _serverUp = up);
    if (up) ref.read(gameProvider.notifier).connect();
  }

  Future<bool> _ready() async {
    if (ref.read(settingsProvider).serverUrl.isEmpty) {
      context.push('/settings');
      return false;
    }
    if (!(_serverUp ?? false)) await _check();
    if (!(_serverUp ?? false)) {
      _snack('السيرفر مطفي أو الرابط غلط. شغّل السيرفر أو صلّح الرابط بالإعدادات');
      return false;
    }
    await ref.read(gameProvider.notifier).connect();
    return true;
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _quick() async {
    if (!await _ready() || !mounted) return;
    final size = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('كم لاعب؟'),
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var n = 2; n <= 8; n++) ActionChip(label: Text('$n'), onPressed: () => Navigator.pop(c, n)),
            ],
          ),
        ],
      ),
    );
    if (size == null) return;
    ref.read(gameProvider.notifier).quickMatch('ffa', size);
    if (mounted) context.push('/play');
  }

  Future<void> _offline() async {
    final choice = await showDialog<({int bots, String level, String map})>(
      context: context,
      builder: (c) => const _OfflineDialog(),
    );
    if (choice == null || !mounted) return;
    await ref.read(gameProvider.notifier).startOffline(
          bots: List.filled(choice.bots, choice.level),
          mapKind: choice.map,
        );
    if (mounted) context.push('/play');
  }

  Future<void> _create() async {
    if (!await _ready() || !mounted) return;
    ref.read(gameProvider.notifier).createRoom();
    context.push('/play');
  }

  Future<void> _join() async {
    if (!await _ready() || !mounted) return;
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('رمز الغرفة'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 4),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('ادخل'))],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    ref.read(gameProvider.notifier).joinRoom(code);
    if (mounted) context.push('/play');
  }

  @override
  Widget build(BuildContext context) {
    final up = _serverUp;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/ui/menu/menu_$_bg.webp'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: Padding(padding: const EdgeInsets.all(12), child: Image.asset('assets/ui/logo.webp')),
                ),
              ),
              Container(
                width: 330,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'حرب العقول',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.gold),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _offline, child: const Text('العب ضد البوتات (بلا نت)')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _quick, child: const Text('مباراة سريعة أونلاين')),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(onPressed: _create, child: const Text('أنشئ غرفة')),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(onPressed: _join, child: const Text('ادخل بغرفة')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(onPressed: () => context.push('/solo'), child: const Text('تدريب (بلا نت)')),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => context.push('/leaderboard'),
                                child: const Text('الصدارة'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  await context.push('/settings');
                                  _check();
                                },
                                child: const Text('الإعدادات'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: up == null ? AppColors.textSecondary : (up ? AppColors.good : AppColors.bad),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              up == null ? 'عم نفحص السيرفر…' : (up ? 'السيرفر شغّال' : 'السيرفر مطفي'),
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            if (up == false) TextButton(onPressed: _check, child: const Text('جرّب كمان')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Offline match setup: how many bots, how strong, which map.
class _OfflineDialog extends StatefulWidget {
  const _OfflineDialog();

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog> {
  int _bots = 3;
  String _level = 'medium';
  String _map = 'fantasy';

  @override
  Widget build(BuildContext context) {
    Widget row(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [SizedBox(width: 90, child: Text(label)), Expanded(child: child)]),
        );
    return AlertDialog(
      title: const Text('ضد البوتات'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        row(
          'عدد البوتات',
          Wrap(spacing: 4, children: [
            for (var n = 1; n <= 7; n++)
              ChoiceChip(label: Text('$n'), selected: _bots == n, onSelected: (_) => setState(() => _bots = n)),
          ]),
        ),
        row(
          'الصعوبة',
          Wrap(spacing: 4, children: [
            for (final l in const [('easy', 'سهل'), ('medium', 'متوسط'), ('hard', 'صعب')])
              ChoiceChip(label: Text(l.$2), selected: _level == l.$1, onSelected: (_) => setState(() => _level = l.$1)),
          ]),
        ),
        row(
          'الخريطة',
          Wrap(spacing: 4, children: [
            for (final m in const [('fantasy', 'خيالية'), ('world', 'العالم')])
              ChoiceChip(label: Text(m.$2), selected: _map == m.$1, onSelected: (_) => setState(() => _map = m.$1)),
          ]),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (bots: _bots, level: _level, map: _map)),
          child: const Text('ابدأ'),
        ),
      ],
    );
  }
}
