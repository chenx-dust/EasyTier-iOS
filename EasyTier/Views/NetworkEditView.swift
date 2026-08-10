import SwiftUI

struct NetworkEditView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @Binding var profile: NetworkProfile
    @State var showProxyCIDREditor = false
    @State var editingProxyCIDR: NetworkProfile.ProxyCIDR = .init()
    @State var editingPeerPublicKey: PeerPublicKeyEditContext?
    @State var selectedPane: EditPane?

    enum EditPane: Identifiable, Hashable {
        var id: Self { self }
        case advanced, dns, route, portForwards, acl
    }
    
    var body: some View {
        AdaptiveNavigation(primaryColumn, secondaryColumn, showNav: $selectedPane)
            .sheet(item: $editingPeerPublicKey) { context in
                PeerPublicKeyEditor(context: context) { publicKey in
                    if let index = profile.peerConfigs.firstIndex(where: { $0.id == context.id }) {
                        profile.peerConfigs[index].peerPublicKey = publicKey
                    }
                    editingPeerPublicKey = nil
                }
            }
    }
    
    var primaryColumn: some View {
        Group {
#if os(iOS)
            List(selection: $selectedPane) {
                basicSettings
                NavigationLink("advanced_settings", value: EditPane.advanced)
                NavigationLink("dns_settings", value: EditPane.dns)
                NavigationLink("route_settings", value: EditPane.route)
                NavigationLink("port_forwards", value: EditPane.portForwards)
                NavigationLink("acl.title", value: EditPane.acl)
            }
            .scrollDismissesKeyboard(.immediately)
#else
            Form {
                basicSettings
                NavigationLink("advanced_settings") { advancedSettings }
                NavigationLink("dns_settings") { dnsSettings }
                NavigationLink("route_settings") { routeSettings }
                NavigationLink("port_forwards") { portForwardsSettings }
                NavigationLink("acl.title") { ACLSettingsView(acl: $profile.acl) }
            }
            .formStyle(.grouped)
#endif
        }
    }
    
    var secondaryColumn: some View {
        Group {
            switch selectedPane {
            case .advanced:
                advancedSettings
            case .dns:
                dnsSettings
            case .route:
                routeSettings
            case .portForwards:
                portForwardsSettings
            case .acl:
                ACLSettingsView(acl: $profile.acl)
            case nil:
                ZStack {
#if os(iOS)
                    Color(.systemGroupedBackground)
#endif
                    Image(systemName: "network")
                        .resizable()
                        .frame(width: 128, height: 128)
                        .foregroundStyle(Color.accentColor.opacity(0.2))
                }
                .ignoresSafeArea()
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    var basicSettings: some View {
        Group {
            Section("virtual_ipv4") {
                Toggle("dhcp", isOn: $profile.dhcp)

                if !profile.dhcp {
                    LabeledContent("address") {
                        IPv4Field(ip: $profile.virtualIPv4.ip, length: $profile.virtualIPv4.length)
                    }
                }
            }

            Section("network") {
                LabeledContent("network_name") {
                    TextField(
                        "easytier",
                        text: $profile.networkName,
                        prompt: Text("easytier")
                    )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                
                LabeledContent("network_secret") {
                    SecureField(
                        "common_text.empty",
                        text: $profile.networkSecret,
                        prompt: Text("common_text.empty")
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                }
                
                LabeledContent("hostname") {
                    TextField(
                        "common_text.default",
                        text: $profile.hostname,
                        prompt: Text("common_text.default")
                    )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                ListEditor(
                    newItemTitle: "common_text.add_initial_node",
                    items: $profile.peerConfigs,
                    addItemFactory: NetworkProfile.PeerSetting.init,
                    rowActionTitle: "set_peer_public_key",
                    rowActionSystemImage: "key.horizontal",
                    rowActionTint: .orange,
                    rowAction: { peer in
                        let peer = peer.wrappedValue
                        editingPeerPublicKey = PeerPublicKeyEditContext(
                            id: peer.id,
                            uri: peer.uri,
                            publicKey: peer.peerPublicKey ?? ""
                        )
                    },
                    rowContent: { peer in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(
                                "example.peer_url",
                                text: peer.uri,
                                prompt: Text("example.peer_url")
                            )
                            .labelsHidden()
                            .font(.body.monospaced())

                            if let publicKey = peer.wrappedValue.peerPublicKey?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !publicKey.isEmpty {
                                (Text("peer_public_key") + Text(verbatim: ": \(publicKey)"))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .labelsHidden()
                    }
                )
            } header: {
                Text("initial_nodes")
            } footer: {
                Text("initial_nodes_help")
            }
        }
    }

    var advancedSettings: some View {
        Form {
            Section {
                LabeledContent("mtu") {
                    TextField(
                        "common_text.default",
                        text: Binding(
                            get: { $profile.mtu.wrappedValue.map(String.init) ?? "" },
                            set: { newValue in
                                if newValue.isEmpty {
                                    $profile.mtu.wrappedValue = nil
                                } else {
                                    $profile.mtu.wrappedValue = Int(newValue)
                                }
                            }
                        ),
                        prompt: Text("common_text.default")
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .numberKeyboardType()
                }
                LabeledContent("instance_recv_bps_limit") {
                    TextField(
                        "example.instance_recv_bps_limit",
                        text: Binding(
                            get: { $profile.instanceRecvBpsLimit.wrappedValue.map(String.init) ?? "" },
                            set: { newValue in
                                if newValue.isEmpty {
                                    $profile.instanceRecvBpsLimit.wrappedValue = nil
                                } else {
                                    $profile.instanceRecvBpsLimit.wrappedValue = UInt64(newValue)
                                }
                            }
                        ),
                        prompt: Text("example.instance_recv_bps_limit")
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .numberKeyboardType()
                }
            } header: {
                Text("general")
            } footer: {
                Text("mtu_help")
                    + Text("\n")
                    + Text("instance_recv_bps_limit_help")
            }

            Section {
                Toggle(
                    "common_text.enable",
                    isOn: Binding(
                        get: { profile.enableSecureMode },
                        set: { enabled in
                            profile.enableSecureMode = enabled
                            if enabled {
                                try? profile.prepareSecureModeKeys()
                            }
                        }
                    )
                )
                if profile.enableSecureMode {
                    LabeledContent("local_private_key") {
                        TextField(
                            "common_text.empty",
                            text: Binding(
                                get: { profile.secureModeLocalPrivateKey },
                                set: { profile.updateSecureModePrivateKey($0) }
                            ),
                            prompt: Text("common_text.empty"),
                            axis: .vertical
                        )
                        .labelsHidden()
                        .font(.body.monospaced())
                        .adaptiveNoTextInputAutocapitalization()
                        .autocorrectionDisabled()
                    }
                    LabeledContent("local_public_key") {
                        Group {
                            if profile.secureModeLocalPublicKey.isEmpty {
                                Text("common_text.empty")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: profile.secureModeLocalPublicKey)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.body.monospaced())
                    }
                }
            } header: {
                Text("secure_mode")
            } footer: {
                Text("secure_mode_help")
            }
            
            Section("vpn_portal_config") {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableVPNPortal
                )
                if profile.enableVPNPortal {
                    LabeledContent("vpn_portal_client_network") {
                        IPv4Field(ip: $profile.vpnPortalClientCIDR.ip, length: $profile.vpnPortalClientCIDR.length)
                    }
                    LabeledContent("vpn_portal_listen_port") {
                        TextField(
                            "example.vpn_portal_listen_port",
                            value: $profile.vpnPortalListenPort,
                            formatter: NumberFormatter(),
                            prompt: Text("example.vpn_portal_listen_port")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .numberKeyboardType()
                    }
                }
            }
            
            Section("listener_urls") {
                ListEditor(newItemTitle: "common_text.add_listener_url", items: $profile.listenerURLs, addItemFactory: { "" }, rowContent: {
                    TextField(
                        "example.listener_url",
                        text: $0.text,
                        prompt: Text("example.listener_url")
                    )
                        .labelsHidden()
                        .font(.body.monospaced())
                })
            }
            
            Section {
                Toggle("common_text.enable", isOn: $profile.enableRelayNetworkWhitelist)
                if profile.enableRelayNetworkWhitelist {
                    ListEditor(newItemTitle: "common_text.add_network", items: $profile.relayNetworkWhitelist, addItemFactory: { "" }, rowContent: {
                        TextField(
                            "example.network_name",
                            text: $0.text,
                            prompt: Text("example.network_name")
                        )
                            .labelsHidden()
                            .font(.body.monospaced())
                    })
                }
            } header: {
                Text("relay_network_whitelist")
            } footer: {
                Text("relay_network_whitelist_help")
            }
            
            Section("socks5") {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableSocks5
                )
                if profile.enableSocks5 {
                    LabeledContent("listen_port") {
                        TextField(
                            "example.socks5_port",
                            value: $profile.socks5Port,
                            formatter: NumberFormatter(),
                            prompt: Text("example.socks5_port")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .numberKeyboardType()
                    }
                }
            }
            
            Section {
                ListEditor(newItemTitle: "common_text.add_map_listener", items: $profile.mappedListeners, addItemFactory: { "" }, rowContent: {
                    TextField(
                        "example.mapped_listener_url",
                        text: $0.text,
                        prompt: Text("example.mapped_listener_url")
                    )
                        .labelsHidden()
                        .font(.body.monospaced())
                })
            } header: {
                Text("mapped_listeners")
            } footer: {
                Text("mapped_listeners_help")
            }

            Section("flags_switch") {
                ForEach(NetworkProfile.boolFlags) { flag in
                    Toggle(isOn: Binding<Bool>(
                        get: { $profile.wrappedValue[keyPath: flag.keyPath] },
                        set: { $profile.wrappedValue[keyPath: flag.keyPath] = $0 }
                    )) {
                        Text(flag.label)
                        if let help = flag.help {
                            Text(help)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("advanced_settings")
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .listEditingToolbar(
            isVisible: !profile.listenerURLs.isEmpty
                || (profile.enableRelayNetworkWhitelist && !profile.relayNetworkWhitelist.isEmpty)
                || !profile.mappedListeners.isEmpty
        )
    }
    
    var dnsSettings: some View {
        Form {
            Section {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableMagicDNS
                )
                if profile.enableMagicDNS {
                    LabeledContent("tld_dns_zone") {
                        TextField(
                            "example.tld_dns_zone",
                            text: $profile.magicDNSTLD,
                            prompt: Text("example.tld_dns_zone")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("magic_dns")
            } footer: {
                Text("magic_dns_help")
            }
            
            Section {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableOverrideDNS
                )
                if profile.enableOverrideDNS {
                    ListEditor(newItemTitle: "common_text.add_dns", items: $profile.overrideDNS, addItemFactory: { "" }, rowContent: { dns in
                        HStack {
                            Text("address")
                                .foregroundStyle(.secondary)
                            Spacer()
                            IPv4Field(ip: dns.text)
                        }
                    })
                }
            } header: {
                Text("override_dns")
            } footer: {
                Text("override_dns_help")
            }
        }
        .navigationTitle("dns_settings")
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .listEditingToolbar(
            isVisible: profile.enableOverrideDNS && !profile.overrideDNS.isEmpty
        )
    }
    
    var routeSettings: some View {
        Form {
            proxyCIDRsSettings
            
            Section {
                ListEditor(newItemTitle: "common_text.add_exit_node", items: $profile.exitNodes, addItemFactory: { "" }, rowContent: { ip in
                    HStack {
                        Text("address")
                            .foregroundStyle(.secondary)
                        Spacer()
                        IPv4Field(ip: ip.text)
                    }
                })
            } header: {
                Text("exit_nodes")
            } footer: {
                Text("exit_nodes_help")
            }
            
            Section {
                Toggle("common_text.enable", isOn: $profile.enableManualRoutes)
                if profile.enableManualRoutes {
                    ListEditor(newItemTitle: "common_text.add_route", items: $profile.routes, addItemFactory: NetworkProfile.CIDR.init, rowContent: { cidr in
                        HStack {
                            Text("cidr")
                                .foregroundStyle(.secondary)
                            Spacer()
                            IPv4Field(ip: cidr.ip, length: cidr.length)
                        }
                    })
                }
            } header: {
                Text("manual_routes")
            } footer: {
                Text("manual_routes_help")
            }
        }
        .navigationTitle("route_settings")
        .scrollDismissesKeyboard(.immediately)
        .sheet(isPresented: $showProxyCIDREditor) {
            proxyCIDREditor
        }
        .formStyle(.grouped)
        .listEditingToolbar(
            isVisible: !profile.proxyCIDRs.isEmpty
                || !profile.exitNodes.isEmpty
                || (profile.enableManualRoutes && !profile.routes.isEmpty)
        )
    }

    var portForwardsSettings: some View {
        Form {
            ListEditor(newItemTitle: "common_text.add_port_forward", items: $profile.portForwards, addItemFactory: NetworkProfile.PortForwardSetting.init, rowContent: { $forward in
                VStack(spacing: 8) {
                    HStack {
                        Text("tunnel_proto")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("tunnel_proto", selection: $forward.proto) {
                            Text("tcp").tag("tcp")
                            Text("udp").tag("udp")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    HStack {
                        TextField(
                            "port_forwards_bind_addr",
                            text: $forward.bindAddr,
                            prompt: Text("port_forwards_bind_addr")
                        )
                        .labelsHidden()
                        Text(":")
                        TextField(
                            "port",
                            value: $forward.bindPort,
                            formatter: NumberFormatter(),
                            prompt: Text("port")
                        )
                        .labelsHidden()
                        .frame(width: 60)
                        .numberKeyboardType()
                    }
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("forward_to")
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                    HStack {
                        TextField(
                            "port_forwards_dst_addr",
                            text: $forward.destAddr,
                            prompt: Text("port_forwards_dst_addr")
                        )
                        .labelsHidden()
                        Text(":")
                        TextField(
                            "port",
                            value: $forward.destPort,
                            formatter: NumberFormatter(),
                            prompt: Text("port")
                        )
                        .labelsHidden()
                        .frame(width: 60)
                        .numberKeyboardType()
                    }
                }
                .padding(.vertical, 5)
            })
        }
        .navigationTitle("port_forwards")
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .listEditingToolbar(isVisible: !profile.portForwards.isEmpty)
    }
    
    var proxyCIDRsSettings: some View {
        Section("common_text.proxy_cidr") {
            ListEditor(newItemTitle: "common_text.add_proxy_cidr", items: $profile.proxyCIDRs, addItemFactory: NetworkProfile.ProxyCIDR.init, rowContent: { proxyCIDR in
                HStack(spacing: 12) {
                    if proxyCIDR.enableMapping.wrappedValue {
                        Text("map")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(proxyCIDR.wrappedValue.cidrString)
                            .font(.body.monospaced())
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(proxyCIDR.wrappedValue.mappedCIDRString)
                            .font(.body.monospaced())
                    } else {
                        Text("proxy")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(proxyCIDR.wrappedValue.cidrString)
                            .font(.body.monospaced())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingProxyCIDR = proxyCIDR.wrappedValue
                    showProxyCIDREditor = true
                }
            })
        }
        .formStyle(.grouped)
    }
    
    var proxyCIDREditor: some View {
        NavigationStack {
            Form {
                Section("common_text.proxy_cidr") {
                    LabeledContent("cidr") {
                        IPv4Field(ip: $editingProxyCIDR.cidr, length: $editingProxyCIDR.length)
                    }
                }
                Section("common_text.mapped_cidr") {
                    Toggle("common_text.enable", isOn: $editingProxyCIDR.enableMapping)
                    if editingProxyCIDR.enableMapping {
                        LabeledContent("cidr") {
                            IPv4Field(ip: $editingProxyCIDR.mappedCIDR, length: $editingProxyCIDR.length, disabledLengthEdit: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("common_text.edit_proxy_cidr")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showProxyCIDREditor = false
                        if let index = (profile.proxyCIDRs.firstIndex { $0.id == editingProxyCIDR.id }) {
                            profile.proxyCIDRs[index] = editingProxyCIDR
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct PeerPublicKeyEditContext: Identifiable {
    let id: UUID
    let uri: String
    let publicKey: String
}

struct PeerPublicKeyEditor: View {
    @Environment(\.dismiss) private var dismiss

    let context: PeerPublicKeyEditContext
    let onSave: (String?) -> Void

    @State private var publicKey: String

    init(context: PeerPublicKeyEditContext, onSave: @escaping (String?) -> Void) {
        self.context = context
        self.onSave = onSave
        _publicKey = State(initialValue: context.publicKey)
    }

    private var validationError: String? {
        do {
            _ = try NetworkProfile.normalizedPeerPublicKey(publicKey, peerURI: context.uri)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("initial_node") {
                    LabeledContent("URL") {
                        Text(context.uri)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section {
                    TextField(
                        "peer_public_key",
                        text: $publicKey,
                        prompt: Text("peer_public_key"),
                        axis: .vertical
                    )
                    .labelsHidden()
                    .font(.body.monospaced())
                    .lineLimit(2...4)
                    .adaptiveNoTextInputAutocapitalization()
                    .autocorrectionDisabled()

                    if let validationError {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("peer_public_key")
                } footer: {
                    Text("peer_public_key_help")
                }

                if !context.publicKey.isEmpty {
                    Section {
                        Button("remove_peer_public_key", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("set_peer_public_key")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        validationError != nil
                    )
                }
            }
        }
    }

    private func save() {
        guard let normalized = try? NetworkProfile.normalizedPeerPublicKey(
            publicKey,
            peerURI: context.uri
        ) else { return }
        onSave(normalized)
        dismiss()
    }
}

#if DEBUG
@available(iOS 17.0, macOS 14.0, *)
#Preview("Network Edit Portrait") {
    @Previewable @State var profile = NetworkProfile()
    NavigationStack {
        NetworkEditView(profile: $profile)
    }
}
#endif
