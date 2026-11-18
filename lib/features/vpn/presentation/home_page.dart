import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../app_update/presentation/app_update_cubit.dart';
import '../../servers/presentation/server_info_cubit.dart';
import 'vpn_connect_cubit.dart';
import 'vpn_stats_format.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDevMode = getIt<AppConfig>().isDevMode;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Statistics',
          onPressed: () => context.push('/stats'),
          icon: const Icon(Icons.bar_chart_rounded),
        ),
        title: const Text('PetrikVPN'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlocBuilder<AppUpdateCubit, AppUpdateState>(
                builder: (context, state) {
                  if (state is! AppUpdateAvailable) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      state.policy.message.isEmpty
                          ? 'Update available'
                          : state.policy.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
              Expanded(
                child: BlocBuilder<VpnConnectCubit, VpnConnectState>(
                  builder: (context, connect) {
                    return Column(
                      children: [
                        const Spacer(),
                        _ServerLine(),
                        const SizedBox(height: 28),
                        _StatusBlock(connect: connect),
                        if (connect.hasSessionStats) ...[
                          const SizedBox(height: 28),
                          _SessionStats(connect: connect),
                        ],
                        if (connect.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            connect.errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const Spacer(),
                        if (connect.isBusy)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (connect.canDisconnect)
                          FilledButton(
                            onPressed: () =>
                                context.read<VpnConnectCubit>().disconnect(),
                            child: const Text('Disconnect'),
                          )
                        else
                          FilledButton(
                            onPressed: connect.canConnect
                                ? () =>
                                    context.read<VpnConnectCubit>().connect()
                                : null,
                            child: const Text('Connect'),
                          ),
                        if (isDevMode && connect.log.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => _showConnectLog(context, connect),
                            child: const Text('Connect log'),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConnectLog(BuildContext context, VpnConnectState connect) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
          ),
          child: _ConnectLogPanel(log: connect.log),
        );
      },
    );
  }
}

class _ServerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<VpnConnectCubit, VpnConnectState>(
      buildWhen: (a, b) => a.peer?.server.id != b.peer?.server.id,
      builder: (context, connect) {
        final peerServer = connect.peer?.server;
        if (peerServer != null) {
          return Text(
            [
              peerServer.name,
              if (peerServer.countryCode != null) peerServer.countryCode!,
            ].join(' · '),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          );
        }
        return BlocBuilder<ServerInfoCubit, ServerInfoState>(
          builder: (context, state) {
            final label = switch (state) {
              ServerInfoLoaded(:final servers) when servers.isNotEmpty => [
                  servers.first.name,
                  if (servers.first.countryCode != null)
                    servers.first.countryCode!,
                ].join(' · '),
              ServerInfoLoading() => 'Loading server…',
              ServerInfoError() => 'Server unavailable',
              _ => 'PetrikVPN',
            };
            return Text(
              label,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            );
          },
        );
      },
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.connect});

  final VpnConnectState connect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = connect.isConnected;
    return Column(
      children: [
        Text(
          connect.stepLabel,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: connected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        if (connected) ...[
          const SizedBox(height: 8),
          Text(
            VpnStatsFormat.duration(connect.sessionSeconds),
            style: theme.textTheme.displaySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionStats extends StatelessWidget {
  const _SessionStats({required this.connect});

  final VpnConnectState connect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    return Column(
      children: [
        Text(
          '↓ ${VpnStatsFormat.bytes(connect.rxBytes ?? 0)}'
          '    ↑ ${VpnStatsFormat.bytes(connect.txBytes ?? 0)}',
          style: style,
          textAlign: TextAlign.center,
        ),
        if (connect.lastHandshakeAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'Handshake ${VpnStatsFormat.handshakeAgo(connect.lastHandshakeAt, DateTime.now())}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
      mainAxisSize: MainAxisSize.min,
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
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
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
        ),
      ],
    );
  }
}
