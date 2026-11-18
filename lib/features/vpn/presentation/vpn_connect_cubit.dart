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
    this.rxBytes,
    this.txBytes,
    this.lastHandshakeAt,
  });

  final VpnConnectPhase phase;
  final String stepLabel;
  final List<VpnConnectLogLine> log;
  final VpnPeerConfig? peer;
  final String? errorMessage;
  final int? rxBytes;
  final int? txBytes;
  final DateTime? lastHandshakeAt;

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

  bool get hasTrafficStats => rxBytes != null || txBytes != null;

  VpnConnectState copyWith({
    VpnConnectPhase? phase,
    String? stepLabel,
    List<VpnConnectLogLine>? log,
    VpnPeerConfig? peer,
    String? errorMessage,
    int? rxBytes,
    int? txBytes,
    DateTime? lastHandshakeAt,
    bool clearError = false,
    bool clearPeer = false,
    bool clearTraffic = false,
  }) {
    return VpnConnectState(
      phase: phase ?? this.phase,
      stepLabel: stepLabel ?? this.stepLabel,
      log: log ?? this.log,
      peer: clearPeer ? null : (peer ?? this.peer),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      rxBytes: clearTraffic ? null : (rxBytes ?? this.rxBytes),
      txBytes: clearTraffic ? null : (txBytes ?? this.txBytes),
      lastHandshakeAt:
          clearTraffic ? null : (lastHandshakeAt ?? this.lastHandshakeAt),
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
  Timer? _statsTimer;

  @override
  Future<void> close() async {
    _stopStatsPolling();
    await _statusSub?.cancel();
    return super.close();
  }

  String? _lastStatusKey;

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshTrafficStats());
    });
    unawaited(_refreshTrafficStats());
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _refreshTrafficStats() async {
    if (state.phase != VpnConnectPhase.skeletonConnected || isClosed) {
      return;
    }
    try {
      final snap = await _vpnEngine.getStatus();
      if (isClosed || state.phase != VpnConnectPhase.skeletonConnected) {
        return;
      }
      _applyTraffic(snap);
    } catch (_) {
      // Ignore transient channel errors while polling.
    }
  }

  void _applyTraffic(VpnStatusSnapshot snap) {
    final same = state.rxBytes == snap.rxBytes &&
        state.txBytes == snap.txBytes &&
        state.lastHandshakeAt == snap.lastHandshakeAt;
    if (same) {
      return;
    }
    emit(
      state.copyWith(
        rxBytes: snap.rxBytes,
        txBytes: snap.txBytes,
        lastHandshakeAt: snap.lastHandshakeAt,
      ),
    );
  }

  void _onStatus(VpnStatusSnapshot snap) {
    if (state.phase != VpnConnectPhase.startingTunnel &&
        state.phase != VpnConnectPhase.skeletonConnected) {
      return;
    }
    final key = '${snap.status}|${snap.extensionStatus}';
    if (key == _lastStatusKey) {
      if (state.phase == VpnConnectPhase.skeletonConnected) {
        _applyTraffic(snap);
      }
      return;
    }
    _lastStatusKey = key;

    final lines = List<VpnConnectLogLine>.from(state.log);
    void log(String message) {
      lines.add(VpnConnectLogLine(at: DateTime.now(), message: message));
    }

    log('VPN status → ${snap.status} (extension: ${snap.extensionStatus})');

    if (snap.status == 'connected' ||
        snap.extensionStatus == 'wireguard_started' ||
        snap.extensionStatus == 'skeleton_connected') {
      emit(
        state.copyWith(
          phase: VpnConnectPhase.skeletonConnected,
          stepLabel: 'Connected (WireGuard + wstunnel)',
          log: List.unmodifiable(lines),
          rxBytes: snap.rxBytes,
          txBytes: snap.txBytes,
          lastHandshakeAt: snap.lastHandshakeAt,
          clearError: true,
        ),
      );
      _startStatsPolling();
    } else if (snap.status == 'disconnected' &&
        state.phase == VpnConnectPhase.skeletonConnected) {
      _stopStatsPolling();
      emit(
        state.copyWith(
          phase: VpnConnectPhase.idle,
          stepLabel: 'Disconnected',
          log: List.unmodifiable(lines),
          clearTraffic: true,
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
    _lastStatusKey = null;
    _stopStatsPolling();

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
          clearTraffic: true,
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
      log(
        'wstunnel — in PacketTunnel; WG endpoint = 127.0.0.1:51820 → '
        '${peer.transport.url}/${peer.transport.pathPrefix}',
      );

      emitPhase(VpnConnectPhase.startingTunnel, 'Starting WireGuard…');
      log('vpn_engine.startTunnel — wstunnel + WireGuardKit');
      final tunnelConfig = <String, Object?>{
        'addresses': peer.interfaceAddresses,
        'dns': peer.dns,
        'mtu': peer.mtu,
        'server_public_key': peer.peerPublicKey,
        'allowed_ips': peer.allowedIps,
        'excluded_ips': peer.excludedIps,
        'persistent_keepalive': peer.persistentKeepalive,
        'server_ips': peer.transport.serverIps,
        'path_prefix': peer.transport.pathPrefix,
        'remote': peer.transport.remote,
        'transport_url': peer.transport.url,
        'url': peer.transport.url,
        'peer_id': peer.peerId,
      };
      final started = await _vpnEngine.startTunnel(tunnelConfig);
      log('startTunnel → ${started.status}: ${started.message}');
      if (!started.ok) {
        throw StateError('startTunnel failed: ${started.message}');
      }

      // Poll briefly for extension status / connected.
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final snap = await _vpnEngine.getStatus();
        log(
          'poll status=${snap.status} ext=${snap.extensionStatus}',
        );
        if (snap.status == 'connected' ||
            snap.extensionStatus == 'wireguard_started' ||
            snap.extensionStatus == 'skeleton_connected') {
          for (final line in snap.extensionLog) {
            log('ext: $line');
          }
          emit(
            state.copyWith(
              phase: VpnConnectPhase.skeletonConnected,
              stepLabel: 'Connected (WireGuard + wstunnel)',
              log: List.unmodifiable(lines),
              peer: peer,
              rxBytes: snap.rxBytes,
              txBytes: snap.txBytes,
              lastHandshakeAt: snap.lastHandshakeAt,
              clearError: true,
            ),
          );
          _startStatsPolling();
          return;
        }
        if (snap.status == 'disconnected' && i > 2) {
          break;
        }
      }

      emit(
        state.copyWith(
          phase: VpnConnectPhase.skeletonConnected,
          stepLabel: 'WireGuard start requested — check OS VPN / logs',
          log: List.unmodifiable(lines),
          peer: peer,
          clearError: true,
        ),
      );
      _startStatsPolling();
    } catch (e) {
      _stopStatsPolling();
      log('Error: $e');
      emit(
        state.copyWith(
          phase: VpnConnectPhase.error,
          stepLabel: 'Connect failed',
          log: List.unmodifiable(lines),
          errorMessage: e.toString(),
          clearTraffic: true,
        ),
      );
    }
  }

  Future<void> disconnect() async {
    if (state.isBusy) {
      return;
    }
    _stopStatsPolling();
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
        clearTraffic: true,
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
    _lastStatusKey = null;
    _stopStatsPolling();
    emit(VpnConnectState.initial());
  }
}
