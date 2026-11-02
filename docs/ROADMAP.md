# Nightforge – UX-Roadmap

> Ziel: **ein wirklich nahtloses Erlebnis – eine App, die man gerne verwendet.**
> Diese Roadmap ist so geschrieben, dass Claude Code (CC) sie Punkt für Punkt abarbeiten kann.
> Stand: 27.10.2026 · Basis: `main@bcc2065` · Nachtarbeit in PR #27 (ein Commit je Punkt)

---

## Versionsplan ab 0.3.0 (vom Nutzer bestätigt, 1.11.2026)

Er bündelt die offenen Punkte aus `docs/TODO.md` und die sieben Recherchen vom 1.11. (`docs/recherche/`). Die Phasen
weiter unten bleiben die Fundstelle für Einzelheiten. Neue Ideen landen weiter erst in der TODO und kommen hier hinein,
wenn sie einer Version zugeordnet sind.

### 0.3.0: fertig machen und veröffentlichen
- [x] TV-Modus: Vollbild beim Anschließen (gespiegelt und erweitert), Spiel im echten Vollbild, ruhiger Lade-Vorhang,
      keine flackernde Rückkehr, das Pad holt Nightforge nach vorne. Zweig `claude/tv-fullscreen-61ab1e`.
- [x] Gespeicherte Spielauflösungen, die der TV nicht hat (Mafia II, `videoconfig.cfg`).
- [x] Mafia II startet wieder: D3D9 unter winecx nur über WineD3D, DXVK-Zeilen beenden keinen WineD3D-Start mehr.
      Zweig `claude/gog-7-3-e69c3b`.
- [x] Spielseite: Das Pad scrollt weich bis ganz unten. Zweig `claude/game-metadata-a2cee0`.
- [x] Anti-Cheat in beide Richtungen: Overwatch 2 und 42 weitere Spiele frei, fehlende Sperren (ARC Raiders, Tarkov,
      EA FC …) nachtragen. Die neuere Profilliste gewinnt. Zweig `claude/dazzling-bell-750b8e`.
- [ ] GOG-Offline-Start live prüfen. → 0.3.1 (Nutzer 1.11.: Offenes kommt mit 0.3.x)
- [x] Kleine Gatekeeper-Punkte: Texte für die Terminal-Warnung von macOS 26.4, Immutable Releases, Meldung bei
      Translocation (`docs/recherche/gatekeeper.md`).
- [ ] → 0.3.1: Wenn ein kurzer Test es bestätigt: Steam lädt Updates sofort (`AutoUpdateBehavior 2` statt 0,
      `docs/recherche/updates.md`).
- [x] **Sicherheitsprüfung vor dem Release** (Nutzer, 1.11.), lokal, weil Cloud-Sessions nur das alte `main` sehen:
  - Problemberichte dürfen keine Pfade mit Benutzernamen, Tokens oder Anmelde-Codes ins öffentliche Issue tragen.
    `wine.log` enthielt am 1.11. Epics `-AUTH_PASSWORD`-Austauschcode im Startbefehl.
  - Herkunft prüfen bei Update-ZIP, Wine-, DXVK-, DXMT- und KosmicKrisp-Downloads (Prüfsummen, Signatur).
  - Wo die Epic- und GOG-Tokens liegen, mit welchen Rechten.
  - Shell- und AppleScript-Aufrufe mit Spielnamen oder Pfaden (Injection).
  - Die in Steam geladene dylib und Steams CEF-Debug-Port.
  - Ergebnis: Funde nach Schwere, das Kritische vor dem Tag beheben.
- [x] Landingpage und README. Dann einfrieren, Ersteinrichtung testen, Live-Durchlauf, Version, Release-Notizen.
      Veröffentlichen nur mit ausdrücklichem OK. Stand 2.11.: alles gemergt, Live-Durchlauf sauber, Ersteinrichtung
      bis zum Steam-Anmeldefenster getestet (gut 3 Min., Fenster vorne, kein Zugriff aufs echte Steam), Version 0.3.0,
      Notizen in `docs/release-notes/v0.3.0.md`. Neuinstallation auf dem Mac mini (Nutzer): einwandfrei, der
      Steam-für-Mac-Code kam nach der Windows-Anmeldung von selbst.
- [ ] **Vor dem Release, beim Nutzer:** bei GitHub die Zwei-Faktor-Anmeldung mit Passkey und „Immutable Releases“
      einschalten (`docs/SICHERHEIT-0.3.md` H2, `docs/recherche/gatekeeper.md`).

### 0.3.1: Signierte Updates (Nutzer, 1.11.: „ja, so umsetzen“)
- [ ] Ed25519-Signatur (CryptoKit) über Update-ZIP, `components/manifest.json` und `profiles/profiles.json`
      (`docs/SICHERHEIT-0.3.md` H2). Der private Schlüssel liegt nur auf dem Mac des Nutzers, nicht bei GitHub.
      - Nightforge kennt zwei öffentliche Schlüssel: Haupt- und Ersatzschlüssel. Der Ersatz ist offline gesichert
        (Passwort-Manager, Papier), damit ein verlorener Schlüssel keine Neuinstallation erzwingt.
      - CI legt den Release-Entwurf an, ein Skript signiert lokal mit einem Befehl, dann veröffentlichen.
      - Die Nacht-Listen ändern sich nur noch über einen Pull Request.
      - Ohne gültige Signatur wird nichts installiert. Die gebündelte Liste gilt weiter, mit einer ruhigen Meldung.
      - Vorher den ganzen Weg „App lädt, prüft, ersetzt sich“ mit einem Test-Release durchspielen, damit kein
        Nutzer vom Update abgeschnitten wird.

### 0.4: „Wie eine Konsole“
- [ ] **Zuerst die Engine, mit voller Kraft** (Nutzer, 1.11.: „sobald das 0.3 draußen ist, geben wir richtig Gas mit
      Engine-Arbeit“). Anlass: Overwatch hängt beim Start (0 % CPU, kein Fenster). Die Ursache ist Blizzards Anti-Cheat
      unter Rosetta. Das läuft erst mit den Wine-Änderungen aus CrossOver 26.1 und macOS 26.5, unsere Engine winecx
      4.7.3 ist älter (`docs/recherche/battlenet.md`, `docs/recherche/engines.md`). Der Reihe nach:
      - **Korrektur nach der Recherche vom 1.11. abends** (`docs/recherche/engine-crossover26.md`): winecx 4.7.3
        enthält CrossOver 26.3 (der neueste veröffentlichte Quellstand) plus Wine 11.17. Der Mac hat macOS 27.0.1, also
        über 26.5. Der Overwatch-Hänger liegt deshalb nicht an einer alten Engine. Zuerst Overwatch mit DXMT statt
        D3DMetal testen und ohne msync. Im CX-26.3-Baum gibt es einen nachgewiesenen msync-Fehler: `alert_fd` wird
        beim Thread-Ende geschlossen.
      - **Nicht erst mit 0.4** (Nutzer, 2.11.): Wichtige Engine-Verbesserungen kommen in 0.3.x, sobald etwas eindeutig
        nicht läuft. Jedes Stück lässt sich für sich mergen und sagt, ob es ein App-Release braucht oder über die
        Profil- bzw. Komponentenliste kommt (`docs/TODO.md` › Engine-Arbeit).
      - **Befund 2.11.** (Stück A, Zweig `claude/engine-04-overwatch`, braucht ein App-Release): Overwatch lief nur auf
        D3DMetal, weil Nightforge es für ein reines DX12-Spiel hielt. Das ist behoben, jetzt kommt DXMT zuerst. Der
        Hänger galt außerdem nach drei Minuten als „läuft“, auch das ist behoben. Der msync-Fehler ist im Code
        bestätigt. Der Live-Test mit DXMT, ohne msync und mit dem msync-Fix steht noch aus.
      - Eigene Unix-Module über die gepinnte winecx 4.7.3, nach dem Vorbild von `gamepad.yml`:
        - `ntdll.so` mit dem msync-Fix
        - `winecoreaudio.so` mit dem SpatialMixer-Downmix aus Wine 11.21 (gegen den Hall am AV-Receiver)
        - als Release mit Quell-Asset, neue Komponente `enginefix`.
      - Den Pin erst auf winecx 4.7.4 oder 4.8.1 heben, wenn Issue #24 geklärt ist. Ein Issue bei dappermint
        (msync-Fix, 11.21-Downmix). Plan B: ein eigener Engine-Build aus dappermint/winecx, falls das Projekt stehen
        bleibt.
      - DirectX 9 über DXVK auf KosmicKrisp (Zweig `claude/quirky-clarke-81fd65`, Live-Test offen). Dazu der Plan, weil
        MoltenVK abgekündigt ist.
      - D3DMetal je nach Ergebnis der Lizenz-Recherche (Cloud, 1.11.).
      - Spiele mit DX11- und DX12-Fassung (Control, Tomb Raider, Hitman …): DX12 mit D3DMetal wählbar machen.
        Heute bietet Nightforge D3DMetal nur von selbst an, und nur für reine DX12-Spiele (`choosableLayers`,
        `onlyD3D12`). Epic startet bei Control `Control_DX11.exe`. Laut allen Mac-Quellen läuft Control aber nur über
        `Control_DX12.exe` mit D3DMetal (`docs/recherche/mac-kompatibilitaet.md`). Dafür braucht es die Wahl der
        Programmdatei pro Spiel (legendary `--override-exe`, GOG, Steam-Startoption) als Profilfeld und in den
        Optionen.
      - Die getesteten Spiele auf der neuen Engine gegenprüfen, die FPS der Landingpage neu messen, Wine 7.7 abschalten.
      - Die Codequalität (nächster Punkt) prüft parallel, nur lesend, die Engine-Dateien zuletzt umbauen.
- [ ] **Codequalität** (Idee des Nutzers, 1.11.):
  - Direkt nach dem Release, wenn `main` den aktuellen Stand hat. Cloud-Sessions sehen nur `main`.
  - Erst eine Prüfung, nur lesen: Vereinfachungen, doppelter Code, Risiken und ein Plan, wie sich die großen
    Dateien aufteilen lassen (`LibraryModel` ca. 2 900, `LibraryView` 2 300, `Engine` 2 000 Zeilen; Projektregel
    unter 500).
  - Dann der Umbau in einer ruhigen Phase, in der keine andere Session dieselben Dateien ändert.
- [ ] Spiele im Hintergrund aktuell halten: Steam über `AutoUpdateBehavior` und die Zeit, in der Steam läuft, Epic
      und GOG selbst über legendary und gogdl. Pause im Spiel, nur am Netzteil, ruhig sichtbar auf der Startseite
      (`docs/recherche/updates.md`, Phase 4.4).
- [ ] Ton am AV-Receiver: ein „Audio-Doktor“ vor dem Start, der warnt, wenn Wine „7.1 wide“ oder Stereo
      aushandelt, und eine Lösung anbietet. Vorher der DENON-Vergleich (a: wie jetzt, b: 2 Kanäle,
      c: „7.1 Rear Surround“), `docs/recherche/engines.md` › Audio.
- [ ] Spiele, die einen Fremd-Launcher brauchen, als Steam-Fassung ohne Launcher freischalten (Overwatch 2,
      Diablo IV, D2R). Danach Rockstar über Steam (nur Story), dann über Epic (`docs/recherche/launcher.md`).
- [ ] Das große Controller-Overlay (heute die kleine Fassung mit L3+R3).
- [ ] **Suchen mit dem Controller** (Nutzer, 1.11.). Heute springt Y ins Suchfeld, getippt wird noch mit der Tastatur.
  - Eigene Bildschirmtastatur im Glas-Stil, unten eingeblendet: Steuerkreuz/Stick wählt, A tippt, X löscht, Y setzt ein
    Leerzeichen, B schließt.
  - Treffer erscheinen schon beim Tippen, nach jedem Buchstaben. Dazu Vorschläge aus den Spielenamen, ↓ springt direkt
    in die Treffer. Meist reichen zwei, drei Buchstaben.
  - Ein Buchstaben-Sprung ohne Tippen: Eine Taste blendet eine A–Z-Leiste am Rand ein, die Bibliothek springt zum
    Anfangsbuchstaben, wie bei PlayStation und Xbox.
  - Spracheingabe (macOS-Diktat) erst später, wenn klar ist, ob das Mikrofon des Controllers am Mac geht.
  - Grundlage ist auch die Big-Picture-Recherche vom 1.11. (Tastaturen von Steam, Xbox, PlayStation).
- [ ] Speicherverwaltung unter Einstellungen › Speicher: neue Laufwerke erkennen und vorbereiten, angesteckte
      Laufwerke oben.
- [ ] Wine 7.7 abschalten, wenn alles auf winecx läuft (`docs/recherche/engines.md`).
- [ ] **Konsolenmodus** (Idee des Nutzers, 1.11.): ein Mac mini am Schreibtisch-Monitor oder am TV als Konsole, wie Steams
      Big Picture. Ein Schalter in den Einstellungen:
      - Nightforge startet beim Anmelden (Anmeldeobjekt über `SMAppService.mainApp`, die App selbst, kein Dienst).
      - Es öffnet im Vollbild, ohne Dock und Menüleiste.
      - Nach jedem Spiel kommt es zurück.
      - Der Controller weckt den Mac.

      Dazu die Bildschirm-Ablage pro Gerät aus dem TV-Zweig (`TVSettings`): Vollbild und Ton pro Bildschirm gemerkt. Ein
      Monitor startet beim ersten Mal im Fenster, weil man dort vielleicht nur kurz etwas testet.
      **Grundlage ist die Big-Picture-Recherche** (`docs/recherche/big-picture.md`):
      - Das smarte Menü hat zwei Ebenen. Ein kurzer Druck öffnet ein Schnellmenü als Seitenleiste: Fortsetzen, Spiel
        beenden, Lautstärke, Tonausgabe, Controller. Ein langer Druck öffnet das Ein/Aus-Menü: Ruhezustand,
        Nightforge neu starten oder beenden, Mac neu starten, ausschalten.
      - Auslöser ist sicher L3+R3. Die Home-/PS-Taste nur zusätzlich, weil macOS 26 sie für sich beansprucht.
      - Den Mac per Controller aus dem echten Ruhezustand wecken geht laut Quellen nicht. Stattdessen ein
        „Couch-Standby“: Der Mac bleibt wach, das Display schläft, eine Pad-Eingabe weckt es.
      - Möglichst wenige Freigaben von macOS (Neustart und Ausschalten brauchen Automation). Die Ad-hoc-Signatur
        verliert Freigaben nach Updates, also hängt das mit der Entscheidung zum Apple-Konto zusammen (Q1 2027).
      - Bewusst weglassen: Freunde/Chat, Store-Feeds, Videohintergründe, Umbelegung pro Spiel, Browser.

### 0.5: „Mehr Stores“
- [ ] Battle.net: die offizielle App bleibt, Nightforge liest `product.db` und startet über `--exec`. Zuerst die
      Mac-Versionen (WoW, Hearthstone, StarCraft II, Diablo III), Windows-Titel über Steam
      (`docs/recherche/battlenet.md`, Phase 7).
- [ ] Tab „Entdecken“: Angebote, Charts, Neu und Gratisspiele aus Steam, Epic und GOG, jedes Spiel mit der
      Einschätzung für diesen Mac. Gekauft wird im Store. Endpunkte vor dem Einbau live prüfen
      (`docs/recherche/entdecken.md`).
