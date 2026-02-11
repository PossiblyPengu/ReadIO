import Foundation
import UIKit
import PDFKit

// MARK: - Book Metadata Result
/// Consolidated metadata from all sources (embedded + API)
struct BookMetadata {
    var title: String?
    var authors: [String]?
    var description: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var isbn10: String?
    var isbn13: String?
    var categories: [String]?
    var language: String?
    var coverImageURL: URL?
    var coverImageData: Data?
    var averageRating: Double?
    var ratingsCount: Int?

    /// Primary author string
    var author: String? {
        authors?.joined(separator: ", ")
    }

    /// Best available title
    var displayTitle: String {
        title ?? "Unknown Title"
    }
}

// MARK: - Cover Option
/// A single cover image candidate for the user to choose from.
/// Multiple options are gathered from different API results/editions.
struct CoverOption: Identifiable {
    let id = UUID()
    let source: MetadataSource
    let label: String          // e.g. "Google Books", "Open Library — 2003 Edition"
    let thumbnailURL: URL      // Small preview (for picker grid)
    let fullURL: URL           // High-res version (saved when selected)
    var thumbnailData: Data?   // Downloaded thumbnail
    var isSelected: Bool = false
}

// MARK: - Metadata Source Priority
/// Sources are tried in order. Embedded metadata is extracted first (free, instant),
/// then APIs fill in any missing fields (cover art, description, page count, etc.)
enum MetadataSource: String {
    case embedded   // From the file itself (EPUB OPF, PDF properties)
    case googleBooks // Google Books API (free, ~100 req/day without key)
    case openLibrary // Open Library API (free, unlimited, no key)
}

