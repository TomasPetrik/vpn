class VpnStatsFormat {
  const VpnStatsFormat._();

  /// Format an instantaneous megabits/sec rate.
  static String mbpsRate(double mbps) {
    if (mbps <= 0 || mbps.isNaN || mbps.isInfinite) {
      return '0.0';
    }
    if (mbps >= 100) {
      return mbps.toStringAsFixed(0);
    }
    if (mbps >= 10) {
      return mbps.toStringAsFixed(1);
    }
    return mbps.toStringAsFixed(2);
  }

  /// Average megabits/sec from transferred [bytes] over [seconds].
  static String mbps(int bytes, int seconds) {
    if (seconds <= 0 || bytes <= 0) {
      return '0.0';
    }
    return mbpsRate((bytes * 8) / seconds / 1e6);
  }

  static String bytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble().abs();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  static String duration(int totalSeconds, {bool includeHours = false}) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (includeHours || h > 0) {
      return '${two(h)}:${two(m)}:${two(s)}';
    }
    return '${two(m)}:${two(s)}';
  }

  static String handshakeAgo(DateTime? at, DateTime now) {
    if (at == null) {
      return 'Waiting…';
    }
    final seconds = now.difference(at.toLocal()).inSeconds;
    if (seconds < 0) {
      return 'just now';
    }
    if (seconds < 60) {
      return '${seconds}s ago';
    }
    if (seconds < 3600) {
      return '${seconds ~/ 60}m ago';
    }
    if (seconds < 86400) {
      return '${seconds ~/ 3600}h ago';
    }
    return '${seconds ~/ 86400}d ago';
  }
}
