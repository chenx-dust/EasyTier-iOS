import SwiftUI

struct NetworkEditView: View {
    @Binding var profile: NetworkProfile
    @State var sel = 0
    @State private var isShowingCIDRManagement = false
    @State private var useCIDR = false // 这里的状态是持久的
    
    var body: some View {
        Form {
            basicSettings

            NavigationLink("Advanced Settings") {
                advancedSettings
            }

            NavigationLink("Port Forwards") {
                portForwardsSettings
            }
        }
        .sheet(isPresented: $isShowingCIDRManagement) {
            CIDRManagementView(useCIDR: $useCIDR, proxyCIDRs: $profile.proxy_cidrs)
        }
    }


    private var basicSettings: some View {
        Group {
            Section("Virtual IPv4") {
                Toggle("DHCP", isOn: $profile.dhcp)

                if !profile.dhcp {
                    HStack {
                        TextField(
                            "IPv4 Address",
                            text: $profile.virtual_ipv4
                        )
                        Text("/")
                        TextField(
                            "Length",
                            value: $profile.network_length,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50)
                        .keyboardType(.numberPad)
                    }
                }
            }

            Section("Network") {
                LabeledContent("Name") {
                    TextField("easytier", text: $profile.network_name)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Secret") {
                    SecureField(
                        "Empty",
                        text: $profile.network_secret
                    )
                    .multilineTextAlignment(.trailing)
                }

                Picker(
                    "Networking Method",
                    selection: $profile.networking_method
                ) {
                    ForEach(NetworkingMethod.allCases) {
                        method in
                        Text(verbatim: "\(method)".capitalized).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch profile.networking_method {
                case .publicServer:
                    LabeledContent("Server") {
                        Text(profile.public_server_url)
                            .multilineTextAlignment(.trailing)
                    }
                case .manual:
                    // For simplicity, using a TextField for comma-separated values.
                    // A more advanced implementation would use a token field.
                    VStack(alignment: .leading) {
                        Text("Peer URLs")
                        TextEditor(
                            text: Binding(
                                get: {
                                    profile.peer_urls.joined(
                                        separator: "\n"
                                    )
                                },
                                set: {
                                    profile.peer_urls = $0.split(
                                        whereSeparator: \.isNewline
                                    ).map(String.init)
                                }
                            )
                        )
                        .frame(minHeight: 100)
                        .border(Color.gray.opacity(0.2), width: 1)
                        .cornerRadius(5)
                    }
                case .standalone:
                    EmptyView()
                }
                
            }
        }
    }

    fileprivate var advancedSettings: some View {
        Form {
            Section("General") {
                LabeledContent("Hostname") {
                    TextField("Default", text: $profile.hostname.bound)
                        .multilineTextAlignment(.trailing)
                }

                Toggle(
                    "Enable VPN Portal",
                    isOn: $profile.enable_vpn_portal
                )
                if profile.enable_vpn_portal {
                    HStack {
                        TextField(
                            "Client Network Address",
                            text: $profile
                                .vpn_portal_client_network_addr
                        )
                        Text("/")
                        TextField(
                            "Length",
                            value: $profile
                                .vpn_portal_client_network_len,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50)
                    }
                    TextField(
                        "Listen Port",
                        value: $profile.vpn_portal_listen_port,
                        formatter: NumberFormatter()
                    )
                }

                MultiLineTextField(
                    title: "Listener URLs",
                    items: $profile.listener_urls
                )

                LabeledContent("Device Name") {
                    TextField("Default", text: $profile.dev_name)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("MTU")
                    TextField(
                        "MTU",
                        value: $profile.mtu.bound,
                        formatter: NumberFormatter()
                    )
                    .help(
                        "Default: 1380 (encrypted) or 1360 (unencrypted). Range: 400-1380."
                    )
                }

                Toggle(
                    "Enable Relay Network Whitelist",
                    isOn: $profile.enable_relay_network_whitelist
                )
                if profile.enable_relay_network_whitelist {
                    MultiLineTextField(
                        title: "Relay Network Whitelist",
                        items: $profile.relay_network_whitelist
                    )
                }

                Toggle(
                    "Enable Manual Routes",
                    isOn: $profile.enable_manual_routes
                )
                if profile.enable_manual_routes {
                    MultiLineTextField(
                        title: "Manual Routes",
                        items: $profile.routes
                    )
                }

                Toggle(
                    "Enable SOCKS5 Server",
                    isOn: $profile.enable_socks5
                )
                if profile.enable_socks5 {
                    TextField(
                        "SOCKS5 Port",
                        value: $profile.socks5_port,
                        formatter: NumberFormatter()
                    )
                }

                MultiLineTextField(
                    title: "Exit Nodes",
                    items: $profile.exit_nodes
                )
                MultiLineTextField(
                    title: "Mapped Listeners",
                    items: $profile.mapped_listeners
                )
            }
            
            Section("Routing") {
                Button(action: {
                    useCIDR = !profile.proxy_cidrs.isEmpty
                    isShowingCIDRManagement = true
                }) {
                    LabeledContent("Proxy CIDRs") {
                        Text("\(profile.proxy_cidrs.count) items")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Feature") {
                ForEach(NetworkProfile.boolFlags) { flag in
                    Toggle(isOn: binding($profile, to: flag.keyPath)) {
                        Text(flag.label)
                        if let help = flag.help {
                            Text(help)
                        }
                    }
                }
            }
        }
        .navigationTitle("Advanced Settings")
    }

    fileprivate var portForwardsSettings: some View {
        Form {
            ForEach($profile.port_forwards) { $forward in
                VStack {
                    HStack {
                        Picker("", selection: $forward.proto) {
                            Text("TCP").tag("tcp")
                            Text("UDP").tag("udp")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)

                        Spacer()

                        Button(action: {
                            profile.port_forwards.removeAll {
                                $0.id == forward.id
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        TextField("Bind IP", text: $forward.bind_ip)
                        Text(":")
                        TextField(
                            "Port",
                            value: $forward.bind_port,
                            formatter: NumberFormatter()
                        ).frame(width: 60)
                    }
                    HStack {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.secondary)
                        Text("Forward to").foregroundColor(.secondary)
                    }
                    HStack {
                        TextField("Destination IP", text: $forward.dst_ip)
                        Text(":")
                        TextField(
                            "Port",
                            value: $forward.dst_port,
                            formatter: NumberFormatter()
                        ).frame(width: 60)
                    }
                }
                .padding(.vertical, 5)
            }

            Button(
                "Add Port Forward",
                systemImage: "plus",
                action: {
                    profile.port_forwards.append(PortForwardConfig())
                }
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Port Forwards")
    }
}

// MARK: - Helper Views and Extensions

private struct MultiLineTextField: View {
    let title: String
    @Binding var items: [String]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            TextEditor(
                text: Binding(
                    get: { items.joined(separator: "\n") },
                    set: {
                        items = $0.split(whereSeparator: \.isNewline).map(
                            String.init
                        )
                    }
                )
            )
            .frame(minHeight: 80)
            .font(.system(.body, design: .monospaced))
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(
                    Color.gray.opacity(0.5)
                )
            )
        }
    }
}

extension Optional where Wrapped == String {
    fileprivate var bound: String {
        get { self ?? "" }
        set { self = newValue.isEmpty ? nil : newValue }
    }
}

extension Optional where Wrapped == Int {
    fileprivate var bound: Int {
        get { self ?? 0 }
        set { self = newValue }
    }
}

private func binding<Root, Value>(
    _ root: Binding<Root>,
    to keyPath: WritableKeyPath<Root, Value>
) -> Binding<Value> {
    Binding<Value>(
        get: { root.wrappedValue[keyPath: keyPath] },
        set: { root.wrappedValue[keyPath: keyPath] = $0 }
    )
}

private struct BoolFlag: Identifiable {
    let id = UUID()
    let keyPath: WritableKeyPath<NetworkProfile, Bool>
    let label: String
    let help: String?
}

extension NetworkProfile {
    fileprivate static let boolFlags: [BoolFlag] = [
        .init(
            keyPath: \.latency_first,
            label: "Latency-First Mode",
            help:
                "Ignore hop count and select the path with the lowest total latency."
        ),
        .init(
            keyPath: \.use_smoltcp,
            label: "Use User-Space Protocol Stack",
            help:
                "Use a user-space TCP/IP stack to avoid issues with OS firewalls."
        ),
        .init(
            keyPath: \.disable_ipv6,
            label: "Disable IPv6",
            help: "Disable IPv6 functionality for this node."
        ),
        .init(
            keyPath: \.enable_kcp_proxy,
            label: "Enable KCP Proxy",
            help: "Convert TCP traffic to KCP to reduce latency."
        ),
        .init(
            keyPath: \.disable_kcp_input,
            label: "Disable KCP Input",
            help: "Disable inbound KCP traffic."
        ),
        .init(
            keyPath: \.enable_quic_proxy,
            label: "Enable QUIC Proxy",
            help: "Convert TCP traffic to QUIC to reduce latency."
        ),
        .init(
            keyPath: \.disable_quic_input,
            label: "Disable QUIC Input",
            help: "Disable inbound QUIC traffic."
        ),
        .init(
            keyPath: \.disable_p2p,
            label: "Disable P2P",
            help: "Route all traffic through a manually specified relay server."
        ),
        .init(
            keyPath: \.p2p_only,
            label: "P2P Only",
            help:
                "Only communicate with peers that have established P2P connections."
        ),
        .init(
            keyPath: \.bind_device,
            label: "Bind to Physical Device Only",
            help: "Use only the physical network interface."
        ),
        .init(
            keyPath: \.no_tun,
            label: "No TUN Mode",
            help:
                "Do not use a TUN interface. This node will be accessible but cannot initiate connections to others without SOCKS5."
        ),
        .init(
            keyPath: \.enable_exit_node,
            label: "Enable Exit Node",
            help: "Allow this node to be an exit node."
        ),
        .init(
            keyPath: \.relay_all_peer_rpc,
            label: "Relay All Peer RPC",
            help:
                "Relay all peer RPC packets, even for peers not in the whitelist."
        ),
        .init(
            keyPath: \.multi_thread,
            label: "Multi-Threaded Runtime",
            help: "Use a multi-thread runtime for performance."
        ),
        .init(
            keyPath: \.proxy_forward_by_system,
            label: "System Forwarding for Proxy",
            help: "Forward packets to proxy networks via the system kernel."
        ),
        .init(
            keyPath: \.disable_encryption,
            label: "Disable Encryption",
            help:
                "Disable encryption for peer communication. Must be the same on all peers."
        ),
        .init(
            keyPath: \.disable_udp_hole_punching,
            label: "Disable UDP Hole Punching",
            help: "Disable the UDP hole punching mechanism."
        ),
        .init(
            keyPath: \.disable_sym_hole_punching,
            label: "Disable Symmetric NAT Hole Punching",
            help: "Disable special handling for symmetric NATs."
        ),
        .init(
            keyPath: \.enable_magic_dns,
            label: "Enable Magic DNS",
            help:
                "Access nodes in the network by their hostname via a special DNS."
        ),
        .init(
            keyPath: \.enable_private_mode,
            label: "Enable Private Mode",
            help:
                "Do not allow handshake or relay for nodes with a different network name or secret."
        ),
    ]
}

struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        @State var profile = NetworkProfile(id: UUID())
        NavigationView {
            NetworkEditView(profile: $profile)
        }
    }
}

struct Advanced_Settings_Previews: PreviewProvider {
    static var previews: some View {
        @State var profile = NetworkProfile(id: UUID())
        NetworkEditView(profile: $profile).advancedSettings
    }
}

struct CIDRManagementView: View {
    @Environment(\.dismiss) var dismiss
    
    @Binding var useCIDR: Bool          
    @Binding var proxyCIDRs: [String]
    
    @State private var editingIndex: Int? = nil
    @State private var isShowingEditor = false
    @State private var newCIDRText = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Use CIDR", isOn: $useCIDR)
                }
                
                if useCIDR {
                    Section("Saved CIDRs") {
                        Button(action: {
                            newCIDRText = ""
                            editingIndex = nil
                            isShowingEditor = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Proxy CIDR")
                            }
                        }
                        
                        ForEach(proxyCIDRs, id: \.self) { cidr in
                            Button(action: {
                                newCIDRText = cidr
                                editingIndex = proxyCIDRs.firstIndex(of: cidr)
                                isShowingEditor = true
                            }) {
                                HStack {
                                    Text(cidr)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Image(systemName: "pencil.circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Proxy CIDRs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                CIDREditView(fullText: $newCIDRText) { savedText in
                    if let index = editingIndex {
                        proxyCIDRs[index] = savedText
                    } else {
                        if !proxyCIDRs.contains(savedText) {
                            proxyCIDRs.append(savedText)
                        }
                    }
                    useCIDR = true
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        proxyCIDRs.remove(atOffsets: offsets)
        if proxyCIDRs.isEmpty {
            useCIDR = false
        }
    }
}

struct CIDREditView: View {
    @Environment(\.dismiss) var dismiss
    
    @Binding var fullText: String
    var onSave: (String) -> Void

    @State private var ipAddress: String = ""
    @State private var prefixLength: Int = 24

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("CIDR Configuration")) {
                    HStack {
                        TextField("IPv4 Address", text: $ipAddress)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                        
                        Text("/")
                            .foregroundColor(.secondary)
                        
                        TextField("Length", value: $prefixLength, formatter: NumberFormatter())
                            .frame(width: 50)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Section(footer: Text("Example: 192.168.1.0 / 24")) {
                    EmptyView()
                }
            }
            .navigationTitle(fullText.isEmpty ? "Add CIDR" : "Edit CIDR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let combined = "\(ipAddress)/\(prefixLength)"
                        onSave(combined)
                        dismiss()
                    }
                    .disabled(ipAddress.isEmpty)
                    .bold()
                }
            }
            .onAppear {
                parseCIDR()
            }
        }
    }

    private func parseCIDR() {
        guard !fullText.isEmpty else { return }
        
        let components = fullText.components(separatedBy: "/")
        if components.count == 2 {
            ipAddress = components[0]
            prefixLength = Int(components[1]) ?? 24
        } else {
            ipAddress = fullText
        }
    }
}
