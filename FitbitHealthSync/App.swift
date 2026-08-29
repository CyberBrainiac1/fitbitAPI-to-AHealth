import SwiftUI

@main
struct FitbitHealthSyncApp: App {
    @StateObject private var model = SyncViewModel()

    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model) }
    }
}

