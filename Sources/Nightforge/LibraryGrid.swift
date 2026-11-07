import SwiftUI

/// The grid's groups, in the order it shows them; each one starts a row of its own.
enum GridGroup: CaseIterable {
    case installed, downloading, library, store

    var title: String {
        switch self {
        case .installed: return L10n.t("Installed")
        case .downloading: return L10n.t("Downloading")
        case .library: return L10n.t("In your library")
        case .store: return L10n.t("In the Stores")
        }
    }

    func contains(_ state: InstallState) -> Bool {
        switch (self, state) {
        case (.installed, .installed), (.downloading, .downloading), (.library, .notInstalled), (.store, .inStore): return true
        default: return false
        }
    }
}

/// A search's quiet last line: Epic's store can't be searched from here (`StoreHits.epicSearch`), so
/// its own search opens in the browser.
struct EpicSearchLink: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if model.offersEpicSearch {
            Button(action: model.openEpicSearch) {
                Label(L10n.t("Search Epic Games in your browser"), systemImage: "arrow.up.right.square")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .padFocus("search.epic", activate: model.openEpicSearch)
        }
    }
}

/// Where each game sits in the grid, so ↑/↓ and ←/→ follow what's on screen: a search orders the
/// games by match, and every group starts a new row, so neither is a plain step through the list.
struct GridLayout {
    /// Indices into the games, row by row.
    let rows: [[Int]]

    /// `sections`: each group's indices, in the order shown.
    init(sections: [[Int]], columns: Int) {
        let columns = max(columns, 1)
        rows = sections.flatMap { members -> [[Int]] in
            stride(from: 0, to: members.count, by: columns).map { Array(members[$0..<min($0 + columns, members.count)]) }
        }
    }

    /// Grouped by install state, in the list's order (the library sorted by "recently played").
    init(games: [Game], columns: Int) {
        self.init(sections: GridGroup.allCases.map { group in games.indices.filter { group.contains(games[$0].shelfState) } },
                  columns: columns)
    }

    /// The games in reading order.
    var order: [Int] { rows.flatMap { $0 } }

    func position(of index: Int) -> (row: Int, column: Int)? {
        for (row, members) in rows.enumerated() {
            if let column = members.firstIndex(of: index) { return (row, column) }
        }
        return nil
    }

    /// The game `delta` rows up or down, in the same column or the last one of a shorter row;
    /// nil past the first or last row.
    func index(from index: Int, rows delta: Int) -> Int? {
        guard let (row, column) = position(of: index), rows.indices.contains(row + delta) else { return nil }
        let target = rows[row + delta]
        return target[min(column, target.count - 1)]
    }

    /// The game `delta` places on in reading order, stopping at either end.
    func index(from index: Int, steps delta: Int) -> Int? {
        let order = self.order
        guard let place = order.firstIndex(of: index) else { return order.first }
        return order[max(0, min(order.count - 1, place + delta))]
    }
}

