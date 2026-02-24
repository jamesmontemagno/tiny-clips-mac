import AppKit
import SwiftUI
import AVFoundation

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
}

// MARK: - Clips View Model

@MainActor
private class ClipsViewModel: ObservableObject {
    @Published var clips: [ClipItem] = []
    @Published var thumbnails: [UUID: NSImage] = [:]
    @Published var isLoading = false
    @Published var sortOption: SortOption = .newest
    @Published var filterType: FilterType = .all
    @Published var viewMode: ViewMode = .grid
    @Published var searchText = ""

#if APPSTORE
    private var activeScopedURL: URL?
#endif

    enum SortOption: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case largest = "Largest"
        case name = "Name"
    }

    enum FilterType: String, CaseIterable {
        case all = "All"
        case screenshots = "Screenshots"
        case videos = "Videos"
        case gifs = "GIFs"
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
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOption {
        case .newest: result = result.sorted { $0.date > $1.date }
        case .oldest: result = result.sorted { $0.date < $1.date }
        case .largest: result = result.sorted { $0.fileSize > $1.fileSize }
        case .name: result = result.sorted {
                $0.url.lastPathComponent < $1.url.lastPathComponent
            }
        }

        return result
    }

    // MARK: - Loading

    func load() {
        isLoading = true
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
                    if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
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
}

// MARK: - Clips Manager Content View

private struct ClipsManagerContentView: View {
    @StateObject private var viewModel = ClipsViewModel()

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
                        thumbnail: viewModel.thumbnails[item.id],
                        onDelete: { viewModel.delete(item) },
                        onCopy: { viewModel.copyToClipboard(item) },
                        onReveal: { viewModel.revealInFinder(item) }
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
                thumbnail: viewModel.thumbnails[item.id],
                onDelete: { viewModel.delete(item) },
                onCopy: { viewModel.copyToClipboard(item) },
                onReveal: { viewModel.revealInFinder(item) }
            )
        }
        .listStyle(.plain)
    }
}

// MARK: - Grid Cell

private struct ClipGridCell: View {
    let item: ClipItem
    let thumbnail: NSImage?
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void

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

                // Type badge
                VStack {
                    HStack {
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
            .onTapGesture(count: 2) { onReveal() }

            VStack(spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
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
    let thumbnail: NSImage?
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
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
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
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
        .contextMenu {
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
                        .foregroundStyle(.accent)

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
                .foregroundStyle(.accent)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }
}
#endif
