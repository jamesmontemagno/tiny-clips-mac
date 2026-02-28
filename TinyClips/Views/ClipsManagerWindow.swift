import AppKit
import SwiftUI
import AVFoundation

// MARK: - Clips Manager Window

class ClipsManagerWindow: NSWindow, NSWindowDelegate {
    private var onClose: (() -> Void)?
    private var didClose = false

    convenience init(onClose: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.onClose = onClose
        self.title = "My Clips"
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.minSize = NSSize(width: 600, height: 400)
        self.center()
        self.contentView = NSHostingView(rootView: ClipsManagerView())
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        let callback = onClose
        onClose = nil
        callback?()
    }
}

// MARK: - Clips Manager View

private struct ClipsManagerView: View {
    @StateObject private var viewModel = ClipsManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if viewModel.isLoading {
                loadingState
            } else if viewModel.clips.isEmpty {
                emptyState
            } else {
                clipsContent
            }
        }
        .task { await viewModel.loadClips() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                filterButton(nil, label: "All")
                filterButton(.screenshot, label: "Screenshots")
                filterButton(.video, label: "Videos")
                filterButton(.gif, label: "GIFs")
            }

            Spacer()

            Picker("Sort", selection: $viewModel.sortOrder) {
                Text("Newest First").tag(ClipsManagerViewModel.SortOrder.newestFirst)
                Text("Oldest First").tag(ClipsManagerViewModel.SortOrder.oldestFirst)
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("View", selection: $viewModel.viewMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(ClipsManagerViewModel.ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(ClipsManagerViewModel.ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 72)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func filterButton(_ type: ClipItem.ClipType?, label: String) -> some View {
        Button(action: { viewModel.filterType = type }) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(viewModel.filterType == type ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(viewModel.filterType == type ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var clipsContent: some View {
        Group {
            if viewModel.viewMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)],
                spacing: 12
            ) {
                ForEach(viewModel.filteredClips) { clip in
                    ClipGridItemView(clip: clip) {
                        viewModel.deleteClip(clip)
                    }
                }
            }
            .padding(16)
        }
    }

    private var listContent: some View {
        List(viewModel.filteredClips) { clip in
            ClipListItemView(clip: clip) {
                viewModel.deleteClip(clip)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Empty / Loading State

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading clips…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Clips Yet")
                .font(.headline)
            Text("Screenshots, videos, and GIFs captured with TinyClips will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid Item View

private struct ClipGridItemView: View {
    let clip: ClipItem
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Image(systemName: clip.type.systemImage)
                    .font(.caption2)
                    .padding(4)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(clip.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(clip.url)
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(clip.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([clip.url]) }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .task { await loadThumbnail() }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
                .frame(maxWidth: .infinity)
                .overlay {
                    Image(systemName: clip.type.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func loadThumbnail() async {
        thumbnail = await ClipThumbnailLoader.thumbnail(for: clip)
    }
}

// MARK: - List Item View

private struct ClipListItemView: View {
    let clip: ClipItem
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: clip.type.systemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 56, height: 40)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(clip.type.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(clip.url)
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(clip.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([clip.url]) }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        thumbnail = await ClipThumbnailLoader.thumbnail(for: clip)
    }
}

// MARK: - Thumbnail Loader

enum ClipThumbnailLoader {
    static func thumbnail(for clip: ClipItem) async -> NSImage? {
        switch clip.type {
        case .screenshot, .gif:
            return NSImage(contentsOf: clip.url)
        case .video:
            return await videoThumbnail(url: clip.url)
        }
    }

    private static func videoThumbnail(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 240)
        do {
            let (image, _) = try await generator.image(at: .zero)
            return NSImage(cgImage: image, size: .zero)
        } catch {
            return nil
        }
    }
}

// MARK: - View Model

@MainActor
class ClipsManagerViewModel: ObservableObject {
    enum SortOrder { case newestFirst, oldestFirst }
    enum ViewMode { case grid, list }

    @Published var clips: [ClipItem] = []
    @Published var isLoading = false
    @Published var filterType: ClipItem.ClipType?
    @Published var sortOrder: SortOrder = .newestFirst
    @Published var viewMode: ViewMode = .grid

    var filteredClips: [ClipItem] {
        let base = filterType == nil ? clips : clips.filter { $0.type == filterType }
        return base.sorted {
            switch sortOrder {
            case .newestFirst: return $0.createdAt > $1.createdAt
            case .oldestFirst: return $0.createdAt < $1.createdAt
            }
        }
    }

    func loadClips() async {
        isLoading = true
        clips = await scanForClips()
        isLoading = false
    }

    func deleteClip(_ clip: ClipItem) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(clip.url.lastPathComponent)\"?"
        alert.informativeText = "This will permanently delete the file from disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.removeItem(at: clip.url)
            clips.removeAll { $0.id == clip.id }
        } catch {
            SaveService.shared.showError("Could not delete \"\(clip.url.lastPathComponent)\": \(error.localizedDescription)")
        }
    }

    private func scanForClips() async -> [ClipItem] {
        let (directories, securityScopedURLs) = clipDirectories()
        var items: [ClipItem] = []
        for dir in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.lastPathComponent.hasPrefix(ClipItem.fileNamePrefix) else { continue }
                if let item = ClipItem.from(url: url) {
                    items.append(item)
                }
            }
        }
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        return items
    }

    private func clipDirectories() -> (dirs: [URL], securityScopedURLs: [URL]) {
#if APPSTORE
        var dirs: [URL] = []
        var securityScopedURLs: [URL] = []
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            dirs.append(pictures.appendingPathComponent("TinyClips"))
        }
        if let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            dirs.append(movies.appendingPathComponent("TinyClips"))
        }
        if let bookmarkData = UserDefaults.standard.data(forKey: "saveDirectoryBookmark"),
           !bookmarkData.isEmpty {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() {
                dirs.append(url)
                securityScopedURLs.append(url)
            }
        }
        return (dirs, securityScopedURLs)
#else
        let saveDir = UserDefaults.standard.string(forKey: "saveDirectory")
            ?? (NSHomeDirectory() + "/Desktop")
        return ([URL(fileURLWithPath: saveDir)], [])
#endif
    }
}
