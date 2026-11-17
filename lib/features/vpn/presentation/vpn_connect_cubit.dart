import 'package:flutter_bloc/flutter_bloc.dart';

import '../../device/domain/device_repository.dart';
import '../../device/domain/vpn_peer_config.dart';
import '../domain/vpn_engine.dart';

enum VpnConnectPhase {
  idle,
  checkingSession,
  ensuringKeys,
  provisioningPeer,
  preparingVpn,
  startingTransport,
  startingTunnel,
  awaitingNative,
  disconnecting,
  error,
}

class VpnConnectLogLine {
  const VpnConnectLogLine({
    required this.at,
    required this.message,
  });

  final DateTime at;
  final String message;
}

class VpnConnectState {
  const VpnConnectState({
    required this.phase,
    required this.stepLabel,
    required this.log,
    this.peer,
    this.errorMessage,
  });

  final VpnConnectPhase phase;
  final String stepLabel;
  final List<VpnConnectLogLine> log;
  final VpnPeerConfig? peer;
  final String? errorMessage;

  bool get isBusy =>
      phase == VpnConnectPhase.checkingSession ||
      phase == VpnConnectPhase.ensuringKeys ||
      phase == VpnConnectPhase.provisioningPeer ||
      phase == VpnConnectPhase.preparingVpn ||
      phase == VpnConnectPhase.startingTransport ||
      phase == VpnConnectPhase.startingTunnel ||
      phase == VpnConnectPhase.disconnecting;

  bool get canConnect =>
      phase == VpnConnectPhase.idle ||
      phase == VpnConnectPhase.awaitingNative ||
      phase == VpnConnectPhase.error;

  bool get canReset =>
      phase == VpnConnectPhase.awaitingNative || phase == VpnConnectPhase.error;

  VpnConnectState copyWith({
    VpnConnectPhase? phase,
    String? stepLabel,
    List<VpnConnectLogLine>? log,
    VpnPeerConfig? peer,
    String? errorMessage,
    bool clearError = false,
    bool clearPeer = false,
  }) {
    return VpnConnectState(
      phase: phase ?? this.phase,
      stepLabel: stepLabel ?? this.stepLabel,
      log: log ?? this.log,
      peer: clearPeer ? null : (peer ?? this.peer),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static VpnConnectState initial() => const VpnConnectState(
        phase: VpnConnectPhase.idle,
        stepLabel: 'Ready to connect',
        log: [],
      );
}

class VpnConnectCubit extends Cubit<VpnConnectState> {
  VpnConnectCubit({
    required DeviceRepository deviceRepository,
    required VpnEngine vpnEngine,
  })  : _deviceRepository = deviceRepository,
        _vpnEngine = vpnEngine,
        super(VpnConnectState.initial());

  final DeviceRepository _deviceRepository;
  final VpnEngine _vpnEngine;

  Future<void> connect() async {
    if (state.isBusy) {
      return;
    }

    final lines = <VpnConnectLogLine>[];
    void log(String message) {
      lines.add(VpnConnectLogLine(at: DateTime.now(), message: message));
    }

    void emitPhase(VpnConnectPhase phase, String label) {
      emit(
        state.copyWith(
          phase: phase,
          stepLabel: label,
          log: List.unmodifiable(lines),
          clearError: true,
        ),
      );
    }

    try {
      log('Connect tapped');
      emitPhase(VpnConnectPhase.checkingSession, 'Checking session…');
      log('GET /me — verifying device session');
      final session = await _deviceRepository.me();
      log('Session OK — user ${session.userId}, device ${session.deviceId}');

      emitPhase(VpnConnectPhase.ensuringKeys, 'Preparing WireGuard keys…');
      log('vpn_engine.getPublicKey — native Keychain (private key stays on device)');
      final publicKey = await _vpnEngine.getPublicKey();
      log('Public key ready (${publicKey.substring(0, 8)}…)');

      emitPhase(VpnConnectPhase.provisioningPeer, 'Provisioning peer…');
      log('PUT /devices/me/peer — registering public key');
      final peer = await _deviceRepository.upsertPeer(publicKey: publicKey);
      log(
        'Peer OK — ${peer.server.name} · ${peer.interfaceAddresses.join(', ')}',
      );

      emitPhase(VpnConnectPhase.preparingVpn, 'VPN permission…');
      log('vpn_engine.prepare — requesting OS VPN configuration');
      final prepared = await _vpnEngine.prepare();
      log('prepare → ${prepared.status}: ${prepared.message}');
      if (prepared.status == 'needs_extension') {
        log('PacketTunnel extension not installed yet (step 3)');
      }

      emitPhase(VpnConnectPhase.startingTransport, 'Starting transport…');
      log('wstunnel — skipped (step 5)');

      emitPhase(VpnConnectPhase.startingTunnel, 'Starting tunnel…');
      log('PacketTunnel / WireGuard — skipped (steps 3–4)');

      log('Peer provisioned — waiting for native PacketTunnel');
      emit(
        state.copyWith(
          phase: VpnConnectPhase.awaitingNative,
          stepLabel: prepared.granted
              ? 'Peer OK — VPN profile ready, waiting for tunnel'
              : 'Peer OK — waiting for PacketTunnel',
          log: List.unmodifiable(lines),
          peer: peer,
          clearError: true,
        ),
      );
    } catch (e) {
      log('Error: $e');
      emit(
        state.copyWith(
          phase: VpnConnectPhase.error,
          stepLabel: 'Connect failed',
          log: List.unmodifiable(lines),
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> reset() async {
    if (state.isBusy) {
      return;
    }
    emit(VpnConnectState.initial());
  }
}
