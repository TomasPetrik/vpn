import 'package:flutter/material.dart';

import '../../../core/theme/cyber_shield_colors.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CyberShieldColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PetrikVPN',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: CyberShieldColors.onSurface,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(
              color: CyberShieldColors.secondaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}
