import SwiftUI

@main
struct ReadListenApp: App {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var audioPlayerVM = AudioPlayerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryVM)
                .environmentObject(settingsVM)
                .environmentObject(audioPlayerVM)
        }
    }
}
