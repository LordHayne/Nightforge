import SwiftUI

/// On a Windows game's page, under "About the game": what AppleGamingWiki says about it on a Mac,
/// way by way, and where to read more – the wiki, CodeWeavers, MacGamingDB. Others' tests on other
/// versions, so said as theirs; the wiki is named and linked, as its licence asks.
struct MacSourcesSection: View {
    let game: Game
    /// The wiki's entry for the game; nil when it has none (the links still help).
    let entry: AGWEntry?
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(L10n.t("What others report"))
            if let entry, !entry.reports.isEmpty {
                Text(L10n.t("According to AppleGamingWiki:"))
                    .font(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entry.ways, id: \.way) { item in
                        WayRow(way: item.way, report: item.report)
                    }
                }
                if let hint = model.insights[game.gameID]?.hint {
                    Label(L10n.t("Nightforge tries %@ first, as these reports did.", hint.shortLabel), systemImage: "arrow.up.forward.circle")
                        .font(size: 13, weight: .medium)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(entry.ids == "name"
                     ? L10n.t("From AppleGamingWiki (CC BY-NC-SA 3.0), shortened. Found by the game's name – it may be another edition.")
                     : L10n.t("From AppleGamingWiki (CC BY-NC-SA 3.0), shortened. Tested with other versions than Nightforge's."))
                    .font(size: 12)
                    .foregroundStyle(Theme.muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t("AppleGamingWiki has no ratings for this game yet."))
                    .font(size: 13)
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                link("AppleGamingWiki", url: entry?.pageURL ?? MacSources.wikiSearch(game.name), id: "detail.sources.agw")
                link("CodeWeavers", url: MacSources.codeWeavers(name: game.name, entry: entry), id: "detail.sources.codeweavers")
                link("MacGamingDB", url: MacSources.macGamingDB(steamAppID: game.steamAppID), id: "detail.sources.macgamingdb")
            }
        }
        .padding(20)
        .frame(maxWidth: 860, alignment: .leading)
        .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("What others report"))
    }

    @ViewBuilder private func link(_ title: String, url: URL?, id: String) -> some View {
        if let url {
            let open = { _ = NSWorkspace.shared.open(url) }
            Button(action: open) {
                Label(title, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(GlassTextButtonStyle(small: true))
            .help(url.absoluteString)
            .padFocus(id, cornerRadius: 16, activate: open)
        }
    }
}

/// One way: its name, the rating as a word in its colour, what the reports name, and the note.
private struct WayRow: View {
    let way: AGWEntry.Way
    let report: AGWEntry.Report

    private var color: Color {
        switch report.rating {
        case .perfect, .playable: return Theme.runsGreat
        case .runs, .menu: return Theme.runsWithTweaks
        case .unplayable: return Theme.runsNot
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(way.label)
                    .font(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                Text(report.rating.label)
                    .font(size: 12, weight: .semibold)
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
                if !report.basis.isEmpty {
                    Text(report.basis)
                        .font(size: 12)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if let note = report.note {
                // The wiki's own words, in English.
                Text(note)
                    .font(size: 12.5)
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(note)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
