import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Window

class ScreenshotEditorWindow: NSWindow, NSWindowDelegate {
    private var onComplete: ((URL?) -> Void)?
    private var didComplete = false

    convenience init(imageURL: URL, onComplete: @escaping (URL?) -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.onComplete = onComplete
        self.title = "Edit Screenshot"
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.minSize = NSSize(width: 560, height: 460)
        self.center()

        let editorView = ScreenshotEditorView(imageURL: imageURL) { [weak self] resultURL in
            self?.completeWith(resultURL)
        }
        self.contentView = NSHostingView(rootView: editorView)
    }

    private func completeWith(_ url: URL?) {
        guard !didComplete, let callback = onComplete else { return }
        didComplete = true
        onComplete = nil
        callback(url)
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        completeWith(nil)
        return true
    }
}

// MARK: - Tool Type

private enum EditTool: String, CaseIterable {
    case move = "arrow.up.and.down.and.arrow.left.and.right"
    case crop = "crop"
    case rectangle = "rectangle"
    case circle = "circle"
    case arrow = "arrow.up.right"
    case line = "line.diagonal"
    case pencil = "pencil.tip"
    case text = "textformat"
    case blur = "eye.slash"

    var label: String {
        switch self {
        case .move: return "Move"
        case .crop: return "Crop"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .pencil: return "Draw"
        case .text: return "Text"
        case .blur: return "Redact"
        }
    }
}

// MARK: - Annotation

private struct Annotation: Identifiable {
    let id = UUID()
    let tool: EditTool
    var rect: CGRect
    var color: Color
    var lineWidth: CGFloat
    var text: String
    var points: [CGPoint] // for pencil
    var fontSize: CGFloat = 16 // for text annotations
}

private typealias LinePoints = (start: CGPoint, end: CGPoint)

// MARK: - Editor View

private struct ScreenshotEditorView: View {
    let imageURL: URL
    let onDone: (URL?) -> Void

    @StateObject private var viewModel: EditorViewModel

