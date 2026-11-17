import CryptoKit
import Flutter
import Foundation
import NetworkExtension
import Security
import UIKit

/// MethodChannel `vpn_engine`: getPublicKey, prepare (step 2).
final class VpnEngineChannel: NSObject {
  static let channelName = "vpn_engine"
  static let providerBundleId = "cz.tomaspetrik.petrikvpn.PacketTunnel"
  static let keychainService = "cz.tomaspetrik.petrikvpn.wireguard"
  static let keychainAccount = "private_key"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPublicKey":
      do {
        let publicKey = try Self.ensurePublicKey()
        result(["public_key": publicKey, "created": true])
      } catch {
        result(
          FlutterError(
            code: "key_error",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    case "prepare":
      Self.prepareVpn { payload in
        result(payload)
      }
    default:
      result(FlutterMethodNotImplemented)
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
    else {
      return nil
    }
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
      throw NSError(
        domain: "VpnEngine",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Keychain store failed (\(status))"]
      )
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
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = item as? Data else {
      throw NSError(
        domain: "VpnEngine",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Keychain read failed (\(status))"]
      )
    }
    return data
  }

  // MARK: - Prepare VPN permission

  private static func prepareVpn(completion: @escaping ([String: Any]) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion([
          "granted": false,
          "status": "error",
          "message": error.localizedDescription,
        ])
        return
      }

      let manager = managers?.first ?? NETunnelProviderManager()
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = providerBundleId
      proto.serverAddress = "vpn.radarcut.com"
      manager.protocolConfiguration = proto
      manager.localizedDescription = "PetrikVPN"
      manager.isEnabled = true

      manager.saveToPreferences { saveError in
        if let saveError {
          let ns = saveError as NSError
          // Extension missing / invalid config until PacketTunnel target exists.
          let needsExtension =
            ns.domain == NEVPNErrorDomain
            || ns.localizedDescription.lowercased().contains("permission")
            || ns.localizedDescription.lowercased().contains("configuration")
            || ns.localizedDescription.lowercased().contains("plugin")
          completion([
            "granted": false,
            "status": needsExtension ? "needs_extension" : "error",
            "message": saveError.localizedDescription,
          ])
          return
        }

        manager.loadFromPreferences { loadError in
          if let loadError {
            completion([
              "granted": false,
              "status": "error",
              "message": loadError.localizedDescription,
            ])
            return
          }
          completion([
            "granted": true,
            "status": "ready",
            "message": "VPN configuration saved",
          ])
        }
      }
    }
  }
}
