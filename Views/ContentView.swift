import SwiftUI

@available(iOS 26.0, *)
struct ContentView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel

    @State private var selectedTab: Tab = .library
    @Namespace private var tabNS

    enum Tab: String, CaseIterable {
        case library, audioPlayer, settings

        var icon: String {
            switch self {
            case .library: return "books.vertical.fill"
            case .audioPlayer: return "headphones"
            case .settings: return "gearshape.fill"
            }
        }

        var label: String {
            switch self {
            case .library: return "Library"
            case .audioPlayer: return "Playing"
            case .settings: return "Settings"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active screen
            Group {
                switch selectedTab {
                case .library: LibraryView()
                case .audioPlayer: AudioPlayerView()
                case .settings: SettingsView()
                }
            }

            // Bottom stack: mini player + bubble tabs
            VStack(spacing: 8) {
                // Mini player (when audio active and not on player tab)
                if audioPlayerVM.isLoaded && selectedTab != .audioPlayer {
                    miniPlayer
                }

                // Floating bubble tab bar
                bubbleTabBar
            }
            .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Bubble Tab Bar
    // Each tab is its own glass bubble. The active tab expands
    // to show its label, creating a pill shape. Inactive tabs
    // are compact circles. All are individual glass elements.
    private var bubbleTabBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 10) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.smooth(duration: 0.35)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.body.weight(.medium))
                                .foregroundStyle(selectedTab == tab ? .indigo : .secondary)

                            if selectedTab == tab {
                                Text(tab.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.indigo)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        .padding(.horizontal, selectedTab == tab ? 18 : 14)
                        .padding(.vertical, 12)
                    }
                    .glassEffect(
                        selectedTab == tab
                            ? .regular.tint(.indigo).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                    .glassEffectID(tab.rawValue, in: tabNS)
                }
            }
        }
    }

    // MARK: - Mini Player
    private var miniPlayer: some View {
        Button {
            withAnimation(.smooth) { selectedTab = .audioPlayer }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .symbolEffect(.variableColor.iterative, isActive: audioPlayerVM.isPlaying)

                VStack(alignment: .leading, spacing: 1) {
                    Text(audioPlayerVM.currentChapterTitle.isEmpty
                         ? "Now Playing"
                         : audioPlayerVM.currentChapterTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(AudioPlayerViewModel.formatTime(audioPlayerVM.currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress bar
                ProgressView(value: audioPlayerVM.currentTime,
                             total: max(1, audioPlayerVM.duration))
                    .tint(.indigo)
                    .frame(width: 48)
                    .scaleEffect(y: 0.5)

                Button {
                    audioPlayerVM.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 34, height: 34)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
    }
}
