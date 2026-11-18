import 'package:flutter/material.dart';

import '../../../core/theme/cyber_shield_colors.dart';
import '../../../core/theme/cyber_shield_theme.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberShieldColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account',
                style: CyberShieldTheme.headlineSm(),
              ),
              const SizedBox(height: 8),
              Text(
                'Vault settings will land here in a later screen.',
                style: CyberShieldTheme.bodySm(),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CyberShieldColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CyberShieldColors.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: CyberShieldColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: CyberShieldColors.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PetrikVPN PRO',
                            style: CyberShieldTheme.headlineSm(),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Device session active',
                            style: CyberShieldTheme.labelCode(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
