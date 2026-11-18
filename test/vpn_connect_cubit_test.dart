import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ru_eu_vpn/features/device/domain/device_repository.dart';
import 'package:ru_eu_vpn/features/device/domain/device_session.dart';
import 'package:ru_eu_vpn/features/device/domain/vpn_peer_config.dart';
import 'package:ru_eu_vpn/features/servers/domain/vpn_server.dart';
import 'package:ru_eu_vpn/features/vpn/domain/vpn_engine.dart';
import 'package:ru_eu_vpn/features/vpn/domain/vpn_usage_stats.dart';
import 'package:ru_eu_vpn/features/vpn/presentation/vpn_connect_cubit.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockVpnEngine extends Mock implements VpnEngine {}

class _MemoryUsageStore implements VpnUsageStatsStore {
  VpnUsageTotals committed = const VpnUsageTotals.zero();
  VpnUsageTotals? inflight;

  @override
  Future<VpnUsageTotals> readCommitted() async => committed;

  @override
  Future<void> commitSession({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  }) async {
    committed = committed.addSession(
      rxBytes: rxBytes,
      txBytes: txBytes,
      activeSeconds: activeSeconds,
    );
    inflight = null;
  }

  @override
  Future<void> writeInflight({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  }) async {
    inflight = VpnUsageTotals(
      rxBytes: rxBytes,
      txBytes: txBytes,
      activeSeconds: activeSeconds,
    );
  }

  @override
  Future<void> clearInflight() async {
    inflight = null;
  }

