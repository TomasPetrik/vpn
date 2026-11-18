import 'package:flutter_test/flutter_test.dart';
import 'package:ru_eu_vpn/features/app_update/domain/app_store_links.dart';

void main() {
  test('normalize adds https when scheme is missing', () {
    expect(
      AppStoreLinks.normalize('www.google.com'),
      'https://www.google.com',
    );
  });

  test('normalize keeps https urls', () {
    expect(
      AppStoreLinks.normalize(
        'https://apps.apple.com/de/app/train-this-much-home-workout/id1546661724',
      ),
      'https://apps.apple.com/de/app/train-this-much-home-workout/id1546661724',
    );
  });

  test('resolve falls back to temp ios link', () {
    expect(
      AppStoreLinks.resolve(policyUrl: '', isIos: true),
      AppStoreLinks.ios,
    );
  });
}
