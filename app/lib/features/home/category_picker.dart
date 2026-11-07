import 'package:flutter/material.dart';

import '../../app/ui_kit.dart';
import '../../core/categories.dart';
import '../match/question_arena.dart' show Toon, categoryIcon;

/// Pick the question categories for a match: tap tiles to toggle, or take them all.
/// Returns the chosen names (empty = all), or null when cancelled.
Future<List<String>?> pickCategories(BuildContext context, List<String> current) {
  return showDialog<List<String>>(
    context: context,
    builder: (c) => _CategoryPicker(initial: current),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.initial});
  final List<String> initial;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  late final Set<String> _on = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final all = _on.isEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: WoodPanel(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RuqaaTitle('شو نوع الأسئلة؟', size: 28),
              Text(
                all ? 'كل الفئات' : 'اخترت ${_on.length} من ${questionCategories.length}',
                style: const TextStyle(color: Color(0xFFE9D6AC), fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      _tile('الكل', Icons.select_all, all, () => setState(_on.clear)),
                      for (final c in questionCategories)
                        _tile(c, categoryIcon(c), _on.contains(c), () {
                          setState(() => _on.contains(c) ? _on.remove(c) : _on.add(c));
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: WarButton(
                      label: 'تمام',
                      kind: WarButtonKind.seal,
                      onPressed: () => Navigator.pop(context, _on.toList()),
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
    );
  }

  Widget _tile(String label, IconData icon, bool on, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: Toon.chunky(on ? Toon.gold : Toon.paper, radius: 10, depth: on ? 1 : 3),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Toon.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Toon.ink, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
              if (on) const Icon(Icons.check_circle, size: 16, color: Toon.green),
            ],
          ),
        ),
      ),
    );
  }
}
