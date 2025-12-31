import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) var context
    @Query(sort: \ProfileSummary.createdAt) var networks: [ProfileSummary]

    @State var selectedProfile: ProfileSummary?
    @State var isConnected = false
    @State var isPending = false

    var body: some View {
        VStack {
            headerView
                .padding([.horizontal, .top])
            if let profile = Binding($selectedProfile) {
                ZStack {
                    if isConnected {
                        StatusView()
                    } else {
                        NetworkEditView(profile: profile.profile)
                            .disabled(isPending)
                    }
                }
            } else {
                Spacer()
                Image(systemName: "network.slash")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color.accentColor)
                Text("Please select a network.")
                Spacer()
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if selectedProfile == nil {
                selectedProfile = networks.first
            }
        }
    }
    
    @State var showSheet = false

    @State var showNewNetworkAlert = false
    @State var newNetworkInput = ""
    
    @State var showRenameAlert = false
    @State var renameInput = ""
    @State var toRenameProfile: ProfileSummary?

    var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.up.chevron.down")
                .onTapGesture {
                    showSheet = true
                }
            Text(selectedProfile?.name ?? "Select Network")
                .font(.largeTitle.bold())
                .onTapGesture {
                    showSheet = true
                }
            Spacer()
            Button(isConnected ? "Disconnect" : "Connect", systemImage: isConnected ? "cable.connector.slash" : "cable.connector") {
                isConnected = !isConnected
            }
            .disabled(isPending || selectedProfile == nil)
            .buttonStyle(.glassProminent)
            .tint(isConnected ? Color.red : Color.accentColor)
            .animation(.interactiveSpring, value: isConnected)
        }
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                List {
                    Section("Network") {
                        ForEach(networks, id: \.self) { item in
                            Button {
                                selectedProfile = item
                            } label: {
                                HStack {
                                    Text(item.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedProfile == item {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    toRenameProfile = item
                                    showRenameAlert = true
                                } label: {
                                    Image(systemName: "pencil")
                                    Text("Rename")
                                }
                                .tint(.orange)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                if selectedProfile == networks[index] {
                                    selectedProfile = nil
                                }
                                context.delete(networks[index])
                            }
                        }
                    }
                    Section("Manage") {
                        Button {
                            showNewNetworkAlert = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "document.badge.plus")
                                Text("Create a network")
                            }
                        }
                        Button {
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.document")
                                Text("Import from file")
                            }
                        }
                        Button {
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "long.text.page.and.pencil")
                                Text("Edit in text")
                            }
                        }
                    }
                }
                .navigationTitle("Manage Networks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button {
                        showSheet = false
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .alert("New Network", isPresented: $showNewNetworkAlert) {
                    TextField("Name of the new network", text: $newNetworkInput)
                        .textInputAutocapitalization(.never)
                    Button(role: .cancel) { }
                    Button(role: .confirm) {
                        let profile = ProfileSummary(name: newNetworkInput.isEmpty ? "New Network" : newNetworkInput, context: context)
                        context.insert(profile)
                        selectedProfile = profile
                    }
                    .buttonStyle(.borderedProminent)
                }
                .alert("Rename Network", isPresented: $showRenameAlert) {
                    TextField("New name of the network", text: $renameInput)
                        .textInputAutocapitalization(.never)
                    Button(role: .cancel) { }
                    Button(role: .confirm) {
                        if !renameInput.isEmpty && toRenameProfile != nil {
                            toRenameProfile!.name = renameInput
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .modelContainer(try! ModelContainer(for: Schema([ProfileSummary.self, NetworkProfile.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
}
