import SwiftUI

struct MouseClickOverlayControls: View {
    let color: Binding<NSColor>
    let size: Binding<Double>
    let strokeWidth: Binding<Double>
    let opacity: Binding<Double>
    let duration: Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Color")
                Spacer()
                MouseClickColorWell(color: color)
                    .frame(width: 48, height: 24)
                    .accessibilityLabel("Mouse click color")
            }

            mouseClickSlider(
                title: "Size",
                value: size,
                range: 12...100,
                step: 1,
                valueText: { "\(Int($0)) px" }
            )

            mouseClickSlider(
                title: "Stroke width",
                value: strokeWidth,
                range: 1...10,
                step: 1,
                valueText: { "\(Int($0)) px" }
            )

            mouseClickSlider(
                title: "Opacity",
                value: opacity,
                range: 0.1...1.0,
                step: 0.05,
                valueText: { "\(Int(($0 * 100).rounded()))%" }
            )

            mouseClickSlider(
                title: "Duration",
                value: duration,
                range: 0.15...1.0,
                step: 0.05,
                valueText: { String(format: "%.2f s", $0) }
            )
        }
    }

    @ViewBuilder
    private func mouseClickSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 110, alignment: .leading)

            Slider(value: value, in: range, step: step)

            Text(valueText(value.wrappedValue))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }
}

struct MouseClickColorWell: NSViewRepresentable {
    @Binding var color: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorDidChange(_:))
        well.isBordered = true
        well.color = color
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        if !nsView.color.isEqual(color) {
            nsView.color = color
        }
    }

    final class Coordinator: NSObject {
        private let color: Binding<NSColor>

        init(color: Binding<NSColor>) {
            self.color = color
        }

        @objc func colorDidChange(_ sender: NSColorWell) {
            color.wrappedValue = sender.color
        }
    }
}
