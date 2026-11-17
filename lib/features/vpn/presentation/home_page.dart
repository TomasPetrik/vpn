import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_update/presentation/app_update_cubit.dart';
import '../../servers/presentation/server_info_cubit.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
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
          FilledButton(
            onPressed: null,
            child: const Text('Connect (Phase 3)'),
          ),
          const SizedBox(height: 8),
          Text(
            'VPN connection will be enabled after the native engine spikes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
