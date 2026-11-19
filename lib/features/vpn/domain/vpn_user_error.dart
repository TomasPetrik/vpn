import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// Maps technical connect failures to short, plain-language copy for the UI.
///
/// Keep detailed exceptions in the connect log / diagnostics — not on the home
/// screen.
abstract final class VpnUserError {
  static const generic =
      'Something went wrong while connecting. Please try again.';

  static String from(Object error) {
    if (error is DioException) {
      return _fromDio(error);
    }
    if (error is PlatformException) {
      return _fromPlatform(error);
    }
    if (error is UnsupportedError) {
      return 'VPN is not available on this device.';
    }

    final text = error.toString().toLowerCase();
    if (text.contains('vpn prepare failed')) {
      return _fromPrepareMessage(text);
    }
    if (text.contains('starttunnel failed') ||
        text.contains('start tunnel failed')) {
      return 'Could not start the VPN. Please try again.';
    }
    if (text.contains('public_key') || text.contains('key_error')) {
      return 'Could not prepare secure keys. Please try again.';
    }
    if (text.contains('device_token') || text.contains('register')) {
      return 'Could not sign in this device. Check your internet and try again.';
    }
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('offline') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (text.contains('timeout')) {
      return 'The connection timed out. Please try again.';
    }
    return generic;
  }

  static String _fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'The connection timed out. Please try again.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'No internet connection. Check your network and try again.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode ?? 0;
        if (code == 401 || code == 403) {
          return 'Your session expired. Please try again.';
        }
        if (code == 404) {
          return 'Server not found. Please try again later.';
        }
        if (code >= 500) {
          return 'Our servers are busy. Please try again in a moment.';
        }
        return 'Could not reach the VPN service. Please try again.';
      case DioExceptionType.cancel:
        return 'Connection was cancelled.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed. Please try again later.';
    }
  }

  static String _fromPlatform(PlatformException error) {
    final code = (error.code).toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    if (code.contains('key') || message.contains('key')) {
      return 'Could not prepare secure keys. Please try again.';
    }
    return generic;
  }

  static String _fromPrepareMessage(String text) {
    if (text.contains('denied') || text.contains('permission')) {
      return 'VPN permission is required to connect.';
    }
    if (text.contains('ipc') ||
        text.contains('preferences') ||
        text.contains('configuration')) {
      return 'Could not set up VPN on this device. Try again, or restart the app.';
    }
    return 'Could not set up VPN on this device. Please try again.';
  }
}
