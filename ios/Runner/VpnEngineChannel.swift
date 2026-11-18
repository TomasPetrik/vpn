import CryptoKit
import Flutter
import Foundation
import NetworkExtension
import Security
import UIKit

/// MethodChannel `vpn_engine` + EventChannel `vpn_engine/status`.
final class VpnEngineChannel: NSObject, FlutterStreamHandler {
  static let channelName = "vpn_engine"
  static let statusChannelName = "vpn_engine/status"
  static let providerBundleId = "cz.tomaspetrik.petrikvpn.PacketTunnel"
  static let appGroupId = "group.cz.tomaspetrik.petrikvpn"
  static let keychainService = "cz.tomaspetrik.petrikvpn.wireguard"
  static let keychainAccount = "private_key"

  private let channel: FlutterMethodChannel
  private let statusChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var statusObserver: NSObjectProtocol?
  private var cachedManager: NETunnelProviderManager?
  private var emitWorkItem: DispatchWorkItem?
  private var lastEmittedStatus: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    statusChannel = FlutterEventChannel(name: Self.statusChannelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler(handle)
    statusChannel.setStreamHandler(self)
  }

  deinit {
    detachStatusObserver()
    emitWorkItem?.cancel()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    scheduleEmitStatus(forceLoad: true)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPublicKey":
      do {
        let publicKey = try Self.ensurePublicKey()
        result(["public_key": publicKey])
      } catch {
        result(FlutterError(code: "key_error", message: error.localizedDescription, details: nil))
      }
    case "prepare":
      prepareVpn { payload in result(payload) }
    case "startTunnel":
      let args = call.arguments as? [String: Any] ?? [:]
      startTunnel(config: args) { payload in result(payload) }
    case "stopTunnel":
      stopTunnel { payload in result(payload) }
    case "getStatus":
      currentStatusPayload(forceLoad: false) { payload in result(payload) }
    case "extensionLog":
      result(["lines": Self.extensionLogLines()])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Status observation

  private func attachStatusObserver(to connection: NEVPNConnection) {
    detachStatusObserver()
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: connection,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      let connection = notification.object as? NEVPNConnection
      self.scheduleEmitStatus(connection: connection, forceLoad: false)
    }
  }

  private func detachStatusObserver() {
    if let statusObserver {
      NotificationCenter.default.removeObserver(statusObserver)
      self.statusObserver = nil
    }
  }

