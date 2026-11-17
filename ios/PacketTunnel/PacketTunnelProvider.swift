import Foundation
import NetworkExtension

/// Step 3 skeleton: starts a VPN session without WireGuard/wstunnel routing.
/// Step 4/5 will configure real tunnel settings and transport.
class PacketTunnelProvider: NEPacketTunnelProvider {
  private let appGroupId = "group.cz.tomaspetrik.petrikvpn"

  override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    appendLog("PacketTunnel startTunnel (skeleton)")
    writeStatus("starting_tunnel")

    // Minimal settings: VPN appears connected but does not claim 0.0.0.0/0 yet.
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    settings.mtu = 1280

    setTunnelNetworkSettings(settings) { [weak self] error in
      if let error {
        self?.appendLog("setTunnelNetworkSettings failed: \(error.localizedDescription)")
        self?.writeStatus("error")
        completionHandler(error)
        return
      }
      self?.appendLog("PacketTunnel skeleton connected (no WireGuard yet)")
      self?.writeStatus("skeleton_connected")
      completionHandler(nil)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    appendLog("PacketTunnel stopTunnel reason=\(reason.rawValue)")
    writeStatus("disconnected")
    completionHandler()
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

  private func defaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
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
