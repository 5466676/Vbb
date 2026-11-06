import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harb_al_oqool/app/app.dart';
import 'package:harb_al_oqool/app/theme.dart';

void main() {
  testWidgets('app starts on the home screen in Arabic RTL', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HarbApp()));
    await tester.pumpAndSettle();

    expect(find.text('حرب العقول'), findsOneWidget);
    expect(find.text('لعب سريع'), findsOneWidget);

    final context = tester.element(find.text('حرب العقول'));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(Localizations.localeOf(context).languageCode, 'ar');
  });

  test('theme uses the teal accent and the Cairo font', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.primary, const Color(0xFF2DD4BF));
    expect(theme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
  });
}