- [ ] EA app für Sims 4, Mass Effect und Dead Space. Die Sportspiele und Battlefield bleiben gesperrt (Javelin).

### Daneben, mit Fristen
- [ ] DirectX-9-Spiele flüssig (Mafia II, Left 4 Dead 2): DXVK auf KosmicKrisp mit Cache, async als Zwischenschritt.
      Zweig `claude/quirky-clarke-81fd65`.
- [ ] Plan für die Zeit nach Rosetta: Ab macOS 28 (Herbst 2027) bleibt nur ein Spiele-Subset. Natives ARM64-Wine,
      FEX und D3DMetal für arm64 beobachten (`docs/recherche/engines.md`).
- [ ] Bis etwa Q1 2027: Apple Developer Program ja oder nein. Damit gäbe es ein notarisiertes DMG und danach
      vielleicht Sparkle und Homebrew.
- [ ] Lizenz: D3DMetal darf laut Apple nur zum Entwickeln, Testen und Bewerten von Spielen genutzt werden. Klären,
      wie Nightforge damit umgeht. Den DXMT-Widerspruch zwischen Hinweisdatei und Manifest beheben.

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
  - **Stand:** `Route` (`home` / `library` / `detail(gameID, from:)`) in `Navigation.swift`, Übergänge in `LibraryModel` (`goHome`, `goLibrary`, `openDetail`, `back`, `activate`); jede Ebene merkt sich ihre Auswahl. Home-Leiste vorläufig `HomeRail.pick` (Downloads, dann installiert nach „zuletzt gespielt“, max. 12) + Kachel „All games“ – Pins und 90 Tage kommen mit 1.7. Die Bibliothek bleibt hinter einer aus ihr geöffneten Detailseite stehen (unsichtbar), daher dieselbe Scroll-Position. Suche springt in die Bibliothek. Tasten: ↩ spielt (Home) / öffnet (Bibliothek) / spielt (Detail), I Details, L Home ↔ Bibliothek, Esc zurück. Pad: A wie ↩, X Details, ☰ Home ↔ Bibliothek, Y Optionen, B zurück; ↑ von der Leiste/obersten Rasterzeile in die Knöpfe, auf der Detailseite steuert der Stick die Knöpfe. (Seit 1.11. neu geordnet, siehe `docs/ENTWURF-CONTROLLER.md`: ☰ Optionen, Y Suchen, L1/R1 Startseite/Bibliothek, auf der Startseite ↓ zu den Knöpfen und ↑ zur oberen Leiste.) Test `tests/NavigationTest/` (Leiste, Ebenen); die Übergänge mit dem echten Model gegen die echte Bibliothek durchgespielt. Nebenbei behoben: lange Hinweistexte (`fixedSize` vertikal) konnten das Fenster auf über 2500 pt Höhe ziehen (z. B. Mac-Hinweis bei 7 Days to Die) – sie haben jetzt eine Mindestbreite.

- [x] **0.2 Anbieter-neutrales Spielmodell** · `M` · `claude/epic-games-d52d35`
  - **Warum:** `Game.appID` ist eine Steam-ID. Für Epic/GOG (Phase 7) und „ein Spiel in zwei Stores = eine Karte“ braucht es eine neutrale ID – vor dem großen UI-Umbau, sonst doppelte Arbeit.
  - **Was:** `GameID { provider, id }`, `Game.providers: [Provider]` (erster = Standard zum Starten), `ArtworkStore`/Caches/Optionen auf die neue ID umstellen, Migration bestehender Einstellungen (`GameOptionsStore`, Insights) wie in `Migration.swift`.
  - **Wo:** `Library.swift`, `LibraryModel.swift`, `Artwork.swift`, `Launcher.swift` (`GameOptionsStore`), `Migration.swift`.
  - **Design:** `data.ts` (`Game`, `Provider`).
  - **Fertig wenn:** Nur Steam funktioniert wie vorher; bestehende Spieloptionen bleiben nach dem Update erhalten (Test).
  - **Stand:** `GameID { provider, id }` (`GameID.swift`, `Provider` = steam/epic) ist der Schlüssel jedes `Game` (`game.gameID`); `appID` gibt es nur noch als Steam-Sicht (0 bei anderen Stores) für Steams eigene Pfade, Manifeste, Store-Seiten und die Profilliste. Auf die neue ID umgestellt: Spieloptionen (`GameOptionsStore`), Start-Erfahrung (`LaunchHealth`, `LearnedFixes`), Shader-Merker (`LaunchPhase`), Bildratenlernen (`FramePacing`), Bewertungen (`GameRatings`), Ausblenden/Anheften (`GameMarks`, jetzt `marks.hidden`/`marks.pinned`), Cover-Cache (`steam.570_cover`) sowie Insights, Analysen, Download-Tempo und Vorbereitungen im `LibraryModel`. Gespeichert wird unter `GameID.key` („steam.570“, „epic.Fortnite“). Links: Steam-Spiele behalten `nightforge://play/570` (bestehende Apps in „Programme“ gehen weiter), andere Stores `nightforge://play/epic.Fortnite`. **Migration** `GameIDMigration` (`Migration.swift`, einmal beim Start nach `LegacyMigration`): kopiert alle Einstellungen „<präfix><App-ID>“ auf „<präfix>steam.<App-ID>“, übernimmt die Markierungen und verlinkt den Cover-Cache (harte Links, offline weiter da). Die alten Einträge bleiben stehen, damit ein älteres Nightforge (z. B. ein Build von `claude/ux-roadmap-next`) sie weiter findet – aufräumen später. Test `tests/GameIDTest/` (Schlüssel, Links, Optionen/Gelerntes/Bewertung/Markierungen/Cover nach dem Update da, nur einmal). **Abweichung:** `Game.providers` (ein Spiel in zwei Stores = eine Karte) kam mit 7.4; jeder Eintrag in `allGames` hat genau einen Store, die Karten in `cards` einen oder mehrere. `MacHealth`, `SaveTransfer` und die Mac-Versions-Wahl bleiben bei der Steam-App-ID – Mac-Versionen gibt es nur über Steam für Mac.

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
  - **Stand:** Sheet `FailedLaunchSheet` statt Alert: was versucht wurde („Tried: DXMT · DXVK · D3DMetal“), **„Try Again From the First Way“** (Primär, ↩/A – setzt `LaunchHealth` zurück und startet neu; hilft bei Steam-Update oder Rückfrage-Fenster), **„Choose Graphics by Hand …“** (öffnet die Spieloptionen; nur wo es Ebenen zur Wahl gibt) und „Report problem“. Seit 2.3 ist **„Try “Most compatible”“** der Hauptknopf (setzt die Voreinstellung und startet neu), „Try Again From the First Way“ steht darunter. **Abweichung:** „Start through <anderer Store>“ kommt mit Phase 7.

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

- [x] **2.3 Grafik-Voreinstellungen in Klartext + Profil-Herkunft** · `M` · Herkunft in PR #27, Rest Branch `claude/presets-2-3-390808`
  - **Was:** In den Spieloptionen statt Einzelschaltern zuerst vier Voreinstellungen:
    - **Automatic (recommended):** bisheriges Verhalten.
    - **Fastest / Balanced / Most compatible:** werden auf `GraphicsLayer`, Frame-Limit und MetalFX gemappt.
    - **Expertenoptionen** darunter.
    - **Kopfzeile:** „Tested by Nightforge · updated 5 days ago“ bzw. „Community fix · from umu-protonfixes“, dazu „Reset to profile“.
    - **Detailseite:** Karte „This game“ zeigt Store, Version, Grafik, HUD, Startoptionen, Engine, Offline-Status sowie „Your own settings … Back to the profile“.
  - **Wo:** `SettingsViews.swift` (`GameOptionsSheet`), `Launcher.swift` (`GameOptions`, `GraphicsLayer`), `Profiles.swift`.
  - **Entschieden (27.10.):** „Balanced“ = die heutige Automatik (MetalFX + gleichmäßige Bildrate passend zum Display, 60 FPS auf 120 Hz); „Fastest“ = MetalFX ohne FPS-Grenze; „Most compatible“ = der verträglichste Grafikweg ohne MetalFX, 60 FPS.
  - **Design:** `Dialogs.tsx` → `GameOptionsDialog`; `Detail.tsx` → `OptionsSummary`; `data.ts` → `PRESETS`.
  - **Stand:**
    - **Voreinstellungen** (`GraphicsPreset` in `Launcher.swift`, pro Spiel in `GameOptions.preset`): Automatic (wie bisher: Profil, gelernte Bildrate aus `FramePacing`, Grafik-Leiter aus `LaunchHealth`), Balanced (MetalFX + gleichmäßige Bildrate, 60 FPS auf 120 Hz, 72 auf 144 Hz; ein FPS-Limit aus dem Profil gilt), Fastest (MetalFX, kein Limit), Most compatible (kein MetalFX, 60 FPS, sicherster Grafikweg zuerst), dazu Custom = die Expertenoptionen. Schließt ein Profil MetalFX aus, bleibt es auch bei Balanced und Fastest aus.
    - **Beim Start** setzt `GameOptions.resolved` FPS-Limit und MetalFX der Voreinstellung fest, `FramePacing` lernt bei Balanced, Fastest und Most compatible also nicht dagegen an. Ein Start mit festem Limit (Voreinstellung, von Hand, Akku) überschreibt das für Automatic Gelernte nicht mehr. `LaunchHealth.ladder` ordnet für Most compatible die Wege um: zuerst die Ebene, mit der ein Nightforge-Profil getestet ist (Palworld DXMT, The Last Caretaker D3DMetal), dann WineD3D, DXVK, DXMT, D3DMetal. Startet ein Weg nicht, nimmt Nightforge den nächsten, wie bei Automatic. Der Problembericht nennt die Voreinstellung.
    - **Alte Optionen** ohne `preset` lesen sich als Automatic, oder als Custom, wo Grafikweg, FPS-Limit oder MetalFX von Hand gesetzt waren. HUD, Startparameter, HDR und Version bleiben. Test `tests/GraphicsPresetTest/`.
    - **Spieloptionen im Glas-Look:** Die System-Picker sind Glas-Segmente. Oben vier Karten (2 × 2, „Automatic · recommended“) mit Klartext, darunter einklappbare „Expert options“ (Grafikweg, FPS-Limit, MetalFX, HDR). Sie zeigen die Werte der gewählten Voreinstellung; ändert man einen, steht sie auf „Custom“ (aus Most compatible bleibt dabei dessen Grafikweg). Ist das Fenster zu niedrig, scrollt der Mittelteil und folgt dem Pad-Fokus.
    - **Kopfzeile:** „Tested by Nightforge on M5 · 2 days ago“ bzw. „Community fix · from umu-protonfixes“; bei eigenen Einstellungen „Your own settings. Back to the Profile“ (ohne Profil „Back to Automatic“), wirksam mit „Save“.
    - **Fehlstart:** `FailedLaunchSheet` hat als Hauptknopf „Try “Most compatible”“ (↩/A). Er setzt die Voreinstellung, setzt `LaunchHealth` zurück und startet neu. „Try Again From the First Way“ steht darunter. Für Spiele, die schon auf Most compatible stehen, bleibt es wie vorher.
    - **Welcome back:** Nach 👎 mit „Crashed“, „Graphics glitches“ oder „Stutters“ bietet das Sheet „Use “Most compatible” next time“ an. Das speichert Bewertung und Voreinstellung, die Bestätigung steht im Sheet.
    - **Spielseite:** Karte „This game“ (`ThisGameCard.swift`) rechts neben dem Titel: Store, Version, Grafik (Voreinstellung · Ebene, die gerade drankommt), Performance HUD, Startparameter, Engine, Offline. Darunter die Herkunft des Profils oder „Your own settings, on top of the profile. Back to the Profile“. „Change …“ öffnet die Optionen. Offline und eine zurückgehaltene Engine stehen dafür nicht mehr bei den Kennzahlen unter dem Titel.
    - **Abweichungen:**
      - „updated 5 days ago“: Die Profilliste hat kein Datum pro Spiel. Nightforges eigene Profile tragen ihr Testdatum in der Notiz („Tested 2026-10-26 on M5: …“), das zeigt die Kopfzeile („· 2 days ago“). Bei Community-Fixes steht kein Datum: bekannt wäre nur das `generated` der ganzen Liste, und das sagt über das einzelne Spiel nichts.
      - Most compatible ist kein einzelner fester Weg, sondern die Grafik-Leiter in sicherer Reihenfolge. Wechselt man zwischen Most compatible und den anderen Voreinstellungen, beginnt die Leiter von vorn, und der erste Start wird wieder beobachtet.
      - HDR steht bei den Expertenoptionen, gehört aber zu keiner Voreinstellung und macht sie deshalb nicht zu Custom.
      - Balanced folgt nicht dem globalen „Sharp & smooth“, es ist dessen feste Fassung. Automatic folgt ihm weiter.
    - **Geprüft:** Build ohne Compiler-Warnungen, alle Testreihen grün. Spieloptionen, Karte und Fehlstart-Sheet offscreen gerendert (echte Views in einem `NSHostingView`, Deutsch und Englisch): Die Voreinstellungs-Karten sind gleich hoch, die alten OxyRail-Optionen erscheinen als „Custom“ mit DXMT und aufgeklappten Expertenoptionen, der Mittelteil scrollt bei wenig Höhe. Die Karte „This game“ sagt mit OxyRails echtem Profil „Von Nightforge getestet auf M5 · vor 4 Tagen“; auf „Most compatible“ fehlt im Fehlstart-Sheet dessen Knopf, wie gewollt. **Nicht in der echten App angesehen:** Der Zugriff per Bildschirmsteuerung wurde am 28.10. abgelehnt. Was dort zu prüfen ist, steht in `docs/TODO.md`.

- [x] **2.4 „Bereit für offline“** · `M` · Recherche · PR #27
  - **Was:** Pro Spiel: „Ready“ oder „Start online once“. Steams Offline-Modus muss vorher online aktiviert worden sein – herausfinden, woran man das erkennt (z. B. `loginusers.vdf`, letzter erfolgreicher Online-Start).
  - **Design:** `Detail.tsx` → Zeile „Offline“.
  - **Stand:** Recherche – Steams Offline-Modus braucht ein gemerktes Konto (`config/loginusers.vdf`: `RememberPassword` 1; auf diesem Mac gesetzt). Pro installiertem Spiel auf der Detailseite „Offline: Ready / Start online once / Update first / Needs internet / Not yet“ mit Erklärung beim Darüberfahren (`OfflineReadiness.swift`): kein gemerktes Konto → „Not yet“; Steam nennt keinen Einzelspielermodus oder eigener Launcher mit Anmeldung → „Needs internet“; Update wartet → „Update first“; noch nie gestartet → „Start online once“; sonst „Ready“. Heuristik – was ein Spiel intern online prüft (DRM), sieht Nightforge nicht. Test `tests/OfflineReadinessTest/`.

