class VpnUsageTotals {
  const VpnUsageTotals({
    required this.rxBytes,
    required this.txBytes,
    required this.activeSeconds,
  });

  const VpnUsageTotals.zero()
      : rxBytes = 0,
        txBytes = 0,
        activeSeconds = 0;

  final int rxBytes;
  final int txBytes;
  final int activeSeconds;

  VpnUsageTotals operator +(VpnUsageTotals other) {
    return VpnUsageTotals(
      rxBytes: rxBytes + other.rxBytes,
      txBytes: txBytes + other.txBytes,
      activeSeconds: activeSeconds + other.activeSeconds,
    );
  }

  VpnUsageTotals addSession({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  }) {
    return VpnUsageTotals(
      rxBytes: this.rxBytes + rxBytes,
      txBytes: this.txBytes + txBytes,
      activeSeconds: this.activeSeconds + activeSeconds,
    );
  }
}

abstract class VpnUsageStatsStore {
  Future<VpnUsageTotals> readCommitted();

  Future<void> commitSession({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  });

  /// Crash-safe checkpoint of the live session (replaced each poll).
  Future<void> writeInflight({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  });

  /// Latest checkpoint of an unfinished session, or null if none.
  Future<VpnUsageTotals?> readInflight();

  Future<void> clearInflight();

  /// If a previous session was checkpointed and never committed, fold it in.
  Future<VpnUsageTotals> recoverInflightIfNeeded();
}