    init(imageURL: URL, onDone: @escaping (URL?) -> Void) {
        self.imageURL = imageURL
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: EditorViewModel(url: imageURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Canvas
            GeometryReader { geo in
                CanvasView(viewModel: viewModel, containerSize: geo.size)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            .clipped()

            Divider()

            // Bottom bar
            bottomBar
                .padding(12)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ForEach(EditTool.allCases, id: \.self) { tool in
                Button {
                    viewModel.selectedTool = tool
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tool.rawValue)
                            .font(.system(size: 14))
                            .frame(width: 28, height: 22)
                        Text(tool.label)
                            .font(.system(size: 9))
                    }
                    .frame(width: 52, height: 42)
                    .contentShape(Rectangle())
                    .background(viewModel.selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Color picker
            ColorPicker("", selection: $viewModel.selectedColor)
                .labelsHidden()
                .frame(width: 30)

            // Line width
            Picker("", selection: $viewModel.lineWidth) {
                Text("Thin").tag(CGFloat(2))
                Text("Medium").tag(CGFloat(4))
                Text("Thick").tag(CGFloat(6))
            }
            .labelsHidden()
            .frame(width: 90)

            // Undo
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(viewModel.annotations.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
        }
    }

    private var bottomBar: some View {
        HStack {
            // Image info & save options
            if let img = viewModel.originalImage {
                let rep = img.representations.first
                Text("\(Int(rep?.pixelsWide ?? 0)) × \(Int(rep?.pixelsHigh ?? 0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Format:", selection: $viewModel.saveFormat) {
                ForEach(ImageFormat.allCases, id: \.self) { format in
                    Text(format.label).tag(format)
                }
            }
            .frame(width: 140)

            Picker("Scale:", selection: $viewModel.saveScale) {
                Text("100%").tag(100)
                Text("75%").tag(75)
                Text("50%").tag(50)
                Text("25%").tag(25)
            }
            .frame(width: 120)

            if viewModel.saveFormat == .jpeg {
                Slider(value: $viewModel.saveJpegQuality, in: 0.1...1.0, step: 0.05)
                    .frame(width: 80)
                Text("\(Int(viewModel.saveJpegQuality * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }

            Spacer()

            Button("Discard") {
                onDone(nil)
            }
            .keyboardShortcut(.cancelAction)

            Button {
                viewModel.copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button("Save") {
                if let url = viewModel.save() {
                    onDone(url)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Canvas View

private struct CanvasView: View {
    @ObservedObject var viewModel: EditorViewModel
    let containerSize: CGSize

    var body: some View {
        let imageSize = viewModel.displaySize(in: containerSize)
        let origin = CGPoint(
            x: (containerSize.width - imageSize.width) / 2,
            y: (containerSize.height - imageSize.height) / 2
        )

        ZStack(alignment: .topLeading) {
            // Checkered background for transparency
            Color(nsColor: .controlBackgroundColor)

            if let image = viewModel.originalImage {
                // Image
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .position(x: containerSize.width / 2, y: containerSize.height / 2)

                // Annotations layer
                Canvas { context, size in
                    for annotation in viewModel.annotations {
                        let scaledRect = viewModel.scaledRect(annotation.rect, imageSize: imageSize, origin: origin)
                        drawAnnotation(annotation, in: context, scaledRect: scaledRect, imageSize: imageSize, origin: origin)
                    }

                    // Draw in-progress annotation
                    if let current = viewModel.currentAnnotation {
                        let scaledRect = viewModel.scaledRect(current.rect, imageSize: imageSize, origin: origin)
                        drawAnnotation(current, in: context, scaledRect: scaledRect, imageSize: imageSize, origin: origin)
                    }

                    // Draw crop overlay
                    if viewModel.selectedTool == .crop, let cropRect = viewModel.cropRect {
                        let scaled = viewModel.scaledRect(cropRect, imageSize: imageSize, origin: origin)
                        // Dim outside crop
                        var dimPath = Path(CGRect(origin: .zero, size: size))
                        dimPath.addRect(scaled)
                        context.fill(dimPath, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                        // Crop border
                        context.stroke(Path(scaled), with: .color(.white), lineWidth: 2)
                        // Corner handles
                        let handleSize: CGFloat = 8
                        for corner in corners(of: scaled) {
                            let handleRect = CGRect(x: corner.x - handleSize/2, y: corner.y - handleSize/2, width: handleSize, height: handleSize)
                            context.fill(Path(handleRect), with: .color(.white))
                        }
                    }
                }
                .allowsHitTesting(false)

                // Text annotations
                ForEach(viewModel.annotations.filter { $0.tool == .text }) { annotation in
                    let scaledRect = viewModel.scaledRect(annotation.rect, imageSize: imageSize, origin: origin)
                    Text(annotation.text)
                        .font(.system(size: annotation.fontSize))
                        .foregroundColor(annotation.color)
                        .position(x: scaledRect.midX, y: scaledRect.midY)
                        .allowsHitTesting(false)
                }

                // Inline text editing field
                if let textPos = viewModel.textEditPosition {
                    let screenPos = CGPoint(
                        x: origin.x + textPos.x * imageSize.width,
                        y: origin.y + textPos.y * imageSize.height
                    )
                    InlineTextEditor(
                        text: $viewModel.textEditValue,
                        fontSize: $viewModel.textFontSize,
                        color: viewModel.selectedColor,
                        onCommit: {
                            viewModel.commitTextAnnotation()
                        },
                        onCancel: {
                            viewModel.cancelTextAnnotation()
                        }
                    )
                    .position(x: screenPos.x, y: screenPos.y)
                }

                // Selection highlight for move tool
                if viewModel.selectedTool == .move,
                   let idx = viewModel.selectedAnnotationIndex,
                   idx < viewModel.annotations.count {
                    let ann = viewModel.annotations[idx]

                    // Show endpoint handles for arrows and lines
                    if ann.tool == .arrow || ann.tool == .line {
                        let linePoints = viewModel.scaledLinePoints(for: ann, imageSize: imageSize, origin: origin)
                        let startPt = linePoints.start
                        let endPt = linePoints.end

                        // Tail handle (hollow circle)
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 12, height: 12)
                            .position(startPt)
                            .allowsHitTesting(false)

                        // Head handle (filled circle)
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                            .position(endPt)
                            .allowsHitTesting(false)
                    } else if let selRect = viewModel.selectedAnnotationRect(imageSize: imageSize, origin: origin) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: selRect.width + 8, height: selRect.height + 8)
                            .position(x: selRect.midX, y: selRect.midY)
                            .allowsHitTesting(false)
                    }
                }

                // Interaction overlay — gestures must be before .position()
                // so coordinates are in the overlay's local space (0..imageSize)
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: imageSize.width, height: imageSize.height)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let normalizedStart = viewModel.normalizePoint(value.startLocation, imageSize: imageSize)
                                let normalizedCurrent = viewModel.normalizePoint(value.location, imageSize: imageSize)
                                viewModel.handleDrag(start: normalizedStart, current: normalizedCurrent)
                            }
                            .onEnded { value in
                                let normalizedStart = viewModel.normalizePoint(value.startLocation, imageSize: imageSize)
                                let normalizedEnd = viewModel.normalizePoint(value.location, imageSize: imageSize)
                                viewModel.handleDragEnd(start: normalizedStart, end: normalizedEnd)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let normalized = viewModel.normalizePoint(value.location, imageSize: imageSize)
                                if viewModel.selectedTool == .text && viewModel.textEditPosition == nil {
                                    viewModel.textEditPosition = normalized
                                    viewModel.textEditValue = ""
                                    viewModel.isEditingText = true
                                } else if viewModel.selectedTool == .move {
                                    // Tap to select/deselect annotations
                                    if let idx = viewModel.annotationIndex(at: normalized) {
                                        viewModel.selectedAnnotationIndex = idx
                                    } else {
                                        viewModel.selectedAnnotationIndex = nil
                                    }
                                }
                            }
                    )
                    .position(x: containerSize.width / 2, y: containerSize.height / 2)
            }
        }
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    private func drawAnnotation(_ annotation: Annotation, in context: GraphicsContext, scaledRect: CGRect, imageSize: CGSize, origin: CGPoint) {
        let color = annotation.color
        let lineWidth = annotation.lineWidth

        switch annotation.tool {
        case .rectangle:
            context.stroke(Path(scaledRect), with: .color(color), lineWidth: lineWidth)

        case .circle:
            context.stroke(Path(ellipseIn: scaledRect), with: .color(color), lineWidth: lineWidth)

        case .arrow:
            var path = Path()
            let linePoints = viewModel.scaledLinePoints(for: annotation, imageSize: imageSize, origin: origin)
            let start = linePoints.start
            let end = linePoints.end
            path.move(to: start)
            path.addLine(to: end)

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 14
            let headAngle: CGFloat = .pi / 6
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y - headLength * sin(angle - headAngle)
            ))
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y - headLength * sin(angle + headAngle)
            ))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

        case .line:
            var path = Path()
            let linePoints = viewModel.scaledLinePoints(for: annotation, imageSize: imageSize, origin: origin)
            path.move(to: linePoints.start)
            path.addLine(to: linePoints.end)
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

        case .pencil:
            if annotation.points.count > 1 {
                var path = Path()
                let scaledPoints = annotation.points.map { pt in
                    CGPoint(
                        x: origin.x + pt.x * imageSize.width,
                        y: origin.y + pt.y * imageSize.height
                    )
                }
                path.move(to: scaledPoints[0])
                for pt in scaledPoints.dropFirst() {
                    path.addLine(to: pt)
                }
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
            }

        case .blur:
            // Draw a pixelated/redacted fill
            let blockSize: CGFloat = 10
            let cols = max(1, Int(scaledRect.width / blockSize))
            let rows = max(1, Int(scaledRect.height / blockSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let brightness = Double((row + col) % 3) * 0.15 + 0.15
                    let blockRect = CGRect(
                        x: scaledRect.minX + CGFloat(col) * blockSize,
                        y: scaledRect.minY + CGFloat(row) * blockSize,
                        width: blockSize,
                        height: blockSize
                    )
                    context.fill(Path(blockRect), with: .color(.gray.opacity(0.6 + brightness)))
                }
            }

        case .text, .crop, .move:
            break
        }
    }
}

// MARK: - ViewModel

private class EditorViewModel: ObservableObject {
    let sourceURL: URL
    @Published var originalImage: NSImage?
    @Published var selectedTool: EditTool = .move
    @Published var selectedColor: Color = .red
    @Published var lineWidth: CGFloat = 4
    @Published var annotations: [Annotation] = []
    @Published var currentAnnotation: Annotation?
    @Published var cropRect: CGRect?
    @Published var isEditingText = false
    @Published var textEditPosition: CGPoint? // normalized click position
    @Published var textEditValue: String = ""
    @Published var textFontSize: CGFloat = 16
    @Published var selectedAnnotationIndex: Int?
    @Published var saveFormat: ImageFormat
    @Published var saveScale: Int
    @Published var saveJpegQuality: Double

    private var pencilPoints: [CGPoint] = []
    private var imagePixelSize: CGSize = .zero
    private var dragOffset: CGPoint = .zero
    private var dragOriginalRect: CGRect = .zero
    private var dragOriginalPoints: [CGPoint] = []
    private var isDraggingAnnotation = false
    private var isDraggingEndpoint = false // true = dragging arrowhead/line end
    private var isDraggingStartpoint = false // true = dragging arrow tail/line start

    init(url: URL) {
        self.sourceURL = url
        let settings = CaptureSettings.shared
        self.saveFormat = settings.imageFormat
        self.saveScale = settings.screenshotScale
        self.saveJpegQuality = settings.jpegQuality
        if let image = NSImage(contentsOf: url) {
            self.originalImage = image
            if let rep = image.representations.first {
                self.imagePixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
        }
    }

    // Convert point in overlay-local space to 0..1 normalized coordinate
    func normalizePoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(1, point.x / imageSize.width)),
            y: max(0, min(1, point.y / imageSize.height))
        )
    }

    // Convert normalized rect to screen rect
    func scaledRect(_ rect: CGRect, imageSize: CGSize, origin: CGPoint) -> CGRect {
        CGRect(
            x: origin.x + rect.origin.x * imageSize.width,
            y: origin.y + rect.origin.y * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    func scaledPoint(_ point: CGPoint, imageSize: CGSize, origin: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + point.x * imageSize.width,
            y: origin.y + point.y * imageSize.height
        )
    }

    func linePoints(for annotation: Annotation) -> LinePoints {
        if annotation.points.count >= 2 {
            return (annotation.points[0], annotation.points[1])
        }
        return (
            start: annotation.rect.origin,
            end: CGPoint(x: annotation.rect.origin.x + annotation.rect.width,
                         y: annotation.rect.origin.y + annotation.rect.height)
        )
    }

    func scaledLinePoints(for annotation: Annotation, imageSize: CGSize, origin: CGPoint) -> LinePoints {
        let points = linePoints(for: annotation)
        return (
            start: scaledPoint(points.start, imageSize: imageSize, origin: origin),
            end: scaledPoint(points.end, imageSize: imageSize, origin: origin)
        )
    }

    func directedRect(from points: LinePoints) -> CGRect {
        CGRect(
            x: points.start.x,
            y: points.start.y,
            width: points.end.x - points.start.x,
            height: points.end.y - points.start.y
        )
    }

    // Calculate display size maintaining aspect ratio
    func displaySize(in containerSize: CGSize) -> CGSize {
        guard let image = originalImage, image.size.width > 0, image.size.height > 0 else {
            return .zero
        }
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width * 0.95
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height * 0.95
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    // Find which annotation is at a normalized point
    func annotationIndex(at point: CGPoint) -> Int? {
        // Search in reverse so topmost (last drawn) is picked first
        for i in annotations.indices.reversed() {
            let ann = annotations[i]
            if ann.tool == .pencil {
                if let bounds = pencilBounds(for: ann), bounds.insetBy(dx: -0.02, dy: -0.02).contains(point) {
                    return i
                }
            } else {
                let hitRect: CGRect
                if ann.tool == .arrow || ann.tool == .line {
                        let line = linePoints(for: ann)
                        if distanceFromPoint(point, toLineSegmentStart: line.start, end: line.end) <= 0.02 {
                            return i
                        }
                        continue
                } else if ann.tool == .text {
                    // Text annotations need a larger hit area since the visual text
                    // size doesn't scale with the normalized rect
                    hitRect = ann.rect.insetBy(dx: -0.03, dy: -0.03)
                } else {
                    hitRect = ann.rect.insetBy(dx: -0.01, dy: -0.01)
                }
                if hitRect.contains(point) {
                    return i
                }
            }
        }
        return nil
    }

    func pencilBounds(for annotation: Annotation) -> CGRect? {
        guard !annotation.points.isEmpty else { return nil }
        var minX = annotation.points[0].x, maxX = minX
        var minY = annotation.points[0].y, maxY = minY
        for pt in annotation.points.dropFirst() {
            minX = min(minX, pt.x); maxX = max(maxX, pt.x)
            minY = min(minY, pt.y); maxY = max(maxY, pt.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func selectedAnnotationRect(imageSize: CGSize, origin: CGPoint) -> CGRect? {
        guard let idx = selectedAnnotationIndex, idx < annotations.count else { return nil }
        let ann = annotations[idx]
        let normRect: CGRect
        if ann.tool == .pencil, let bounds = pencilBounds(for: ann) {
            normRect = bounds
        } else {
            normRect = ann.rect
        }
        return scaledRect(normRect, imageSize: imageSize, origin: origin)
    }

    func handleDrag(start: CGPoint, current: CGPoint) {
        switch selectedTool {
        case .move:
            if !isDraggingAnnotation && !isDraggingEndpoint && !isDraggingStartpoint {
                // First drag event — find what we hit
                if let idx = annotationIndex(at: start) {
                    selectedAnnotationIndex = idx
                    dragOriginalRect = annotations[idx].rect
                    dragOriginalPoints = annotations[idx].points

                    let ann = annotations[idx]
                    if ann.tool == .arrow || ann.tool == .line {
                        if dragOriginalPoints.count < 2 {
                            let line = linePoints(for: ann)
                            dragOriginalPoints = [line.start, line.end]
                        }
                        // Check if near the head (end) or tail (start) endpoint
                        let line = linePoints(for: ann)
                        let endPt = line.end
                        let startPt = line.start
                        let distToEnd = hypot(start.x - endPt.x, start.y - endPt.y)
                        let distToStart = hypot(start.x - startPt.x, start.y - startPt.y)
                        let threshold: CGFloat = 0.04

                        if distToEnd < threshold && distToEnd <= distToStart {
                            isDraggingEndpoint = true
                        } else if distToStart < threshold && distToStart < distToEnd {
                            isDraggingStartpoint = true
                        } else {
                            isDraggingAnnotation = true
                        }
                    } else {
                        isDraggingAnnotation = true
                    }
                } else {
                    selectedAnnotationIndex = nil
                }
            }
            if let idx = selectedAnnotationIndex {
                let dx = current.x - start.x
                let dy = current.y - start.y
                if isDraggingEndpoint {
                    // Move just the endpoint (rotate the arrow/line)
                    var ann = annotations[idx]
                    let orig = originalLinePoints()
                    let updated: LinePoints = (
                        start: orig.start,
                        end: CGPoint(x: orig.end.x + dx, y: orig.end.y + dy)
                    )
                    ann.points = [updated.start, updated.end]
                    ann.rect = directedRect(from: updated)
                    annotations[idx] = ann
                } else if isDraggingStartpoint {
                    // Move the start point (reverse rotate)
                    var ann = annotations[idx]
                    let orig = originalLinePoints()
                    let updated: LinePoints = (
                        start: CGPoint(x: orig.start.x + dx, y: orig.start.y + dy),
                        end: orig.end
                    )
                    ann.points = [updated.start, updated.end]
                    ann.rect = directedRect(from: updated)
                    annotations[idx] = ann
                } else if isDraggingAnnotation {
                    moveAnnotation(at: idx, dx: dx, dy: dy)
                }
            }

        case .crop:
            let rect = makeRect(from: start, to: current)
            cropRect = rect

        case .pencil:
            pencilPoints.append(current)
            currentAnnotation = Annotation(
                tool: .pencil,
                rect: .zero,
                color: selectedColor,
                lineWidth: lineWidth,
                text: "",
                points: pencilPoints
            )

        case .text:
            break // text uses click, not drag

        default:
            let rect = makeRect(from: start, to: current)
            currentAnnotation = Annotation(
                tool: selectedTool,
                rect: rect,
                color: selectedColor,
                lineWidth: lineWidth,
                text: "",
                points: (selectedTool == .arrow || selectedTool == .line) ? [start, current] : []
            )
        }
    }

    func handleDragEnd(start: CGPoint, end: CGPoint) {
        switch selectedTool {
        case .move:
            isDraggingAnnotation = false
            isDraggingEndpoint = false
            isDraggingStartpoint = false

        case .crop:
            break

        case .pencil:
            if pencilPoints.count > 1 {
                annotations.append(Annotation(
                    tool: .pencil,
                    rect: .zero,
                    color: selectedColor,
                    lineWidth: lineWidth,
                    text: "",
                    points: pencilPoints
                ))
            }
            pencilPoints = []
            currentAnnotation = nil

        case .text:
            break // handled by SpatialTapGesture

        default:
            let rect = makeRect(from: start, to: end)
            let w = abs(rect.width)
            let h = abs(rect.height)
            if w > 0.005 || h > 0.005 {
                annotations.append(Annotation(
                    tool: selectedTool,
                    rect: rect,
                    color: selectedColor,
                    lineWidth: lineWidth,
                    text: "",
                    points: (selectedTool == .arrow || selectedTool == .line) ? [start, end] : []
                ))
            }
            currentAnnotation = nil
        }
    }

    private func moveAnnotation(at index: Int, dx: CGFloat, dy: CGFloat) {
        var ann = annotations[index]
        if ann.tool == .pencil {
            ann.points = dragOriginalPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        } else if ann.tool == .arrow || ann.tool == .line {
            let base = originalLinePoints()
            let moved: LinePoints = (
                start: CGPoint(x: base.start.x + dx, y: base.start.y + dy),
                end: CGPoint(x: base.end.x + dx, y: base.end.y + dy)
            )
            ann.points = [moved.start, moved.end]
            ann.rect = directedRect(from: moved)
        } else {
            ann.rect = CGRect(
                x: dragOriginalRect.origin.x + dx,
                y: dragOriginalRect.origin.y + dy,
                width: dragOriginalRect.width,
                height: dragOriginalRect.height
            )
        }
        annotations[index] = ann
    }

    func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
        }
        if cropRect != nil {
            cropRect = nil
        }
    }

    func copyToClipboard() {
        guard let output = buildOutputImage() else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([output.image])
    }

    func save() -> URL? {
        guard let output = buildOutputImage() else { return nil }

        // Build output URL with the chosen format extension
        let saveURL = SaveService.shared.generateURL(for: .screenshot, fileExtension: saveFormat.rawValue)
        do {
            try output.data.write(to: saveURL)
            return saveURL
        } catch {
            return nil
        }
    }

    private func buildOutputImage() -> (image: NSImage, data: Data)? {
        guard let rendered = renderFinalImage() else { return nil }

        let scaledImage = scaleImage(rendered, to: saveScale)
        guard let tiffData = scaledImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let imageData: Data?
        switch saveFormat {
        case .png:
            imageData = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: saveJpegQuality])
        }

        guard let data = imageData,
              let outputImage = NSImage(data: data) else { return nil }

        return (outputImage, data)
    }

    private func scaleImage(_ image: NSImage, to percent: Int) -> NSImage {
        guard percent < 100, percent > 0 else { return image }
        let factor = CGFloat(percent) / 100.0
        let newW = Int(image.size.width * factor)
        let newH = Int(image.size.height * factor)
        guard newW > 0 && newH > 0 else { return image }

        let scaled = NSImage(size: NSSize(width: newW, height: newH))
        scaled.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH),
                    from: NSRect(origin: .zero, size: image.size),
                    operation: .copy,
                    fraction: 1.0)
        scaled.unlockFocus()
        return scaled
    }

    // MARK: - Private

    private func originalLinePoints() -> LinePoints {
        if dragOriginalPoints.count >= 2 {
            return (dragOriginalPoints[0], dragOriginalPoints[1])
        }
        return (
            start: dragOriginalRect.origin,
            end: CGPoint(x: dragOriginalRect.origin.x + dragOriginalRect.width,
                         y: dragOriginalRect.origin.y + dragOriginalRect.height)
        )
    }

    private func distanceFromPoint(_ point: CGPoint, toLineSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len2 = dx * dx + dy * dy
        if len2 <= 0.000001 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / len2))
        let proj = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }

    private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        // Arrow/line store start in origin and end in maxX/maxY (can be negative width/height)
        if selectedTool == .arrow || selectedTool == .line {
            return CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
        }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    func commitTextAnnotation() {
        guard let pos = textEditPosition, !textEditValue.isEmpty else {
            cancelTextAnnotation()
            return
        }
        // Size the rect based on the chosen font size (normalized to image)
        let normFontHeight = textFontSize / 500.0 // approximate normalized height
        let textWidth = max(0.05, CGFloat(textEditValue.count) * normFontHeight * 0.6)
        let rect = CGRect(x: pos.x, y: pos.y - normFontHeight / 2, width: textWidth, height: normFontHeight)
        annotations.append(Annotation(
            tool: .text,
            rect: rect,
            color: selectedColor,
            lineWidth: lineWidth,
            text: textEditValue,
            points: [],
            fontSize: textFontSize
        ))
        textEditPosition = nil
        textEditValue = ""
        isEditingText = false
    }

    func cancelTextAnnotation() {
        textEditPosition = nil
        textEditValue = ""
        isEditingText = false
    }

    private func renderFinalImage() -> NSImage? {
        guard let original = originalImage, imagePixelSize.width > 0 else { return nil }

        let pixelW = imagePixelSize.width
        let pixelH = imagePixelSize.height

        // Determine crop region in pixels
        let cropPixelRect: CGRect
        if let crop = cropRect {
            cropPixelRect = CGRect(
                x: crop.origin.x * pixelW,
                y: crop.origin.y * pixelH,
                width: crop.width * pixelW,
                height: crop.height * pixelH
            )
        } else {
            cropPixelRect = CGRect(origin: .zero, size: imagePixelSize)
        }

        let outputW = Int(cropPixelRect.width)
        let outputH = Int(cropPixelRect.height)
        guard outputW > 0 && outputH > 0 else { return nil }

        let result = NSImage(size: NSSize(width: outputW, height: outputH))
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return nil
        }

        // Draw the original image (cropped)
        let drawRect = CGRect(x: 0, y: 0, width: outputW, height: outputH)
        if let cgImage = original.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let cropCGRect = CGRect(
                x: cropPixelRect.origin.x,
                y: pixelH - cropPixelRect.origin.y - cropPixelRect.height, // flip Y for CG
                width: cropPixelRect.width,
                height: cropPixelRect.height
            )
            if let croppedCG = cgImage.cropping(to: cropCGRect) {
                context.draw(croppedCG, in: drawRect)
            }
        }

        // Draw annotations
        for annotation in annotations {
            drawAnnotationCG(annotation, in: context, cropOrigin: cropPixelRect.origin, outputSize: CGSize(width: outputW, height: outputH), fullSize: imagePixelSize)
        }

        result.unlockFocus()
        return result
    }

    private func drawAnnotationCG(_ annotation: Annotation, in ctx: CGContext, cropOrigin: CGPoint, outputSize: CGSize, fullSize: CGSize) {
        // Convert normalized rect to pixel coords relative to crop
        let pixelRect = CGRect(
            x: (annotation.rect.origin.x * fullSize.width) - cropOrigin.x,
            y: outputSize.height - ((annotation.rect.origin.y * fullSize.height) - cropOrigin.y + annotation.rect.height * fullSize.height), // flip Y
            width: annotation.rect.width * fullSize.width,
            height: annotation.rect.height * fullSize.height
        )

        let nsColor = NSColor(annotation.color)
        let cgColor = nsColor.cgColor
        ctx.setStrokeColor(cgColor)
        ctx.setLineWidth(annotation.lineWidth * 2) // scale up for pixel density

        switch annotation.tool {
        case .rectangle:
            ctx.stroke(pixelRect)

        case .circle:
            ctx.strokeEllipse(in: pixelRect)

        case .arrow:
            let line = linePoints(for: annotation)
            let start = CGPoint(
                x: (line.start.x * fullSize.width) - cropOrigin.x,
                y: outputSize.height - ((line.start.y * fullSize.height) - cropOrigin.y)
            )
            let end = CGPoint(
                x: (line.end.x * fullSize.width) - cropOrigin.x,
                y: outputSize.height - ((line.end.y * fullSize.height) - cropOrigin.y)
            )
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 20
            let headAngle: CGFloat = .pi / 6
            ctx.move(to: end)
            ctx.addLine(to: CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y - headLength * sin(angle - headAngle)
            ))
            ctx.move(to: end)
            ctx.addLine(to: CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y - headLength * sin(angle + headAngle)
            ))
            ctx.strokePath()

        case .line:
            let line = linePoints(for: annotation)
            let start = CGPoint(
                x: (line.start.x * fullSize.width) - cropOrigin.x,
                y: outputSize.height - ((line.start.y * fullSize.height) - cropOrigin.y)
            )
            let end = CGPoint(
                x: (line.end.x * fullSize.width) - cropOrigin.x,
                y: outputSize.height - ((line.end.y * fullSize.height) - cropOrigin.y)
            )
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

        case .pencil:
            if annotation.points.count > 1 {
                let scaledPoints = annotation.points.map { pt in
                    CGPoint(
                        x: (pt.x * fullSize.width) - cropOrigin.x,
                        y: outputSize.height - ((pt.y * fullSize.height) - cropOrigin.y)
                    )
                }
                ctx.move(to: scaledPoints[0])
                for pt in scaledPoints.dropFirst() {
                    ctx.addLine(to: pt)
                }
                ctx.strokePath()
            }

        case .blur:
            // Fill the redacted area with solid blocks
            ctx.setFillColor(CGColor(gray: 0.4, alpha: 1.0))
            ctx.fill(pixelRect)
            let blockSize: CGFloat = 12
            let cols = max(1, Int(pixelRect.width / blockSize))
            let rows = max(1, Int(pixelRect.height / blockSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let brightness = CGFloat((row + col) % 3) * 0.08 + 0.3
                    ctx.setFillColor(CGColor(gray: brightness, alpha: 1.0))
                    let blockRect = CGRect(
                        x: pixelRect.minX + CGFloat(col) * blockSize,
                        y: pixelRect.minY + CGFloat(row) * blockSize,
                        width: blockSize,
                        height: blockSize
                    )
                    ctx.fill(blockRect)
                }
            }

        case .text:
            let str = annotation.text as NSString
            let fontSize = annotation.fontSize * (fullSize.width / 800.0) // scale to pixel density
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: nsColor,
            ]
            // NSString.draw uses flipped coords, so flip context temporarily
            ctx.saveGState()
            ctx.translateBy(x: 0, y: outputSize.height)
            ctx.scaleBy(x: 1, y: -1)
            let flippedRect = CGRect(
                x: pixelRect.origin.x,
                y: outputSize.height - pixelRect.origin.y - pixelRect.height,
                width: pixelRect.width,
                height: pixelRect.height
            )
            str.draw(in: flippedRect, withAttributes: attrs)
            ctx.restoreGState()

        case .crop, .move:
            break
        }
    }
}

// MARK: - Inline Text Editor

private struct InlineTextEditor: View {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    let color: Color
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            TextField("Type text…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 180)
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onSubmit { onCommit() }
                .onExitCommand { onCancel() }

            // Font size control
            HStack(spacing: 6) {
                Button {
                    fontSize = max(10, fontSize - 2)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                Text("\(Int(fontSize))pt")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                Button {
                    fontSize = min(72, fontSize + 2)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(.background)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(color.opacity(0.5), lineWidth: 1.5)
                }
        }
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
    }
}
