class VpnPrepareResult {
  const VpnPrepareResult({
    required this.granted,
    required this.status,
    required this.message,
  });

  final bool granted;

  /// ready | needs_extension | denied | error | unsupported
  final String status;
  final String message;

  factory VpnPrepareResult.fromMap(Map<Object?, Object?> map) {
    return VpnPrepareResult(
      granted: map['granted'] == true,
      status: '${map['status'] ?? 'error'}',
      message: '${map['message'] ?? ''}',
    );
  }
}

class VpnTunnelResult {
  const VpnTunnelResult({
    required this.ok,
    required this.status,
    required this.message,
  });

  final bool ok;
  final String status;
  final String message;

  factory VpnTunnelResult.fromMap(Map<Object?, Object?> map) {
    return VpnTunnelResult(
      ok: map['ok'] == true,
      status: '${map['status'] ?? ''}',
      message: '${map['message'] ?? ''}',
    );
  }
}

class VpnStatusSnapshot {
  const VpnStatusSnapshot({
    required this.status,
    required this.extensionStatus,
    required this.extensionLog,
    this.rxBytes,
    this.txBytes,
    this.lastHandshakeAt,
  });

  final String status;
  final String extensionStatus;
  final List<String> extensionLog;

  /// WireGuard peer counters from PacketTunnel runtime config (when connected).
  final int? rxBytes;
  final int? txBytes;
  final DateTime? lastHandshakeAt;

  factory VpnStatusSnapshot.fromMap(Map<Object?, Object?> map) {
    final rawLog = map['extension_log'];
    final log = <String>[];
    if (rawLog is List) {
      for (final line in rawLog) {
        log.add('$line');
      }
    }
    DateTime? handshake;
    final hs = map['last_handshake_sec'];
    if (hs is num && hs > 0) {
      handshake = DateTime.fromMillisecondsSinceEpoch(
        (hs.toInt()) * 1000,
        isUtc: true,
      );
    }
    int? asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    return VpnStatusSnapshot(
      status: '${map['status'] ?? 'unknown'}',
      extensionStatus: '${map['extension_status'] ?? ''}',
      extensionLog: log,
      rxBytes: asInt(map['rx_bytes']),
      txBytes: asInt(map['tx_bytes']),
      lastHandshakeAt: handshake,
    );
  }
}

abstract class VpnEngine {
  /// Returns WireGuard public key (base64). Private key stays native.
  Future<String> getPublicKey();

  /// Requests OS VPN permission / installs tunnel preferences.
  Future<VpnPrepareResult> prepare();

  /// Starts the PacketTunnel provider with the provisioned peer config.
  Future<VpnTunnelResult> startTunnel(Map<String, Object?> tunnelConfig);

  /// Stops the PacketTunnel provider.
  Future<VpnTunnelResult> stopTunnel();

  Future<VpnStatusSnapshot> getStatus();

  Stream<VpnStatusSnapshot> statusStream();
}
