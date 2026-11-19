import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/cyber_shield_colors.dart';
import '../../../core/theme/cyber_shield_theme.dart';
import '../data/vpn_privacy_disclosure_store.dart';

/// Shows the required pre-VPN data disclosure. Returns true if the user continues.
Future<bool> ensureVpnPrivacyDisclosureAccepted(BuildContext context) async {
  final store = getIt<VpnPrivacyDisclosureStore>();
  if (store.hasAccepted) {
    return true;
  }
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: CyberShieldColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => const _VpnPrivacyDisclosureSheet(),
  );
  return accepted == true;
}

class _VpnPrivacyDisclosureSheet extends StatelessWidget {
  const _VpnPrivacyDisclosureSheet();

  static const _privacyUrl = 'https://petrixon.com/vpn/privacy/';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CyberShieldColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Before you connect',
              style: CyberShieldTheme.headlineSm().copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'PetrikVPN needs a short disclosure before the tunnel starts.',
              style: CyberShieldTheme.bodySm(),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.52,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bullet(
                      title: 'What we collect',
                      body:
                          'Anonymous device registration, device/app metadata, '
                          'WireGuard public key, and technical peer stats '
                          '(handshake / byte counters). Optional diagnostic '
                          'reports only if you send them from Settings.',
                    ),
                    const SizedBox(height: 12),
                    _Bullet(
                      title: 'How we use it',
                      body:
                          'To provide the VPN, keep the service secure, enforce '
                          'required app updates, and prevent abuse.',
                    ),
                    const SizedBox(height: 12),
                    _Bullet(
                      title: 'What we do not do',
                      body:
                          'We do not sell your data. We do not use VPN traffic '
                          'content for advertising. We do not disclose VPN '
                          'traffic content to third parties for advertising or '
                          'marketing. We do not keep browsing-history or DNS '
                          'content logs of tunneled traffic.',
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => _openPrivacy(context),
                      style: TextButton.styleFrom(
                        foregroundColor: CyberShieldColors.secondaryContainer,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      child: const Text('Read full Privacy Policy'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await getIt<VpnPrivacyDisclosureStore>().accept();
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not now',
                style: CyberShieldTheme.bodySm(
                  color: CyberShieldColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openPrivacy(BuildContext context) async {
    final uri = Uri.parse(_privacyUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Privacy Policy')),
      );
    }
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: CyberShieldTheme.labelBadge(
              color: CyberShieldColors.secondaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: CyberShieldTheme.bodySm(
              color: CyberShieldColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