// MARK: - MetadataService
/// Extracts and fetches book metadata automatically on import.
///
/// Strategy:
/// 1. Parse embedded metadata from the file (EPUB: OPF/container.xml, PDF: document properties)
/// 2. Search Google Books API by title+author (or ISBN if found)
/// 3. Fall back to Open Library if Google returns no results
/// 4. Merge all sources: embedded fields take priority, APIs fill gaps
///
/// Usage:
/// ```swift
/// let metadata = await MetadataService.shared.fetchMetadata(
///     forFileAt: fileURL,
///     format: .epub
/// )
/// ```
actor MetadataService {
    static let shared = MetadataService()

    private let session: URLSession
    private let cache = NSCache<NSString, CachedMetadata>()

    /// Optional Google Books API key. Works without one (~100 req/day),
    /// but with a key you get higher quota and full imageLinks.
    var googleBooksAPIKey: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Main Entry Point

    /// Fetch metadata for a book file. Extracts embedded data first,
    /// then enriches from APIs. Returns merged result.
    func fetchMetadata(forFileAt url: URL, format: BookFormat) async -> BookMetadata {
        // Check cache
        let cacheKey = url.lastPathComponent as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.metadata
        }

        // Step 1: Extract embedded metadata
        var metadata = extractEmbeddedMetadata(from: url, format: format)

        // Step 2: Try Google Books API
        if let apiMeta = await searchGoogleBooks(
            title: metadata.title,
            author: metadata.author,
            isbn: metadata.isbn13 ?? metadata.isbn10
        ) {
            metadata = merge(base: metadata, overlay: apiMeta)
        }

        // Step 3: If still missing cover or key fields, try Open Library
        if metadata.coverImageURL == nil || metadata.description == nil {
            if let olMeta = await searchOpenLibrary(
                title: metadata.title,
                author: metadata.author,
                isbn: metadata.isbn13 ?? metadata.isbn10
            ) {
                metadata = merge(base: metadata, overlay: olMeta)
            }
        }

        // Step 4: Download cover image if we got a URL
        if let coverURL = metadata.coverImageURL, metadata.coverImageData == nil {
            metadata.coverImageData = await downloadImage(from: coverURL)
        }

        // Cache result
        cache.setObject(CachedMetadata(metadata: metadata), forKey: cacheKey)

        return metadata
    }

    // MARK: - Cover Options (Multi-Source Picker)

    /// Fetch multiple cover candidates from Google Books (multiple results)
    /// and Open Library (multiple editions). Returns an array of options
    /// the user can browse and pick from.
    func fetchCoverOptions(title: String?, author: String?, isbn: String?) async -> [CoverOption] {
        var options: [CoverOption] = []

        // Google Books — fetch up to 8 results for different editions/covers
        let googleCovers = await fetchGoogleBooksCoverOptions(title: title, author: author, isbn: isbn)
        options.append(contentsOf: googleCovers)

        // Open Library — search editions for this work
        let olCovers = await fetchOpenLibraryCoverOptions(title: title, author: author, isbn: isbn)
        options.append(contentsOf: olCovers)

        // Download thumbnails concurrently
        options = await withTaskGroup(of: (UUID, Data?).self) { group in
            for opt in options {
                group.addTask {
                    let data = await self.downloadImage(from: opt.thumbnailURL)
                    return (opt.id, data)
                }
            }
            var updated = options
            for await (id, data) in group {
                if let idx = updated.firstIndex(where: { $0.id == id }) {
                    updated[idx].thumbnailData = data
                }
            }
            // Filter out options where thumbnail failed to load
            return updated.filter { $0.thumbnailData != nil }
        }

        return options
    }

    /// Download the full-resolution cover for a selected option.
    func downloadFullCover(for option: CoverOption) async -> Data? {
        return await downloadImage(from: option.fullURL)
    }

    // MARK: Google Books — Multiple Results

    private func fetchGoogleBooksCoverOptions(title: String?, author: String?, isbn: String?) async -> [CoverOption] {
        var queryParts: [String] = []
        if let isbn = isbn, !isbn.isEmpty {
            queryParts.append("isbn:\(isbn)")
        } else {
            if let title = title, !title.isEmpty { queryParts.append("intitle:\(title)") }
            if let author = author, !author.isEmpty { queryParts.append("inauthor:\(author)") }
        }
        guard !queryParts.isEmpty else { return [] }

        let query = queryParts.joined(separator: "+")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        var urlString = "https://www.googleapis.com/books/v1/volumes?q=\(query)&maxResults=8"
        if let key = googleBooksAPIKey { urlString += "&key=\(key)" }
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let items = json?["items"] as? [[String: Any]] else { return [] }

            var options: [CoverOption] = []
            var seenThumbs = Set<String>() // deduplicate identical covers

            for item in items {
                guard let info = item["volumeInfo"] as? [String: Any],
                      let imageLinks = info["imageLinks"] as? [String: String] else { continue }

                // Get best thumbnail
                let thumbURL: URL? = {
                    for key in ["thumbnail", "smallThumbnail"] {
                        if let s = imageLinks[key],
                           let u = URL(string: s.replacingOccurrences(of: "http://", with: "https://")) {
                            return u
                        }
                    }
                    return nil
                }()

                // Get best full-res URL
                let fullURL: URL? = {
                    for key in ["extraLarge", "large", "medium", "thumbnail"] {
                        if let s = imageLinks[key] {
                            let highRes = s
                                .replacingOccurrences(of: "zoom=1", with: "zoom=0")
                                .replacingOccurrences(of: "http://", with: "https://")
                            if let u = URL(string: highRes) { return u }
                        }
                    }
                    return nil
                }()

                guard let thumb = thumbURL, let full = fullURL else { continue }

                // Deduplicate
                let thumbKey = thumb.absoluteString
                guard !seenThumbs.contains(thumbKey) else { continue }
                seenThumbs.insert(thumbKey)

                // Build label from edition info
                let volumeTitle = info["title"] as? String ?? "Unknown"
                let pubDate = info["publishedDate"] as? String ?? ""
                let publisher = info["publisher"] as? String
                var label = "Google Books"
                if !pubDate.isEmpty {
                    let year = String(pubDate.prefix(4))
                    label += " · \(year)"
                }
                if let pub = publisher { label += " · \(pub)" }
                if volumeTitle != title { label += " — \(volumeTitle)" }

                options.append(CoverOption(
                    source: .googleBooks,
                    label: label,
                    thumbnailURL: thumb,
                    fullURL: full
                ))
            }
            return options
        } catch {
            return []
        }
    }

    // MARK: Open Library — Multiple Editions

    private func fetchOpenLibraryCoverOptions(title: String?, author: String?, isbn: String?) async -> [CoverOption] {
        // Step 1: Search for the work to find edition keys
        var searchParts: [String] = []
        if let title = title, !title.isEmpty { searchParts.append("title=\(title)") }
        if let author = author, !author.isEmpty { searchParts.append("author=\(author)") }
        guard !searchParts.isEmpty else { return [] }

        let query = searchParts.joined(separator: "&")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURL = "https://openlibrary.org/search.json?\(query)&limit=1&fields=edition_key,cover_edition_key,title"

        guard let url = URL(string: searchURL) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let docs = json?["docs"] as? [[String: Any]],
                  let doc = docs.first,
                  let editionKeys = doc["edition_key"] as? [String] else { return [] }

            // Step 2: Fetch covers for up to 8 editions
            let keysToCheck = Array(editionKeys.prefix(8))

            var options: [CoverOption] = []

            // Fetch edition details concurrently
            let editions = await withTaskGroup(of: (String, [String: Any]?).self) { group in
                for key in keysToCheck {
                    group.addTask {
                        let edURL = URL(string: "https://openlibrary.org/books/\(key).json")!
                        guard let (d, r) = try? await self.session.data(from: edURL),
                              let hr = r as? HTTPURLResponse, hr.statusCode == 200,
                              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                            return (key, nil)
                        }
                        return (key, j)
                    }
                }
                var result: [(String, [String: Any])] = []
                for await (key, json) in group {
                    if let json = json { result.append((key, json)) }
                }
                return result
            }

            var seenCovers = Set<Int>()

            for (key, edData) in editions {
                // Get cover IDs from this edition
                guard let covers = edData["covers"] as? [Int],
                      let coverId = covers.first,
                      coverId > 0,
                      !seenCovers.contains(coverId) else { continue }

                seenCovers.insert(coverId)

                let thumbURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-M.jpg")!
                let fullURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg")!

                // Build label from edition info
                let pubDate = edData["publish_date"] as? String ?? ""
                let publishers = edData["publishers"] as? [String]
                var label = "Open Library"
                if !pubDate.isEmpty { label += " · \(pubDate)" }
                if let pub = publishers?.first { label += " · \(pub)" }

                options.append(CoverOption(
                    source: .openLibrary,
                    label: label,
                    thumbnailURL: thumbURL,
                    fullURL: fullURL
                ))
            }

            // Also try ISBN-based cover if we have one
            if let isbn = isbn, !isbn.isEmpty {
                let isbnThumb = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg")!
                let isbnFull = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg")!
                options.insert(CoverOption(
                    source: .openLibrary,
                    label: "Open Library · ISBN",
                    thumbnailURL: isbnThumb,
                    fullURL: isbnFull
                ), at: 0)
            }

            return Array(options.prefix(8))
        } catch {
            return []
        }
    }

    // MARK: - Embedded Metadata Extraction

    /// Extract metadata embedded in the file itself.
    /// EPUB: Parse META-INF/container.xml → OPF file → dc:title, dc:creator, cover image
    /// PDF: PDFDocument.documentAttributes
    private func extractEmbeddedMetadata(from url: URL, format: BookFormat) -> BookMetadata {
        switch format {
        case .epub:
            return extractEPUBMetadata(from: url)
        case .pdf:
            return extractPDFMetadata(from: url)
        case .mobi:
            // MOBI metadata extraction is complex; skip to API lookup
            return extractMOBIMetadata(from: url)
        }
    }

    // MARK: EPUB
    private func extractEPUBMetadata(from url: URL) -> BookMetadata {
        var meta = BookMetadata()

        guard url.startAccessingSecurityScopedResource() else { return meta }
        defer { url.stopAccessingSecurityScopedResource() }

        // EPUB is a ZIP archive. We need to find container.xml → rootfile → OPF
        // For simplicity, we'll try to read the OPF content directly.
        // In production, use ZIPFoundation or similar to unzip.

        do {
            // Try reading as directory (if already unzipped) or use file coordinators
            let data = try Data(contentsOf: url)
            let content = String(data: data, encoding: .utf8) ?? ""

            // Extract title from dc:title
            if let title = extractXMLValue(from: content, tag: "dc:title") {
                meta.title = title
            }

            // Extract author from dc:creator
            if let author = extractXMLValue(from: content, tag: "dc:creator") {
                meta.authors = [author]
            }

            // Extract publisher
            if let publisher = extractXMLValue(from: content, tag: "dc:publisher") {
                meta.publisher = publisher
            }

            // Extract language
            if let language = extractXMLValue(from: content, tag: "dc:language") {
                meta.language = language
            }

            // Extract ISBN from dc:identifier
            if let identifier = extractXMLValue(from: content, tag: "dc:identifier") {
                if identifier.count == 13 && identifier.hasPrefix("978") {
                    meta.isbn13 = identifier
                } else if identifier.count == 10 {
                    meta.isbn10 = identifier
                }
            }

            // Extract description
            if let desc = extractXMLValue(from: content, tag: "dc:description") {
                meta.description = desc
            }
        } catch {
            // If we can't read the file directly, use filename as title
            meta.title = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }

        // Fallback: derive title from filename
        if meta.title == nil || meta.title?.isEmpty == true {
            meta.title = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }

        return meta
    }

    // MARK: PDF
    private func extractPDFMetadata(from url: URL) -> BookMetadata {
        var meta = BookMetadata()

        guard url.startAccessingSecurityScopedResource() else { return meta }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let doc = PDFDocument(url: url) else { return meta }

        let attrs = doc.documentAttributes ?? [:]

        if let title = attrs[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            meta.title = title
        }
        if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
            meta.authors = [author]
        }
        if let subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String, !subject.isEmpty {
            meta.description = subject
        }
        if let keywords = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            meta.categories = keywords
        }

        meta.pageCount = doc.pageCount

        // Fallback title from filename
        if meta.title == nil {
            meta.title = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }

        return meta
    }

    // MARK: MOBI
    private func extractMOBIMetadata(from url: URL) -> BookMetadata {
        var meta = BookMetadata()
        // MOBI has a binary header with title at offset 0.
        // Full parsing requires PalmDOC + MOBI header extraction.
        // For now, derive title from filename.
        meta.title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return meta
    }

    // MARK: - Google Books API

    /// Search Google Books by title+author or ISBN.
    /// Free tier: ~100 requests/day without API key.
    /// Returns: title, authors, description, cover URL, page count, ISBN, categories, rating.
    ///
    /// API docs: https://developers.google.com/books/docs/v1/using
    private func searchGoogleBooks(title: String?, author: String?, isbn: String?) async -> BookMetadata? {
        // Build query
        var queryParts: [String] = []

        if let isbn = isbn, !isbn.isEmpty {
            // ISBN search is most precise
            queryParts.append("isbn:\(isbn)")
        } else {
            if let title = title, !title.isEmpty {
                queryParts.append("intitle:\(title)")
            }
            if let author = author, !author.isEmpty {
                queryParts.append("inauthor:\(author)")
            }
        }

        guard !queryParts.isEmpty else { return nil }

        let query = queryParts.joined(separator: "+")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        var urlString = "https://www.googleapis.com/books/v1/volumes?q=\(query)&maxResults=1"
        if let key = googleBooksAPIKey {
            urlString += "&key=\(key)"
        }

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let items = json?["items"] as? [[String: Any]],
                  let volumeInfo = items.first?["volumeInfo"] as? [String: Any] else {
                return nil
            }

            return parseGoogleBooksVolume(volumeInfo)
        } catch {
            print("Google Books API error: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseGoogleBooksVolume(_ info: [String: Any]) -> BookMetadata {
        var meta = BookMetadata()

        meta.title = info["title"] as? String
        meta.authors = info["authors"] as? [String]
        meta.publisher = info["publisher"] as? String
        meta.publishedDate = info["publishedDate"] as? String
        meta.description = info["description"] as? String
        meta.pageCount = info["pageCount"] as? Int
        meta.categories = info["categories"] as? [String]
        meta.language = info["language"] as? String
        meta.averageRating = info["averageRating"] as? Double
        meta.ratingsCount = info["ratingsCount"] as? Int

        // ISBN identifiers
        if let identifiers = info["industryIdentifiers"] as? [[String: String]] {
            for id in identifiers {
                if id["type"] == "ISBN_13" { meta.isbn13 = id["identifier"] }
                if id["type"] == "ISBN_10" { meta.isbn10 = id["identifier"] }
            }
        }

        // Cover image — prefer thumbnail, can modify URL for higher res
        if let imageLinks = info["imageLinks"] as? [String: String] {
            // Try largest available
            let preferred = ["extraLarge", "large", "medium", "small", "thumbnail", "smallThumbnail"]
            for size in preferred {
                if let urlStr = imageLinks[size],
                   let url = URL(string: urlStr.replacingOccurrences(of: "http://", with: "https://")) {
                    meta.coverImageURL = url
                    break
                }
            }

            // Google trick: modify zoom parameter for higher res
            if meta.coverImageURL == nil, let thumb = imageLinks["thumbnail"] {
                let highRes = thumb
                    .replacingOccurrences(of: "zoom=1", with: "zoom=0")
                    .replacingOccurrences(of: "http://", with: "https://")
                meta.coverImageURL = URL(string: highRes)
            }
        }

        return meta
    }

    // MARK: - Open Library API

    /// Search Open Library as a fallback. Completely free, no key needed.
    /// Good for cover images and basic metadata.
    ///
    /// API docs: https://openlibrary.org/developers/api
    private func searchOpenLibrary(title: String?, author: String?, isbn: String?) async -> BookMetadata? {
        var urlString: String

        if let isbn = isbn, !isbn.isEmpty {
            // ISBN lookup is most reliable
            urlString = "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"
            return await fetchOpenLibraryByISBN(urlString: urlString, isbn: isbn)
        }

        // Search by title+author
        var searchParts: [String] = []
        if let title = title, !title.isEmpty {
            searchParts.append("title=\(title)")
        }
        if let author = author, !author.isEmpty {
            searchParts.append("author=\(author)")
        }
        guard !searchParts.isEmpty else { return nil }

        let query = searchParts.joined(separator: "&")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        urlString = "https://openlibrary.org/search.json?\(query)&limit=1"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let docs = json?["docs"] as? [[String: Any]],
                  let doc = docs.first else { return nil }

            var meta = BookMetadata()
            meta.title = doc["title"] as? String
            if let authors = doc["author_name"] as? [String] {
                meta.authors = authors
            }
            meta.publisher = (doc["publisher"] as? [String])?.first
            meta.publishedDate = "\(doc["first_publish_year"] as? Int ?? 0)"

            if let subjects = doc["subject"] as? [String] {
                meta.categories = Array(subjects.prefix(5))
            }
            if let pages = doc["number_of_pages_median"] as? Int {
                meta.pageCount = pages
            }

            // Cover from cover_i (Open Library cover ID)
            if let coverId = doc["cover_i"] as? Int {
                meta.coverImageURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg")
            }

            // ISBN
            if let isbns = doc["isbn"] as? [String] {
                for isbn in isbns {
                    if isbn.count == 13 { meta.isbn13 = isbn; break }
                    if isbn.count == 10 && meta.isbn10 == nil { meta.isbn10 = isbn }
                }
            }

            return meta
        } catch {
            print("Open Library API error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchOpenLibraryByISBN(urlString: String, isbn: String) async -> BookMetadata? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let bookData = json?["ISBN:\(isbn)"] as? [String: Any] else { return nil }

            var meta = BookMetadata()
            meta.title = bookData["title"] as? String
            if let authors = bookData["authors"] as? [[String: Any]] {
                meta.authors = authors.compactMap { $0["name"] as? String }
            }
            if let publishers = bookData["publishers"] as? [[String: Any]] {
                meta.publisher = publishers.first?["name"] as? String
            }
            meta.publishedDate = bookData["publish_date"] as? String
            meta.pageCount = bookData["number_of_pages"] as? Int

            // Cover
            if let cover = bookData["cover"] as? [String: String] {
                let preferred = ["large", "medium", "small"]
                for size in preferred {
                    if let urlStr = cover[size], let url = URL(string: urlStr) {
                        meta.coverImageURL = url
                        break
                    }
                }
            }

            return meta
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// Merge two metadata objects. Base takes priority for non-nil fields;
    /// overlay fills in any gaps.
    private func merge(base: BookMetadata, overlay: BookMetadata) -> BookMetadata {
        var result = base
        if result.title == nil || result.title?.isEmpty == true { result.title = overlay.title }
        if result.authors == nil || result.authors?.isEmpty == true { result.authors = overlay.authors }
        if result.description == nil { result.description = overlay.description }
        if result.publisher == nil { result.publisher = overlay.publisher }
        if result.publishedDate == nil { result.publishedDate = overlay.publishedDate }
        if result.pageCount == nil { result.pageCount = overlay.pageCount }
        if result.isbn10 == nil { result.isbn10 = overlay.isbn10 }
        if result.isbn13 == nil { result.isbn13 = overlay.isbn13 }
        if result.categories == nil { result.categories = overlay.categories }
        if result.language == nil { result.language = overlay.language }
        if result.coverImageURL == nil { result.coverImageURL = overlay.coverImageURL }
        if result.coverImageData == nil { result.coverImageData = overlay.coverImageData }
        if result.averageRating == nil { result.averageRating = overlay.averageRating }
        if result.ratingsCount == nil { result.ratingsCount = overlay.ratingsCount }
        return result
    }

    /// Download image data from URL
    func downloadImage(from url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  UIImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Simple XML tag value extractor (for EPUB OPF parsing)
    private func extractXMLValue(from content: String, tag: String) -> String? {
        // Match <tag ...>value</tag> or <tag>value</tag>
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: content,
                                           range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return nil
        }
        let value = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Cache Wrapper
private class CachedMetadata {
    let metadata: BookMetadata
    init(metadata: BookMetadata) { self.metadata = metadata }
}
