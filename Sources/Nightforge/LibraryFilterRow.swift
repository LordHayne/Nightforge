import SwiftUI

/// What a chip in the library's row opens: the stores, the orders, the filters.
enum LibraryMenu: Hashable {
    case store, sort, filters

    /// The chip it opens under, for the pad's highlight to go back to.
    var chipID: String {
        switch self {
        case .store: return "library.store"
        case .sort: return "library.sort"
        case .filters: return "library.filter"
        }
    }
}

/// Where each chip sits: its list opens right under it, over the grid (LibraryMenuLayer).
struct LibraryMenuAnchors: PreferenceKey {
    static var defaultValue: [LibraryMenu: Anchor<CGRect>] = [:]

    static func reduce(value: inout [LibraryMenu: Anchor<CGRect>], nextValue: () -> [LibraryMenu: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The library's row under its title: the store (with games from two stores or more), the order and
/// the filters as chips, then the filters that are on, each with its ✕, and "Clear filters" while
/// anything narrows the games. One line also at 980 pt. During a search everything rests and the
/// row says so.
struct LibraryFilterRow: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(spacing: 10) {
            if !Search.key(model.searchText).isEmpty {
                Label(L10n.t("The search finds all %ld games – filters and store rest until you clear it.", model.visibleCount),
                      systemImage: "line.3.horizontal.decrease")
                    .font(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(height: 32)
                ClearFiltersChip()
                Spacer(minLength: 0)
            } else {
                if model.storesWithGames.count > 1 {
                    ChoiceChip(symbol: "square.stack", title: model.filters.store?.label ?? L10n.t("All Stores"),
                               on: model.filters.store != nil, menu: .store, help: L10n.t("Games of one store"))
                }
                ChoiceChip(symbol: "arrow.up.arrow.down", title: model.filters.sort.label, menu: .sort,
                           help: L10n.t("Order"))
                ChoiceChip(symbol: "line.3.horizontal.decrease", title: L10n.t("Filter"),
                           badge: model.filters.on.isEmpty ? nil : model.filters.on.count, menu: .filters,
                           help: L10n.t("Only some games: running great, with a controller, two on one Mac …"))
                // The Play Later list, one press away; the chip stays while it's on, to go back.
                let later = model.laterCount
                if later > 0 || model.filters.later {
                    FilterToggle(title: L10n.t("Play Later"), symbol: "bookmark.fill", count: later, on: model.filters.later,
                                 id: "library.later", help: L10n.t("Only the games you marked to play later")) {
                        model.filters.later.toggle()
                    }
                }
                let active = LibraryFilters.Filter.allCases.filter(model.filters.has)
                if !active.isEmpty {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 18)
                    // All of them while they fit; else the first and how many more.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            ForEach(active, id: \.self) { ActiveFilterChip(filter: $0) }
                        }
                        HStack(spacing: 8) {
                            ActiveFilterChip(filter: active[0])
                            Text("+\(active.count - 1)")
                                .font(size: 13, weight: .semibold)
                                .foregroundStyle(Theme.muted)
                        }
                        EmptyView()
                    }
                }
                if LibraryFilters.clearable(model.filters, search: model.searchText) {
                    ClearFiltersChip()
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A choice in one chip: "All Stores ▾", "Recently played ▾", "Filter ▾". A click or A on the pad
/// opens its list.
private struct ChoiceChip: View {
    let symbol: String
    let title: String
    var on = false
    var badge: Int?
    let menu: LibraryMenu
    let help: String
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        Button { model.libraryMenu = model.libraryMenu == menu ? nil : menu } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(size: 12, weight: .semibold)
                Text(title)
                if let badge {
                    Text("\(badge)")
                        .font(size: 11, weight: .bold).monospacedDigit()
                        .foregroundStyle(Theme.night)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.sodium, in: Circle())
                }
                Image(systemName: "chevron.down").font(size: 9, weight: .bold).opacity(0.7)
            }
            .font(size: 13, weight: .semibold)
            .foregroundStyle(on ? Theme.night : Theme.ink.opacity(0.88))
            .padding(.horizontal, 13)
            .frame(height: 32)
        }
        .buttonStyle(GlassButtonStyle(glass: on ? .tinted(Theme.ink) : .regular, shape: Capsule()))
        .help(help)
        .accessibilityValue(title)
        .anchorPreference(key: LibraryMenuAnchors.self, value: .bounds) { [menu: $0] }
        .padFocus(menu.chipID, cornerRadius: 16, activate: { model.openLibraryMenu(menu) })
        .fixedSize()
    }
}

/// Store, filters and search back to the start in one press (the order stays).
private struct ClearFiltersChip: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        Button { model.clearFilters() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(size: 11, weight: .bold)
                Text(L10n.t("Clear filters"))
            }
            .font(size: 13, weight: .semibold)
            .foregroundStyle(Theme.ink.opacity(0.88))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L10n.t("Store, filters and search back to the start – the order stays"))
        .padFocus("library.clear", cornerRadius: 16) { model.clearFilters() }
        .fixedSize()
    }
}

