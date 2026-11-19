import 'package:shared_preferences/shared_preferences.dart';

/// Persists first-connect privacy disclosure acceptance (Apple 5.4 / Play VpnService).
class VpnPrivacyDisclosureStore {
  VpnPrivacyDisclosureStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'vpn_privacy_disclosure_accepted_v1';

  bool get hasAccepted => _prefs.getBool(_key) ?? false;

  Future<void> accept() => _prefs.setBool(_key, true);
}