/// The whole library at once: covers in a grid, grouped by installed / downloading / the rest.
/// A click selects a game, a second one (or Return, A) opens its page, where its Play or Download
/// button is.
struct LibraryGrid: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.reduceMotion) private var reduceMotion
    /// Pinching on the trackpad changes it in steps (InputRouter); it's kept for the next start.
    @AppStorage(CoverSize.defaultsKey) private var coverSize = CoverSize.regular.rawValue

    private var cardWidth: CGFloat { CoverSize(stored: coverSize).width }
    private static let spacing: CGFloat = 24

    private struct Section: Identifiable {
        let id: String
        let title: String
        let items: [(index: Int, game: Game)]
    }

    private var sections: [Section] {
        model.librarySections.map { section in
            Section(id: section.id, title: section.title, items: section.items.map { (index: $0, game: model.games[$0]) })
        }
    }

    var body: some View {
        GeometryReader { geo in
            let columnCount = max(1, Int((geo.size.width - 2 * Theme.gutter + Self.spacing) / (cardWidth + Self.spacing)))
            let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: Self.spacing), count: columnCount)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(section.title)
                                        .displayFont(19)
                                        .foregroundStyle(Theme.ink)
                                    Text("\(section.items.count)")
                                        .font(size: 13, weight: .semibold).monospacedDigit()
                                        .foregroundStyle(Theme.muted)
                                }
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                                    ForEach(section.items, id: \.game.id) { item in
                                        GridCard(game: item.game, isSelected: item.index == model.selectedIndex,
                                                 isRunning: model.isRunning(item.game), isPinned: model.isPinned(item.game),
                                                 isLater: model.isLater(item.game),
                                                 compatibility: model.compatibility(of: item.game), width: cardWidth) {
                                            model.openQuickMenu(at: item.index)
                                        }
                                        .id(item.game.id)
                                        .modifier(GameCardMenu(game: item.game))
                                        .onTapGesture {
                                            guard model.quickMenu == nil else { return }  // a long click that opened it, let go
                                            if item.index == model.selectedIndex {
                                                model.openDetail()
                                            } else {
                                                model.selectedIndex = item.index
                                            }
                                        }
                                        .modifier(LongClick { model.openQuickMenu(at: item.index) })
                                    }
                                }
                            }
                        }
                        EpicSearchLink()
                            .padReachable(false)  // the pad's steps stay with the games and the top row
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 20)
                    .id(Self.top)
                }
                .onAppear {
                    model.gridColumns = columnCount
                    showSelected(proxy, columns: columnCount)
                }
                .onChange(of: columnCount) { _, count in model.gridColumns = count }
                // Another cover size: the selected game stays in sight.
                .onChange(of: coverSize) { _, _ in showSelected(proxy, columns: columnCount) }
                .onChange(of: model.selectedIndex) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showSelected(proxy, columns: columnCount) }
                }
            }
        }
    }

    private static let top = "grid.top"

    /// The selected game in sight: in the middle, or in the first row the grid's very top, so the
    /// first group's title and the room above it stay in view in a short window.
    private func showSelected(_ proxy: ScrollViewProxy, columns: Int) {
        guard let id = model.selected?.id else { return }
        if model.librarySections.first?.items.prefix(columns).contains(model.selectedIndex) == true {
            proxy.scrollTo(Self.top, anchor: .top)
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct GridCard: View {
    let game: Game
    let isSelected: Bool
    var isRunning = false
    var isPinned = false
    var isLater = false
    let compatibility: Compatibility
    var width = CoverSize.regular.width
    let openMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverCard(game: game, isSelected: isSelected, isRunning: isRunning, isPinned: isPinned, isLater: isLater, width: width,
                      openMenu: openMenu)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The level's own icon (each has a different one), named for VoiceOver and on hover.
                Image(systemName: compatibility.level.symbol)
                    .font(size: 11, weight: .semibold)
                    .foregroundStyle(compatibility.level.color)
                    .help(compatibility.level.label)
                    .accessibilityLabel(compatibility.level.label)
                Text(game.name)
                    .font(size: 13, weight: isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                    .lineLimit(2)
            }
            .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// Above the grid: what it shows and in which order. Every control is a button the pad reaches
/// (↑ from the grid's first row).
struct LibraryToolbar: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderRow {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(model.showingHidden ? L10n.t("Hidden games") : L10n.t("Library"))
                        .displayFont(26)
                        .foregroundStyle(Theme.ink)
                    Text(countText)
                        .font(size: 13, weight: .semibold).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                    if !model.showingHidden {
                        // Redrawn every half minute, so "2 min ago" moves on by itself.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            if let fresh = ScanFreshness.text(lastScan: model.lastScan, scanning: model.isScanning, now: context.date) {
                                Text("· " + fresh)
                                    .font(size: 12.5).monospacedDigit()
                                    .foregroundStyle(Theme.muted.opacity(0.8))
                            }
                        }
                    }
                    if model.showingHidden {
                        Text(L10n.t("Open a game to bring it back."))
                            .font(size: 13, weight: .medium)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
                HStack(spacing: 12) {
                    if !model.hiddenGames.isEmpty {
                        FilterToggle(title: L10n.t("Hidden"), symbol: "eye.slash", count: model.hiddenCount,
                                     on: model.showingHidden, id: "library.hidden",
                                     help: L10n.t("Games you hid from your library")) { model.toggleShowingHidden() }
                            .padding(.trailing, model.showingHidden ? 0 : 8)
                    }
                    LibrarySearchField()
                }
            }
            if !model.showingHidden {
                LibraryFilterRow()
                StoreSyncBanner(store: model.epic, connect: model.connectEpic)
                StoreSyncBanner(store: model.gog, connect: model.connectGOG)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
    }

    private var countText: String {
        let owned = model.games.filter(\.counted).count
        if model.showingHidden { return L10n.t("%ld hidden", owned) }
        let total = model.visibleCount
        if model.filters.narrows || !model.searchText.isEmpty {
            return total == 1 ? L10n.t("%ld of 1 game", owned) : L10n.t("%ld of %ld games", owned, total)
        }
        return total == 1 ? L10n.t("1 game") : L10n.t("%ld games", total)
    }
}

/// "up to date 2 min ago" beside the library's count: when the last scan finished – or that one
/// is running.
enum ScanFreshness {
    static func text(lastScan: Date?, scanning: Bool, now: Date = Date()) -> String? {
        if scanning { return L10n.t("Scanning …") }
        guard let lastScan else { return nil }
        let minutes = max(0, Int(now.timeIntervalSince(lastScan) / 60))
        switch minutes {
        case ..<1: return L10n.t("up to date just now")
        case ..<60: return L10n.t("up to date %ld min ago", minutes)
        case ..<1440: return L10n.t("up to date %ld h ago", Int((Double(minutes) / 60).rounded()))
        case ..<2880: return L10n.t("up to date since yesterday")
        default: return L10n.t("up to date %ld days ago", minutes / 1440)
        }
    }
}

/// The header's title and its controls side by side, the controls at the right end – or under the
/// title when the window is too narrow for both (the longer German texts need more room).
private struct HeaderRow: Layout {
    var spacing: CGFloat = 16
    var lineSpacing: CGFloat = 12

    private func sizes(_ subviews: Subviews) -> (title: CGSize, controls: CGSize)? {
        guard subviews.count == 2 else { return nil }
        return (subviews[0].sizeThatFits(.unspecified), subviews[1].sizeThatFits(.unspecified))
    }

    private func fits(_ sizes: (title: CGSize, controls: CGSize), in width: CGFloat) -> Bool {
        sizes.title.width + spacing + sizes.controls.width <= width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let sizes = sizes(subviews) else { return .zero }
        let width = proposal.width ?? sizes.title.width + spacing + sizes.controls.width
        return fits(sizes, in: width)
            ? CGSize(width: width, height: max(sizes.title.height, sizes.controls.height))
            : CGSize(width: width, height: sizes.title.height + lineSpacing + sizes.controls.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let sizes = sizes(subviews) else { return }
        if fits(sizes, in: bounds.width) {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes.title))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(sizes.controls))
        } else {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(sizes.title))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + sizes.title.height + lineSpacing),
                              proposal: ProposedViewSize(width: min(sizes.controls.width, bounds.width), height: sizes.controls.height))
        }
    }
}

