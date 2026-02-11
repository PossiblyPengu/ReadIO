import SwiftUI
import UIKit
import UniformTypeIdentifiers

@available(iOS 26.0, *)
struct LibraryView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var audioPlayerVM: AudioPlayerViewModel

    @State private var showingImporter = false
    @State private var showingAudioImporter = false
    @State private var selectedBookForAudio: Book?
    @State private var selectedBook: Book?
    @State private var showingDeleteConfirm = false
    @State private var bookToDelete: Book?
    @State private var showingCoverPicker = false
    @State private var bookForCoverPicker: Book?

    @Namespace private var filterNS

    let columns = [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .searchable(text: $libraryVM.searchText, prompt: "Search books...")
                .toolbar { toolbarContent }
                .fileImporter(isPresented: $showingImporter,
                    allowedContentTypes: LibraryViewModel.supportedBookTypes,
                    allowsMultipleSelection: true) { handleBookImport($0) }
                .fileImporter(isPresented: $showingAudioImporter,
                    allowedContentTypes: LibraryViewModel.supportedAudioTypes,
                    allowsMultipleSelection: true) { handleAudioImport($0) }
                .fullScreenCover(item: $selectedBook) { ReaderView(book: $0) }
                .alert("Delete Book", isPresented: $showingDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        if let b = bookToDelete { libraryVM.removeBook(b) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Delete \"\(bookToDelete?.title ?? "")\" and any linked audio?")
                }
                .sheet(isPresented: $showingCoverPicker) {
                    if let book = bookForCoverPicker {
                        CoverPickerView(book: book) { imageData in
                            libraryVM.updateCover(for: book.id, imageData: imageData)
                        } onRemove: {
                            Task { await libraryVM.removeCover(for: book.id) }
                        }
                    }
                }
                .onAppear { libraryVM.enrichAllPending() }
        }
    }

    // MARK: - Content
    @ViewBuilder
    private var content: some View {
        if libraryVM.filteredBooks.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    filterBar.padding(.top, 4)
                    if settingsVM.settings.viewStyle == .grid {
                        gridView
                    } else {
                        listView
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar
    // GlassEffectContainer: filters within spacing distance morph together.
    // Active filter gets tinted glass; inactive gets regular glass.
    // The glassEffectID enables smooth morphing transitions between states.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(LibraryViewModel.BookFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                libraryVM.selectedFilter = filter
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.subheadline.weight(
                                    libraryVM.selectedFilter == filter ? .semibold : .regular
                                ))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .glassEffect(
                            libraryVM.selectedFilter == filter
                                ? .regular.tint(.indigo)  // Tint = semantic meaning
                                : .regular,
                            in: .capsule
                        )
                        .glassEffectID(filter.rawValue, in: filterNS) // Morph tracking
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Grid
    // Content: NO glass. Clean, readable cards.
    // Only badges (audio icon, fav heart) use small glass circles
    // because they're floating controls over cover art.
    private var gridView: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(libraryVM.filteredBooks) { book in
                BookCard(book: book)
                    .onTapGesture { selectedBook = book }
                    .contextMenu { contextMenu(for: book) }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 100)
    }

    // MARK: - List
    private var listView: some View {
        LazyVStack(spacing: 2) {
            ForEach(libraryVM.filteredBooks) { book in
                BookRow(book: book)
                    .onTapGesture { selectedBook = book }
                    .contextMenu { contextMenu(for: book) }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 100)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No Books Yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Import EPUB, PDF, or MOBI files\nto start reading")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button { showingImporter = true } label: {
                Label("Import Books", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .glassEffect(.regular.tint(.indigo).interactive(), in: .capsule)
            Spacer()
        }
    }

    // MARK: - Context Menu
    @ViewBuilder
    private func contextMenu(for book: Book) -> some View {
        Button { libraryVM.toggleFavorite(book) } label: {
            Label(book.isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: book.isFavorite ? "heart.slash" : "heart")
        }
        Button {
            selectedBookForAudio = book
            showingAudioImporter = true
        } label: {
            Label(book.audiobook != nil ? "Replace Audio" : "Link Audiobook",
                  systemImage: "headphones")
        }
        Button { libraryVM.refetchMetadata(for: book) } label: {
            Label("Refresh Metadata", systemImage: "arrow.triangle.2.circlepath")
        }
        Button {
            bookForCoverPicker = book
            showingCoverPicker = true
        } label: {
            Label("Choose Cover", systemImage: "photo.on.rectangle")
        }
        Divider()
        Button(role: .destructive) {
            bookToDelete = book
            showingDeleteConfirm = true
        } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Toolbar
    // iOS 26 toolbars get Liquid Glass automatically.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingImporter = true } label: {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Section("View") {
                    ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                        Button {
                            settingsVM.settings.viewStyle = style
                            settingsVM.saveSettings()
                        } label: {
                            Label(style.rawValue,
                                  systemImage: style == .grid ? "square.grid.2x2" : "list.bullet")
                            if settingsVM.settings.viewStyle == style {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    // MARK: - Import Handlers
    private func handleBookImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            urls.forEach { libraryVM.importBook(from: $0) }
        }
    }
    private func handleAudioImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let book = selectedBookForAudio {
            libraryVM.importAudioFiles(for: book.id, urls: urls)
        }
    }
}

