import SwiftUI

enum Direction: CaseIterable {
    case up, down, left, right
}

/// The home screen's state: the tiles, which one has focus, and status shown in the corner.
final class LauncherModel: ObservableObject {
    @Published private(set) var entries: [LauncherEntry] = []
    @Published var focusIndex = 0
    /// Small left-stick movement on the focused tile, from -1 to 1 on each axis, for the Apple TV style tilt.
    @Published var tilt = CGSize.zero
    @Published var controllerName: String?
    /// A persistent problem to show at the bottom of the screen, such as a broken apps.json.
    @Published var notice: String?

    var screenSize = CGSize(width: 1920, height: 1080)
    var onActivate: ((LauncherEntry) -> Void)?
    /// When the real mouse last moved. Hover only moves focus right after that, so tiles scrolling
    /// under a resting pointer don't steal focus from the controller.
    var mouseMovedAt: TimeInterval = -100

    var mouseIsActive: Bool {
        ProcessInfo.processInfo.systemUptime - mouseMovedAt < 0.5
    }

    var focused: LauncherEntry? {
        entries.indices.contains(focusIndex) ? entries[focusIndex] : nil
    }

    func setEntries(_ newEntries: [LauncherEntry]) {
        entries = newEntries
        focusIndex = min(focusIndex, max(0, newEntries.count - 1))
    }

    func move(_ direction: Direction) {
        guard !entries.isEmpty else { return }
        let columns = GridMetrics(size: screenSize).columns
        let lastRow = (entries.count - 1) / columns
        var index = focusIndex
        switch direction {
        case .left:
            if index % columns > 0 { index -= 1 }
        case .right:
            if index % columns < columns - 1 && index + 1 < entries.count { index += 1 }
        case .up:
            if index >= columns { index -= columns }
        case .down:
            if index + columns < entries.count {
                index += columns
            } else if index / columns < lastRow {
                index = entries.count - 1
            }
        }
        if index != focusIndex { focusIndex = index }
    }

    func activateFocused() {
        if let entry = focused { onActivate?(entry) }
    }
}

/// Sizes for the home screen, scaled from a 1080-point-tall layout so it looks the same at 1080p and 4K.
struct GridMetrics {
    let size: CGSize
    let u: CGFloat
    let tileSize: CGSize
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let columns: Int
    let margin: CGFloat
    let shelfHeight: CGFloat
    let gridGap: CGFloat
    let labelGap: CGFloat
    let labelHeight: CGFloat

    init(size: CGSize) {
        self.size = size
        u = max(size.height / 1080, 0.5)
        tileSize = CGSize(width: 300 * u, height: 180 * u)
        spacing = 40 * u
        rowSpacing = 36 * u
        let minimumMargin = 80 * u
        columns = max(1, Int((size.width - 2 * minimumMargin + spacing) / (tileSize.width + spacing)))
        let gridWidth = CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
        margin = max(minimumMargin, (size.width - gridWidth) / 2)
        shelfHeight = 560 * u
        gridGap = 30 * u
        labelGap = 22 * u
        labelHeight = 30 * u
    }

    var rowHeight: CGFloat {
        tileSize.height + labelGap + labelHeight + rowSpacing
    }

    /// The top row sits under the top shelf. Moving below it scrolls the shelf away, like tvOS.
    func contentOffset(focusedRow: Int) -> CGFloat {
        guard focusedRow > 0 else { return 0 }
        let topInset = 140 * u
        let rowsOnScreen = max(1, Int((size.height - topInset) / rowHeight))
        let extraRows = max(0, focusedRow - (rowsOnScreen - 1))
        return -(shelfHeight + gridGap - topInset + CGFloat(extraRows) * rowHeight)
    }
}
