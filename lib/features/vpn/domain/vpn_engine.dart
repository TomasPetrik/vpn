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

abstract class VpnEngine {
  /// Returns WireGuard public key (base64). Private key stays native.
  Future<String> getPublicKey();

  /// Requests OS VPN permission / installs tunnel preferences.
  Future<VpnPrepareResult> prepare();
}
