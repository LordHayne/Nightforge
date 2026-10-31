import SwiftUI

/// What a game is, in a calm grid: its screenshots as a band, the description, then two cards of the
/// same size side by side – "At a glance" and "How it's played" – or one, when there's too little for
/// two. What a store doesn't say is left out. From its store or the same game on Steam (GameInfo).
struct GameAboutSection: View {
    let game: Game
    let info: GameInfo
    var narrow = false

    /// Anything to show: a store that knew nothing about the game leaves the page as it was.
    static func hasContent(_ info: GameInfo) -> Bool {
        info.summary != nil || !info.screenshots.isEmpty || !AboutRows.facts(info).isEmpty || !AboutRows.play(info).isEmpty
    }

    var body: some View {
        let facts = AboutRows.facts(info)
        let play = AboutRows.play(info)
        VStack(alignment: .leading, spacing: 24) {
            if !info.screenshots.isEmpty {
                ScreenshotStrip(game: game, screenshots: info.screenshots, height: narrow ? 118 : 150)
            }
            if let summary = info.summary {
                Text(summary)
                    .font(size: 15)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink.opacity(0.88))
                    .frame(maxWidth: 860, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if facts.count >= 2 && play.count >= 2 {
                HStack(alignment: .top, spacing: 20) {
                    AboutCard(title: L10n.t("At a glance"), rows: facts, footnote: borrowedFrom)
                    AboutCard(title: L10n.t("How it's played"), rows: play, footnote: nil)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if !(facts + play).isEmpty {
                AboutCard(title: L10n.t("At a glance"), rows: facts + play, footnote: borrowedFrom)
                    .frame(maxWidth: 560)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("About the game"))
    }

    /// The store the facts come from, when it isn't one the game is in here.
    private var borrowedFrom: String? {
        let store = info.source.split(separator: ".").first.flatMap { Provider(rawValue: String($0)) }
        guard let store, !game.providers.contains(store) else { return nil }
        return store.label
    }
}

/// One line of a card: a label and what it says.
struct AboutRow: Identifiable {
    enum Value {
        case text(String)
        case modes([PlayMode])
        case language(LanguageSupport)
        case age(AgeRating)
    }

    let label: String
    let value: Value
    var id: String { label }
}

/// The two cards' lines, only those a store says.
enum AboutRows {
    static func facts(_ info: GameInfo) -> [AboutRow] {
        var rows: [AboutRow] = []
        if !info.genres.isEmpty { rows.append(AboutRow(label: L10n.t("Genre"), value: .text(info.genres.prefix(3).joined(separator: " · ")))) }
        if !info.developers.isEmpty, info.developers == info.publishers {
            rows.append(AboutRow(label: L10n.t("Developer & publisher"), value: .text(info.developers.joined(separator: ", "))))
        } else {
            if !info.developers.isEmpty { rows.append(AboutRow(label: L10n.t("Developer"), value: .text(info.developers.joined(separator: ", ")))) }
            if !info.publishers.isEmpty { rows.append(AboutRow(label: L10n.t("Publisher"), value: .text(info.publishers.joined(separator: ", ")))) }
        }
        if let released = info.released {
            rows.append(AboutRow(label: L10n.t("Released"),
                                 value: .text(released.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale)))))
        }
        if let age = info.age { rows.append(AboutRow(label: L10n.t("Age rating"), value: .age(age))) }
        return rows
    }

    static func play(_ info: GameInfo) -> [AboutRow] {
        var rows: [AboutRow] = []
        let modes = PlayMode.shown(info.modes)
        if !modes.isEmpty { rows.append(AboutRow(label: L10n.t("Ways to play"), value: .modes(modes))) }
        if let controller = info.controller { rows.append(AboutRow(label: L10n.t("Controller"), value: .text(controller.label))) }
        if info.language == "german", let german = info.macLanguage { rows.append(AboutRow(label: L10n.t("German"), value: .language(german))) }
        return rows
    }
}

/// A card of the grid, on thick glass like "This game".
private struct AboutCard: View {
    let title: String
    let rows: [AboutRow]
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title)
            VStack(spacing: 11) {
                ForEach(rows) { row in
                    // The value under its label when larger text leaves no room beside it.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            label(row)
                            Spacer(minLength: 12)
                            value(row.value, trailing: true)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            label(row)
                            value(row.value, trailing: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            if let footnote {
                Text(L10n.t("Details from %@ – the same game there.", footnote))
                    .font(size: 12)
                    .foregroundStyle(Theme.muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func label(_ row: AboutRow) -> some View {
        Text(row.label).font(size: 13).foregroundStyle(Theme.muted).fixedSize()
    }

    @ViewBuilder private func value(_ value: AboutRow.Value, trailing: Bool) -> some View {
        switch value {
        case .text(let text):
            Text(text)
                .font(size: 13, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(trailing ? .trailing : .leading)
                .lineLimit(2)
        case .modes(let modes):
            VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
                ForEach(modes, id: \.self) { mode in
                    HStack(spacing: 6) {
                        if !trailing { Image(systemName: mode.symbol).font(size: 11, weight: .semibold).foregroundStyle(Theme.ink.opacity(0.7)) }
                        Text(mode.label).font(size: 13, weight: .semibold).foregroundStyle(Theme.ink)
                        if trailing { Image(systemName: mode.symbol).font(size: 11, weight: .semibold).foregroundStyle(Theme.ink.opacity(0.7)) }
                    }
                    .fixedSize()
                }
            }
        case .language(let german):
            HStack(spacing: 10) {
                mark(L10n.t("Text"), german.text)
                mark(L10n.t("Speech"), german.audio)
            }
        case .age(let rating):
            AgeBadge(rating: rating)
        }
    }

    private func mark(_ label: String, _ yes: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: yes ? "checkmark" : "xmark")
                .font(size: 10, weight: .bold)
                .foregroundStyle(yes ? Theme.runsGreat : Theme.muted)
            Text(label)
                .font(size: 13, weight: .semibold)
                .foregroundStyle(yes ? Theme.ink : Theme.muted)
        }
        .fixedSize()
        .accessibilityLabel(yes ? L10n.t("%@: yes", label) : L10n.t("%@: no", label))
    }
}

/// The screenshots, small and cached at the size they're drawn: as many whole ones as fit, the last
/// one saying how many more there are. A click (A on the pad) shows one big.
struct ScreenshotStrip: View {
    let game: Game
    let screenshots: [Screenshot]
    var height: CGFloat = 150
    @EnvironmentObject private var model: LibraryModel
    @State private var images: [Int: NSImage] = [:]

    static let spacing: CGFloat = 12

    /// How many 16:9 tiles of `height` fit whole into `width` (two at least, never more than there are).
    static func count(width: CGFloat, height: CGFloat, of total: Int) -> Int {
        min(total, max(2, Int((width + spacing) / (height * 16 / 9 + spacing))))
    }

    var body: some View {
        GeometryReader { geo in
            let count = Self.count(width: geo.size.width, height: height, of: screenshots.count)
            let width = (geo.size.width - Self.spacing * CGFloat(count - 1)) / CGFloat(max(count, 1))
            HStack(spacing: Self.spacing) {
                ForEach(0..<count, id: \.self) { index in
                    tile(index, width: width, more: index == count - 1 && screenshots.count > count ? screenshots.count - count + 1 : nil)
                }
            }
        }
        .frame(height: height)
        .task(id: game.gameID) {
            for (index, shot) in screenshots.enumerated() {
                guard images[index] == nil else { continue }
                // Kept by its own name: a later answer may list the pictures in another order.
                let name = shot.thumbnail.deletingPathExtension().lastPathComponent
                if let image = await ArtworkStore.shared.screenshot(shot.thumbnail, key: "\(game.gameID.key)_\(name)") {
                    images[index] = image
                }
            }
        }
    }

    private func tile(_ index: Int, width: CGFloat, more: Int?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let open = { model.lightbox = Lightbox(game: game.gameID, screenshots: screenshots, index: index, preview: images) }
        return Button(action: open) {
            ZStack {
                if let image = images[index] {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Theme.slate
                }
                if let more {
                    Theme.night.opacity(0.62)
                    VStack(spacing: 2) {
                        Text("+\(more)")
                            .displayFont(22)
                        Text(L10n.t("Pictures"))
                            .font(size: 12, weight: .semibold)
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .help(L10n.t("Show big"))
        .accessibilityLabel(more.map { L10n.t("%ld more pictures", $0) } ?? L10n.t("Screenshot %ld", index + 1))
        .padFocus("detail.shot.\(index)", cornerRadius: 14, activate: open)
    }
}

/// "USK 12" in the colour the USK gives it, PEGI's in its own; the number always says it too.
struct AgeBadge: View {
    let rating: AgeRating

    private var colors: (fill: Color, text: Color) {
        let usk: [Int: Color] = [0: .white, 6: Color(red: 1, green: 0.93, blue: 0), 12: Color(red: 0, green: 0.65, blue: 0.32),
                                 16: Color(red: 0, green: 0.68, blue: 0.94), 18: Color(red: 0.93, green: 0.11, blue: 0.14)]
        let pegi: [Int: Color] = [3: Color(red: 0.6, green: 0.8, blue: 0.2), 7: Color(red: 0.6, green: 0.8, blue: 0.2),
                                  12: Color(red: 0.97, green: 0.65, blue: 0.1), 16: Color(red: 0.97, green: 0.65, blue: 0.1),
                                  18: Color(red: 0.89, green: 0.1, blue: 0.13)]
        let isUSK = rating.system == "USK"
        let fill = (isUSK ? usk[rating.age] : pegi[rating.age]) ?? Theme.muted
        let dark = isUSK ? [0, 6].contains(rating.age) : [3, 7, 12, 16].contains(rating.age)
        return (fill, dark ? Theme.night : .white)
    }

    var body: some View {
        Text("\(rating.system) \(rating.age)")
            .font(size: 11.5, weight: .heavy)
            .foregroundStyle(colors.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(L10n.t("Rated %@ %ld", rating.system, rating.age))
    }
}

/// A screenshot shown big over the whole window.
struct Lightbox: Equatable {
    let game: GameID
    let screenshots: [Screenshot]
    var index: Int
    /// The small pictures already loaded: shown until the big one comes.
    var preview: [Int: NSImage] = [:]

    static func == (a: Lightbox, b: Lightbox) -> Bool { a.game == b.game && a.index == b.index && a.screenshots == b.screenshots }

    /// ← → on the keyboard and the pad: the one before or after, wrapping around.
    mutating func step(_ delta: Int) {
        guard !screenshots.isEmpty else { return }
        index = (index + delta + screenshots.count) % screenshots.count
    }
}

/// A screenshot big, over everything: ← → (and the pad) for the others, Esc or B closes. The big
/// picture is loaded when it's shown and kept only while it is.
struct ScreenshotLightbox: View {
    let lightbox: Lightbox
    @EnvironmentObject private var model: LibraryModel
    @State private var big: [Int: NSImage] = [:]

    var body: some View {
        let index = lightbox.index
        ZStack {
            Theme.night.opacity(0.94)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.lightbox = nil }
            if let image = big[index] ?? lightbox.preview[index] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                    .padding(.horizontal, 120)
                    .padding(.vertical, 90)
            } else {
                GlassSpinner(size: 22)
            }
            if lightbox.screenshots.count > 1 {
                HStack {
                    RoundIconButton(symbol: "chevron.left", help: L10n.t("Previous (←)"), focusID: "lightbox.previous") {
                        model.lightbox?.step(-1)
                    }
                    Spacer()
                    RoundIconButton(symbol: "chevron.right", help: L10n.t("Next (→)"), focusID: "lightbox.next") {
                        model.lightbox?.step(1)
                    }
                }
                .padding(.horizontal, 36)
            }
            VStack {
                HStack {
                    Spacer()
                    RoundIconButton(symbol: "xmark", help: L10n.t("Close (Esc)"), size: 40, focusID: "lightbox.close") {
                        model.lightbox = nil
                    }
                }
                Spacer()
                Text("\(index + 1) / \(lightbox.screenshots.count)")
                    .font(size: 13, weight: .semibold).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(GlassBackground(glass: .regular, shape: Capsule()))
            }
            .padding(.top, 30)
            .padding(.trailing, 36)
            .padding(.bottom, 34)
        }
        .task(id: index) {
            guard big[index] == nil, lightbox.screenshots.indices.contains(index) else { return }
            var request = URLRequest(url: lightbox.screenshots[index].full)
            request.timeoutInterval = 20
            if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
               let image = NSImage(data: data) {
                // Only the one shown and its neighbours stay: a dozen 1920-pixel pictures would weigh.
                big = big.filter { abs($0.key - index) <= 1 }
                big[index] = image
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Screenshot %ld of %ld", index + 1, lightbox.screenshots.count))
    }
}
