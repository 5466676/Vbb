import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../game/game_state.dart';

/// The question on a parchment scroll, with a timer bar. MCQ: four buttons in the player's
/// own option order. Numeric: a number field. Spectators see it greyed out.
class QuestionPanel extends StatefulWidget {
  const QuestionPanel({
    super.key,
    required this.match,
    required this.onChoice,
    required this.onValue,
    required this.onTick,
  });

  final MatchView match;
  final void Function(int) onChoice;
  final void Function(double) onValue;
  final VoidCallback onTick; // last-5-seconds tick sound

  @override
  State<QuestionPanel> createState() => _QuestionPanelState();
}

class _QuestionPanelState extends State<QuestionPanel> {
  Timer? _timer;
  final _num = TextEditingController();
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final left = _leftMs();
      final sec = (left / 1000).ceil();
      final q = widget.match.question;
      if (q != null && !q.resolved && !q.answered && q.participant && sec <= 5 && sec > 0 && sec != _lastTick) {
        _lastTick = sec;
        widget.onTick();
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(QuestionPanel old) {
    super.didUpdateWidget(old);
    if (old.match.question?.id != widget.match.question?.id) {
      _num.clear();
      _lastTick = -1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _num.dispose();
    super.dispose();
  }

  int _leftMs() {
    final q = widget.match.question;
    if (q == null) return 0;
    final end = q.receivedAt.add(Duration(milliseconds: q.timeMs));
    return end.difference(DateTime.now()).inMilliseconds.clamp(0, q.timeMs);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.match.question!;
    final frac = q.timeMs == 0 ? 0.0 : _leftMs() / q.timeMs;
    final spectator = !q.participant;
    final m = widget.match;
    final who = q.participants.map((s) => m.players[s].name).join(' ضد ');
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 16),
      decoration: const BoxDecoration(
        image: DecorationImage(image: AssetImage('assets/ui/question_card.webp'), fit: BoxFit.fill),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.phase == 'battle_duel' || m.phase == 'battle_tiebreak')
            Text(
              m.phase == 'battle_tiebreak' ? 'سؤال الحسم: $who' : 'مبارزة: $who',
              style: const TextStyle(color: AppColors.seal, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              q.text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: q.resolved ? 0 : frac,
              minHeight: 6,
              backgroundColor: AppColors.ink.withValues(alpha: 0.15),
              color: frac < 0.3 ? AppColors.bad : AppColors.seal,
            ),
          ),
          const SizedBox(height: 10),
          if (q.kind == 'mcq') _options(q, spectator) else _numeric(q, spectator),
          const SizedBox(height: 6),
          Text(
            spectator
                ? 'إنت عم تتفرّج'
                : q.resolved
                ? _resultLine(q)
                : q.answered
                ? 'جوابك انقفل… ناطرين الباقي (${q.locked.length}/${q.participants.length})'
                : '${(_leftMs() / 1000).ceil()} ثانية',
            style: TextStyle(color: AppColors.ink.withValues(alpha: 0.8), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _resultLine(QuestionView q) {
    final m = widget.match;
    if (q.ranking.isEmpty) return '';
    final first = m.players[q.ranking.first].name;
    if (q.kind == 'numeric') {
      final a = q.answer;
      final shown = a == null ? '' : (a == a.roundToDouble() ? a.toInt().toString() : a.toString());
      return 'الجواب: $shown ${q.unit} — الأقرب: $first';
    }
    return 'الأسرع والأصح: $first';
  }

  Widget _options(QuestionView q, bool spectator) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 5.2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (var i = 0; i < q.options.length; i++) _option(q, i, spectator)],
    );
  }

  Widget _option(QuestionView q, int i, bool spectator) {
    final removed = q.removed.contains(i);
    Color bg = AppColors.parchment;
    Color fg = AppColors.ink;
    if (q.resolved) {
      if (i == q.correctIndex) {
        bg = AppColors.good;
        fg = Colors.white;
      } else if (i == q.myChoice) {
        bg = AppColors.bad;
        fg = Colors.white;
      }
    } else if (i == q.myChoice) {
      bg = AppColors.gold;
    }
    final enabled = !spectator && !q.answered && !q.resolved && !removed;
    return Opacity(
      opacity: removed ? 0.25 : (spectator ? 0.7 : 1),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.ink.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => widget.onChoice(i) : null,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                q.options[i],
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numeric(QuestionView q, bool spectator) {
    final enabled = !spectator && !q.answered && !q.resolved;
    void send() {
      final v = double.tryParse(
        _num.text.replaceAll(',', '.').replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m.group(0)!.codeUnitAt(0) - 0x660}'),
      );
      if (v != null) widget.onValue(v);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            controller: _num,
            enabled: enabled,
            autofocus: enabled,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(color: AppColors.ink, fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: q.hintLow != null ? 'بين ${q.hintLow!.round()} و ${q.hintHigh!.round()}' : 'رقمك',
              suffixText: q.unit,
              filled: true,
              fillColor: AppColors.parchment,
            ),
            onSubmitted: (_) => send(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(onPressed: enabled ? send : null, child: const Text('أرسل')),
      ],
    );
  }
}