- [x] **2.5 Barrierefreiheit** · `S` · teilweise in PR #27, „Larger text“ Branch `claude/larger-text-2-5-2d1360`
  - **Was:** „Reduce motion“ (folgt `NSWorkspace.accessibilityDisplayShouldReduceMotion`, abschaltbar): kein Lampen-Flackern, kein Cover-Zoom, nur Überblenden. „Larger text“ (eine Stufe größer). VoiceOver-Labels für alle Icon-Buttons und Abzeichen.
  - **Design:** `Dialogs.tsx` → Tab „General › Accessibility“; `index.css` (`.ns-reduce`).
  - **Stand:** „Reduce motion“ in General › Accessibility – folgt macOS, bis man es umstellt (`Prefs.reduceMotion`, eigener Umgebungswert `\.reduceMotion`, weil SwiftUIs eigener nicht überschreibbar ist); schaltet Cover-Zoom, Rail-/Raster-Scrollen und Toast-Gleiten ab. VoiceOver-Labels: alle neuen Icon-Knöpfe, Abzeichen (Kompatibilität, Pin) und Kacheln haben Namen.
    - **Larger text** (31.10.): Schalter „Größere Schrift“ unter General › Bedienungshilfen, aus, bis man ihn einschaltet (`Prefs.Keys.largerText`, Umgebungswert `\.textScale`). Kein Folgen von macOS: Die Textgröße pro App unter Bedienungshilfen › Anzeige gilt nur für Apples eigene Apps (`com.apple.universalaccess` › `FontSizeCategory` nennt nur deren Bundle-IDs), eine API für andere Apps gibt es nicht (Apple-Entwicklerforum, macOS 26).
    - **Eine Stelle für Schrift:** Jede Größe läuft über `.font(size:weight:design:)` oder `.displayFont(_:)` (Accessibility.swift, auch für `Theme.display`). Die Stufe ist +18 %; Titel ab 20 pt wachsen um die 3,6 pt von 20 pt, wie Dynamic Type auf iOS, sonst sprengen die großen Titel Bühne und Dialoge. Text ohne eigene Größe (Zeilen in den Einstellungen) bekommt 13 pt wie macOS' Body, `.caption` ist jetzt `.font(size: 10)` – ausgeschaltet pixelgleich wie vorher (bis auf die Silbentrennung eines deutschen Fußtexts in Stores). Symbole, die allein stehen (runde Knöpfe, Abzeichen auf Covern, Kacheln, Pad-Zeichen, Zahl im Download-Ring), behalten ihre Größe (`scales: false`, `Font.drawing`); Symbole neben Text wachsen mit. Suchfeld der Bibliothek und Download-Panel werden mit der Schrift breiter.
    - **Layouts:** Die Knöpfe unter Startseite und Spielseite stehen in einer `FlowRow`: Die runden gehen in eine neue Zeile, statt „Spielen“ zusammenzudrücken. Das war bei 980 pt Breite schon ohne größere Schrift kaputt („▶ |“ auf der Spielseite, „Downloadin / g … 42 %“ auf der Startseite). Das Logo der Spielseite gibt bei wenig Höhe nach (bis 80 pt, wie auf der Startseite). Der erste Start scrollt, wenn eine Seite höher als das Fenster ist (Anmeldung mit QR-Hinweis war bei 640 pt schon vorher zu hoch); der Pad-Fokus holt die Knöpfe am Ende ins Bild.
    - **Kleines Fenster** (31.10., nach dem Live-Test, gilt für beide Schriftgrößen): Einstellungen und Glas-Dialoge werden nie höher als das Fenster weniger 40 pt (`DialogRoom`, Glass.swift). Bei 980 × 640 sind das 568 pt statt bis zu 771. Kopf und Tabs bleiben stehen, das Formular des Tabs scrollt; im Platz- und im „Nicht gestartet“-Dialog scrollt die Mitte (`DialogScroll`), die Knöpfe bleiben unten. Der Pad-Fokus holt den markierten Knopf dort ins Bild (`PadFocus.reveal`). Speicher und Über haben nur noch eine Wunschhöhe von 480 pt. Die Bibliothek bleibt ganz oben, wenn das gewählte Spiel in der ersten Reihe steht (vorher klebte „Installiert“ bei 640 pt Höhe an den Filtern).
    - **Regel für neue Views:** keine feste `.system(size:)`, kein `Theme.display(n)`, keine Textstile – `tests/TextScaleTest/` schlägt sonst an.
    - **Geprüft:** offscreen gerendert (echte Views, Deutsch und Englisch, aus und an, 1512 × 900 und 980 × 640): Startseite, Bibliothek, Spielseite, Downloads, Toast, erster Start (Willkommen, Checkliste mit Seitenleiste, Anmeldung, Fehler, Prüfung, Ergebnis), alle Einstellungs-Tabs, Spieloptionen und die Glas-Dialoge. Nicht in der echten App angesehen – siehe docs/TODO.md.

