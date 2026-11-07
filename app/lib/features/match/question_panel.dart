import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
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
    final secs = (_leftMs() / 1000).ceil();
    final urgent = !q.resolved && !q.answered && secs <= 5;
    return Container(
      constraints: const BoxConstraints(maxWidth: 700),
      padding: const EdgeInsets.fromLTRB(30, 14, 30, 12),
      decoration: const BoxDecoration(
        image: DecorationImage(image: AssetImage('assets/ui/question_card.webp'), fit: BoxFit.fill),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // who is answering, with a check once each one locks in
              for (final s in q.participants.take(8)) _who(m, s, q.locked.contains(s)),
              const Spacer(),
              if (m.phase == 'battle_duel' || m.phase == 'battle_tiebreak')
                Flexible(
                  flex: 4,
                  child: Text(
                    m.phase == 'battle_tiebreak' ? 'سؤال الحسم: $who' : '⚔ $who',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.seal, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              const Spacer(),
              _Clock(secs: q.resolved ? 0 : secs, frac: q.resolved ? 0 : frac, urgent: urgent),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              q.text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800, height: 1.35),
            ),
          ),
          const SizedBox(height: 6),
          // time left
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: q.resolved ? 0 : frac,
              minHeight: 5,
              backgroundColor: AppColors.ink.withValues(alpha: 0.12),
              color: urgent ? AppColors.bad : AppColors.seal,
            ),
          ),
          const SizedBox(height: 8),
          if (q.kind == 'mcq') _options(q, spectator) else _numeric(q, spectator),
          if (spectator || q.resolved || q.answered) ...[
            const SizedBox(height: 4),
            Text(
              spectator
                  ? 'إنت عم تتفرّج'
                  : q.resolved
                  ? _resultLine(q)
                  : 'جوابك انقفل… ناطرين الباقي (${q.locked.length}/${q.participants.length})',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.85), fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _who(MatchView m, int seat, bool locked) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 4),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.seat(seat)),
          child: Opacity(
            opacity: locked ? 1 : 0.65,
            child: ClipOval(child: Image.asset(armyOf(m.players[seat].army).commander, fit: BoxFit.cover)),
          ),
        ),
        if (locked)
          Positioned(
            bottom: -3,
            left: -3,
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.good),
              child: const Icon(Icons.check, size: 11, color: Colors.white),
            ),
          ),
      ],
    ),
  );

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
      childAspectRatio: 6.2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (var i = 0; i < q.options.length; i++) _option(q, i, spectator)],
    );
  }

  Widget _option(QuestionView q, int i, bool spectator) {
    final removed = q.removed.contains(i);
    Color bg = const Color(0xFFF6EBD2);
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
          side: BorderSide(color: AppColors.ink.withValues(alpha: 0.55), width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => widget.onChoice(i) : null,
          child: Row(
            children: [
              const SizedBox(width: 6),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFFC0392B), Color(0xFF6E1A12)]),
                  border: Border.all(color: const Color(0xFFE2B85A), width: 1.2),
                ),
                child: Center(
                  child: Text(
                    const ['أ', 'ب', 'ج', 'د'][i % 4],
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, height: 1.1),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    q.options[i],
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 32),
            ],
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

/// A round brass clock face with the seconds; it reddens and beats in the last five seconds.
class _Clock extends StatelessWidget {
  const _Clock({required this.secs, required this.frac, required this.urgent});
  final int secs;
  final double frac;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(urgent ? secs : -1),
      tween: Tween(begin: urgent ? 1.25 : 1, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: urgent ? AppColors.bad : const Color(0xFF3B2610),
                border: Border.all(color: const Color(0xFFE2B85A), width: 1.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(3),
              child: CircularProgressIndicator(
                value: frac,
                strokeWidth: 3,
                color: const Color(0xFFF0CF7A),
                backgroundColor: Colors.transparent,
              ),
            ),
            Center(
              child: Text(
                '$secs',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
