import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api.dart';
import '../../core/armies.dart';
import '../../core/settings_store.dart';
import '../../core/sound.dart';
import '../game/game_controller.dart';
import 'category_picker.dart';

/// Main menu over one of the four painted backgrounds.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static final _bg = 1 + Random().nextInt(4);
  bool? _serverUp;
  static List<String> _lastCategories = const [];

  @override
  void initState() {
    super.initState();
    _check();
    ref.read(soundProvider).music('menu');
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
    final choice = await showDialog<({int bots, String level, String map, List<String> categories, bool open})>(
      context: context,
      builder: (c) => _OfflineDialog(
        army: ref.read(settingsProvider).army,
        onArmy: (a) {
          ref.read(settingsProvider).setArmy(a);
          ref.read(soundProvider).capture(a); // the army's war cry
        },
      ),
    );
    if (choice == null || !mounted) return;
    await ref
        .read(gameProvider.notifier)
        .startOffline(
          bots: List.filled(choice.bots, choice.level),
          mapKind: choice.map,
          categories: choice.categories,
          openEnded: choice.open,
        );
    if (mounted) context.push('/play');
  }

  Future<void> _create() async {
    if (!await _ready() || !mounted) return;
    final cats = await pickCategories(context, _lastCategories);
    if (cats == null || !mounted) return;
    _lastCategories = cats;
    ref.read(gameProvider.notifier).createRoom(categories: cats);
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
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    // the crest's empty scroll carries the game's name
                    child: AspectRatio(
                      aspectRatio: 873 / 845,
                      child: LayoutBuilder(
                        builder: (context, box) => Stack(
                          children: [
                            Positioned.fill(child: Image.asset('assets/ui/logo.webp')),
                            Align(
                              alignment: const Alignment(0, 0.70),
                              child: RuqaaTitle(
                                'حرب العقول',
                                size: box.maxWidth * 0.085,
                                color: const Color(0xFF6E1A12),
                                outline: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: WoodPanel(
                  width: 330,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const RuqaaTitle('حرب العقول', size: 40),
                          const SizedBox(height: 10),
                          WarButton(
                            label: 'العب ضد البوتات (بلا نت)',
                            kind: WarButtonKind.seal,
                            icon: Icons.shield_moon_outlined,
                            height: 56,
                            onPressed: _offline,
                          ),
                          const SizedBox(height: 8),
                          WarButton(label: 'مباراة سريعة أونلاين', icon: Icons.bolt, onPressed: _quick),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: WarButton(label: 'أنشئ غرفة', onPressed: _create),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: WarButton(label: 'ادخل بغرفة', onPressed: _join),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          WarButton(
                            label: 'تدريب (بلا نت)',
                            icon: Icons.menu_book,
                            onPressed: () => context.push('/solo'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: WarButton(
                                  label: 'الصدارة',
                                  icon: Icons.emoji_events_outlined,
                                  onPressed: () => context.push('/leaderboard'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: WarButton(
                                  label: 'الإعدادات',
                                  icon: Icons.settings,
                                  onPressed: () async {
                                    await context.push('/settings');
                                    _check();
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // a quiet note: playing offline needs no server, so "off" is not an error here
                          InkWell(
                            onTap: up == false ? _check : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  up == true ? Icons.wifi : Icons.wifi_off,
                                  size: 14,
                                  color: up == true ? AppColors.good : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    up == null
                                        ? 'عم نفحص السيرفر…'
                                        : (up ? 'أونلاين جاهز' : 'أونلاين مو متاح هلق • اللعب بلا نت شغّال'),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
  const _OfflineDialog({required this.army, required this.onArmy});
  final String army;
  final void Function(String) onArmy;

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog> {
  int _bots = 3;
  String _level = 'medium';
  String _map = 'fantasy';
  List<String> _categories = const [];
  bool _open = true;
  late String _army = widget.army;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: WoodPanel(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RuqaaTitle('مجلس الحرب', size: 32),
                const SizedBox(height: 12),
                // your army: portrait, perk and ability
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final a in armies)
                        Semantics(
                          button: true,
                          selected: a.id == _army,
                          label: a.name,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _army = a.id);
                              widget.onArmy(a.id);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 56,
                              height: 56,
                              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: a.id == _army ? AppColors.gold : const Color(0xFF3A2414),
                                boxShadow: [
                                  if (a.id == _army) const BoxShadow(color: Color(0xAAFFC233), blurRadius: 10),
                                ],
                              ),
                              child: ClipOval(child: Image.asset(a.commander, fit: BoxFit.cover)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) {
                    final a = armyOf(_army);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${a.name}  ',
                              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            TextSpan(text: 'ميزة: ${a.perk}  •  قدرة «${a.abilityName}»: ${a.ability}'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFE9D6AC), fontSize: 12.5, height: 1.4),
                      ),
                    );
                  },
                ),
                row(
                  'الخصوم',
                  Row(
                    children: [
                      _Step(icon: Icons.remove, onTap: _bots > 1 ? () => setState(() => _bots--) : null),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: Wrap(
                              spacing: -10,
                              children: [
                                for (var i = 0; i < _bots; i++)
                                  CircleAvatar(
                                    radius: 17,
                                    backgroundColor: AppColors.seat(i + 1),
                                    child: CircleAvatar(
                                      radius: 15,
                                      backgroundImage: AssetImage(armies[(i * 3 + 1) % armies.length].commander),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _Step(icon: Icons.add, onTap: _bots < 7 ? () => setState(() => _bots++) : null),
                    ],
                  ),
                ),
                row(
                  'الصعوبة',
                  BannerChoice(
                    options: const [('easy', 'سهل'), ('medium', 'متوسط'), ('hard', 'صعب')],
                    value: _level,
                    onChanged: (v) => setState(() => _level = v),
                  ),
                ),
                row(
                  'الأسئلة',
                  SizedBox(
                    height: 40,
                    child: WarButton(
                      label: _categories.isEmpty ? 'كل الفئات' : '${_categories.length} فئات مختارة',
                      icon: Icons.category,
                      height: 40,
                      fontSize: 15,
                      onPressed: () async {
                        final c = await pickCategories(context, _categories);
                        if (c != null) setState(() => _categories = c);
                      },
                    ),
                  ),
                ),
                row(
                  'المدة',
                  BannerChoice(
                    options: const [(true, 'مفتوحة'), (false, 'بالجولات')],
                    value: _open,
                    onChanged: (v) => setState(() => _open = v),
                  ),
                ),
                row(
                  'الخريطة',
                  BannerChoice(
                    options: const [('fantasy', 'خيالية'), ('world', 'العالم')],
                    value: _map,
                    onChanged: (v) => setState(() => _map = v),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: WarButton(
                        label: 'للمعركة!',
                        kind: WarButtonKind.seal,
                        onPressed: () => Navigator.pop(context, (
                          bots: _bots,
                          level: _level,
                          map: _map,
                          categories: _categories,
                          open: _open,
                        )),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: WarButton(label: 'إلغاء', onPressed: () => Navigator.pop(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: WarButton(label: '', icon: icon, height: 40, onPressed: onTap),
  );
}
