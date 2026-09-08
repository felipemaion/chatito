import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'strings.dart';
import 'theme.dart';

class PiriquitoApp extends ConsumerWidget {
  const PiriquitoApp({super.key, this.initialLocation});

  /// Rota inicial (útil em testes e deep links).
  final String? initialLocation;

  static const supportedLocales = [Locale('pt', 'BR')];
  static const localizationsDelegates = <LocalizationsDelegate<Object>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider(initialLocation));
    return MaterialApp.router(
      title: S.appName,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: supportedLocales.first,
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
      routerConfig: router,
    );
  }
}
