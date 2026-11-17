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

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    statusChannel = FlutterEventChannel(name: Self.statusChannelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler(handle)
    statusChannel.setStreamHandler(self)
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.emitStatus()
    }
  }

  deinit {
    if let statusObserver {
      NotificationCenter.default.removeObserver(statusObserver)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitStatus()
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
      Self.prepareVpn { payload in result(payload) }
    case "startTunnel":
      Self.startTunnel { payload in result(payload) }
    case "stopTunnel":
      Self.stopTunnel { payload in result(payload) }
    case "getStatus":
      Self.currentStatusPayload { payload in result(payload) }
    case "extensionLog":
      result(["lines": Self.extensionLogLines()])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func emitStatus() {
    Self.currentStatusPayload { [weak self] payload in
      self?.eventSink?(payload)
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

  private static func prepareVpn(completion: @escaping ([String: Any]) -> Void) {
    loadOrCreateManager { manager, error in
      if let error {
        completion(["granted": false, "status": "error", "message": error.localizedDescription])
        return
      }
      guard let manager else {
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
          completion(["granted": true, "status": "ready", "message": "VPN configuration saved"])
        }
      }
    }
  }

  private static func startTunnel(completion: @escaping ([String: Any]) -> Void) {
    loadOrCreateManager { manager, error in
      if let error {
        completion(["ok": false, "status": "error", "message": error.localizedDescription])
        return
      }
      guard let manager else {
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
          do {
            try manager.connection.startVPNTunnel(options: [
              "step": "skeleton" as NSString,
            ])
            completion([
              "ok": true,
              "status": statusString(manager.connection.status),
              "message": "startVPNTunnel requested",
            ])
          } catch {
            completion(["ok": false, "status": "error", "message": error.localizedDescription])
          }
        }
      }
    }
  }

  private static func stopTunnel(completion: @escaping ([String: Any]) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(["ok": false, "message": error.localizedDescription])
        return
      }
      guard let manager = managers?.first else {
        completion(["ok": true, "message": "No VPN manager to stop"])
        return
      }
      manager.connection.stopVPNTunnel()
      completion(["ok": true, "message": "stopVPNTunnel requested"])
    }
  }

  private static func loadOrCreateManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(nil, error)
        return
      }
      let manager = managers?.first ?? NETunnelProviderManager()
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = providerBundleId
      proto.serverAddress = "vpn.radarcut.com"
      manager.protocolConfiguration = proto
      manager.localizedDescription = "PetrikVPN"
      completion(manager, nil)
    }
  }

  private static func currentStatusPayload(completion: @escaping ([String: Any]) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      let vpnStatus: String
      if let manager = managers?.first {
        vpnStatus = statusString(manager.connection.status)
      } else {
        vpnStatus = "disconnected"
      }
      let defaults = UserDefaults(suiteName: appGroupId)
      let extensionStatus = defaults?.string(forKey: "tunnel_status") ?? ""
      completion([
        "status": vpnStatus,
        "extension_status": extensionStatus,
        "extension_log": extensionLogLines(),
      ])
    }
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
