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
    when(() => engine.getPublicKey()).thenAnswer((_) async => 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
    when(() => engine.prepare()).thenAnswer(
      (_) async => const VpnPrepareResult(
        granted: false,
        status: 'needs_extension',
        message: 'PacketTunnel missing',
      ),
    );
  });

  blocTest<VpnConnectCubit, VpnConnectState>(
    'connect uses native keys and stops at awaitingNative',
    build: () => VpnConnectCubit(deviceRepository: repo, vpnEngine: engine),
    act: (cubit) => cubit.connect(),
    expect: () => [
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.checkingSession,
      ),
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.ensuringKeys,
      ),
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.provisioningPeer,
      ),
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.preparingVpn,
      ),
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.startingTransport,
      ),
      isA<VpnConnectState>().having(
        (s) => s.phase,
        'phase',
        VpnConnectPhase.startingTunnel,
      ),
      isA<VpnConnectState>()
          .having((s) => s.phase, 'phase', VpnConnectPhase.awaitingNative)
          .having((s) => s.peer?.peerId, 'peerId', 'peer-1'),
    ],
    verify: (_) {
      verify(() => engine.getPublicKey()).called(1);
      verify(() => engine.prepare()).called(1);
      verify(() => repo.upsertPeer(publicKey: any(named: 'publicKey')))
          .called(1);
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
