import Foundation
import SwiftUI

// MARK: - Cover Option (Codable, for persistence)
struct CoverOptionInfo: Identifiable, Codable, Hashable {
    let id: UUID
    let source: String          // "Google Books", "Open Library", "Open Library (1965 Edition)"
    let thumbnailURL: String    // Smaller preview image URL
    let fullURL: String         // Full-resolution image URL

    init(id: UUID = UUID(), source: String, thumbnailURL: String, fullURL: String) {
        self.id = id
        self.source = source
        self.thumbnailURL = thumbnailURL
        self.fullURL = fullURL
    }
}

// MARK: - Book Model
struct Book: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var author: String
    var coverImagePath: String?
    var coverOptions: [CoverOptionInfo]   // All available covers from metadata sources
    var filePath: String
    var fileFormat: BookFormat
    var dateAdded: Date
    var lastOpened: Date?
    var readingProgress: ReadingProgress
    var bookmarks: [Bookmark]
    var highlights: [Highlight]
    var audiobook: AudiobookInfo?
    var isFavorite: Bool

    // Extended metadata (auto-fetched on import)
    var bookDescription: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var isbn: String?          // ISBN-13 preferred, falls back to ISBN-10
    var categories: [String]?
    var language: String?
    var averageRating: Double?
    var ratingsCount: Int?
    var metadataFetched: Bool   // true once API lookup has completed

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "Unknown Author",
        coverImagePath: String? = nil,
        coverOptions: [CoverOptionInfo] = [],
        filePath: String,
        fileFormat: BookFormat,
        dateAdded: Date = Date(),
        lastOpened: Date? = nil,
        readingProgress: ReadingProgress = ReadingProgress(),
        bookmarks: [Bookmark] = [],
        highlights: [Highlight] = [],
        audiobook: AudiobookInfo? = nil,
        isFavorite: Bool = false,
        bookDescription: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        pageCount: Int? = nil,
        isbn: String? = nil,
        categories: [String]? = nil,
        language: String? = nil,
        averageRating: Double? = nil,
        ratingsCount: Int? = nil,
        metadataFetched: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.coverOptions = coverOptions
        self.filePath = filePath
        self.fileFormat = fileFormat
        self.dateAdded = dateAdded
        self.lastOpened = lastOpened
        self.readingProgress = readingProgress
        self.bookmarks = bookmarks
        self.highlights = highlights
        self.audiobook = audiobook
        self.isFavorite = isFavorite
        self.bookDescription = bookDescription
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.pageCount = pageCount
        self.isbn = isbn
        self.categories = categories
        self.language = language
        self.averageRating = averageRating
        self.ratingsCount = ratingsCount
        self.metadataFetched = metadataFetched
    }
}

// MARK: - Book Format
enum BookFormat: String, Codable, CaseIterable {
    case epub = "epub"
    case pdf = "pdf"
    case mobi = "mobi"

    var displayName: String {
        rawValue.uppercased()
    }

    var iconName: String {
        switch self {
        case .epub: return "doc.text"
        case .pdf: return "doc.richtext"
        case .mobi: return "doc.plaintext"
        }
    }

    var supportedExtensions: [String] {
        switch self {
        case .epub: return ["epub"]
        case .pdf: return ["pdf"]
        case .mobi: return ["mobi", "azw", "azw3"]
        }
    }
}

// MARK: - Reading Progress
struct ReadingProgress: Codable, Hashable {
    var currentChapter: Int
    var currentPage: Int
    var totalPages: Int
    var percentage: Double
    var lastPosition: String? // CFI for EPUB, page number for PDF
    var lastUpdated: Date

    init(
        currentChapter: Int = 0,
        currentPage: Int = 0,
        totalPages: Int = 0,
        percentage: Double = 0.0,
        lastPosition: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.currentChapter = currentChapter
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.percentage = percentage
        self.lastPosition = lastPosition
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Bookmark
struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    var position: String // CFI or page reference
    var chapter: Int
    var page: Int
    var title: String?
    var note: String?
    var dateCreated: Date
    var color: BookmarkColor

    init(
        id: UUID = UUID(),
        position: String,
        chapter: Int = 0,
        page: Int = 0,
        title: String? = nil,
        note: String? = nil,
        dateCreated: Date = Date(),
        color: BookmarkColor = .red
    ) {
        self.id = id
        self.position = position
        self.chapter = chapter
        self.page = page
        self.title = title
        self.note = note
        self.dateCreated = dateCreated
        self.color = color
    }
}

enum BookmarkColor: String, Codable, CaseIterable {
    case red, blue, green, yellow, purple

