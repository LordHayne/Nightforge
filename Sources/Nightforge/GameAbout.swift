import SwiftUI

/// Under a game's title: what it is, in up to two lines, and the way to the rest further down its
/// page. The page gives it fewer lines – or none – when the window is short (DetailLevel).
struct SummaryTeaser: View {
    let text: String
    let lines: Int
    let more: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(size: 15)
                .lineSpacing(2)
                .foregroundStyle(Theme.ink.opacity(0.82))
                .lineLimit(lines)
                .frame(minWidth: 320, maxWidth: 600, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: more) {
                HStack(spacing: 4) {
                    Text(L10n.t("More about the game"))
                    Image(systemName: "chevron.down").font(size: 10, weight: .bold)
                }
                .font(size: 13, weight: .semibold)
                .foregroundStyle(Theme.sodium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padFocus("detail.more", cornerRadius: 8, activate: more)
        }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
    }
}

/// Below a game's first screen: screenshots, what it is, its kind and ways to play, and the facts
/// beside it – from its store or the same game on Steam (GameInfo).
struct GameAboutSection: View {
    let game: Game
    let info: GameInfo
    var narrow = false

    /// Anything to show: a store that knew nothing about the game leaves the page as it was.
    static func hasContent(_ info: GameInfo) -> Bool {
        info.summary != nil || !info.screenshots.isEmpty || !info.genres.isEmpty || !info.modes.isEmpty || FactsCard.hasFacts(info)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                SectionTitle(L10n.t("About the game"))
                Image(systemName: "chevron.down")
                    .font(size: 9, weight: .bold)
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            if !info.screenshots.isEmpty {
                ScreenshotStrip(game: game, screenshots: info.screenshots, height: narrow ? 118 : 150)
            }
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 20) {
                    if let summary = info.summary {
                        Text(summary)
                            .font(size: 15)
                            .lineSpacing(3)
                            .foregroundStyle(Theme.ink.opacity(0.88))
                            .frame(maxWidth: 640, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if !info.genres.isEmpty {
                        FlowRow(spacing: 8, lineSpacing: 8, centered: true) {
                            ForEach(info.genres, id: \.self) { InfoChip(text: $0) }
                        }
                    }
                    let modes = PlayMode.shown(info.modes)
                    if !modes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(L10n.t("How it's played"))
                            FlowRow(spacing: 8, lineSpacing: 8, centered: true) {
                                ForEach(modes, id: \.self) { InfoChip(text: $0.label, symbol: $0.symbol) }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if FactsCard.hasFacts(info) {
                    FactsCard(game: game, info: info)
                }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("About the game"))
    }
}

/// A word on glass: a genre, a way to play.
private struct InfoChip: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(size: 11, weight: .semibold)
                    .foregroundStyle(Theme.ink.opacity(0.75))
            }
            Text(text)
                .font(size: 13, weight: .medium)
                .foregroundStyle(Theme.ink.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .fixedSize()
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

/// Beside the description, like "This game" above it: who made it, when, in German or not, from what
/// age, and where that's from when it's the same game on Steam.
private struct FactsCard: View {
    let game: Game
    let info: GameInfo

    static func hasFacts(_ info: GameInfo) -> Bool {
        !info.developers.isEmpty || !info.publishers.isEmpty || info.released != nil || info.age != nil
            || (info.language == "german" && info.macLanguage != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(L10n.t("At a glance"))
            VStack(spacing: 10) {
                if !info.developers.isEmpty, info.developers == info.publishers {
                    row(L10n.t("Developer & publisher"), info.developers.joined(separator: ", "))
                } else {
                    if !info.developers.isEmpty { row(L10n.t("Developer"), info.developers.joined(separator: ", ")) }
                    if !info.publishers.isEmpty { row(L10n.t("Publisher"), info.publishers.joined(separator: ", ")) }
                }
                if let released = info.released {
                    row(L10n.t("Released"), released.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale)))
                }
                if info.language == "german", let german = info.macLanguage {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(L10n.t("German")).foregroundStyle(Theme.muted)
                            Spacer(minLength: 0)
                            language(L10n.t("Text"), german.text)
                            language(L10n.t("Speech"), german.audio)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("German")).foregroundStyle(Theme.muted)
                            HStack(spacing: 12) {
                                language(L10n.t("Text"), german.text)
                                language(L10n.t("Speech"), german.audio)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(size: 13)
                    .accessibilityElement(children: .combine)
                }
                if let age = info.age {
                    HStack(spacing: 16) {
                        Text(L10n.t("Age rating")).foregroundStyle(Theme.muted).font(size: 13)
                        Spacer(minLength: 0)
                        AgeBadge(rating: age)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let source = borrowedFrom {
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                Label(L10n.t("Details from %@ – the same game there.", source), systemImage: "info.circle")
                    .font(size: 12.5)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 310)
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("At a glance"))
    }

    /// The store the facts come from, when it isn't one the game is in here.
    private var borrowedFrom: String? {
        let store = info.source.split(separator: ".").first.flatMap { Provider(rawValue: String($0)) }
        guard let store, !game.providers.contains(store) else { return nil }
        return store.label
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Text(value)
                .font(size: 13, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(size: 13)
        .accessibilityElement(children: .combine)
    }

    private func language(_ label: String, _ yes: Bool) -> some View {
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
