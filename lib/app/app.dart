import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/di/injection.dart';
import '../features/debug/presentation/dev_api_button.dart';

class PetrikVpnApp extends StatelessWidget {
  const PetrikVpnApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final isDevMode = getIt<AppConfig>().isDevMode;
    return MaterialApp.router(
      title: 'PetrikVPN',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B4F6C)),
        useMaterial3: true,
      ),
      routerConfig: router,
      builder: (context, child) {
        if (!isDevMode) {
          return child ?? const SizedBox.shrink();
        }
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            DevApiButton(
              onPressed: () => router.push('/debug/api-log'),
            ),
          ],
        );
      },
    );
  }
}
