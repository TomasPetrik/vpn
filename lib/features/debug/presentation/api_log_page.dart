import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_traffic_log.dart';
import '../../device/domain/device_repository.dart';
import '../../health/data/health_api.dart';
import '../../servers/domain/servers_repository.dart';

class ApiLogPage extends StatelessWidget {
  const ApiLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = getIt<ApiTrafficLog>();
    return AnimatedBuilder(
      animation: log,
      builder: (context, _) {
        final entries = log.entries;
        return Scaffold(
          appBar: AppBar(
            title: Text('API log (${entries.length})'),
            actions: [
              IconButton(
                tooltip: 'Call all endpoints',
                onPressed: () => _exerciseAll(context),
                icon: const Icon(Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'Clear',
                onPressed: log.clear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(child: Text('No API calls yet in this session.'))
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final code = entry.statusCode;
                    final color = entry.errorMessage != null && code == null
                        ? Colors.red
                        : (entry.isSuccess ? Colors.green.shade700 : Colors.orange.shade800);
                    return ListTile(
                      title: Text('${entry.method} ${entry.pathWithQuery}'),
                      subtitle: Text(
                        [
                          if (code != null) '$code',
                          if (entry.duration != null)
                            '${entry.duration!.inMilliseconds} ms',
                          if (entry.errorMessage != null) entry.errorMessage!,
                          _formatTime(entry.startedAt),
                        ].join(' · '),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Text(
                          code?.toString() ?? '!',
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ApiLogDetailPage(entry: entry),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  Future<void> _exerciseAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Calling all REST endpoints…')),
    );
    final deviceRepo = getIt<DeviceRepository>();
    final serversRepo = getIt<ServersRepository>();
    final healthApi = getIt<HealthApi>();

    try {
      await healthApi.healthz();
    } catch (_) {}
    try {
      await deviceRepo.me();
    } catch (_) {}
    try {
      await serversRepo.list();
    } catch (_) {}
    try {
      await deviceRepo.getPeer();
    } catch (_) {}
    // Random 32-byte key so PUT is exerciseable before Phase 3 keygen.
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final demoPublicKey = base64Encode(bytes);
    try {
      await deviceRepo.upsertPeer(publicKey: demoPublicKey);
    } catch (_) {}

    messenger.showSnackBar(
      const SnackBar(content: Text('Finished. See log for results.')),
    );
  }
}

class ApiLogDetailPage extends StatelessWidget {
  const ApiLogDetailPage({super.key, required this.entry});

  final ApiCallEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = StringBuffer()
      ..writeln('${entry.method} ${entry.uri}')
      ..writeln('Started: ${entry.startedAt.toIso8601String()}')
      ..writeln('Status: ${entry.statusCode ?? '-'}')
      ..writeln('Duration: ${entry.duration?.inMilliseconds ?? '-'} ms')
      ..writeln()
      ..writeln('--- Request headers ---')
      ..writeln(entry.requestHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\n'))
      ..writeln()
      ..writeln('--- Request body ---')
      ..writeln(entry.requestBody ?? '(empty)')
      ..writeln()
      ..writeln('--- Response body ---')
      ..writeln(entry.responseBody ?? '(empty)')
      ..writeln()
      ..writeln('--- Error ---')
      ..writeln(entry.errorMessage ?? '(none)');

    return Scaffold(
      appBar: AppBar(
        title: Text('${entry.method} ${entry.statusCode ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              }
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(text.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ),
    );
  }
}
