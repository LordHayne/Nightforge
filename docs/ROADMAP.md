# Nightforge – UX-Roadmap

> Ziel: **ein wirklich nahtloses Erlebnis – eine App, die man gerne verwendet.**
> Diese Roadmap ist so geschrieben, dass Claude Code (CC) sie Punkt für Punkt abarbeiten kann.
> Stand: 27.10.2026 · Basis: `main@bcc2065` · Nachtarbeit in PR #27 (ein Commit je Punkt)

---

## So arbeitest du damit mit Claude Code

1. **Ein Punkt pro Sitzung/Branch.** Prompt-Vorlage:
   > Lies `docs/ROADMAP.md` und den Abschnitt „Regeln für jeden Punkt“. Setz Punkt **1.3** um. Schau dir vorher das Design dazu an (`npx -y magicpath-ai inspect solidly-valley-2097 -o json`, Datei siehe „Design“). Arbeite auf einem eigenen Branch, schreib Tests wie in `tests/`, und hak den Punkt hier ab, wenn alle „Fertig wenn“-Kriterien erfüllt sind.
2. **Reihenfolge:** Phase 0 zuerst – darauf bauen fast alle anderen Punkte auf. Innerhalb einer Phase ist die Reihenfolge frei, außer bei „Braucht“.
3. **Abhaken:** `- [ ]` → `- [x]` und den Commit/PR dahinter schreiben.

### Design-Referenz

- **Klickbarer Entwurf (MagicPath):** https://www.magicpath.ai/files/464423826076372992 – Komponente `solidly-valley-2097` („Nachtschicht Library“). Quellcode lesen: `npx -y magicpath-ai inspect solidly-valley-2097 -o json`. Der Entwurf ist React/Tailwind und **nur Vorlage** – in SwiftUI nachbauen, nicht übernehmen. Dateien im Entwurf:
  - `NachtschichtLibrary.tsx` – Navigation, Startablauf, Downloads, Sitzungsende (die ganze Logik als Referenz)
  - `Home.tsx`, `Library.tsx`, `Detail.tsx` – die drei Ebenen
  - `Parts.tsx` – Play-Button-Zustände (`playLabel`, `playHint`), Kompatibilitäts-Abzeichen
  - `Cover.tsx` – Cover-Abzeichen
  - `Dialogs.tsx` – Optionen, Einstellungen (Tabs), Deinstallieren, Fehlstart
  - `Overlays.tsx` – Sitzungsabschluss, Platz-Dialog, Download-Panel, Ersteinrichtung
  - `data.ts` – Datenmodell (Provider, Kompatibilität, Spielstände, Laufwerke …)
- **Design-System (Tokens, Typo, Logos):** https://claude.ai/code/artifact/7e195660-f21f-4d6a-92ed-b22a7ec8355d – Werte stammen aus `Theme.swift` und den Views.

### Regeln für jeden Punkt

- **Texte:** Jeder sichtbare Text über `L10n.t`, **Englisch und Deutsch**. Layout muss die längere deutsche Fassung tragen.
- **Couch:** Jede neue Steuerung bekommt `.padFocus(…)`; jede Aktion hat einen Tasten- und einen Controller-Weg; die `HintBar` zeigt, was gerade gilt.
- **Farben/Typo:** nur aus `Theme` (night, slate, ink, muted, sodium). `sodium` = die eine Hauptaktion / Auswahl / Fokus – nie Deko. Neue Farben (z. B. Kompatibilität) als benannte `Theme`-Konstanten, nie inline.
- **Kein Warten ohne Erklärung, kein Fehler ohne Ausweg.** Jeder Ladezustand sagt, worauf er wartet; jede Fehlermeldung bietet mindestens eine Aktion.
- **Datenschutz:** kein Account, keine Telemetrie. Alles, was den Mac verlässt, nur nach ausdrücklichem Opt-in.
- **Offline zuerst:** UI reagiert sofort aus lokalen Daten; Netzwerk lädt im Hintergrund nach.
- **Tests:** Logik ohne UI (Sortierung, Suche, Kompatibilität, Speicherprüfung …) als Test unter `tests/<Name>Test/` mit `run.sh`, wie die bestehenden.
- **Nordstern-Messwert:** Zeit vom App-Start bis das Spiel läuft – Ziel **< 10 s** bei einem installierten Spiel. Kein Punkt darf das verschlechtern.

### Größen

`S` ≈ eine Sitzung · `M` ≈ 2–3 Sitzungen · `L` ≈ eine Woche oder mehr / braucht Recherche

---

## Phase 0 – Fundament

- [x] **0.1 Navigation in drei Ebenen** · `L` · PR #27
  - **Warum:** Heute zeigt die Leiste alle Spiele (bei 100+ Spielen unbenutzbar), der zweite Klick startet/lädt sofort (versehentliche 50-GB-Downloads), und die Bibliothek ist ein Schalter statt einer Ebene – Zurück führt nicht dorthin, wo man herkam.
  - **Was:** `LibraryModel.showingLibrary` durch eine Route ersetzen: `home` → `library` → `detail(gameID, from:)`. Esc/B geht immer eine Ebene zurück (zuerst Suche leeren, dann Ebene).
    - **Home:** Hero des gewählten Spiels + Leiste „Continue playing“ (siehe 1.7) + letzte Kachel „All games“.
    - **Library:** bestehendes `LibraryGrid` als eigene Ebene (Filter kommen in 2.1).
    - **Detail:** heutige Hero-Ansicht als Spielseite, mit Zurück-Pille („← Home“ / „← Library“).
    - **Klickverhalten:** Klick auf Cover = auswählen, zweiter Klick = **Detailseite**, nie Start. Gestartet wird nur über den Play-Button oder Enter/A.
    - Top-Bar: Segment „Home | Library (Anzahl)“.
  - **Wo:** `LibraryView.swift` (TopBar, CoverRail, GameDetail), `LibraryGrid.swift`, `LibraryModel.swift` (`toggleLibrary`, `showSelectedGame`, `primaryAction`), `InputRouter.swift`.
  - **Design:** `NachtschichtLibrary.tsx` (View-State, `back()`), `Home.tsx`, `Detail.tsx`.
  - **Fertig wenn:** Doppelklick auf ein nicht installiertes Cover startet keinen Download; Esc aus einer Detailseite, die aus der Bibliothek geöffnet wurde, landet in der Bibliothek an derselben Scroll-Position; alles per Controller erreichbar.
  - **Stand:** `Route` (`home` / `library` / `detail(gameID, from:)`) in `Navigation.swift`, Übergänge in `LibraryModel` (`goHome`, `goLibrary`, `openDetail`, `back`, `activate`); jede Ebene merkt sich ihre Auswahl. Home-Leiste vorläufig `HomeRail.pick` (Downloads, dann installiert nach „zuletzt gespielt“, max. 12) + Kachel „All games“ – Pins und 90 Tage kommen mit 1.7. Die Bibliothek bleibt hinter einer aus ihr geöffneten Detailseite stehen (unsichtbar), daher dieselbe Scroll-Position. Suche springt in die Bibliothek. Tasten: ↩ spielt (Home) / öffnet (Bibliothek) / spielt (Detail), I Details, L Home ↔ Bibliothek, Esc zurück. Pad: A wie ↩, X Details, ☰ Home ↔ Bibliothek, Y Optionen, B zurück; ↑ von der Leiste/obersten Rasterzeile in die Knöpfe, auf der Detailseite steuert der Stick die Knöpfe. Test `tests/NavigationTest/` (Leiste, Ebenen); die Übergänge mit dem echten Model gegen die echte Bibliothek durchgespielt. Nebenbei behoben: lange Hinweistexte (`fixedSize` vertikal) konnten das Fenster auf über 2500 pt Höhe ziehen (z. B. Mac-Hinweis bei 7 Days to Die) – sie haben jetzt eine Mindestbreite.

