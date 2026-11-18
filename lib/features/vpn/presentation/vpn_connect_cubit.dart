import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../device/domain/device_repository.dart';
import '../../device/domain/vpn_peer_config.dart';
import '../domain/tunnel_latency_probe.dart';
import '../domain/vpn_engine.dart';
import '../domain/vpn_usage_stats.dart';

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
    this.sessionStartedAt,
    this.sessionSeconds = 0,
    this.rxMbps = 0,
    this.txMbps = 0,
    this.latencyMs,
    this.committedTotals = const VpnUsageTotals.zero(),
  });

  final VpnConnectPhase phase;
  final String stepLabel;
  final List<VpnConnectLogLine> log;
  final VpnPeerConfig? peer;
  final String? errorMessage;
  final int? rxBytes;
  final int? txBytes;
  final DateTime? lastHandshakeAt;
  final DateTime? sessionStartedAt;
  final int sessionSeconds;

  /// Instantaneous download rate from WireGuard counter deltas (Mbps).
  final double rxMbps;

  /// Instantaneous upload rate from WireGuard counter deltas (Mbps).
  final double txMbps;

  /// Latest TCP-connect RTT through the tunnel, in milliseconds.
  final int? latencyMs;
  final VpnUsageTotals committedTotals;

  bool get isBusy =>
      phase == VpnConnectPhase.checkingSession ||
      phase == VpnConnectPhase.ensuringKeys ||
      phase == VpnConnectPhase.provisioningPeer ||
      phase == VpnConnectPhase.preparingVpn ||
      phase == VpnConnectPhase.startingTransport ||
      phase == VpnConnectPhase.startingTunnel ||
      phase == VpnConnectPhase.disconnecting;

  bool get isConnected => phase == VpnConnectPhase.skeletonConnected;

  bool get canConnect =>
      phase == VpnConnectPhase.idle || phase == VpnConnectPhase.error;

  bool get canDisconnect => phase == VpnConnectPhase.skeletonConnected;

  bool get hasSessionStats =>
      isConnected && (rxBytes != null || txBytes != null || sessionStartedAt != null);

  VpnUsageTotals get overallTotals {
    final session = VpnUsageTotals(
      rxBytes: rxBytes ?? 0,
      txBytes: txBytes ?? 0,
      activeSeconds: sessionSeconds,
    );
    return isConnected ? committedTotals + session : committedTotals;
  }

  VpnConnectState copyWith({
    VpnConnectPhase? phase,
    String? stepLabel,
    List<VpnConnectLogLine>? log,
    VpnPeerConfig? peer,
    String? errorMessage,
    int? rxBytes,
    int? txBytes,
    DateTime? lastHandshakeAt,
    DateTime? sessionStartedAt,
    int? sessionSeconds,
    double? rxMbps,
    double? txMbps,
    int? latencyMs,
    VpnUsageTotals? committedTotals,
    bool clearError = false,
    bool clearPeer = false,
    bool clearTraffic = false,
    bool clearSession = false,
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
      sessionStartedAt:
          clearSession ? null : (sessionStartedAt ?? this.sessionStartedAt),
      sessionSeconds: clearSession ? 0 : (sessionSeconds ?? this.sessionSeconds),
      rxMbps: clearTraffic || clearSession ? 0 : (rxMbps ?? this.rxMbps),
      txMbps: clearTraffic || clearSession ? 0 : (txMbps ?? this.txMbps),
      latencyMs: clearTraffic || clearSession
          ? null
          : (latencyMs ?? this.latencyMs),
      committedTotals: committedTotals ?? this.committedTotals,
    );
  }

  static VpnConnectState initial({VpnUsageTotals? committedTotals}) =>
      VpnConnectState(
        phase: VpnConnectPhase.idle,
        stepLabel: 'Not connected',
        log: const [],
        committedTotals: committedTotals ?? const VpnUsageTotals.zero(),
      );
}

class VpnConnectCubit extends Cubit<VpnConnectState> {
  VpnConnectCubit({
    required DeviceRepository deviceRepository,
    required VpnEngine vpnEngine,
    required VpnUsageStatsStore usageStatsStore,
    TunnelLatencyProbe? latencyProbe,
    Duration latencyInterval = const Duration(seconds: 3),
  })  : _deviceRepository = deviceRepository,
        _vpnEngine = vpnEngine,
        _usageStatsStore = usageStatsStore,
        _latencyProbe = latencyProbe ?? const TcpTunnelLatencyProbe(),
        _latencyInterval = latencyInterval,
        super(VpnConnectState.initial()) {
    _statusSub = _vpnEngine.statusStream().listen(_onStatus);
    unawaited(_bootstrapUsage());
  }

