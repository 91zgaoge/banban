import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/api/api_client.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/secure_storage.dart';
import 'features/companion/bloc/companion_bloc.dart';
import 'features/companion/screens/companion_screen.dart';
import 'features/onboarding/screens/bot_picker_screen.dart';
import 'features/onboarding/screens/login_screen.dart';

/// Root application widget.
class CompanionApp extends StatefulWidget {
  const CompanionApp({super.key, required this.storage});
  final SecureStorageService storage;

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) async {
        final loggedIn = await AuthRepository(
          storage: widget.storage,
          dio: ApiClient.dio,
        ).isLoggedIn();
        final isLoginRoute = state.matchedLocation == '/login';
        if (!loggedIn && !isLoginRoute) return '/login';
        if (loggedIn && isLoginRoute) return '/bots';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/bots',
          builder: (_, __) => const BotPickerScreen(),
        ),
        GoRoute(
          path: '/chat/:bot_id',
          builder: (context, state) {
            final botId = state.pathParameters['bot_id']!;
            final extra = state.extra as Map<String, dynamic>?;
            final botName = extra?['botName'] as String? ?? '伴伴';
            return BlocProvider(
              create: (_) => CompanionBloc(
                storage: widget.storage,
                baseUrl: ApiClient.dio.options.baseUrl,
              ),
              child: CompanionScreen(botId: botId, botName: botName),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '伴伴',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      routerConfig: _router,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE8A5A0), // warm blush — companion brand
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'PingFang SC', // system CJK font on Apple; fallback gracefully
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
