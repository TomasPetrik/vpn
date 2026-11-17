import 'package:equatable/equatable.dart';

import '../../servers/domain/vpn_server.dart';

class VpnPeerConfig extends Equatable {
  const VpnPeerConfig({
    required this.peerId,
    required this.server,
    required this.interfaceAddresses,
    required this.dns,
    required this.mtu,
    required this.peerPublicKey,
    required this.allowedIps,
    required this.excludedIps,
    required this.persistentKeepalive,
    required this.transport,
  });

  final String peerId;
  final VpnServer server;
  final List<String> interfaceAddresses;
  final List<String> dns;
  final int mtu;
  final String peerPublicKey;
  final List<String> allowedIps;
  final List<String> excludedIps;
  final int persistentKeepalive;
  final VpnTransportConfig transport;

  factory VpnPeerConfig.fromJson(Map<String, dynamic> json) {
    final iface = Map<String, dynamic>.from(json['interface'] as Map? ?? {});
    final peer = Map<String, dynamic>.from(json['peer'] as Map? ?? {});
    final transport = Map<String, dynamic>.from(json['transport'] as Map? ?? {});
    final serverJson = Map<String, dynamic>.from(json['server'] as Map? ?? {});

    return VpnPeerConfig(
      peerId: '${json['peer_id']}',
      server: VpnServer.fromJson({
        ...serverJson,
        'status': serverJson['status'] ?? 'online',
      }),
      interfaceAddresses: _stringList(iface['addresses']),
      dns: _stringList(iface['dns']),
      mtu: int.tryParse('${iface['mtu'] ?? 1280}') ?? 1280,
      peerPublicKey: '${peer['public_key'] ?? ''}',
      allowedIps: _stringList(peer['allowed_ips']),
      excludedIps: _stringList(peer['excluded_ips']),
      persistentKeepalive:
          int.tryParse('${peer['persistent_keepalive'] ?? 25}') ?? 25,
      transport: VpnTransportConfig.fromJson(transport),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map((e) => '$e').toList();
  }

  @override
  List<Object?> get props => [
        peerId,
        server,
        interfaceAddresses,
        dns,
        mtu,
        peerPublicKey,
        allowedIps,
        excludedIps,
        persistentKeepalive,
        transport,
      ];
}

class VpnTransportConfig extends Equatable {
  const VpnTransportConfig({
    required this.type,
    required this.url,
    required this.pathPrefix,
    required this.remote,
    required this.serverIps,
  });

  final String type;
  final String url;
  final String pathPrefix;
  final String remote;
  final List<String> serverIps;

  factory VpnTransportConfig.fromJson(Map<String, dynamic> json) {
    return VpnTransportConfig(
      type: '${json['type'] ?? 'wstunnel'}',
      url: '${json['url'] ?? ''}',
      pathPrefix: '${json['path_prefix'] ?? ''}',
      remote: '${json['remote'] ?? ''}',
      serverIps: json['server_ips'] is List
          ? (json['server_ips'] as List).map((e) => '$e').toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [type, url, pathPrefix, remote, serverIps];
}
