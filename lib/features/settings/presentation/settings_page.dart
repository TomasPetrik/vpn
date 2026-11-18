import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/theme/cyber_shield_colors.dart';
import '../../../core/theme/cyber_shield_theme.dart';
import '../../device/data/device_info_source.dart';
import '../../device/domain/device_repository.dart';
import '../../vpn/presentation/vpn_connect_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _privacyUrl = 'https://petrixon.com/vpn/privacy/';
  static const _termsUrl = 'https://petrixon.com/vpn/terms/';

  @override
  Widget build(BuildContext context) {
    final packageInfo = getIt<PackageInfo>();

    return Scaffold(
      backgroundColor: CyberShieldColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: CyberShieldColors.background,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'Settings',
                  style: CyberShieldTheme.headlineSm().copyWith(
                    fontSize: 24,
                    height: 32 / 24,
                    letterSpacing: -0.02 * 24,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _SettingsSection(
                    title: 'Legal',
                    children: [
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'How we handle device data',
                        onTap: () => _openUrl(context, _privacyUrl),
                      ),
                      const _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.description_outlined,
                        title: 'Terms of Use',
                        subtitle: 'Service terms and conditions',
                        onTap: () => _openUrl(context, _termsUrl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'Support',
                    children: [
                      _SettingsTile(
                        icon: Icons.bug_report_outlined,
                        title: 'Send diagnostic data',
                        subtitle: 'Upload connect log to your device record',
                        onTap: () => _sendDiagnosticData(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'About',
                    children: [
                      _SettingsTile(
                        icon: Icons.info_outline,
                        title: 'App version',
                        subtitle:
                            '${packageInfo.version} (${packageInfo.buildNumber})',
                        trailing: Text(
                          'v${packageInfo.version}',
                          style: CyberShieldTheme.labelCode(
                            color: CyberShieldColors.secondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openUrl(BuildContext context, String raw) async {
    final uri = Uri.parse(raw);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  static Future<void> _sendDiagnosticData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Uploading diagnostic data…')),
    );

    try {
      final body = await _buildDiagnosticPayload();
      final result =
          await getIt<DeviceRepository>().submitDiagnostics(body);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Sent: ${result.summary}')),
      );
    } catch (_) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send diagnostic data')),
      );
    }
  }

  static Future<Map<String, dynamic>> _buildDiagnosticPayload() async {
    final packageInfo = getIt<PackageInfo>();
    final config = getIt<AppConfig>();
    final secureStore = getIt<SecureStore>();
    final deviceInfo = await getIt<DeviceInfoSource>().collect();
    final connect = getIt<VpnConnectCubit>().state;
    final installationId = await secureStore.readInstallationId();

    String? userId;
    String? deviceId;
    String? clientIp;
    String? clientCountry;
    try {
      final session = await getIt<DeviceRepository>().me();
      userId = session.userId;
      deviceId = session.deviceId;
      clientIp = session.clientIp;
      clientCountry = session.clientCountry;
    } catch (_) {}

    final log = connect.log
        .map(
          (line) => <String, dynamic>{
            'at': line.at.toUtc().toIso8601String(),
            'message': line.message,
          },
        )
        .toList(growable: false);

    return <String, dynamic>{
      'summary': log.isEmpty
          ? 'Diagnostic report'
          : 'Connect log · ${log.length} lines',
      'meta': <String, dynamic>{
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'api_base_url': config.apiBaseUrl,
        'dev_mode': config.isDevMode,
      },
      'app': <String, dynamic>{
        'name': packageInfo.appName,
        'version': packageInfo.version,
        'build': packageInfo.buildNumber,
        'package': packageInfo.packageName,
      },
      'device': <String, dynamic>{
        'platform': deviceInfo.platform.isNotEmpty
            ? deviceInfo.platform
            : (Platform.isIOS
                ? 'ios'
                : Platform.isAndroid
                    ? 'android'
                    : Platform.operatingSystem),
        'manufacturer': deviceInfo.manufacturer,
        'model': deviceInfo.model,
        'os_version': deviceInfo.osVersion,
        'physical': deviceInfo.isPhysicalDevice,
        'installation_id': installationId,
        'user_id': userId,
        'device_id': deviceId,
        'client_ip': clientIp,
        'client_country': clientCountry,
      },
      'vpn': <String, dynamic>{
        'phase': connect.phase.name,
        'step': connect.stepLabel,
        'connected': connect.isConnected,
        'server': connect.peer?.server.name,
        'country': connect.peer?.server.countryCode,
        'latency_ms': connect.latencyMs,
        'rx_bytes': connect.rxBytes ?? 0,
        'tx_bytes': connect.txBytes ?? 0,
        'rx_mbps': connect.rxMbps,
        'tx_mbps': connect.txMbps,
        'session_seconds': connect.sessionSeconds,
      },
      'log': log,
    };
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: CyberShieldTheme.labelBadge(),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: CyberShieldColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 58,
      color: CyberShieldColors.outlineVariant.withValues(alpha: 0.35),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chevron = onTap == null
        ? null
        : Icon(
            Icons.chevron_right,
            size: 20,
            color: CyberShieldColors.onSurfaceVariant,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CyberShieldColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: CyberShieldColors.secondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CyberShieldTheme.bodySm(
                        color: CyberShieldColors.onSurface,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: CyberShieldTheme.labelCode(),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                if (chevron != null) const SizedBox(width: 4),
              ],
              ?chevron,
            ],
          ),
        ),
      ),
    );
  }
}
