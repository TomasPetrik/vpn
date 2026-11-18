/// App Store / Play links used by update CTAs.
///
/// `ios` is a temporary placeholder until PetrikVPN is published.
class AppStoreLinks {
  const AppStoreLinks._();

  static const ios =
      'https://apps.apple.com/de/app/train-this-much-home-workout/id1546661724';

  static String resolve({required String policyUrl, required bool isIos}) {
    final normalized = normalize(policyUrl);
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return isIos ? ios : '';
  }

  /// Ensures admin-entered URLs like `www.google.com` become launchable.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' ||
            parsed.scheme == 'https' ||
            parsed.scheme == 'itms-apps')) {
      return parsed.toString();
    }
    return Uri.parse('https://$trimmed').toString();
  }

  static Uri? uriFor({required String policyUrl, required bool isIos}) {
    final resolved = resolve(policyUrl: policyUrl, isIos: isIos);
    if (resolved.isEmpty) {
      return null;
    }
    return Uri.tryParse(resolved);
  }
}
