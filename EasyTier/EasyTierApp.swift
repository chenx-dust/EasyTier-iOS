import SwiftUI
import SwiftData

@main
struct EasyTierApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ProfileSummary.self, NetworkProfile.self])
    }
}
