import Foundation
import SwiftData

enum NetworkingMethod: Int, Codable, CaseIterable, Identifiable {
    var id: Self { self }
    case publicServer = 0
    case manual = 1
    case standalone = 2
}

struct PortForwardConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var bind_ip: String = ""
    var bind_port: Int = 0
    var dst_ip: String = ""
    var dst_port: Int = 0
    var proto: String = "tcp"
    
    private enum CodingKeys: String, CodingKey {
        case bind_ip, bind_port, dst_ip, dst_port, proto
    }
}

@Model
final class ProfileSummary {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade) var profile: NetworkProfile
    
    init(name: String, context: ModelContext) {
        let id = UUID()
        self.id = id
        self.name = name
        self.createdAt = Date()
        let profile = NetworkProfile(id: id)
        self.profile = profile
        context.insert(profile)
    }
}

@Model
final class NetworkProfile {
    @Attribute(.unique) var id: UUID

    var dhcp: Bool = true
    var virtual_ipv4: String = "10.144.144.0"
    var network_length: Int = 24
    var hostname: String? = nil
    var network_name: String = "default"
    var network_secret: String = ""

    var networking_method: NetworkingMethod = NetworkingMethod.publicServer

    var public_server_url: String = "https://api.example.com"
    var peer_urls: [String] = []

    var proxy_cidrs: [String] = []

    var enable_vpn_portal: Bool = false
    var vpn_portal_listen_port: Int = 22022
    var vpn_portal_client_network_addr: String = "10.144.144.0"
    var vpn_portal_client_network_len: Int = 24

    var advanced_settings: Bool = false

    var listener_urls: [String] = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010", "wg://0.0.0.0:11011"]
    var latency_first: Bool = false

    var dev_name: String = "utun10"

    var use_smoltcp: Bool = false
    var disable_ipv6: Bool = false
    var enable_kcp_proxy: Bool = false
    var disable_kcp_input: Bool = false
    var enable_quic_proxy: Bool = false
    var disable_quic_input: Bool = false
    var disable_p2p: Bool = false
    var p2p_only: Bool = false
    var bind_device: Bool = false
    var no_tun: Bool = false
    var enable_exit_node: Bool = false
    var relay_all_peer_rpc: Bool = false
    var multi_thread: Bool = false
    var proxy_forward_by_system: Bool = false
    var disable_encryption: Bool = false
    var disable_udp_hole_punching: Bool = false
    var disable_sym_hole_punching: Bool = false

    var enable_relay_network_whitelist: Bool = false
    var relay_network_whitelist: [String] = []

    var enable_manual_routes: Bool = false
    var routes: [String] = []
    
    var port_forwards: [PortForwardConfig] = []

    var exit_nodes: [String] = []

    var enable_socks5: Bool = false
    var socks5_port: Int = 1080

    var mtu: Int? = nil
    var mapped_listeners: [String] = []

    var enable_magic_dns: Bool = false
    var enable_private_mode: Bool = false

    init(id: UUID) {
        self.id = id
    }
}
