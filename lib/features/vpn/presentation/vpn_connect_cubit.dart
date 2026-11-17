import 'dart:async';

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
  skeletonConnected,
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
      phase == VpnConnectPhase.skeletonConnected ||
      phase == VpnConnectPhase.error;

  bool get canReset =>
      phase == VpnConnectPhase.skeletonConnected ||
      phase == VpnConnectPhase.error;

  bool get canDisconnect => phase == VpnConnectPhase.skeletonConnected;

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
        super(VpnConnectState.initial()) {
    _statusSub = _vpnEngine.statusStream().listen(_onStatus);
  }

  final DeviceRepository _deviceRepository;
  final VpnEngine _vpnEngine;
  StreamSubscription<VpnStatusSnapshot>? _statusSub;

  @override
  Future<void> close() async {
    await _statusSub?.cancel();
    return super.close();
  }

  void _onStatus(VpnStatusSnapshot snap) {
    if (state.phase != VpnConnectPhase.startingTunnel &&
        state.phase != VpnConnectPhase.skeletonConnected) {
      return;
    }
    final lines = List<VpnConnectLogLine>.from(state.log);
    void log(String message) {
      lines.add(VpnConnectLogLine(at: DateTime.now(), message: message));
    }

    log('VPN status → ${snap.status} (extension: ${snap.extensionStatus})');
    for (final line in snap.extensionLog.takeLast(3)) {
      log('ext: $line');
    }

    if (snap.status == 'connected' ||
        snap.extensionStatus == 'skeleton_connected') {
      emit(
        state.copyWith(
          phase: VpnConnectPhase.skeletonConnected,
          stepLabel: 'PacketTunnel skeleton connected (no WireGuard yet)',
          log: List.unmodifiable(lines),
          clearError: true,
        ),
      );
    } else if (snap.status == 'disconnected' &&
        state.phase == VpnConnectPhase.skeletonConnected) {
      emit(
        state.copyWith(
          phase: VpnConnectPhase.idle,
          stepLabel: 'Disconnected',
          log: List.unmodifiable(lines),
        ),
      );
    } else {
      emit(state.copyWith(log: List.unmodifiable(lines)));
    }
  }

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
      log('vpn_engine.getPublicKey — native Keychain');
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
      if (!prepared.granted) {
        throw StateError('VPN prepare failed: ${prepared.message}');
      }

      emitPhase(VpnConnectPhase.startingTransport, 'Starting transport…');
      log('wstunnel — skipped (step 5)');

      emitPhase(VpnConnectPhase.startingTunnel, 'Starting PacketTunnel…');
      log('vpn_engine.startTunnel — PacketTunnel skeleton');
      final started = await _vpnEngine.startTunnel();
      log('startTunnel → ${started.status}: ${started.message}');
      if (!started.ok) {
        throw StateError('startTunnel failed: ${started.message}');
      }

      // Poll briefly for extension status / connected.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final snap = await _vpnEngine.getStatus();
        log(
          'poll status=${snap.status} ext=${snap.extensionStatus}',
        );
        if (snap.status == 'connected' ||
            snap.extensionStatus == 'skeleton_connected') {
          for (final line in snap.extensionLog) {
            log('ext: $line');
          }
          emit(
            state.copyWith(
              phase: VpnConnectPhase.skeletonConnected,
              stepLabel: 'PacketTunnel skeleton connected (no WireGuard yet)',
              log: List.unmodifiable(lines),
              peer: peer,
              clearError: true,
            ),
          );
          return;
        }
        if (snap.status == 'disconnected' && i > 2) {
          break;
        }
      }

      emit(
        state.copyWith(
          phase: VpnConnectPhase.skeletonConnected,
          stepLabel: 'Tunnel start requested — check OS VPN / logs',
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

  Future<void> disconnect() async {
    if (state.isBusy) {
      return;
    }
    final lines = List<VpnConnectLogLine>.from(state.log);
    void log(String message) {
      lines.add(VpnConnectLogLine(at: DateTime.now(), message: message));
    }

    emit(
      state.copyWith(
        phase: VpnConnectPhase.disconnecting,
        stepLabel: 'Disconnecting…',
        log: List.unmodifiable(lines),
      ),
    );
    log('vpn_engine.stopTunnel');
    final stopped = await _vpnEngine.stopTunnel();
    log('stopTunnel → ${stopped.message}');
    emit(
      state.copyWith(
        phase: VpnConnectPhase.idle,
        stepLabel: 'Disconnected',
        log: List.unmodifiable(lines),
        clearPeer: true,
      ),
    );
  }

  Future<void> reset() async {
    if (state.isBusy) {
      return;
    }
    if (state.canDisconnect) {
      await disconnect();
    }
    emit(VpnConnectState.initial());
  }
}

extension _TakeLast<E> on List<E> {
  Iterable<E> takeLast(int n) {
    if (length <= n) {
      return this;
    }
    return sublist(length - n);
  }
}
