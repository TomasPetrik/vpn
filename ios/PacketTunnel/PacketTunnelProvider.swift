import Foundation
import NetworkExtension
import Security
import WireGuardKit
import WstunnelFFI

/// Packet tunnel: wstunnel client (local UDP) + WireGuardKit.
class PacketTunnelProvider: NEPacketTunnelProvider {
  static let appGroupId = "group.cz.tomaspetrik.petrikvpn"
  static let keychainService = "cz.tomaspetrik.petrikvpn.wireguard"
  static let keychainAccount = "private_key"
  /// Local UDP port where wstunnel listens; WireGuard peers this endpoint.
  static let localTransportEndpoint = "127.0.0.1:51820"

  private var adapter: WireGuardAdapter?
  private var wstunnelRunning = false
  /// VPS public IPs that must stay outside the tunnel so WSS does not hairpin.
  private var excludedV4Routes: [NEIPv4Route] = []

  override func setTunnelNetworkSettings(
    _ tunnelNetworkSettings: NETunnelNetworkSettings?,
    completionHandler: ((Error?) -> Void)? = nil
  ) {
    if let packet = tunnelNetworkSettings as? NEPacketTunnelNetworkSettings,
       let ipv4 = packet.ipv4Settings,
       !excludedV4Routes.isEmpty
    {
      ipv4.excludedRoutes = excludedV4Routes
      packet.ipv4Settings = ipv4
      appendLog("excludedRoutes=\(excludedV4Routes.map { "\($0.destinationAddress)/\($0.destinationSubnetMask)" }.joined(separator: ","))")
    }
    super.setTunnelNetworkSettings(tunnelNetworkSettings, completionHandler: completionHandler)
  }

  override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    appendLog("PacketTunnel startTunnel (wstunnel + WireGuardKit)")
    writeStatus("starting_transport")

