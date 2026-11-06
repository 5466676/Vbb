import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/widgets/glass_panel.dart';

/// Home screen placeholder. Buttons are wired up in phase 6.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2A3A), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'حرب العقول',
                      textAlign: TextAlign.center,
                      style: textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أجب أسرع، واغزُ أكثر',
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const FilledButton(onPressed: null, child: Text('لعب سريع')),
                    const SizedBox(height: 12),
                    const OutlinedButton(onPressed: null, child: Text('إنشاء غرفة')),
                    const SizedBox(height: 12),
                    const OutlinedButton(onPressed: null, child: Text('الانضمام بكود')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
