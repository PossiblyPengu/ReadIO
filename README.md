# ReadIO — iOS 26 Liquid Glass Edition

A reading and audiobook companion app built with Apple's Liquid Glass design language.

## What is Liquid Glass?

Liquid Glass is **not** glassmorphism. It is a physics-based material system introduced at WWDC 2025 that uses:

- **Refraction**: Edges warp background content through a convex squircle bevel profile
- **Specular highlights**: Bright rim light derived from surface normal × light direction
- **Translucency**: Adaptive brightness/saturation — not just blur + transparency
- **Hierarchy**: Glass is ONLY for controls/navigation. Content stays clean.
- **Morphing**: `GlassEffectContainer` merges nearby glass elements into continuous shapes

## Where Glass Is Applied

| Element | Glass Treatment | Why |
|---|---|---|
| Tab bubbles | Individual `.glassEffect(.capsule)` per tab | Floating bubble navigation |
| Active tab | `.regular.tint(.indigo)` expands to show label | Semantic state |
| Filter chips | `.glassEffect(.regular, in: .capsule)` | Interactive controls |
| Transport buttons | Glass circles in `GlassEffectContainer` | Control cluster |
| Mini player | Glass capsule above tab bubbles | Persistent control |
| Settings sections | `.glassEffect(.regular, in: .roundedRectangle)` | Themed glass groups |
| Book covers | **No glass** — real cover art or gradient | Content |

## Auto-Download Metadata

On import, books are enriched automatically from three sources:

### 1. Embedded Metadata (instant, no network)
- **EPUB**: Parses `dc:title`, `dc:creator`, `dc:publisher`, ISBN from OPF XML
- **PDF**: Reads `PDFDocument.documentAttributes` (title, author, subject, page count)
- **MOBI**: Falls back to filename-derived title

### 2. Google Books API (free, ~100 req/day)
- Searches by ISBN or `intitle:` + `inauthor:`
- Returns: title, authors, description, publisher, page count, categories, rating, cover images
- Optional: Set `MetadataService.shared.googleBooksAPIKey` for higher quota

### 3. Open Library API (free, unlimited, no key)
- Fallback when Google doesn't return cover or description
- Covers via `covers.openlibrary.org/b/id/{coverId}-L.jpg`

### Merge Strategy
- Embedded data wins for any field it has
- API data fills gaps (cover art, description, rating, categories)
- Cover image saved to `Covers/{bookId}.jpg`
- Long-press → **Refresh Metadata** to re-run lookup
- `enrichAllPending()` retries failed books on app launch

## Project Structure

```
ReadIO/
├── ReadIOApp.swift
├── Extensions/
│   └── LiquidGlassHelpers.swift
├── Models/
│   └── Models.swift
├── ViewModels/
│   ├── LibraryViewModel.swift       # Import + async metadata enrichment
│   ├── AudioPlayerViewModel.swift
│   └── SettingsViewModel.swift
├── Services/
│   ├── StorageService.swift
│   └── MetadataService.swift        # Embedded + Google Books + Open Library
└── Views/
    ├── ContentView.swift            # Floating bubble tab bar + mini player
    ├── LibraryView.swift            # Book grid/list with cover art
    ├── ReaderView.swift
    ├── AudioPlayerView.swift
    └── SettingsView.swift           # Themed glass sections + appearance picker
```

## Requirements

- Xcode 26+ / Swift 6.0+ / iOS 26.0+
- Network access for metadata (graceful offline fallback)

## Recommended Libraries

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — EPUB archive extraction
- [Readium Swift Toolkit](https://github.com/readium/swift-toolkit) — EPUB rendering
- [AudioKit](https://audiokit.io) — Advanced audio processing
