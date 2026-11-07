import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api.dart';

/// Online matches only (offline answers can be faked on a device).
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _period = 'all';
  Future<Map<String, dynamic>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _data = ref.read(apiProvider).leaderboard(period: _period));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصدارة'),
        backgroundColor: AppColors.background,
        actions: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('الكل')),
              ButtonSegment(value: 'week', label: Text('هالأسبوع')),
            ],
            selected: {_period},
            onSelectionChanged: (s) {
              _period = s.first;
              _load();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('السيرفر مش عم يرد'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = (snap.data!['rows'] as List).cast<Map>();
          if (rows.isEmpty) {
            return const Center(child: Text('لسا ما في مباريات أونلاين (بلاعبين حقيقيين اتنين أو أكتر)'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final r in rows)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.ink,
                    child: Text('${r['rank']}'),
                  ),
                  title: Text('${r['name']}'),
                  subtitle: Text('${r['matches']} مباراة'),
                  trailing: Text(
                    '🏆 ${r['wins']}   ${r['score']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
