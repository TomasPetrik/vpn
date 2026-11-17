import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ru_eu_vpn/features/device/domain/device_repository.dart';
import 'package:ru_eu_vpn/features/device/domain/device_session.dart';
import 'package:ru_eu_vpn/features/device/domain/vpn_peer_config.dart';
import 'package:ru_eu_vpn/features/servers/domain/vpn_server.dart';
import 'package:ru_eu_vpn/features/vpn/domain/vpn_engine.dart';
import 'package:ru_eu_vpn/features/vpn/presentation/vpn_connect_cubit.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockVpnEngine extends Mock implements VpnEngine {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  late _MockDeviceRepository repo;
  late _MockVpnEngine engine;

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

  setUp(() {
    repo = _MockDeviceRepository();
    engine = _MockVpnEngine();
    when(() => repo.me()).thenAnswer(
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
    build: () => VpnConnectCubit(deviceRepository: repo, vpnEngine: engine),
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
      expect(cubit.state.stepLabel, contains('Connected'));
    },
  );

  blocTest<VpnConnectCubit, VpnConnectState>(
    'connect failure emits error with log',
    build: () {
      when(() => repo.me()).thenThrow(Exception('offline'));
      return VpnConnectCubit(deviceRepository: repo, vpnEngine: engine);
    },
    act: (cubit) => cubit.connect(),
    expect: () => [
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.checkingSession,
      ),
      isA<VpnConnectState>()
          .having((s) => s.phase, 'phase', VpnConnectPhase.error)
          .having((s) => s.log, 'log', isNotEmpty),
    ],
  );
}
