import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/local_store.dart';
import '../../core/sound.dart';
import '../../core/sync_service.dart';

/// Offline training: rounds of 10 questions from the downloaded solo pack.
/// Every answer is stored in `pending_actions` first and synced later; the server grades it.
class SoloScreen extends ConsumerStatefulWidget {
  const SoloScreen({super.key});

  @override
  ConsumerState<SoloScreen> createState() => _SoloScreenState();
}

class _SoloScreenState extends ConsumerState<SoloScreen> {
  static const perRound = 10;
  final _uuid = const Uuid();
  final _num = TextEditingController();
  List<Map<String, dynamic>> _round = [];
  int _i = 0;
  int _right = 0;
  int? _picked;
  bool _revealed = false;
  late String _session;
  late DateTime _shownAt;
  bool _loading = true;
  String? _note;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final store = ref.read(localStoreProvider);
    setState(() => _loading = true);
    if (await store.questionCount() == 0) {
      setState(() => _note = 'عم ننزّل أسئلة التدريب…');
      await ref.read(syncProvider).sync();
    }
    var all = await store.questions();
    if (all.isEmpty) {
      // never reached a server: train on the questions bundled with the app
      all = [
        for (final q in jsonDecode(await rootBundle.loadString('assets/questions/solo.json')) as List)
          (q as Map).cast<String, dynamic>(),
      ];
    }
    all.shuffle(Random());
    setState(() {
      _round = all.take(perRound).toList();
      _i = 0;
      _right = 0;
      _picked = null;
      _revealed = false;
      _session = _uuid.v4();
      _shownAt = DateTime.now();
      _loading = false;
      _note = all.isEmpty ? 'ما في أسئلة تدريب على الجهاز لسا. افتح التدريب مرة وإنت متصل بالسيرفر.' : null;
    });
  }

  String _ts(DateTime t) {
    final off = t.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    String two(int v) => v.abs().toString().padLeft(2, '0');
    return '${t.toIso8601String()}$sign${two(off.inHours)}:${two(off.inMinutes % 60)}';
  }

  Future<void> _answer({int? choice, double? value}) async {
    if (_revealed) return;
    final q = _round[_i];
    final now = DateTime.now();
    await ref.read(localStoreProvider).addPending({
      'id': _uuid.v4(),
      'type': 'answer',
      'ts': _ts(now),
      'session_id': _session,
      'question_id': q['id'],
      'choice': ?choice,
      'value': ?value,
      'elapsed_ms': now.difference(_shownAt).inMilliseconds,
    });
    final ok = q['kind'] == 'mcq' ? choice == q['correct_index'] : value == (q['answer'] as num).toDouble();
    if (ok) _right++;
    ref.read(soundProvider).play(ok ? 'correct' : 'wrong');
    setState(() {
      _picked = choice;
      _revealed = true;
    });
  }

  Future<void> _next() async {
    if (_i + 1 >= _round.length) {
      await ref.read(localStoreProvider).addPending({
        'id': _uuid.v4(),
        'type': 'session_end',
        'ts': _ts(DateTime.now()),
        'session_id': _session,
      });
      unawaited(ref.read(syncProvider).sync()); // quietly, if the server is on
      setState(() => _i++);
      return;
    }
    _num.clear();
    setState(() {
      _i++;
      _picked = null;
      _revealed = false;
      _shownAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'تدريب',
      child: Center(
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (_note != null) Padding(padding: const EdgeInsets.all(12), child: Text(_note!)),
                ],
              )
            : _note != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_note!, textAlign: TextAlign.center),
              )
            : _i >= _round.length
            ? _summary()
            : _question(_round[_i]),
      ),
    );
  }

  Widget _summary() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$_right / ${_round.length}',
        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.gold),
      ),
      const Text('النقاط الرسمية بيحسبها السيرفر لما يتزامن'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _start,
        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('جولة جديدة')),
      ),
    ],
  );

  Widget _question(Map<String, dynamic> q) {
    final mcq = q['kind'] == 'mcq';
    final options = [for (final o in (q['options'] as List? ?? [])) '$o'];
    final correct = q['correct_index'] as int?;
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      padding: const EdgeInsets.fromLTRB(40, 22, 40, 18),
      decoration: const BoxDecoration(
        image: DecorationImage(image: AssetImage('assets/ui/question_card.webp'), fit: BoxFit.fill),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_i + 1}/${_round.length} • ${q['category']}',
            style: const TextStyle(color: AppColors.seal, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            q['text'] as String,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (mcq)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < options.length; i++)
                  SizedBox(
                    width: 300,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: !_revealed
                            ? AppColors.parchment
                            : i == correct
                            ? AppColors.good
                            : i == _picked
                            ? AppColors.bad
                            : AppColors.parchmentDark,
                        foregroundColor: AppColors.ink,
                      ),
                      onPressed: _revealed ? null : () => _answer(choice: i),
                      child: Text(options[i]),
                    ),
                  ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _num,
                    enabled: !_revealed,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.ink, fontSize: 22),
                    decoration: InputDecoration(suffixText: '${q['unit'] ?? ''}', fillColor: AppColors.parchment),
                    onSubmitted: (v) => _answer(value: double.tryParse(v)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _revealed ? null : () => _answer(value: double.tryParse(_num.text)),
                  child: const Text('أرسل'),
                ),
              ],
            ),
          if (_revealed) ...[
            const SizedBox(height: 8),
            if (!mcq)
              Text(
                'الجواب: ${q['answer']} ${q['unit'] ?? ''}',
                style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 6),
            FilledButton(onPressed: _next, child: Text(_i + 1 >= _round.length ? 'النتيجة' : 'التالي')),
          ],
        ],
      ),
    );
  }
}
