import SwiftUI
import Combine
import NetworkExtension
import os
import TOMLKit
import UniformTypeIdentifiers
import EasyTierShared

private let dashboardLogger = Logger(subsystem: APP_BUNDLE_ID, category: "main.dashboard")
private let autoSaveInterval: UInt64 = 1_200_000_000

private struct ProfileTextDraft: Identifiable {
    let id = UUID()
    let text: String
}

private struct EditModeAwareConfirmationButton: View {
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif

    let action: () -> Void

    var body: some View {
#if os(iOS)
        if editMode?.wrappedValue.isEditing != true {
            Button(action: action) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
#else
        Button(action: action) {
            Image(systemName: "checkmark")
        }
        .buttonStyle(.borderedProminent)
#endif
    }
}

private struct ProfileTextEditor: View {
    @State private var text: String

    let onCancel: () -> Void
    let onSave: (String) -> Void

    init(text: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            }
            .navigationTitle("edit_config")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        onSave(text)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct DashboardView<Manager: NetworkExtensionManagerProtocol>: View {
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var manager: Manager
    @ObservedObject var selectedSession: SelectedProfileSession
    
    @AppStorage("selectedProfileName", store: UserDefaults(suiteName: APP_GROUP_ID)) var lastSelected: String?

    @State var currentProfile = NetworkProfile()
    @State var isLocalPending = false

    @State var showManageSheet = false
    @State var showNewNetworkAlert = false
    @State var newNetworkInput = ""
    @State var showEditConfigNameAlert = false
    @State var editConfigNameInput = ""
    @State var editingProfileName: String?

    @State var showImportPicker = false
#if os(iOS)
    @State var exportURL: IdentifiableURL?
#endif
    @State private var editDraft: ProfileTextDraft?

    @State var errorMessage: TextItem?
    @State var showConflictAlert = false
    @State var conflictConfigName: String?
    @State var conflictDetails: String = ""

    @State var darwinObserver: DarwinNotificationObserver? = nil
    @State var autoSaveTask: Task<Void, Never>? = nil
    
    init(manager: Manager, selectedSession: SelectedProfileSession) {
        _manager = ObservedObject(wrappedValue: manager)
        _selectedSession = ObservedObject(wrappedValue: selectedSession)
    }

    struct ProfileEntry: Identifiable, Equatable {
        var id: String { configName }
        var configName: String
        var profile: NetworkProfile?
    }

    var isConnected: Bool {
        [.connected, .disconnecting, .reasserting].contains(manager.status)
    }
    var isPending: Bool {
        isLocalPending || [.connecting, .disconnecting, .reasserting].contains(manager.status)
    }
    var hasSelectedProfile: Bool {
        selectedSession.session != nil
    }

    var mainView: some View {
        Group {
            if hasSelectedProfile {
                if isConnected {
                    StatusView(currentProfile.networkName, manager: manager)
                } else {
                    NetworkEditView(profile: $currentProfile)
                        .disabled(isPending)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "network.slash")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(Color.accentColor)
                    Text("no_network_selected")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
#if os(iOS)
                .background(Color(.systemGroupedBackground))
#endif
            }
        }
    }

    func createProfile() {
        let baseName = newNetworkInput.isEmpty ? String(localized: "new_network") : newNetworkInput
        guard let sanitizedName = availableConfigName(baseName) else { return }
        let profile = NetworkProfile()
        Task { @MainActor in
            do {
                guard await closeSelectedSession() else { return }
                try ProfileStore.save(profile, named: sanitizedName)
                let session = try await ProfileStore.openSession(named: sanitizedName)
                try await activateSession(session)
            } catch {
                dashboardLogger.error("create profile failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    var manageSheet: some View {
        NavigationStack {
            Form {
                Section("network") {
                    let profiles = ProfileStore.loadIndexOrEmpty().map{ IdenticalTextItem($0) }
                    ForEach(profiles) { item in
                        HStack {
                            Text(item.id)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedSession.session?.name == item.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {  
                            if selectedSession.session?.name == item.id {
                                Task { @MainActor in
                                    await closeSelectedSession()
                                }
                            } else {
                                Task { @MainActor in
                                    await loadProfile(item.id)
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                editingProfileName = item.id
                                editConfigNameInput = item.id
                                showEditConfigNameAlert = true
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task { @MainActor in
                                    do {
                                        if selectedSession.session?.name == item.id {
                                            await closeSelectedSession(save: false)
                                        }
                                        try ProfileStore.deleteProfile(named: item.id)
                                    } catch {
                                        dashboardLogger.error("delete profile failed: \(error)")
                                        errorMessage = .init(error.localizedDescription)
                                    }
                                }
                            } label: {
                                Label("delete", systemImage: "trash")
                                    .tint(.red)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingProfileName = item.id
                                editConfigNameInput = item.id
                                showEditConfigNameAlert = true
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onDelete { indexSet in
                        withAnimation {
                            for index in indexSet {
                                Task { @MainActor in
                                    do {
                                        if selectedSession.session?.name == profiles[index].id {
                                            await closeSelectedSession(save: false)
                                        }
                                        try ProfileStore.deleteProfile(named: profiles[index].id)
                                    } catch {
                                        dashboardLogger.error("delete profile failed: \(error)")
                                        errorMessage = .init(error.localizedDescription)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("device.management") {
                    Button {
                        showNewNetworkAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "document.badge.plus")
                            } else {
                                Image(systemName: "plus.app")
                            }
                            Text("profile.create_network")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                    Button {
                        presentEditInText()
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.4, *) {
                                Image(systemName: "long.text.page.and.pencil")
                            } else {
                                Image(systemName: "square.and.pencil")
                            }
                            Text("profile.edit_in_text")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                    Button {
                        showImportPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "arrow.down.document")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("profile.import_config")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                    Button {
                        exportSelectedProfile()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                            Text("profile.export_config")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                }
            }
            .formStyle(.grouped)
            .navigationTitle("device.management")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    EditModeAwareConfirmationButton {
                        showManageSheet = false
                    }
                }
            }
            .listEditingToolbar(
                isVisible: !ProfileStore.loadIndexOrEmpty().isEmpty,
                placement: .cancellationAction
            )
            .alert("add_new_network", isPresented: $showNewNetworkAlert) {
                TextField("config_name", text: $newNetworkInput)
                    .adaptiveNoTextInputAutocapitalization()
                if #available(iOS 26.0, macOS 26.0, *) {
                    Button(role: .cancel) {}
                    Button("network.create", role: .confirm, action: createProfile)
                } else {
                    Button("common.cancel") {}
                    Button("network.create", action: createProfile)
                }
            }
            .alert("edit_config_name", isPresented: $showEditConfigNameAlert) {
                TextField("config_name", text: $editConfigNameInput)
                    .adaptiveNoTextInputAutocapitalization()
                Button("common.cancel") {}
                Button("save") {
                    commitConfigNameEdit()
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainView
                .navigationTitle(selectedSession.session?.name ?? String(localized: "select_network"))
            .toolbar {
                ToolbarItem(placement: ToolbarLeading) {
                    Button("select_network", systemImage: "chevron.up.chevron.down") {
                        showManageSheet = true
                    }
                    .disabled(isPending || isConnected)
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button {
                        guard !isPending else { return }
                        isLocalPending = true
                        Task { @MainActor in
                            if isConnected {
                                await manager.disconnect()
                            } else {
                                if await saveProfile() {
                                    do {
                                        try await manager.connect()
                                    } catch {
                                        dashboardLogger.error("connect failed: \(error)")
                                        errorMessage = .init(error.localizedDescription)
                                    }
                                }
                            }
                            isLocalPending = false
                        }
                    } label: {
                        Label(
                            isConnected ? "vpn_disconnect" : "vpn_connect",
                            systemImage: isConnected ? "cable.connector.slash" : "cable.connector"
                        )
                        .labelStyle(.titleAndIcon)
                        .padding(10)
                    }
                    .disabled((!hasSelectedProfile && !isConnected) || manager.isLoading || isPending)
#if os(iOS)
                    .buttonStyle(.plain)
#endif
                    .foregroundStyle(isConnected ? Color.red : Color.accentColor)
                    .animation(.interactiveSpring, value: [isConnected, isPending])
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                try? await manager.load()
                if let session = selectedSession.session {
                    currentProfile = session.document.profile
                } else if let lastSelected {
                    await loadProfile(lastSelected)
                }
            }
            // Register Darwin notification observer for tunnel errors
            darwinObserver = DarwinNotificationObserver(name: "\(APP_BUNDLE_ID).error") {
                // Read the latest error from shared App Group defaults
                let defaults = UserDefaults(suiteName: APP_GROUP_ID)
                if let msg = defaults?.string(forKey: "TunnelLastError") {
                    DispatchQueue.main.async {
                        dashboardLogger.error("core stopped: \(msg)")
                        self.errorMessage = .init(msg)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            guard [.inactive, .background].contains(newPhase) else { return }
            Task { @MainActor in
                autoSaveTask?.cancel()
                autoSaveTask = nil
                await saveProfile()
            }
        }
        .onChange(of: selectedSession.session) { session in
            lastSelected = session?.name
            currentProfile = session?.document.profile ?? NetworkProfile()
        }
        .onChange(of: currentProfile) { profile in
            guard let session = selectedSession.session,
                  session.document.profile != profile else { return }
            session.document.profile = profile
            scheduleAutoSave()
        }
        .onDisappear {
            // Release observer to remove registration
            darwinObserver = nil
            autoSaveTask?.cancel()
            autoSaveTask = nil
            Task { @MainActor in
                await saveProfile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDocumentConflictDetected)) { notification in
            let configName = notification.userInfo?["configName"] as? String
            Task { @MainActor in
                handleConflict(configName: configName ?? selectedSession.session?.name)
            }
        }
        .sheet(isPresented: $showManageSheet) {
            manageSheet
                .sheet(item: $editDraft) { draft in
                    ProfileTextEditor(text: draft.text) {
                        editDraft = nil
                    } onSave: { text in
                        saveEditInText(text)
                    }
                }
#if os(iOS)
                .sheet(item: $exportURL) { url in
                    ShareSheet(activityItems: [url.url])
                }
#endif
                .fileImporter(
                    isPresented: $showImportPicker,
                    allowedContentTypes: [
                        UTType(mimeType: "application/toml"),
                        UTType(filenameExtension: "toml"),
                        .plainText
                    ].compactMap { $0 },
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        importConfig(from: url)
                    case .failure(let error):
                        errorMessage = .init(error.localizedDescription)
                    }
                }
                .alert(item: $errorMessage) { msg in
                    dashboardLogger.error("received error: \(String(describing: msg))")
                    return Alert(title: Text("common.error"), message: Text(msg.text))
                }
        }
        .alert(item: $errorMessage) { msg in
            dashboardLogger.error("received error: \(String(describing: msg))")
            return Alert(title: Text("common.error"), message: Text(msg.text))
        }
        .alert("icloud_conflict_title", isPresented: $showConflictAlert) {
            Button("icloud_conflict_use_local") {
                resolveConflict(useLocal: true)
            }
            Button("icloud_conflict_use_remote") {
                resolveConflict(useLocal: false)
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            if conflictDetails.isEmpty {
                Text("icloud_conflict_message")
            } else {
                Text(conflictDetails)
            }
        }
    }
    
    @MainActor
    private func activateSession(_ session: ProfileSession) async throws {
        do {
            var profile = session.document.profile
            let options = try NetworkExtensionManager.generateOptions(&profile)
            session.document.profile = profile
            try await session.save()
            NetworkExtensionManager.saveOptions(options)
            selectedSession.session = session
            currentProfile = profile
            lastSelected = session.name
        } catch {
            await session.close()
            throw error
        }
    }

    @MainActor
    private func loadProfile(_ named: String) async {
        guard await closeSelectedSession() else { return }
        do {
            let session = try await ProfileStore.openSession(named: named)
            try await activateSession(session)
        } catch {
            dashboardLogger.error("load profile failed: \(error)")
            if let conflict = error as? ProfileStoreError,
               case .conflict = conflict {
                handleConflict(configName: named)
            } else {
                errorMessage = .init(error.localizedDescription)
            }
            selectedSession.session = nil
        }
    }
    
    @MainActor
    @discardableResult
    private func saveProfile(saveOptions: Bool = true) async -> Bool {
        if let session = selectedSession.session {
            do {
                try currentProfile.prepareForUse()
                session.document.profile = currentProfile
                let options: EasyTierOptions?
                if saveOptions {
                    options = try NetworkExtensionManager.generateOptions(&session.document.profile)
                    currentProfile = session.document.profile
                } else {
                    options = nil
                }
                try await session.save()
                if let options {
                    NetworkExtensionManager.saveOptions(options)
                }
            } catch {
                dashboardLogger.error("save failed: \(error)")
                if let conflict = error as? ProfileStoreError,
                   case .conflict = conflict {
                    handleConflict(configName: session.name)
                } else {
                    errorMessage = .init(error.localizedDescription)
                }
                return false
            }
        }
        return true
    }

    private func importConfig(from url: URL) {
        Task { @MainActor in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let toml = try String(contentsOf: url, encoding: .utf8)
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: toml)
                let rawName = url.deletingPathExtension().lastPathComponent
                guard let configName = availableConfigName(rawName) else { return }
                let profile = NetworkProfile(from: config)
                guard await closeSelectedSession() else { return }
                try ProfileStore.save(profile, named: configName)
                let session = try await ProfileStore.openSession(named: configName)
                try await activateSession(session)
            } catch {
                dashboardLogger.error("import failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func exportSelectedProfile() {
        guard let session = selectedSession.session else {
            errorMessage = .init(String(localized: "no_network_selected"))
            return
        }
        let fileURL = try? ProfileStore.fileURL(forConfigName: session.name)
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = .init("Config file not found.")
            return
        }
        dashboardLogger.info("exporting to: \(fileURL)")
#if os(iOS)
        exportURL = .init(fileURL)
#elseif os(macOS)
        do {
            try saveExportedFileToDisk(fileURL)
        } catch {
            errorMessage = .init(error.localizedDescription)
        }
#endif
    }

    private func presentEditInText() {
        Task { @MainActor in
            guard hasSelectedProfile else {
                errorMessage = .init(String(localized: "no_network_selected"))
                return
            }
            do {
                try currentProfile.prepareForUse()
                selectedSession.session?.document.profile = currentProfile
                let config = currentProfile.toConfig()
                guard let encoded = try TOMLEncoder().encode(config).string else {
                    throw ProfileStoreError.encodingProducedNoString
                }
                editDraft = ProfileTextDraft(text: encoded)
            } catch {
                dashboardLogger.error("edit load failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func saveEditInText(_ text: String) {
        Task { @MainActor in
            do {
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: text)
                let profile = NetworkProfile(from: config)
                currentProfile = profile
                selectedSession.session?.document.profile = profile
                guard await saveProfile() else { return }
                editDraft = nil
            } catch {
                dashboardLogger.error("edit save failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func commitConfigNameEdit() {
        guard let editingProfileName else { return }
        let trimmed = editConfigNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != editingProfileName else { return }
        guard let sanitizedName = validatedConfigName(trimmed) else { return }
        Task { @MainActor in
            do {
                let renamingSelected = selectedSession.session?.name == editingProfileName
                if renamingSelected {
                    guard await closeSelectedSession() else { return }
                }
                try ProfileStore.renameProfileFile(from: editingProfileName, to: sanitizedName)
                if renamingSelected {
                    await loadProfile(sanitizedName)
                }
            } catch {
                dashboardLogger.error("rename failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func validatedConfigName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = .init("Config name cannot be empty.")
            return nil
        }
        let sanitized = ProfileStore.sanitizedFileName(trimmed, fallback: "")
        guard sanitized == trimmed else {
            errorMessage = .init("Config name contains invalid characters.")
            return nil
        }
        do {
            guard try ProfileStore.profileExists(named: sanitized) == false else {
                errorMessage = .init("Config name already exists.")
                return nil
            }
        } catch {
            dashboardLogger.error("validate config name failed: \(error)")
            errorMessage = .init(error.localizedDescription)
            return nil
        }
        return sanitized
    }

    private func availableConfigName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = .init("Config name cannot be empty.")
            return nil
        }
        let sanitized = ProfileStore.sanitizedFileName(trimmed, fallback: "")
        guard sanitized == trimmed else {
            errorMessage = .init("Config name contains invalid characters.")
            return nil
        }
        do {
            let existingNames = try ProfileStore.loadIndex()
            let normalizedNames = Set(existingNames.map { $0.lowercased() })
            if !normalizedNames.contains(sanitized.lowercased()) {
                return sanitized
            }
            var suffix = 2
            while suffix < 10_000 {
                let candidate = "\(sanitized) \(suffix)"
                if !normalizedNames.contains(candidate.lowercased()) {
                    return candidate
                }
                suffix += 1
            }
        } catch {
            dashboardLogger.error("find available config name failed: \(error)")
            errorMessage = .init(error.localizedDescription)
            return nil
        }
        errorMessage = .init("Config name already exists.")
        return nil
    }

    @MainActor
    @discardableResult
    private func closeSelectedSession(save: Bool = true) async -> Bool {
        dashboardLogger.info("closing session with save: \(save)")
        autoSaveTask?.cancel()
        autoSaveTask = nil
        if save, !(await saveProfile()) {
            return false
        }
        if let session = selectedSession.session {
            await session.close()
        }
        selectedSession.session = nil
        currentProfile = NetworkProfile()
        lastSelected = nil
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        defaults?.removeObject(forKey: "VPNConfig")
        defaults?.synchronize()
        return true
    }

    private func resolveConflict(useLocal: Bool) {
        Task { @MainActor in
            guard let conflictConfigName else { return }
            do {
                await closeSelectedSession(save: false)
                let url = try ProfileStore.fileURL(forConfigName: conflictConfigName)
                if useLocal {
                    try ProfileStore.resolveConflictUseLocal(at: url)
                } else {
                    try ProfileStore.resolveConflictUseRemote(at: url)
                }
                try await ProfileStore.waitForConflictResolved(at: url)
                await loadProfile(conflictConfigName)
            } catch {
                dashboardLogger.error("resolve conflict failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
            self.conflictConfigName = nil
            self.conflictDetails = ""
        }
    }

    @MainActor
    private func handleConflict(configName: String?) {
        guard let configName else { return }
        if showConflictAlert, conflictConfigName == configName {
            return
        }
        conflictConfigName = configName
        conflictDetails = conflictDetailsText(for: configName)
        showConflictAlert = true
    }

    private func conflictDetailsText(for configName: String) -> String {
        guard let url = try? ProfileStore.fileURL(forConfigName: configName) else {
            return String(localized: "icloud_conflict_message")
        }
        let infos = ProfileStore.conflictInfos(at: url)
        guard !infos.isEmpty else {
            return String(localized: "icloud_conflict_message")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let lines = infos.map { info in
            let label = info.local ? String(localized: "local") : String(localized: "icloud")
            let time = info.modificationDate.map { formatter.string(from: $0) } ?? "-"
            let device = info.deviceName ?? "N/A"
            return "\(label): \(device) · \(time)"
        }
        return ([String(localized: "icloud_conflict_message")] + lines).joined(separator: "\n")
    }

    @MainActor
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard selectedSession.session != nil else { return }
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoSaveInterval)
            guard !Task.isCancelled else { return }
            dashboardLogger.info("auto saving...")
            await saveProfile(saveOptions: true)
        }
    }

}

struct IdentifiableURL: Identifiable {
    var id: URL { self.url }
    var url: URL
    init(_ url: URL) {
        self.url = url
    }
}


#if DEBUG
#Preview("Dashboard") {
    let manager = MockNEManager()
    let selectedSession = SelectedProfileSession()
    DashboardView(manager: manager, selectedSession: selectedSession)
        .environmentObject(manager)
}
#endif
