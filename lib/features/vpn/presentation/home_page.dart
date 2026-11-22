import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/cyber_shield_colors.dart';
import '../../../core/theme/cyber_shield_theme.dart';
import '../../app_update/domain/app_store_links.dart';
import '../../app_update/presentation/app_update_cubit.dart';
import '../../device/domain/device_repository.dart';
import '../../device/domain/public_network_info.dart';
import '../../servers/domain/vpn_server.dart';
import '../../servers/presentation/server_info_cubit.dart';
import 'home/connect_dial.dart';
import 'home/country_flag.dart';
import 'vpn_connect_cubit.dart';
import 'vpn_stats_format.dart';

enum _HubVisualState { disconnected, connecting, connected }

ConnectDialVisual _dialVisual(_HubVisualState visual) => switch (visual) {
  _HubVisualState.disconnected => ConnectDialVisual.disconnected,
  _HubVisualState.connecting => ConnectDialVisual.connecting,
  _HubVisualState.connected => ConnectDialVisual.connected,
};

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDevMode = getIt<AppConfig>().isDevMode;

    return Scaffold(
      backgroundColor: CyberShieldColors.background,
      body: BlocListener<VpnConnectCubit, VpnConnectState>(
        listenWhen: (previous, current) =>
            current.errorMessage != null &&
            current.errorMessage != previous.errorMessage,
        listener: (context, state) {
          final message = state.errorMessage;
          if (message == null || message.isEmpty) {
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              backgroundColor: CyberShieldColors.errorContainer,
            ),
          );
        },
        child: BlocBuilder<VpnConnectCubit, VpnConnectState>(
          builder: (context, connect) {
            final visual = _visualFor(connect);
            return Column(
              children: [
                _HubHeader(visual: visual),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                    children: [
                      BlocBuilder<AppUpdateCubit, AppUpdateState>(
                        builder: (context, state) {
                          if (state is! AppUpdateAvailable) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SoftUpdateBanner(
                              message: state.policy.message.isEmpty
                                  ? 'Update available'
                                  : state.policy.message,
                              storeUrl: AppStoreLinks.resolve(
                                policyUrl: state.policy.updateUrl,
                                isIos: defaultTargetPlatform == TargetPlatform.iOS,
                              ),
                              onDismiss: () =>
                                  context.read<AppUpdateCubit>().dismissSoftUpdate(),
                            ),
                          );
                        },
                      ),
                      _HeroCard(connect: connect, visual: visual),
                      const SizedBox(height: 8),
                      _TelemetryGrid(connect: connect, visual: visual),
                      const SizedBox(height: 8),
                      _ServerDetailCard(connect: connect, visual: visual),
                      if (visual == _HubVisualState.connecting) ...[
                        const SizedBox(height: 8),
                        _TunnelNegotiationCard(phase: connect.phase),
                      ],
                      if (isDevMode && connect.log.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => _showConnectLog(context, connect),
                          child: const Text('Connect log'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static _HubVisualState _visualFor(VpnConnectState connect) {
    if (connect.isConnected) {
      return _HubVisualState.connected;
    }
    if (connect.isBusy) {
      return _HubVisualState.connecting;
    }
    return _HubVisualState.disconnected;
  }

  void _showConnectLog(BuildContext context, VpnConnectState connect) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CyberShieldColors.surfaceContainer,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.paddingOf(context).bottom + 16),
          child: _ConnectLogPanel(log: connect.log),
        );
      },
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.visual});

  final _HubVisualState visual;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLowest.withValues(alpha: 0.85),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 6, 20, 8),
        child: Row(
          children: [
            Image.asset(
              'assets/branding/header_mark.png',
              height: 32,
              width: 32,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.shield_outlined, size: 32, color: CyberShieldColors.secondaryContainer),
            ),
            const SizedBox(width: 10),
            Text(
              'PetrikVPN',
              style: CyberShieldTheme.headlineSm(
                color: CyberShieldColors.onSurface,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: CyberShieldColors.secondaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('FREE', style: CyberShieldTheme.labelBadge(color: CyberShieldColors.secondaryContainer)),
            ),
            const Spacer(),
            _HeaderStatusChip(visual: visual),
          ],
        ),
      ),
    );
  }
}

