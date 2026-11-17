import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/vpn_engine.dart';

class MethodChannelVpnEngine implements VpnEngine {
  MethodChannelVpnEngine({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('vpn_engine');

  final MethodChannel _channel;

  @override
  Future<String> getPublicKey() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('vpn_engine getPublicKey is iOS-only in step 2');
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('getPublicKey');
    final key = result?['public_key'];
    if (key is! String || key.isEmpty) {
      throw StateError('getPublicKey returned no public_key');
    }
    return key;
  }

  @override
  Future<VpnPrepareResult> prepare() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const VpnPrepareResult(
        granted: false,
        status: 'unsupported',
        message: 'prepare() is iOS-only in step 2',
      );
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('prepare');
    if (result == null) {
      return const VpnPrepareResult(
        granted: false,
        status: 'error',
        message: 'prepare() returned null',
      );
    }
    return VpnPrepareResult.fromMap(result);
  }
}
