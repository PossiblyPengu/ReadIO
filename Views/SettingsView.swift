import SwiftUI

@available(iOS 26.0, *)
struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingResetConfirm = false

    /// Whether the settings page renders in dark mode
    private var isDark: Bool {
        switch settingsVM.settings.appAppearance {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Themed background with subtle ambient gradients
                // Glass elements refract these color fields
                settingsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        header
                        settingsContent
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Reset All Settings", isPresented: $showingResetConfirm) {
                Button("Reset", role: .destructive) { settingsVM.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will restore all settings to their defaults.")
            }
        }
        .preferredColorScheme(
            settingsVM.settings.appAppearance == .dark ? .dark :
            settingsVM.settings.appAppearance == .light ? .light : nil
        )
    }

    // MARK: - Background
    private var settingsBackground: some View {
        ZStack {
            (isDark ? Color(hex: "1C1C1E") : Color(hex: "F2F2F7"))
            // Subtle ambient color for glass to refract
            RadialGradient(
                colors: [.indigo.opacity(isDark ? 0.06 : 0.04), .clear],
                center: .topLeading, startRadius: 0, endRadius: 400)
            RadialGradient(
                colors: [.purple.opacity(isDark ? 0.04 : 0.03), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 400)
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.largeTitle.weight(.bold))
            Text("Customize your reading experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Settings Content
    private var settingsContent: some View {
        VStack(spacing: 20) {
            appearanceSection
            readingSection
            audioSection
            storageSection
            aboutSection
        }
    }

    // MARK: - Glass Section Builder
    // Each section is wrapped in a LiquidGlass rounded rect.
    // Section headers sit outside. Rows inside get separator lines.
    // This replaces the standard Form — themed and glassed.

    // MARK: - Appearance
    private var appearanceSection: some View {
        GlassSection("Appearance") {
            // Theme picker row
            VStack(alignment: .leading, spacing: 10) {
                Text("THEME")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)

                HStack(spacing: 10) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                settingsVM.settings.appAppearance = appearance
                                settingsVM.saveSettings()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(appearance.previewGradient)
                                        .frame(height: 48)
                                    Text("Aa")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(appearance.previewTextColor)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            settingsVM.settings.appAppearance == appearance
                                                ? .indigo : .clear,
                                            lineWidth: 2.5
                                        )
                                )

                                Text(appearance.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(
                                        settingsVM.settings.appAppearance == appearance
                                            ? .indigo : .secondary
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            GlassSeparator(isDark: isDark)

            SettingsToggleRow(
                icon: "moon.stars.fill",
                iconColor: .indigo,
                title: "Auto Night Mode",
                isOn: $settingsVM.settings.autoNightMode,
                isDark: isDark
            )
        }
    }

    // MARK: - Reading
    private var readingSection: some View {
        GlassSection("Reading") {
            SettingsNavRow(icon: "textformat", iconColor: .blue,
                           title: "Font & Typography", isDark: isDark) {
                FontSettingsView()
            }

            GlassSeparator(isDark: isDark)

            SettingsNavRow(icon: "paintpalette.fill", iconColor: .orange,
                           title: "Reading Themes", isDark: isDark) {
                ThemeSettingsView()
            }

            GlassSeparator(isDark: isDark)

            // Font size inline slider
            HStack(spacing: 12) {
                Image(systemName: "textformat.size.smaller")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Font Size")
                        .font(.subheadline)
                    Slider(value: $settingsVM.settings.fontSize, in: 12...36, step: 1)
                        .tint(.indigo)
                        .onChange(of: settingsVM.settings.fontSize) { _, _ in settingsVM.saveSettings() }
                }

                Text("\(Int(settingsVM.settings.fontSize))pt")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.indigo)
                    .frame(minWidth: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            GlassSeparator(isDark: isDark)

            SettingsToggleRow(
                icon: "sun.max.fill",
                iconColor: .yellow,
                title: "Keep Screen On",
                isOn: $settingsVM.settings.keepScreenOn,
                isDark: isDark
            )

            GlassSeparator(isDark: isDark)

            // View style picker
            HStack {
                SettingsIconLabel(icon: "rectangle.grid.1x2.fill", color: .cyan, isDark: isDark)
                Text("Library View")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $settingsVM.settings.viewStyle) {
                    ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .onChange(of: settingsVM.settings.viewStyle) { _, _ in settingsVM.saveSettings() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Audio
    private var audioSection: some View {
        GlassSection("Audio") {
            // Speed picker
            HStack {
                SettingsIconLabel(icon: "gauge.with.needle.fill", color: .green, isDark: isDark)
                Text("Default Speed")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $settingsVM.settings.defaultPlaybackSpeed) {
                    ForEach(SettingsViewModel.playbackSpeeds, id: \.self) { speed in
                        Text("\(speed, specifier: "%.1f")x").tag(speed)
                    }
                }
                .pickerStyle(.menu)
                .tint(.indigo)
                .onChange(of: settingsVM.settings.defaultPlaybackSpeed) { _, _ in settingsVM.saveSettings() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            GlassSeparator(isDark: isDark)

            SettingsValueRow(icon: "goforward.30", iconColor: .mint,
                             title: "Skip Forward",
                             value: "\(Int(settingsVM.settings.skipForwardInterval))s",
                             isDark: isDark)

            GlassSeparator(isDark: isDark)

            SettingsValueRow(icon: "gobackward.15", iconColor: .teal,
                             title: "Skip Backward",
                             value: "\(Int(settingsVM.settings.skipBackwardInterval))s",
                             isDark: isDark)

            GlassSeparator(isDark: isDark)

            SettingsToggleRow(
                icon: "play.circle.fill",
                iconColor: .purple,
                title: "Auto-Play Audio",
                isOn: $settingsVM.settings.autoPlayAudio,
                isDark: isDark
            )
        }
    }

    // MARK: - Storage
    private var storageSection: some View {
        GlassSection("Storage") {
            SettingsValueRow(icon: "books.vertical.fill", iconColor: .indigo,
                             title: "Books Stored",
                             value: "\(settingsVM.bookCount)",
                             isDark: isDark)

            GlassSeparator(isDark: isDark)

            Button {
                showingResetConfirm = true
            } label: {
                HStack {
                    SettingsIconLabel(icon: "arrow.counterclockwise", color: .red, isDark: isDark)
                    Text("Reset All Settings")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        GlassSection("About") {
            SettingsValueRow(icon: "info.circle.fill", iconColor: .gray,
                             title: "Version", value: "1.0.0", isDark: isDark)

            GlassSeparator(isDark: isDark)

            SettingsNavRow(icon: "book.closed.fill", iconColor: .indigo,
                           title: "About ReadIO", isDark: isDark) {
                AboutView()
            }

            GlassSeparator(isDark: isDark)

            SettingsNavRow(icon: "star.fill", iconColor: .yellow,
                           title: "Rate on App Store", isDark: isDark) {
                Text("App Store").navigationTitle("Rate")
            }
        }
    }
}

// MARK: - Glass Section Container
// Wraps content in a LiquidGlass rounded rectangle with a header label.
@available(iOS 26.0, *)
struct GlassSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                content
            }
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }
}

// MARK: - Separator
struct GlassSeparator: View {
    let isDark: Bool
    var body: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}

// MARK: - Row Components

struct SettingsIconLabel: View {
    let icon: String
    let color: Color
    let isDark: Bool

    var body: some View {
        Image(systemName: icon)
            .font(.body)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .padding(.trailing, 8)
    }
}

@available(iOS 26.0, *)
struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    let isDark: Bool

    var body: some View {
        HStack {
            SettingsIconLabel(icon: icon, color: iconColor, isDark: isDark)
            Text(title).font(.subheadline)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct SettingsValueRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let isDark: Bool

    var body: some View {
        HStack {
            SettingsIconLabel(icon: icon, color: iconColor, isDark: isDark)
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

@available(iOS 26.0, *)
struct SettingsNavRow<Destination: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let isDark: Bool
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                SettingsIconLabel(icon: icon, color: iconColor, isDark: isDark)
                Text(title).font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AppAppearance Display Extensions
extension AppAppearance {
    var displayName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var previewGradient: LinearGradient {
        switch self {
        case .system:
            return LinearGradient(
                colors: [Color(hex: "1C1C1E"), Color(hex: "FFFFFF")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .light:
            return LinearGradient(colors: [.white], startPoint: .top, endPoint: .bottom)
        case .dark:
            return LinearGradient(colors: [Color(hex: "1C1C1E")], startPoint: .top, endPoint: .bottom)
        }
    }

    var previewTextColor: Color {
        switch self {
        case .system: return .white
        case .light: return Color(hex: "1C1C1E")
        case .dark: return Color(hex: "E5E5E7")
        }
    }
}

// MARK: - Color Hex Init
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .init(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Font Settings
@available(iOS 26.0, *)
struct FontSettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        Form {
            Section("Font Family") {
                Picker("Family", selection: $settingsVM.settings.fontFamily) {
                    ForEach(SettingsViewModel.availableFonts, id: \.self) { font in
                        Text(font).font(.custom(font, size: 16)).tag(font)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: settingsVM.settings.fontFamily) { _, _ in settingsVM.saveSettings() }
            }

            Section("Preview") {
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.custom(settingsVM.settings.fontFamily, size: settingsVM.settings.fontSize))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            Section("Spacing") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Spacing: \(settingsVM.settings.lineSpacing, specifier: "%.1f")")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settingsVM.settings.lineSpacing, in: 1.0...3.0, step: 0.1)
                }
                .onChange(of: settingsVM.settings.lineSpacing) { _, _ in settingsVM.saveSettings() }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Margins: \(Int(settingsVM.settings.margins))pt")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settingsVM.settings.margins, in: 12...48, step: 4)
                }
                .onChange(of: settingsVM.settings.margins) { _, _ in settingsVM.saveSettings() }
            }
        }
        .navigationTitle("Font & Typography")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme Settings
@available(iOS 26.0, *)
struct ThemeSettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        Form {
            Section("Built-in Themes") {
                ForEach(ReadingTheme.builtInThemes) { theme in
                    Button { settingsVM.selectTheme(theme) } label: {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.backgroundColor.color)
                                .frame(width: 50, height: 36)
                                .overlay(Text("Aa").font(.headline).foregroundStyle(theme.textColor.color))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(.systemGray4), lineWidth: 0.5))
                            Text(theme.name).font(.subheadline.weight(.medium))
                            Spacer()
                            if settingsVM.currentTheme.id == theme.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About
@available(iOS 26.0, *)
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.indigo)
                    .padding(.top, 40)

                Text("ReadIO").font(.largeTitle.weight(.bold))
                Text("Your reading and listening companion")
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    aboutRow("book", "Multi-format reading (EPUB, PDF, MOBI)")
                    aboutRow("headphones", "Integrated audiobook playback")
                    aboutRow("paintpalette", "Customizable reading themes")
                    aboutRow("bookmark", "Bookmarks & highlights")
                    aboutRow("icloud", "Sync across devices (coming soon)")
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Text("Built with Liquid Glass for iOS 26")
                    .font(.caption).foregroundStyle(.tertiary).padding(.top, 20)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(.indigo).frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}
