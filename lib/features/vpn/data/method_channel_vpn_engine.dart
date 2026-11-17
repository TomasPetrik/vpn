import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/vpn_engine.dart';

class MethodChannelVpnEngine implements VpnEngine {
  MethodChannelVpnEngine({
    MethodChannel? channel,
    EventChannel? statusChannel,
  })  : _channel = channel ?? const MethodChannel('vpn_engine'),
        _statusChannel =
            statusChannel ?? const EventChannel('vpn_engine/status');

  final MethodChannel _channel;
  final EventChannel _statusChannel;

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<String> getPublicKey() async {
    if (!_isIos) {
      throw UnsupportedError('vpn_engine getPublicKey is iOS-only for now');
    }
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('getPublicKey');
    final key = result?['public_key'];
    if (key is! String || key.isEmpty) {
      throw StateError('getPublicKey returned no public_key');
    }
    return key;
  }

  @override
  Future<VpnPrepareResult> prepare() async {
    if (!_isIos) {
      return const VpnPrepareResult(
        granted: false,
        status: 'unsupported',
        message: 'prepare() is iOS-only for now',
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

  @override
  Future<VpnTunnelResult> startTunnel(Map<String, Object?> tunnelConfig) async {
    if (!_isIos) {
      return const VpnTunnelResult(
        ok: false,
        status: 'unsupported',
        message: 'startTunnel() is iOS-only for now',
      );
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'startTunnel',
      tunnelConfig,
    );
    if (result == null) {
      return const VpnTunnelResult(
        ok: false,
        status: 'error',
        message: 'startTunnel() returned null',
      );
    }
    return VpnTunnelResult.fromMap(result);
  }

  @override
  Future<VpnTunnelResult> stopTunnel() async {
    if (!_isIos) {
      return const VpnTunnelResult(
        ok: false,
        status: 'unsupported',
        message: 'stopTunnel() is iOS-only for now',
      );
    }
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('stopTunnel');
    if (result == null) {
      return const VpnTunnelResult(
        ok: false,
        status: 'error',
        message: 'stopTunnel() returned null',
      );
    }
    return VpnTunnelResult.fromMap(result);
  }

  @override
  Future<VpnStatusSnapshot> getStatus() async {
    if (!_isIos) {
      return const VpnStatusSnapshot(
        status: 'unsupported',
        extensionStatus: '',
        extensionLog: [],
      );
    }
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('getStatus');
    if (result == null) {
      return const VpnStatusSnapshot(
        status: 'unknown',
        extensionStatus: '',
        extensionLog: [],
      );
    }
    return VpnStatusSnapshot.fromMap(result);
  }

  @override
  Stream<VpnStatusSnapshot> statusStream() {
    if (!_isIos) {
      return const Stream.empty();
    }
    return _statusChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return VpnStatusSnapshot.fromMap(Map<Object?, Object?>.from(event));
      }
      return const VpnStatusSnapshot(
        status: 'unknown',
        extensionStatus: '',
        extensionLog: [],
      );
    });
  }
}
