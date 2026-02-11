import Foundation

class StorageService {
    static let shared = StorageService()
    private init() {}

    private let booksKey = "readio_books"
    private let settingsKey = "readio_settings"
    private let customThemesKey = "readio_custom_themes"
    private let fileManager = FileManager.default

    // MARK: - Directory Setup

    var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var booksDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Books", isDirectory: true)
        createDirectoryIfNeeded(dir)
        return dir
    }

    var audioDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Audio", isDirectory: true)
        createDirectoryIfNeeded(dir)
        return dir
    }

    var coversDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Covers", isDirectory: true)
        createDirectoryIfNeeded(dir)
        return dir
    }

    private func createDirectoryIfNeeded(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Books CRUD

    func loadBooks() -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: booksKey) else { return [] }
        return (try? JSONDecoder().decode([Book].self, from: data)) ?? []
    }

    func saveBooks(_ books: [Book]) {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: booksKey)
        }
    }

    func deleteBookFiles(_ book: Book) {
        try? fileManager.removeItem(atPath: book.filePath)
        if let coverPath = book.coverImagePath {
            try? fileManager.removeItem(atPath: coverPath)
        }
        if let audioInfo = book.audiobook {
            for path in audioInfo.audioFilePaths {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - Custom Themes

    func loadCustomThemes() -> [ReadingTheme] {
        guard let data = UserDefaults.standard.data(forKey: customThemesKey) else { return [] }
        return (try? JSONDecoder().decode([ReadingTheme].self, from: data)) ?? []
    }

    func saveCustomThemes(_ themes: [ReadingTheme]) {
        if let data = try? JSONEncoder().encode(themes) {
            UserDefaults.standard.set(data, forKey: customThemesKey)
        }
    }

    // MARK: - File Operations

    func copyFileToDocuments(_ sourceURL: URL) -> URL? {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fileName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()

        // Determine target directory
        let targetDir: URL
        if AudioFormat.allExtensions.contains(ext) {
            targetDir = audioDirectory
        } else {
            targetDir = booksDirectory
        }

        var destinationURL = targetDir.appendingPathComponent(fileName)

        // Handle duplicate filenames
        var counter = 1
        while fileManager.fileExists(atPath: destinationURL.path) {
            let name = sourceURL.deletingPathExtension().lastPathComponent
            destinationURL = targetDir.appendingPathComponent("\(name)_\(counter).\(ext)")
            counter += 1
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Failed to copy file: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Storage Size

    func calculateStorageUsed() -> String {
        let dirs = [booksDirectory, audioDirectory, coversDirectory]
        var totalSize: Int64 = 0

        for dir in dirs {
            if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }

        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    // MARK: - Cover Images

    /// Save cover image data to the Covers directory and return the path.
    func saveCoverImage(_ data: Data, for bookId: UUID) -> String? {
        let filename = "\(bookId.uuidString).jpg"
        let url = coversDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url.path
        } catch {
            print("Failed to save cover image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get the file URL for a book's stored file.
    func fileURL(for book: Book) -> URL? {
        let url = URL(fileURLWithPath: book.filePath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