- [x] **0.2 Anbieter-neutrales Spielmodell** · `M` · `claude/epic-games-d52d35`
  - **Warum:** `Game.appID` ist eine Steam-ID. Für Epic/GOG (Phase 7) und „ein Spiel in zwei Stores = eine Karte“ braucht es eine neutrale ID – vor dem großen UI-Umbau, sonst doppelte Arbeit.
  - **Was:** `GameID { provider, id }`, `Game.providers: [Provider]` (erster = Standard zum Starten), `ArtworkStore`/Caches/Optionen auf die neue ID umstellen, Migration bestehender Einstellungen (`GameOptionsStore`, Insights) wie in `Migration.swift`.
  - **Wo:** `Library.swift`, `LibraryModel.swift`, `Artwork.swift`, `Launcher.swift` (`GameOptionsStore`), `Migration.swift`.
  - **Design:** `data.ts` (`Game`, `Provider`).
  - **Fertig wenn:** Nur Steam funktioniert wie vorher; bestehende Spieloptionen bleiben nach dem Update erhalten (Test).
  - **Stand:** `GameID { provider, id }` (`GameID.swift`, `Provider` = steam/epic) ist der Schlüssel jedes `Game` (`game.gameID`); `appID` gibt es nur noch als Steam-Sicht (0 bei anderen Stores) für Steams eigene Pfade, Manifeste, Store-Seiten und die Profilliste. Auf die neue ID umgestellt: Spieloptionen (`GameOptionsStore`), Start-Erfahrung (`LaunchHealth`, `LearnedFixes`), Shader-Merker (`LaunchPhase`), Bildratenlernen (`FramePacing`), Bewertungen (`GameRatings`), Ausblenden/Anheften (`GameMarks`, jetzt `marks.hidden`/`marks.pinned`), Cover-Cache (`steam.570_cover`) sowie Insights, Analysen, Download-Tempo und Vorbereitungen im `LibraryModel`. Gespeichert wird unter `GameID.key` („steam.570“, „epic.Fortnite“). Links: Steam-Spiele behalten `nightforge://play/570` (bestehende Apps in „Programme“ gehen weiter), andere Stores `nightforge://play/epic.Fortnite`. **Migration** `GameIDMigration` (`Migration.swift`, einmal beim Start nach `LegacyMigration`): kopiert alle Einstellungen „<präfix><App-ID>“ auf „<präfix>steam.<App-ID>“, übernimmt die Markierungen und verlinkt den Cover-Cache (harte Links, offline weiter da). Die alten Einträge bleiben stehen, damit ein älteres Nightforge (z. B. ein Build von `claude/ux-roadmap-next`) sie weiter findet – aufräumen später. Test `tests/GameIDTest/` (Schlüssel, Links, Optionen/Gelerntes/Bewertung/Markierungen/Cover nach dem Update da, nur einmal). **Abweichung:** `Game.providers` (ein Spiel in zwei Stores = eine Karte) kommt mit 7.4; heute hat jeder Eintrag genau einen Store. `MacHealth`, `SaveTransfer` und die Mac-Versions-Wahl bleiben bei der Steam-App-ID – Mac-Versionen gibt es nur über Steam für Mac.

- [x] **0.3 Toasts mit Aktion** · `S` · PR #9, benutzt seit 1.4 (PR #27)
  - **Was:** Leichtgewichtige Meldung unten mittig mit optionalem Button („Undo“, „Play“, „Show“), Auto-Ausblenden (2,8 s, mit Aktion 5 s), per Controller erreichbar.
  - **Design:** `NachtschichtLibrary.tsx` (`notify`), Toast-Markup.
  - **Fertig wenn:** Wird von 1.4 (Undo), 4.4 (Download fertig → Play) benutzt.
  - **Stand:** Komponente fertig – `Toast.swift` (`Toasts.shared.show(_:action:)`, `ToastHost` im Hauptfenster, Aktion per ⌘↩ oder Pad, HintBar zeigt sie, VoiceOver liest vor, „Reduce motion“ nur Überblenden). Benutzt von 1.4 (Ausblenden → „Undo“, Anheften) und vom fertigen Download („<Spiel> is ready to play“ → „Play“, Teil von 4.4).

---

## Phase 1 – Schnelle Gewinne mit vorhandenen Daten

- [x] **1.1 Ehrliche Wartezustände beim Start** · `M` · braucht 0.1 · PR #27
  - **Warum:** Ein Launcher, der 40 s „Launching …“ zeigt, wirkt kaputt. Shader-Kompilierung beim ersten Start/nach Updates ist normal – man muss es nur sagen.
  - **Was:** Startphasen auf dem Play-Button, je mit Erklärzeile darunter:
    - „Starting Steam …“ (Steam unsichtbar im Hintergrund)
    - „Preparing shaders … N %“ (erster Start / nach Grafik-Update; Fortschritt wenn ermittelbar, sonst unbestimmt)
    - „Launching …“
  - **Wo:** `LibraryModel.launchStatus` existiert bereits → zu einem Enum `LaunchPhase` ausbauen; Quellen: `Launcher.swift` (Steam-Konsolen-Log), `GameLog.swift`, DXMT/DXVK-Shader-Cache-Ordner (prüfen, ob leer/neu).
  - **Design:** `Parts.tsx` → `LaunchPhase`, `playLabel`, `playHint`.
  - **Fertig wenn:** Jede Phase > 2 s hat einen eigenen Text; nach einem Grafik-Update zeigt der erste Start „Preparing shaders“, der zweite nicht.
  - **Stand:** `LaunchPhase.swift` ersetzt `launchStatus`: Starting Steam (neu, solange die Hintergrund-Steam noch hochfährt) / Starting Steam for Mac / Signing in / Sign in in the Steam window / Setting up the game / Setting up .NET / Restarting Steam / Starting again with …, jede mit Erklärzeile unter dem Play-Knopf; „Confirm in the Steam window“ ebenso. Shader: Beim ersten Start mit neuer Engine, anderer Ebene oder neuen Grafik-Builds aus der Komponentenliste (`LaunchPhase.graphicsSignature`) steht unter „Launching …“ „First start with this graphics version: shaders are prepared …“; nach dem Start wird die Signatur gemerkt, der zweite Start zeigt es nicht. **Abweichung:** kein Prozentwert – die Shader entstehen erst im laufenden Spiel; der Knopf heißt weiter „Launching …“, die Zeile erklärt die Wartezeit. Test in `tests/LaunchHealthTest/`.

- [x] **1.2 Fehlstart mit Lösung statt Sackgasse** · `M` · PR #27
  - **Was:** Das heutige Alert „didn't start“ wird zum Sheet: Erklärung + **„Start with ‚Most compatible‘“** (Primär) + **„Start through <anderer Store>“** (wenn vorhanden) + „Report problem“ (bestehend).
  - **Wo:** `LibraryView.swift` (`failedLaunch`-Alert), `LaunchHealth.swift` (Attempts), `ProblemReport.swift`.
  - **Design:** `Dialogs.tsx` → `LaunchFailedDialog`.
  - **Fertig wenn:** Kein Fehlstart endet ohne mindestens eine Aktion außer „OK“.
  - **Stand:** Sheet `FailedLaunchSheet` statt Alert: was versucht wurde („Tried: DXMT · DXVK · D3DMetal“), **„Try Again From the First Way“** (Primär, ↩/A – setzt `LaunchHealth` zurück und startet neu; hilft bei Steam-Update oder Rückfrage-Fenster), **„Choose Graphics by Hand …“** (öffnet die Spieloptionen; nur wo es Ebenen zur Wahl gibt) und „Report problem“. **Abweichung:** „Most compatible“ gibt es erst mit den Voreinstellungen aus 2.3 – heute hat „Automatic“ bei einem Fehlstart schon jede passende Ebene probiert. „Start through <anderer Store>“ kommt mit Phase 7.

