import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'router.dart';
import 'theme.dart';

/// Root widget. The app is Arabic-only and always right-to-left.
class HarbApp extends StatelessWidget {
  const HarbApp({super.key});

  static const locale = Locale('ar');

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'حرب العقول',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Force RTL even if the device locale is not Arabic.
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
      routerConfig: appRouter,
    );
  }
}