// MARK: - Book Grid Card
// Content card — no glass on the card itself. Clean hierarchy.
// Shows fetched cover art when available, gradient fallback otherwise.
// Small glass badges float over the cover for audio/fav indicators.
@available(iOS 26.0, *)
struct BookCard: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Cover image or gradient fallback
                if let coverPath = book.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(0.65, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    // Gradient fallback with format icon
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: gradient(for: book),
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .aspectRatio(0.65, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: book.fileFormat.iconName)
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.75))
                                Text(book.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .padding(.horizontal, 8)
                            }
                        }
                }

                // Metadata fetching indicator
                if !book.metadataFetched {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(6)
                        }
                    }
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .overlay(alignment: .topTrailing) {
                if book.audiobook != nil {
                    Image(systemName: "headphones")
                        .font(.caption2.weight(.semibold))
                        .padding(6)
                        .glassEffect(.regular.tint(.indigo), in: .circle)
                        .offset(x: 4, y: -4)
                }
            }
            .overlay(alignment: .topLeading) {
                if book.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(6)
                        .glassEffect(.regular, in: .circle)
                        .offset(x: -4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(book.author).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if book.readingProgress.percentage > 0 {
                ProgressView(value: book.readingProgress.percentage, total: 100)
                    .tint(.indigo).scaleEffect(y: 0.6)
            }
        }
    }

    private func gradient(for book: Book) -> [Color] {
        let h = Double(abs(book.title.hashValue) % 360) / 360
        return [
            Color(hue: h, saturation: 0.55, brightness: 0.5),
            Color(hue: (h + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.3)
        ]
    }
}

// MARK: - Book List Row
@available(iOS 26.0, *)
struct BookRow: View {
    let book: Book
    var body: some View {
        HStack(spacing: 14) {
            // Cover thumbnail or gradient fallback
            if let coverPath = book.coverImagePath,
               let uiImage = UIImage(contentsOfFile: coverPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.indigo.opacity(0.15), .purple.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 50, height: 70)
                    .overlay(Image(systemName: book.fileFormat.iconName).foregroundStyle(.indigo))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(1)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text(book.fileFormat.displayName).font(.caption).foregroundStyle(.tertiary)
                    if book.audiobook != nil {
                        Label("Audio", systemImage: "headphones").font(.caption).foregroundStyle(.indigo)
                    }
                    if book.readingProgress.percentage > 0 {
                        Text("\(Int(book.readingProgress.percentage))%")
                            .font(.caption.weight(.medium)).foregroundStyle(.indigo)
                    }
                    if !book.metadataFetched {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
            Spacer()
            if book.isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.red).font(.caption)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.quaternary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