- [x] **1.3 Kompatibilitäts-Abzeichen („Runs great“)** · `M` · PR #9, angezeigt seit 0.1 und 2.1 (PR #27)
  - **Warum:** „Läuft das überhaupt?“ ist die erste Frage. Steam Deck Verified hat gezeigt, wie viel klare Stufen bringen – für den Mac gibt es so etwas nicht.
  - **Was:** Stufen `great` / `tweaks` / `no` / `untested`, immer **Icon + Wort** (nie nur Farbe). Ableitung lokal:
    - `no`: `AntiCheatBlock` (ohne GeForce Now), VR-only
    - `tweaks`: Profil mit Fixes / `LearnedFixes` / Anti-Cheat nur online / D3D12-only
    - `great`: Nightforge-eigenes Profil oder erfolgreiche Starts ohne Fixes
    - `untested`: sonst
    - Optional Zeile „Tested on M2, M3“ (wenn das Profil das hergibt).
  - **Wo:** neu `Compatibility.swift`; Quellen `Profiles.swift`, `LaunchHealth.swift` (`LearnedFixes`), `GameAnalysis.swift`. Anzeige: Hero-Metazeile, Detail-Karte „On a Mac“, Rasterkarte, Filter (2.1).
  - **Design:** `Parts.tsx` → `CompatBadge`; `Detail.tsx` → `CompatCard`.
  - **Fertig wenn:** Jedes Spiel hat eine Stufe; Unit-Test für die Ableitung; Kontrast ≥ 4,5:1 auf `night`.
  - **Stand:** Ableitung, Abzeichen und Test fertig – `Compatibility.swift` (`Compatibility.of(game, profile:, analysis:)`, `CompatibilityBadge`), `tests/CompatibilityTest/` (inkl. Kontrast). Farben `Theme.runsGreat / runsWithTweaks / runsNot`; „Tweaks“ bewusst blasser als `sodium`. Mit GeForce Now bleibt die Stufe `no`, die Notiz verweist auf GeForce Now (wie im Entwurf). Angezeigt in Home-Hero (Abzeichen), Detailseite (Abzeichen + Notiz + „Tested on“) und Rasterkarte (Symbol vor dem Namen) seit 0.1. Filter „Runs great“ seit 2.1.

- [x] **1.4 Spiele ausblenden & anpinnen** · `S` · braucht 0.3 · PR #27
  - **Was:** Detailseite: „Hide from library“ (Taste H) mit Undo-Toast; Bibliothek: Umschalter „Hidden (n)“ zum Zurückholen. „Pin to Home“ (Taste P): bleibt in der Home-Leiste, auch wenn lange nicht gespielt; Pin-Abzeichen auf dem Cover.
  - **Wo:** `Prefs` (UserDefaults), `LibraryModel`, `LibraryGrid`.
  - **Design:** `Detail.tsx` (Buttons), `Library.tsx` (Hidden-Toggle), `Cover.tsx` (Pin).
  - **Fertig wenn:** Ausgeblendete Spiele erscheinen weder in Home noch in Suche/Raster (außer im Hidden-Filter); bleibt über Neustarts erhalten.
  - **Stand:** `GameMarks.swift` (UserDefaults `library.hidden` / `library.pinned`, nach App-ID – überlebt den Wechsel Mac ↔ Windows-Version). Detailseite: Augen- und Pin-Knopf (H / P, per Pad erreichbar), „Hidden“-Chip; Ausblenden schließt die Seite und zeigt einen Toast mit „Undo“ (holt auch den Pin zurück). Bibliothek: Leiste über dem Raster mit Schalter „Hidden n“ (nur wenn es welche gibt); Esc schaltet ihn zuerst aus. Angeheftete Spiele stehen vorne in der Home-Leiste (nach Name), Pin-Abzeichen auf dem Cover. Zähler (Bibliothek, „All games“) ohne ausgeblendete Spiele. Tests in `tests/NavigationTest/` (Pins in der Leiste, Speichern/Laden); Ablauf mit dem echten Model durchgespielt.