class _HeaderStatusChip extends StatelessWidget {
  const _HeaderStatusChip({required this.visual});

  final _HubVisualState visual;

  @override
  Widget build(BuildContext context) {
    final (label, color, border, bg, pulse) = switch (visual) {
      _HubVisualState.connected => (
        'SECURE',
        CyberShieldColors.tertiary,
        Colors.transparent,
        CyberShieldColors.surfaceContainerHigh,
        true,
      ),
      _HubVisualState.connecting => (
        'CONNECTING...',
        CyberShieldColors.secondaryContainer,
        CyberShieldColors.primary.withValues(alpha: 0.3),
        CyberShieldColors.primary.withValues(alpha: 0.1),
        true,
      ),
      _HubVisualState.disconnected => (
        'NOT SECURE',
        CyberShieldColors.onSurfaceVariant,
        Colors.transparent,
        CyberShieldColors.surfaceContainerHigh,
        false,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: color, pulse: pulse),
          const SizedBox(width: 6),
          Text(label, style: CyberShieldTheme.labelBadge(color: color)),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.connect, required this.visual});

  final VpnConnectState connect;
  final _HubVisualState visual;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (visual) {
      _HubVisualState.connecting => CyberShieldColors.primary.withValues(alpha: 0.2),
      _ => Colors.transparent,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          ConnectDial(connect: connect, visual: _dialVisual(visual)),
          const SizedBox(height: 6),
          _StatusHud(connect: connect, visual: visual),
          const SizedBox(height: 10),
          _RegionQuickSelect(connect: connect, visual: visual),
        ],
      ),
    );
  }
}

class _StatusHud extends StatelessWidget {
  const _StatusHud({required this.connect, required this.visual});

  final VpnConnectState connect;
  final _HubVisualState visual;

  @override
  Widget build(BuildContext context) {
    final latencyLabel = connect.latencyMs == null ? null : '${connect.latencyMs} ms';
    final (status, color, subIcon, subText, pulse) = switch (visual) {
      _HubVisualState.connected => (
        latencyLabel == null
            ? 'CONNECTED • ${VpnStatsFormat.duration(connect.sessionSeconds, includeHours: true)}'
            : 'CONNECTED • ${VpnStatsFormat.duration(connect.sessionSeconds, includeHours: true)} • $latencyLabel',
        CyberShieldColors.secondaryContainer,
        Icons.check_circle,
        'Secure Connection Active',
        true,
      ),
      _HubVisualState.connecting => (
        _connectingStatus(connect),
        CyberShieldColors.secondaryContainer,
        Icons.autorenew,
        _connectingSubtitle(connect),
        true,
      ),
      _HubVisualState.disconnected => (
        'DISCONNECTED',
        CyberShieldColors.onSurfaceVariant,
        Icons.shield_outlined,
        'Tap to protect your traffic',
        false,
      ),
    };

    final subColor = switch (visual) {
      _HubVisualState.connected => CyberShieldColors.tertiary,
      _HubVisualState.connecting => CyberShieldColors.secondaryContainer,
      _HubVisualState.disconnected => CyberShieldColors.outline,
    };

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: CyberShieldColors.surfaceContainerHighest.withValues(
              alpha: visual == _HubVisualState.connecting ? 0.9 : 1,
            ),
            borderRadius: BorderRadius.circular(999),
            border: visual == _HubVisualState.connecting
                ? Border.all(color: CyberShieldColors.secondaryContainer.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusDot(color: color, pulse: pulse),
              const SizedBox(width: 8),
              Text(
                status,
                style: CyberShieldTheme.labelCode(color: color, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(subIcon, size: 14, color: subColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(subText, style: CyberShieldTheme.bodySm(), textAlign: TextAlign.center),
            ),
          ],
        ),
        // Always reserve the handshake bar slot so dial/telemetry do not jump.
        const SizedBox(height: 6),
        SizedBox(
          width: 176,
          height: 4,
          child: visual == _HubVisualState.connecting
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _handshakePercent(connect.phase) / 100,
                    minHeight: 4,
                    backgroundColor: CyberShieldColors.surfaceContainerHighest,
                    valueColor: const AlwaysStoppedAnimation(
                      CyberShieldColors.secondaryContainer,
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ],
    );
  }

  static String _connectingStatus(VpnConnectState connect) {
    final pct = _handshakePercent(connect.phase);
    return 'CONNECTING • HANDSHAKE $pct%';
  }

  static String _connectingSubtitle(VpnConnectState connect) {
    final city = connect.peer?.server.city ?? connect.peer?.server.name ?? 'server';
    return switch (connect.phase) {
      VpnConnectPhase.checkingSession || VpnConnectPhase.ensuringKeys => 'Securing DNS & preparing keys…',
      VpnConnectPhase.provisioningPeer || VpnConnectPhase.preparingVpn => 'Generating cryptographic keypairs…',
      _ => 'Securing DNS & routing traffic to $city…',
    };
  }
}

class _RegionQuickSelect extends StatelessWidget {
  const _RegionQuickSelect({required this.connect, required this.visual});

