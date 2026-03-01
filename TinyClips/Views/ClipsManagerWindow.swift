import AppKit
import SwiftUI
import AVFoundation
import SwiftData
import ImageIO

// MARK: - Window

@MainActor
class ClipsManagerWindow: NSWindow, NSWindowDelegate {
    private var onClose: (() -> Void)?
    private var didClose = false

    convenience init(onClose: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.onClose = onClose
        self.title = "Clips Manager"
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.minSize = NSSize(width: 620, height: 420)
        self.center()
        self.contentView = NSHostingView(rootView: ClipsManagerRootView())
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        onClose?()
        onClose = nil
    }
}

// MARK: - Root View (Pro gating)

private struct ClipsManagerRootView: View {
#if APPSTORE
    @ObservedObject private var storeService = StoreService.shared

    var body: some View {
        if storeService.isPro {
            ClipsManagerContentView()
        } else {
            ProUpsellView()
        }
    }
#else
    var body: some View {
        ClipsManagerContentView()
    }
#endif
}

// MARK: - Clip Item Model

struct ClipItem: Identifiable {
    let id = UUID()
    let url: URL
    let type: CaptureType
    let date: Date
    let fileSize: Int64

    init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg": self.type = .screenshot
        case "mp4": self.type = .video
        case "gif": self.type = .gif
        default: return nil
        }
        let resources = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        self.date = resources?.creationDate ?? Date()
        self.fileSize = Int64(resources?.fileSize ?? 0)
        self.url = url
    }

    var typeLabel: String { type.label }

    var formattedSize: String {
        let bytes = Double(fileSize)
        if bytes < 1_024 { return "\(fileSize) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", bytes / 1_024) }
        return String(format: "%.1f MB", bytes / 1_048_576)
    }

    var typeIcon: String {
        switch type {
        case .screenshot: return "photo"
        case .video: return "video"
        case .gif: return "photo.on.rectangle"
        }
    }

    var filePath: String { url.path }
}

// MARK: - Metadata

private struct ClipMetadata {
    var displayName: String?
    var tags: [String]
    var isFavorite: Bool
    var notes: String
    var collection: String?
}

@Model
private final class ClipMetadataRecord {
    @Attribute(.unique) var clipPath: String
    var displayName: String?
    var tagsBlob: String
    var isFavorite: Bool
    var notes: String
    var collection: String?

    init(
        clipPath: String,
        displayName: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        notes: String = "",
        collection: String? = nil
    ) {
        self.clipPath = clipPath
        self.displayName = displayName
        self.tagsBlob = tags.joined(separator: "\n")
        self.isFavorite = isFavorite
        self.notes = notes
        self.collection = collection
    }

    var tags: [String] {
        get {
            tagsBlob
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsBlob = newValue.joined(separator: "\n")
        }
    }
}

@MainActor
private final class ClipMetadataStore {
    static let shared = ClipMetadataStore()

    private let modelContext: ModelContext?

    private init() {
        do {
            let container = try ModelContainer(for: ClipMetadataRecord.self)
            modelContext = ModelContext(container)
        } catch {
            modelContext = nil
        }
    }

    func metadataMap() -> [String: ClipMetadata] {
        guard let modelContext else { return [:] }

        let descriptor = FetchDescriptor<ClipMetadataRecord>()
        guard let records = try? modelContext.fetch(descriptor) else { return [:] }

        return records.reduce(into: [String: ClipMetadata]()) { partial, record in
            partial[record.clipPath] = ClipMetadata(
                displayName: record.displayName,
                tags: record.tags,
                isFavorite: record.isFavorite,
                notes: record.notes,
                collection: record.collection
            )
        }
    }

    func upsert(path: String, mutate: (inout ClipMetadata) -> Void) {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<ClipMetadataRecord>(
            predicate: #Predicate { $0.clipPath == path }
        )
        descriptor.fetchLimit = 1

        let record = (try? modelContext.fetch(descriptor).first) ?? ClipMetadataRecord(clipPath: path)
        if record.modelContext == nil {
            modelContext.insert(record)
        }

        var metadata = ClipMetadata(
            displayName: record.displayName,
            tags: record.tags,
            isFavorite: record.isFavorite,
            notes: record.notes,
            collection: record.collection
        )
        mutate(&metadata)

        record.displayName = metadata.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        record.tags = metadata.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        record.isFavorite = metadata.isFavorite
        record.notes = metadata.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCollection = metadata.collection?.trimmingCharacters(in: .whitespacesAndNewlines)
        record.collection = (trimmedCollection?.isEmpty == false) ? trimmedCollection : nil

        try? modelContext.save()
    }