  @override
  Future<VpnUsageTotals> recoverInflightIfNeeded() async {
    if (inflight == null) {
      return committed;
    }
    await commitSession(
      rxBytes: inflight!.rxBytes,
      txBytes: inflight!.txBytes,
      activeSeconds: inflight!.activeSeconds,
    );
    return committed;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  late _MockDeviceRepository repo;
  late _MockVpnEngine engine;
  late _MemoryUsageStore usage;

  final peer = VpnPeerConfig(
    peerId: 'peer-1',
    server: const VpnServer(id: 's1', name: 'Germany', countryCode: 'DE'),
    interfaceAddresses: const ['10.201.0.2/32'],
    dns: const ['1.1.1.1'],
    mtu: 1280,
    peerPublicKey: 'serverkey',
    allowedIps: const ['0.0.0.0/0'],
    excludedIps: const ['72.61.158.103/32'],
    persistentKeepalive: 25,
    transport: const VpnTransportConfig(
      type: 'wstunnel',
      url: 'wss://vpn.radarcut.com',
      pathPrefix: 'prefix',
      remote: '127.0.0.1:51821',
      serverIps: ['72.61.158.103'],
    ),
  );

  VpnConnectCubit buildCubit() => VpnConnectCubit(
        deviceRepository: repo,
        vpnEngine: engine,
        usageStatsStore: usage,
      );

  setUp(() {
    repo = _MockDeviceRepository();
    engine = _MockVpnEngine();
    usage = _MemoryUsageStore();
    when(() => repo.me()).thenAnswer(
      (_) async => const DeviceSession(userId: 'u1', deviceId: 'd1'),
    );
    when(() => repo.ensureSession()).thenAnswer(
      (_) async => const DeviceSession(userId: 'u1', deviceId: 'd1'),
    );
    when(() => repo.upsertPeer(publicKey: any(named: 'publicKey')))
        .thenAnswer((_) async => peer);
    when(() => engine.getPublicKey())
        .thenAnswer((_) async => 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
    when(() => engine.prepare()).thenAnswer(
      (_) async => const VpnPrepareResult(
        granted: true,
        status: 'ready',
        message: 'ok',
      ),
    );
    when(() => engine.startTunnel(any())).thenAnswer(
      (_) async => const VpnTunnelResult(
        ok: true,
        status: 'connecting',
        message: 'startVPNTunnel requested (WireGuardKit)',
      ),
    );
    when(() => engine.getStatus()).thenAnswer(
      (_) async => const VpnStatusSnapshot(
        status: 'connected',
        extensionStatus: 'wireguard_started',
        extensionLog: ['WireGuard started (wstunnel on 127.0.0.1:51820)'],
      ),
    );
    when(() => engine.statusStream()).thenAnswer((_) => const Stream.empty());
  });

  blocTest<VpnConnectCubit, VpnConnectState>(
    'connect starts wstunnel+WireGuardKit and reaches skeletonConnected',
    build: buildCubit,
    act: (cubit) => cubit.connect(),
    wait: const Duration(milliseconds: 500),
    verify: (cubit) {
      verify(() => engine.getPublicKey()).called(1);
      verify(() => engine.prepare()).called(1);
      final captured = verify(() => engine.startTunnel(captureAny())).captured;
      final cfg = captured.single as Map<String, Object?>;
      expect(cfg['path_prefix'], 'prefix');
      expect(cfg['remote'], '127.0.0.1:51821');
      expect(cfg['server_ips'], ['72.61.158.103']);
      expect(cubit.state.phase, VpnConnectPhase.skeletonConnected);
      expect(cubit.state.peer?.peerId, 'peer-1');
      expect(cubit.state.stepLabel, 'Connected');
      expect(cubit.state.sessionStartedAt, isNotNull);
    },
  );

  blocTest<VpnConnectCubit, VpnConnectState>(
    'connect failure emits error with log',
    build: () {
      when(() => repo.ensureSession()).thenThrow(Exception('offline'));
      return buildCubit();
    },
    act: (cubit) => cubit.connect(),
    verify: (cubit) {
      expect(cubit.state.phase, VpnConnectPhase.error);
      expect(cubit.state.log, isNotEmpty);
      expect(cubit.state.errorMessage, contains('offline'));
    },
  );

  blocTest<VpnConnectCubit, VpnConnectState>(
    'connect stores WireGuard rx/tx and handshake from status',
    build: () {
      when(() => engine.getStatus()).thenAnswer(
        (_) async => VpnStatusSnapshot(
          status: 'connected',
          extensionStatus: 'wireguard_started',
          extensionLog: const [],
          rxBytes: 1500,
          txBytes: 800,
          lastHandshakeAt: DateTime.utc(2026, 11, 18, 3, 0, 0),
        ),
      );
      return buildCubit();
    },
    act: (cubit) => cubit.connect(),
    wait: const Duration(milliseconds: 500),
    verify: (cubit) {
      expect(cubit.state.phase, VpnConnectPhase.skeletonConnected);
      expect(cubit.state.rxBytes, 1500);
      expect(cubit.state.txBytes, 800);
      expect(
        cubit.state.lastHandshakeAt,
        DateTime.utc(2026, 11, 18, 3, 0, 0),
      );
    },
  );

  blocTest<VpnConnectCubit, VpnConnectState>(
    'disconnect commits session into overall totals',
    build: () {
      when(() => engine.getStatus()).thenAnswer(
        (_) async => const VpnStatusSnapshot(
          status: 'connected',
          extensionStatus: 'wireguard_started',
          extensionLog: [],
          rxBytes: 2000,
          txBytes: 1000,
        ),
      );
      when(() => engine.stopTunnel()).thenAnswer(
        (_) async => const VpnTunnelResult(
          ok: true,
          status: 'disconnected',
          message: 'stopped',
        ),
      );
      return buildCubit();
    },
    act: (cubit) async {
      await cubit.connect();
      await cubit.disconnect();
    },
    wait: const Duration(milliseconds: 600),
    verify: (cubit) {
      expect(cubit.state.phase, VpnConnectPhase.idle);
      expect(usage.committed.rxBytes, 2000);
      expect(usage.committed.txBytes, 1000);
      expect(cubit.state.committedTotals.rxBytes, 2000);
    },
  );

  test('VpnStatusSnapshot parses UAPI counters', () {
    final snap = VpnStatusSnapshot.fromMap({
      'status': 'connected',
      'extension_status': 'wireguard_started',
      'extension_log': <String>[],
      'rx_bytes': 2048,
      'tx_bytes': 1024,
      'last_handshake_sec': 1700000000,
    });
    expect(snap.rxBytes, 2048);
    expect(snap.txBytes, 1024);
    expect(
      snap.lastHandshakeAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
  });
}