  final DeviceRepository _deviceRepository;
  final VpnEngine _vpnEngine;
  final VpnUsageStatsStore _usageStatsStore;
  final TunnelLatencyProbe _latencyProbe;
  final Duration _latencyInterval;
  StreamSubscription<VpnStatusSnapshot>? _statusSub;
  Timer? _statsTimer;
  Timer? _latencyTimer;
  String? _lastStatusKey;
  bool _committingSession = false;
  bool _latencyInFlight = false;
  int? _prevRxBytes;
  int? _prevTxBytes;
  DateTime? _prevTrafficSampleAt;

  @override
  Future<void> close() async {
    _stopStatsPolling();
    await _statusSub?.cancel();
    return super.close();
  }

  Future<void> refreshCommittedTotals() async {
    final totals = await _usageStatsStore.readCommitted();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(committedTotals: totals));
  }

  Future<void> _bootstrapUsage() async {
    final totals = await _usageStatsStore.recoverInflightIfNeeded();
    if (isClosed) {
      return;
    }
    final current = state.committedTotals;
    if (totals.rxBytes == current.rxBytes &&
        totals.txBytes == current.txBytes &&
        totals.activeSeconds == current.activeSeconds) {
      return;
    }
    emit(state.copyWith(committedTotals: totals));
  }

  void _markSessionStarted({DateTime? at}) {
    if (state.sessionStartedAt != null) {
      return;
    }
    emit(state.copyWith(sessionStartedAt: at ?? DateTime.now(), sessionSeconds: 0));
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshTrafficStats());
    });
    unawaited(_refreshTrafficStats());
    _startLatencyPolling();
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _prevRxBytes = null;
    _prevTxBytes = null;
    _prevTrafficSampleAt = null;
    _stopLatencyPolling();
  }

  void _startLatencyPolling() {
    _latencyTimer?.cancel();
    _latencyTimer = Timer.periodic(_latencyInterval, (_) {
      unawaited(_refreshLatency());
    });
    unawaited(_refreshLatency());
  }

  void _stopLatencyPolling() {
    _latencyTimer?.cancel();
    _latencyTimer = null;
    _latencyInFlight = false;
  }

  Future<void> _refreshLatency() async {
    if (_latencyInFlight ||
        state.phase != VpnConnectPhase.skeletonConnected ||
        isClosed) {
      return;
    }
    _latencyInFlight = true;
    try {
      final host = _latencyHost();
      final ms = await _latencyProbe.measureMs(host: host);
      if (isClosed || state.phase != VpnConnectPhase.skeletonConnected) {
        return;
      }
      if (ms == state.latencyMs) {
        return;
      }
      emit(state.copyWith(latencyMs: ms));
    } finally {
      _latencyInFlight = false;
    }
  }

  String _latencyHost() {
    final dns = state.peer?.dns;
    if (dns != null) {
      for (final entry in dns) {
        final host = entry.trim();
        if (_looksLikeIpv4(host)) {
          return host;
        }
      }
    }
    return '1.1.1.1';
  }

  static bool _looksLikeIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) {
        return false;
      }
    }
    return true;
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
      await _applyTraffic(snap);
    } catch (_) {
      // Ignore transient channel errors while polling.
    }
  }

  Future<void> _applyTraffic(VpnStatusSnapshot snap) async {
    _markSessionStarted();
    final now = DateTime.now();
    final started = state.sessionStartedAt ?? now;
    final elapsed = now.difference(started).inSeconds;
    final rxMbps = _instantMbps(
      previous: _prevRxBytes,
      current: snap.rxBytes,
      previousAt: _prevTrafficSampleAt,
      now: now,
    );
    final txMbps = _instantMbps(
      previous: _prevTxBytes,
      current: snap.txBytes,
      previousAt: _prevTrafficSampleAt,
      now: now,
    );
    if (snap.rxBytes != null) {
      _prevRxBytes = snap.rxBytes;
    }
    if (snap.txBytes != null) {
      _prevTxBytes = snap.txBytes;
    }
    _prevTrafficSampleAt = now;

    final same = state.rxBytes == snap.rxBytes &&
        state.txBytes == snap.txBytes &&
        state.lastHandshakeAt == snap.lastHandshakeAt &&
        state.sessionSeconds == elapsed &&
        state.rxMbps == rxMbps &&
        state.txMbps == txMbps;
    if (same) {
      return;
    }
    emit(
      state.copyWith(
        rxBytes: snap.rxBytes,
        txBytes: snap.txBytes,
        lastHandshakeAt: snap.lastHandshakeAt,
        sessionStartedAt: started,
        sessionSeconds: elapsed,
        rxMbps: rxMbps,
        txMbps: txMbps,
      ),
    );
    await _usageStatsStore.writeInflight(
      rxBytes: snap.rxBytes ?? state.rxBytes ?? 0,
      txBytes: snap.txBytes ?? state.txBytes ?? 0,
      activeSeconds: elapsed,
    );
  }

  static double _instantMbps({
    required int? previous,
    required int? current,
    required DateTime? previousAt,
    required DateTime now,
  }) {
    if (previous == null || current == null || previousAt == null) {
      return 0;
    }
    final dtMs = now.difference(previousAt).inMilliseconds;
    if (dtMs < 200) {
      return 0;
    }
    final delta = current - previous;
    if (delta <= 0) {
      return 0;
    }
    final seconds = dtMs / 1000.0;
    final mbps = (delta * 8) / seconds / 1e6;
    // Quantize to avoid noisy UI rebuilds from float noise.
    return (mbps * 100).roundToDouble() / 100;
  }

  Future<void> _commitCurrentSession() async {
    if (_committingSession || state.sessionStartedAt == null) {
      return;
    }
    _committingSession = true;
    try {
      final seconds = state.sessionSeconds > 0
          ? state.sessionSeconds
          : DateTime.now().difference(state.sessionStartedAt!).inSeconds;
      await _usageStatsStore.commitSession(
        rxBytes: state.rxBytes ?? 0,
        txBytes: state.txBytes ?? 0,
        activeSeconds: seconds,
      );
      final totals = await _usageStatsStore.readCommitted();
      if (!isClosed) {
        emit(state.copyWith(committedTotals: totals));
      }
    } finally {
      _committingSession = false;
    }
  }

  void _onStatus(VpnStatusSnapshot snap) {
    if (state.phase != VpnConnectPhase.startingTunnel &&
        state.phase != VpnConnectPhase.skeletonConnected) {
      return;
    }
    final key = '${snap.status}|${snap.extensionStatus}';
    if (key == _lastStatusKey) {
      if (state.phase == VpnConnectPhase.skeletonConnected) {
        unawaited(_applyTraffic(snap));
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
      final started = state.sessionStartedAt ?? DateTime.now();
      emit(
        state.copyWith(
          phase: VpnConnectPhase.skeletonConnected,
          stepLabel: 'Connected',
          log: List.unmodifiable(lines),
          rxBytes: snap.rxBytes,
          txBytes: snap.txBytes,
          lastHandshakeAt: snap.lastHandshakeAt,
          sessionStartedAt: started,
          clearError: true,
        ),
      );
      _startStatsPolling();
    } else if (snap.status == 'disconnected' &&
        state.phase == VpnConnectPhase.skeletonConnected) {
      _stopStatsPolling();
      unawaited(() async {
        await _commitCurrentSession();
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            phase: VpnConnectPhase.idle,
            stepLabel: 'Not connected',
            log: List.unmodifiable(lines),
            clearTraffic: true,
            clearSession: true,
          ),
        );
      }());
    } else {
      emit(state.copyWith(log: List.unmodifiable(lines)));
    }
  }

  Future<void> connect() async {
    if (state.isBusy || state.isConnected) {
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
          clearSession: true,
        ),
      );
    }

    try {
      log('Connect tapped');
      emitPhase(VpnConnectPhase.checkingSession, 'Checking session…');
      log('ensureSession — register/re-auth if needed');
      final session = await _deviceRepository.ensureSession();
      log('Session OK — user ${session.userId}, device ${session.deviceId}');

      emitPhase(VpnConnectPhase.ensuringKeys, 'Preparing keys…');
      log('vpn_engine.getPublicKey — native Keychain');
      final publicKey = await _vpnEngine.getPublicKey();
      log('Public key ready (${publicKey.substring(0, 8)}…)');

      emitPhase(VpnConnectPhase.provisioningPeer, 'Provisioning…');
      log('PUT /devices/me/peer — registering public key');
      final peer = await _deviceRepository.upsertPeer(publicKey: publicKey);
      log(
        'Peer OK — ${peer.server.name} · ${peer.interfaceAddresses.join(', ')}',
      );

      emitPhase(VpnConnectPhase.preparingVpn, 'Requesting VPN permission…');
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

      emitPhase(VpnConnectPhase.startingTunnel, 'Connecting…');
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
          final sessionStart = DateTime.now();
          emit(
            state.copyWith(
              phase: VpnConnectPhase.skeletonConnected,
              stepLabel: 'Connected',
              log: List.unmodifiable(lines),
              peer: peer,
              rxBytes: snap.rxBytes,
              txBytes: snap.txBytes,
              lastHandshakeAt: snap.lastHandshakeAt,
              sessionStartedAt: sessionStart,
              sessionSeconds: 0,
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
          stepLabel: 'Connected',
          log: List.unmodifiable(lines),
          peer: peer,
          sessionStartedAt: DateTime.now(),
          sessionSeconds: 0,
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
          stepLabel: 'Connection failed',
          log: List.unmodifiable(lines),
          errorMessage: e.toString(),
          clearTraffic: true,
          clearSession: true,
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
    await _commitCurrentSession();
    log('vpn_engine.stopTunnel');
    final stopped = await _vpnEngine.stopTunnel();
    log('stopTunnel → ${stopped.message}');
    emit(
      state.copyWith(
        phase: VpnConnectPhase.idle,
        stepLabel: 'Not connected',
        log: List.unmodifiable(lines),
        clearPeer: true,
        clearTraffic: true,
        clearSession: true,
      ),
    );
  }
}