    func remove(path: String) {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<ClipMetadataRecord>(
            predicate: #Predicate { $0.clipPath == path }
        )
        descriptor.fetchLimit = 1

        if let record = try? modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try? modelContext.save()
        }
    }
}

// MARK: - Clips View Model

@MainActor
private class ClipsViewModel: ObservableObject {
    @Published var clips: [ClipItem] = []
    @Published var thumbnails: [UUID: NSImage] = [:]
    @Published var isLoading = false
    @Published var sortOption: SortOption = .newest
    @Published var filterType: FilterType = .all
    @Published var dateFilter: DateFilter = .allTime
    @Published var viewMode: ViewMode = .grid
    @Published var searchText = ""
    @Published var selectedTag: String = ""
    @Published var selectedCollection: String = ""
    @Published var selectionMode = false
    @Published var selectedClipIDs: Set<UUID> = []
    @Published private var metadataByPath: [String: ClipMetadata] = [:]

    private let metadataStore = ClipMetadataStore.shared

    private var editorWindows: [NSWindow] = []

#if APPSTORE
    private var activeScopedURL: URL?
#endif

    enum SortOption: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case largest = "Largest"
        case name = "Name"
        case favoritesFirst = "Favorites First"
    }

    enum FilterType: String, CaseIterable {
        case all = "All"
        case screenshots = "Screenshots"
        case videos = "Videos"
        case gifs = "GIFs"
        case favorites = "Favorites"
    }

    enum DateFilter: String, CaseIterable {
        case allTime = "Any Date"
        case today = "Today"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
    }

    enum ViewMode {
        case grid, list
    }

    var filteredSortedClips: [ClipItem] {
        var result = clips

        switch filterType {
        case .all: break
        case .screenshots: result = result.filter { $0.type == .screenshot }
        case .videos: result = result.filter { $0.type == .video }
        case .gifs: result = result.filter { $0.type == .gif }
        case .favorites: result = result.filter { isFavorite($0) }
        }

        if dateFilter != .allTime {
            let now = Date()
            result = result.filter { item in
                switch dateFilter {
                case .allTime:
                    return true
                case .today:
                    return Calendar.current.isDateInToday(item.date)
                case .last7Days:
                    guard let threshold = Calendar.current.date(byAdding: .day, value: -7, to: now) else { return true }
                    return item.date >= threshold
                case .last30Days:
                    guard let threshold = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return true }
                    return item.date >= threshold
                }
            }
        }

        if !selectedTag.isEmpty {
            result = result.filter { tags(for: $0).contains(selectedTag) }
        }

        if !selectedCollection.isEmpty {
            result = result.filter { collection(for: $0) == selectedCollection }
        }

        if !searchText.isEmpty {
            result = result.filter { matchesSearch(item: $0, query: searchText) }
        }

        switch sortOption {
        case .newest: result = result.sorted { $0.date > $1.date }
        case .oldest: result = result.sorted { $0.date < $1.date }
        case .largest: result = result.sorted { $0.fileSize > $1.fileSize }
        case .name: result = result.sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
            }
        case .favoritesFirst:
            result = result.sorted {
                if isFavorite($0) == isFavorite($1) {
                    return $0.date > $1.date
                }
                return isFavorite($0)
            }
        }

        return result
    }

    // MARK: - Loading

    func load() {
        isLoading = true
        selectedClipIDs = []
        metadataByPath = metadataStore.metadataMap()
        Task {
            let urls = await scanForClips()
            self.clips = urls.compactMap { ClipItem(url: $0) }
            self.isLoading = false
            loadThumbnails()
        }
    }

    private func scanForClips() async -> [URL] {
        let directories = clipDirectories()
        var urls: [URL] = []
        for dir in directories {
            urls.append(contentsOf: filesInDirectory(dir))
        }
        // Deduplicate by path
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    private func clipDirectories() -> [URL] {
#if APPSTORE
        let bookmark = UserDefaults.standard.data(forKey: "saveDirectoryBookmark")
        if let bookmark, !bookmark.isEmpty,
           let customURL = resolveBookmark(bookmark) {
            return [customURL]
        }
        var dirs: [URL] = []
        if let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            dirs.append(pics.appendingPathComponent("TinyClips"))
        }
        if let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            dirs.append(movies.appendingPathComponent("TinyClips"))
        }
        return dirs