- [x] **1.5 Suche mit Abkürzungen** · `S` · PR #27
  - **Was:** „rdr2“ → Red Dead Redemption 2, „bg3“ → Baldur's Gate 3 (Anfangsbuchstaben + Ziffern), Wortanfänge zuerst. Store-Treffer bleiben eigener Abschnitt.
  - **Wo:** `LibraryModel.searchKey` / `applyFilter`.
  - **Design:** `data.ts` → `searchMatches`, `searchRank`.
  - **Fertig wenn:** Test mit rdr2, bg3, „witcher“, „gate 3“, Umlauten.
  - **Stand:** `Search.swift` (`Search.rank(name:query:)`: 0 Wortanfänge, 1 Initialen mit Zahlen, 2 irgendwo im Namen). Apostroph verbindet („Baldur's“ → bg3), andere Zeichen trennen („Half-Life“ → hl2, „S.T.A.L.K.E.R.“ → stalker). `applyFilter` sortiert danach, innerhalb gleicher Stufe Bibliotheksreihenfolge. Test `tests/SearchTest/`.

- [x] **1.6 „Credits & Lizenzen“ + Datenschutz-Seite** · `S` · (Teil von 2.2) · PR #27
  - **Was:** Liste aus `components/manifest.json` (Name, Version, Lizenz – Felder sind schon da) plus umu-protonfixes (BSD-2) und AreWeAntiCheatYet (MIT); Satz „No account. No telemetry. No background service.“
  - **Design:** `Dialogs.tsx` → Tab „About“.
  - **Fertig wenn:** Jede mitgelieferte Komponente steht mit Lizenz drin, automatisch aus dem Manifest.
  - **Stand:** Tab „About“: „No account. No telemetry. No background service.“ + Satz zum Problembericht; Liste aus `ComponentStore.localManifest()` (zuletzt geladene Liste, sonst die mitgelieferte – ohne Netz) mit Name, Version, Rolle, Lizenz, dazu umu-protonfixes (BSD-2-Clause) und AreWeAntiCheatYet (MIT); „Show Licence Files“ zeigt die Lizenzdateien in der App im Finder. „Show the first start again“ kommt mit 6.1.

- [x] **1.7 Home-Leiste = „Continue playing“** · `S` · braucht 0.1, 1.4 · PR #27
  - **Was:** Angepinnte zuerst, dann installiert/ladend und in den letzten 90 Tagen gespielt, max. 12; letzte Kachel „All games · N“.
  - **Design:** `data.ts` → `continuePlaying`; `Home.tsx` → `Rail`.
  - **Fertig wenn:** Bei 100+ Spielen enthält die Leiste ≤ 13 Elemente.
  - **Stand:** `HomeRail.pick` – Angeheftete (nach Name), dann Downloads, dann installiert und in den letzten 90 Tagen gespielt (neueste zuerst), max. 12, plus Kachel „All games“. Abweichung: Sind es weniger als 3 (neue Bibliothek), füllen andere installierte Spiele auf, damit Home nie leer ist. Überschrift „Continue playing · Pinned, then what you played lately“. Kopfzeile: Bereichsschalter schrumpft nicht mehr, die Suche wird bei schmalem Fenster schmaler. Test in `tests/NavigationTest/`.

- [x] **1.8 „Update & Play“** · `M` · PR #27 (ungetestet mit echtem Update)
  - **Warum:** „Play“ wird sonst überraschend zu einem 8-GB-Download.
  - **Was:** Steht ein Pflicht-Update an, zeigt der Button vorher „Update & Play · 1.2 GB“; nach dem Update startet das Spiel von selbst. Update-Abzeichen auf dem Cover.
  - **Wo:** `Library.swift` (appmanifest – `StateFlags`/`UpdateResult`/`BytesToDownload` prüfen und verifizieren), `LibraryModel.primaryAction`.
  - **Design:** `Parts.tsx` (`Update & Play`), `NachtschichtLibrary.tsx` (`playAfterUpdate`).
  - **Fertig wenn:** Update-Größe ist vor dem Klick sichtbar; nach Ende des Updates startet das Spiel ohne weiteren Klick.
  - **Stand:** `UpdateState` (Library.swift) liest aus dem appmanifest: Update wartet = StateFlags-Bit 2 oder TargetBuildID ≠ buildid; Größe = BytesToDownload − BytesDownloaded (0 = Steam kennt sie noch nicht); läuft = Bits 256/1024/Downloading/Staging/Committing. Play-Knopf „Update & Play · 1,2 GB“ (ohne Größe, solange unbekannt), Abzeichen auf dem Cover, VoiceOver „Installed, update waiting“. Beim Start liest Nightforge jede Sekunde das Manifest: Solange Steam aktualisiert, zeigt der Knopf „Updating … 42 %“ mit Erklärzeile, und das zählt nicht als „Steam antwortet nicht“ – Steam startet das Spiel danach selbst (Steams eigenes Verhalten bei einer Startanfrage). Test `tests/UpdateStateTest/` (mit den echten Werten von diesem Mac). **Noch nicht mit einem echten Update ausprobiert** – gerade wartet bei keinem Spiel eins.

---

## Phase 2 – Bibliothek, Einstellungen, Optionen

- [x] **2.1 Bibliothek mit Filtern & Sortierung** · `M` · braucht 0.1, 1.3 · PR #27
  - **Was:**
    - **Filter:** „All / On this Mac / Not downloaded“, pro Store (mit Anzahl, Warnsymbol bei Sync-Fehler), „Runs great“, „Controller“, „Mac version“, „Hidden“.
    - **Sortierung:** Recently played / Name / Size.
    - **Suche:** Treffer in einer Liste, beste zuerst.
  - **Wo:** `LibraryGrid.swift` (Sections), `LibraryModel`.
  - **Design:** `Library.tsx`.
  - **Fertig wenn:** Filter kombinierbar, Zustand bleibt beim Wechsel Detail ↔ Bibliothek erhalten, alles per Controller bedienbar.
  - **Stand:** `LibraryFilters.swift` (Status All / On this Mac / Not downloaded, „Runs great“, „Controller“ = volle Unterstützung, „Mac version“; Sortierung Recently played / Name / Disk space) und `LibrarySection.make` (Suche = eine Trefferliste, beste zuerst; Hidden = nach Name; „Recently played“ gruppiert nach Installiert / Lädt / Rest; Name/Größe eine Liste; Store-Treffer zuletzt). Leiste über dem Raster (nicht mitscrollend): Titel + „n von m Spielen“, Hidden-Schalter, Sortierung; darunter Status und Filter – jedes Segment ein eigener Pad-Knopf (↑ aus der obersten Rasterzeile). Filter gelten nur in der Bibliothek (Home bleibt vollständig) und bleiben über Detailseite und Home hinweg erhalten. Leeres Ergebnis: „No games match these filters“ + „Clear filters“. Pro-Store-Filter kommt mit Phase 7 (heute nur Steam). Test `tests/LibraryFiltersTest/`.

- [x] **2.2 Einstellungen in Tabs** · `M` · PR #27
  - **Was:** Tabs `Stores` · `General` · `Controller` · `Storage` · `About`. Inhalte siehe 1.6, 4.3, 5.4, 2.5.
  - **Wo:** `SettingsViews.swift` (`SettingsView`).
  - **Design:** `Dialogs.tsx` → `SettingsDialog`.
  - **Stand:** `SettingsView.swift` mit Tab-Leiste (eigene Pad-Knöpfe): **Stores** (Steam: angemeldet/Spiele, „Open Steam“; CrossOver/Whisky/eigenes Wine), **General** (wie bisher), **Controller** (Teil von 5.4), **About** (1.6). `SettingsView(tab:)` öffnet direkt einen Tab. **Storage** (Teil von 4.3). In General inzwischen auch 5.1 (Mitteilungen), 2.5 (Reduce motion) und 3.4 (Akku sparen).

- [ ] **2.3 Grafik-Voreinstellungen in Klartext + Profil-Herkunft** · `M` · Herkunft in PR #27
  - **Was:** In den Spieloptionen statt Einzelschaltern zuerst vier Voreinstellungen:
    - **Automatic (recommended):** bisheriges Verhalten.
    - **Fastest / Balanced / Most compatible:** werden auf `GraphicsLayer`, Frame-Limit und MetalFX gemappt.
    - **Expertenoptionen** darunter.
    - **Kopfzeile:** „Tested by Nightforge · updated 5 days ago“ bzw. „Community fix · from umu-protonfixes“, dazu „Reset to profile“.
    - **Detailseite:** Karte „This game“ zeigt Store, Version, Grafik, HUD, Startoptionen, Engine, Offline-Status sowie „Your own settings … Back to the profile“.
  - **Wo:** `SettingsViews.swift` (`GameOptionsSheet`), `Launcher.swift` (`GameOptions`, `GraphicsLayer`), `Profiles.swift`.
  - **Design:** `Dialogs.tsx` → `GameOptionsDialog`; `Detail.tsx` → `OptionsSummary`; `data.ts` → `PRESETS`.
  - **Stand** (teilweise): Kopfzeile in den Spieloptionen – „Tested by Nightforge on M5“ (Chips aus der Profilnotiz, Notiz beim Darüberfahren) bzw. „Community fix · from umu-protonfixes“; weichen die Optionen vom Standard ab: „Your own settings. Back to the Profile“ (ohne Profil „Back to Automatic“), wirksam mit „Save“. Offen – **braucht deine Entscheidung:** welche Ebene/Grenze/MetalFX „Fastest“, „Balanced“ und „Most compatible“ genau bedeuten; „updated 5 days ago“ (die Profilliste hat ein `generated`-Datum, aber nicht pro Spiel); Karte „This game“ auf der Detailseite.

- [x] **2.4 „Bereit für offline“** · `M` · Recherche · PR #27
  - **Was:** Pro Spiel: „Ready“ oder „Start online once“. Steams Offline-Modus muss vorher online aktiviert worden sein – herausfinden, woran man das erkennt (z. B. `loginusers.vdf`, letzter erfolgreicher Online-Start).
  - **Design:** `Detail.tsx` → Zeile „Offline“.
  - **Stand:** Recherche – Steams Offline-Modus braucht ein gemerktes Konto (`config/loginusers.vdf`: `RememberPassword` 1; auf diesem Mac gesetzt). Pro installiertem Spiel auf der Detailseite „Offline: Ready / Start online once / Update first / Needs internet / Not yet“ mit Erklärung beim Darüberfahren (`OfflineReadiness.swift`): kein gemerktes Konto → „Not yet“; Steam nennt keinen Einzelspielermodus oder eigener Launcher mit Anmeldung → „Needs internet“; Update wartet → „Update first“; noch nie gestartet → „Start online once“; sonst „Ready“. Heuristik – was ein Spiel intern online prüft (DRM), sieht Nightforge nicht. Test `tests/OfflineReadinessTest/`.

- [ ] **2.5 Barrierefreiheit** · `S` · teilweise in PR #27
  - **Was:** „Reduce motion“ (folgt `NSWorkspace.accessibilityDisplayShouldReduceMotion`, abschaltbar): kein Lampen-Flackern, kein Cover-Zoom, nur Überblenden. „Larger text“ (eine Stufe größer). VoiceOver-Labels für alle Icon-Buttons und Abzeichen.
  - **Design:** `Dialogs.tsx` → Tab „General › Accessibility“; `index.css` (`.ns-reduce`).
  - **Stand** (teilweise): „Reduce motion“ in General › Accessibility – folgt macOS, bis man es umstellt (`Prefs.reduceMotion`, eigener Umgebungswert `\.reduceMotion`, weil SwiftUIs eigener nicht überschreibbar ist); schaltet Cover-Zoom, Rail-/Raster-Scrollen und Toast-Gleiten ab. VoiceOver-Labels: alle neuen Icon-Knöpfe, Abzeichen (Kompatibilität, Pin) und Kacheln haben Namen. Offen: „Larger text“ – die Ansichten nutzen feste Schriftgrößen (`.system(size:)`), das braucht einen Skalierungsfaktor quer durch alle Views.

---

## Phase 3 – Der Kreis ums Spielen

- [ ] **3.1 Sitzungsabschluss („Welcome back“)** · `M` · teilweise in PR #27
  - **Warum:** Wir denken bisher nur bis zum Start. Am Ende will man wissen: Ist der Spielstand sicher, kann ich zuklappen?
  - **Was:** Wenn das Spiel endet (Nightforge kommt ja schon nach vorne), Sheet mit:
    - Spielzeit dieser Sitzung und gesamt
    - Spielstand-Status: „Uploading to Steam Cloud …“ → „Save is in Steam Cloud. You can close your Mac.“ (bzw. „Saved on this Mac only“)
    - „How did it run?“ 👍/👎 (als Icons) mit Gründen (Stutters, Crashed, Low frame rate …); bei Abstürzen/Ruckeln das Angebot „Use ‚Most compatible‘ next time“
    - Buttons „Play again“ / „Done“
  - **Wo:** `LibraryModel` (Erkennung Spielende), Steam-Cloud-Status aus dem Steam-Log/`remotecache.vdf` (recherchieren), `SaveTransfer.swift` (Speicherorte).
  - **Design:** `Overlays.tsx` → `SessionSummary`.
  - **Fertig wenn:** Erscheint nach jedem Spielende; die Bewertung wird lokal gespeichert und fließt in 1.3 (eigene Erfahrung schlägt Profil).
  - **Stand** (teilweise): `SessionSummary.swift` – nach jedem von Nightforge gestarteten Spiel, das mindestens eine Minute lief, Sheet „Welcome back“: Spielzeit diesmal und insgesamt (Steams Zählung, ohne Doppelzählung), „How did it run?“ 👍/👎 mit Gründen (Stutters, Crashed, Low frame rate, Graphics glitches, Controller, Sound), „Play Again“ / „Done“. Bewertung lokal (`GameRatings`, UserDefaults) und in `Compatibility.rate` vor dem Profil (👍 → great, 👎 → tweaks mit „You said: …“; Anti-Cheat/VR bleiben „no“). Test in `tests/CompatibilityTest/`. Spielstand-Zeile: `CloudSaves.swift` liest `userdata/<Konto>/<App-ID>/remotecache.vdf` (pro Cloud-Datei `syncstate`, 1 = im Einklang); „Your save is in the Steam Cloud. You can close your Mac.“ erst, wenn Steam die Datei nach dem Spielende neu geschrieben hat und alle Dateien auf 1 stehen – vorher „Steam is syncing …“ (alle 2 s geprüft), nach einer Minute ohne Bestätigung „Steam syncs your save in the background.“, ohne Datei „No Steam Cloud for this game – its saves are on this Mac.“ Test `tests/CloudSavesTest/`. Die Bedeutung der anderen `syncstate`-Werte ist nicht dokumentiert – deshalb nur „1“ als sicher. Offen: „Use ‚Most compatible‘ next time“ (braucht 2.3).

- [ ] **3.2 Spielstand-Konflikt lösen, bevor etwas überschrieben wird** · `L` · Recherche · teilweise in `claude/ux-roadmap-next`
  - **Was:** Weichen lokaler und Cloud-Spielstand voneinander ab: Vor dem Start „Keep this Mac · today 14:02 (Newer)“ vs. „Keep the cloud · yesterday“; der andere wird als Backup im Spielordner behalten. Play zeigt bis dahin „Choose a save first“.
  - **Wo:** `SaveTransfer.swift`, `SteamCatalog.SaveRule`.
  - **Design:** `Detail.tsx` → `SaveChoice` (+ kompakte Variante in `Home.tsx`).
  - **Fertig wenn:** Kein Szenario, in dem Nightforge stillschweigend einen neueren Spielstand verliert (Test mit Fake-Ordnern).
  - **Recherche** (27.10.): Zwei Fälle.
    - **Steam Cloud:** Steam vergleicht beim Start selbst und zeigt bei einem Konflikt sein eigenes Fenster („Cloud Sync Conflict“). Was in der Cloud liegt, weiß vorher nur Steam: `remotecache.vdf` hält pro Datei `localtime`, `remotetime`, `sha` und `syncstate` vom *letzten* Abgleich. Nightforge kann vorab nur erkennen, dass lokal etwas geändert wurde (Datei neuer oder `sha` anders). Aufgabe hier: Steams Konfliktfenster nach vorne holen und sagen, was zu tun ist – wie bei „Confirm in the Steam window“.
    - **Wechsel Windows ↔ Mac-Version** (`SaveTransfer`): Heute füllt Nightforge nur *leere* Spielstand-Ordner. Haben beide Seiten Stände, passiert nichts, und man spielt womöglich mit dem älteren weiter. Plan: vor dem ersten Start nach einem Versionswechsel die neueste Datei beider Seiten vergleichen; weichen sie ab, Auswahl „Weiter mit dem Stand der Windows-Version · heute 14:02 (neuer)“ / „… der Mac-Version · gestern“. Der andere Stand wird vorher nach `Backups/` kopiert.
  - **Stand** (`claude/ux-roadmap-next`, teilweise):
    - **Wechsel Windows ↔ Mac-Version:** Haben beide Seiten Spielstände und die zuletzt gespielte Version die neueren, fragt ein Sheet vor dem Start: „Mit welchem Spielstand willst du weiterspielen?“. Zur Wahl stehen die Windows-Version (Heute, 14:02, Abzeichen „Neuer“) und die Mac-Version (Gestern). Die neuere ist vorausgewählt (↩/A); Esc/B behält den eigenen.
    - **Übernehmen:** Zuerst kommen alle eigenen Stände dieser Version nach `Backups/<Spiel>-saves-<Zeit>/<Version>/`. Klappt das nicht, bleibt alles unverändert. Danach hat der Ordner genau die Stände der anderen Version.
    - Gleiche Dateien auf beiden Seiten lösen nichts aus. `SaveTransfer.newerElsewhere` / `takeNewer`, Test in `tests/MacVersionTest/`.
    - „Komplett entfernen“ (4.3) nimmt diese Sicherungen mit nach „Dokumente“.
    - Offen: Steam-Cloud-Konflikt – Steams eigenes Fenster nach vorne holen und sagen, was zu tun ist. Dafür braucht es einen echten Konflikt zum Ausprobieren.

- [ ] **3.3 Automatisches Zurückrollen der Engine** · `L` · braucht 1.1
  - **Warum:** macOS-/Wine-Updates machen Spiele kaputt, die gestern liefen (siehe Whisky). Selbst-Heilung ist ein echtes Alleinstellungsmerkmal.
  - **Was:**
    - Pro Spiel die letzte funktionierende Kombination aus Engine und Grafikschicht merken.
    - Die vorige Engine-Version bleibt installiert (`ComponentStore`).
    - Stürzt ein Spiel nach einem Update beim Start ab: automatisch mit der alten Version starten. Phase „Trying last week's engine …“, danach Hinweis „Runs with last week's engine … Try the newest now“.
    - Nach dem nächsten Engine-Update wird automatisch wieder die neue versucht.
  - **Wo:** `Components.swift` (`ComponentStore`, Versionen), `LaunchHealth.swift`, `Engine.swift`.
  - **Design:** `Parts.tsx` (`rollback`-Phase), `Detail.tsx` (Engine-Hinweis, Zeile „Engine … (held back)“).
  - **Fertig wenn:** Ein simuliertes kaputtes Engine-Update führt zu einem erfolgreichen Start mit der alten Version, ohne dass der Nutzer etwas tun muss.

- [x] **3.4 Akku-Modus** · `S` · PR #27 (standardmäßig aus)
  - **Was:** Ohne Netzteil (IOKit `IOPSCopyPowerSourcesInfo`): Bildrate auf 30 FPS begrenzen, Hinweis „On battery: capped at 30 FPS – about 1 h 40 min of play“, Akkustand in der Top-Bar. Abschaltbar in General. Grundlage für die Begrenzung: `FramePacing.swift`.
  - **Design:** `Parts.tsx` (`playHint` mit `onBattery`), Top-Bar-Akku.
  - **Stand:** `PowerSource.swift` (IOKit: Akku/Netzteil, Ladestand; alle paar Sekunden im bestehenden Lauf-Check). Schalter „Save battery when unplugged“ in General – **standardmäßig aus** (Abweichung, bitte entscheiden: du magst 60 FPS fest, deshalb nicht ungefragt eingeschaltet). Ist er an und der Mac im Akkubetrieb, startet ein Spiel mit höchstens 30 FPS (auch ohne eigene Grenze), und aus so einer Sitzung lernt `FramePacing` nichts. Top-Bar zeigt im Akkubetrieb den Ladestand (unter 20 % in der Akzentfarbe), die Spielseite die Zeile „On battery: games are capped at 30 FPS …“. Ohne Restzeit-Schätzung – macOS' Schätzung gilt für die aktuelle Last, nicht fürs Spielen. Test in `tests/LaunchHealthTest/`.

---

## Phase 4 – Speicherplatz & Downloads

- [x] **4.1 Platz prüfen vor dem Download** · `M` · PR #27
  - **Was:** Ist zu wenig Platz frei: Dialog „<Spiel> needs 49.5 GB – 18.5 GB short“ mit (a) „Install on <externe SSD>“ und (b) „Make room“. Vorgeschlagen werden lange nicht gespielte Spiele (Größe, zuletzt gespielt, „saves stay in the cloud“), vorausgewählt bis es reicht → „Uninstall n & download“.
  - **Design:** `Overlays.tsx` → `SpaceDialog`.
  - **Fertig wenn:** Kein Download startet, der mangels Platz abbrechen würde.
  - **Stand:** `SpaceCheck.swift` – vor jedem Download (Windows und Mac) Vergleich Downloadgröße + 1 GB Reserve mit dem freien Platz des Ziel-Volumes (nächster existierender Ordner). Reicht es nicht: Sheet „<Spiel> needs up to …“ mit fehlender Menge und bis zu 8 installierten Spielen auf demselben Volume, die seit 30 Tagen nicht (oder nie) gespielt wurden, größte zuerst, vorausgewählt bis es reicht → „Uninstall n & Download“ deinstalliert nacheinander und lädt dann (prüft vorher noch einmal). Gibt es keine Kandidaten, sagt das Sheet das. „Install on <externe SSD>“ kommt mit 4.2. Test `tests/SpaceCheckTest/`.

- [ ] **4.2 Spiele auf externen Laufwerken** · `L` · Recherche · teilweise in `claude/ux-roadmap-next`
  - **Was:** Steam-Bibliotheksordner auf externen Volumes anlegen/erkennen (`libraryfolders.vdf`), Spiele dorthin installieren und zwischen Laufwerken verschieben. Ist das Laufwerk nicht angeschlossen: Spiel ausgegraut mit „Connect Samsung T7 to play“.
  - **Design:** `Detail.tsx` (Stat „On“), `Dialogs.tsx` → Tab „Storage“ (Move to …).
  - **Recherche** (27.10.):
    - **Pfad:** Steam unter Wine nimmt jeden Laufwerksbuchstaben, und `Z:` zeigt auf `/`. Ein Bibliotheksordner `Z:\Volumes\T7\Nightforge Games` braucht also keinen eigenen Buchstaben und bleibt gültig, solange das Laufwerk so heißt. Wine legt für eingesteckte Laufwerke zwar selbst Buchstaben an (`d:` → `/Volumes/…`), die wechseln aber.
    - **Bibliothek anlegen:** Ein Eintrag in `steamapps/libraryfolders.vdf` (Pfad, `contentid`, `apps` mit App-ID → Größe) plus ein Ordner mit `steamapps/`. Steam liest beides beim Start, also bei gestopptem Steam schreiben – wie `requestDownload`. Nightforge liest Zusatzbibliotheken schon heute (`LibraryScanner.libraryFolders`).
    - **Verschieben:** Bei gestopptem Steam `steamapps/common/<Ordner>` und `appmanifest_<id>.acf` in die andere Bibliothek legen, dann findet Steam das Spiel dort. So steht es in Erfahrungsberichten ([Steam-Forum](https://steamcommunity.com/discussions/forum/1/1762481957319992375), [steam-mv](https://github.com/oaksisfolks/steam-mv)); selten will Steam danach neu prüfen.
    - **Nicht angeschlossen:** Die `apps`-Liste des Eintrags bleibt in `libraryfolders.vdf` stehen. Das Spiel kann also „Connect T7 to play“ zeigen statt „Download“.
    - **Steam für Mac** hat eigene Bibliotheksordner (Mac-Pfade, gleiches Format).
    - **Dateisystem:** exFAT geht, hat aber keine Unix-Rechte und Symlinks, deshalb könnten einzelne Spiele scheitern. APFS ist besser.
    - Anlegen und Verschieben bleiben offen bis zum Test mit einem echten externen Laufwerk (gerade ist keins angeschlossen).
  - **Stand** (`claude/ux-roadmap-next`, teilweise): **Nicht angeschlossen:** Liegt ein Spiel in einer Steam-Bibliothek auf einem Laufwerk, das gerade fehlt, heißt der Play-Knopf „Connect T7 to Play“ und ist gesperrt. ↩/A lädt dann auch nichts doppelt herunter.
    - Erkannt wird das an `libraryfolders.vdf` (`LibraryScanner.missingDrives`): `/Volumes/<Name>` fehlt. Das gilt für Mac-Pfade, für `Z:\Volumes\…` und für Laufwerksbuchstaben, die Wine dorthin verlinkt hat – in Nightforges Steam und in Steam für Mac.
    - Test `tests/ExternalDriveTest/`.
    - Offen: Bibliothek anlegen, „Install on <Laufwerk>“ im Platz-Sheet und „Move to …“ – erst mit einem echten Laufwerk ausprobieren.

- [ ] **4.3 Speicher-Übersicht & sauber entfernen** · `M` · teilweise in PR #27
  - **Was:** Tab „Storage“:
    - **Balken pro Laufwerk:** Spiele / Nightforge / Rest.
    - **Installierte Spiele:** nach Größe sortiert, jeweils mit „Move to …“.
    - **Shader-Caches:** „Clear“ mit Größe.
    - **Komplett entfernen:** „Remove Nightforge completely …“ löscht Engine, Windows-Umgebung und Caches; nur lokal gespeicherte Spielstände werden vorher nach `Documents/Nightforge Saves` kopiert.
  - **Design:** `Dialogs.tsx` → Tab „Storage“.
  - **Stand:** Tab „Storage“: Balken für das Laufwerk mit Nightforges Daten (Spiele / Nightforge ohne Spiele, im Hintergrund gemessen / Anderes / frei) und die Spiele auf dem Mac nach Größe mit „Im Finder zeigen“ und „Uninstall …“ (fragt im Hauptfenster). Seit `claude/ux-roadmap-next` gibt es im Abschnitt „Caches“ die Zeile „Shader caches · 150 MB · Clear“ (`ShaderCaches.swift`) mit den Ordnern aus der Recherche. Geleert wird nur der Inhalt, und nicht, während ein Spiel läuft oder startet. Danach zeigt der erste Start jedes Spiels wieder die Shader-Zeile aus 1.1. Test `tests/ShaderCachesTest/`. „Remove Nightforge Completely …“ gibt es seit `claude/ux-roadmap-next` (`CompleteRemoval.swift`):
    1. Eine Abfrage zeigt die Größen: Windows-Spiele, Engine mit Umgebung und Caches, Spielstände.
    2. Steam und Wine werden gestoppt.
    3. Die lokalen Spielstände werden nach `Dokumente/Nightforge Saves/<Datum>` kopiert. Klappt das nicht, wird nichts gelöscht.
    4. Gelöscht werden Nightforges Ordner, die Caches, die Kurzbefehle und die Einstellungen.
    5. Nightforge legt sich selbst in den Papierkorb und beendet sich.
    Test `tests/CompleteRemovalTest/` auf Test-Ordnern; in echt nie ausgeführt. Offen: „Move to …“ (braucht 4.2).
  - **Recherche** (27.10.):
    - **Shader-Caches** liegen an drei Stellen:
      1. `steamapps/shadercache/<App-ID>` jeder Windows-Bibliothek (DXVK-Zustand, Steams Vulkan-Caches).
      2. `~/Library/Caches/Nightforge/dxmt` (DXMT).
      3. Die Metal-Caches in `$(getconf DARWIN_USER_CACHE_DIR)`, jeweils mit `com.apple.metal`, `com.apple.metalfe` und `com.apple.gpuarchiver`. Sie liegen unter `io.github.lordhayne.nightforge.game` (Spiele im Spielmodus), `org.winehq.wine` und `com.codeweavers.CrossOver.wineloader` (D3DMetal, MoltenVK).
      Alles baut sich beim nächsten Start neu, der Start dauert dann länger.
    - **Nightforge komplett entfernen** erfasst:
      - `~/Library/Application Support/Nightforge`: Prefix (die Windows-Umgebung *mit den Windows-Spielen*), Components, Backups, Logs, Profile.
      - `~/Library/Caches/Nightforge`: Cover, DXMT, winetricks.
      - Die Metal-Caches von oben.
      - `~/Library/Preferences/io.github.lordhayne.nightforge.plist` und `~/Library/HTTPStorages/io.github.lordhayne.nightforge`.
      - `~/Applications/Nightforge Games` (5.3).
    - **Nicht anfassen:** Steam für Mac mit seinen Mac-Spielen und CrossOver-/Whisky-Flaschen.
    - **Lokale Spielstände** stecken in der Windows-Umgebung:
      - unter `users/crossover`: `Documents`, `Saved Games` und `AppData/{Local,LocalLow,Roaming}` ohne `Temp`, `Steam` und `Microsoft`,
      - in `Steam/userdata/<Konto>/<App-ID>`.
      Die kommen vorher nach `Documents/Nightforge Saves`. macOS fragt dabei einmal nach dem Zugriff auf „Dokumente“.

- [ ] **4.4 Download-Warteschlange & Ruhezustand** · `M` · braucht 0.3 · teilweise in PR #27
  - **Was:**
    - **Top-Bar:** Download-Ring mit Anzahl (Taste D).
    - **Panel:** Reihenfolge („Download this next“), Pause/Fortsetzen, Geschwindigkeit/Restzeit, „Only download overnight (1–7 am)“.
    - **Ruhezustand:** Während eines Downloads verhindert eine `IOPMAssertion` das Einschlafen, mit Hinweis.
    - **Fertig:** Download fertig → Toast mit „Play“ + macOS-Mitteilung (5.1). *(Toast erledigt mit 1.4.)*
  - **Stand** (teilweise): Ring in der Top-Bar (Durchschnitt aller Downloads, Anzahl in der Mitte, Taste D, per Pad erreichbar) mit Panel: je Spiel Fortschritt „42 % von 20 GB“ bzw. „Pausiert – zu wenig Platz“ und „Cancel“. Während Downloads laufen, hält `KeepAwake` eine `IOPMAssertion` gegen den Ruhezustand (der Bildschirm darf ausgehen) – das Panel sagt es. Fertig → Toast + Mitteilung (5.1). Seit `claude/ux-roadmap-next` steht unter jedem Download Geschwindigkeit und Restzeit („12 MB/s · noch 25 Min.“, `DownloadRate.swift`). Grundlage ist der Fortschritt der letzten 30 Sekunden. Test `tests/DownloadRateTest/`. Offen: Reihenfolge, Pause/Fortsetzen, „Only download overnight“ – siehe Recherche. In der App nicht gesehen (gerade lädt nichts).
  - **Wo:** Steam-Download-Warteschlange über Steam steuern (recherchieren, was von außen geht), sonst eigene Reihenfolge.
  - **Design:** `Overlays.tsx` → `DownloadsPanel`.
  - **Recherche** (27.10.): Von außen lässt sich Steams Warteschlange nicht direkt steuern. Es gibt keinen steam://-Befehl für Pause, Fortsetzen oder Reihenfolge ([Valve-Wiki](https://developer.valvesoftware.com/wiki/Steam_browser_protocol)). Was geht:
    - **Geschwindigkeit und Restzeit** aus `BytesDownloaded` / `BytesToDownload` im appmanifest, das Nightforge ohnehin alle paar Sekunden liest.
    - **Reihenfolge** über Nightforges eigene Anfragen: Nightforge schreibt das appmanifest selbst (`requestDownload`) und kann den nächsten Download deshalb erst anfragen, wenn der vorige fertig ist. „Download this next“ heißt dann: in Nightforges Liste nach vorne.
    - **Pause** nur grob. Steam hält Downloads an, solange ein Spiel läuft. Sonst bliebe nur „Steam beenden“, was alles pausiert, oder `StateFlags` 512 (UpdatePaused) im appmanifest bei gestopptem Steam – ungetestet.
    - **Nachts laden:** Steams „Nur zwischen … automatisch aktualisieren“ (`AutoUpdateWindowEnabled` in `config/config.vdf`) gilt nur für Updates. Für neue Spiele müsste Nightforge die Anfrage bis 1 Uhr zurückhalten, und das geht nur, solange Nightforge offen ist (kein Hintergrunddienst).
    - `config.vdf` enthält außerdem `DownloadsStoreRecentlyCompleted`, ein JSON mit `queue_index`, `paused` und Restzeit. Wann Steam das schreibt, ist unklar.

---

## Phase 5 – macOS-Integration & Controller

- [x] **5.1 Mitteilungen** · `S` — `UNUserNotificationCenter`: „<Spiel> is ready to play“ mit Aktion „Play“, auch wenn Nightforge geschlossen ist. Abschaltbar (General).
  - **Stand:** `MacIntegration.swift` – Mitteilung mit „Play“, wenn ein Download fertig wird und Nightforge nicht vorne ist (vorne: Toast). Klick auf die Mitteilung zeigt das Spiel, „Play“ startet es. Schalter „Notify me when downloads finish“ in General (an). macOS fragt beim ersten Mal nach der Erlaubnis. **Abweichung:** nur solange Nightforge läuft – „geschlossen“ ginge nur mit einem Hintergrunddienst, und „No background service“ steht in About. Noch nicht in der echten App angeklickt.
- [x] **5.2 Dock-Menü** · `S` — `applicationDockMenu`: die letzten 5 Spiele direkt startbar.
  - **Stand:** installierte, schon gespielte Spiele, zuletzt gespielt zuerst, ohne ausgeblendete (`MacIntegration.recentGames`, Test in `tests/NavigationTest/`). Ein Klick holt Nightforge nach vorne und startet das Spiel. Noch nicht in der echten App angeklickt.
- [ ] **5.3 Spiele als Kurzbefehle** · `M` · teilweise in PR #27
  - **Verknüpfungen:** `~/Applications/Nightforge Games/<Spiel>.app` (kleiner Starter mit Cover-Icon, der `nightforge://play/<id>` öffnet), damit Spotlight und Launchpad die Spiele finden.
  - **URL-Schema:** `nightforge://play/<id>` registrieren.
  - **Siri/Kurzbefehle:** App Intents für „Siri, play Hades II“.
  - **Detailseite:** Button „Add to Applications“.
  - **Stand** (teilweise): `nightforge://play/<App-ID>` und `nightforge://show/<App-ID>` im Info.plist registriert (`AppDelegate.application(_:open:)`; kommt ein Link vor dem ersten Scan, wartet er darauf). Ein Link startet nur installierte Spiele, sonst öffnet er die Spielseite – er lädt nie etwas herunter. Detailseite: Knopf „Add to Applications“ legt `~/Applications/Nightforge Games/<Spiel>.app` an (Skript, das den Link öffnet, Cover als Icon, ohne Dock-Symbol); danach zeigt der Knopf die App im Finder. Test `tests/GameShortcutTest/`. Offen: App Intents für Siri/Kurzbefehle; in der echten App noch nicht durchgeklickt (Bildschirmfreigabe fehlte).
- [x] **5.4 Controller-Tab** · `M` · PR #27
  - **Anzeige:** Verbundene Controller mit Akkustand (`GCController.battery`).
  - **Koppeln:** „Pair a controller“ mit Anleitung je Hersteller. Direktes Bluetooth-Koppeln ist eingeschränkt → bei Bedarf die Bluetooth-Einstellungen öffnen und dort warten, bis der Controller erscheint.
  - **Tastensymbole:** „Like my controller / Xbox / PlayStation“ (`InputRouter.PadSymbols`).
  - **Design:** `Dialogs.tsx` → Tab „Controller“; HintBar zeigt „DualSense · 80 %“.
  - **Stand:** Verbundene Controller mit Akkustand (alle 30 s und bei An-/Abmelden aktualisiert), „Pair a Controller …“ öffnet die Bluetooth-Einstellungen und zeigt die Tasten je Hersteller, „Button labels: Like my controller / Xbox / PlayStation“ (`Prefs.padGlyphs`, `PadSymbols(style:)`). Akku in der HintBar: links unten „DualSense · 80 %“ mit Akku-Symbol (unter 20 % in der Akzentfarbe, wie im Entwurf), aktualisiert bei An-/Abmelden und alle paar Sekunden, solange Nightforge vorne ist.

---

## Phase 6 – Ersteinrichtung mit Aha-Moment

- [ ] **6.1 Erster Start** · `M` · braucht 1.3 · teilweise in PR #27
  - **Was:** `SetupView` erweitern:
    - **Ablauf:** Welcome → Checkliste (vorhanden) → Steam-Login mit QR-Hinweis → „Checking your library … N of M games“.
    - **Die Enthüllung:** „**87 of your 104 games run here**“ mit Balken (great / tweaks / untested / need Windows) und den Gründen.
    - **Abschluss:** „Let's play“ + „Also add Epic Games or GOG“.
    - **Wiederholbar:** „Show the first start again“ in About.
  - **Wo:** `SetupView.swift`, `Setup.swift`.
  - **Design:** `Overlays.tsx` → `Onboarding`.
  - **Stand** (teilweise): **Die Enthüllung** – nach dem Abschluss der Ersteinrichtung und dem ersten Scan erscheint „22 of your 105 games run here“ (bei diesem Mac: 21 great, 1 tweaks, 62 untested, 21 no) mit einem Balken in den Kompatibilitätsfarben und je Stufe eine Zeile, was sie heißt; bei „Doesn't run“ getrennt Anti-Cheat (davon n auf GeForce Now) und VR. „Let's Play“ schließt. **Wiederholbar:** „Show the First Start Again“ in Settings › About. Test `tests/LibraryRevealTest/`. Offen: Welcome-Seite und „Checking your library … N of M“ im Ablauf selbst, QR-Hinweis, „Also add Epic Games or GOG“ (Phase 7).

---

## Phase 7 – Mehrere Stores (groß)

- [ ] **7.1 Store-Abstraktion** · `L` · braucht 0.2 — Protokoll `StoreProvider`: Bibliothek laden (offline-Cache zuerst), installieren, starten, Cloud-Spielstände, Sync-Status. Steam wird die erste Implementierung.
- [ ] **7.2 Epic Games ohne Epic-Launcher** · `L` · Recherche — Weg wie Heroic: [legendary](https://github.com/derrod/legendary) (GPL-3.0, passt zu Nightforges GPL-3.0). Login im eigenen Fenster, Download/Start direkt.
- [ ] **7.3 GOG ohne Galaxy** · `L` · Recherche — Weg wie Heroic (`gogdl`) bzw. GOG-API; DRM-freie Installer direkt.
- [ ] **7.4 Doppelt gekaufte Spiele zusammenführen** · `M`
  - **Anzeige:** eine Karte pro Spiel.
  - **Detailseite:** „Start through Steam | GOG“ und der Hinweis „saves stay with each store“.
  - **Matching:** über Titel-Normalisierung und IGDB-/Store-IDs.
- [ ] **7.5 Sync-Status pro Store** · `S`
  - **Fehlerfall:** Banner „Couldn't reach Epic Games – your games are from 3 days ago and still play. Try again“; nie still verschwundene Spiele.
  - **Design:** `Library.tsx` → `SyncBanner`; Tab „Stores“.

---

## Phase 8 – Gemeinsame Bewertungen (optional, nur Opt-in)

- [ ] **8.1 „Help rate games“** · `L`
  - **Opt-in:** standardmäßig aus.
  - **Gesendet wird nur:** Spiel, Chip (M1–M4), gestartet ja/nein, 👍/👎 aus 3.1 – ohne ID.
  - **Auswertung:** Ein kleiner Server sammelt; einmal pro Nacht entsteht eine öffentliche, aggregierte JSON (wie `profiles.json`), aus der 1.3 die Zeile „Tested on M2, M3 · 9 reports“ füllt.
  - **Design:** `Dialogs.tsx` → About (Schalter), `Detail.tsx` → `CompatCard`.

---

## Bewusst geparkt

- **Gatekeeper / Notarisierung** (Apple-Developer-Konto, 99 $/Jahr) – später entscheiden. Bis dahin: Installationsskript prominent, Weg „Open Anyway“ mit Screenshots erklären.
- **Soziales** (Freunde, Chat, Overlay) – bewusst nicht; höchstens Mitteilung bei Steam-Einladungen. Steam-Overlay ist unter Wine unzuverlässig.
- **Mehrere Steam-Konten / Familienfreigabe** – lieber klar „nicht unterstützt“ als halb.

---

## Woher die Punkte kommen

- **UX-Analyse des bestehenden Codes:**
  - Leiste mit allen Spielen
  - Zweiter Klick startet sofort
  - Bibliothek als Schalter
  - Starke Entsättigung nicht installierter Cover
- **Recherche zu den größten Launcher-Problemen:**
  - [PCWorld](https://www.pcworld.com/article/2627128/enough-with-the-game-launchers-its-dragging-pc-gaming-down.html): zu viele Launcher, Launcher-im-Launcher
  - [VGC](https://www.videogameschronicle.com/news/epic-games-store-exec-admits-the-launcher-sucks-says-improvements-are-on-the-way): Epic-Launcher langsam
  - [Tech Insider](https://tech-insider.org/gog-galaxy-vs-playnite-2026/): kaputte Integrationen in GOG Galaxy/Playnite
  - [GamingOnLinux](https://www.gamingonlinux.com/guides/view/what-steam-deck-steam-machine-steam-frame-and-steamos-verified-ratings-mean/): Steam Deck Verified als Vorbild
  - [TechSpot](https://www.techspot.com/article/2629-shader-compilation-explained/): Shader-Wartezeiten
  - [Neowin](https://www.neowin.net/news/whisky-a-popular-tool-for-playing-windows-games-on-mac-is-almost-dead/): Whisky eingestellt
- **GameHub (GameSir):**
  - [Android Authority](https://www.androidauthority.com/gamehub-lite-3608539/), [Tech Insider](https://tech-insider.org/winlator-vs-gamenative-vs-gamehub-2026/): Vorbild bei „läuft ohne Basteln“ und Voreinstellungen in Klartext
  - Abschreckendes Beispiel: undurchsichtige Profile, Tracking, fehlende Nennung von Open-Source-Code
- **Eigene Erfahrung/Ergänzungen:** Speicherplatz, Sitzungsabschluss, Rollback, Ersteinrichtung, Downloads/Ruhezustand, macOS-Integration, Akku, Controller, Offline, Barrierefreiheit.
