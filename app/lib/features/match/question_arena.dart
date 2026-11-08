import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../game/game_state.dart';

/// Cartoon palette for the question arena: bright paper, thick dark outlines, chunky shadows.
abstract final class Toon {
  // neon «system window» palette (names kept from the cartoon look)
  static const paper = Color(0xFF0E1D3D); // panel
  static const paperDark = Color(0xFF060E22);
  static const card = Color(0xFF10234A); // answer keys, inputs
  static const outline = Color(0xFF3FD0FF); // neon edge
  static const ink = Color(0xFFE6F7FF); // text
  static const green = Color(0xFF17A86A);
  static const red = Color(0xFFE0284A);
  static const gold = Color(0xFFFFCF4A);
  static const ringRed = Color(0xFF16305E);
  static const ringCream = Color(0xFF0A1630);

  static BoxDecoration chunky(Color fill, {double radius = 14, double depth = 4, Color? edge}) {
    final e = edge ?? (fill == card || fill == paper ? outline : Color.lerp(fill, Colors.white, 0.45)!);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(fill, Colors.white, 0.08)!, fill],
      ),
      borderRadius: BorderRadius.circular(radius * 0.55),
      border: Border.all(color: e, width: 1.6),
      boxShadow: [
        BoxShadow(
          color: e.withValues(alpha: 0.25 + 0.08 * depth),
          blurRadius: 4 + 2 * depth,
        ),
      ],
    );
  }
}

/// Icon for a question category (the owner's 23 names, matched by keyword).
IconData categoryIcon(String c) {
  if (c.contains('رياضيات')) return Icons.calculate;
  if (c.contains('رياضة')) return Icons.sports_soccer;
  if (c.contains('جغراف') || c.contains('أعلام')) return Icons.public;
  if (c.contains('تاريخ') || c.contains('الشام')) return Icons.account_balance;
  if (c.contains('دين')) return Icons.mosque;
  if (c.contains('علماء')) return Icons.lightbulb;
  if (c.contains('علوم')) return Icons.science;
  if (c.contains('فضاء')) return Icons.rocket_launch;
  if (c.contains('أدب') || c.contains('أمثال')) return Icons.menu_book;
  if (c.contains('إنجليزي')) return Icons.translate;
  if (c.contains('تكنولوجيا')) return Icons.memory;
  if (c.contains('ألعاب')) return Icons.sports_esports;
  if (c.contains('أفلام')) return Icons.movie;
  if (c.contains('فن')) return Icons.palette;
  if (c.contains('حيوان')) return Icons.pets;
  if (c.contains('أكل')) return Icons.restaurant;
  if (c.contains('جسم')) return Icons.favorite;
  if (c.contains('شركات')) return Icons.storefront;
  if (c.contains('ألغاز')) return Icons.extension;
  return Icons.help_center;
}

/// The question takes the whole battlefield: flags of the players on the sides, the question on
/// a board, four chunky answers or a number pad, and after the answer a reveal (who chose what;
/// for numbers, arrows flying into a target — the closer the answer, the closer to the centre).
class QuestionArena extends StatefulWidget {
  const QuestionArena({
    super.key,
    required this.match,
    required this.onChoice,
    required this.onValue,
    required this.onTick,
  });

  final MatchView match;
  final void Function(int) onChoice;
  final void Function(double) onValue;
  final void Function(bool urgent) onTick; // every second; urgent in the last five

  @override
  State<QuestionArena> createState() => _QuestionArenaState();
}

