import Foundation
import Combine
import NetworkExtension
import WidgetKit
import os
#if os(iOS)
import UIKit
#else
import SystemConfiguration
#endif

import EasyTierShared
import TOMLKit

protocol NetworkExtensionManagerProtocol: ObservableObject {
    var status: NEVPNStatus { get }
    var connectedDate: Date? { get }
    var isLoading: Bool { get }
    var isAlwaysOnEnabled: Bool { get set }
    
    func load() async throws
    @MainActor
    func connect() async throws
    func disconnect() async
    func fetchRunningInfo(_ callback: @escaping ((NetworkStatus) -> Void))
    func fetchLastNetworkSettings(_ callback: @escaping ((TunnelNetworkSettingsSnapshot?) -> Void))
    func updateName(name: String, server: String) async
    func clearCoreLog() async throws
    func exportExtensionLogs() async throws -> URL
    @MainActor
    func setAlwaysOnEnabled(_ enabled: Bool) async throws
}

class NetworkExtensionManager: NetworkExtensionManagerProtocol {
    private static let logger = Logger(subsystem: APP_BUNDLE_ID, category: "NEManager")

    private struct ProviderMessageResponse: Codable {
        let ok: Bool
        let path: String?
        let error: String?
    }

    enum NEManagerError: LocalizedError {
        case providerUnavailable
        case invalidResponse
        case clearFailed(String)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .providerUnavailable:
                return "provider unavailable"
            case .invalidResponse:
                return "invalid response"
            case .clearFailed(let message):
                return message
            case .exportFailed(let message):
                return message
            }
        }
    }

    private var manager: NETunnelProviderManager?
    private var connection: NEVPNConnection?
    private var observer: Any?

    @Published var status: NEVPNStatus
    @Published var connectedDate: Date?
    @Published var isLoading = true
    @Published var isAlwaysOnEnabled = false
    
    init() {
        status = .invalid
    }

    private func registerObserver() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let manager = manager {
            observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NEVPNStatusDidChange,
                object: manager.connection,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let connection = notification.object as? NEVPNConnection
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    self.connection = connection
                    self.status = self.connection?.status ?? .invalid
                    self.connectedDate = self.connection?.connectedDate
                    if self.status == .invalid {
                        self.manager = nil
                    }
                    
                    // Sync VPN connection status to App Group for Control Widget
                    self.syncWidgetState()
                }
            }
        }
    }
    
    // Notify Control Widget to refresh its state
    private func syncWidgetState() {
        if #available(iOS 18.0, macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: "\(APP_BUNDLE_ID).control")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "\(APP_BUNDLE_ID).widget")
    }
    
    private func reset() {
        manager = nil
        connection = nil
        status = .invalid
        connectedDate = nil
        isAlwaysOnEnabled = false
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        isLoading = false
    }
    
    private func setManager(manager: NETunnelProviderManager?) {
        self.manager = manager
        connection = manager?.connection
        status = manager?.connection.status ?? .invalid
        connectedDate = manager?.connection.connectedDate
        isAlwaysOnEnabled = manager?.isOnDemandEnabled ?? false
        registerObserver()
    }
    
    static func install() async throws -> NETunnelProviderManager {
        Self.logger.info("install()")
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "EasyTier"
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "\(APP_BUNDLE_ID).tunnel"
        tunnelProtocol.serverAddress = "localhost"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            return manager
        } catch {
            Self.logger.error("install() failed: \(String(describing: error))")
            throw error
        }
    }

    func load() async throws {
        Self.logger.info("load()")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = managers.first
            for m in managers {
                if m != manager {
                    try? await m.removeFromPreferences()
                    Self.logger.info("load() removed unnecessary profile")
                }
            }
            setManager(manager: manager)
            isLoading = false
        } catch {
            Self.logger.error("load() failed: \(String(describing: error))")
            reset()
            throw error
        }
    }
    
    static func generateOptions(_ profile: inout NetworkProfile) throws -> EasyTierOptions {
        try profile.prepareForUse()
        var options = EasyTierOptions()
        var config = profile.toConfig()
        if config.hostname == nil && UserDefaults.standard.bool(forKey: "useRealDeviceNameAsDefault") {
#if os(iOS)
            config.hostname = UIDevice.current.name
#else
            config.hostname = SCDynamicStoreCopyComputerName(nil, nil) as String?
#endif
        }

        let encoded: String
        do {
            encoded = try TOMLEncoder().encode(config).string ?? ""
        } catch {
            Self.logger.error("generateOptions() generate config failed: \(String(describing: error))")
            throw error
        }
        options.config = encoded
        if let ipv4 = config.ipv4 {
            options.ipv4 = ipv4
        }
        if let ipv6 = config.ipv6 {
            options.ipv6 = ipv6
        }
        if let mtu = config.flags?.mtu {
            options.mtu = mtu
        } else {
            options.mtu = config.flags?.enableEncryption ?? true ? 1360 : 1380
        }
        if let routes = config.routes {
            options.routes = routes
        }
        options.exitNodes = config.exitNodes
        if let logLevel = UserDefaults.standard.string(forKey: "logLevel"),
           let logLevel = LogLevel.init(rawValue: logLevel) {
            options.logLevel = logLevel
        }
        if profile.enableMagicDNS {
            options.magicDNS = true
        }
        if profile.enableOverrideDNS {
            options.dns = profile.overrideDNS.compactMap { $0.text.isEmpty ? nil : $0.text }
        }
        
        return options
    }
    
    static func saveOptions(_ options: EasyTierOptions) {
        // Save config to App Group for Widget use
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        if let configData = try? JSONEncoder().encode(options) {
            logger.debug("save options: \(configData.string ?? "nil")")
            defaults?.set(configData, forKey: "VPNConfig")
            defaults?.synchronize()
        }
    }
    
    func connect() async throws {
        guard ![.connecting, .connected, .disconnecting, .reasserting].contains(status) else {
            Self.logger.warning("connect() failed: in \(String(describing: self.status)) status")
            return
        }
        guard !isLoading else {
            Self.logger.warning("connect() failed: not loaded")
            return
        }
        if status == .invalid {
            _ = try await NetworkExtensionManager.install()
            try await load()
        }
        guard let manager else {
            Self.logger.error("connect() failed: manager is nil")
            return
        }

        do {
            try await connectWithManager(manager, logger: Self.logger)
        } catch {
            Self.logger.error("connect() start vpn tunnel failed: \(String(describing: error))")
            throw error
        }
        Self.logger.info("connect() started")
        // Immediately sync widget state after initiating connection
        syncWidgetState()
    }
    
    func disconnect() async {
        guard let manager else {
            Self.logger.error("disconnect() failed: manager is nil")
            return
        }
        let connection = manager.connection
        guard [.connecting, .connected, .reasserting, .disconnecting].contains(connection.status) else {
            return
        }

        connection.stopVPNTunnel()
        // Immediately sync widget state after initiating disconnection
        syncWidgetState()

        while [.connecting, .connected, .reasserting, .disconnecting].contains(connection.status) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    
    func updateName(name: String, server: String) async {
        guard let manager else { return }
        manager.localizedDescription = name
        manager.protocolConfiguration?.serverAddress = server
        try? await manager.saveToPreferences()
    }
    
    func fetchRunningInfo(_ callback: @escaping ((NetworkStatus) -> Void)) {
        guard let manager else { return }
        guard let session = manager.connection as? NETunnelProviderSession,
              session.status != .invalid else { return }
        do {
            let message = ProviderCommand.runningInfo.rawValue.data(using: .utf8) ?? Data()
            try session.sendProviderMessage(message) { data in
                guard let data else { return }
                Self.logger.debug("fetchRunningInfo() received data: \(String(data: data, encoding: .utf8) ?? data.description)")
                let info: NetworkStatus
                do {
                    info = try JSONDecoder().decode(NetworkStatus.self, from: data)
                } catch {
                    Self.logger.error("fetchRunningInfo() json deserialize failed: \(String(describing: error))")
                    return
                }
                callback(info)
            }
        } catch {
            Self.logger.error("fetchRunningInfo() failed: \(String(describing: error))")
        }
    }

    func fetchLastNetworkSettings(_ callback: @escaping ((TunnelNetworkSettingsSnapshot?) -> Void)) {
        guard let manager else {
            callback(nil)
            return
        }
        guard let session = manager.connection as? NETunnelProviderSession,
              session.status != .invalid else {
            callback(nil)
            return
        }
        do {
            let message = ProviderCommand.lastNetworkSettings.rawValue.data(using: .utf8) ?? Data()
            try session.sendProviderMessage(message) { data in
                guard let data else {
                    callback(nil)
                    return
                }
                do {
                    let settings = try JSONDecoder().decode(TunnelNetworkSettingsSnapshot.self, from: data)
                    callback(settings)
                } catch {
                    Self.logger.error("fetchLastNetworkSettings() json deserialize failed: \(String(describing: error))")
                    callback(nil)
                }
            }
        } catch {
            Self.logger.error("fetchLastNetworkSettings() failed: \(String(describing: error))")
            callback(nil)
        }
    }

    func exportExtensionLogs() async throws -> URL {
        guard let manager,
              let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected else {
            throw NEManagerError.providerUnavailable
        }
        guard let message = ProviderCommand.exportOSLog.rawValue.data(using: .utf8) else {
            throw NEManagerError.invalidResponse
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { data in
                    guard let data else {
                        continuation.resume(throwing: NEManagerError.invalidResponse)
                        return
                    }
                    do {
                        let response = try JSONDecoder().decode(ProviderMessageResponse.self, from: data)
                        if response.ok, let path = response.path {
                            continuation.resume(returning: URL(fileURLWithPath: path))
                        } else {
                            continuation.resume(throwing: NEManagerError.exportFailed(response.error ?? "export failed"))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func clearCoreLog() async throws {
        guard let manager,
              let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected else {
            throw NEManagerError.providerUnavailable
        }
        guard let message = ProviderCommand.clearLog.rawValue.data(using: .utf8) else {
            throw NEManagerError.invalidResponse
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { data in
                    guard let data else {
                        continuation.resume(throwing: NEManagerError.invalidResponse)
                        return
                    }
                    do {
                        let response = try JSONDecoder().decode(ProviderMessageResponse.self, from: data)
                        if response.ok {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: NEManagerError.clearFailed(response.error ?? "clear failed"))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @MainActor
    func setAlwaysOnEnabled(_ enabled: Bool) async throws {
        if status == .invalid || manager == nil {
            _ = try await NetworkExtensionManager.install()
            try await load()
        }
        guard let manager else {
            throw NEManagerError.providerUnavailable
        }
        manager.isEnabled = true
        if enabled {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
        } else {
            manager.onDemandRules = nil
        }
        manager.isOnDemandEnabled = enabled
        try await manager.saveToPreferences()
        isAlwaysOnEnabled = enabled
    }
}

class MockNEManager: NetworkExtensionManagerProtocol {
    @Published var status: NEVPNStatus = .disconnected
    @Published var connectedDate: Date? = nil
    @Published var isLoading: Bool = true
    @Published var isAlwaysOnEnabled: Bool = false

    // Simulate a successful load
    func load() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        isLoading = false
        status = .disconnected
    }

    // Simulate connecting
    func connect() async throws {
        status = .connecting
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        status = .connected
        connectedDate = Date()
    }

    func disconnect() async {
        status = .disconnecting
        try? await Task.sleep(nanoseconds: 500_000_000)
        status = .disconnected
        connectedDate = nil
    }

    func updateName(name: String, server: String) async { }

    func clearCoreLog() async throws { }

    func fetchRunningInfo(_ callback: @escaping ((NetworkStatus) -> Void)) {
        callback(MockNEManager.dummyRunningInfo)
    }

    func fetchLastNetworkSettings(_ callback: @escaping ((TunnelNetworkSettingsSnapshot?) -> Void)) {
        callback(nil)
    }

    func exportExtensionLogs() async throws -> URL {
        throw NetworkExtensionManager.NEManagerError.providerUnavailable
    }

    @MainActor
    func setAlwaysOnEnabled(_ enabled: Bool) async throws {
        isAlwaysOnEnabled = enabled
    }
    
    static var dummyRunningInfo: NetworkStatus {
        let id = UUID().uuidString

        let myNodeInfo = NetworkStatus.MyNodeInfo(
            virtualIPv4: NetworkStatus.IPv4CIDR(address: NetworkStatus.IPv4Addr("10.144.144.10")!, networkLength: 24),
            hostname: "My iPhone",
            version: "0.10.1",
            ips: .init(
                publicIPv4: NetworkStatus.IPv4Addr("8.8.8.8"),
                interfaceIPv4s: [NetworkStatus.IPv4Addr("192.168.1.100")!],
                publicIPv6: nil as NetworkStatus.IPv6Addr?,
                interfaceIPv6s: []
            ),
            stunInfo: NetworkStatus.STUNInfo(udpNATType: .symmetricEasyInc, tcpNATType: .fullCone, lastUpdateTime: Date().timeIntervalSince1970 - 10),
            listeners: [NetworkStatus.Url(url: "tcp://0.0.0.0:11010"), NetworkStatus.Url(url: "udp://0.0.0.0:11010")],
            vpnPortalCfg: "[Interface]\nPrivateKey = [REDACTED]\nAddress = 10.144.144.1/24\nListenPort = 22022\n\n[Peer]\nPublicKey = [REDACTED]\nAllowedIPs = 10.144.144.2/32",
            peerID: 114514,
        )
        
        let peerRoute1 = NetworkStatus.Route(peerId: 123, ipv4Addr: .init(address: .init("10.144.144.10")!, networkLength: 24), nextHopPeerId: 123, cost: 1, pathLatency: 8, proxyCIDRs: [], hostname: "peer-1-ubuntu", stunInfo: NetworkStatus.STUNInfo(udpNATType: .fullCone, tcpNATType: .symmetric, lastUpdateTime: Date().timeIntervalSince1970 - 20), instId: id, version: "0.10.0")
        let peerRoute2 = NetworkStatus.Route(peerId: 456, ipv6Addr: .init(address: .init("fd00::1")!, networkLength: 64), nextHopPeerId: 789, cost: 2, pathLatency: 8, proxyCIDRs: [], hostname: "peer-2-relayed-windows", stunInfo: NetworkStatus.STUNInfo(udpNATType: .symmetric, tcpNATType: .restricted, lastUpdateTime: Date().timeIntervalSince1970 - 30), instId: id, version: "0.9.8")
        let peerRoute3 = NetworkStatus.Route(peerId: 256, ipv4Addr: .init(address: .init("10.144.144.14")!, networkLength: 32), ipv6Addr: .init(address: .init("fd00::2")!, networkLength: 48), nextHopPeerId: 789, cost: 1, pathLatency: 8, proxyCIDRs: [], hostname: "peer-3-relayed-verylong-verylong-verylong-verylong", stunInfo: NetworkStatus.STUNInfo(udpNATType: .openInternet, tcpNATType: .openInternet, lastUpdateTime: Date().timeIntervalSince1970 - 20), instId: id, version: "1.9.8")
        
        let conn1 = NetworkStatus.PeerConnInfo(connId: "conn-1", myPeerId: 0, isClient: true, peerId: 123, features: [], tunnel: NetworkStatus.TunnelInfo(tunnelType: "tcp", localAddr: NetworkStatus.Url(url:"192.168.1.100:55555"), remoteAddr: NetworkStatus.Url(url:"1.2.3.4:11010")), stats: NetworkStatus.PeerConnStats(rxBytes: 102400, txBytes: 204800, rxPackets: 100, txPackets: 200, latencyUs: 180000), lossRate: 0.01)
        let conn2 = NetworkStatus.PeerConnInfo(connId: "conn-2", myPeerId: 0, isClient: true, peerId: 256, features: [], tunnel: NetworkStatus.TunnelInfo(tunnelType: "udp", localAddr: NetworkStatus.Url(url:"192.168.1.100:55555"), remoteAddr: NetworkStatus.Url(url:"1.2.3.4:11010")), stats: NetworkStatus.PeerConnStats(rxBytes: 102400, txBytes: 204800, rxPackets: 100, txPackets: 200, latencyUs: 5000), lossRate: 0.01)

        let peer1 = NetworkStatus.PeerInfo(peerId: 123, conns: [conn1])
        let peer2 = NetworkStatus.PeerInfo(peerId: 256, conns: [conn1, conn2])
        
        return NetworkStatus(
            devName: "utun10",
            myNodeInfo: myNodeInfo,
            events: [
                "{\"time\":\"2026-01-04T14:31:55.012731+08:00\",\"event\":{\"PeerAdded\":4129348860}}",
                "{\"time\":\"2026-01-04T14:31:55.012711+08:00\",\"event\":{\"PeerConnAdded\":{\"conn_id\":\"11fdb3dd-9f35-4ab3-b255-133f1c7dad38\",\"my_peer_id\":3967454550,\"peer_id\":4129348860,\"features\":[],\"tunnel\":{\"tunnel_type\":\"tcp\",\"local_addr\":{\"url\":\"tcp://192.168.31.19:58758\"},\"remote_addr\":{\"url\":\"tcp://public.easytier.top:11010\"}},\"stats\":{\"rx_bytes\":91,\"tx_bytes\":93,\"rx_packets\":1,\"tx_packets\":1,\"latency_us\":0},\"loss_rate\":0.0,\"is_client\":true,\"network_name\":\"sijie-easytier-public\",\"is_closed\":false}}}",
                "{\"time\":\"2026-01-04T14:31:54.872468+08:00\",\"event\":{\"ListenerAdded\":\"wg://0.0.0.0:11011\"}}",
                "{\"time\":\"2026-01-04T14:31:54.866061+08:00\",\"event\":{\"Connecting\":\"tcp://public.easytier.top:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.869940+08:00\",\"event\":{\"ListenerAdded\":\"wg://[::]:11011\"}}",
                "{\"time\":\"2026-01-04T14:31:53.869581+08:00\",\"event\":{\"ListenerAddFailed\":[\"wg://0.0.0.0:11011\",\"error: IOError(Os { code: 48, kind: AddrInUse, message: \\\"Address already in use\\\" }), retry listen later...\"]}}",
                "{\"time\":\"2026-01-04T14:31:53.868529+08:00\",\"event\":{\"ListenerAdded\":\"udp://[::]:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.868207+08:00\",\"event\":{\"ListenerAdded\":\"udp://0.0.0.0:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.865719+08:00\",\"event\":{\"ListenerAdded\":\"tcp://0.0.0.0:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.865237+08:00\",\"event\":{\"ListenerAdded\":\"tcp://[::]:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.863019+08:00\",\"event\":{\"ListenerAdded\":\"ring://360e18ba-81de-4bd0-b32a-07958ee9c917\"}}"
            ],
            routes: [peerRoute1, peerRoute2, peerRoute3],
            peers: [peer1, peer2],
            peerRoutePairs: [
                NetworkStatus.PeerRoutePair(route: peerRoute1, peer: peer1),
                NetworkStatus.PeerRoutePair(route: peerRoute2, peer: nil),
                NetworkStatus.PeerRoutePair(route: peerRoute3, peer: peer2)
            ],
            running: true,
            errorMsg: nil
        )
    }
}
