import GrimoireAppKit
import SwiftUI

/// One engraved icon from the Brand Codex, drawn in the current foreground style, so it follows
/// the sidebar's tint, red marks and night mode. Size in points; the cut follows the size.
struct CodexIcon: View {
    let icon: CodexIconDef
    var size: Double = CodexIcons.Scale.sm

    var body: some View {
        let cut = CodexIconCut.at(size)
        Canvas { context, _ in
            let k = size / 24
            for part in cut.parts(of: icon) {
                let path = Path { p in
                    for op in part.ops {
                        switch op {
                        case let .move(x, y): p.move(to: CGPoint(x: x * k, y: y * k))
                        case let .line(x, y): p.addLine(to: CGPoint(x: x * k, y: y * k))
                        case let .curve(x1, y1, x2, y2, x, y):
                            p.addCurve(to: CGPoint(x: x * k, y: y * k),
                                       control1: CGPoint(x: x1 * k, y: y1 * k),
                                       control2: CGPoint(x: x2 * k, y: y2 * k))
                        case .close: p.closeSubpath()
                        }
                    }
                }
                switch part.weight {
                case .fill:
                    context.fill(path, with: .foreground, style: FillStyle(eoFill: true))
                case .stroke, .hair:
                    let width = part.weight == .stroke ? cut.stroke : cut.hair
                    context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A Label whose icon is the Codex icon under the house style, and the SF Symbol under System.
struct HouseLabel: View {
    let title: String
    let symbol: String
    let icon: CodexIconDef?
    var size: Double = CodexIcons.Scale.sm

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let icon, !HouseStyleStore.shared.style.isSystem {
                CodexIcon(icon: icon, size: size)
            } else {
                Image(systemName: symbol)
            }
        }
    }
}