    var color: Color {
        switch self {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .purple: return .purple
        }
    }
}

// MARK: - Highlight
struct Highlight: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var position: String
    var chapter: Int
    var page: Int
    var note: String?
    var color: HighlightColor
    var dateCreated: Date

    init(
        id: UUID = UUID(),
        text: String,
        position: String,
        chapter: Int = 0,
        page: Int = 0,
        note: String? = nil,
        color: HighlightColor = .yellow,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.chapter = chapter
        self.page = page
        self.note = note
        self.color = color
        self.dateCreated = dateCreated
    }
}

enum HighlightColor: String, Codable, CaseIterable {
    case yellow, green, blue, pink, orange

    var color: Color {
        switch self {
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .orange: return .orange
        }
    }
}

// MARK: - Audiobook Info
struct AudiobookInfo: Codable, Hashable {
    var audioFilePaths: [String]
    var totalDuration: TimeInterval
    var currentTime: TimeInterval
    var currentTrack: Int
    var playbackSpeed: Double
    var chapterMapping: [AudioChapterMapping]?

    init(
        audioFilePaths: [String] = [],
        totalDuration: TimeInterval = 0,
        currentTime: TimeInterval = 0,
        currentTrack: Int = 0,
        playbackSpeed: Double = 1.0,
        chapterMapping: [AudioChapterMapping]? = nil
    ) {
        self.audioFilePaths = audioFilePaths
        self.totalDuration = totalDuration
        self.currentTime = currentTime
        self.currentTrack = currentTrack
        self.playbackSpeed = playbackSpeed
        self.chapterMapping = chapterMapping
    }
}

struct AudioChapterMapping: Codable, Hashable {
    var chapterIndex: Int
    var chapterTitle: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var correspondingReadingPosition: String?
}

// MARK: - Reading Theme
struct ReadingTheme: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var backgroundColor: ThemeColor
    var textColor: ThemeColor
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        backgroundColor: ThemeColor,
        textColor: ThemeColor,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.isBuiltIn = isBuiltIn
    }

    static let light = ReadingTheme(
        name: "Light",
        backgroundColor: ThemeColor(red: 1.0, green: 1.0, blue: 1.0),
        textColor: ThemeColor(red: 0.1, green: 0.1, blue: 0.1),
        isBuiltIn: true
    )

    static let dark = ReadingTheme(
        name: "Dark",
        backgroundColor: ThemeColor(red: 0.1, green: 0.1, blue: 0.12),
        textColor: ThemeColor(red: 0.9, green: 0.9, blue: 0.88),
        isBuiltIn: true
    )

    static let sepia = ReadingTheme(
        name: "Sepia",
        backgroundColor: ThemeColor(red: 0.96, green: 0.93, blue: 0.87),
        textColor: ThemeColor(red: 0.3, green: 0.25, blue: 0.18),
        isBuiltIn: true
    )

    static let night = ReadingTheme(
        name: "Night",
        backgroundColor: ThemeColor(red: 0.0, green: 0.0, blue: 0.0),
        textColor: ThemeColor(red: 0.7, green: 0.7, blue: 0.65),
        isBuiltIn: true
    )

    static let builtInThemes: [ReadingTheme] = [.light, .sepia, .dark, .night]
}

struct ThemeColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

// MARK: - App Settings
struct AppSettings: Codable {
    var fontSize: Double
    var fontFamily: String
    var lineSpacing: Double
    var margins: Double
    var textAlignment: TextAlignmentOption
    var selectedThemeId: UUID?
    var autoNightMode: Bool
    var nightModeStartHour: Int
    var nightModeEndHour: Int
    var keepScreenAwake: Bool
    var defaultPlaybackSpeed: Double
    var skipForwardSeconds: Int
    var skipBackwardSeconds: Int
    var sleepTimerMinutes: Int?
    var sortOrder: LibrarySortOrder
    var viewStyle: LibraryViewStyle
    var appAppearance: AppAppearance
    var autoPlayAudio: Bool

