import SwiftUI
import PDFKit

@available(iOS 26.0, *)
struct ReaderView: View {
    let book: Book
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showTOC = false
    @State private var currentPage: Int = 0

    @Namespace private var readerNS

    var body: some View {
        ZStack {
            settingsVM.activeTheme.backgroundColor.color.ignoresSafeArea()
            readerContent
            if showControls {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onTapGesture {
            withAnimation(.smooth(duration: 0.25)) { showControls.toggle() }
        }
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBookmarks) { BookmarksSheet(book: book) }
        .sheet(isPresented: $showTOC) { TOCSheet(book: book) }
        .onAppear {
            currentPage = book.readingProgress.currentPage
            if book.audiobook != nil { audioPlayerVM.loadAudio(for: book) }
        }
        .onDisappear { saveProgress() }
    }

    // MARK: - Reader Content
    @ViewBuilder
    private var readerContent: some View {
        switch book.fileFormat {
        case .pdf:
            PDFReaderView(filePath: book.filePath)
        case .epub, .mobi:
            ScrollView {
                Text(sampleContent)
                    .font(.custom(settingsVM.settings.fontFamily, size: settingsVM.settings.fontSize))
                    .foregroundStyle(settingsVM.activeTheme.textColor.color)
                    .lineSpacing(settingsVM.settings.fontSize * (settingsVM.settings.lineSpacing - 1))
                    .padding(.horizontal, settingsVM.settings.margins)
                    .padding(.vertical, 80)
            }
            .gesture(DragGesture(minimumDistance: 50).onEnded { v in
                if v.translation.width < -50 { nextPage() }
                else if v.translation.width > 50 { prevPage() }
            })
        }
    }

    // MARK: - Top Bar
    // Floating glass controls at top. GlassEffectContainer groups
    // the tool buttons so they morph into a single glass shape.
    private var topBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("back", in: readerNS)

                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)

                Spacer()