#else
        let dir = UserDefaults.standard.string(forKey: "saveDirectory") ?? (NSHomeDirectory() + "/Desktop")
        return [URL(fileURLWithPath: dir)]
#endif
    }

#if APPSTORE
    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else { return nil }
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = url
        return url
    }

    deinit {
        activeScopedURL?.stopAccessingSecurityScopedResource()
    }
#endif

    private func filesInDirectory(_ dir: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return contents.filter {
            let name = $0.lastPathComponent
            let ext = $0.pathExtension.lowercased()
            return name.hasPrefix("TinyClips ") && ["png", "jpg", "mp4", "gif"].contains(ext)
        }
    }

    // MARK: - Thumbnails

    private func loadThumbnails() {
        let items = self.clips
        for item in items {
            let url = item.url
            let type = item.type
            let itemID = item.id
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let image: NSImage?
                switch type {
                case .screenshot, .gif:
                    image = NSImage(contentsOf: url)
                case .video:
                    let asset = AVURLAsset(url: url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 160, height: 120)
                    let time = CMTime(seconds: 0, preferredTimescale: 600)
                    var generatedImage: CGImage?
                    let semaphore = DispatchSemaphore(value: 0)
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
                        if result == .succeeded {
                            generatedImage = cgImage
                        }
                        semaphore.signal()
                    }
                    _ = semaphore.wait(timeout: .now() + 2)
                    if let cgImage = generatedImage {
                        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    } else {
                        image = nil
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.thumbnails[itemID] = image
                }
            }
        }
    }

    // MARK: - Actions

    func delete(_ item: ClipItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            clips.removeAll { $0.id == item.id }
            thumbnails.removeValue(forKey: item.id)
            metadataStore.remove(path: item.filePath)
            metadataByPath.removeValue(forKey: item.filePath)
        } catch {
            SaveService.shared.showError("Could not delete clip: \(error.localizedDescription)")
        }
    }

    func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.type {
        case .screenshot:
            if let image = NSImage(contentsOf: item.url) {
                pasteboard.writeObjects([image])
            }
        case .video, .gif:
            pasteboard.writeObjects([item.url as NSURL])
        }
    }

    func revealInFinder(_ item: ClipItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func displayName(for item: ClipItem) -> String {
        let customName = metadataByPath[item.filePath]?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let customName, !customName.isEmpty {
            return customName
        }
        return item.url.lastPathComponent
    }

    func note(for item: ClipItem) -> String {
        metadataByPath[item.filePath]?.notes ?? ""
    }

    func isFavorite(_ item: ClipItem) -> Bool {
        metadataByPath[item.filePath]?.isFavorite ?? false
    }

    func tags(for item: ClipItem) -> [String] {
        metadataByPath[item.filePath]?.tags ?? []
    }

    func setDisplayName(_ item: ClipItem, name: String) {
        metadataStore.upsert(path: item.filePath) { metadata in
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata.displayName = trimmedName.isEmpty ? nil : trimmedName
        }
        metadataByPath = metadataStore.metadataMap()
    }

    func toggleFavorite(_ item: ClipItem) {
        metadataStore.upsert(path: item.filePath) { metadata in
            metadata.isFavorite.toggle()
        }
        metadataByPath = metadataStore.metadataMap()
    }

    func setTags(_ item: ClipItem, tags: [String]) {
        metadataStore.upsert(path: item.filePath) { metadata in
            metadata.tags = tags
        }
        metadataByPath = metadataStore.metadataMap()
    }

    func setNotes(_ item: ClipItem, notes: String) {
        metadataStore.upsert(path: item.filePath) { metadata in
            metadata.notes = notes
        }
        metadataByPath = metadataStore.metadataMap()
    }

    func collection(for item: ClipItem) -> String {
        metadataByPath[item.filePath]?.collection ?? ""
    }

    func setCollection(_ item: ClipItem, collection: String) {
        metadataStore.upsert(path: item.filePath) { metadata in
            let trimmed = collection.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata.collection = trimmed.isEmpty ? nil : trimmed
        }
        metadataByPath = metadataStore.metadataMap()
    }

    var availableTags: [String] {
        let tags = clips.flatMap { self.tags(for: $0) }
        return Array(Set(tags)).sorted()
    }

    var availableCollections: [String] {
        let values = clips.map { collection(for: $0) }.filter { !$0.isEmpty }
        return Array(Set(values)).sorted()
    }

    func isSelected(_ item: ClipItem) -> Bool {
        selectedClipIDs.contains(item.id)
    }

    func toggleSelection(_ item: ClipItem) {
        if selectedClipIDs.contains(item.id) {
            selectedClipIDs.remove(item.id)
        } else {
            selectedClipIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedClipIDs.removeAll()
    }

    var selectedItems: [ClipItem] {
        clips.filter { selectedClipIDs.contains($0.id) }
    }

    func deleteSelected() {
        let items = selectedItems
        for item in items {
            delete(item)
        }
        clearSelection()
    }

    func favoriteSelected() {
        for item in selectedItems where !isFavorite(item) {
            toggleFavorite(item)
        }
    }

    func addTagToSelected(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return }
        for item in selectedItems {
            var current = tags(for: item)
            if !current.contains(cleaned) {
                current.append(cleaned)
                setTags(item, tags: current)
            }
        }
    }

    func editClip(_ item: ClipItem) {
        switch item.type {
        case .screenshot:
            presentScreenshotEditor(item)
        case .video:
            presentVideoTrimmer(item)
        case .gif:
            presentGifTrimmer(item)
        }
    }

    private func presentScreenshotEditor(_ item: ClipItem) {
        var windowRef: ScreenshotEditorWindow?
        let window = ScreenshotEditorWindow(imageURL: item.url) { [weak self] _ in
            DispatchQueue.main.async {
                if let windowRef {
                    self?.releaseEditorWindow(windowRef)
                }
                self?.load()
            }
        }
        windowRef = window
        retainEditorWindow(window)
    }

    private func presentVideoTrimmer(_ item: ClipItem) {
        var windowRef: VideoTrimmerWindow?
        let window = VideoTrimmerWindow(videoURL: item.url) { [weak self] _ in
            DispatchQueue.main.async {
                if let windowRef {
                    self?.releaseEditorWindow(windowRef)
                }
                self?.load()
            }
        }
        windowRef = window
        retainEditorWindow(window)
    }

    private func presentGifTrimmer(_ item: ClipItem) {
        guard let gifData = makeGifCaptureData(from: item.url) else {
            SaveService.shared.showError("Could not load GIF frames for trimming.")
            return
        }

        let outputURL = item.url.deletingLastPathComponent()
            .appendingPathComponent(item.url.deletingPathExtension().lastPathComponent + " (trimmed)")
            .appendingPathExtension("gif")

        var windowRef: GifTrimmerWindow?
        let window = GifTrimmerWindow(gifData: gifData, outputURL: outputURL) { [weak self] _ in
            DispatchQueue.main.async {
                if let windowRef {
                    self?.releaseEditorWindow(windowRef)
                }
                self?.load()
            }
        }
        windowRef = window
        retainEditorWindow(window)
    }

    private func retainEditorWindow(_ window: NSWindow) {
        editorWindows.append(window)
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func releaseEditorWindow(_ window: NSWindow) {
        editorWindows.removeAll { $0 === window }
    }

    private func makeGifCaptureData(from url: URL) -> GifCaptureData? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var frameDelay: Double = 0.08
        var maxWidth: CGFloat = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(cgImage)
            maxWidth = max(maxWidth, CGFloat(cgImage.width))

            if index == 0,
               let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
                    frameDelay = unclamped
                } else if let delayed = gifDict[kCGImagePropertyGIFDelayTime] as? Double {
                    frameDelay = delayed
                }
            }
        }

        guard !frames.isEmpty else { return nil }
        return GifCaptureData(frames: frames, frameDelay: frameDelay, maxWidth: maxWidth)
    }

    private func matchesSearch(item: ClipItem, query: String) -> Bool {
        let loweredQuery = query.lowercased()
        let tokens = loweredQuery.split(separator: " ").map(String.init)
        let itemTags = tags(for: item)
        let itemNote = note(for: item).lowercased()
        let itemName = displayName(for: item).lowercased()

        for token in tokens where token.contains(":") {
            if token.hasPrefix("type:") {
                let value = String(token.dropFirst(5))
                if value == "video" && item.type != .video { return false }
                if value == "gif" && item.type != .gif { return false }
                if (value == "shot" || value == "screenshot" || value == "image") && item.type != .screenshot { return false }
            } else if token.hasPrefix("tag:") {
                let value = String(token.dropFirst(4))
                if !itemTags.contains(where: { $0.lowercased() == value }) { return false }
            }
        }

        if loweredQuery.contains("fav") || loweredQuery.contains("favorite") {
            if !isFavorite(item) { return false }
        }

        if loweredQuery.contains("today") && !Calendar.current.isDateInToday(item.date) {
            return false
        }

        let plainTerms = tokens.filter { !$0.contains(":") }
        if plainTerms.isEmpty { return true }

        let searchable = [itemName, item.url.lastPathComponent.lowercased(), itemTags.joined(separator: " ").lowercased(), itemNote]
            .joined(separator: " ")
        return plainTerms.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
    }
}