  final VpnConnectState connect;
  final _HubVisualState visual;

  static const _fallbackGermany = VpnServer(
    id: 'de',
    name: 'Germany',
    countryCode: 'DE',
    city: 'Frankfurt',
    status: 'online',
  );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerInfoCubit, ServerInfoState>(
      builder: (context, state) {
        final servers = switch (state) {
          ServerInfoLoaded(:final servers) => servers,
          _ => const <VpnServer>[],
        };
        VpnServer? fromApi;
        for (final server in servers) {
          if (server.countryCode?.toUpperCase() == 'DE') {
            fromApi = server;
            break;
          }
        }
        fromApi ??= servers.isNotEmpty ? servers.first : null;
        final active = connect.peer?.server ?? fromApi ?? _fallbackGermany;

        final border = visual == _HubVisualState.connecting
            ? CyberShieldColors.secondaryContainer.withValues(alpha: 0.3)
            : CyberShieldColors.outlineVariant.withValues(alpha: 0.4);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showServerPicker(
              context,
              servers: servers.isEmpty ? const [_fallbackGermany] : servers,
              selectedId: active.id,
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: CyberShieldColors.surfaceContainerLowest.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: _RegionChip(server: active, visual: visual),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showServerPicker(
    BuildContext context, {
    required List<VpnServer> servers,
    required String selectedId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: CyberShieldColors.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                Text('Available servers', style: CyberShieldTheme.headlineSm()),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: servers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final available = _isServerAvailable(server);
                      final selected = server.id == selectedId;
                      return _ServerPickerTile(
                        server: server,
                        selected: selected,
                        available: available,
                        onTap: available ? () => Navigator.of(context).pop() : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static bool _isServerAvailable(VpnServer server) {
    return server.countryCode?.toUpperCase() == 'DE' && server.status.toLowerCase() != 'offline';
  }
}

class _ServerPickerTile extends StatelessWidget {
  const _ServerPickerTile({required this.server, required this.selected, required this.available, required this.onTap});

  final VpnServer server;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final code = server.countryCode?.toUpperCase() ?? '';
    final city = server.city ?? server.name;

    return Opacity(
      opacity: available ? 1 : 0.45,
      child: Material(
        color: selected ? CyberShieldColors.surfaceContainerHigh : CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(countryFlagEmoji(server.countryCode), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.isEmpty ? server.name : _countryName(code),
                        style: CyberShieldTheme.labelBadge(color: CyberShieldColors.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        available ? city : '$city · Unavailable',
                        style: CyberShieldTheme.labelCode(
                          color: available ? CyberShieldColors.secondaryContainer : CyberShieldColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected && available)
                  const Icon(Icons.check_circle, size: 20, color: CyberShieldColors.tertiary)
                else if (!available)
                  Text('Soon', style: CyberShieldTheme.labelBadge(color: CyberShieldColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({required this.server, required this.visual});

  final VpnServer server;
  final _HubVisualState visual;

  @override
  Widget build(BuildContext context) {
    final code = (server.countryCode ?? 'DE').toUpperCase();
    final city = server.city ?? server.name;

    final trailing = switch (visual) {
      _HubVisualState.connecting => const Icon(Icons.sync, size: 16, color: CyberShieldColors.secondaryContainer),
      _HubVisualState.connected => const Icon(Icons.check, size: 16, color: CyberShieldColors.tertiary),
      _HubVisualState.disconnected => Icon(Icons.expand_more, size: 18, color: CyberShieldColors.onSurfaceVariant),
    };

    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: visual == _HubVisualState.connecting
            ? Border.all(color: CyberShieldColors.secondaryContainer.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          Text(countryFlagEmoji(code), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _countryName(code),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CyberShieldTheme.labelBadge(color: CyberShieldColors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CyberShieldTheme.labelCode(color: CyberShieldColors.secondaryContainer).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

String _countryName(String code) {
  return switch (code.toUpperCase()) {
    'DE' => 'GERMANY',
    'RU' => 'RUSSIA',
    'NL' => 'NETHERLANDS',
    'US' => 'UNITED STATES',
    'CZ' => 'CZECHIA',
    'AE' => 'UNITED ARAB EMIRATES',
    'SK' => 'SLOVAKIA',
    'PL' => 'POLAND',
    'AT' => 'AUSTRIA',
    'CH' => 'SWITZERLAND',
    'GB' || 'UK' => 'UNITED KINGDOM',
    'FR' => 'FRANCE',
    'IT' => 'ITALY',
    'ES' => 'SPAIN',
    'UA' => 'UKRAINE',
    'TR' => 'TURKEY',
    _ => code,
  };
}

String _countryTitle(String code) {
  return switch (code.toUpperCase()) {
    'DE' => 'Germany',
    'RU' => 'Russia',
    'NL' => 'Netherlands',
    'US' => 'United States',
    'CZ' => 'Czechia',
    'AE' => 'United Arab Emirates',
    'SK' => 'Slovakia',
    'PL' => 'Poland',
    'AT' => 'Austria',
    'CH' => 'Switzerland',
    'GB' || 'UK' => 'United Kingdom',
    'FR' => 'France',
    'IT' => 'Italy',
    'ES' => 'Spain',
    'UA' => 'Ukraine',
    'TR' => 'Turkey',
    _ => code.toUpperCase(),
  };
}

class _TelemetryGrid extends StatelessWidget {
  const _TelemetryGrid({required this.connect, required this.visual});

  final VpnConnectState connect;
  final _HubVisualState visual;

  @override
  Widget build(BuildContext context) {
    final rx = connect.rxBytes ?? 0;
    final tx = connect.txBytes ?? 0;

    return Row(
      children: [
        Expanded(
          child: _TelemetryCard(
            title: 'Download',
            icon: Icons.arrow_downward,
            accent: CyberShieldColors.secondaryContainer,
            visual: visual,
            value: switch (visual) {
              _HubVisualState.disconnected => '0.0',
              _HubVisualState.connecting => '--',
              _HubVisualState.connected => VpnStatsFormat.mbpsRate(connect.rxMbps),
            },
            unit: switch (visual) {
              _HubVisualState.connecting => 'Measuring...',
              _ => 'Mbps',
            },
            badge: switch (visual) {
              _HubVisualState.disconnected => 'IDLE',
              _HubVisualState.connecting => 'TESTING',
              _HubVisualState.connected => connect.rxMbps > 0.05 ? 'LIVE' : 'IDLE',
            },
            badgeColor: switch (visual) {
              _HubVisualState.connected =>
                connect.rxMbps > 0.05 ? CyberShieldColors.tertiary : CyberShieldColors.onSurfaceVariant,
              _HubVisualState.connecting => CyberShieldColors.secondaryContainer,
              _HubVisualState.disconnected => CyberShieldColors.onSurfaceVariant,
            },
            footerLabel: visual == _HubVisualState.connecting ? 'Handshake' : 'Total',
            footerValue: visual == _HubVisualState.connecting
                ? '—'
                : VpnStatsFormat.bytes(visual == _HubVisualState.connected ? rx : 0),
            samples: connect.rxMbpsHistory,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TelemetryCard(
            title: 'Upload',
            icon: Icons.arrow_upward,
            accent: CyberShieldColors.primary,
            visual: visual,
            value: switch (visual) {
              _HubVisualState.disconnected => '0.0',
              _HubVisualState.connecting => '--',
              _HubVisualState.connected => VpnStatsFormat.mbpsRate(connect.txMbps),
            },
            unit: switch (visual) {
              _HubVisualState.connecting => 'Measuring...',
              _ => 'Mbps',
            },
            badge: switch (visual) {
              _HubVisualState.disconnected => 'IDLE',
              _HubVisualState.connecting => 'PROBING',
              _HubVisualState.connected => connect.txMbps > 0.05 ? 'LIVE' : 'IDLE',
            },
            badgeColor: switch (visual) {
              _HubVisualState.connected =>
                connect.txMbps > 0.05 ? CyberShieldColors.primary : CyberShieldColors.onSurfaceVariant,
              _HubVisualState.connecting => CyberShieldColors.primary,
              _HubVisualState.disconnected => CyberShieldColors.onSurfaceVariant,
            },
            footerLabel: visual == _HubVisualState.connecting ? 'Latency' : 'Total',
            footerValue: visual == _HubVisualState.connecting
                ? '—'
                : VpnStatsFormat.bytes(visual == _HubVisualState.connected ? tx : 0),
            samples: connect.txMbpsHistory,
          ),
        ),
      ],
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.visual,
    required this.value,
    required this.unit,
    required this.badge,
    required this.badgeColor,
    required this.footerLabel,
    required this.footerValue,
    required this.samples,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final _HubVisualState visual;
  final String value;
  final String unit;
  final String badge;
  final Color badgeColor;
  final String footerLabel;
  final String footerValue;
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    final muted = visual == _HubVisualState.disconnected;
    return Container(
      height: 136,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: visual == _HubVisualState.connecting
              ? CyberShieldColors.outlineVariant.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: muted ? CyberShieldColors.outline : accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: CyberShieldTheme.labelBadge(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: visual == _HubVisualState.connected
                      ? badgeColor.withValues(alpha: 0.18)
                      : CyberShieldColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: visual == _HubVisualState.connecting
                        ? badgeColor.withValues(alpha: 0.2)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  badge,
                  style: CyberShieldTheme.labelCode(color: badgeColor),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: CyberShieldTheme.metricStat(
                    color: muted
                        ? CyberShieldColors.onSurfaceVariant
                        : CyberShieldColors.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    unit,
                    style: CyberShieldTheme.labelCode(color: accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(samples: samples, visual: visual, color: accent),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Text(footerLabel, style: CyberShieldTheme.labelCode()),
              const Spacer(),
              Text(
                footerValue,
                style: CyberShieldTheme.labelCode(
                  color: muted
                      ? CyberShieldColors.onSurfaceVariant
                      : (visual == _HubVisualState.connecting
                          ? accent
                          : CyberShieldColors.onSurface),
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServerDetailCard extends StatefulWidget {
  const _ServerDetailCard({required this.connect, required this.visual});

  final VpnConnectState connect;
  final _HubVisualState visual;

  @override
  State<_ServerDetailCard> createState() => _ServerDetailCardState();
}

class _ServerDetailCardState extends State<_ServerDetailCard> {
  PublicNetworkInfo? _localNetwork;
  bool _loadingLocalNetwork = false;

  @override
  void initState() {
    super.initState();
    if (widget.visual == _HubVisualState.disconnected) {
      unawaited(_refreshLocalNetwork());
    }
  }

  @override
  void didUpdateWidget(covariant _ServerDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visual == _HubVisualState.disconnected && oldWidget.visual != _HubVisualState.disconnected) {
      unawaited(_refreshLocalNetwork());
    }
  }

  Future<void> _refreshLocalNetwork() async {
    if (_loadingLocalNetwork) return;
    setState(() => _loadingLocalNetwork = true);
    try {
      final info = await getIt<DeviceRepository>().currentPublicNetwork();
      if (!mounted) return;
      setState(() {
        _localNetwork = info;
        _loadingLocalNetwork = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLocalNetwork = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connect = widget.connect;
    final visual = widget.visual;
    return BlocBuilder<ServerInfoCubit, ServerInfoState>(
      builder: (context, state) {
        final fallback = switch (state) {
          ServerInfoLoaded(:final servers) when servers.isNotEmpty => servers.first,
          _ => null,
        };
        final vpnServer = connect.peer?.server ?? fallback;
        final vpnCountryCode = (vpnServer?.countryCode ?? 'DE').toUpperCase();
        // TEMP: demo override — show Spain instead of detected local country (e.g. RU).
        // Remove before shipping a real user-facing build.
        final detectedLocalCountry = _localNetwork?.countryCode?.toUpperCase();
        final localCountryCode = detectedLocalCountry == null ? null : 'ES';

        final isLocal = visual == _HubVisualState.disconnected;
        final flagCode = isLocal ? localCountryCode : vpnCountryCode;
        final locationName = isLocal
            ? (localCountryCode == null
                  ? (_loadingLocalNetwork ? 'Detecting…' : 'Local network')
                  : _countryTitle(localCountryCode))
            : _countryTitle(vpnCountryCode);

        final tunnelOrServerIp = connect.peer?.transport.serverIps.isNotEmpty == true
            ? connect.peer!.transport.serverIps.first
            : (connect.peer?.interfaceAddresses.isNotEmpty == true
                  ? connect.peer!.interfaceAddresses.first.split('/').first
                  : null);
        final localIp = _localNetwork?.ip;
        final ip = switch (visual) {
          _HubVisualState.disconnected =>
            _loadingLocalNetwork && (localIp == null || localIp.isEmpty)
                ? '…'
                : (localIp?.isNotEmpty == true ? localIp! : '—'),
          _ => tunnelOrServerIp ?? '—',
        };

        final (title, statusLabel, statusColor) = switch (visual) {
          _HubVisualState.connected => ('Current Connection', 'Connected', CyberShieldColors.tertiary),
          _HubVisualState.connecting => ('Current Connection', 'Handshaking...', CyberShieldColors.secondaryContainer),
          _HubVisualState.disconnected => ('Current Connection', 'Direct', CyberShieldColors.onSurfaceVariant),
        };

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: CyberShieldColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: visual == _HubVisualState.connecting
                  ? CyberShieldColors.outlineVariant.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(title.toUpperCase(), style: CyberShieldTheme.labelBadge()),
                  const Spacer(),
                  Row(
                    children: [
                      _StatusDot(color: statusColor, pulse: visual != _HubVisualState.disconnected),
                      const SizedBox(width: 6),
                      Text(statusLabel, style: CyberShieldTheme.labelCode(color: statusColor)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CyberShieldColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: flagCode == null
                        ? Icon(Icons.public, size: 20, color: CyberShieldColors.onSurfaceVariant)
                        : Text(countryFlagEmoji(flagCode), style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                locationName,
                                style: CyberShieldTheme.headlineSm(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (flagCode != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CyberShieldColors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  flagCode,
                                  style: CyberShieldTheme.labelBadge(
                                    color: visual == _HubVisualState.connecting
                                        ? CyberShieldColors.secondaryContainer
                                        : CyberShieldColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(isLocal ? 'Your IP: $ip' : 'IP: $ip', style: CyberShieldTheme.labelCode()),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: CyberShieldColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.speed,
                          size: 16,
                          color: visual == _HubVisualState.disconnected
                              ? CyberShieldColors.onSurfaceVariant
                              : CyberShieldColors.secondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '—',
                          style: CyberShieldTheme.labelCode(
                            color: visual == _HubVisualState.disconnected
                                ? CyberShieldColors.onSurfaceVariant
                                : CyberShieldColors.onSurface,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TunnelNegotiationCard extends StatelessWidget {
  const _TunnelNegotiationCard({required this.phase});

  final VpnConnectPhase phase;

  @override
  Widget build(BuildContext context) {
    final pct = _handshakePercent(phase);
    final step = pct <= 33 ? 1 : (pct <= 68 ? 2 : 3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CyberShieldColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Tunnel Negotiation', style: CyberShieldTheme.labelCode()),
              const Spacer(),
              Text(
                'Step $step of 3',
                style: CyberShieldTheme.labelCode(
                  color: CyberShieldColors.secondaryContainer,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: CyberShieldColors.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(CyberShieldColors.secondaryContainer),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StepChip(done: step > 1, active: step == 1, label: 'DNS OK'),
              ),
              Expanded(
                child: _StepChip(done: step > 2, active: step == 2, label: 'Keys $pct%'),
              ),
              Expanded(
                child: _StepChip(done: step > 3, active: step == 3, label: 'Route'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.done, required this.active, required this.label});

  final bool done;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? CyberShieldColors.tertiary
        : active
        ? CyberShieldColors.secondaryContainer
        : CyberShieldColors.outline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          done
              ? Icons.check_circle
              : active
              ? Icons.sync
              : Icons.radio_button_unchecked,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: CyberShieldTheme.labelCode(color: color).copyWith(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

int _handshakePercent(VpnConnectPhase phase) {
  return switch (phase) {
    VpnConnectPhase.checkingSession => 18,
    VpnConnectPhase.ensuringKeys => 34,
    VpnConnectPhase.provisioningPeer => 52,
    VpnConnectPhase.preparingVpn => 68,
    VpnConnectPhase.startingTransport => 82,
    VpnConnectPhase.startingTunnel => 92,
    VpnConnectPhase.disconnecting => 40,
    _ => 10,
  };
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.pulse) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulse)
                Opacity(
                  opacity: (1 - _controller.value) * 0.75,
                  child: Transform.scale(
                    scale: 1 + _controller.value,
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
                    ),
                  ),
                ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.55), blurRadius: 6)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.samples, required this.visual, required this.color});

  final List<double> samples;
  final _HubVisualState visual;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (visual != _HubVisualState.connected || samples.length < 2) {
      final paint = Paint()
        ..color = CyberShieldColors.outlineVariant
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final y = size.height * 0.9;
      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final peak = samples.fold<double>(0, math.max);
    final maxV = math.max(peak, 0.5);
    final last = samples.length - 1;
    final points = <Offset>[
      for (var i = 0; i < samples.length; i++)
        Offset(last == 0 ? 0 : size.width * (i / last), size.height * (1 - (samples[i].clamp(0, maxV) / maxV) * 0.92)),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fill);

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final total = (b - a).distance;
    final direction = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + direction * drawn;
      final end = a + direction * math.min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.visual != visual || oldDelegate.color != color) {
      return true;
    }
    if (oldDelegate.samples.length != samples.length) {
      return true;
    }
    for (var i = 0; i < samples.length; i++) {
      if (oldDelegate.samples[i] != samples[i]) {
        return true;
      }
    }
    return false;
  }
}

class _SoftUpdateBanner extends StatelessWidget {
  const _SoftUpdateBanner({required this.message, required this.storeUrl, required this.onDismiss});

  final String message;
  final String storeUrl;
  final VoidCallback onDismiss;

  Future<void> _openStore(BuildContext context) async {
    final uri = Uri.tryParse(AppStoreLinks.normalize(storeUrl));
    if (uri == null) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CyberShieldColors.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(child: Text(message, style: CyberShieldTheme.bodySm())),
            TextButton(onPressed: storeUrl.isEmpty ? null : () => _openStore(context), child: const Text('Update')),
            IconButton(tooltip: 'Dismiss', onPressed: onDismiss, icon: const Icon(Icons.close, size: 18)),
          ],
        ),
      ),
    );
  }
}

class _ConnectLogPanel extends StatelessWidget {
  const _ConnectLogPanel({required this.log});

  final List<VpnConnectLogLine> log;

  static String formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String get _plainText => log.map((line) => '${formatTime(line.at)}  ${line.message}').join('\n');

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _plainText));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect log copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Connect log', style: CyberShieldTheme.headlineSm())),
            TextButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: CyberShieldColors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
              color: CyberShieldColors.surfaceContainerLowest,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _plainText,
                style: CyberShieldTheme.labelCode(
                  color: CyberShieldColors.onSurface,
                ).copyWith(fontSize: 11, height: 1.45),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