                // Tool cluster: morphs into single capsule
                HStack(spacing: 0) {
                    toolButton("list.bullet") { showTOC = true }
                    toolButton(bookmarked ? "bookmark.fill" : "bookmark") { addBookmark() }
                    toolButton("textformat.size") { showSettings = true }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    @ViewBuilder
    private func toolButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 40, height: 40)
                .contentTransition(.symbolEffect(.replace))
        }
        .glassEffect(.regular.interactive())
        .glassEffectID(icon, in: readerNS)
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if book.audiobook != nil { audioStrip }
            progressBar
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    // MARK: - Audio Strip
    // Each transport button is a glass circle inside a GlassEffectContainer.
    // Play/pause gets a tinted glass circle (semantic: primary action).
    private var audioStrip: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 16) {
                Button { audioPlayerVM.skipBackward() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.body).frame(width: 36, height: 36)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Button { audioPlayerVM.togglePlayPause() } label: {
                    Image(systemName: audioPlayerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.tint(.indigo).interactive(), in: .circle)

                Button { audioPlayerVM.skipForward() } label: {
                    Image(systemName: "goforward.30")
                        .font(.body).frame(width: 36, height: 36)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Spacer()

                Text(AudioPlayerViewModel.formatTime(audioPlayerVM.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button { cycleSpeed() } label: {
                    Text("\(audioPlayerVM.playbackSpeed, specifier: "%.1f")x")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Progress Bar (glass capsule at bottom)
    private var progressBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { Double(currentPage) },
                               set: { currentPage = Int($0) }),
                in: 0...Double(max(1, book.readingProgress.totalPages - 1)),
                step: 1
            ).tint(.indigo)

            HStack {
                Text("Page \(currentPage + 1) of \(max(1, book.readingProgress.totalPages))")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(book.readingProgress.percentage))%")
                    .font(.caption2.weight(.medium)).foregroundStyle(.indigo)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers
    private var bookmarked: Bool {
        book.bookmarks.contains { $0.page == currentPage }
    }

    private func addBookmark() {
        let bm = Bookmark(position: "\(currentPage)", chapter: book.readingProgress.currentChapter,
                          page: currentPage, title: "Page \(currentPage + 1)")
        libraryVM.addBookmark(to: book.id, bookmark: bm)
    }

    private func nextPage() {
        if currentPage < book.readingProgress.totalPages - 1 {
            withAnimation(.smooth) { currentPage += 1 }
        }
    }
    private func prevPage() {
        if currentPage > 0 { withAnimation(.smooth) { currentPage -= 1 } }
    }

    private func cycleSpeed() {
        let s = SettingsViewModel.playbackSpeeds
        if let i = s.firstIndex(of: audioPlayerVM.playbackSpeed) {
            audioPlayerVM.setPlaybackSpeed(s[(i + 1) % s.count])
        }
    }

    private func saveProgress() {
        let total = max(book.readingProgress.totalPages, 1)
        let pct = Double(currentPage) / Double(total) * 100
        let p = ReadingProgress(currentChapter: book.readingProgress.currentChapter,
            currentPage: currentPage, totalPages: total,
            percentage: min(pct, 100), lastPosition: "\(currentPage)", lastUpdated: Date())
        libraryVM.updateProgress(for: book.id, progress: p)
    }

    private var sampleContent: String {
        """
        Welcome to ReadListen — your reading and listening companion.

        Your book "\(book.title)" by \(book.author) will be rendered here with your preferred font, size, and theme settings.

        In the full implementation, EPUB files are parsed using a reader library like Readium, extracting chapters, metadata, and formatting. PDFs render through Apple's PDFKit. MOBI files are converted to EPUB at import.

        Swipe left or right to turn pages. Tap anywhere to show or hide the floating Liquid Glass controls. The controls form a distinct functional layer above the reading surface — they're translucent, they refract your content at the edges, and they catch specular highlights from the ambient environment.

        If this book has a linked audiobook, playback controls float above the page — letting you switch between reading and listening without losing your place.

        Happy reading!
        """
    }
}

// MARK: - PDF Reader
struct PDFReaderView: UIViewRepresentable {
    let filePath: String
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.displayDirection = .horizontal
        v.usePageViewController(true)
        if let doc = PDFDocument(url: URL(fileURLWithPath: filePath)) { v.document = doc }
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

// MARK: - Reader Settings Sheet
@available(iOS 26.0, *)
struct ReaderSettingsSheet: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ReadingTheme.builtInThemes) { theme in
                                Button { settingsVM.selectTheme(theme) } label: {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(theme.backgroundColor.color)
                                            .frame(width: 60, height: 44)
                                            .overlay(Text("Aa").font(.headline).foregroundStyle(theme.textColor.color))
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(settingsVM.currentTheme.id == theme.id ? .indigo : Color(.systemGray4),
                                                              lineWidth: settingsVM.currentTheme.id == theme.id ? 2.5 : 1))
                                        Text(theme.name).font(.caption2)
                                            .foregroundStyle(settingsVM.currentTheme.id == theme.id ? .indigo : .secondary)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }

                Section("Font") {
                    Picker("Family", selection: $settingsVM.settings.fontFamily) {
                        ForEach(SettingsViewModel.availableFonts, id: \.self) {
                            Text($0).font(.custom($0, size: 16)).tag($0)
                        }
                    }
                }

                Section("Size & Spacing") {
                    HStack {
                        Text("A").font(.caption)
                        Slider(value: $settingsVM.settings.fontSize, in: 12...36, step: 1)
                            .onChange(of: settingsVM.settings.fontSize) { _, _ in settingsVM.saveSettings() }
                        Text("A").font(.title2)
                    }
                    HStack {
                        Image(systemName: "text.alignleft")
                        Slider(value: $settingsVM.settings.lineSpacing, in: 1.0...3.0, step: 0.1)
                            .onChange(of: settingsVM.settings.lineSpacing) { _, _ in settingsVM.saveSettings() }
                        Image(systemName: "text.alignleft").imageScale(.large)
                    }
                }

                Section("Night Mode") {
                    Toggle("Auto Night Mode", isOn: $settingsVM.settings.autoNightMode)
                        .onChange(of: settingsVM.settings.autoNightMode) { _, _ in settingsVM.saveSettings() }
                }
            }
            .navigationTitle("Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Bookmarks Sheet
@available(iOS 26.0, *)
struct BookmarksSheet: View {
    let book: Book
    @EnvironmentObject var libraryVM: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if book.bookmarks.isEmpty && book.highlights.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                        description: Text("Tap the bookmark icon while reading."))
                } else {
                    List {
                        if !book.bookmarks.isEmpty {
                            Section("Bookmarks") {
                                ForEach(book.bookmarks) { bm in
                                    HStack {
                                        Image(systemName: "bookmark.fill").foregroundStyle(bm.color.color)
                                        VStack(alignment: .leading) {
                                            Text(bm.title ?? "Page \(bm.page + 1)").font(.subheadline.weight(.medium))
                                            if let n = bm.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Text(bm.dateCreated, style: .date).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        if !book.highlights.isEmpty {
                            Section("Highlights") {
                                ForEach(book.highlights) { h in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(h.text).font(.subheadline).padding(8)
                                            .background(h.color.color.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        if let n = h.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks & Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - TOC Sheet
@available(iOS 26.0, *)
struct TOCSheet: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Table of Contents", systemImage: "list.bullet",
                description: Text("Chapters will be extracted from the book's metadata."))
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
