import Foundation
import SwiftUI
import UniformTypeIdentifiers

class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: BookFilter = .all
    @Published var isImporting: Bool = false
    @Published var importError: String?

    private let storageService = StorageService.shared

    enum BookFilter: String, CaseIterable {
        case all = "All"
        case reading = "Reading"
        case favorites = "Favorites"
        case audiobooks = "Audiobooks"
        case epub = "EPUB"
        case pdf = "PDF"
        case mobi = "MOBI"
    }

    var filteredBooks: [Book] {
        var result = books

        // Apply filter
        switch selectedFilter {
        case .all: break
        case .reading:
            result = result.filter { $0.readingProgress.percentage > 0 && $0.readingProgress.percentage < 100 }
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .audiobooks:
            result = result.filter { $0.audiobook != nil }
        case .epub:
            result = result.filter { $0.fileFormat == .epub }
        case .pdf:
            result = result.filter { $0.fileFormat == .pdf }
        case .mobi:
            result = result.filter { $0.fileFormat == .mobi }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    init() {
        loadBooks()
    }

    func loadBooks() {
        books = storageService.loadBooks()
    }

    func saveBooks() {
        storageService.saveBooks(books)
    }

    func addBook(_ book: Book) {
        books.append(book)
        saveBooks()
    }

    func removeBook(_ book: Book) {
        books.removeAll { $0.id == book.id }
        // Clean up stored files
        storageService.deleteBookFiles(book)
        saveBooks()
    }

    func toggleFavorite(_ book: Book) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index].isFavorite.toggle()
            saveBooks()
        }
    }

    /// Update a book's cover image from user-selected data (cover picker).
    func updateCover(for bookId: UUID, imageData: Data) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        if let path = storageService.saveCoverImage(imageData, for: bookId) {
            books[index].coverImagePath = path
            saveBooks()
        }
    }

    func updateProgress(for bookId: UUID, progress: ReadingProgress) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].readingProgress = progress
            books[index].lastOpened = Date()
            saveBooks()
        }
    }

    func addBookmark(to bookId: UUID, bookmark: Bookmark) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].bookmarks.append(bookmark)
            saveBooks()
        }
    }

    func removeBookmark(from bookId: UUID, bookmarkId: UUID) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].bookmarks.removeAll { $0.id == bookmarkId }
            saveBooks()
        }
    }

    func addHighlight(to bookId: UUID, highlight: Highlight) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].highlights.append(highlight)
            saveBooks()
        }
    }

    func removeHighlight(from bookId: UUID, highlightId: UUID) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].highlights.removeAll { $0.id == highlightId }
            saveBooks()
        }
    }

    func linkAudiobook(to bookId: UUID, audioInfo: AudiobookInfo) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].audiobook = audioInfo
            saveBooks()
        }
    }

    /// Import a book file: copies to documents, adds with filename title,
    /// then kicks off async metadata fetch (embedded + API).
    func importBook(from url: URL) {
        let ext = url.pathExtension.lowercased()

        guard let format = BookFormat.allCases.first(where: { $0.supportedExtensions.contains(ext) }) else {
            importError = "Unsupported file format: .\(ext)"
            return
        }

        // Copy file to app's documents directory
        let destinationURL = storageService.copyFileToDocuments(url)

        guard let savedURL = destinationURL else {
            importError = "Failed to import file"
            return
        }

        // Create book with filename-derived title (instant, no network wait)
        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        var book = Book(
            title: title,
            filePath: savedURL.path,
            fileFormat: format
        )

        addBook(book)

        // Fetch metadata in background — UI updates when done
        Task {
            await enrichMetadata(for: book.id, fileURL: savedURL, format: format)
        }
    }

    // MARK: - Metadata Enrichment

    /// Fetch metadata from embedded file data + Google Books + Open Library,
    /// then merge into the existing book record.
    @MainActor
    func enrichMetadata(for bookId: UUID, fileURL: URL, format: BookFormat) async {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }

        // Mark as fetching (UI can show spinner)
        books[index].metadataFetched = false

        let meta = await MetadataService.shared.fetchMetadata(forFileAt: fileURL, format: format)

        // Also fetch all available cover options from both APIs
        let isbn = meta.isbn13 ?? meta.isbn10
        let coverOptions = await MetadataService.shared.fetchCoverOptions(
            title: meta.title,
            author: meta.authors?.first,
            isbn: isbn
        )

        // Re-find index (array may have changed)
        guard let idx = books.firstIndex(where: { $0.id == bookId }) else { return }

        // Apply metadata — embedded/API values override filename-derived title
        if let title = meta.title, !title.isEmpty {
            books[idx].title = title
        }
        if let author = meta.author, !author.isEmpty, author != "Unknown Author" {
            books[idx].author = author
        }
        books[idx].bookDescription = meta.description ?? books[idx].bookDescription
        books[idx].publisher = meta.publisher ?? books[idx].publisher
        books[idx].publishedDate = meta.publishedDate ?? books[idx].publishedDate
        books[idx].pageCount = meta.pageCount ?? books[idx].pageCount
        books[idx].isbn = meta.isbn13 ?? meta.isbn10 ?? books[idx].isbn
        books[idx].categories = meta.categories ?? books[idx].categories
        books[idx].language = meta.language ?? books[idx].language
        books[idx].averageRating = meta.averageRating ?? books[idx].averageRating
        books[idx].ratingsCount = meta.ratingsCount ?? books[idx].ratingsCount

        // Convert CoverOption → CoverOptionInfo for persistence
        books[idx].coverOptions = coverOptions.map { opt in
            CoverOptionInfo(
                source: opt.label,
                thumbnailURL: opt.thumbnailURL.absoluteString,
                fullURL: opt.fullURL.absoluteString
            )
        }

        // Save cover image to documents (auto-select first available)
        if let imageData = meta.coverImageData {
            let coverPath = storageService.saveCoverImage(imageData, for: bookId)
            books[idx].coverImagePath = coverPath
        }

        books[idx].metadataFetched = true
        saveBooks()
    }

    /// Select a specific cover from the available options.
    /// Downloads the full-res image and saves it as the book's cover.
    @MainActor
    func selectCover(for bookId: UUID, option: CoverOptionInfo) async {
        guard let idx = books.firstIndex(where: { $0.id == bookId }),
              let url = URL(string: option.fullURL) else { return }

        // Download the full-resolution cover
        if let imageData = await MetadataService.shared.downloadImage(from: url) {
            if let coverPath = storageService.saveCoverImage(imageData, for: bookId) {
                books[idx].coverImagePath = coverPath
                saveBooks()
            }
        }
    }

    /// Remove the cover image for a book (revert to gradient placeholder).
    @MainActor
    func removeCover(for bookId: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[idx].coverImagePath = nil
        saveBooks()
    }

    /// Retry metadata fetch for a specific book (e.g. if first attempt failed
    /// or user wants to refresh).
    func refetchMetadata(for book: Book) {
        guard let fileURL = URL(string: book.filePath) ?? storageService.fileURL(for: book) else { return }
        Task {
            await enrichMetadata(for: book.id, fileURL: fileURL, format: book.fileFormat)
        }
    }

    /// Fetch metadata for all books that haven't been enriched yet.
    /// Called on app launch to catch any imports that failed previously.
    func enrichAllPending() {
        let pending = books.filter { !$0.metadataFetched }
        for book in pending {
            refetchMetadata(for: book)
        }
    }

    func importAudioFiles(for bookId: UUID, urls: [URL]) {
        var audioPaths: [String] = []

        for url in urls {
            if let savedURL = storageService.copyFileToDocuments(url) {
                audioPaths.append(savedURL.path)
            }
        }

        guard !audioPaths.isEmpty else {
            importError = "Failed to import audio files"
            return
        }

        let audioInfo = AudiobookInfo(
            audioFilePaths: audioPaths,
            totalDuration: 0, // Will be calculated when audio loads
            currentTime: 0,
            currentTrack: 0
        )

        linkAudiobook(to: bookId, audioInfo: audioInfo)
    }

    // Supported UTTypes for file import
    static var supportedBookTypes: [UTType] {
        [
            UTType(filenameExtension: "epub") ?? .data,
            .pdf,
            UTType(filenameExtension: "mobi") ?? .data,
            UTType(filenameExtension: "azw") ?? .data,
            UTType(filenameExtension: "azw3") ?? .data,
        ]
    }

    static var supportedAudioTypes: [UTType] {
        [
            .mp3,
            .mpeg4Audio,
            UTType(filenameExtension: "m4b") ?? .data,
            .aiff,
            .wav,
            UTType(filenameExtension: "flac") ?? .data,
        ]
    }
}