// MARK: - Clips Manager Content View

private struct ClipsManagerContentView: View {
    @StateObject private var viewModel = ClipsViewModel()
    @State private var renameClip: ClipItem?
    @State private var tagEditorClip: ClipItem?
    @State private var notesClip: ClipItem?
    @State private var detailClip: ClipItem?
    @State private var collectionClip: ClipItem?
    @State private var batchTag = ""

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .onAppear { viewModel.load() }
        .popover(item: $renameClip) { item in
            ClipRenamePopover(
                currentName: viewModel.displayName(for: item),
                onSave: { newName in
                    viewModel.setDisplayName(item, name: newName)
                    renameClip = nil
                },
                onCancel: {
                    renameClip = nil
                }
            )
        }
        .popover(item: $tagEditorClip) { item in
            ClipTagEditorPopover(
                initialTags: viewModel.tags(for: item),
                onSave: { tags in
                    viewModel.setTags(item, tags: tags)
                    tagEditorClip = nil
                },
                onCancel: {
                    tagEditorClip = nil
                }
            )
        }
        .popover(item: $notesClip) { item in
            ClipNotesPopover(
                initialNotes: viewModel.note(for: item),
                onSave: { notes in
                    viewModel.setNotes(item, notes: notes)
                    notesClip = nil
                },
                onCancel: {
                    notesClip = nil
                }
            )
        }
        .popover(item: $detailClip) { item in
            ClipDetailPopover(
                item: item,
                title: viewModel.displayName(for: item),
                tags: viewModel.tags(for: item),
                notes: viewModel.note(for: item),
                collection: viewModel.collection(for: item),
                isFavorite: viewModel.isFavorite(item),
                onToggleFavorite: { viewModel.toggleFavorite(item) },
                onRename: {
                    detailClip = nil
                    renameClip = item
                },
                onEditTags: {
                    detailClip = nil
                    tagEditorClip = item
                },
                onEditNotes: {
                    detailClip = nil
                    notesClip = item
                },
                onEditCollection: {
                    detailClip = nil
                    collectionClip = item
                },
                onEditMedia: { viewModel.editClip(item) },
                onReveal: { viewModel.revealInFinder(item) }
            )
        }
        .popover(item: $collectionClip) { item in
            ClipCollectionPopover(
                initialCollection: viewModel.collection(for: item),
                suggestions: viewModel.availableCollections,
                onSave: { value in
                    viewModel.setCollection(item, collection: value)
                    collectionClip = nil
                },
                onCancel: {
                    collectionClip = nil
                }
            )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Filter picker
            Picker("Filter", selection: $viewModel.filterType) {
                ForEach(ClipsViewModel.FilterType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            // Sort picker
            Picker("Sort", selection: $viewModel.sortOption) {
                ForEach(ClipsViewModel.SortOption.allCases, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Picker("Date", selection: $viewModel.dateFilter) {
                ForEach(ClipsViewModel.DateFilter.allCases, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Picker("Tag", selection: $viewModel.selectedTag) {
                Text("All Tags").tag("")
                ForEach(viewModel.availableTags, id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Picker("Collection", selection: $viewModel.selectedCollection) {
                Text("All Collections").tag("")
                ForEach(viewModel.availableCollections, id: \.self) { collection in
                    Text(collection).tag(collection)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Spacer()

            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            // View mode toggle
            Picker("View Mode", selection: $viewModel.viewMode) {
                Image(systemName: "square.grid.2x2").tag(ClipsViewModel.ViewMode.grid)
                Image(systemName: "list.bullet").tag(ClipsViewModel.ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 64)

            // Refresh button
            Button {
                viewModel.load()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button(viewModel.selectionMode ? "Done" : "Select") {
                viewModel.selectionMode.toggle()
                if !viewModel.selectionMode {
                    viewModel.clearSelection()
                }
            }

            if viewModel.selectionMode {
                HStack(spacing: 6) {
                    Text("\(viewModel.selectedItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Favorite") { viewModel.favoriteSelected() }
                        .disabled(viewModel.selectedItems.isEmpty)
                    Button("Delete", role: .destructive) { viewModel.deleteSelected() }
                        .disabled(viewModel.selectedItems.isEmpty)
                    TextField("Tag", text: $batchTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Add Tag") {
                        viewModel.addTagToSelected(batchTag)
                        batchTag = ""
                    }
                    .disabled(viewModel.selectedItems.isEmpty || batchTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading clips…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredSortedClips.isEmpty {
            emptyState
        } else {
            switch viewModel.viewMode {
            case .grid:
                gridContent
            case .list:
                listContent
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(viewModel.searchText.isEmpty && viewModel.filterType == .all
                 ? "No clips found"
                 : "No clips match your filter")
                .font(.headline)
                .foregroundStyle(.secondary)
            if viewModel.searchText.isEmpty && viewModel.filterType == .all {
                Text("Captures will appear here after you take screenshots, record videos, or create GIFs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid View

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(viewModel.filteredSortedClips) { item in
                    ClipGridCell(
                        item: item,
                        title: viewModel.displayName(for: item),
                        tags: viewModel.tags(for: item),
                        notes: viewModel.note(for: item),
                        isFavorite: viewModel.isFavorite(item),
                        isSelectionMode: viewModel.selectionMode,
                        isSelected: viewModel.isSelected(item),
                        thumbnail: viewModel.thumbnails[item.id],
                        onDelete: { viewModel.delete(item) },
                        onCopy: { viewModel.copyToClipboard(item) },
                        onReveal: { viewModel.revealInFinder(item) },
                        onToggleFavorite: { viewModel.toggleFavorite(item) },
                        onRename: { renameClip = item },
                        onEditTags: { tagEditorClip = item },
                        onEditNotes: { notesClip = item },
                        onEditCollection: { collectionClip = item },
                        onOpenDetails: { detailClip = item },
                        onEditMedia: { viewModel.editClip(item) },
                        onToggleSelection: { viewModel.toggleSelection(item) }
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - List View

    private var listContent: some View {
        List(viewModel.filteredSortedClips) { item in
            ClipListRow(
                item: item,
                title: viewModel.displayName(for: item),
                tags: viewModel.tags(for: item),
                notes: viewModel.note(for: item),
                isFavorite: viewModel.isFavorite(item),
                isSelectionMode: viewModel.selectionMode,
                isSelected: viewModel.isSelected(item),
                thumbnail: viewModel.thumbnails[item.id],
                onDelete: { viewModel.delete(item) },
                onCopy: { viewModel.copyToClipboard(item) },
                onReveal: { viewModel.revealInFinder(item) },
                onToggleFavorite: { viewModel.toggleFavorite(item) },
                onRename: { renameClip = item },
                onEditTags: { tagEditorClip = item },
                onEditNotes: { notesClip = item },
                onEditCollection: { collectionClip = item },
                onOpenDetails: { detailClip = item },
                onEditMedia: { viewModel.editClip(item) },
                onToggleSelection: { viewModel.toggleSelection(item) }
            )
        }
        .listStyle(.plain)
    }
}

// MARK: - Grid Cell

private struct ClipGridCell: View {
    let item: ClipItem
    let title: String
    let tags: [String]
    let notes: String
    let isFavorite: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let thumbnail: NSImage?
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onToggleFavorite: () -> Void
    let onRename: () -> Void
    let onEditTags: () -> Void
    let onEditNotes: () -> Void
    let onEditCollection: () -> Void
    let onOpenDetails: () -> Void
    let onEditMedia: () -> Void
    let onToggleSelection: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(4/3, contentMode: .fit)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .aspectRatio(4/3, contentMode: .fit)
                } else {
                    Image(systemName: item.typeIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }

                // Hover overlay
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.4))
                        .aspectRatio(4/3, contentMode: .fit)
                    HStack(spacing: 12) {
                        cellButton(icon: "doc.on.doc", help: "Copy", action: onCopy)
                        cellButton(icon: "folder", help: "Reveal in Finder", action: onReveal)
                    }
                }

                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onToggleSelection) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? .green : .white.opacity(0.9))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                        }
                        Spacer()
                    }
                }

                // Type badge
                VStack {
                    HStack {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isFavorite ? .yellow : .white.opacity(0.85))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)

                        Spacer()
                        Text(item.typeLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                    Spacer()
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture {
                if isSelectionMode {
                    onToggleSelection()
                } else {
                    onOpenDetails()
                }
            }
            .onTapGesture(count: 2) {
                if !isSelectionMode {
                    onReveal()
                }
            }

            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !tags.isEmpty {
                    Text(tags.prefix(2).joined(separator: " • "))
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
                Text(item.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button(isFavorite ? "Remove Favorite" : "Add Favorite") { onToggleFavorite() }
            Button("Rename…") { onRename() }
            Button("Edit Tags…") { onEditTags() }
            Button("Edit Notes…") { onEditNotes() }
            Button("Set Collection…") { onEditCollection() }
            Button("Details…") { onOpenDetails() }
            Button(item.type == .screenshot ? "Edit Screenshot…" : "Trim Clip…") { onEditMedia() }
            Divider()
            Button("Open in Finder") { onReveal() }
            Button("Copy") { onCopy() }
            Divider()
            ShareLink(item: item.url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func cellButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - List Row

private struct ClipListRow: View {
    let item: ClipItem
    let title: String
    let tags: [String]
    let notes: String
    let isFavorite: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let thumbnail: NSImage?
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onToggleFavorite: () -> Void
    let onRename: () -> Void
    let onEditTags: () -> Void
    let onEditNotes: () -> Void
    let onEditCollection: () -> Void
    let onOpenDetails: () -> Void
    let onEditMedia: () -> Void
    let onToggleSelection: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .green : .secondary)
                }
                .buttonStyle(.borderless)
            }

            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 60, height: 45)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: item.typeIcon)
                        .foregroundStyle(.secondary)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 8) {
                    Label(item.typeLabel, systemImage: item.typeIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(Self.dateFormatter.string(from: item.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !tags.isEmpty {
                    Text(tags.joined(separator: " • "))
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                if !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                Button("Rename") { onRename() }
                    .buttonStyle(.borderless)
                Button("Tags") { onEditTags() }
                    .buttonStyle(.borderless)
                Button("Notes") { onEditNotes() }
                    .buttonStyle(.borderless)
                Button("Collection") { onEditCollection() }
                    .buttonStyle(.borderless)
                Button(item.type == .screenshot ? "Edit" : "Trim") { onEditMedia() }
                    .buttonStyle(.borderless)
                Button("Info") { onOpenDetails() }
                    .buttonStyle(.borderless)
                Button("Copy") { onCopy() }
                    .buttonStyle(.borderless)
                Button("Show") { onReveal() }
                    .buttonStyle(.borderless)
                ShareLink(item: item.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelectionMode {
                onOpenDetails()
            }
        }
        .contextMenu {
            Button(isFavorite ? "Remove Favorite" : "Add Favorite") { onToggleFavorite() }
            Button("Rename…") { onRename() }
            Button("Edit Tags…") { onEditTags() }
            Button("Edit Notes…") { onEditNotes() }
            Button("Set Collection…") { onEditCollection() }
            Button("Details…") { onOpenDetails() }
            Button(item.type == .screenshot ? "Edit Screenshot…" : "Trim Clip…") { onEditMedia() }
            Divider()
            Button("Open in Finder") { onReveal() }
            Button("Copy") { onCopy() }
            Divider()
            ShareLink(item: item.url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Metadata Popovers

private struct ClipRenamePopover: View {
    let currentName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Clip")
                .font(.headline)
            TextField("Clip Name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(newName) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            newName = currentName
        }
    }
}

private struct ClipTagEditorPopover: View {
    let initialTags: [String]
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    @State private var draftTags: [String] = []
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Tags")
                .font(.headline)

            if !draftTags.isEmpty {
                FlowTagWrap(tags: draftTags) { tag in
                    draftTags.removeAll { $0 == tag }
                }
            }

            HStack {
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addTag()
                }
                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(draftTags) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            draftTags = initialTags
        }
    }

    private func addTag() {
        let normalized = newTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return }
        if !draftTags.contains(normalized) {
            draftTags.append(normalized)
        }
        newTag = ""
    }
}

private struct FlowTagWrap: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 6) {
                    Text(tag)
                        .lineLimit(1)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
        }
    }
}

private struct ClipNotesPopover: View {
    let initialNotes: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clip Notes")
                .font(.headline)
            TextEditor(text: $draft)
                .font(.body)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            draft = initialNotes
        }
    }
}

private struct ClipDetailPopover: View {
    let item: ClipItem
    let title: String
    let tags: [String]
    let notes: String
    let collection: String
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onRename: () -> Void
    let onEditTags: () -> Void
    let onEditNotes: () -> Void
    let onEditCollection: () -> Void
    let onEditMedia: () -> Void
    let onReveal: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(item.url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Label(item.typeLabel, systemImage: item.typeIcon)
                Text("·")
                Text(Self.dateFormatter.string(from: item.date))
                Text("·")
                Text(item.formattedSize)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !tags.isEmpty {
                Text(tags.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !collection.isEmpty {
                Text("Collection: \(collection)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Rename", action: onRename)
                Button("Tags", action: onEditTags)
                Button("Notes", action: onEditNotes)
                Button("Collection", action: onEditCollection)
                Button(item.type == .screenshot ? "Edit" : "Trim", action: onEditMedia)
                Button("Show", action: onReveal)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 360)
    }
}

private struct ClipCollectionPopover: View {
    let initialCollection: String
    let suggestions: [String]
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set Collection")
                .font(.headline)
            TextField("Collection name", text: $draft)
                .textFieldStyle(.roundedBorder)

            if !suggestions.isEmpty {
                Text("Existing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                draft = suggestion
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 80)
            }

            HStack {
                Spacer()
                Button("Clear") { onSave("") }
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            draft = initialCollection
        }
    }
}

// MARK: - Pro Upsell View

#if APPSTORE
private struct ProUpsellView: View {
    @ObservedObject private var storeService = StoreService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)

                    Text("Clips Manager")
                        .font(.largeTitle.bold())

                    Text("Organize and browse all your TinyClips captures in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }

                // Feature list
                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "photo.on.rectangle.angled", text: "Browse screenshots, videos, and GIFs")
                    featureRow(icon: "square.grid.2x2", text: "Grid and list views with thumbnail previews")
                    featureRow(icon: "arrow.up.arrow.down", text: "Sort by date, size, or name — filter by type")
                    featureRow(icon: "doc.on.doc", text: "Quick copy, reveal in Finder, and share")
                    featureRow(icon: "trash", text: "Delete clips directly from the manager")
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Purchase actions
                VStack(spacing: 12) {
                    if let product = storeService.proProduct {
                        Button {
                            Task { await storeService.purchase() }
                        } label: {
                            HStack {
                                if storeService.isPurchasing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Upgrade to Pro — \(product.displayPrice)")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(storeService.isPurchasing)
                    } else if storeService.isLoading {
                        ProgressView("Loading…")
                    } else {
                        Button("Upgrade to Pro") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(true)
                    }

                    Button {
                        Task { await storeService.restore() }
                    } label: {
                        Text("Restore Purchase")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(storeService.isPurchasing)
                }

                if let error = storeService.purchaseError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }
}
#endif
