import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'vpn_connect_cubit.dart';
import 'vpn_stats_format.dart';

class VpnStatsPage extends StatefulWidget {
  const VpnStatsPage({super.key});

  @override
  State<VpnStatsPage> createState() => _VpnStatsPageState();
}

class _VpnStatsPageState extends State<VpnStatsPage> {
  @override
  void initState() {
    super.initState();
    context.read<VpnConnectCubit>().refreshCommittedTotals();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: BlocBuilder<VpnConnectCubit, VpnConnectState>(
        builder: (context, state) {
          final overall = state.overallTotals;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Text('Overall', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _StatTile(
                label: 'Downloaded',
                value: VpnStatsFormat.bytes(overall.rxBytes),
              ),
              _StatTile(
                label: 'Uploaded',
                value: VpnStatsFormat.bytes(overall.txBytes),
              ),
              _StatTile(
                label: 'Time connected',
                value: VpnStatsFormat.duration(overall.activeSeconds),
              ),
              if (state.isConnected) ...[
                const SizedBox(height: 28),
                Text('This session', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _StatTile(
                  label: 'Downloaded',
                  value: VpnStatsFormat.bytes(state.rxBytes ?? 0),
                ),
                _StatTile(
                  label: 'Uploaded',
                  value: VpnStatsFormat.bytes(state.txBytes ?? 0),
                ),
                _StatTile(
                  label: 'Duration',
                  value: VpnStatsFormat.duration(state.sessionSeconds),
                ),
                if (state.lastHandshakeAt != null)
                  _StatTile(
                    label: 'Last handshake',
                    value: VpnStatsFormat.handshakeAgo(
                      state.lastHandshakeAt,
                      DateTime.now(),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyLarge),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