  /// Debounced status emit. Avoids `loadAllFromPreferences` on every NE callback
  /// (that storms `ne_session queue` and trips EXC_RESOURCE under the debugger).
  private func scheduleEmitStatus(
    connection: NEVPNConnection? = nil,
    forceLoad: Bool = false
  ) {
    emitWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.emitStatusNow(connection: connection, forceLoad: forceLoad)
    }
    emitWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
  }

  private func emitStatusNow(connection: NEVPNConnection?, forceLoad: Bool) {
    currentStatusPayload(connection: connection, forceLoad: forceLoad) { [weak self] payload in
      guard let self, let sink = self.eventSink else { return }
      let status = payload["status"] as? String ?? ""
      let extensionStatus = payload["extension_status"] as? String ?? ""
      let key = "\(status)|\(extensionStatus)"
      if key == self.lastEmittedStatus {
        return
      }
      self.lastEmittedStatus = key
      sink(payload)
    }
  }

  // MARK: - Keys

  private static func ensurePublicKey() throws -> String {
    if let existing = try loadPrivateKeyData() {
      let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existing)
      return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    try storePrivateKeyData(privateKey.rawRepresentation)
    return privateKey.publicKey.rawRepresentation.base64EncodedString()
  }

  private static func keychainAccessGroup() -> String? {
    guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
          !prefix.isEmpty
    else { return nil }
    return prefix + "cz.tomaspetrik.petrikvpn"
  }

  private static func storePrivateKeyData(_ data: Data) throws {
    var base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
    if let group = keychainAccessGroup() {
      base[kSecAttrAccessGroup as String] = group
    }
    SecItemDelete(base as CFDictionary)
    var query = base
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: "VpnEngine", code: Int(status), userInfo: [
        NSLocalizedDescriptionKey: "Keychain store failed (\(status))",
      ])
    }
  }

  private static func loadPrivateKeyData() throws -> Data? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let group = keychainAccessGroup() {
      query[kSecAttrAccessGroup as String] = group
    }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw NSError(domain: "VpnEngine", code: Int(status), userInfo: [
        NSLocalizedDescriptionKey: "Keychain read failed (\(status))",
      ])
    }
    return data
  }

  // MARK: - VPN manager

  private func prepareVpn(completion: @escaping ([String: Any]) -> Void) {
    loadOrCreateManager { [weak self] manager, error in
      if let error {
        completion(["granted": false, "status": "error", "message": error.localizedDescription])
        return
      }
      guard let self, let manager else {
        completion(["granted": false, "status": "error", "message": "No VPN manager"])
        return
      }
      manager.isEnabled = true
      manager.saveToPreferences { saveError in
        if let saveError {
          completion([
            "granted": false,
            "status": "error",
            "message": saveError.localizedDescription,
          ])
          return
        }
        manager.loadFromPreferences { loadError in
          if let loadError {
            completion(["granted": false, "status": "error", "message": loadError.localizedDescription])
            return
          }
          self.cachedManager = manager
          self.attachStatusObserver(to: manager.connection)
          completion(["granted": true, "status": "ready", "message": "VPN configuration saved"])
        }
      }
    }
  }

  private func startTunnel(config: [String: Any], completion: @escaping ([String: Any]) -> Void) {
    do {
      try Self.storeTunnelConfig(config)
    } catch {
      completion(["ok": false, "status": "error", "message": error.localizedDescription])
      return
    }
    loadOrCreateManager { [weak self] manager, error in
      if let error {
        completion(["ok": false, "status": "error", "message": error.localizedDescription])
        return
      }
      guard let self, let manager else {
        completion(["ok": false, "status": "error", "message": "No VPN manager"])
        return
      }
      manager.isEnabled = true
      manager.saveToPreferences { saveError in
        if let saveError {
          completion(["ok": false, "status": "error", "message": saveError.localizedDescription])
          return
        }
        manager.loadFromPreferences { loadError in
          if let loadError {
            completion(["ok": false, "status": "error", "message": loadError.localizedDescription])
            return
          }
          self.cachedManager = manager
          self.attachStatusObserver(to: manager.connection)
          do {
            try manager.connection.startVPNTunnel(options: [
              "step": "wireguard" as NSString,
            ])
            completion([
              "ok": true,
              "status": Self.statusString(manager.connection.status),
              "message": "startVPNTunnel requested (WireGuardKit)",
            ])
          } catch {
            completion(["ok": false, "status": "error", "message": error.localizedDescription])
          }
        }
      }
    }
  }

  private static func storeTunnelConfig(_ config: [String: Any]) throws {
    guard JSONSerialization.isValidJSONObject(config) else {
      throw NSError(domain: "VpnEngine", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "tunnel config is not valid JSON",
      ])
    }
    let data = try JSONSerialization.data(withJSONObject: config, options: [])
    guard let defaults = UserDefaults(suiteName: appGroupId) else {
      throw NSError(domain: "VpnEngine", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "App Group UserDefaults unavailable",
      ])
    }
    defaults.set(data, forKey: "tunnel_config")
    defaults.synchronize()
  }

  private func stopTunnel(completion: @escaping ([String: Any]) -> Void) {
    let finish: (NETunnelProviderManager?) -> Void = { manager in
      guard let manager else {
        completion(["ok": true, "message": "No VPN manager to stop"])
        return
      }
      manager.connection.stopVPNTunnel()
      completion(["ok": true, "message": "stopVPNTunnel requested"])
    }

    if let cachedManager {
      finish(cachedManager)
      return
    }
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      if let error {
        completion(["ok": false, "message": error.localizedDescription])
        return
      }
      let manager = managers?.first
      self?.cachedManager = manager
      if let manager {
        self?.attachStatusObserver(to: manager.connection)
      }
      finish(manager)
    }
  }

  private func loadOrCreateManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    if let cachedManager {
      applyProtocol(to: cachedManager)
      completion(cachedManager, nil)
      return
    }
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      if let error {
        completion(nil, error)
        return
      }
      let manager = managers?.first ?? NETunnelProviderManager()
      self?.applyProtocol(to: manager)
      self?.cachedManager = manager
      completion(manager, nil)
    }
  }

  private func applyProtocol(to manager: NETunnelProviderManager) {
    let proto = NETunnelProviderProtocol()
    proto.providerBundleIdentifier = Self.providerBundleId
    proto.serverAddress = "vpn.radarcut.com"
    manager.protocolConfiguration = proto
    manager.localizedDescription = "PetrikVPN"
  }

  private func currentStatusPayload(
    connection: NEVPNConnection? = nil,
    forceLoad: Bool,
    completion: @escaping ([String: Any]) -> Void
  ) {
    let finish: (NETunnelProviderManager?, String) -> Void = { manager, vpnStatus in
      let defaults = UserDefaults(suiteName: Self.appGroupId)
      let extensionStatus = defaults?.string(forKey: "tunnel_status") ?? ""
      var payload: [String: Any] = [
        "status": vpnStatus,
        "extension_status": extensionStatus,
        "extension_log": Self.extensionLogLines(),
      ]
      Self.fetchRuntimeStats(from: manager) { stats in
        for (key, value) in stats {
          payload[key] = value
        }
        completion(payload)
      }
    }

    if let cachedManager {
      let status = connection.map { Self.statusString($0.status) }
        ?? Self.statusString(cachedManager.connection.status)
      finish(cachedManager, status)
      return
    }
    guard forceLoad else {
      finish(nil, "disconnected")
      return
    }
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
      if let manager = managers?.first {
        self?.cachedManager = manager
        self?.attachStatusObserver(to: manager.connection)
        finish(manager, Self.statusString(manager.connection.status))
      } else {
        finish(nil, "disconnected")
      }
    }
  }

  /// Asks PacketTunnel for WireGuard UAPI runtime config and parses peer counters.
  private static func fetchRuntimeStats(
    from manager: NETunnelProviderManager?,
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard let manager,
          manager.connection.status == .connected,
          let session = manager.connection as? NETunnelProviderSession
    else {
      completion([:])
      return
    }
    do {
      try session.sendProviderMessage(Data([0])) { data in
        guard let data, let text = String(data: data, encoding: .utf8) else {
          completion([:])
          return
        }
        completion(parseRuntimeConfig(text))
      }
    } catch {
      completion([:])
    }
  }

  private static func parseRuntimeConfig(_ text: String) -> [String: Any] {
    var rxBytes: Int64?
    var txBytes: Int64?
    var handshakeSec: Int64?
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard let eq = line.firstIndex(of: "=") else { continue }
      let key = String(line[..<eq])
      let value = String(line[line.index(after: eq)...])
      switch key {
      case "rx_bytes":
        rxBytes = Int64(value)
      case "tx_bytes":
        txBytes = Int64(value)
      case "last_handshake_time_sec":
        handshakeSec = Int64(value)
      default:
        break
      }
    }
    var out: [String: Any] = [:]
    if let rxBytes { out["rx_bytes"] = NSNumber(value: rxBytes) }
    if let txBytes { out["tx_bytes"] = NSNumber(value: txBytes) }
    if let handshakeSec, handshakeSec > 0 {
      out["last_handshake_sec"] = NSNumber(value: handshakeSec)
    }
    return out
  }

  private static func extensionLogLines() -> [String] {
    UserDefaults(suiteName: appGroupId)?.stringArray(forKey: "tunnel_log") ?? []
  }

  private static func statusString(_ status: NEVPNStatus) -> String {
    switch status {
    case .invalid: return "invalid"
    case .disconnected: return "disconnected"
    case .connecting: return "connecting"
    case .connected: return "connected"
    case .reasserting: return "reasserting"
    case .disconnecting: return "disconnecting"
    @unknown default: return "unknown"
    }
  }
}
