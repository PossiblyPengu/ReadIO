import SwiftUI

/// A sheet that fetches and displays cover image options from Google Books
/// and Open Library, letting the user browse different editions and pick
/// the cover they want for their book.
///
/// Shows the current cover with a selection border, groups results by
/// source, and includes a "Remove Cover" option at the bottom.
@available(iOS 26.0, *)
struct CoverPickerView: View {
    let book: Book
    let onSelect: (Data) -> Void
    var onRemove: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var options: [CoverOption] = []
    @State private var isLoading = true
    @State private var selectedOption: CoverOption?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                if isLoading && options.isEmpty {
                    loadingState
                } else if options.isEmpty {
                    emptyState
                } else {
                    coverGrid
                }
            }
            .navigationTitle("Choose Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if selectedOption != nil {
                        Button("Save") { saveCover() }
                            .fontWeight(.semibold)
                            .disabled(isSaving)
                    }
                }
            }
        }
        .task { await loadOptions() }
    }

    // MARK: - Cover Grid

    private var coverGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Current cover
                if let coverPath = book.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    currentCoverSection(uiImage)
                }

                // Google Books results
                let googleOpts = options.filter { $0.source == .googleBooks }
                if !googleOpts.isEmpty {
                    sourceSection("Google Books", options: googleOpts)
                }

                // Open Library results
                let olOpts = options.filter { $0.source == .openLibrary }
                if !olOpts.isEmpty {
                    sourceSection("Open Library", options: olOpts)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Searching more editions...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Remove cover option
                removeCoverSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    private func currentCoverSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT COVER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selectedOption == nil ? .indigo : .clear, lineWidth: 2.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
    }

    private func sourceSection(_ title: String, options: [CoverOption]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(options) { option in
                    coverThumbnail(option)
                }
            }
        }
    }

    private func coverThumbnail(_ option: CoverOption) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) {
                selectedOption = option
            }
        } label: {
            VStack(spacing: 6) {
                if let data = option.thumbnailData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(0.65, contentMode: .fill)
                        .frame(minHeight: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selectedOption?.id == option.id ? .indigo : .clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                        .overlay(alignment: .bottomTrailing) {
                            if selectedOption?.id == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .indigo)
                                    .shadow(radius: 2)
                                    .padding(6)
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(0.65, contentMode: .fit)
                        .overlay(ProgressView().scaleEffect(0.7))
                }

                Text(option.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Remove Cover

    private var removeCoverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.top, 4)

            Button {
                onRemove?()
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.gray.opacity(0.3), .gray.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 68)

                        Image(systemName: "photo.badge.minus")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove Cover")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text("Revert to gradient placeholder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(book.coverImagePath == nil)
            .opacity(book.coverImagePath == nil ? 0.4 : 1)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching for covers...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(book.title) — \(book.author)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            Text("No covers found")
                .font(.headline)
            Text("Try editing the book title or author\nfor better search results.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if book.coverImagePath != nil {
                Button("Remove Current Cover") {
                    onRemove?()
                    dismiss()
                }
                .font(.subheadline)
                .tint(.red)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Data Loading

    private func loadOptions() async {
        isLoading = true

        let results = await MetadataService.shared.fetchCoverOptions(
            title: book.title,
            author: book.author == "Unknown Author" ? nil : book.author,
            isbn: book.isbn
        )

        await MainActor.run {
            options = results
            isLoading = false
            if results.isEmpty {
                errorMessage = "Could not find any cover images for this book."
            }
        }
    }

    private func saveCover() {
        guard let option = selectedOption else { return }
        isSaving = true

        Task {
            let data = await MetadataService.shared.downloadFullCover(for: option)

            await MainActor.run {
                isSaving = false
                if let data = data {
                    onSelect(data)
                    dismiss()
                } else {
                    errorMessage = "Failed to download high-res cover. Try another option."
                }
            }
        }
    }
}