class _QuestionArenaState extends State<QuestionArena> {
  Timer? _timer;
  int _lastTick = -1;
  String _typed = '';
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final q = widget.match.question;
      final sec = (_leftMs() / 1000).ceil();
      // the clock ticks every second you still owe an answer, louder at the end
      if (q != null && !q.resolved && !q.answered && q.participant && sec > 0 && sec != _lastTick) {
        _lastTick = sec;
        widget.onTick(sec <= 5);
      }
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(QuestionArena old) {
    super.didUpdateWidget(old);
    if (old.match.question?.id != widget.match.question?.id) {
      _typed = '';
      _lastTick = -1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  int _leftMs() {
    final q = widget.match.question;
    if (q == null) return 0;
    final end = q.receivedAt.add(Duration(milliseconds: q.timeMs));
    return end.difference(DateTime.now()).inMilliseconds.clamp(0, q.timeMs);
  }

  bool get _canType {
    final q = widget.match.question;
    return q != null && q.kind == 'numeric' && q.participant && !q.answered && !q.resolved;
  }

  void _key(String k) {
    if (!_canType) return;
    setState(() {
      if (k == '⌫') {
        if (_typed.isNotEmpty) _typed = _typed.substring(0, _typed.length - 1);
      } else if (k == '✓') {
        final v = double.tryParse(_typed);
        if (v != null) widget.onValue(v);
      } else if (_typed.length < 9) {
        _typed += k;
      }
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || !_canType) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _key(ch);
    } else if (ch != null && RegExp('^[٠-٩]\$').hasMatch(ch)) {
      _key('${ch.codeUnitAt(0) - 0x660}');
    } else if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _key('⌫');
    } else if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _key('✓');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final q = m.question!;
    final left = _leftMs();
    final frac = q.timeMs == 0 ? 0.0 : left / q.timeMs;
    final secs = (left / 1000).ceil();
    final urgent = !q.resolved && !q.answered && secs <= 5;
    // in a duel the attacker stands on the right (where reading starts), the defender on the left
    final seats = q.participants;
    final duel = (m.phase == 'battle_duel' || m.phase == 'battle_tiebreak') && m.attacker != null;
    final right = duel
        ? [m.attacker!]
        : [
            for (var i = 0; i < seats.length; i++)
              if (i.isEven) seats[i],
          ];
    final leftSeats = duel
        ? [
            for (final s in seats)
              if (s != m.attacker) s,
          ]
        : [
            for (var i = 0; i < seats.length; i++)
              if (i.isOdd) seats[i],
          ];

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 360;
          final flagW = (box.maxWidth * 0.12).clamp(74.0, 120.0);
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Toon.outline, width: 1.8),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF00E1D3D), Color(0xF5060E22)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x993FD0FF), blurRadius: 16),
                BoxShadow(color: Color(0xAA000000), blurRadius: 24, offset: Offset(0, 6)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(10, compact ? 6 : 10, 10, compact ? 6 : 10),
            child: Column(
              children: [
                _header(q, frac, secs, urgent, duel, compact),
                SizedBox(height: compact ? 6 : 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: flagW, child: _flags(m, q, right, compact)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: q.kind == 'mcq'
                            ? _Options(match: m, question: q, onChoice: widget.onChoice, compact: compact)
                            : q.resolved
                            ? _Target(match: m, question: q)
                            : _NumberPad(
                                typed: _typed,
                                unit: q.unit,
                                hint: q.hintLow != null ? 'بين ${q.hintLow!.round()} و ${q.hintHigh!.round()}' : null,
                                enabled: _canType,
                                sent: q.answered,
                                onKey: _key,
                                compact: compact,
                              ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: flagW, child: _flags(m, q, leftSeats, compact)),
                    ],
                  ),
                ),
                if (!q.participant || q.resolved || q.answered)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      !q.participant
                          ? 'إنت عم تتفرّج'
                          : q.resolved
                          ? _resultLine(m, q)
                          : 'جوابك انقفل… ناطرين الباقي (${q.locked.length}/${q.participants.length})',
                      style: const TextStyle(color: Toon.ink, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(QuestionView q, double frac, int secs, bool urgent, bool duel, bool compact) {
    final m = widget.match;
    return Row(
      children: [
        if (q.category.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: Toon.chunky(const Color(0xFF3B2A86), radius: 10, depth: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(categoryIcon(q.category), size: 18, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  q.category,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, height: 1.2),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              if (m.phase == 'king_question')
                Text(
                  m.king == m.mySeat
                      ? '👑 إنت الملك: إذا حدا جاوب صح بياخد منك 150'
                      : '👑 سؤال الملك: أسرع جواب صح بياخد 150 من ${m.king == null ? '' : m.players[m.king!].name}',
                  style: const TextStyle(color: Toon.gold, fontWeight: FontWeight.w900, fontSize: 13, height: 1.2),
                ),
              if (duel)
                Text(
                  m.phase == 'battle_tiebreak'
                      ? 'سؤال الحسم!'
                      : '${m.players[m.attacker!].name} هاجم ${m.defender == null ? '' : m.players[m.defender!].name}'
                            '${m.mySeat != m.attacker && m.mySeat != m.defender && q.participant ? '  •  جاوب صح وخود +50' : ''}',
                  style: const TextStyle(color: Toon.red, fontWeight: FontWeight.w900, fontSize: 13, height: 1.2),
                ),
              Text(
                q.text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Toon.ink,
                  fontSize: compact ? 17 : 21,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    border: Border.all(color: Toon.outline, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: LinearProgressIndicator(
                    value: q.resolved ? 0 : frac,
                    backgroundColor: Colors.white,
                    color: urgent ? Toon.red : Toon.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _Clock(secs: q.resolved ? 0 : secs, urgent: urgent),
      ],
    );
  }

  Widget _flags(MatchView m, QuestionView q, List<int> seats, bool compact) {
    return Column(
      children: [
        for (final s in seats.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Flag(
              player: m.players[s],
              locked: q.locked.contains(s),
              rank: q.resolved ? q.ranking.indexOf(s) : -1,
              small: compact || seats.length > 2,
              role: s == m.attacker && m.phase.startsWith('battle')
                  ? 'المهاجم'
                  : s == m.defender && m.phase.startsWith('battle')
                  ? 'المدافع'
                  : null,
            ),
          ),
      ],
    );
  }

  String _resultLine(MatchView m, QuestionView q) {
    if (q.ranking.isEmpty) return '';
    final first = m.players[q.ranking.first].name;
    if (q.kind == 'numeric') {
      final a = q.answer;
      final shown = a == null ? '' : _fmt(a);
      return 'الجواب: $shown ${q.unit} • الأقرب: $first';
    }
    return 'الأسرع والأصح: $first';
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// A hanging flag in the player's colour: portrait, name, role, answered check, rank after reveal.
class _Flag extends StatelessWidget {
  const _Flag({required this.player, required this.locked, required this.rank, required this.small, this.role});
  final PlayerView player;
  final bool locked;
  final int rank; // -1 = not revealed
  final bool small;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.seat(player.seat);
    final d = small ? 40.0 : 58.0;
    return ClipPath(
      clipper: _SwallowTail(),
      child: Container(
        padding: EdgeInsets.fromLTRB(4, 6, 4, small ? 14 : 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(c, Toon.paperDark, 0.35)!, Color.lerp(c, Toon.paperDark, 0.78)!],
          ),
          border: Border.all(color: c, width: 2),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: d,
                  height: d,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Toon.paperDark,
                    border: Border.all(color: Color.lerp(c, Colors.white, 0.3)!, width: 2),
                    boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)],
                  ),
                  child: ClipOval(child: Image.asset(armyOf(player.army).commander, fit: BoxFit.cover)),
                ),
                if (rank == 0)
                  const Positioned(
                    top: -12,
                    left: 0,
                    right: 0,
                    child: Icon(Icons.workspace_premium, color: Toon.gold, size: 22),
                  ),
                if (locked && rank < 0)
                  Positioned(
                    bottom: -4,
                    left: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Toon.green,
                        border: Border.all(color: Toon.outline, width: 1.5),
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
                if (rank >= 0)
                  Positioned(
                    bottom: -4,
                    left: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rank == 0 ? Toon.gold : const Color(0xFFCFE6F5),
                        border: Border.all(color: Toon.outline, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          '${rank + 1}',
                          style: const TextStyle(
                            color: Color(0xFF05070F),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: small ? 12 : 14,
                height: 1.2,
                shadows: const [Shadow(color: Toon.outline, offset: Offset(0, 1.5))],
              ),
            ),
            if (role != null && !small)
              Text(
                role!,
                style: const TextStyle(
                  color: Color(0xFFFFF3D6),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SwallowTail extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height - 10)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(_SwallowTail old) => false;
}

/// Four chunky answer buttons; after the reveal, each shows the faces of who picked it.
class _Options extends StatelessWidget {
  const _Options({required this.match, required this.question, required this.onChoice, required this.compact});
  final MatchView match;
  final QuestionView question;
  final void Function(int) onChoice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return LayoutBuilder(
      builder: (context, box) {
        final h = ((box.maxHeight - 22) / 2).clamp(26.0, 90.0); // two rows always fit their box
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final row in const [
              [0, 1],
              [2, 3],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (final i in row)
                      if (i < q.options.length)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: SizedBox(height: h, child: _option(q, i)),
                          ),
                        ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _option(QuestionView q, int i) {
    final removed = q.removed.contains(i);
    var fill = Toon.card;
    var fg = Toon.ink;
    if (q.resolved) {
      if (i == q.correctIndex) {
        fill = Toon.green;
        fg = Colors.white;
      } else if (i == q.myChoice) {
        fill = Toon.red;
        fg = Colors.white;
      } else {
        fill = const Color(0xFF0A1428);
      }
    } else if (i == q.myChoice) {
      fill = Toon.gold;
    }
    final enabled = q.participant && !q.answered && !q.resolved && !removed;
    final pickers = q.resolved
        ? [
            for (final e in q.answers.entries)
              if (e.value['choice'] == i) e.key,
          ]
        : const <int>[];
    final pressed = i == q.myChoice && !q.resolved;
    return Opacity(
      opacity: removed ? 0.25 : 1,
      child: GestureDetector(
        onTap: enabled ? () => onChoice(i) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0),
          decoration: Toon.chunky(fill, depth: pressed ? 1 : 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF6C4AB6),
                      border: Border.all(color: Toon.outline, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        const ['أ', 'ب', 'ج', 'د'][i % 4],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        q.options[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: compact ? 15 : 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 38),
                ],
              ),
              if (pickers.isNotEmpty)
                Positioned(
                  top: -10,
                  left: 6,
                  child: Row(
                    children: [
                      for (final s in pickers)
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 2),
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.seat(s),
                            border: Border.all(color: Toon.outline, width: 1.5),
                          ),
                          child: ClipOval(
                            child: Image.asset(armyOf(match.players[s].army).commander, fit: BoxFit.cover),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big number display and a phone-style pad (also takes the keyboard).
class _NumberPad extends StatelessWidget {
  const _NumberPad({
    required this.typed,
    required this.unit,
    required this.hint,
    required this.enabled,
    required this.sent,
    required this.onKey,
    required this.compact,
  });
  final String typed;
  final String unit;
  final String? hint;
  final bool enabled;
  final bool sent;
  final void Function(String) onKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['7', '8', '9', '⌫'],
      ['4', '5', '6', '0'],
      ['1', '2', '3', '✓'],
    ];
    // a number pad reads left to right even in Arabic
    return LayoutBuilder(
      builder: (context, box) {
        final keyH = ((box.maxHeight - 60) / 3 - 8).clamp(30.0, 54.0);
        // scale the whole pad down on short screens: a pad taller than its box would leave
        // the bottom row (1 2 3 ▶) outside it, where taps never arrive (phones in landscape)
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: min(360.0, box.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 46,
                    decoration: Toon.chunky(Toon.card, radius: 10, depth: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            typed.isEmpty ? (hint ?? (sent ? 'انبعت' : 'رقمك')) : typed,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: typed.isEmpty ? 18 : 26,
                              fontWeight: FontWeight.w900,
                              color: typed.isEmpty ? const Color(0x888FB3C9) : Toon.ink,
                            ),
                          ),
                        ),
                        if (unit.isNotEmpty)
                          Text(
                            unit,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Toon.ink),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final row in keys)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            for (final k in row)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: _Key(
                                    label: k,
                                    height: keyH,
                                    enabled: enabled && (k != '✓' || typed.isNotEmpty),
                                    onTap: () => onKey(k),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.height, required this.enabled, required this.onTap});
  final String label;
  final double height;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final send = label == '✓';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label == '⌫' ? 'امسح' : (label == '✓' ? 'أرسل الرقم' : label),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            height: height,
            decoration: Toon.chunky(send ? Toon.green : Toon.card, radius: 10, depth: 3),
            child: Center(
              child: label == '⌫'
                  ? const Icon(Icons.backspace_outlined, color: Colors.white)
                  : send
                  ? const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30)
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Toon.outline, offset: Offset(0, 1.5))],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Numeric reveal: an archery target with the correct answer in the bullseye; each player's
/// arrow flies in, landing as far from the centre as their answer was from the truth.
class _Target extends StatefulWidget {
  const _Target({required this.match, required this.question});
  final MatchView match;
  final QuestionView question;

  @override
  State<_Target> createState() => _TargetState();
}

class _TargetState extends State<_Target> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final truth = q.answer ?? 0;
    final shots = <_Shot>[];
    final seats = q.participants;
    for (var i = 0; i < seats.length; i++) {
      final a = q.answers[seats[i]];
      final v = (a?['value'] as num?)?.toDouble();
      final ms = (a?['elapsed_ms'] as num?)?.toInt();
      // distance: relative error on a square-root scale, so near answers stay readable
      final rel = v == null ? 1.0 : (v - truth).abs() / max(truth.abs(), 1);
      final dist = v == null ? 1.0 : min(1.0, sqrt(rel) * 0.9);
      final angle = -pi / 2 + (i - (seats.length - 1) / 2) * (seats.length > 4 ? 0.55 : 0.85) + (i.isOdd ? pi : 0);
      shots.add(_Shot(seats[i], v, ms, dist, angle, i));
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final r = min(box.maxHeight, box.maxWidth) / 2 - 6;
          final center = Offset(box.maxWidth / 2, box.maxHeight / 2);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TargetPainter(
                    shots: shots,
                    t: _c.value,
                    radius: r,
                    center: center,
                    winner: q.ranking.isEmpty ? null : q.ranking.first,
                  ),
                ),
              ),
              // the correct answer on the bullseye
              Positioned(
                left: center.dx - 60,
                top: center.dy - 18,
                width: 120,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: Toon.chunky(Toon.card, radius: 8, depth: 2),
                    child: Text(
                      '${_fmt(truth)} ${q.unit}',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Toon.ink, height: 1.2),
                    ),
                  ),
                ),
              ),
              // each player's answer card next to where the arrow landed
              for (final s in shots)
                if (_c.value > s.start + 0.25)
                  Positioned(
                    left: (center + Offset(cos(s.angle), sin(s.angle)) * (s.dist * r + 30)).dx - 46,
                    top: (center + Offset(cos(s.angle), sin(s.angle)) * (s.dist * r + 30)).dy - 18,
                    width: 92,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: Toon.chunky(AppColors.seat(s.seat), radius: 7, depth: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (q.ranking.indexOf(s.seat) case final r when r >= 0 && r < 3)
                              Text(
                                const ['I', 'II', 'III'][r],
                                style: TextStyle(
                                  color: const [Color(0xFFFFE08A), Color(0xFFE6E6E6), Color(0xFFE0A070)][r],
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  height: 1.1,
                                ),
                              ),
                            Text(
                              s.value == null ? '—' : _fmt(s.value!),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                height: 1.2,
                              ),
                            ),
                            if (s.ms != null)
                              Text(
                                '${(s.ms! / 1000).toStringAsFixed(1)} ث',
                                style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 10, height: 1.1),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Shot {
  _Shot(this.seat, this.value, this.ms, this.dist, this.angle, int i) : start = 0.08 + i * 0.12;
  final int seat;
  final double? value;
  final int? ms;
  final double dist; // 0 centre .. 1 rim
  final double angle;
  final double start; // when its flight starts (0..1 of the animation)
}

class _TargetPainter extends CustomPainter {
  _TargetPainter({required this.shots, required this.t, required this.radius, required this.center, this.winner});
  final List<_Shot> shots;
  final double t;
  final double radius;
  final Offset center;
  final int? winner;

  @override
  void paint(Canvas canvas, Size size) {
    // wooden stand rim + rings
    canvas.drawCircle(center, radius + 6, Paint()..color = const Color(0xFF060E22));
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Toon.outline,
    );
    for (var i = 6; i >= 1; i--) {
      canvas.drawCircle(center, radius * i / 6, Paint()..color = i.isEven ? Toon.ringRed : Toon.ringCream);
    }
    canvas.drawCircle(center, radius * 0.1, Paint()..color = Toon.outline);
    for (final s in shots) {
      if (s.value == null) continue;
      final p = ((t - s.start) / 0.3).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final dir = Offset(cos(s.angle), sin(s.angle));
      final land = center + dir * (s.dist * radius);
      // flies in from outside the board along the same direction
      final from = center + dir * (radius * 2.2);
      final tip = Offset.lerp(from, land, Curves.easeInCubic.transform(p))!;
      final tail = tip + dir * radius * 0.42;
      final c = AppColors.seat(s.seat);
      canvas.drawLine(
        tip,
        tail,
        Paint()
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = Toon.outline,
      );
      canvas.drawLine(
        tip,
        tail,
        Paint()
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFE6F7FF),
      );
      // fletching in the player's colour
      final side = Offset(-dir.dy, dir.dx);
      final f0 = tail - dir * 10;
      final fletch = Path()
        ..moveTo(f0.dx, f0.dy)
        ..lineTo(tail.dx + side.dx * 9, tail.dy + side.dy * 9)
        ..lineTo(tail.dx + dir.dx * 6, tail.dy + dir.dy * 6)
        ..lineTo(tail.dx - side.dx * 9, tail.dy - side.dy * 9)
        ..close();
      canvas.drawPath(fletch, Paint()..color = c);
      canvas.drawPath(
        fletch,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Toon.outline,
      );
      if (p >= 1) {
        // impact ring, larger for the winner
        final k = ((t - s.start - 0.3) / 0.2).clamp(0.0, 1.0);
        if (k < 1) {
          canvas.drawCircle(
            land,
            6 + 14 * k,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Colors.white.withValues(alpha: 1 - k),
          );
        }
        canvas.drawCircle(land, s.seat == winner ? 5 : 3.5, Paint()..color = Toon.outline);
      }
    }
  }

  @override
  bool shouldRepaint(_TargetPainter old) => true;
}

/// A round clock face with the seconds; red and beating in the last five seconds.
class _Clock extends StatelessWidget {
  const _Clock({required this.secs, required this.urgent});
  final int secs;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(urgent ? secs : -1),
      tween: Tween(begin: urgent ? 1.3 : 1, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: urgent ? Toon.red : Toon.paperDark,
          border: Border.all(color: urgent ? const Color(0xFFFF8FA3) : Toon.outline, width: 2),
          boxShadow: [BoxShadow(color: (urgent ? Toon.red : Toon.outline).withValues(alpha: 0.7), blurRadius: 12)],
        ),
        child: Center(
          child: Text(
            '$secs',
            style: TextStyle(
              color: urgent ? Colors.white : Toon.ink,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