- [x] **2.6 Nur eigene Spiele – Demo oder Store für den Rest** · `M` · Recherche · Branch `claude/steam-ownership-3b3bdd`
  - **Warum:** Nightforge zeigte 105 Spiele als „in deiner Bibliothek“, dem Konto gehören 100. Der Download eines fremden Spiels (The Last Caretaker) hing ewig bei „Download wird vorbereitet …“.
  - **Recherche** (27.10.):
    - `appcache/packageinfo.vdf` ist ein Cache aller Pakete, nach denen der Client gefragt hat. Darin stehen auch abgelaufene Gratis-Wochenenden (Lizenz mit Flag „Expired“) und Pakete von Store-Seiten, die man in Steam geöffnet hat (The Last Caretaker: Kaufpaket 642779, `billingtype` 10). Besitz folgt daraus nicht.
    - Die echte Lizenzliste liegt pro Konto in `userdata/<Konto-ID>/config/licensecache` (nicht unter `config/`). Inhalt ist die `CMsgClientLicenseList` (Protobuf), die die Steam-Server bei der Anmeldung schicken, dahinter ihre CRC32. Jedes Byte ist per XOR mit `RandomInt(32, 126)` aus Valves `CUniformRandomStream` verknüpft (vstdlib, Numerical Recipes' `ran1`), Startwert ist die Konto-ID (der Ordnername). Die CRC32 bestätigt, dass richtig entschlüsselt wurde. Windows-Steam und Steam für Mac schreiben dasselbe Format. Eine öffentliche Beschreibung habe ich nicht gefunden; das Format ist durch Abgleich mit den echten Dateien ermittelt.
    - Pro Lizenz stehen u. a. `package_id` (Feld 1), `flags` (7, ELicenseFlags: 4 ausstehend, 8 abgelaufen, 16/32 storniert/erstattet, 1024 Betrugssperre), Kaufland (8) und `owner_id` (12) darin. Nightforge liest nur Paket und Flags. Nichts verlässt den Mac, Anmeldedaten werden nicht angefasst (die liegen woanders).
    - Andere Werkzeuge: Playnite, Lutris und GOG Galaxy fragen meines Wissens die Steam-Web-API (API-Key oder öffentliches Profil). Steam Achievement Manager fragt den laufenden Client über `steamclient` (`BIsSubscribedApp`). Beides passt nicht zu „offline, ohne Key, ohne fremden Code“.
    - Ergebnis auf diesem Mac: **100 von 105 besessen**. Nicht besessen sind Conan Exiles Enhanced, FOR HONOR, The Culling und Rainbow Six Siege (abgelaufene Gratis-Wochenenden) sowie The Last Caretaker. Von The Last Caretaker liegt nur die Demo 3916150 im Konto, deren kostenlose Lizenz seit 27.10. 20:29 besteht.
    - Demos: `appinfo.vdf` kennt sie (`common/type` „Demo“, `common/parent` = das Spiel). Jede Demo braucht eine eigene kostenlose Lizenz (Paket mit `billingtype` 12, FreeOnDemand). Ganz ohne Fenster lässt sie sich nicht holen. `steam://install/<Demo>` öffnet Steams Installationsdialog und fügt die Lizenz beim Bestätigen hinzu. Die Store-Webseite (`addfreelicense`) bräuchte Login-Cookies, die Steam-Konsole (`app_license_request`) ein sichtbares Fenster. Darum gibt es einen einmaligen, vorher erklärten Klick.
  - **Stand:** `SteamCatalog` liest die Lizenzliste des zuletzt angemeldeten Kontos. Abgelaufene, erstattete und ausstehende Lizenzen zählen nicht. Ohne lesbare Liste zählt alles aus `packageinfo.vdf`, wie bisher.
    - **Nicht besessene Spiele**, die Steam kennt, erscheinen als ihre Demo: Cover mit „DEMO“, „Demo laden“ bzw. „Demo spielen“ auf Spielseite und Startseite, dazu ein Hinweis und „Vollversion im Steam-Store“. Ohne Demo erscheinen sie als Store-Eintrag mit Preis. Beides zählt nicht zur Anzahl der Spiele.
    - **Demo ohne Lizenz:** Ein Glas-Dialog erklärt den Klick im Steam-Fenster und öffnet dann `steam://install/<Demo>`.
    - **Hängende Downloads:** Ein angefragter Download, den Steam nicht holt, wird nach einer Minute ohne Änderung zum Store-Eintrag mit Hinweis und Toast. „Download abbrechen“ nimmt die Anfrage zurück. Ohne Lizenzliste entscheidet `LastOwner` "0", solange Steam angemeldet ist und nichts anderes lädt.
    - Dateien: `SteamCatalog.swift`, `Library.swift` (`demoOf`, `downloadRefused`), `Demos.swift`. Test `tests/SteamOwnershipTest/`; `tests/CatalogProbe/run.sh <Steam-Ordner>` zeigt die Liste eines echten Steams.
    - **In der echten App geprüft** (27.10., 22:28–22:47): Die Bibliothek zeigt 100 Spiele, „Im Steam-Store 4“ am Ende (FOR HONOR mit Spielzeit 13 Min. und 29,99 €). The Last Caretaker Demo erscheint mit „DEMO“, Hinweis und „Demo laden“. Der Download lief ohne Steam-Fenster an (12,6 GB, ~28 MB/s, fertig nach 11 Min.). „Demo spielen“ startete sie, danach kam „Willkommen zurück“. Die alte Anfrage für The Last Caretaker nachgestellt: Nach einer Minute wurde aus „Download wird vorbereitet …“ ein Store-Eintrag mit Hinweis, „Download abbrechen“ nahm die Anfrage zurück, und Steam startete neu.

---

## Phase 3 – Der Kreis ums Spielen

- [x] **3.1 Sitzungsabschluss („Welcome back“)** · `M` · PR #27, Glas-Look in `claude/ux-roadmap-next` · **Entschieden (27.10.):** nach jeder Sitzung ab einer Minute
  - **Warum:** Wir denken bisher nur bis zum Start. Am Ende will man wissen: Ist der Spielstand sicher, kann ich zuklappen?
  - **Was:** Wenn das Spiel endet (Nightforge kommt ja schon nach vorne), Sheet mit:
    - Spielzeit dieser Sitzung und gesamt
    - Spielstand-Status: „Uploading to Steam Cloud …“ → „Save is in Steam Cloud. You can close your Mac.“ (bzw. „Saved on this Mac only“)
    - „How did it run?“ 👍/👎 (als Icons) mit Gründen (Stutters, Crashed, Low frame rate …); bei Abstürzen/Ruckeln das Angebot „Use ‚Most compatible‘ next time“
    - Buttons „Play again“ / „Done“
  - **Wo:** `LibraryModel` (Erkennung Spielende), Steam-Cloud-Status aus dem Steam-Log/`remotecache.vdf` (recherchieren), `SaveTransfer.swift` (Speicherorte).
  - **Design:** `Overlays.tsx` → `SessionSummary`.
  - **Fertig wenn:** Erscheint nach jedem Spielende; die Bewertung wird lokal gespeichert und fließt in 1.3 (eigene Erfahrung schlägt Profil).
  - **Stand** (teilweise): `SessionSummary.swift` – nach jedem von Nightforge gestarteten Spiel, das mindestens eine Minute lief, Sheet „Welcome back“: Spielzeit diesmal und insgesamt (Steams Zählung, ohne Doppelzählung), „How did it run?“ 👍/👎 mit Gründen (Stutters, Crashed, Low frame rate, Graphics glitches, Controller, Sound), „Play Again“ / „Done“. Bewertung lokal (`GameRatings`, UserDefaults) und in `Compatibility.rate` vor dem Profil (👍 → great, 👎 → tweaks mit „You said: …“; Anti-Cheat/VR bleiben „no“). Test in `tests/CompatibilityTest/`. Spielstand-Zeile: `CloudSaves.swift` liest `userdata/<Konto>/<App-ID>/remotecache.vdf` (pro Cloud-Datei `syncstate`, 1 = im Einklang); „Your save is in the Steam Cloud. You can close your Mac.“ erst, wenn Steam die Datei nach dem Spielende neu geschrieben hat und alle Dateien auf 1 stehen – vorher „Steam is syncing …“ (alle 2 s geprüft), nach einer Minute ohne Bestätigung „Steam syncs your save in the background.“, ohne Datei „No Steam Cloud for this game – its saves are on this Mac.“ Test `tests/CloudSavesTest/`. Die Bedeutung der anderen `syncstate`-Werte ist nicht dokumentiert – deshalb nur „1“ als sicher. Seit 2.3: nach 👎 mit „Crashed“, „Graphics glitches“ oder „Stutters“ „Use “Most compatible” next time“.

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

- [x] **3.3 Automatisches Zurückrollen der Engine** · `L` · braucht 1.1 · lokal in `claude/engine-rollback-02a61e`
  - **Warum:** macOS-/Wine-Updates machen Spiele kaputt, die gestern liefen (siehe Whisky). Selbst-Heilung ist ein echtes Alleinstellungsmerkmal.
  - **Was:**
    - Pro Spiel die letzte funktionierende Kombination aus Engine und Grafikschicht merken.
    - Die vorige Engine-Version bleibt installiert (`ComponentStore`).
    - Stürzt ein Spiel nach einem Update beim Start ab: automatisch mit der alten Version starten. Phase „Trying last week's engine …“, danach Hinweis „Runs with last week's engine … Try the newest now“.
    - Nach dem nächsten Engine-Update wird automatisch wieder die neue versucht.
  - **Wo:** `Components.swift` (`ComponentStore`, Versionen), `LaunchHealth.swift`, `Engine.swift`.
  - **Design:** `Parts.tsx` (`rollback`-Phase), `Detail.tsx` (Engine-Hinweis, Zeile „Engine … (held back)“).
  - **Fertig wenn:** Ein simuliertes kaputtes Engine-Update führt zu einem erfolgreichen Start mit der alten Version, ohne dass der Nutzer etwas tun muss.
  - **Stand:**
    - **Build:** `EngineRollback.swift`. Ein Engine-Build ist die Engine samt allen Grafik-Builds (DXMT-Paket, D3DMetal, MoltenVK, Gamepad, DXVK) – eine neue Version von einem davon ist ein Engine-Update. `Components/engine-history.json` merkt sich den aktuellen Build und pro Spiel Build und Grafikweg des letzten guten Starts (beim ersten Mal aus den bestätigten Wegen von `LaunchHealth`).
    - **Vorige Engine behalten:** Bevor `ensureEngine` etwas an der Engine ändert, kopiert es den bisherigen Build nach `Components/.held/` – wenn ein Spiel zuletzt darauf gut lief. Kopiert werden Engine-, Grafik- und DXVK-Ordner als APFS-Klon (0,1 s für 1,4 GB; Platz kostet nur, was sich danach ändert). Die Kopie geht, sobald kein Spiel sie mehr als letzten guten Build hat. Höchstens zwei Kopien; nach 30 Tagen weg, außer ein Spiel ist darauf festgelegt; nie, solange etwas daraus läuft.
    - **Rückfall:** Nach jedem neuen Build oder Weg wird ein Spiel einmal 30 s beobachtet (auch mit selbst gewählter Grafik). Endet es sofort und lief es mit demselben Weg auf dem Build davor, wird es auf die Kopie festgelegt und gleich damit neu gestartet. Steam zieht dafür auf die alte Engine um, der Prefix bekommt deren DXMT/DXVK-DLLs (`preparePrefix`, `Engine.engineForStart`). Die Grafik-Leiter bleibt, wo sie war. Läuft es auch dort nicht, fällt die Festlegung, und die bisherigen Wege folgen (Runtimes, nächste Grafikschicht).
    - **Anzeige:** Spielknopf „Versucht die vorige Engine …“ mit Erklärzeile; bei späteren Starts, wenn Steam erst umziehen muss, „Startet mit der vorigen Engine …“. Spielseite: „Engine 4.7.3 (zurückgehalten)“ und der Hinweis „Läuft mit der vorigen Engine vom 27. Okt. – die neueste hat es abstürzen lassen …“ mit „Jetzt die neueste probieren“ (Toast wie im Entwurf; stürzt es wieder ab, geht es von selbst zurück). Haben zwei Builds dieselbe Engine-Version, unterscheidet sie das Datum.
    - **Nächstes Update:** Alle Festlegungen fallen, die neue Engine wird probiert.
    - **Abweichung:** „vorige Engine“ statt „last week's engine“ – Updates kommen nicht im Wochentakt.
    - **Tests:** `tests/EngineRollbackTest/` (Fake-Engines und -Ordner, eigenes leeres Home).
    - **In der echten App** (27.10., geklontes Home, deine Engine unverändert): Engine 4.7.4 mit eingebautem Absturz → Palworld nach 3 s weg → von selbst mit 4.7.3 neu gestartet, gespielt, Spielstand in der Steam Cloud.
    - **Offen:** siehe `docs/TODO.md` („Engine-Rückfall“).

- [x] **3.4 Akku-Modus** · `S` · PR #27 (standardmäßig aus)
  - **Was:** Ohne Netzteil (IOKit `IOPSCopyPowerSourcesInfo`): Bildrate auf 30 FPS begrenzen, Hinweis „On battery: capped at 30 FPS – about 1 h 40 min of play“, Akkustand in der Top-Bar. Abschaltbar in General. Grundlage für die Begrenzung: `FramePacing.swift`.
  - **Design:** `Parts.tsx` (`playHint` mit `onBattery`), Top-Bar-Akku.
  - **Stand:** `PowerSource.swift` (IOKit: Akku/Netzteil, Ladestand; alle paar Sekunden im bestehenden Lauf-Check). Schalter „Save battery when unplugged“ in General – **standardmäßig aus** (Abweichung, bitte entscheiden: du magst 60 FPS fest, deshalb nicht ungefragt eingeschaltet). Ist er an und der Mac im Akkubetrieb, startet ein Spiel mit höchstens 30 FPS (auch ohne eigene Grenze), und aus so einer Sitzung lernt `FramePacing` nichts. Top-Bar zeigt im Akkubetrieb den Ladestand (unter 20 % in der Akzentfarbe), die Spielseite die Zeile „On battery: games are capped at 30 FPS …“. Ohne Restzeit-Schätzung – macOS' Schätzung gilt für die aktuelle Last, nicht fürs Spielen. Test in `tests/LaunchHealthTest/`.

---

- [x] **3.5 Schwaches Netzteil erkennen** · `S` · Idee des Nutzers am 27.10. · lokal in `claude/ux-roadmap-next`
  - **Warum:** Mit einem zu schwachen Netzteil steht der Mac auf „lädt“, verliert beim Spielen aber trotzdem Akku –
    der Spielspaß ist schnell vorbei, ohne dass man merkt, warum.
  - **Was:** Am Netzteil dezent zeigen, wenn es nicht reicht: in der Akku-Pille oben ein Bernstein-Blitz mit „18 W“
    (Tooltip mit Erklärung), auf Startseite/Spielseite eine Hinweiszeile wie bei „Akku sparen“.
  - **Recherche (27.10., echter Fall):** `IOPSCopyExternalPowerAdapterDetails()` liefert die Watt (`Watts` = 18, „pd
    charger“, 9 V/1,98 A); `IOPSCopyPowerSourcesInfo` den Strom des Akkus (`Current`, mA). Am 18-W-Netzteil stand
    „charging“, der Strom war aber −1236 mA: Der Akku entlud sich. `ChargerData.SlowChargingReason` blieb 0, taugt
    also nicht. Regel: am Netzteil **und** (Akku entlädt sich über mehrere Messungen **oder** unter 30 W). Beim
    Ladelimit (80 %) fließt kein Strom – das ist kein Fehler.
  - **Wo:** `PowerSource.swift` (Watt, Entladen), `LibraryView.swift` (Akku-Pille, Hinweiszeilen).
  - **Fertig wenn:** Mit dem 18-W-Netzteil erscheint der Hinweis, mit dem passenden Netzteil oder am Ladelimit nicht (Test mit Beispielwerten).
  - **Stand:**
    - **Messen:** `PowerSource.reading()` liest jetzt auch die Watt des Netzteils (`adapterWatts`) und den Strom des Akkus. Der Strom bleibt außerhalb von `PowerSource`, sonst würde die Oberfläche bei jeder Messung neu zeichnen.
    - **Bewerten:** `ChargerCheck` gilt nur am Netzteil und nur bei einem Mac mit Akku.
      - Unter 30 W warnt er sofort, auch am Ladelimit: Für Spiele reicht so ein Netzteil nie.
      - Sonst warnt er, wenn sich der Akku drei Messungen in Folge um mehr als 100 mA entlädt, und hört nach drei guten Messungen wieder auf (kein Flackern). Die Messungen kommen im bestehenden Lauf-Check alle 3–10 s.
      - Ein Rinnsal um 0 mA am Ladelimit zählt nicht.
    - **Anzeigen:**
      - Oben in der Top-Bar steht eine Glas-Pille mit Bernstein-Blitz und „18 W“, ohne bekannte Watt der Ladestand. Den Tooltip liest VoiceOver vor.
      - Auf Startseite und Spielseite steht die Zeile „Das Netzteil liefert nur 18 W – zu wenig für Spiele: Beim Spielen entlädt sich der Akku. Ein stärkeres hilft.“ Ohne bekannte Watt heißt sie „Der Akku entlädt sich, obwohl der Mac am Netzteil hängt …“.
    - **Test:** Fälle in `tests/LaunchHealthTest/` mit den Werten des echten Falls (18 W, −1236 mA), dazu 96 W am Ladelimit, kurze Spitzen, ohne Watt, Akkubetrieb und Mac ohne Akku.
    - Am 28.10. mit dem 18-W-Netzteil gemessen: 18 W, −356 mA bei „charging“.

## Phase 4 – Speicherplatz & Downloads

- [x] **4.1 Platz prüfen vor dem Download** · `M` · PR #27
  - **Was:** Ist zu wenig Platz frei: Dialog „<Spiel> needs 49.5 GB – 18.5 GB short“ mit (a) „Install on <externe SSD>“ und (b) „Make room“. Vorgeschlagen werden lange nicht gespielte Spiele (Größe, zuletzt gespielt, „saves stay in the cloud“), vorausgewählt bis es reicht → „Uninstall n & download“.
  - **Design:** `Overlays.tsx` → `SpaceDialog`.
  - **Fertig wenn:** Kein Download startet, der mangels Platz abbrechen würde.
  - **Stand:** `SpaceCheck.swift` – vor jedem Download (Windows und Mac) Vergleich Downloadgröße + 1 GB Reserve mit dem freien Platz des Ziel-Volumes (nächster existierender Ordner). Reicht es nicht: Sheet „<Spiel> needs up to …“ mit fehlender Menge und bis zu 8 installierten Spielen auf demselben Volume, die seit 30 Tagen nicht (oder nie) gespielt wurden, größte zuerst, vorausgewählt bis es reicht → „Uninstall n & Download“ deinstalliert nacheinander und lädt dann (prüft vorher noch einmal). Gibt es keine Kandidaten, sagt das Sheet das. „Install on <externe SSD>“ kommt mit 4.2. Test `tests/SpaceCheckTest/`.

- [ ] **4.2 Spiele auf externen Laufwerken** · `L` · Recherche · teilweise in `claude/ux-roadmap-next`, Rest gebaut in `claude/external-drive-4-2-710e3d` (Live-Test offen)
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
  - **Stand** (`claude/external-drive-4-2-710e3d`, 29.10., mit dem USB-Stick „Spiele test“ geprüft, noch nicht mit echtem Steam):
    - **Bibliothek auf dem Laufwerk** (`ExternalDrives.swift`): Nightforge legt `Nightforge Games` auf dem Laufwerk an – darin `steamapps/` für Nightforges Windows-Steam, `Steam for Mac/steamapps/` für Steam für Mac und `Epic Games/` für legendary, jeder Store für sich, damit keine Steam die Spiele der anderen für ihre hält.
      - Eingetragen wird sie bei gestopptem Steam in beide `libraryfolders.vdf` (`config/` und `steamapps/`), als `Z:\Volumes\<Name>\Nightforge Games` bzw. als Mac-Pfad, mit `contentid` und Steams Marke `libraryfolder.vdf` im Ordner. Liegen dort schon Spiele (frühere Installation), kommen sie mit in die `apps`-Liste.
      - Die Liste wird in ihrer Reihenfolge und Schreibweise gelesen und zurückgeschrieben (`VDF.nodes`/`VDF.text`). Ist sie nicht lesbar, bleibt sie unangetastet.
    - **Dateisystem** (`DriveCheck`, über `statfs`): APFS und Mac OS Extended gehen. exFAT geht mit ruhigem Hinweis (keine Mac-Rechte und Verknüpfungen). FAT32 wird abgelehnt (4 GB pro Datei), ebenso nur lesbare Laufwerke (NTFS). Time-Machine-Volumes und Netzlaufwerke tauchen nicht auf.
    - **„Install on <Laufwerk>“** (`DriveViews.swift`): Im Platz-Sheet stehen die angeschlossenen Laufwerke mit freiem Platz und Format („Install on Spiele test“). Hat der Mac genug Platz und hängt ein Laufwerk mit `Nightforge Games` daran, fragt Nightforge „Wohin soll <Spiel>?“ (Mac oder Laufwerk, Return = Mac) – wie Steam bei mehreren Bibliotheken. Ohne Laufwerk sagt das Platz-Sheet, dass eines auch geht. Keine neue Einstellung.
      - Windows: Bibliothek eintragen (Steam dafür gestoppt; beim ersten Mal also nicht während ein Spiel läuft), dann wie sonst `requestDownload` in die Bibliothek auf dem Laufwerk und Neustart.
      - Mac: Steam für Mac wird beendet, die Bibliothek eingetragen und Steam wieder gestartet wie vorher.
      - Epic: `legendary install --base-path <Laufwerk>/Nightforge Games/Epic Games`, das Ziel bleibt pro Spiel in `Epic/destinations.json` (Warteschlange über Neustarts).
    - **Nicht angeschlossen:** Verschobene Spiele stehen in der `apps`-Liste der Laufwerks-Bibliothek, also greift „Connect <Laufwerk> to Play“. Epic-Spiele auf einem fehlenden Laufwerk zeigen das jetzt auch. Solche Spiele bleiben auf der Startseite und unter „Installiert“ (`Game.shelfState`), mit Laufwerks-Zeichen statt Download-Pfeil auf dem Cover. Beim Ein- und Ausstecken liest Nightforge die Bibliothek neu ein. Liegen auf dem eingesteckten Laufwerk Spiele der Windows-Steam, startet Nightforge diese neu, sobald nichts läuft.
    - Test `tests/ExternalDriveTest/`: vdf lesen/schreiben, Pfade, Bibliothek anlegen und wieder eintragen, Dateisysteme. Mit `NIGHTFORGE_TEST_IMAGES=1` auch auf exFAT- und FAT32-Abbildern, mit `NIGHTFORGE_TEST_DRIVE=/Volumes/<Name>` ein echtes Hin und Zurück (im Ordner `nightforge-session-test`, der danach wieder weg ist).
    - Offen: der Test mit echtem Steam (docs/TODO.md › „Externes Laufwerk“).

- [ ] **4.3 Speicher-Übersicht & sauber entfernen** · `M` · teilweise in PR #27, „Move to …“ in `claude/external-drive-4-2-710e3d` (Live-Test offen)
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
    Test `tests/CompleteRemovalTest/` auf Test-Ordnern; in echt nie ausgeführt.
    - **„Move to …“** (`claude/external-drive-4-2-710e3d`, `GameMove.swift`, `DriveMoves.swift`): Jedes Spiel in Einstellungen › Speicher hat „Verschieben nach …“. Die Abfrage im Hauptfenster zeigt die Laufwerke (zu volle und FAT32 mit Grund ausgegraut) und bei Spielen auf einem Laufwerk „Zurück auf diesen Mac“. Der Fortschritt steht im Download-Panel, mit Abbrechen.
      - Steam (Windows oder Mac) wird dafür gestoppt und danach wieder gestartet, wie es war. Nie, solange ein Spiel dieser Steam läuft oder startet; Starts und Downloads dieser Steam warten mit einem Hinweis.
      - Ablauf: kopieren (`copyfile` mit Rechten, Verknüpfungen und erweiterten Attributen, unter verstecktem Namen), prüfen (jede Datei gleich groß, jede Verknüpfung gleich), umbenennen, dann dem Store sagen. Steam: Manifest, Workshop-Inhalte und Shader-Cache mit, `apps` in der Liste umgetragen. Epic: `legendary move --skip-move` für das Spiel und jeden Zusatzinhalt (legendary trägt Zusatzinhalte nicht selbst um). Erst dann wird das Original gelöscht.
      - Schlägt etwas vorher fehl (Platz, Laufwerk weg, Abbrechen, Steam inzwischen gestartet, legendary lehnt ab), wird die Kopie entfernt und die Liste zurückgeschrieben – das Spiel bleibt, wo es war.
      - Speicher-Tab: pro angeschlossenem Laufwerk mit Spielen ein Balken (Spiele / Anderes / frei) und seine Spiele. Fehlende Laufwerke stehen mit ihren Spielen darunter. „Remove Nightforge Completely“ zählt Spiele auf Laufwerken nicht mehr mit (sie bleiben dort).
      - Test `tests/ExternalDriveTest/`: Hin und zurück mit Prüfung, Abbrechen, Laufwerk nicht beschreibbar, Ordner schon da, Steam inzwischen gestartet, Epic mit Zusatzinhalt und abgelehntem Umtragen.
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
  - **Stand** (teilweise): `nightforge://play/<App-ID>` und `nightforge://show/<App-ID>` im Info.plist registriert (`AppDelegate.application(_:open:)`; kommt ein Link vor dem ersten Scan, wartet er darauf). Ein Link startet nur installierte Spiele, sonst öffnet er die Spielseite – er lädt nie etwas herunter. Detailseite: Knopf „Add to Applications“ legt `~/Applications/Nightforge Games/<Spiel>.app` an (Skript, das den Link öffnet, Cover als Icon, ohne Dock-Symbol); danach zeigt der Knopf die App im Finder. Test `tests/GameShortcutTest/`. Offen: App Intents für Siri/Kurzbefehle – brauchen Xcode: Der Build muss die Intents mit `appintentsmetadataprocessor` auslesen, und den gibt es in den Command Line Tools nicht (geprüft 28.10.); in der echten App noch nicht durchgeklickt (Bildschirmfreigabe fehlte).
- [x] **5.4 Controller-Tab** · `M` · PR #27
  - **Anzeige:** Verbundene Controller mit Akkustand (`GCController.battery`).
  - **Koppeln:** „Pair a controller“ mit Anleitung je Hersteller. Direktes Bluetooth-Koppeln ist eingeschränkt → bei Bedarf die Bluetooth-Einstellungen öffnen und dort warten, bis der Controller erscheint.
  - **Tastensymbole:** „Like my controller / Xbox / PlayStation“ (`InputRouter.PadSymbols`).
  - **Design:** `Dialogs.tsx` → Tab „Controller“; HintBar zeigt „DualSense · 80 %“.
  - **Stand:** Verbundene Controller mit Akkustand (alle 30 s und bei An-/Abmelden aktualisiert), „Pair a Controller …“ öffnet die Bluetooth-Einstellungen und zeigt die Tasten je Hersteller, „Button labels: Like my controller / Xbox / PlayStation“ (`Prefs.padGlyphs`, `PadSymbols(style:)`). Akku in der HintBar: links unten „DualSense · 80 %“ mit Akku-Symbol (unter 20 % in der Akzentfarbe, wie im Entwurf), aktualisiert bei An-/Abmelden und alle paar Sekunden, solange Nightforge vorne ist.
- [x] **5.5 Trackpad-Gesten** · `S` · `claude/musing-haslett-71514d`
  - **Warum:** Am MacBook ist das Trackpad die Maus. Zurück über Esc oder die Pille ist dort ein Umweg (Wunsch vom 28.10.).
  - **Was:** Zwei Finger seitwärts gehen zurück und wieder vor wie in Safari, die Seite folgt dem Finger. Zusammenziehen und Spreizen in der Bibliothek ändert die Cover-Größe.
  - **Stand:**
    - **Erkennen:** `InputRouter` prüft `scrollWheel`-Ereignisse mit `SwipeRecognizer` (`Trackpad.swift`). Eine Geste muss seitwärts anfangen und 15 pt seitwärts weitergehen, wie in Safari. Bis das klar ist, hält er die Ereignisse zurück und gibt sie weiter, wenn doch gescrollt wird. Dann übernimmt `NSEvent.trackSwipeEvent`.
    - **Bedingungen:** Das geht nur mit „Zwischen Seiten blättern“ in den Systemeinstellungen. Die Richtung ist wie in Safari die des Inhalts und folgt damit „Natürliches Scrollen“. Drei Finger (`swipe(with:)`) wechseln ohne Mitgleiten, wenn das so eingestellt ist.
    - **Vor:** Vor gibt es nur direkt nach einem Zurück (`NavigationHistory` in `Navigation.swift`, `LibraryModel.forward()`). Jeder andere Schritt vergisst es. Ein Zurück, das nur die Suche leert oder die ausgeblendeten Spiele verlässt, bleibt auf der Ebene.
    - **Mitgleiten:** Die verlassene Ebene folgt dem Finger und schnappt zurück, wenn man abbricht (`SwipeLevel`). Hinter einer Spielseite scheint die Bibliothek durch, das Abdunkeln der Bibliothek blendet mit. Mit „Bewegung reduzieren“ wird nur überblendet.
    - **Kein Konflikt:** Über der Cover-Leiste scrollt die Leiste. Vor greift dort erst, wenn sie ganz rechts steht. Ihre Ränder kommen ab macOS 15 aus `onScrollGeometryChange`; davor behält die Leiste jede Geste. Sheets, Dialoge, das Download-Panel und das Suchfeld unter dem Zeiger bekommen keine Geste. Was unter dem Zeiger liegt, kommt aus den Rahmen der Views (`SwipeArea`), nicht aus Hover. So stimmt es auch nach einem Ebenenwechsel ohne Mausbewegung.
    - **Pinch:** Die Cover-Größe hat vier Stufen (116, 154, 196, 240 pt) und bleibt gemerkt (`CoverSize`). Das Raster rechnet die Spalten neu, das gewählte Spiel bleibt im Blick.
    - **Geprüft:** Test `tests/TrackpadTest/` prüft Richtung, wann die Geste übernimmt, die Zurück/Vor-Historie, die Ränder der Leiste und die Pinch-Stufen. Am 28.10. mit dem Nutzer am echten Trackpad ausprobiert. Erster Fund: Über dem Suchfeld ließ sich zurückwischen, behoben.
    - **Offen:** siehe `docs/TODO.md`, „Trackpad-Gesten“.

---

## Phase 6 – Ersteinrichtung mit Aha-Moment

- [x] **6.1 Erster Start** · `M` · braucht 1.3 · teilweise in PR #27, Rest in `claude/first-start-6-1-18d92f`
  - **Was:** `SetupView` erweitern:
    - **Ablauf:** Welcome → Checkliste (vorhanden) → Steam-Login mit QR-Hinweis → „Checking your library … N of M games“.
    - **Die Enthüllung:** „**87 of your 104 games run here**“ mit Balken (great / tweaks / untested / need Windows) und den Gründen.
    - **Abschluss:** „Let's play“ + „Also add Epic Games or GOG“.
    - **Wiederholbar:** „Show the first start again“ in About.
  - **Wo:** `SetupView.swift`, `Setup.swift`.
  - **Design:** `Overlays.tsx` → `Onboarding`.
  - **Stand:** Der ganze erste Start läuft auf Home (`SetupView`, `SetupModel.stage`), ohne eigenes Blatt:
    - **Welcome:** „Welcome to Nightforge“, ein Satz, was Nightforge ist und was gleich passiert, „Let's Go“.
    - **Checkliste** mit einer Live-Zeile unter dem laufenden Schritt, nur aus echten Daten (`SetupDetail`): Downloads mit Name, Version, MB und Tempo, dann „wird entpackt“; Windows' Systemdateien, während wineboot sie anlegt; die Pakete und Schritte von `ensureEngine` (MoltenVK, D3DMetal, Controller, DXVK, Grafik-Schichten, Spielumgebung); Steams Update 1 von 2 und 2 von 2 (64-Bit) mit MB und Tempo aus den Stempeln seines Logs, „wird installiert“, Neustarts. Unter fertigen Schritten steht die Dauer („in 25 s“), beim Mac „Rosetta ist da · 120 GB frei“. Keine geschätzte Restzeit. Solange Steam sich vor seinem Anmeldefenster aktualisiert, steht darunter: „Steam's sign-in window opens next: scan its QR code with the Steam app on your phone – no typing.“ Ist das Fenster offen, kommt der Satz mit QR-Code oder Passwort und „Show Steam window again“. Das Anmeldefenster holt Nightforge vor sein eigenes (`SteamWindow`, `yieldActivation`); seit macOS 14 kommt es nicht von selbst nach vorn.
    - **„Checking your library … N of M games“** mit Balken: erst die neueste Profilliste, dann alle 3 s ein Scan, bis zwei gleich viele eigene Spiele finden (höchstens 2 Minuten), dann jedes Spiel einmal nachgeschlagen (bei installierten liest `GameAnalysis` die Dateien). Der Zähler braucht höchstens 2,5 s. „Skip“ führt in die Bibliothek.
    - **Die Enthüllung** auf derselben Seite: „22 of your 100 games run here“ mit Balken in den Kompatibilitätsfarben und je Stufe einer Zeile, was sie heißt; bei „Doesn't run“ getrennt Anti-Cheat (davon n auf GeForce Now) und VR. Gezählt werden Karten (ein Spiel aus zwei Stores ist eins), ohne Store-Einträge und Demos nicht besessener Spiele.
    - **Abschluss:** „Let's Play“ führt in die Bibliothek.
    - **Wiederholbar:** „Show the First Start Again“ in Settings › About spielt Welcome, Prüfung und Enthüllung noch einmal ab, mit eigenen Texten und ohne die Einrichtung selbst. „Skip“ oder Esc schließt.
    - **Bedienung:** ↩/A löst die Hauptaktion der Seite aus (Let's Go, Install Rosetta, Show Steam window again, Try again, Let's Play), Esc/B „Skip“ oder „Let's Play“. Die HintBar zeigt beides, jeder Knopf hat `padFocus`.
    - **Steams erster Start** (gefunden beim Durchlauf am 29.10.): Die Einrichtung tauschte `steamwebhelper.exe` mitten in Steams Update-Installation und startete Steam neu – 124 Neustarts in 30 Minuten, früher „rund 11 Minuten“. `SteamBootstrap` liest jetzt Steams Update-Log; getauscht und neu gestartet wird erst, wenn der neue Client läuft. Bis der Client da ist, startet Steam ohne `-noverifyfiles` (sonst prüfte der erste Bootstrapper keine Updates und stand 92 s). Ein Bootstrapper ohne Client, der nicht nach Updates fragt, wird nach 15 s neu gestartet. Das Quit-Skript beendet Steam mit `-noverifyfiles`; ohne prüfte Steam beim Beenden seine Dateien und installierte Valves Helper über den Wrapper. Nach dem Update tauscht die Einrichtung den Helper und startet Steam nur neu, wenn Valves Helper schon läuft (gestartet vor dem Tausch); vor dem Neustart wartet sie, bis alles von Steam beendet ist. Ein Client, der danach nicht hochkommt (kein „Client version“ in `console_log.txt` seit seinem Start), wird nach 20 s statt 90 s neu gestartet – im zweiten Lauf hing genau so ein Neustart 93 s. Dieser erste Neustart nach dem Update hing in allen drei Läufen beim Einlesen des Browser-Profils: Valves Browser hatte seinen Cache (`htmlcache`) angelegt und wurde dabei beendet. Vor der Anmeldung leert die Einrichtung den Cache deshalb vor dem Neustart.
    - **Gemessen** am 29.10. (Build 297fc6f, frisches `build/fh`, winecx 4.7.3), ab dem Klick auf „Loslegen“: Engine-Ordner 0:36, Prefix 1:11, steam.exe da 1:36, Bootstrapper-Start 1:44, zweiter Start erst 3:16 (die 92 s, inzwischen behoben), Download fertig 3:41, win32 installiert 3:51, win64 installiert 4:28, Anmeldefenster 4:39. Dritter Lauf (a40e22a): Anmeldefenster nach 3:09 (win64 2:34, der erste Neustart hing 26 s bis zum 20-s-Netz, der zweite kam in 6 s hoch). Zweiter Lauf (57cb377, Anmeldefenster vorn, keine 92 s mehr): Engine 0:25, Prefix 1:04, steam.exe 1:27, Bootstrapper-Start 1:35, Download fertig 1:55, win32 installiert 2:06, win64 installiert 2:28, Anmeldefenster 4:13 – davon 93 s ein hängender Neustart nach dem Tausch, inzwischen behoben; Ziel um 2:40. Die Enthüllung „22 deiner 100 Spiele laufen hier“ kam 18–20 s nach der Anmeldung. Der Neustart von Steam 7 s nach der Anmeldung (`finish()`: großes Hauptfenster zu, Hintergrundmodus `-silent`, Spieleinstellungen) läuft parallel zur Prüfung: Steam schreibt seine Lizenzliste etwa 7 s nach der Anmeldung, die Prüfung wartet darauf.
    - **Tests:** `tests/FirstStartTest/` (Seiten, Tasten, QR-Hinweis, Anmeldefenster, Warten auf Steam, Tempo, Wiederholung und ihre Texte), `tests/LibraryRevealTest/`, `tests/SteamBootstrapTest/` (mit den echten Logs vom 23.10. und 29.10.).
  - **Abweichungen:**
    - Kein „Also add Epic Games or GOG“ im Abschluss (Entscheidung des Nutzers, 29.10.): Der erste Start endet mit „Let's Play“. Epic Games verbindet man in Settings › Stores (7.2); GOG kommt mit 7.3.
    - Kein Lampenschein hinter dem Ablauf (Entwurf: `ns-lamp`), weil Sodium laut Regeln nie Deko ist.
    - Die Enthüllung zeigt die Stufen mit ihrer Erklärung im 2×2-Raster statt der kurzen Zeilen des Entwurfs.
    - „Skip“ gibt es nur bei der Prüfung und in der Wiederholung, nicht oben rechts auf jeder Seite: Die Einrichtung selbst lässt sich nicht überspringen.

---

## Phase 7 – Mehrere Stores (groß)

- [x] **7.1 Store-Abstraktion** · `L` · braucht 0.2 · `claude/epic-games-d52d35` — Protokoll `StoreProvider`: Bibliothek laden (offline-Cache zuerst), installieren, starten, Cloud-Spielstände, Sync-Status. Steam wird die erste Implementierung.
  - **Stand:** `Stores.swift`: `StoreProvider` mit `library()` (was auf dem Mac ist – zuletzt Geladenes plus Installiertes/Ladendes, ohne Netz, sofort), `refresh()` (beim Store nachfragen, im Hintergrund), `install(_:context:)`, `uninstall(_:)`, `isConnected` und `sync` (`StoreSync`: ok / syncing / failed mit Grund, `lastSuccess`). Fortschritt steht wie bisher in `Game.install`. `SteamStore` ist die erste Umsetzung: Scan (Nightforges Steam, CrossOver-Flaschen, Steam für Mac, Laufwerke, Anti-Cheat), Download-Anfrage samt Steam-Neustart (sofort oder wenn nichts läuft) und Deinstallieren. `LibraryModel.rescan` sammelt alle Stores ein, Download und Deinstallieren gehen an den Store des Spiels. **Abweichung:** Steams Start bleibt im `LibraryModel` (Anmeldung, Neustarts, `LaunchWatcher`, Mac-Versionen und Steam für Mac sind dort mit dem Startablauf verwoben); andere Stores hängen sich an denselben Ablauf mit Grafik-Leiter und Erstsekunden-Prüfung (siehe 7.2). Cloud-Spielstände sind pro Store eigene Wege (Steam: Steam selbst; Epic: 7.2).
- [ ] **7.2 Epic Games ohne Epic-Launcher** · `L` · Recherche · `claude/epic-games-d52d35` (mit echtem Konto: verbinden, laden, spielen geprüft; Cloud-Spielstände und Deinstallieren noch nicht) — Weg wie Heroic: [legendary](https://github.com/derrod/legendary) (GPL-3.0, passt zu Nightforges GPL-3.0). Login im eigenen Fenster, Download/Start direkt.
  - **Recherche** (27.10.): So macht es Heroic, Quelle legendary 0.21.1:
    - **legendary** ist ein Python-Kommandozeilenprogramm (GPL-3.0). Seit August 2026 wieder gepflegt; 0.21.1 vom 08.09.2026 übernimmt die Fixes aus Heroics Fork. Jede Version hat ein fertiges macOS-Programm (`legendary_macOS_arm64`, ~13 MB, mit eingebautem Python). Heroic liefert es mit und steuert es über die Kommandozeile. Der Konfigordner lässt sich mit `LEGENDARY_CONFIG_PATH` verlegen.
    - **Login:** Epics Anmeldeseite `https://www.epicgames.com/id/login?redirectUrl=…` mit der Weiterleitung `https://www.epicgames.com/id/api/redirect?clientId=34a02cf8f4414e29b15921876da36f9a&responseType=code` in einem eigenen Fenster. Nach dem Anmelden zeigt Epic dort nur eine JSON-Antwort mit `authorizationCode`. Heroic liest diesen Code und gibt ihn an `legendary auth --code <code>`. legendary tauscht ihn gegen Zugangs- und Refresh-Token (`user.json`) und erneuert sie selbst. Passwort, Zwei-Faktor und Captcha bleiben auf Epics Seite.
    - **Bibliothek:** `legendary list --json --platform Windows` liefert je Spiel `app_name`, `app_title` und die Katalogdaten (`metadata`: Namespace, `keyImages` mit `DieselGameBoxTall` = Hochformat-Cover, `DieselGameBox` = Querformat, `DieselGameBoxLogo`, `customAttributes`). Installierte Spiele stehen in `installed.json` (Pfad, Exe, Größe, `can_run_offline`, `requires_ot`). Spiele, die über EA app oder Ubisoft Connect laufen (`ThirdPartyManagedApp`), startet legendary nicht selbst.
    - **Download:** `legendary install <app> --base-path <Ordner> --platform Windows -y` lädt das Manifest und die Chunks vom CDN, prüft sie (SHA-1), setzt nach einem Abbruch fort (`.resume`) und lädt Updates als Delta. Den Fortschritt gibt es nur als Logzeile auf stderr: `= Progress: 12.34% (…), Running for …, ETA: 00:12:34` und `+ Download - 12.34 MiB/s (raw)`. Die Größe vorab liefert `legendary info <app> --json`.
    - **Start unter Wine:** `legendary launch <app> --json` startet nichts, sondern gibt Ordner, Exe, Spielparameter und die Epic-Parameter aus. Dazu gehören ein frischer Exchange-Code (`-AUTH_PASSWORD=…`, `-AUTH_TYPE=exchangecode`), `-epicapp`, `-epicenv=Prod`, `-EpicPortal`, Benutzer, Sprache und Sandbox. Spiele mit Kopierschutz bekommen eine Ownership-Token-Datei (`-epicovt=<Pfad>`). Danach startet Heroic `wine <exe> <Parameter>` selbst. Der Exchange-Code gilt nur kurz, also unmittelbar vor dem Start holen. `-epicovt` ist ein Mac-Pfad und muss für Wine `Z:\…` werden. `--offline` gibt die Parameter ohne Anmeldung aus.
    - **Cloud-Spielstände:** `legendary sync-saves <app> -y --accept-path` mit `WINEPREFIX` findet die Speicherorte im Prefix (`{AppData}`, `{UserDir}`, Benutzer `crossover`) und gleicht nach Zeitstempel ab: das Neuere gewinnt. Heroic ruft das vor dem Start und nach dem Spielende auf.
    - **Anti-Cheat:** legendary weiß nichts davon. AreWeAntiCheatYet führt 73 Spiele mit Epic-Namespace (Fortnite, Valorant, PUBG …).
    - **Grundsatzfrage** (27.10., vom Nutzer entschieden): legendary als Komponente über `components/manifest.json`, nicht selbst in Swift nachbauen. Grund: Manifest-Format, Chunk-Downloader mit Fortsetzen und Prüfen, Delta-Updates und Cloud-Spielstände wären rund 2.500 Zeilen Python zum Nachbauen, ohne echte Testdaten. Nightforge übernimmt Fenster, Bibliothek, Fortschritt und den Start mit seiner Wine-Engine.
  - **Stand:**
    - **Komponente:** `legendary` 0.21.1 (`legendary_macOS_arm64`, GPL-3.0) in `components/manifest.json` und `sources.json`, fest angepinnt. Steht sie in der Online-Liste noch nicht, nimmt Nightforge den Eintrag aus der mitgelieferten Liste und räumt ihn auch nicht weg (`ComponentStore.bundledManifest`). **Schnellstart:** Die PyInstaller-Datei entpackt sich sonst bei jedem Aufruf neu, und macOS prüft dann jede Bibliothek – 5–16 s pro Aufruf. `PackedApp` (`Legendary.swift`) entpackt sie einmal neben sich, danach läuft jeder Aufruf in 0,2 s. Beim Klick auf „Verbinden“ wird legendary schon geholt und einmal gestartet, während man sich anmeldet.
    - **Anmeldung:** `EpicSignIn.swift`: Epics Anmeldeseite in einem eigenen Fenster (WKWebView ohne gespeicherte Cookies). Nightforge liest nur die letzte Seite mit dem `authorizationCode` und gibt ihn an `legendary auth --code`. „Verbunden“ (eigener Merker `Epic/account.json`) ist getrennt von legendarys Anmeldung: Lehnt Epic die Anmeldung ab (abgelaufen), löscht legendary seine Token – die Spiele bleiben dann sichtbar, Stores zeigt „Epic Games hat dich abgemeldet – deine Spiele bleiben hier“ mit „Erneut anmelden“, und Spielen/Laden öffnet die Anmeldung.
    - **Bibliothek:** `EpicStore` (`StoreProvider`): `library()` aus dem eigenen Cache `Epic/library.json` plus legendarys `installed.json`/`assets.json` (Update wartet) und laufenden Downloads – ohne Netz. `refresh()` fragt `legendary list --json` im Hintergrund (Start, alle 15 Min. beim Zurückkommen, „Erneut versuchen“). Cover/Hero/Logo von Epic (`DieselGameBoxTall` usw., `Game.art`), Abzeichen „EPIC“ auf dem Cover und „Epic Games“ auf der Spielseite. Spiele über EA app/Ubisoft Connect sind ausgelassen.
    - **Laden:** `legendary install … --base-path <Prefix>/drive_c/Program Files/Epic Games --platform Windows --skip-sdl --skip-dlcs -y`, Ausgabe in `Epic/Logs/<App>.log`. Fortschritt, Größe und Restzeit liest Nightforge aus dem Log (Download-Panel mit Tempo/Restzeit wie bei Steam). Gewünschte Downloads stehen in `Epic/downloads.json` und laufen nach einem Neustart weiter (legendary setzt fort). Abbrechen löscht den Teil-Download, Deinstallieren `legendary uninstall --skip-uninstaller`.
    - **Größe vor dem Download** (28.10.): Für nicht geladene Epic-Spiele fragt Nightforge `legendary info <App> --json --platform Windows` (legendary liest dafür das Manifest bei Epic): Download- und Installationsgröße samt Build stehen in `Epic/sizes.json` (`EpicSize`) und gelten, bis `assets.json` einen neueren Build nennt. Gefragt wird im Hintergrund, sobald die Spielseite 0,6 s gezeigt wird (nicht für jedes vorbeigescrollte Cover), offline höchstens alle 5 Min. Die Spielseite zeigt „Download 12 GB · Auf dem Mac 25 GB“ (`Game.downloadSize`), `sizeOnDisk` ist die Installationsgröße – damit greift `SpaceCheck` und das Platz-Sheet (`SpaceRequest.needed`). Ist die Größe beim Klick noch unbekannt, zeigt der Knopf „Größe wird geprüft …“; ohne Antwort lädt legendary trotzdem und prüft den Platz selbst. Das Platz-Sheet sagt bei Spielen aus mehreren Stores „Sie bleiben in der Bibliothek ihres Stores“. Test in `tests/EpicTest/`.
    - **Zusatzinhalte (DLCs)** (28.10.): `legendary list --json` liefert je Spiel die besessenen DLCs mit Dateien (`EpicGame.dlcs`, ohne `digitalextras` wie Soundtracks und Artbooks). Die Spielseite nennt sie („Deine Zusatzinhalte: Season Pass – sie werden mit dem Spiel geladen und aktualisiert.“, ab vier „und 2 weitere“). **Laden:** Spiel und Zusatzinhalte sind ein Download in einer Warteschlange (`Epic/downloads.json`, jetzt mit Reihenfolge): legendary installiert nur eins zugleich (es sperrt `installed.json`; ein zweiter Download brach bisher sofort mit „only one instance of Legendary may install“ ab), also nacheinander, ein DLC erst nach seinem Spiel, jeder Teil mit eigenem `legendary install <Teil> --skip-dlcs` und eigenem Log. Der Fortschritt ist einer über alles, nach Größe gewichtet (`EpicStore.jobProgress`); die Größen der DLCs fragt `legendary info` mit (bis zu vier zugleich), das Platz-Sheet rechnet sie mit ein. Bewusst nicht legendarys eigenes `--with-dlcs`: Dort springt der Fortschritt pro DLC auf 0 zurück, und ein DLC ohne Dateien beendet den ganzen Lauf mit einem Absturz (`exit(0)` bzw. `AttributeError` in 0.21.1). Ein DLC ohne Dateien merkt sich Nightforge als „nichts zu laden“ (Größe 0 in `sizes.json`). Bricht ein DLC ab, ist das Spiel trotzdem da („… kommt mit dem nächsten „Aktualisieren & spielen““). **Update & Play** bringt das Spiel und seine DLCs auf Stand: veraltete DLCs und solche, die noch fehlen (später gekauft, abgebrochen), nacheinander nach dem Spiel (`EpicStore.updateParts`); scheitert nur ein DLC, startet das Spiel ohne ihn. Test in `tests/EpicTest/`.
    - **Update & Play, Größe, DLCs mit echtem Konto geprüft** (28.10., Nutzer; ohne Fenster über ein Testprogramm, das `EpicStore` direkt aufruft – der Zugriff auf die App war nicht freigegeben): Bibliothek mit DLCs (Fallout: New Vegas 6, Civilization VI 1, The Outer Worlds 2, Guardians of the Galaxy 1, Fortnite 3). Größen von `legendary info` (Civ VI 10,69 GB Download / 19,67 GB auf dem Mac, Aztec-DLC 1 KB; Fallout NV 14,9 + 2,9 GB). Civ VI mit Aztec-DLC geladen: ein Download mit einem Fortschritt, nach 9 Min. lief der DLC von selbst (2,5 s), beide in `installed.json`, Warteschlange leer. Abbrechen nach 25 s: keine Prozesse übrig, Ordner, Log und Resume-Datei weg. Update & Play: fehlender DLC wurde nachgeladen; Spiel und DLC veraltet → zwei Teile nacheinander, Versionen danach aktuell. Deinstallieren samt DLC. **Zwei Fehler gefunden und behoben:** `Legendary.run` hing selten für immer in `waitUntilExit` (1 von ~400 Aufrufen; eine Größenabfrage wartete 10 Min.) – jetzt wartet es über `isRunning`; und Abbrechen/Deinstallieren/Abmelden beendeten nur legendarys Hauptprozess, seine 18 Download-Prozesse liefen verwaist weiter – `Legendary.stop` beendet jetzt die ganze Prozessfamilie. Knöpfe und Spielseite in der App selbst sind damit noch nicht gesehen.
    - **Starten:** über denselben Ablauf wie Steam-Spiele (Grafik-Leiter DXMT/DXVK/D3DMetal mit `LaunchHealth`, Laufzeiten, `FramePacing`, MetalFX, Erstsekunden-Prüfung, Fehlstart-Sheet), nur ohne Steam: `legendary launch --json --no-wine` liefert Exe und Epic-Parameter mit frischem Anmeldecode (offline: `--offline`), Nightforge startet `wine "C:\Program Files\Epic Games\…"` selbst (`Launcher.launchDirect`, Umgebung wie Steams Spiele per `Engine.directLaunchEnvironment`), Ausgabe in `wine.log`. Startphasen „Bei Epic Games anmelden …“ und „Spielstand wird geholt …“.
    - **Update & Play** (28.10.): Wartet ein Update (`assets.json` ≠ installierte Version), lädt Play es zuerst: `legendary install <App> --update-only --skip-sdl --skip-dlcs -y` mit Log in `Epic/Logs/<App>.log`, der Play-Knopf zeigt „Wird aktualisiert … 42 %“ (`LaunchPhase.updating` aus `Legendary.progress`) mit dem Hinweis „Das Update kommt zuerst von Epic Games …“, danach startet das Spiel von selbst (`LibraryModel.updateEpic`, `EpicStore.update`). B/Esc bricht ab, legendary setzt beim nächsten Mal fort. Ohne Epic (offline, 90 s keine Antwort) oder während ein anderer Epic-Download legendary belegt (legendary installiert nur eins zugleich) startet die Version auf dem Mac, mit einem Hinweis. Bricht das Update mittendrin ab oder fehlt der Platz, startet das Spiel nicht halb aktualisiert, sondern sagt warum; Play setzt fort. Läuft noch ein Update aus einem früheren Nightforge, folgt Play diesem. Test in `tests/EpicTest/` (`updateOutcome`).
    - **Spielstände:** vor dem Start `legendary sync-saves --skip-upload`, nach dem Spielende `--skip-download` (das Neuere gewinnt); „Willkommen zurück“ zeigt „Dein Spielstand ist bei Epic Games“ bzw. was los ist. Spielzeit und „zuletzt gespielt“ zählt Nightforge selbst (`Epic/playtime.json`) – für Home „Weiterspielen“.
    - **Anti-Cheat:** `profiles.json` bekommt Einträge „epic.<Namespace>“ aus AreWeAntiCheatYet (53 Spiele, 26 mit GeForce-Now-ID über den Steam-Zwilling), `scripts/build-profiles.py` schreibt sie (Test in `tests/test_build_profiles.py`). Ältere Nightforge-Versionen überspringen diese Schlüssel. Behandlung wie bei Steam: Symbol auf dem Cover, kein Download, GeForce Now als Hauptknopf, wenn vorhanden.
    - **Test** `tests/EpicTest/` (eigenes leeres Home): legendarys JSON (Liste, installiert, Assets, Startparameter), Fortschritt aus dem Log, Windows-Pfade, Anmeldecode, Entpacken samt Pfad-Ausbruchsschutz, Epic-Profile, der Store offline (Bibliothek von vor 3 Tagen bleibt, abgemeldet bleibt sie auch), Spielzeit.
    - **Mit echtem Konto geprüft** (27.10., Nutzer): Anmeldung in Epics Fenster, 95 Spiele mit Covern, Anti-Cheat-Treffer (Fortnite, Destiny 2, Century gesperrt; Destiny 2/Century mit GeForce Now). 20 Minutes Till Dawn: 54,5 MB in 5 s geladen, gestartet über DXMT mit Epic-Parametern, 2 Min. bei stabilen 60 FPS gespielt, Nightforge kam zurück, „Willkommen zurück“ mit Bewertung, Spielzeit auf der Spielseite. Dabei gefunden und behoben: Discord und Zusatzinhalte standen als Spiele drin; Spiele starteten auf Englisch (`-epiclocale=en`); die Offline-Zeile folgte Steams Regeln.
    - **In der App geprüft** (leeres Test-Home, 27.10.): Stores-Zeile in allen Zuständen, Anmeldefenster mit Epics Seite (deutsch), Bibliothek mit Epic-Covern und Abzeichen, Spielseite, Anti-Cheat-Symbol bei Fortnite, Laden im abgemeldeten Zustand öffnet die Anmeldung, legendary-Komponente geladen und entpackt.
- [ ] **7.3 GOG ohne Galaxy** · `L` · Recherche · `claude/gog-7-3-e69c3b` (gebaut und mit Testdaten geprüft; mit echtem Konto noch nicht) — Weg wie Heroic (`gogdl`) bzw. GOG-API; DRM-freie Installer direkt.
  - **Recherche** (29.10.): So macht es Heroic, Quellen gogdl 1.4.0 und Heroics `storeManagers/gog`:
    - **gogdl** (github.com/Heroic-Games-Launcher/heroic-gogdl, GPL-3.0, passt zu Nightforges GPL-3.0) ist Heroics GOG-Downloader in Python, gepflegt (1.4.0 vom 28.10.2026, 1.3.1 vom 16.10.). Jede Version hat ein fertiges macOS-Programm (`gogdl_macos_arm64`, ~11 MB, PyInstaller-onefile wie legendary). Es kann: Anmeldung (`auth --code` tauscht den Code gegen Token, `auth` gibt sie erneuert aus), Download/Update/Reparatur über GOGs Content-System (Generation 1 und 2, Fortsetzen über `.gogdl-resume`, Updates als Delta gegen das gespeicherte Manifest), `info` (Größe je Sprache, besessene DLCs, Build, Ordnername), `save-sync` (Cloud-Spielstände nach Zeitstempel) und `launch`. Es kann **keine Bibliothek** – die liest Heroic selbst aus GOGs API – und führt **keine Liste installierter Spiele** (Heroic führt sie selbst). `launch` startet das Spiel gleich selbst, statt Parameter auszugeben.
    - **Login:** GOG Galaxys Anmeldeseite `https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https://embed.gog.com/on_login_success?origin=client&response_type=code&layout=galaxy`. Am Ende leitet GOG auf `https://embed.gog.com/on_login_success?origin=client&code=…` weiter; den Code gibt Heroic an `gogdl auth --code`. Passwort, Zwei-Faktor und Captcha bleiben auf GOGs Seite. Lehnt GOG die Erneuerung ab, gibt `gogdl auth` `null` aus, lässt seine Datei aber stehen (anders als legendary); ohne Netz schreibt es zusätzlich „Failed to refresh credentials“ ins Log.
    - **Bibliothek (Heroic, aktuell):** `https://galaxy-library.gog.com/users/<user_id>/releases` (mit Token, seitenweise über `next_page_token`) nennt jedes besessene Produkt (`platform_id` „gog“, `external_id` = Produkt-ID; auch Spiele anderer Plattformen, die am Konto hängen). Was ein Produkt ist, sagt GOGs GamesDB `https://gamesdb.gog.com/platforms/gog/external_releases/<id>`: Titel (`title["*"]`), `type` (game/dlc/…), `supported_operating_systems` (Slug `osx` = Mac-Version), `game.vertical_cover`/`background` als `url_format` mit `{formatter}`/`{ext}`, die DLCs des Spiels (`dlcs[].external_id`). GamesDBs „logo“ ist die Store-Kachel mit Titel, kein freigestelltes Logo.
    - **Starten:** Jedes Spiel bringt `goggame-<id>.info` mit (Windows im Spielordner, Mac in `Contents/Resources` der App): `playTasks` mit `isPrimary`, `path`, `arguments`, `workingDir`, dazu `buildId` und `clientId`. Das reicht zum Starten; GOG-Spiele sind DRM-frei, es braucht keine Anmeldung und keinen Code.
    - **Cloud-Spielstände:** Wo ein Spiel speichert, steht in GOGs Remote-Config `https://remote-config.gog.com/components/galaxy_client/clients/<clientId>?component_version=2.0.45` (`content.Windows/MacOS.cloudStorage.locations` mit `<?SAVED_GAMES?>`, `<?APPLICATION_DATA_LOCAL?>`, `<?INSTALL?>` …; ohne Einträge GOG Galaxys Standardordner). `gogdl save-sync <Ordner> <id> --os … --ts <letzter Abgleich> --name <Name> --skip-upload|--skip-download` gleicht ab und gibt den neuen Zeitstempel aus; sind beide Seiten neuer, rührt es nichts an.
    - **Mac-Versionen:** gogdl lädt Mac-Builds über `--platform osx` als App. Ältere Mac-Versionen, die GOG nur als Installer hat, kann das Content-System nicht ausliefern („Game doesn't support content system api“), und manche sind noch 32-Bit (laufen seit macOS 10.15 nicht).
  - **Entscheidung:** gogdl als Komponente wie legendary, für das, was es gut kann und was sonst viel Nachbau wäre (Content-System v1/v2 mit Delta-Updates, Prüfen, Fortsetzen, Abhängigkeiten, Cloud-Abgleich). **Direkt mit GOGs API** spricht Nightforge, wo gogdl nichts hat und es einfach ist: Bibliothek (galaxy-library + GamesDB, wie Heroic), neuester Build (öffentliches Content-System), Kontoname, Speicherorte (Remote-Config). Den Start liest Nightforge selbst aus `goggame-<id>.info`, statt `gogdl launch` zu nehmen (das startet selbst und kennt Nightforges Engine, Grafik-Leiter und Erstsekunden-Prüfung nicht).
  - **Stand:**
    - **Komponente:** `gogdl` 1.4.0 (`gogdl_macos_arm64`, GPL-3.0) in `components/manifest.json` und `sources.json`, fest angepinnt (sha256 von GitHub, gegen den Download geprüft); Lizenz in `THIRD_PARTY_NOTICES.txt` (legendary stand dort noch nicht, jetzt mit). **Kein Schnellstart:** Der Bootloader von gogdl 1.4.0 (neueres PyInstaller) prüft, dass sein Home-Ordner ein selbst angelegter `_MEI…` ist (PID des Elternprozesses, Besitzer), und bricht aus Nightforges entpacktem Ordner mit „Security validation failure“ und Code 255 ab – im Live-Test (31.10.) scheiterte daran die Anmeldung. Die Prüfung ist absichtlich und wird nicht ausgetrickst: `PackedApp.run` erkennt den Abbruch, merkt ihn sich neben dem Programm (`.runs-packed`), löscht den entpackten Ordner und startet das Programm normal als onefile – im selben Aufruf und künftig immer (`.runs-unpacked` merkt sich umgekehrt ein Programm, das aus dem Ordner läuft; legendary bleibt bei 0,2 s, ein neueres legendary mit demselben Bootloader wäre ebenso abgefangen). Ein gogdl-Aufruf kostet damit ~3 s (der allererste 7,6 s). Damit das nicht spürbar wird: das Token liest Nightforge selbst aus `auth.json`, solange es gilt (genau das gibt `gogdl auth` dann auch aus) – Bibliothek und Anmeldung starten gogdl dafür nicht; Größen fragt Nightforge eine nach der anderen und nur für die Spielseite, die noch offen ist (einmal je Build, in `sizes.json`). Bleibt spürbar: „Spielstand wird geholt …“ vor dem Start eines Spiels mit GOG-Cloud (~3 s je Spielstand-Ordner, nacheinander – zwei gogdl gleichzeitig schrieben beide `auth.json`) und die Größe auf einer Spielseite, die ~3 s später erscheint. Beim Klick auf „Verbinden“ wird gogdl geholt und einmal gestartet, so fällt der langsame erste Start in die Anmeldung, und wie es läuft, steht fest, bevor der Code kommt. Scheitert gogdl selbst (kein JSON, Fehlercode), sagt die Anmeldung „Nightforges GOG-Helfer ist nicht gestartet …“ statt „nicht angenommen“; jede Anmeldung schreibt `GOG/Logs/auth.log` (Code, Art der Antwort, gogdls Log – ohne Code und Token). `tests/GOGTest` startet das echte gogdl, wenn es auf dem Mac installiert ist. Einstellungen, Token (`GOG/gogdl/auth.json`, `--auth-config-path`) und Manifeste (`GOGDL_CONFIG_PATH`) liegen in Nightforges Ordner (`GOGDL.swift`).
    - **Anmeldung:** `GOGSignIn.swift`: GOGs Anmeldeseite in einem eigenen Fenster wie bei Epic (WKWebView ohne gespeicherte Cookies). Nightforge liest nur die Adresse, auf die GOG am Ende weiterleitet (`on_login_success?code=…`, nur https und embed.gog.com), lädt sie nicht und gibt den Code an `gogdl auth --code`. Eigener Merker „verbunden“ `GOG/account.json` mit dem Kontonamen (users.gog.com). Lehnt GOG die Token ab, bleiben die Spiele; Stores und Banner sagen „GOG hat dich abgemeldet – deine Spiele bleiben hier“ mit „Erneut anmelden“. Laden öffnet dann die Anmeldung; **Spielen nicht** – GOG-Spiele starten ohne Konto.
    - **Bibliothek:** `GOGStore` (`StoreProvider`, `AccountStore`): `library()` aus `GOG/library.json` plus Installiertem und laufenden Downloads – ohne Netz. `refresh()` (Start, alle 15 Min. beim Zurückkommen, „Erneut versuchen“) holt die Token über `gogdl auth`, dann galaxy-library und GamesDB für Produkte, die Nightforge noch nicht kennt (8 zugleich, Antworten in `GOG/releases.json` – beim nächsten Mal nur Neues, einmal pro Woche alle, falls GOG eine Mac-Version oder neue Bilder ergänzt hat). Spiele (game/mod, sichtbar) mit ihren besessenen DLCs; Zusatzinhalte, „spam“ und Goodies sind keine eigenen Spiele. Antwortet GOG für mehr als die Hälfte nicht, bleibt die alte Liste. Cover aus `vertical_cover`, Hero aus `background` (sonst die Kachel), kein Logo. Abzeichen „GOG“ auf dem Cover, „GOG“ auf der Spielseite, im Download-Panel und als „Store“-Zeile.
    - **Mac zuerst:** Hat GOG eine Mac-Version, lädt Nightforge sie (`--platform osx`) als App nach `GOG/Games/` in Nightforges Ordner und startet sie direkt (`NSWorkspace`, ohne Wine; eigene „Flasche“ wie Steams Mac-Versionen, also keine Grafik-Presets). Kann GOGs Content-System die Mac-Version nicht ausliefern (`gogdl info` sagt es vorher) oder ist ihr Programm nur 32-Bit (`MachO`, nach dem Download geprüft), merkt sich Nightforge das (`GOG/mac-unfit.json`), entfernt sie und lädt die Windows-Version – mit dem Hinweis „Die Mac-Version von … ist zu alt für diesen Mac – stattdessen kommt die Windows-Version.“ Hat ein Spiel in mehreren Stores nirgends eine Installation, startet die Karte über den Store mit Mac-Version (`DuplicateGames.order`, vor „Steam zuerst“).
    - **Windows-Versionen** gehen nach `C:\Program Files\GOG Games\<Ordner>` im Prefix und starten über denselben Ablauf wie Epic-Spiele (Grafik-Leiter, Laufzeiten, `FramePacing`, MetalFX, Erstsekunden-Prüfung, Engine-Rückfall, Fehlstart-Sheet) – mit Exe, Ordner und Argumenten aus `goggame-<id>.info` (`StoreLaunchCommand`, gemeinsam mit Epic). Laufende GOG-Spiele erkennt Nightforge an `\GOG Games\` (Spielerkennung, Engine-Wechsel, Beenden-Skript). Was die Dateien verraten (`GameAnalysis`), liest es am Programm aus der Info-Datei.
    - **Laden:** Größe vorab mit `gogdl info <id> --platform … --with-dlcs` (Download und Platz in der Sprache des Macs, falls GOG sie hat, sonst Englisch; mit DLCs) in `GOG/sizes.json`; gefragt nach 0,6 s auf der Spielseite, vor dem Download sonst „Größe wird geprüft …“, das Platz-Sheet rechnet damit. Dann `gogdl download <id> --platform … --path <Spielordner> --support … --with-dlcs --lang …` – Spiel und DLCs sind bei gogdl ein Download mit einem Fortschritt. Downloads stehen in einer Warteschlange (`GOG/downloads.json`, einer zugleich) und laufen nach einem Neustart weiter (gogdl setzt fort). gogdl schreibt nichts, wenn es fertig ist; deshalb läuft es in einer Shell, die „Nightforge: gogdl ended with <Code>“ ins Log schreibt – so erkennt Nightforge auch nach einem Neustart, ob ein Download fertig ist, und trägt das Spiel in `GOG/installed.json` ein (Pfad, Version, Build, Sprache, Größe, DLCs). Fortschritt, Tempo und Restzeit aus dem Log (`GOGDL.progress`). Abbrechen beendet gogdl samt Kindprozessen und löscht den Teil-Download.
    - **Update & Play:** Neuester Build aus dem öffentlichen Content-System beim Abgleich (`GOG/builds.json`); weicht er vom installierten ab oder sind DLCs dazugekommen, zeigt die Karte das Update-Zeichen und Play lädt zuerst (`gogdl update` im Spielordner, „Wird aktualisiert … 42 %“, „Das Update kommt zuerst von GOG …“). Offline oder bei laufendem GOG-Download startet die Version auf dem Mac (GOG-Spiele sind DRM-frei).
    - **Spielstände:** vor dem Start `save-sync --skip-upload`, nach dem Spielende `--skip-download`, je Speicherort mit eigenem Zeitstempel (`GOG/saves.json`); Speicherorte aus GOGs Remote-Config, im Prefix unter `drive_c/users/crossover` bzw. für Mac-Versionen im Mac-Home. „Willkommen zurück“ sagt „Dein Spielstand ist bei GOG.“ bzw. „Keine GOG-Cloud …“. Spielzeit und „zuletzt gespielt“ zählt Nightforge selbst (`GOG/playtime.json`).
    - **Offline:** „Offline: Bereit“ mit „GOG-Spiele sind DRM-frei: Es läuft ohne Internet und ohne Anmeldung.“ (außer das Spiel startet über einen anderen Launcher).
    - **Einbindung:** `Provider.gog`, `GameID.gog(<Produkt-ID>)` („gog.1207664663“, Links `nightforge://play/gog.<id>`). Einstellungen › Stores: Epic und GOG teilen eine Zeile (`AccountStoreRow`), das Sync-Banner gibt es je Store (`StoreSyncBanner<Store>`). Texte, die vorher „Epic Games“ fest nannten (Spielstand-Zeilen, Update-Hinweis, Deinstallieren), nehmen jetzt den Store-Namen. Kein Anti-Cheat-Sonderweg (DRM-frei); die Kompatibilitätsprüfungen bleiben.
    - **`LibraryModel.swift`:** ein Abschnitt `// MARK: - GOG` (Verbinden, Abmelden, Spielstände nach dem Spielen, Update und Spielstand vor dem Start, Start der Mac-Version) und kurze Weichen: `stores`, Download (Mac-Version von GOG nicht über Steam für Mac), Start, Größe (`loadStoreSizeIfNeeded`, `storeSize`), `startDirect`, `insight`, `canUninstall`, `runningGame` (Steam für Mac zählt nur Steams Mac-Versionen), `afterScan`/`takeTurnsDownloading` (dito), `launchHint`.
    - **Test** `tests/GOGTest/` (eigenes leeres Home, ohne Netz – GOGs Antworten als Fixtures nach Heroics Typen): galaxy-library, GamesDB, Token-Antworten (angemeldet, abgemeldet, offline), Größe mit Sprache und DLCs, Builds, `goggame-*.info` (Windows und Mac, Pfad-Ausbruch), Speicherorte, Mach-O (64/32 Bit, Universal), Download-Log samt Ende-Zeile, Update-Ergebnis, Anmeldecode, GameID/Links, Mac zuerst, Zusammenführen mit Steam und Epic, der Store (Bibliothek von vor 3 Tagen, installiert, Update wartet, fertiger und abgebrochener Download nach einem Neustart, Deinstallieren nur in GOGs Ordnern, abgemeldet, offline, Abgleich über zwei Seiten, Bekanntes nicht noch einmal fragen).
    - **Abweichungen:** Laden während GOG abgemeldet ist, öffnet die Anmeldung; Spielen nicht. Die Optionen haben (noch) keine Mac/Windows-Wahl für GOG-Spiele – Automatisch heißt Mac zuerst; eine in den Optionen gespeicherte Windows-Wahl würde beachtet. Alte v1-Builds bekommen ihre Redists, ihre `support_commands` laufen nicht.
    - **Galaxys Abhängigkeiten** (31.10., nach dem Live-Test mit Mafia II: „PhysX SDK not initialized“): Wie Heroic (`gog/redist.ts`, `gog/setup.ts`) liest Nightforge nach dem Download und vor jedem Start aus gogdls Manifest (`GOG/gogdl/heroic_gogdl/manifests/<id>`) `dependencies` (v1: Depots mit `redist`) und `scriptInterpreter` (`GOGRedist.swift`). `gogdl redist --ids … --path GOG/Redist` holt die Installer aus GOGs Dependencies-Repository, einmal für alle Spiele; die IDs enthalten immer alles schon Geholte, sonst löscht gogdl es wieder. Befehlszeilen kommen aus dem Repository-Manifest (`.gogdl-redist-manifest`, `executable.path` und `arguments`), ohne Fenster: `.msi` über `msiexec /i … /qn` (Heroic: `/qb` für PHYSXLEGACY), `/passive` wird `/quiet`. Sie laufen in Nightforges Prefix und warten nur auf sich selbst, nicht auf `wineserver -w` (Steam läuft dort). Was eingerichtet ist, steht im Prefix selbst (`Prefix/gog-redist.json`): je Abhängigkeit einmal, das Installationsskript je Produkt und Build – ein zweites Spiel mit denselben Teilen kostet nichts, ein Update lässt das Skript neu laufen, ein neuer Prefix richtet alles neu ein. `scriptInterpreter`-Spiele: `__redist/ISI/scriptinterpreter.exe /VERYSILENT /DIR=… /Language=German /ProductId=… /buildId=… /versionName=… /lang-code=de-DE /supportDir=… /nodesktopshorctut /nodesktopshortcut` je Produkt (Spiel und installierte DLCs), wie Galaxy und Heroic; Spiele ohne Skript mit `temp_executable` bekommen den Installer aus ihrem Support-Ordner. **Belegt übersprungen:** DirectX (DXSETUP, June 2010, 103 MB): winecx 4.7.3 hat d3dx9_24–43, d3dx10/11_43, d3dcompiler_43, xinput1_3, XACT, XAudio2, X3DAudio und XAPOFX eingebaut (i386 und x86_64, im Engine-Ordner nachgesehen); native Kopien im gemeinsamen Prefix würden sie für alle Spiele ersetzen. .NET Framework 3.5–4.7.2: Microsofts Installer laufen unter Wine nicht, dafür kommt Wine Mono. PhysX legacy (9.13) und PhysX 9.17 laufen als GOGs eigene Installer (winetricks `physx` wäre ein anderer Build). Für den Spieler: „Windows-Bausteine für Mafia II werden eingerichtet …“ mit dem Namen des Teils darunter; scheitert einer, sagt ein Dialog welcher, das Spiel startet trotzdem, und der nächste Start versucht es noch einmal (nicht innerhalb von 10 Min., höchstens zweimal). Schon installierte Spiele holen den Schritt beim nächsten Start nach. Protokoll: `GOG/Logs/redist.log` (von gogdl nur die Fehlerzeilen – die anderen tragen Download-Links).
    - **Nach dem Merge von `claude/ux-roadmap-next`** (a5103ef, 29.10.): „Nightforge vollständig entfernen“ nennt jetzt die Stores, in denen die Spiele bleiben („… bleiben in deiner Bibliothek bei Steam, Epic Games und GOG“), zählt GOGs Mac-Versionen mit und sagt „Spielstände in der Cloud deiner Stores“ (`CompleteRemoval.gamesNote`). Auf der Bühne (Home, „Für den Anfang“) bekommt ein Spiel nur von GOG/Epic keine falsche Controller-Aussage mehr: Controller-Unterstützung kennt nur Steam, unbekannt steht in der Reihung zwischen „voll“ und „keine“ und der Satz sagt nichts dazu. Mac-Version und Größe kommen für GOG-Spiele aus dem Store (Größe, sobald das Spiel 0,6 s gewählt war). „Spielordner im Finder zeigen“ zeigt bei nicht geladenen Spielen anderer Stores den nächsten vorhandenen Ordner. `./build.sh` ohne Warnungen im Code, alle 37 Testsuiten grün.
    - **Externe Laufwerke (4.2/4.3)** (nach dem Merge von `claude/ux-roadmap-next` 9097a66, 31.10.): GOG-Spiele gehen wie Epics auf ein Laufwerk – „Auf <Laufwerk> installieren“ lädt nach `Nightforge Games/GOG Games/` (Windows- und Mac-Versionen; `GOGJob.base`, auch nach einem Neustart), „Verschieben nach …“ kopiert den Spielordner dorthin oder zurück (`GameMover.move`, danach merkt sich `GOGStore.recordMove` den neuen Ort – gogdl führt keine eigene Liste; kein Steam zu stoppen, wartet nur, solange gogdl lädt). Ein Spiel auf einem abgesteckten Laufwerk bleibt das des Spielers: „Installiert“, Laufwerk-Abzeichen und „Schließe … an“ wie bei Steam und Epic (`missingDrive`). Die Deinstallieren-Frage nennt GOG (bzw. jeden Store) für den Mac und für das Laufwerk (`Game.uninstallMessage`). Spiele auf einem Laufwerk zählen nicht zu Nightforges eigenem Ordner (`Game.inNightforgeFolder`). Vorher zeigte die Speicher-Ansicht „Verschieben nach …“ auch für GOG-Spiele, lief dann aber in Steams Weg (App-ID 0) – und „Auf <Laufwerk> installieren“ lud trotzdem auf den Mac.
    - **Offen:** Test mit echtem Konto (siehe `docs/TODO.md` › „GOG“).
- [x] **7.4 Doppelt gekaufte Spiele zusammenführen** · `M` · `claude/merge-dupes-7-4-b22892`
  - **Anzeige:** eine Karte pro Spiel.
  - **Detailseite:** „Start through Steam | GOG“ und der Hinweis „saves stay with each store“.
  - **Matching:** über Titel-Normalisierung und IGDB-/Store-IDs.
  - **Stand** (28.10.):
    - **Modell:** `LibraryModel.allGames` bleibt ein Eintrag pro Store (Downloads, laufende Spiele, Speicherplatz, Willkommen zurück brauchen ihn). Daraus entsteht `cards` (`DuplicateGames.swift`), eine Karte pro Spiel – Bibliothek, Home, Suche, Zähler und Dock-Menü zeigen nur sie. Eine Karte ist der Eintrag des Stores, über den sie startet, mit den anderen in `Game.others`; `Game.providers` (erster = Standard zum Starten), `entries`, `gameIDs`, `holds(id)`. Allgemein gebaut: GOG (7.3) ist ein weiterer `Provider`.
    - **Matching** (`DuplicateGames.titleKey`): Groß/Klein, Akzente, Vollbreite, ™®© und Satzzeichen fallen weg, Apostroph und Punkt verbinden („Sid Meier’s“ = „Sid Meier's“, „S.T.A.L.K.E.R.“ = „STALKER“), „&“ = „and“, und am Ende eine allgemeine Ausgabe („Game of the Year (Edition)“, „GOTY (Edition)“, „Complete/Deluxe/Digital Deluxe/Standard/Gold/Ultimate/Premium Edition“). Bewusst nicht „Definitive“, „Enhanced“, „Special“, „Anniversary“, „Remastered“, „Director's Cut“: oft ein eigenes, überarbeitetes Spiel (Age of Empires II: Definitive Edition, Skyrim Special Edition). Zusammengeführt wird nur bei genau gleichem Schlüssel und nur über verschiedene Stores; hat ein Store denselben Titel zweimal (zwei Flaschen, zwei Apps), bleibt alles getrennt. Store-Treffer und Demos nie. Teile einer Reihe, Remaster, Testserver, Soundtracks und Demos haben andere Titel und bleiben so getrennt.
    - **Store-IDs** (Recherche 28.10.): Weder legendarys Metadaten (`metadata` mit `customAttributes`, `releaseInfo`, `developer`; `partnerLinkType` gilt nur EA/Ubisoft) noch Steams `appinfo.vdf` nennen das Spiel im anderen Store. Zuordnungen Steam ↔ Epic gibt es nur online (IGDB mit Twitch-Konto, GOGs GamesDB, PCGamingWiki). AreWeAntiCheatYet (Quelle von `profiles.json`) kennt Steam-App-ID und Epic-Namespace, aber nur für ~50 Anti-Cheat-Spiele, die der Titel ohnehin findet. Daher nur der Titel, vorsichtig.
    - **Standard-Store** (`DuplicateGames.order`): der auf der Spielseite gewählte (`StoreChoice`, neuer Schlüssel `startsThrough.<GameID.key>` unter jedem Eintrag der Karte); sonst der, in dem es installiert ist (vor dem, in dem es lädt), von mehreren der zuletzt gespielte; sonst Steam, dann die anderen Stores in ihrer Reihenfolge. Wird die Kopie im gewählten Store deinstalliert und ein anderer Store hat das Spiel noch, vergisst Nightforge die Wahl.
    - **Spielseite** (`StoreChoiceRow` über dem Play-Knopf): „Starten über [Steam | Epic Games]“ als Glas-`Segmented` (per Pad erreichbar, feste Reihenfolge der Stores), darunter „Spielstände bleiben beim jeweiligen Store.“; lädt gerade der andere Store, „Wird von Epic Games geladen … 42 %“. Play, Laden, Deinstallieren, Update & Play, Größe, Optionen und Gelerntes gehen an den gewählten Store, denn die Karte ist dessen Eintrag. Meta-Zeile: alle Stores, der gewählte zuerst. Genre, Jahr und Metascore kommen vom Steam-Eintrag, auch wenn die Karte über Epic startet.
    - **Karte:** Cover-Abzeichen „STEAM + EPIC“ (neben „MAC“). Status und Fortschritt (Cover, Gruppe in der Bibliothek, Filter „Auf diesem Mac“, Home-Leiste) zeigen einen laufenden Download in einem der Stores (`Game.shown`); das Download-Panel nennt bei solchen Spielen den Store. Läuft das Spiel aus einem seiner Stores, zeigt die Karte „Läuft“, und Play wechselt zum Spiel.
    - **Was am Spiel hängt:** Ausblenden und Anheften gelten, wenn einer der Einträge markiert ist; Markieren und Aufheben setzen alle Einträge. Optionen, Gelerntes, Bewertungen und Cover-Cache bleiben pro Store. Zuletzt gespielt: das Neueste von beiden. Controller und VR kommen vom Store, der es weiß (Epic kennt beides nicht). Suche (bester Treffer über die Namen aller Stores), Filter, Home-Leiste und Zähler („n Spiele“, „Ausgeblendet n“, Dock-Menü, „So läuft deine Bibliothek“) zählen das Spiel einmal; die Zahlen in Einstellungen › Stores zählen es in jedem seiner Stores. Links `nightforge://play/<id>` beider Stores führen zur selben Karte; ist der gewählte Store nicht installiert, wohl aber der verlinkte (oder der aus „… ist bereit“ nach einem Download), spielt dieser und wird die Wahl.
    - Keine bestehenden Schlüssel geändert, keine Migration.
    - **Test** `tests/DuplicateGamesTest/`: Titel (auch 17 Paare, die getrennt bleiben), Zusammenführen samt Store-Treffern, Demos und doppelten Titeln, Standard-Store, gemerkte Wahl, Markierungen, Zähler, Home-Leiste, Dock-Menü, Filter.
    - **Echte Bibliothek** (nur lesend, 28.10.): 105 Steam- und 93 Epic-Einträge werden 197 Karten – ARK: Survival Evolved (Steam 346110 + Epic) ist eine Karte; Dead Island / Dead Island 2, Tomb Raider / Rise of the Tomb Raider, Chivalry / Chivalry 2 bleiben getrennt. **ARC Raiders** steht auf diesem Mac weder in Steams Katalog (App 1808500 fehlt in `appinfo.vdf` beider Steams) noch in Epics Bibliothek (`library.json`, `assets.json`) – hier nicht prüfbar. **In der App gesehen** (28.10., Maus): Bibliothek „192“; ARK als eine Karte „STEAM + EPIC“ mit Controller-Symbol, „ARK: Survival Of The Fittest“ daneben getrennt; Spielseite mit „Starten über [Steam | Epic Games]“ und dem Hinweis. Wechsel auf Epic Games: Seite bleibt offen, Epic-Bild, Abzeichen „EPIC GAMES · STEAM“, Epic liefert „Herunterladen 69,2 GB · Auf dem Mac 169,7 GB“, Karte zeigt „EPIC + STEAM“; zurück auf Steam: Steam-Logo, „bis zu 177,89 GB“, Hinweis zur Mac-Version. Esc direkt nach dem Wechsel führt zurück. Nichts geladen; die Test-Wahl ist wieder entfernt. Offen: per Pad, Download im anderen Store, Markierungen (`docs/TODO.md`).
    - **Abweichungen:** Die Spielzeit ist die Summe beider Stores, nicht „das Neueste“ – die Spielseite sagt, wie lange man das Spiel gespielt hat. Matching nur über den Titel (siehe Store-IDs). Cover und Logo kommen vom Store, über den die Karte startet, und wechseln mit der Wahl. „Start through <anderer Store>“ im Fehlstart-Sheet (1.2) ist damit möglich, aber nicht gebaut.
- [x] **7.5 Sync-Status pro Store** · `S` · `claude/epic-games-d52d35`
  - **Fehlerfall:** Banner „Couldn't reach Epic Games – your games are from 3 days ago and still play. Try again“; nie still verschwundene Spiele.
  - **Design:** `Library.tsx` → `SyncBanner`; Tab „Stores“.
  - **Stand:** `StoreSync` (7.1) hält pro Store ok / syncing / failed(Grund) / signedOut und die Zeit der letzten erfolgreichen Abfrage. `StoreSyncBanner.swift` unter den Filtern der Bibliothek: „Epic Games nicht erreichbar – deine Spiele von Epic Games sind auf dem Stand vor 3 Tagen und laufen weiter.“ mit „Erneut versuchen“ (zeigt dann „Epic Games wird aktualisiert …“ mit Glas-Spinner) bzw. „Epic Games hat dich abgemeldet – deine Spiele bleiben hier …“ mit „Erneut anmelden“; per Pad erreichbar. Ist alles aktuell, sagt das Banner nichts. Dieselben Zustände in Einstellungen › Stores (siehe 7.2). Steam meldet nie einen Fehler – seine Bibliothek liest Nightforge von der Platte. Test in `tests/EpicTest/`. In der App gesehen (Test-Home, abgemeldet). Offen: Warnsymbol am Store-Filter, sobald es den gibt (2.1).

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
