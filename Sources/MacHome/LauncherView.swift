import SwiftUI

/// The Apple TV style home screen: a top shelf for the focused app above a grid of tiles.
struct LauncherView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(size: geometry.size)
            let focusedRow = model.focusIndex / metrics.columns
            ZStack(alignment: .topLeading) {
                Color.black
                VStack(alignment: .leading, spacing: 0) {
                    TopShelfView(entry: model.focused, metrics: metrics)
                    grid(metrics)
                        .padding(.top, metrics.gridGap)
                }
                .offset(y: metrics.contentOffset(focusedRow: focusedRow))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: focusedRow)

                StatusView(model: model, u: metrics.u)
                    .frame(width: geometry.size.width, alignment: .trailing)

                if model.entries.isEmpty {
                    Text("No apps yet. Press ⌘, to edit apps.json.")
                        .font(.system(size: 34 * metrics.u, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                if let notice = model.notice {
                    HStack(spacing: 12 * metrics.u) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(notice).lineLimit(2)
                    }
                    .font(.system(size: 22 * metrics.u, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.leading, metrics.margin)
                    .padding(.bottom, 36 * metrics.u)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
    }

    private func grid(_ metrics: GridMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            ForEach(rows(columns: metrics.columns), id: \.self) { row in
                HStack(alignment: .top, spacing: metrics.spacing) {
                    ForEach(row, id: \.self) { index in
                        tile(index, metrics)
                    }
                }
                .zIndex(row.contains(model.focusIndex) ? 1 : 0)
            }
        }
        .padding(.leading, metrics.margin)
    }

    private func tile(_ index: Int, _ metrics: GridMetrics) -> some View {
        let focused = index == model.focusIndex
        return TileView(entry: model.entries[index], focused: focused, tilt: focused ? model.tilt : .zero, metrics: metrics)
            .zIndex(focused ? 1 : 0)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { model.focusIndex = index }
            }
            .onTapGesture {
                model.focusIndex = index
                model.activateFocused()
            }
    }

    private func rows(columns: Int) -> [[Int]] {
        stride(from: 0, to: model.entries.count, by: columns).map { start in
            Array(start..<min(start + columns, model.entries.count))
        }
    }
}

/// The large banner across the top, showing the focused app like tvOS's top shelf.
struct TopShelfView: View {
    let entry: LauncherEntry?
    let metrics: GridMetrics

    var body: some View {
        let u = metrics.u
        return ZStack(alignment: .bottomLeading) {
            if let entry = entry {
                artwork(entry, u)
                    .id("art-" + entry.id.uuidString)
                    .transition(.opacity)
            }
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), Color.black]),
                           startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0)]),
                           startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
            if let entry = entry {
                details(entry, u)
                    .id("details-" + entry.id.uuidString)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.size.width, height: metrics.shelfHeight)
        .clipped()
        .animation(.easeInOut(duration: 0.3), value: entry?.id)
    }

    @ViewBuilder
    private func artwork(_ entry: LauncherEntry, _ u: CGFloat) -> some View {
        if let image = entry.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: metrics.size.width, height: metrics.shelfHeight)
                .clipped()
        } else {
            ZStack(alignment: .trailing) {
                LinearGradient(gradient: Gradient(colors: entry.colors), startPoint: .topLeading, endPoint: .bottomTrailing)
                emblem(entry, u)
                    .padding(.trailing, 160 * u)
            }
            .frame(width: metrics.size.width, height: metrics.shelfHeight)
        }
    }

    @ViewBuilder
    private func emblem(_ entry: LauncherEntry, _ u: CGFloat) -> some View {
        if let icon = entry.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 320 * u, height: 320 * u)
                .shadow(color: Color.black.opacity(0.4), radius: 24 * u, x: 0, y: 12 * u)
        } else if let symbol = entry.symbol {
            Image(systemName: symbol)
                .font(.system(size: 260 * u, weight: .bold))
                .foregroundColor(Color.white.opacity(0.22))
        }
    }

    private func details(_ entry: LauncherEntry, _ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12 * u) {
            Text(entry.title)
                .font(.system(size: 84 * u, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(.system(size: 30 * u))
                    .foregroundColor(Color.white.opacity(0.82))
                    .lineLimit(2)
            }
            if let problem = entry.problem {
                HStack(spacing: 10 * u) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(problem)
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                .font(.system(size: 26 * u, weight: .medium))
                .padding(.top, 6 * u)
            }
        }
        .frame(maxWidth: metrics.size.width * 0.6, alignment: .leading)
        .padding(.leading, metrics.margin)
        .padding(.bottom, 60 * u)
        .shadow(color: Color.black.opacity(0.5), radius: 10 * u)
    }
}

/// One app tile. The focused tile lifts, casts a shadow, catches a highlight and tilts with the left stick.
struct TileView: View {
    let entry: LauncherEntry
    let focused: Bool
    let tilt: CGSize
    let metrics: GridMetrics

    var body: some View {
        let u = metrics.u
        let shape = RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
        let scale: CGFloat = focused ? 1.12 : 1
        let shadowOpacity: Double = focused ? 0.6 : 0.35
        let shadowRadius: CGFloat = (focused ? 24 : 8) * u
        let shadowOffset: CGFloat = (focused ? 20 : 6) * u
        let turn = Angle.degrees(Double(tilt.width) * 8)
        let lean = Angle.degrees(Double(tilt.height) * 8)
        return VStack(spacing: metrics.labelGap) {
            art(u)
                .frame(width: metrics.tileSize.width, height: metrics.tileSize.height)
                .clipShape(shape)
                .overlay(gloss.clipShape(shape).opacity(focused ? 1 : 0))
                .opacity(entry.problem == nil ? 1 : 0.45)
                .rotation3DEffect(turn, axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(lean, axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .scaleEffect(scale)
                .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowOffset)
            Text(entry.title)
                .font(.system(size: 24 * u, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: metrics.tileSize.width * 1.12, height: metrics.labelHeight)
                .opacity(focused ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: focused)
        .animation(.easeOut(duration: 0.12), value: tilt)
    }

    @ViewBuilder
    private func art(_ u: CGFloat) -> some View {
        if let image = entry.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(gradient: Gradient(colors: entry.colors), startPoint: .topLeading, endPoint: .bottomTrailing)
                if let icon = entry.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 112 * u, height: 112 * u)
                } else {
                    VStack(spacing: 10 * u) {
                        if let symbol = entry.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 52 * u, weight: .semibold))
                        }
                        Text(entry.title)
                            .font(.system(size: 34 * u, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16 * u)
                }
            }
        }
    }

    private var gloss: some View {
        LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)]),
                       startPoint: UnitPoint(x: 0.2 - tilt.width * 0.3, y: tilt.height * 0.3),
                       endPoint: UnitPoint(x: 0.75, y: 0.85))
    }
}

/// Controller status and the time, in the top-right corner.
struct StatusView: View {
    @ObservedObject var model: LauncherModel
    let u: CGFloat

    var body: some View {
        HStack(spacing: 30 * u) {
            HStack(spacing: 10 * u) {
                Image(systemName: "gamecontroller.fill")
                Text(model.controllerName ?? "No controller")
            }
            .opacity(model.controllerName == nil ? 0.5 : 0.9)
            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
            }
        }
        .font(.system(size: 26 * u, weight: .medium))
        .foregroundColor(.white)
        .shadow(color: Color.black.opacity(0.6), radius: 6 * u)
        .padding(.top, 44 * u)
        .padding(.trailing, 70 * u)
    }
}
