import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PetrikVpnApp extends StatelessWidget {
  const PetrikVpnApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PetrikVPN',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B4F6C)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
