import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vpn_usage_stats.dart';

class SharedPrefsVpnUsageStatsStore implements VpnUsageStatsStore {
  SharedPrefsVpnUsageStatsStore(this._prefs);

  static const _rxKey = 'vpn_usage_rx_bytes';
  static const _txKey = 'vpn_usage_tx_bytes';
  static const _secondsKey = 'vpn_usage_active_seconds';
  static const _inflightRxKey = 'vpn_usage_inflight_rx';
  static const _inflightTxKey = 'vpn_usage_inflight_tx';
  static const _inflightSecondsKey = 'vpn_usage_inflight_seconds';
  static const _inflightFlagKey = 'vpn_usage_inflight_active';

  final SharedPreferences _prefs;

  @override
  Future<VpnUsageTotals> readCommitted() async {
    return VpnUsageTotals(
      rxBytes: _prefs.getInt(_rxKey) ?? 0,
      txBytes: _prefs.getInt(_txKey) ?? 0,
      activeSeconds: _prefs.getInt(_secondsKey) ?? 0,
    );
  }

  @override
  Future<void> commitSession({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  }) async {
    final safeRx = rxBytes < 0 ? 0 : rxBytes;
    final safeTx = txBytes < 0 ? 0 : txBytes;
    final safeSeconds = activeSeconds < 0 ? 0 : activeSeconds;
    if (safeRx == 0 && safeTx == 0 && safeSeconds == 0) {
      await clearInflight();
      return;
    }
    final current = await readCommitted();
    await _prefs.setInt(_rxKey, current.rxBytes + safeRx);
    await _prefs.setInt(_txKey, current.txBytes + safeTx);
    await _prefs.setInt(_secondsKey, current.activeSeconds + safeSeconds);
    await clearInflight();
  }

  @override
  Future<void> writeInflight({
    required int rxBytes,
    required int txBytes,
    required int activeSeconds,
  }) async {
    await _prefs.setBool(_inflightFlagKey, true);
    await _prefs.setInt(_inflightRxKey, rxBytes < 0 ? 0 : rxBytes);
    await _prefs.setInt(_inflightTxKey, txBytes < 0 ? 0 : txBytes);
    await _prefs.setInt(
      _inflightSecondsKey,
      activeSeconds < 0 ? 0 : activeSeconds,
    );
  }

  @override
  Future<void> clearInflight() async {
    await _prefs.remove(_inflightFlagKey);
    await _prefs.remove(_inflightRxKey);
    await _prefs.remove(_inflightTxKey);
    await _prefs.remove(_inflightSecondsKey);
  }

  @override
  Future<VpnUsageTotals> recoverInflightIfNeeded() async {
    if (_prefs.getBool(_inflightFlagKey) != true) {
      return readCommitted();
    }
    await commitSession(
      rxBytes: _prefs.getInt(_inflightRxKey) ?? 0,
      txBytes: _prefs.getInt(_inflightTxKey) ?? 0,
      activeSeconds: _prefs.getInt(_inflightSecondsKey) ?? 0,
    );
    return readCommitted();
  }
}