    // Convenience aliases for consistent naming
    var keepScreenOn: Bool {
        get { keepScreenAwake }
        set { keepScreenAwake = newValue }
    }
    var skipForwardInterval: Double {
        get { Double(skipForwardSeconds) }
        set { skipForwardSeconds = Int(newValue) }
    }
    var skipBackwardInterval: Double {
        get { Double(skipBackwardSeconds) }
        set { skipBackwardSeconds = Int(newValue) }
    }
    var sortBy: LibrarySortOrder {
        get { sortOrder }
        set { sortOrder = newValue }
    }

    init(
        fontSize: Double = 18.0,
        fontFamily: String = "Georgia",
        lineSpacing: Double = 1.4,
        margins: Double = 20.0,
        textAlignment: TextAlignmentOption = .left,
        selectedThemeId: UUID? = nil,
        autoNightMode: Bool = false,
        nightModeStartHour: Int = 20,
        nightModeEndHour: Int = 7,
        keepScreenAwake: Bool = true,
        defaultPlaybackSpeed: Double = 1.0,
        skipForwardSeconds: Int = 30,
        skipBackwardSeconds: Int = 15,
        sleepTimerMinutes: Int? = nil,
        sortOrder: LibrarySortOrder = .dateAdded,
        viewStyle: LibraryViewStyle = .grid,
        appAppearance: AppAppearance = .system,
        autoPlayAudio: Bool = false
    ) {
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.lineSpacing = lineSpacing
        self.margins = margins
        self.textAlignment = textAlignment
        self.selectedThemeId = selectedThemeId
        self.autoNightMode = autoNightMode
        self.nightModeStartHour = nightModeStartHour
        self.nightModeEndHour = nightModeEndHour
        self.keepScreenAwake = keepScreenAwake
        self.defaultPlaybackSpeed = defaultPlaybackSpeed
        self.skipForwardSeconds = skipForwardSeconds
        self.skipBackwardSeconds = skipBackwardSeconds
        self.sleepTimerMinutes = sleepTimerMinutes
        self.sortOrder = sortOrder
        self.viewStyle = viewStyle
        self.appAppearance = appAppearance
        self.autoPlayAudio = autoPlayAudio
    }

    // CodingKeys to exclude computed properties from encoding
    enum CodingKeys: String, CodingKey {
        case fontSize, fontFamily, lineSpacing, margins, textAlignment
        case selectedThemeId, autoNightMode, nightModeStartHour, nightModeEndHour
        case keepScreenAwake, defaultPlaybackSpeed, skipForwardSeconds, skipBackwardSeconds
        case sleepTimerMinutes, sortOrder, viewStyle, appAppearance, autoPlayAudio
    }
}

enum TextAlignmentOption: String, Codable, CaseIterable {
    case left, center, justified

    var alignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .justified: return .leading // SwiftUI doesn't natively support justified
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum LibrarySortOrder: String, Codable, CaseIterable {
    case dateAdded = "Date Added"
    case title = "Title"
    case author = "Author"
    case lastOpened = "Last Opened"
    case progress = "Progress"
}

enum LibraryViewStyle: String, Codable, CaseIterable {
    case grid = "Grid"
    case list = "List"
}

/// Type alias for backward compat
typealias SortOption = LibrarySortOrder

// MARK: - App Appearance
enum AppAppearance: String, Codable, CaseIterable {
    case system, light, dark
}

// MARK: - Supported Audio Formats
enum AudioFormat: String, CaseIterable {
    case mp3, m4a, m4b, aac, wav, flac

    var supportedExtensions: [String] {
        switch self {
        case .mp3: return ["mp3"]
        case .m4a: return ["m4a"]
        case .m4b: return ["m4b"]
        case .aac: return ["aac"]
        case .wav: return ["wav"]
        case .flac: return ["flac"]
        }
    }

    static var allExtensions: [String] {
        allCases.flatMap { $0.supportedExtensions }
    }
}
