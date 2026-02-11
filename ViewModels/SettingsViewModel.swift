import Foundation
import SwiftUI

class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var themes: [ReadingTheme]
    @Published var currentTheme: ReadingTheme

    private let storageService = StorageService.shared

    // Available font families for reader
    static let availableFonts: [String] = [
        "Georgia",
        "Palatino",
        "Times New Roman",
        "Helvetica Neue",
        "Avenir",
        "San Francisco",
        "Bookerly",
        "Literata",
        "Charter",
        "Iowan Old Style"
    ]

    static let playbackSpeeds: [Double] = [
        0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0
    ]

    init() {
        let loadedSettings = storageService.loadSettings()
        self.settings = loadedSettings
        self.themes = ReadingTheme.builtInThemes + storageService.loadCustomThemes()

        // Set current theme
        if let themeId = loadedSettings.selectedThemeId,
           let theme = (ReadingTheme.builtInThemes + storageService.loadCustomThemes())
            .first(where: { $0.id == themeId }) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .light
        }
    }

    func saveSettings() {
        storageService.saveSettings(settings)
    }

    func selectTheme(_ theme: ReadingTheme) {
        currentTheme = theme
        settings.selectedThemeId = theme.id
        saveSettings()
    }

    func updateFontSize(_ size: Double) {
        settings.fontSize = max(12, min(36, size))
        saveSettings()
    }

    func updateFontFamily(_ family: String) {
        settings.fontFamily = family
        saveSettings()
    }

    func updateLineSpacing(_ spacing: Double) {
        settings.lineSpacing = max(1.0, min(3.0, spacing))
        saveSettings()
    }

    func updateMargins(_ margins: Double) {
        settings.margins = max(8, min(60, margins))
        saveSettings()
    }

    func updatePlaybackSpeed(_ speed: Double) {
        settings.defaultPlaybackSpeed = speed
        saveSettings()
    }

    func toggleAutoNightMode() {
        settings.autoNightMode.toggle()
        saveSettings()
    }

    var shouldUseNightMode: Bool {
        guard settings.autoNightMode else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        if settings.nightModeStartHour > settings.nightModeEndHour {
            // Crosses midnight (e.g., 20:00 - 07:00)
            return hour >= settings.nightModeStartHour || hour < settings.nightModeEndHour
        } else {
            return hour >= settings.nightModeStartHour && hour < settings.nightModeEndHour
        }
    }

    var activeTheme: ReadingTheme {
        shouldUseNightMode ? .night : currentTheme
    }

    var bookCount: Int {
        storageService.loadBooks().count
    }

    func resetToDefaults() {
        settings = AppSettings()
        currentTheme = .light
        saveSettings()
    }
}
