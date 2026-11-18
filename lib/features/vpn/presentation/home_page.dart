import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../app_update/presentation/app_update_cubit.dart';
import '../../servers/presentation/server_info_cubit.dart';
import 'vpn_connect_cubit.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDevMode = getIt<AppConfig>().isDevMode;

    return Scaffold(
      appBar: AppBar(title: const Text('PetrikVPN')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          BlocBuilder<AppUpdateCubit, AppUpdateState>(
            builder: (context, state) {
              if (state is! AppUpdateAvailable) {
                return const SizedBox.shrink();
              }
              return Card(
                child: ListTile(
                  title: const Text('Update available'),
                  subtitle: Text(state.policy.message.isEmpty
                      ? 'A newer PetrikVPN build is available.'
                      : state.policy.message),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          BlocBuilder<ServerInfoCubit, ServerInfoState>(
            builder: (context, state) {
              return switch (state) {
                ServerInfoLoading() => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ServerInfoError(:final message) => Text('Server info: $message'),
                ServerInfoLoaded(:final servers) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (servers.isEmpty) const Text('No servers'),
                      ...servers.map(
                        (s) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.name),
                          subtitle: Text(
                            [
                              if (s.countryCode != null) s.countryCode!,
                              if (s.city != null && s.city!.isNotEmpty) s.city!,
                              s.status,
                            ].join(' · '),
                          ),
                        ),
                      ),
                    ],
                  ),
              };
            },
          ),
          const SizedBox(height: 32),
          BlocBuilder<VpnConnectCubit, VpnConnectState>(
            builder: (context, connect) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (connect.isBusy) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          connect.stepLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  if (connect.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      connect.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (connect.peer != null &&
                      (connect.phase == VpnConnectPhase.skeletonConnected ||
                          connect.phase == VpnConnectPhase.error)) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tunnel IP: ${connect.peer!.interfaceAddresses.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (connect.phase == VpnConnectPhase.skeletonConnected &&
                      (connect.hasTrafficStats ||
                          connect.lastHandshakeAt != null)) ...[
                    const SizedBox(height: 12),
                    _TunnelStatsPanel(
                      rxBytes: connect.rxBytes,
                      txBytes: connect.txBytes,
                      lastHandshakeAt: connect.lastHandshakeAt,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: connect.canConnect
                        ? () => context.read<VpnConnectCubit>().connect()
                        : null,
                    child: Text(
                      connect.phase == VpnConnectPhase.skeletonConnected ||
                              connect.phase == VpnConnectPhase.error
                          ? 'Retry'
                          : 'Connect',
                    ),
                  ),
                  if (connect.canDisconnect) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () =>
                          context.read<VpnConnectCubit>().disconnect(),
                      child: const Text('Disconnect'),
                    ),
                  ],
                  if (connect.canReset) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.read<VpnConnectCubit>().reset(),
                      child: const Text('Reset'),
                    ),
                  ],
                  if (isDevMode && connect.log.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _ConnectLogPanel(log: connect.log),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TunnelStatsPanel extends StatelessWidget {
  const _TunnelStatsPanel({
    required this.rxBytes,
    required this.txBytes,
    required this.lastHandshakeAt,
  });

  final int? rxBytes;
  final int? txBytes;
  final DateTime? lastHandshakeAt;

  static String formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  static String formatHandshake(DateTime? at, DateTime now) {
    if (at == null) {
      return 'Waiting…';
    }
    final seconds = now.difference(at.toLocal()).inSeconds;
    if (seconds < 0) {
      return 'just now';
    }
    if (seconds < 60) {
      return '${seconds}s ago';
    }
    if (seconds < 3600) {
      return '${seconds ~/ 60}m ago';
    }
    if (seconds < 86400) {
      return '${seconds ~/ 3600}h ago';
    }
    return '${seconds ~/ 86400}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rxBytes != null || txBytes != null)
          Text(
            '↓ ${formatBytes(rxBytes ?? 0)}   ↑ ${formatBytes(txBytes ?? 0)}',
            style: style,
          ),
        if (lastHandshakeAt != null || rxBytes != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last handshake: ${formatHandshake(lastHandshakeAt, now)}',
            style: style,
          ),
        ],
      ],
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

  String get _plainText => log
      .map((line) => '${formatTime(line.at)}  ${line.message}')
      .join('\n');

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _plainText));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connect log copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Connect log',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _plainText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