/// A filter that's on, in the row: a click (or A) takes it off.
private struct ActiveFilterChip: View {
    let filter: LibraryFilters.Filter
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        Button { model.filters.toggle(filter) } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.symbol).font(size: 11, weight: .semibold)
                Text(filter.label)
                Image(systemName: "xmark").font(size: 8, weight: .heavy).opacity(0.6)
            }
            .font(size: 13, weight: .semibold)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L10n.t("Remove this filter"))
        .accessibilityLabel(L10n.t("Remove filter %@", filter.label))
        .padFocus("library.active.\(filter)", cornerRadius: 16) { model.filters.toggle(filter) }
        .fixedSize()
    }
}

/// Over everything in the window while a chip's list is open: a click beside it closes it (like a
/// popover), the list itself sits right under its chip.
struct LibraryMenuLayer: View {
    let anchors: [LibraryMenu: Anchor<CGRect>]
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if let menu = model.libraryMenu, let anchor = anchors[menu] {
            GeometryReader { geo in
                let chip = geo[anchor]
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { model.libraryMenu = nil }
                    Group {
                        switch menu {
                        case .filters: FilterPanel()
                        case .store: StoreList()
                        case .sort: SortList()
                        }
                    }
                    .fixedSize()
                    .padZone(.panel)  // it keeps the pad while it's open
                    .offset(x: chip.minX, y: chip.maxY + 8)
                    .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
        }
    }
}

/// Glass under a chip, like the downloads panel.
struct MenuGlass<Content: View>: View {
    var width: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { content }
            .padding(10)
            .frame(width: width * textScale)
            .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }
}

/// "Filter ▾": each filter a switch, with how many games it leaves; "All filters off" below.
private struct FilterPanel: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        MenuGlass(width: 340) {
            SectionTitle(L10n.t("Filter"))
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            ForEach(LibraryFilters.Filter.allCases, id: \.self) { filter in
                let on = model.filters.has(filter)
                Button { model.filters.toggle(filter) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: filter.symbol)
                            .font(size: 13, weight: .semibold)
                            .foregroundStyle(on ? Theme.ink : Theme.muted)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(filter.label)
                                .font(size: 13.5, weight: .semibold)
                                .foregroundStyle(Theme.ink)
                            if let note = filter.note {
                                Text(note)
                                    .font(size: 11.5)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer(minLength: 12)
                        Text("\(model.count(with: filter))")
                            .font(size: 12.5, weight: .semibold).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                        GlassSwitch(isOn: on) { model.filters.toggle(filter) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .padFocus("filter.\(filter)", cornerRadius: 12) { model.filters.toggle(filter) }
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            HStack {
                Button(L10n.t("All filters off")) { model.filters = model.filters.switchesOff }
                    .buttonStyle(.plain)
                    .font(size: 13, weight: .semibold)
                    .foregroundStyle(model.filters.on.isEmpty ? Theme.muted : Theme.sodium)
                    .disabled(model.filters.on.isEmpty)
                    .padFocus("filter.off", enabled: !model.filters.on.isEmpty, cornerRadius: 8) {
                        model.filters = model.filters.switchesOff
                    }
                Spacer()
                // The pad's own button (○ on a DualSense), else the key.
                HStack(spacing: 5) {
                    if model.controllerConnected {
                        Image(systemName: model.padSymbols.back)
                    } else {
                        Text("esc")
                    }
                    Text(L10n.t("Close"))
                }
                .font(size: 11.5, weight: .medium)
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}

/// The store chip's list: all stores, then each store with games here, with how many.
private struct StoreList: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        MenuGlass(width: 280) {
            row(nil, L10n.t("All Stores"), model.visibleCount)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            ForEach(model.storesWithGames, id: \.self) { store in
                row(store, store.label, model.visibleCount(of: store))
            }
            Text(L10n.t("Games in several stores count in each."))
                .font(size: 11.5)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ store: Provider?, _ title: String, _ count: Int) -> some View {
        let pick = {
            model.filters.store = store
            model.closeLibraryMenu(.store)  // the pad's highlight back on the chip
        }
        return Button(action: pick) {
            MenuRow(title: title, count: count, on: model.filters.store == store)
        }
        .buttonStyle(.plain)
        .padFocus("store.\(store?.rawValue ?? "all")", cornerRadius: 10, activate: pick)
    }
}

/// The order chip's list.
private struct SortList: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        MenuGlass(width: 240) {
            ForEach(LibraryFilters.Sort.allCases, id: \.self) { sort in
                let pick = {
                    model.filters.sort = sort
                    model.closeLibraryMenu(.sort)
                }
                Button(action: pick) {
                    MenuRow(title: sort.label, count: nil, on: model.filters.sort == sort)
                }
                .buttonStyle(.plain)
                .padFocus("sort.\(sort)", cornerRadius: 10, activate: pick)
            }
        }
    }
}

private struct MenuRow: View {
    let title: String
    let count: Int?
    let on: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(size: 11, weight: .bold)
                .foregroundStyle(Theme.sodium)
                .opacity(on ? 1 : 0)
                .frame(width: 14)
            Text(title)
                .font(size: 13.5, weight: .semibold)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 16)
            if let count {
                Text("\(count)")
                    .font(size: 12.5, weight: .semibold).monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