/// Search as you type, in the library's header: ⌘F or / jumps here (from Home too, which opens the
/// library), Return or ↓ goes back to the hits, Esc clears and then leaves.
private struct LibrarySearchField: View {
    @EnvironmentObject private var model: LibraryModel
    @FocusState private var focused: Bool
    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(size: 13, weight: .semibold)
                .foregroundStyle(Theme.muted)
            TextField("", text: $model.searchText,
                      prompt: Text(L10n.t("Search – try “rdr2” or “bg3”")).foregroundStyle(Theme.muted))
                .textFieldStyle(.plain)
                .font(size: 14)
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit { focused = false }
                .onKeyPress(.downArrow) {
                    focused = false
                    return .handled
                }
                .onExitCommand {
                    if model.searchText.isEmpty { focused = false } else { model.searchText = "" }
                }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(size: 8, weight: .bold, scales: false)
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Clear search"))
                .accessibilityLabel(L10n.t("Clear search"))
            } else {
                Text("⌘F")
                    .font(size: 11, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(minWidth: 180, idealWidth: 300 * textScale, maxWidth: 300 * textScale)
        .frame(height: 38)
        .background(GlassBackground(glass: .regular, shape: Capsule()))
        .overlay(Capsule().strokeBorder(Theme.sodium.opacity(focused || !model.searchText.isEmpty ? 0.8 : 0), lineWidth: 1.5))
        .modifier(SwipeArea(kind: .search))  // two fingers over the field never swipe
        .padFocus("library.search", cornerRadius: 19, activate: { focused = true })
        .onChange(of: model.searchFocusRequest) { _, _ in takeFocus() }
        // The library stays behind a game's page it opened: the field mustn't keep the keys there
        // (Esc would clear the search instead of going back, letters would type into it).
        .onChange(of: model.route) { _, route in
            if route != .library { focused = false }
        }
        .onAppear { takeFocus() }
        .help(L10n.t("Search (⌘F)"))
    }

    /// A request from ⌘F, / or Home; on appearing, the field shows only once it's on screen.
    private func takeFocus() {
        guard model.takeSearchFocus() else { return }
        Task { @MainActor in focused = true }
    }
}

/// A row of choices, one filled in; each segment is a button of its own for the pad.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String, count: Int?)]
    let selection: Value
    let id: String
    /// The pad starts on the chosen segment (Settings' tabs).
    var preferSelected = false
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { place, option in
                let on = option.value == selection
                Button { select(option.value) } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                        if let count = option.count {
                            Text("\(count)").monospacedDigit().foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                        }
                    }
                    .font(size: 13, weight: .semibold)
                    .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.8))
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .background(on ? Theme.ink : .clear, in: Capsule())
                    .shadow(color: .black.opacity(on ? 0.3 : 0), radius: 4, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .padFocus("\(id).\(place)", cornerRadius: 13, preferred: preferSelected && on, activate: { select(option.value) })
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(GlassBackground(glass: .regular, shape: Capsule()))
        .fixedSize()
    }
}

/// A filter switch: filled in while it's on.
struct FilterToggle: View {
    let title: String
    let symbol: String
    var count: Int?
    let on: Bool
    let id: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(size: 12, weight: .semibold)
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(on ? Theme.night.opacity(0.6) : Theme.muted)
                }
            }
            .font(size: 13, weight: .semibold)
            .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.85))
            .padding(.horizontal, 13)
            .frame(height: 32)
        }
        .buttonStyle(GlassButtonStyle(glass: on ? .tinted(Theme.ink) : .regular, shape: Capsule()))
        .help(help ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .padFocus(id, cornerRadius: 16, activate: action)
        .fixedSize()
    }
}
