import SwiftUI

@available(iOS 26.0, *)
struct AudioPlayerView: View {
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    @Namespace private var playerNS
    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showChapters = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Ambient background: MeshGradient gives the glass
                // material something colorful to refract and reflect.
                // This is a key design choice — glass looks flat over
                // plain backgrounds but comes alive over gradients.
                ambientBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        coverArt
                            .padding(.top, 20)
                            .padding(.bottom, 28)

                        trackInfo
                            .padding(.bottom, 24)

                        progressSection
                            .padding(.horizontal, 28)
                            .padding(.bottom, 32)

                        transportControls
                            .padding(.bottom, 24)

                        secondaryControls
                            .padding(.bottom, 40)
                    }
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSpeedPicker) { SpeedPickerSheet() }
            .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
            .sheet(isPresented: $showChapters) { ChapterListSheet() }
        }
    }

    // MARK: - Ambient Background
    // MeshGradient: iOS 26+ feature that creates organic color fields.
    // The glass controls above it will refract these colors at their edges,
    // creating the signature Liquid Glass look.
    private var ambientBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .indigo.opacity(0.15), .blue.opacity(0.08), .purple.opacity(0.12),
                .cyan.opacity(0.06),   .indigo.opacity(0.04), .pink.opacity(0.08),
                .blue.opacity(0.10),   .purple.opacity(0.06), .indigo.opacity(0.10)
            ]
        )
    }

    // MARK: - Cover Art
    // The cover is content, NOT glass. It sits behind the control layer.
    // The shadow gives it physical presence so the glass controls feel
    // like they float above it.
    private var coverArt: some View {
        VStack(spacing: 0) {
            if let coverPath = audioPlayerVM.currentBook?.coverImagePath,
               let img = UIImage(contentsOfFile: coverPath) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
            } else {
                // Placeholder cover
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.linearGradient(
                        colors: [.indigo.opacity(0.12), .purple.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 260, height: 260)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "headphones")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(.indigo.opacity(0.4))

                            // Animated waveform when playing
                            if audioPlayerVM.isPlaying {
                                Image(systemName: "waveform")
                                    .font(.title2)
                                    .foregroundStyle(.indigo.opacity(0.3))
                                    .symbolEffect(.variableColor.iterative, isActive: true)
                            }
                        }
                    }
                    .shadow(color: .indigo.opacity(0.12), radius: 24, y: 12)
            }
        }
    }

    // MARK: - Track Info
    // Plain text, no glass. Content layer.
    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(audioPlayerVM.currentBook?.title ?? "No Book Loaded")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(audioPlayerVM.currentChapterTitle.isEmpty
                 ? (audioPlayerVM.currentBook?.author ?? "Select a book to listen")
                 : audioPlayerVM.currentChapterTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Progress
    // Slider and time labels — content, not glass.
    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { audioPlayerVM.currentTime },
                    set: { audioPlayerVM.seek(to: $0) }
                ),
                in: 0...max(1, audioPlayerVM.duration)
            )
            .tint(.indigo)

            HStack {
                Text(AudioPlayerViewModel.formatTime(audioPlayerVM.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-\(AudioPlayerViewModel.formatTime(audioPlayerVM.duration - audioPlayerVM.currentTime))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Transport Controls
    // GlassEffectContainer groups all transport buttons.
    // When spacing <= threshold, they morph into one continuous
    // glass shape. The play button is tinted indigo (semantic: primary).
    // Each button uses .interactive() for press-scale haptic feedback.
    private var transportControls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 20) {
                // Previous chapter
                Button { audioPlayerVM.previousChapter() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("prev", in: playerNS)

                // Skip backward
                Button { audioPlayerVM.skipBackward() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("skipBack", in: playerNS)

                // Play/Pause — hero button, tinted glass
                Button { audioPlayerVM.togglePlayPause() } label: {
                    Image(systemName: audioPlayerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 62, height: 62)
                }
                .glassEffect(.regular.tint(.indigo).interactive(), in: .circle)
                .glassEffectID("play", in: playerNS)

                // Skip forward
                Button { audioPlayerVM.skipForward() } label: {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("skipFwd", in: playerNS)

                // Next chapter
                Button { audioPlayerVM.nextChapter() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("next", in: playerNS)
            }
        }
    }

    // MARK: - Secondary Controls
    // Separate glass elements for secondary actions.
    // Speed uses capsule shape, others use circles.
    private var secondaryControls: some View {
        HStack(spacing: 16) {
            // Speed
            Button { showSpeedPicker = true } label: {
                Text("\(audioPlayerVM.playbackSpeed, specifier: "%.1f")x")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // Chapters
            Button { showChapters = true } label: {
                Image(systemName: "list.bullet")
                    .font(.body)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            // Sleep timer
            Button { showSleepTimer = true } label: {
                Image(systemName: audioPlayerVM.sleepTimerActive
                      ? "moon.fill" : "moon")
                    .font(.body)
                    .frame(width: 42, height: 42)
                    .foregroundStyle(audioPlayerVM.sleepTimerActive ? .indigo : .primary)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            // AirPlay
            Button {} label: {
                Image(systemName: "airplayaudio")
                    .font(.body)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

// MARK: - Speed Picker Sheet
@available(iOS 26.0, *)
struct SpeedPickerSheet: View {
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsViewModel.playbackSpeeds, id: \.self) { speed in
                    Button {
                        audioPlayerVM.setPlaybackSpeed(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text("\(speed, specifier: "%.1f")x")
                                .font(.body.monospacedDigit())
                            Spacer()
                            if audioPlayerVM.playbackSpeed == speed {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Sleep Timer Sheet
@available(iOS 26.0, *)
struct SleepTimerSheet: View {
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    let options: [(String, TimeInterval?)] = [
        ("Off", nil),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("45 minutes", 2700),
        ("1 hour", 3600),
        ("End of chapter", -1),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.0) { option in
                    Button {
                        if let t = option.1 { audioPlayerVM.setSleepTimer(minutes: t / 60) }
                        else { audioPlayerVM.cancelSleepTimer() }
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.0)
                            Spacer()
                            if audioPlayerVM.sleepTimerActive && option.1 != nil {
                                Image(systemName: "checkmark").foregroundStyle(.indigo)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Chapter List Sheet
@available(iOS 26.0, *)
struct ChapterListSheet: View {
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if audioPlayerVM.chapters.isEmpty {
                ContentUnavailableView("No Chapters",
                    systemImage: "list.bullet",
                    description: Text("Chapter information will appear when an audiobook is loaded."))
            } else {
                List(audioPlayerVM.chapters) { chapter in
                    Button {
                        audioPlayerVM.jumpToChapter(chapter)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title).font(.subheadline.weight(.medium))
                                Text(AudioPlayerViewModel.formatTime(chapter.duration))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if audioPlayerVM.currentChapterTitle == chapter.title {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.indigo)
                                    .symbolEffect(.variableColor.iterative,
                                                   isActive: audioPlayerVM.isPlaying)
                            }
                        }
                    }
                }
            }
            NavigationStack {}.navigationTitle("Chapters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
