import 'dart:io';

/// Measures approximate tunnel RTT via a TCP connect through the VPN.
///
/// Uses a public IP:443 so the probe rides WireGuard routes (VPS IPs are
/// excluded from the tunnel and would not measure tunnel latency).
abstract class TunnelLatencyProbe {
  Future<int?> measureMs({String host = '1.1.1.1', int port = 443});
}

class TcpTunnelLatencyProbe implements TunnelLatencyProbe {
  const TcpTunnelLatencyProbe({
    this.timeout = const Duration(seconds: 3),
  });

  final Duration timeout;

  @override
  Future<int?> measureMs({
    String host = '1.1.1.1',
    int port = 443,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      try {
        await socket.close();
      } catch (_) {}
      return sw.elapsedMilliseconds;
    } on Object {
      return null;
    }
  }
}
