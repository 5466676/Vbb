import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/settings_store.dart';

/// Server link, player name, sound volumes, and account restore.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final SettingsStore s = ref.read(settingsProvider);
  late final _url = TextEditingController(text: s.serverUrl);
  late final _name = TextEditingController(text: s.name);
  final _user = TextEditingController();
  final _pin = TextEditingController();
  String? _status;
  late double _sfx = s.sfxVolume;

  Future<void> _save() async {
    await s.setServerUrl(_url.text);
    final nameChanged = _name.text.trim() != s.name;
    await s.setName(_name.text);
    if (nameChanged) await s.clearSession(); // the next login sends the new name
    setState(() => _status = 'عم نفحص…');
    final ok = await ref.read(apiProvider).health();
    if (!mounted) return;
    setState(() => _status = ok ? 'انحفظ — السيرفر شغّال ✓' : 'انحفظ — بس السيرفر مش عم يرد');
  }

  Future<void> _account(bool restore) async {
    final api = ref.read(apiProvider);
    try {
      if (restore) {
        await api.restore(_user.text, _pin.text);
        setState(() => _status = 'رجع حسابك لهالجهاز ✓');
      } else {
        final name = await api.setAccount(_user.text, _pin.text);
        setState(() => _status = 'صار عندك حساب: $name ✓');
      }
    } on ApiError catch (e) {
      setState(
        () => _status = switch (e.status) {
          401 => 'الاسم أو الرقم السري غلط',
          409 => 'هالاسم مأخوذ',
          429 => 'محاولات كتير، استنى شوي',
          _ => 'ما زبط: ${e.message}',
        },
      );
    } catch (_) {
      setState(() => _status = 'السيرفر مش عم يرد');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), backgroundColor: AppColors.background),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'رابط السيرفر', hintText: 'https://pc.tailnet.ts.net'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'اسمك باللعبة'),
          ),
          const SizedBox(height: 6),
          FilledButton(onPressed: _save, child: const Text('احفظ وافحص')),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_status!, textAlign: TextAlign.center),
            ),
          const Divider(height: 32),
          Text('صوت المؤثرات: ${(_sfx * 100).round()}%'),
          Slider(
            value: _sfx,
            onChanged: (v) => setState(() => _sfx = v),
            onChangeEnd: (v) => s.setVolumes(sfx: v),
          ),
          const Divider(height: 32),
          const Text('حسابك (لترجع لحسابك على موبايل جديد)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'رقم سري (4–8 أرقام)'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _account(false), child: const Text('اعمل حساب')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(onPressed: () => _account(true), child: const Text('رجّع حسابي')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('رقم جهازك: ${s.deviceId}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
