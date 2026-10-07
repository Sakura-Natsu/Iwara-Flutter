import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/proxy.dart';
import 'core/settings.dart';
import 'router.dart';

class IwaraApp extends ConsumerWidget {
  const IwaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    AppHttpOverrides.proxy = settings.proxyAddress;
    final router = ref.watch(routerProvider);
    final seed = Color(settings.seedColor);

    return MaterialApp.router(
      title: 'Iwara',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: settings.themeMode,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

ThemeData buildTheme(Color seed, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF111316) : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 1,
      backgroundColor: dark ? const Color(0xFF111316) : scheme.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: dark ? const Color(0xFF181B1F) : null,
    ),
    // 注意：dividerHeight 设为 0 会导致可滚动 TabBar 收缩并居中，这里只隐藏颜色
    tabBarTheme: const TabBarThemeData(dividerColor: Colors.transparent),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}
