import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ru_eu_vpn/features/vpn/domain/vpn_user_error.dart';

void main() {
  test('maps prepare IPC failure to plain language', () {
    expect(
      VpnUserError.from(StateError('VPN prepare failed: IPC failed')),
      'Could not set up VPN on this device. Try again, or restart the app.',
    );
  });

  test('maps permission denied prepare failure', () {
    expect(
      VpnUserError.from(StateError('VPN prepare failed: VPN permission denied')),
      'VPN permission is required to connect.',
    );
  });

  test('maps startTunnel failure', () {
    expect(
      VpnUserError.from(StateError('startTunnel failed: boom')),
      'Could not start the VPN. Please try again.',
    );
  });

  test('maps Dio timeout and connection errors', () {
    expect(
      VpnUserError.from(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      'The connection timed out. Please try again.',
    );
    expect(
      VpnUserError.from(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      ),
      'No internet connection. Check your network and try again.',
    );
  });

  test('never returns DioException or Bad state prefixes', () {
    final messages = [
      VpnUserError.from(StateError('VPN prepare failed: IPC failed')),
      VpnUserError.from(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
          ),
        ),
      ),
      VpnUserError.from(
        PlatformException(code: 'key_error', message: 'secure enclave'),
      ),
      VpnUserError.from(Exception('totally unknown')),
    ];
    for (final message in messages) {
      expect(message.toLowerCase(), isNot(contains('dioexception')));
      expect(message.toLowerCase(), isNot(contains('bad state')));
      expect(message.toLowerCase(), isNot(contains('exception')));
    }
  });
}
