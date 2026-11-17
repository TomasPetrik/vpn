import Foundation
import NetworkExtension
import Security
import WireGuardKit

/// Packet tunnel powered by WireGuardKit.
/// Endpoint is local (127.0.0.1:51820) until step 5 starts the wstunnel client there.
class PacketTunnelProvider: NEPacketTunnelProvider {
  static let appGroupId = "group.cz.tomaspetrik.petrikvpn"
  static let keychainService = "cz.tomaspetrik.petrikvpn.wireguard"
  static let keychainAccount = "private_key"
  /// Reserved for the in-extension wstunnel client (step 5).
  static let localTransportEndpoint = "127.0.0.1:51820"

  private var adapter: WireGuardAdapter?

  override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    appendLog("PacketTunnel startTunnel (WireGuardKit)")
    writeStatus("starting_wireguard")

    do {
      let privateKeyData = try loadPrivateKeyData()
      guard let privateKey = PrivateKey(rawValue: privateKeyData) else {
        throw TunnelError.invalidPrivateKey
      }
      let configJSON = try loadTunnelConfigJSON()
      let tunnelConfig = try Self.buildTunnelConfiguration(
        privateKey: privateKey,
        config: configJSON
      )
      appendLog("config ready peers=\(tunnelConfig.peers.count) addrs=\(tunnelConfig.interface.addresses.map(\.stringRepresentation).joined(separator: ","))")

      let adapter = WireGuardAdapter(with: self) { [weak self] level, message in
        self?.appendLog("wg[\(level)] \(message)")
      }
      self.adapter = adapter
      adapter.start(tunnelConfiguration: tunnelConfig) { [weak self] error in
        if let error {
          self?.appendLog("WireGuardAdapter start failed: \(error.localizedDescription)")
          self?.writeStatus("error")
          completionHandler(error)
          return
        }
        self?.appendLog("WireGuard started (awaiting wstunnel on \(Self.localTransportEndpoint))")
        self?.writeStatus("wireguard_started")
        completionHandler(nil)
      }
    } catch {
      appendLog("startTunnel error: \(error.localizedDescription)")
      writeStatus("error")
      completionHandler(error)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    appendLog("PacketTunnel stopTunnel reason=\(reason.rawValue)")
    writeStatus("disconnecting")
    guard let adapter else {
      writeStatus("disconnected")
      completionHandler()
      return
    }
    adapter.stop { [weak self] error in
      if let error {
        self?.appendLog("adapter stop error: \(error.localizedDescription)")
      }
      self?.adapter = nil
      self?.writeStatus("disconnected")
      completionHandler()
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
    if lines.count > 100 {
      lines = Array(lines.suffix(100))
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

  var errorDescription: String? {
    switch self {
    case .missingTunnelConfig: return "Missing tunnel_config in App Group"
    case .invalidPrivateKey: return "Invalid WireGuard private key"
    case .invalidServerPublicKey: return "Invalid server public key"
    case .invalidEndpoint: return "Invalid local transport endpoint"
    case .keychainReadFailed(let status): return "Keychain read failed (\(status))"
    }
  }
}