    do {
      let privateKeyData = try loadPrivateKeyData()
      guard let privateKey = PrivateKey(rawValue: privateKeyData) else {
        throw TunnelError.invalidPrivateKey
      }
      let configJSON = try loadTunnelConfigJSON()
      excludedV4Routes = Self.excludedRoutes(from: configJSON)
      try startWstunnel(from: configJSON)
      writeStatus("wstunnel_started")

      let tunnelConfig = try Self.buildTunnelConfiguration(
        privateKey: privateKey,
        config: configJSON
      )
      appendLog(
        "config ready peers=\(tunnelConfig.peers.count) addrs=\(tunnelConfig.interface.addresses.map(\.stringRepresentation).joined(separator: ","))"
      )
      writeStatus("starting_wireguard")

      let adapter = WireGuardAdapter(with: self) { [weak self] level, message in
        self?.appendLog("wg[\(level)] \(message)")
      }
      self.adapter = adapter
      adapter.start(tunnelConfiguration: tunnelConfig) { [weak self] error in
        if let error {
          self?.appendLog("WireGuardAdapter start failed: \(error.localizedDescription)")
          self?.stopWstunnel()
          self?.writeStatus("error")
          completionHandler(error)
          return
        }
        self?.appendLog("WireGuard started (wstunnel on \(Self.localTransportEndpoint))")
        self?.writeStatus("wireguard_started")
        completionHandler(nil)
      }
    } catch {
      appendLog("startTunnel error: \(error.localizedDescription)")
      stopWstunnel()
      writeStatus("error")
      completionHandler(error)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    appendLog("PacketTunnel stopTunnel reason=\(reason.rawValue)")
    writeStatus("disconnecting")
    let finish = { [weak self] in
      self?.stopWstunnel()
      self?.writeStatus("disconnected")
      completionHandler()
    }
    guard let adapter else {
      finish()
      return
    }
    adapter.stop { [weak self] error in
      if let error {
        self?.appendLog("adapter stop error: \(error.localizedDescription)")
      }
      self?.adapter = nil
      finish()
    }
  }

  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    let text = String(data: messageData, encoding: .utf8) ?? ""
    appendLog("appMessage: \(text)")
    if text == "ping" {
      completionHandler?("pong".data(using: .utf8))
      return
    }
    completionHandler?(nil)
  }

  // MARK: - wstunnel

  private func startWstunnel(from config: [String: Any]) throws {
    let transportJSON = try Self.buildWstunnelConfigJSON(from: config)
    appendLog("wstunnel start \(transportJSON)")
    var err = [CChar](repeating: 0, count: 512)
    let rc = transportJSON.withCString { ptr in
      wstunnel_client_start(ptr, &err, err.count)
    }
    if rc != 0 {
      let message = String(cString: err)
      throw TunnelError.wstunnelStartFailed(rc, message)
    }
    wstunnelRunning = true
    appendLog("wstunnel_started local=\(Self.localTransportEndpoint)")
  }

  private func stopWstunnel() {
    guard wstunnelRunning || wstunnel_client_is_running() != 0 else { return }
    appendLog("wstunnel_stop")
    wstunnel_client_stop()
    wstunnelRunning = false
  }

  static func excludedRoutes(from config: [String: Any]) -> [NEIPv4Route] {
    let cidrs = (config["excluded_ips"] as? [String]) ?? []
    var routes: [NEIPv4Route] = []
    for cidr in cidrs {
      let parts = cidr.split(separator: "/")
      guard let host = parts.first.map(String.init), !host.isEmpty else { continue }
      let prefix = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
      let mask = Self.ipv4SubnetMask(prefixLength: prefix)
      routes.append(NEIPv4Route(destinationAddress: host, subnetMask: mask))
    }
    return routes
  }

  static func ipv4SubnetMask(prefixLength: Int) -> String {
    let prefix = max(0, min(32, prefixLength))
    if prefix == 0 { return "0.0.0.0" }
    let mask: UInt32 = prefix == 32 ? 0xffff_ffff : ~((1 << (32 - prefix)) - 1)
    return [
      (mask >> 24) & 0xff,
      (mask >> 16) & 0xff,
      (mask >> 8) & 0xff,
      mask & 0xff,
    ].map(String.init).joined(separator: ".")
  }

  static func buildWstunnelConfigJSON(from config: [String: Any]) throws -> String {
    let serverIps = config["server_ips"] as? [String] ?? []
    guard let serverIp = serverIps.first, !serverIp.isEmpty else {
      throw TunnelError.missingTransport("server_ips")
    }
    let pathPrefix = (config["path_prefix"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      ?? ""
    guard !pathPrefix.isEmpty else {
      throw TunnelError.missingTransport("path_prefix")
    }
    let remote = (config["remote"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "127.0.0.1:51821"
    let url = (config["transport_url"] as? String)
      ?? (config["url"] as? String)
      ?? "wss://vpn.radarcut.com"
    let tlsSni: String = {
      if let host = URL(string: url)?.host, !host.isEmpty { return host }
      return "vpn.radarcut.com"
    }()

    let payload: [String: Any] = [
      "server_ip": serverIp,
      "tls_sni": tlsSni,
      "path_prefix": pathPrefix,
      "remote": remote,
      "local_udp": localTransportEndpoint,
      "url": url,
      // iOS NE often has an empty rustls native trust store; LE verify fails otherwise.
      // TODO: ship webpki-roots (or Security.framework verifier) and re-enable.
      "tls_verify_certificate": false,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
    guard let s = String(data: data, encoding: .utf8) else {
      throw TunnelError.missingTransport("json")
    }
    return s
  }

  // MARK: - Config

  static func buildTunnelConfiguration(privateKey: PrivateKey, config: [String: Any]) throws -> TunnelConfiguration {
    var iface = InterfaceConfiguration(privateKey: privateKey)
    if let addresses = config["addresses"] as? [String] {
      iface.addresses = addresses.compactMap { IPAddressRange(from: $0) }
    }
    if let dns = config["dns"] as? [String] {
      iface.dns = dns.compactMap { DNSServer(from: $0) }
    }
    if let mtu = config["mtu"] as? Int, mtu > 0, mtu <= Int(UInt16.max) {
      iface.mtu = UInt16(mtu)
    }

    let serverPublicKey = (config["server_public_key"] as? String) ?? ""
    guard let publicKey = PublicKey(base64Key: serverPublicKey) else {
      throw TunnelError.invalidServerPublicKey
    }
    var peer = PeerConfiguration(publicKey: publicKey)
    if let allowed = config["allowed_ips"] as? [String] {
      peer.allowedIPs = allowed.compactMap { IPAddressRange(from: $0) }
    }
    if let keepalive = config["persistent_keepalive"] as? Int, keepalive >= 0, keepalive <= Int(UInt16.max) {
      peer.persistentKeepAlive = UInt16(keepalive)
    }
    guard let endpoint = Endpoint(from: localTransportEndpoint) else {
      throw TunnelError.invalidEndpoint
    }
    peer.endpoint = endpoint

    return TunnelConfiguration(name: "PetrikVPN", interface: iface, peers: [peer])
  }

  private func loadTunnelConfigJSON() throws -> [String: Any] {
    guard let defaults = UserDefaults(suiteName: Self.appGroupId),
          let data = defaults.data(forKey: "tunnel_config")
    else {
      throw TunnelError.missingTunnelConfig
    }
    let obj = try JSONSerialization.jsonObject(with: data)
    guard let map = obj as? [String: Any] else {
      throw TunnelError.missingTunnelConfig
    }
    return map
  }

  private func loadPrivateKeyData() throws -> Data {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.keychainService,
      kSecAttrAccount as String: Self.keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let group = keychainAccessGroup() {
      query[kSecAttrAccessGroup as String] = group
    }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      throw TunnelError.keychainReadFailed(status)
    }
    return data
  }

  private func keychainAccessGroup() -> String? {
    guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
          !prefix.isEmpty
    else { return nil }
    return prefix + "cz.tomaspetrik.petrikvpn"
  }

  // MARK: - App Group status / log

  private func defaults() -> UserDefaults? {
    UserDefaults(suiteName: Self.appGroupId)
  }

  private func writeStatus(_ status: String) {
    let d = defaults()
    d?.set(status, forKey: "tunnel_status")
    d?.set(Date().timeIntervalSince1970, forKey: "tunnel_status_at")
    d?.synchronize()
  }

  private func appendLog(_ line: String) {
    let d = defaults()
    var lines = d?.stringArray(forKey: "tunnel_log") ?? []
    let stamp = ISO8601DateFormatter().string(from: Date())
    lines.append("\(stamp) \(line)")
    if lines.count > 120 {
      lines = Array(lines.suffix(120))
    }
    d?.set(lines, forKey: "tunnel_log")
    d?.synchronize()
  }
}

private enum TunnelError: LocalizedError {
  case missingTunnelConfig
  case invalidPrivateKey
  case invalidServerPublicKey
  case invalidEndpoint
  case keychainReadFailed(OSStatus)
  case missingTransport(String)
  case wstunnelStartFailed(Int32, String)

  var errorDescription: String? {
    switch self {
    case .missingTunnelConfig: return "Missing tunnel_config in App Group"
    case .invalidPrivateKey: return "Invalid WireGuard private key"
    case .invalidServerPublicKey: return "Invalid server public key"
    case .invalidEndpoint: return "Invalid local transport endpoint"
    case .keychainReadFailed(let status): return "Keychain read failed (\(status))"
    case .missingTransport(let field): return "Missing transport field: \(field)"
    case .wstunnelStartFailed(let code, let message):
      return "wstunnel start failed (\(code)): \(message)"
    }
  }
}
