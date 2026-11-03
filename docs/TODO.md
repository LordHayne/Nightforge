# Nightforge – offene Punkte

Was liegen geblieben ist und irgendwann angegangen werden kann. Stand: 26.10.2026, nach dem
Umstieg auf winecx 4.7.3 mit D3DMetal (PR #7), dem Controller-Paket (PR #8) und dem Code-Audit
(behoben in PR #4, #5, #11, #12, #14–#19, der Rest steht unten unter „Aus dem Code-Audit“).

Neue Punkte unten in den passenden Abschnitt, Erledigtes löschen (die Geschichte steht im Git-Log).
Jeder Punkt nennt, wo man anfängt.

## Nächster Release (0.3.0)

Der Nutzer, 31.10.: „Wenn wir die großen Brocken abgearbeitet haben, brauchen wir einen Stand für einen Release.“
Seit v0.2.0 (25.10., a4a57a0) sind über 340 Commits dazugekommen, alle auf dem lokalen Integrationszweig
`claude/ux-roadmap-next`, nichts davon gepusht.

- **Vorher fertig (jeweils live getestet, gemergt mit OK des Nutzers):**
  - 2.5 größere Schrift: erledigt (a55040a).
  - GOG 7.3: gemergt (159acfa, Fixes d555778), live geprüft. Offen ist nur der Offline-Start.
  - TV-Modus (live am 31.10./1.11.): L1/R1, Overlay, Ton über den Verstärker und die sofortige Rückkehr funktionieren.
    Gebaut auf `claude/tv-fullscreen-61ab1e`, am Fernseher nachzutesten: Vollbild beim Anschließen im Spiegelbetrieb
    (6eb8030), Overcooked im Fenster bzw. Mafia II mit 3024×1964 durch eine frische Wine-Sitzung, wenn sich die
    Bildschirme geändert haben (7d8a440, 0d50047), und der **Lade-Vorhang** mit dem Nightforge-N beim Start und Ende,
    damit kein Desktop und kein Steam-Fenster aufblitzt (dc507c4, 518701b; Nutzer: „für einen richtigen Big-Picture-Modus“).
  - L1/R1 zwischen Startseite und Bibliothek: gebaut auf `claude/tv-fullscreen-61ab1e` (die TV-Session hat es mitgebaut,
    weil sie `InputRouter` ohnehin ändert), live bestätigt.
  - Reichere Spieldaten, Phase 2: Teil A und B gebaut. Das Layout der Spielseite wird nach dem Feedback vom 31.10. überarbeitet.
  - Testabdeckung: gemergt (9becef2). Weitere Tests für TV und Spielinfos nach deren Merge.
  - Kleines Controller-Overlay: beide Sticks 2 s drücken (L3 + R3, weil macOS 26 die PS-Taste fürs Game Overlay nutzt), dann
    Weiterspielen, Spiel beenden (auch wenn es hängt) und Zu Nightforge. Gebaut auf `claude/tv-fullscreen-61ab1e`
    (`GameOverlay.swift`), live in Overcooked 2 und Valheim bestätigt; es wird mit dem TV-Modus gemergt (siehe
    „Controller“). Das schöne große Overlay kommt nach 0.3.0.
  - GOG-Spiele bekommen Spielprofile, dazu das Mafia-II-Profil (Session mafia-ii, Zweig `claude/reverent-goldberg-46e548`,
    95305e4 + 78997a3): mergen. Mafia II startet damit gleich mit WineD3D, ohne Echo.
  - **Nach 0.3.0** (Nutzer, 31.10.): Mafia II flüssig und ohne Knacken. Ursache ist OpenGL im WoW64 für 32-Bit-Spiele
    (zwei bis drei volle CPU-Threads). APEX, DirectSound, Schatten, Geometrie und AO helfen nicht. Der Weg ist DXVK
    auf KosmicKrisp (Session kosmickrisp-dx9), gilt auch für Left 4 Dead 2 und andere DX9-Spiele.
  - Landingpage und README.
  - **Kleine Anzeigefehler kommen in späteren Releases** (Nutzer, 1.11. abends: „diese kleinen anzeige bugs …
    können wir in weiteren releases dann auch beheben. der grundstein ist gelegt“). Damit gemeint sind:
    - der Mauszeiger, der am Ladebildschirm aufblitzt bzw. bei Overcooked wieder sichtbar war (53b3346);
    - ein Fenster des Spiels, das nicht auf dem Ladebildschirm landet (Wukongs Treiber-Warnung);
    - Steams Hauptfenster, das nach dem Spielende kurz vor dem Ladebildschirm auftaucht (ShowInterstitials hatte es geöffnet);
    - das Pad in „startet nicht?“.
    Was die Sitzungen dazu am 1.11. noch committet haben, wird mit getestet. Für 0.3.0 blockiert davon nichts.
    Gebaut am 2.11. auf `claude/display-polish-03x-1a4e06`, dazu das Flackern beim Beenden (Mafia II) und ein
    durchgehender Vorhang über alle automatischen Wege eines Starts (Control), live zu
    prüfen (Schritte unter „Darstellung und Leistung“ › „Nach 0.3.0“); beim Pad bei „startet nicht?“ ist die
    Ursache weiter offen, es gibt neue Log-Zeilen.
    In 0.3.0 gehört dagegen Unreals Treiber-Warnung unter D3DMetal 3.0: Das ist kein Anzeigefehler, ihr „Yes“
    beendet das Spiel. AMD-Liste erledigt (f177076), NVIDIA/Intel bei der Sicherheits-Sitzung.
  - **Kurz gespielt und beendet galt als Fehlstart** (1.11. 23:26, OxyRail und Mafia II; Zweig
    `claude/quick-quit-fix-fcdb40`): Nightforge startete das Spiel danach ungefragt mit der nächsten Grafik neu, bei
    OxyRail über den Vorhang von Valheim, das gerade startete. Jetzt gilt ein Start mit Bild als gelungen und der Weg
    als bestätigt, auch wenn das Spiel in den ersten 30 s endet. Bild heißt: Der Vorhang ist für das Spiel gesunken
    (`LaunchHealth.pictureShown`, auch für Steams Log beim nächsten Start) oder Bildraten stehen im Log. Nur eine
    Grafik-Fehlermeldung rückt dann noch weiter; ein Ende ohne Bild wie bisher. Ein Druck auf „Spielen“ beendet, was
    der Start davor noch tut (die ersten Sekunden beobachten oder das Spiel anders neu starten), und der alte Ablauf
    fasst den neuen Vorhang nicht mehr an. B auf dem Vorhang tut nichts mehr, außer bei „startet nicht?“: Bisher brach
    es nur Nightforges Warten ab, und Steam startete das Spiel trotzdem. Live zu prüfen.
- **Release-Stand einfrieren:**
  - Alle Testreihen grün.
  - Ersteinrichtung mit leerem HOME (`build/fh`, siehe Notizen zum Fresh-Setup-Test).
  - Kurzer Live-Durchlauf: Windows-Spiel über Steam, Mac-Version, Epic, GOG, TV.
  - Version 0.2.1-dev → 0.3.0.
  - Release-Notizen seit v0.2.0 auf Deutsch und Englisch: `docs/release-notes/v0.3.0.md`. `release.yml` setzt die Datei
    zum Tag (`docs/release-notes/<Tag>.md`) vor den Installationstext. Nach den letzten Merges gegenlesen. Sie warnen:
    Auf macOS 14/15 nicht aktualisieren, denn der Updater von 0.2 prüft `LSMinimumSystemVersion` noch nicht und tauscht
    sich gegen ein 0.3.0, das sich dort nicht öffnet. Erst der Updater von 0.3.0 prüft das.
  - Kleine Punkte aus der Gatekeeper-Recherche (unten, „Recherchen vom 1.11.“).
- **Veröffentlichen, nur mit ausdrücklichem OK des Nutzers:**
  - Vorher das Release `d3dmetal-3.0` anlegen, mit `scripts/package-d3dmetal.sh` aus dem Game Porting Toolkit 3.0. Der
    Nutzer hat die DMG am 1.11. geladen.
  - Integrationszweig pushen und über einen PR nach `main` bringen.
  - Tag `v0.3.0` löst `release.yml` aus.
  - Danach das Beta-Release `d3dmetal-4.0b3` samt Tag löschen (Nutzer, 1.11.: „entfernen wir es“). Erst dann, denn
    `main` (0.2.0) lädt D3DMetal bis zum Release noch von dort.
  - Danach die zurückgehaltenen Dependabot-PRs #21–#26 prüfen (sie warten auf einen Release- oder Grafik-Build).

## 0.3.1: Hänger-Fixes live prüfen (H1–H3 der Codeprüfung, Zweig `claude/h1-h3-031`)

Gebaut und mit Stand-ins getestet (`tests/SubprocessTest`, `tests/QuitScriptTest`, `tests/CompleteRemovalTest`), noch nicht in der
echten App gesehen. Beschreibung der Risiken: `docs/CODE-PRUEFUNG.md` (Zweig `claude/code-review-plan-2f9ae5`, 87e6ef1).

- **Was sich ändert:**
  - `Subprocess.run(…, timeout:)` (neu, `Subprocess.swift`): `Engine.stopAll` (`wineserver -k` 15 s), `Engine.ownProcesses`
    (`ps` 5 s, über `Engine.processTable`), `importRegistry` (regedit 30 s, `DetachedProcess.waitUntilExit(timeout:)`/`end()`),
    `open` und `codesign` in `Detached.swift` (10 s/30 s). Ein Befehl, der nicht zurückkommt, wird beendet (SIGTERM, nach 2 s SIGKILL).
  - „Komplett entfernen“ (`CompleteRemoval`): Steam wird höchstens 20 s freundlich beendet (`withDeadline`), dann SIGKILL für alles, was
    aus Nightforges Ordner läuft (`proc_listallpids`, kein `ps`, kein `wineserver -k`), und für ein wartendes `steam-shutdown.sh`.
    Die Zeile unter dem Knopf zeigt die Phase. Ein Ziel, das sich nicht löschen lässt, hält die anderen nicht auf; die Einstellungen
    bleiben dann stehen, die Meldung nennt, was blieb („Nicht alles ließ sich löschen (…)“). „Spielstände nicht kopiert“ kommt nur noch,
    wenn es wirklich das Kopieren war (dann ist nichts gelöscht). Ordner ohne Schreibrecht werden beschreibbar gemacht und noch einmal versucht.
  - Beenden-Skript: „Nightforge läuft wieder“ heißt jetzt, dass eine Befehlszeile mit dem Programm *dieser* App BEGINNT (nicht nur
    den Pfad nennt) und nicht die beendende Nightforge selbst ist. Wartet höchstens 12 h auf ein Spiel oder einen Download
    (`NIGHTFORGE_QUIT_LIMIT`, Sekunden) und lässt dann alles, wie es ist. Ein pausierter Download (`StateFlags` 512) und ein Rest
    ohne Manifest in `steamapps/downloading` halten Steam nicht mehr.
  - Die Entfernung braucht kein `ps` mehr für das Beenden-Skript: es schreibt seine PID in `steam-shutdown.pid` neben sich (und
    löscht sie am Ende), die Entfernung beendet genau diese PID (nur wenn sie eine `/bin/bash` ist, die beim Schreiben der Datei
    begann). Ein Skript aus einer Nightforge von davor wird über seine Befehlszeile gefunden (`ps`, höchstens ~9 s). Grund: Am 3.11. um
    0:30 hing `ps -ax` auf dem MacBook für alle Aufrufer (56 feststehende `ps`, `ps -p 1` antwortete, SIGKILL half nicht).
  - **`ProcessList`** (`Subprocess.swift`): alle `ps -axo`-Aufrufe (`Engine.processTable`/`ownProcesses`/`isSteamRunning`, `GameProcesses.table`,
    `GameTestRun.ps`, `Legendary.processTable`) laufen mit Frist (4 s); verfehlt `ps` sie, wird eine Minute lang gar keins mehr gestartet
    (jedes wäre nur ein weiteres, das nie endet, und ein weiterer Wartender – oft der Hauptthread). In der Minute bekommen Aufrufer, die eine
    alte Liste vertragen (`isSteamRunning` & Co., `GameProcesses.tableForWatching` für die Spielerkennung), die letzte gute (bis 10 Minuten
    alt), die anderen (Spiel beenden) nichts. `nettop` in `MacSteamProgress` hat ebenfalls eine Frist. Anlass: 3.11. ab ~0:40 hing
    `ps -ax` auf dem MacBook für alle Aufrufer (angehaltene Wine-Prozesse nach einem abgebrochenen winedbg), Nightforge (e8f11cc) stand
    auf dem Hauptthread in `watchDrives` → `Engine.isSteamRunning` → `ps`. Offen: die übrigen `waitUntilExit`/`readDataToEndOfFile`-Stellen
    (Liste in `docs/CODE-PRUEFUNG.md`), und dass der Hauptthread bei einem ersten verfehlten `ps` einmal bis ~6 s steht.
  - `CompleteRemoval.Places()` zeigt außerhalb der App (ohne Bundle-ID `io.github.lordhayne.nightforge`, also in jeder Testbinary)
    ins Leere und nimmt die Domäne `nightforge.not-the-app`: ein Test, der einen Ort zu überschreiben vergisst, löscht nichts
    Echtes, und `CompleteRemoval.run()` verweigert sich dort (`requireApp`, bevor etwas beendet wird).
  - **Steam geht nach dem Beenden schneller aus** (war: immer 30 s Cloud-Wartezeit, dann `-shutdown`, dann `wineserver -k`): Das Beenden-Skript
    bekommt als 8. Argument, wann zuletzt ein Spiel lief oder zu starten gebeten wurde (`Engine.lastGameActivity`, gesetzt bei „Spielen“
    und solange die Spielerkennung ein Spiel sieht), und wartet die 30 s nur, wenn das weniger als 5 Minuten her ist (oder es selbst ein Spiel
    laufen sah). Sonst sofort `-shutdown`. Nach „Spielen“ und sofortigem Beenden (Nightforge beenden nach dem Start) bleibt die Wartezeit, damit ein
    Spiel, das noch nicht in der Prozessliste steht, nicht unter Steam weggeräumt wird.
  - **`-shutdown` nie an ein Steam, das nicht läuft** (es würde ein neues starten): `Engine.stopSteam` fragt nach dem Warten auf Steams Update
    noch einmal, ob es läuft (die Schritte sind jetzt als `stopSteam(_:running:installing:shutdown:hardStop:)` prüfbar, `tests/SteamStopTest`);
    das Skript tut es schon nur bei laufendem Steam. Ignoriert Steam das `-shutdown`, folgt nach 20 s `wineserver -k` (beides war so, jetzt getestet).
- **Live zu prüfen** (alles im Test-HOME `build/fh`, nicht im eigenen Konto; „Komplett entfernen“ nie mit dem echten HOME):
  1. Entfernen mit laufender, angemeldeter Steam: die Zeile wechselt „Steam und Wine werden beendet …“ → „Spielstände werden kopiert …“ →
     „Dateien werden gelöscht …“, Nightforge geht in den Papierkorb und endet, nach dem Beenden liegt nichts mehr im Test-HOME außer
     `Documents/Nightforge Saves` (`find build/fh -newer …`; besonders `Saved Application State` und `Preferences`, die AppKit beim
     Beenden neu schreiben könnte).
  2. Dasselbe, nachdem sich Steam abgemeldet hat (die Lage am Mac mini): darf nicht länger als ~25 s bis zum Löschen brauchen. Hängt es
     doch, in der Aktivitätsanzeige „Prozess analysieren“ und den Stapel aufheben.
  3. Entfernen mit absichtlich veraltetem Log: `bootstrap_log.txt` des Test-Prefix mit einem Block, der in „Found pending update“ endet,
     und Steam läuft: früher 120 s Warten, jetzt höchstens 20 s.
  4. Löschfehler: in `build/fh/Library/Caches/Nightforge` eine Datei mit `chflags uchg` sperren, entfernen: Meldung nennt „Nightforge“,
     der Rest ist weg, die Einstellungen bleiben; `chflags nouchg`, zweiter Versuch geht durch.
  5. Ein wartendes Beenden-Skript: Nightforge beenden, während ein Download läuft (neben dem Skript liegt `steam-shutdown.pid`,
     `ps` zeigt `steam-shutdown.sh`), Nightforge neu starten und entfernen: das Skript ist danach weg, die PID-Datei auch.
  6. Beenden-Skript, mit der installierten Nightforge: daneben einen Entwicklungsbau (anderer Ordner) offen lassen, die installierte beenden:
     Steam und die Wine-Sitzung gehen nach ~30 s trotzdem (früher blieben sie, weil der Entwicklungsbau als „wieder geöffnet“ zählte).
  6b. Nightforge beenden ohne Spiel in den letzten 5 Minuten: Steam und die Wine-Sitzung sind in wenigen Sekunden weg (nicht nach ~1 Minute).
     Ein Spiel starten und Nightforge sofort beenden (Nachher-Einstellung „Beenden“): das Spiel läuft weiter, Steam wird nicht darunter beendet.
     Ein Spiel beenden und Nightforge innerhalb einer Minute beenden: ~30 s Wartezeit, dann Steam aus.
  7. Pausierter Download: in Steam einen Download pausieren, Nightforge beenden: Steam geht nach ~30 s aus, kein `steam-shutdown.sh` bleibt.
     Aktiver Download: Steam bleibt, das Skript wartet; Nightforge wieder öffnen beendet das Skript.
  8. Spielstart nach einem festgefahrenen Wine (nur im Test-HOME: den `wineserver` des Test-Prefix mit `kill -STOP` anhalten, ein
     Spiel starten): „Startet …“ endet nach der Frist von `importRegistry` (30 s) mit einem Fehler oder einem Neustart von Steam, statt für
     immer zu stehen. Danach `kill -CONT`/beenden.
- **Nicht gemacht (bleibt für den Umbau):** die übrigen 17 `waitUntilExit()` (Liste in `docs/CODE-PRUEFUNG.md`, H2), die Wartezeit auf
  „installing“ in `stopSteam` (M6), `ComponentStore` entpackt auf dem Actor (M1), `windowsGameRunning` in `applyRetinaMode` (H4).

## Nach dem Engine-Wechsel neu prüfen

Die Tests vom 26.10. liefen größtenteils noch auf Wine 11.18 (Gcenx). Seit PR #7 läuft winecx 4.7.3.

- **Spieletest über Nacht** (2.11., Zweig `claude/angry-heisenberg-1f2283`): Nightforge spielt alle installierten Spiele
  selbst durch – über den normalen Start mit Leiter und Vorhang, bis 120 s auf das Bild, dann 60 s laufen, beenden wie
  „Spiel beenden“ im Overlay – und schreibt `GameTests/<Datum>/report.json` und `report.md` in Nightforges Support-Ordner.
  Nur über den Schalter `defaults write io.github.lordhayne.nightforge gameTest -bool true` (einmalig, wird beim
  Start gelöscht), Abbruch mit `gameTest.stop`. Misst zu Beginn die Systemlast (wartet bis 5 min, bis sie unter der
  Hälfte der Kerne liegt) und vor jedem Spiel; FPS unter hoher Last sind markiert – also nachts auf dem MacBook, wenn keine
  Sitzung baut. Mit `gameTest.basket` (compat-dbs `testkorb.json`) spielt er die installierten Korb-Spiele zuerst, nach
  `score`, und trägt `hint`/`standsFor` in den Bericht ein. Lädt und installiert nichts: Spiele mit Update, fehlenden Laufzeiten,
  D3DMetal-Einrichtung, Anmeldung oder Anti-Cheat stehen unter „Nicht gestartet“. `scripts/import-game-test.py` bringt
  den Bericht nach `docs/spieletest/`. Offen: der erste Lauf mit dem Nutzer, danach nach jeder Engine-Änderung; die
  Einträge (`game`, `store`, `storeID`, `result`, `way`, `issues` wie `compat-report.yml`) in die Kompatibilitätsliste zählen.
  Die zweite Fassung eines Spiels (Windows-Rest neben der Mac-Version) testet er nicht, nur die gewählte.
- **Getestete Spiele auf winecx gegenprüfen.** Palworld (DXMT, 60 FPS), Deadlock (DXVK, 60–120 FPS),
  Left 4 Dead 2 (WineD3D) und 7 Days to Die. Die Ergebnisse und Profile in
  `profiles/mac.json` beziehen sich auf 11.18. OxyRail ist am 28.10. auf winecx bestätigt: DXMT mit MetalFX,
  nach dem Laden gleichmäßig 59,7–59,9 FPS am 60er-Limit, laut Thomas scharf und flüssig.
- **Left 4 Dead 2.** Auf 11.18 scheitert DXVK an seinen Puffern (`vkCreateBuffer`, MoltenVK lehnt
  externe Speicher-Handles ab). WineD3D läuft, stürzt aber nach etwa einer Minute ab, und im Spiel fehlte der Ton.
  `-vulkan` (Valves DXVK) und WineD3D mit Vulkan starten nicht. Auf winecx (26.10.) scheitert DXVK schon früher:
  `VK_ERROR_FEATURE_NOT_PRESENT` bei `vkCreateDevice`, weil der Vulkan-Layer dort nicht geladen wird (siehe
  „Aus dem Code-Audit“ → Vulkan-Layer). WineD3D bleibt der Weg. Zum Ton:
  In der Cloud-Konfiguration stehen `volume "0.008"` und Quadro-Lautsprecher, also erst im Spiel unter
  Optionen → Audio hochdrehen, bevor man Wine verdächtigt. Stürzt am 28.10. weiterhin ab, noch nicht genauer
  untersucht.
- **DXVK unter winecx gar nicht nutzbar?** Ursache am 3.11. eingegrenzt: Es fehlt der Vulkan-Loader, also auch der
  Layer. Die Probe dazu und der Weg über `CX_LIBVULKAN` stehen unten bei „Vulkan-Layer und winecx“. Mafia II (31.10., GOG) scheitert genau wie L4D2: `vkCreateDevice` lehnt das
  5. und 39. Feature ab (`geometryShader`, `shaderCullDistance`), „DxvkAdapter: Failed to create device“ – viermal in
  `Logs/wine.log`, dreimal davon gleich nach Steams `gldriverquery`. DXVK-macOS 1.10.3 verlangt beide; ohne den Vulkan-Layer
  (winecx hat keinen Loader) bleibt das so. Für D3D10/11 vermutlich genauso (Geometry-Shader ab Feature-Level 10) – mit
  einem D3D11-Spiel auf DXVK nachprüfen. Gebaut: Unter winecx (`Engine.vulkanLayerLoads` false) ist die D3D9-Leiter nur
  noch „WineD3D“ (seit 1.11.; vorher „WineD3D, DXVK“, und ein frühes Ende schaltete Mafia II auf DXVK weiter, das hier nie
  geht). Mit KosmicKrisp (Branch `claude/quirky-clarke-81fd65`) kommt DXVK für D3D9 zurück auf die Leiter. DXVKs Fehlerzeilen
  zählen nur noch für einen Start auf DXVK (`GameLog.graphicsFailed(…, layer:)`) – das Log ist geteilt.
  Der Ausweg ist KosmicKrisp (unten bei „Vulkan-Layer und winecx“): Er meldet `shaderCullDistance` schon lange und
  `geometryShader` seit Mesa 14f59d06 (29.10.2026).
  Die D3D9-Leiter in `LaunchHealth.attempts` fragt das Profil nicht. Ein Profil mit `graphics` ändert für D3D9-Spiele nur
  „Am verträglichsten“ (`ladder`). Für Mafia II reicht das, weil winecx ohnehin mit WineD3D beginnt.
- **Andere Source-Spiele** (Team Fortress 2, Garry's Mod): Sie bekommen jetzt dieselbe DirectX-9-Leiter wie L4D2.
  Noch kein einziges getestet.
- **Unreal-Spiele allgemein.** Bis 26.10. bekam kein Unreal-Spiel DXMT. Die Einstellungen reichten nur drei
  Ordner tief, `<Projekt>/Binaries/Win64/*-Shipping.exe` liegt auf Ebene 4. Wer ein Unreal-Spiel für
  „läuft schlecht“ hielt, sollte es erneut versuchen (z. B. Marvel Rivals).
- **msync (PR #1)** ist auf 11.18 portiert. winecx bringt ein eigenes msync mit, der Patch greift dort nicht.
  Klären, ob der 11.18-Weg noch gebraucht wird. Unter winecx meldet das Log bei jedem Steam-Start
  `msync: up and running` (Test vom 28.10.), also ist dessen eigenes msync aktiv. Beide haben denselben Fehler beim
  Thread-Ende (unten „Engine-Arbeit“). Für winecx behebt ihn `enginefix` (Stück B).

## Engine-Arbeit (ab 0.3.x, seit 2.11.)

Der Nutzer hat am 2.11. entschieden: Wichtige Engine-Verbesserungen kommen in 0.3.x, sobald etwas eindeutig nicht läuft,
nicht erst mit 0.4. Deshalb ist die Arbeit in Stücke geschnitten. Jedes lässt sich für sich mergen, und bei jedem steht,
ob es ein App-Release braucht oder über die Profil- bzw. Komponentenliste zu den Spielern kommt.

- **Stück A, Overwatch** (Zweig `claude/engine-04-overwatch`): `GameAnalysis` (DXMT zuerst), `LaunchHealth` (kein
  „läuft“ ohne Fenster), die Testschalter. **Braucht ein App-Release (0.3.x).** Über die Profilliste allein geht es
  nicht: 0.3.0 wertet bei „nur DirectX 12“ das `graphics` eines Profils gar nicht aus. Das `notYet` im Profil fällt über die
  Profilliste weg, sobald der Live-Test grün ist **und** das 0.3.x mit diesem Stück draußen ist. Vorher liefe Overwatch
  unter 0.3.0 wieder auf D3DMetal.
- **Stück B, `enginefix`** (Zweig `claude/engine-04-703c49`, auf Stück A): msync-Fix und Downmix als eigene Komponente.
  **Braucht einmal ein App-Release** (`Engine.installEngineFix`, eine 0.3.0 kennt die Komponente nicht und lässt sie
  liegen). Danach kommen neue Stände allein über die Komponentenliste: ein neuer Patch, ein Lauf von `enginefix.yml` auf
  `main`, der nächtliche `components.yml`. Workflow und Patches können auch vor dem App-Release nach `main`: Das Release
  entsteht dann schon, und `sources.json` führt es als `optional`.
- **Stück C, Control** (Zweig `claude/engine-04-control`, auf Stück A): DX12-Programm erkennen, Programmwahl,
  Epic-Profile beim Start. **Braucht ein App-Release (0.3.x).** Das Control-Profil
  (`epic.calluna`, `gog.2049187585`) kommt über die Profilliste, wirkt aber erst mit diesem Release: 0.3.0 startet
  Epic-Spiele ohne Profil und kennt `Control_DX12.exe` nicht.

### Control startet nicht (Epic, GOG; Stück C)

Befund vom 2.11. (Nutzer, Release 0.3.0): Epic startet `Control.exe`, ein kleiner Starter, der an `Control_DX11.exe`
übergibt. Direkt nach „Using feature level D3D_FEATURE_LEVEL_11_0“ kommt ein Seitenfehler auf Adresse 0. Das passiert auf
DXMT und auf DXVK, ein Fenster erscheint nie. Laut Mac-Quellen läuft Control nur als `Control_DX12.exe` mit D3DMetal
(`docs/recherche/mac-kompatibilitaet.md`). D3DMetal stand nicht auf der Leiter, weil `GameAnalysis` gar kein
DirectX fand: Die Renderer liegen in DLLs, die sie nicht ansieht.

Gebaut:

- `GameAnalysis`: Programme neben dem des Stores, die DX12/D3D12 bzw. DX11/D3D11 im Namen tragen, zählen als
  DirectX-12- und DirectX-11-Weg. `d3d12Program` merkt sich das DX12-Programm. Control gilt damit als DirectX 11 + 12.
- `GameProgram`: welches Programm startet. Zuerst die Wahl in den Optionen, dann das Profilfeld `executable`, dann auf
  D3DMetal das DX12-Programm, sonst das des Stores. Nur für Epic und GOG, die Nightforge selbst startet. Epics
  Anmeldeparameter gehen mit, ein anderes Programm läuft in seinem eigenen Ordner. `wine.log` meldet
  „<Spiel> starts Control_DX12.exe on d3dmetal instead of Control.exe“.
- Optionen: D3DMetal ist seit de1f146 (koordinierende Session) für jedes DX11-Spiel wählbar und dessen letzter Weg, sobald
  es eingerichtet ist. Live: `Control_DX11.exe` läuft darauf. Wer D3DMetal ausdrücklich wählt, bei dem bekommt Unreal
  `-dx12` und Unity `-force-d3d12`, und die Erklärzeile sagt, was D3DMetal zeichnet. Für Epic- und GOG-Spiele mit 2 bis 4 Programmen gibt es die Zeile „Programm“ (Automatisch oder eines
  davon).
- Die D3DMetal-Frage kommt auch, wenn das Profil D3DMetal nennt und das Spiel ein eigenes DX12-Programm hat.
- Epic-Spiele starten jetzt mit ihrem Profil (`epic.<namespace>`, der Namespace aus `Epic/library.json`). Davon
  profitiert auch Sonic Mania, dessen `iniSettings` (Vollbild) bisher nie angewendet wurden.
- Profil Control: `graphics: d3dmetal`, für Epic und GOG. `profiles.json` hat den neuen `generated`-Stempel, damit die
  Kopie im Build die ältere Online-Liste schlägt. Beim Merge nach `main` gibt es dort einen Konflikt, weil der
  nächtliche Lauf `profiles.json` neu schreibt. Dann einfach neu bauen lassen.
- Die Leiter selbst bleibt, wie sie war (D3DMetal ohne Argumente). So behalten Wukong und The Last Caretaker ihren
  bestätigten Weg.
- `LaunchHealth` (eigener Commit, lässt sich allein übernehmen): Bisher fing ein Spiel mit geänderter Leiter von vorn an.
  Wächst die Leiter nur am Ende (D3DMetal als letzter DX11-Weg), behält das Spiel jetzt, was es gelernt hat. Ohne das
  wäre jedes DX11-Spiel einmal auf DXMT zurückgefallen, auch eines, das DXVK gelernt hatte.

Live-Test (der Nutzer setzt die Grafik vorher auf „Automatisch“): Control (Epic) starten. Ist D3DMetal nicht
eingerichtet, kommt erst die Frage danach. Dann muss `Control_DX12.exe` auf D3DMetal laufen, siehe die Zeile in
`wine.log`. Danach die GOG-Fassung. In den Optionen prüfen: Grafik bietet D3DMetal, die Zeile „Programm“ zeigt
Control, Control_DX11 und Control_DX12. Sonic Mania (Epic) startet jetzt im Vollbild.

Offen: die Programmwahl für Steam (die Startoption mit `%command%` in `localconfig.vdf`). Control gibt es bei Steam
ohnehin als Mac-Version.

### Overwatch hängt beim Start

Befund vom 1.11.: `Overwatch.exe` läuft ohne Fenster bei 0 % CPU (Steam-Fassung, auf `/Volumes/Nightforge Games`).
Laut `docs/recherche/engine-crossover26.md` liegt es nicht an einer alten Engine (4.7.3 enthält CrossOver 26.3 und
Wine 11.17, der Mac hat macOS 27.0.1). Am 2.11. aus Dateien und Einstellungen gefunden:

- **Overwatch lief nur auf D3DMetal (behoben).** `Overwatch.exe` importiert nur `Overwatch_loader.dll`, und erst die
  importiert `d3d11.dll`/`dxgi.dll`. Der Ordner `D3D12/D3D12Core.dll` (Agility SDK) hat `GameAnalysis` „nur DirectX 12“
  sagen lassen, bevor sie die Loader-DLL ansah. Folge: Die Leiter war `['d3dmetal']`, ohne DXMT oder DXVK, und die
  Optionen boten keine Grafikwahl. Jetzt zählt das Agility SDK erst am Ende dazu: Overwatch ist DirectX 11 + 12, die
  Leiter ist DXMT → DXVK → D3DMetal. Test in `tests/GameAnalysisTest`.
- **Der Hänger galt als „läuft“ (behoben).** D3DMetal schreibt keine FPS-Zeilen, also zählten 180 s Laufzeit als
  Beweis. Gespeichert war `confirmed: true`. Jetzt zählen die 180 s nur, wenn der Vorhang für ein Spielfenster gesunken
  ist (`LaunchHealth.verdict(…, showedPicture:)`). Ein Start ohne Fenster bleibt unbestätigt. Er schaltet aber auch nicht
  weiter, das wäre der nächste Schritt (unten bei „Später“).
- **Kandidat msync:** Im winecx-Baum `e0aa380` steht in `alert_fd` unter msync eine msync-Objektnummer.
  `pthread_exit_wrapper` (`dlls/ntdll/unix/thread.c`) schließt sie trotzdem mit `close()`. Damit schließt jeder Thread
  an seinem Ende eine fremde Datei des Prozesses mit dieser Nummer. Liest das Spiel danach aus einem solchen Archiv, schlägt
  das fehl. Wurde die Nummer inzwischen von einer Pipe belegt, wartet der Lesevorgang für immer: 0 % CPU. Den Fix bringt
  Stück B (`enginefix`). Ob das Overwatch trifft, zeigt erst der Test.
- **Kandidat D3DMetal unter Rosetta:** D4Mac fand den hängenden Thread der Blizzard-Spiele in `os_sync_wait_on_address` in
  Apples `libd3dshared.dylib`. Mit DXMT ist D3DMetal nicht im Spiel.
- **Live-Tests vom 2.11. abends** (Plan und Auswertung im Notizordner, `overwatch-engine-04.md`): A (DXMT mit msync),
  B (DXMT ohne msync) und der nächtliche Spieletest (23:46, DXMT mit msync) **hängen gleich**. Es kommt keine Grafikzeile
  ins Log, der Grafikweg ist also nicht schuld. Der Windows-Hauptthread wartet in `NtWaitForAlertByThreadId` auf eine
  Sperre. Ein Thread wartet auf ein Objekt, mit msync über `msync_wait_objs`, ohne msync über `server_select`, also nicht
  msyncs Schuld. Vier Threads wurden angehalten erzeugt und nie fortgesetzt. D3DMetals Rosetta-Deadlock (D4Mac,
  `libd3dshared`) ist es nicht: Die Wartestelle liegt in Wines `ntdll.so`, und D3DMetal ist nicht geladen.
- **Abgleich mit Recall** (AsherJN/recall, CX-26.3-Wine mit DXMT, läuft mit Overwatch): Recall setzt bei jedem Start
  `WINE_SIMULATE_WRITECOPY=1` (CW Hack 22996: `NtProtectVirtualMemory` meldet Write-Copy-Seiten wie Windows, das
  prüfen Anti-Tamper) und `CX_HACK_FILESYSTEM_TYPE=1` (CrossOver-Hack 5870: kein NTFS). Dazu kommen
  `CX_ACTIVE_GRAPHICS_BACKEND=dxmt` und `d3d12,nvapi64,nvngx` aus. Beide Hacks stecken in unserem winecx-Baum, nur
  schaltet sie nichts ein. In CrossOver tut das vermutlich die nicht freie Kompatibilitätsdatenbank. Recall startet
  außerdem über Battle.net statt Steam. Seine Wine-Patches betreffen Ruckler, Maus und msync, nicht den Start.
- **Nächster Live-Test E** (mit dem Nutzer): die beiden Hacks über das Profilfeld `environment` bzw. den Testschalter
  `gameEnvironment` (unten). Hängt es weiter, `winedbg --command "bt all"` im Hänger: Das zeigt die Windows-Stapel,
  die `sample` unter Rosetta nicht auflöst. Bis dahin bleibt `notYet` im Profil (`profiles/mac.json`).

### Engine-Fixes (`enginefix`)

Eigene Unix-Module über die gepinnte Runtime 4.7.3, nach dem Vorbild von `gamepad.yml`:

- `engine/patches/winecx-ntdll-msync-alert-fd.patch`: `if (!do_msync()) close( data->alert_fd );`. Genauso macht es Recall.
- `engine/patches/winecx-winecoreaudio-spatialmixer.patch`: die fünf Commits aus Wine 11.21 (199ae1d, d20f6c7,
  3e29c36, 8cf6408, 0c61795). Sie passen unverändert, nur mit versetzten Zeilen. Danach gleicht `coreaudio.c` dem aus
  11.21, bis auf CrossOvers Mikrofonfreigabe und winecx' eigene Zeitstempel.
- `scripts/build-enginefix.sh`: baut zuerst die Wine-Werkzeuge nativ, dann nur `ntdll.so` und `winecoreaudio.so` für
  x86_64. Die Configure-Flags sind die von dappermint, das Minimum ist macOS 26.0. Danach prüft das Skript die Ergebnisse
  gegen die Originale der Runtime: exportierte Symbole (D3DMetal patcht ntdll beim Laden), Bibliotheken und rpaths.
- `.github/workflows/enginefix.yml` (macos-26): prüft den SHA-256 der Runtime und baut. Unter Wine mit `WINEMSYNC=1`
  läuft dann `engine/probes/msync-thread-exit.c`, 64- und 32-bit: 1000 Threads enden, 1000 Dateien müssen lesbar
  bleiben. Zum Vergleich läuft die Probe auch auf dem Original. Danach packt der Workflow das Paket mit
  `originals.sha256` und das Quell-Asset (LGPL §4: unveränderter Baum, Patches, Skript, Workflow, NOTICE). Jeder Lauf lädt
  das Paket als Artefakt hoch, ein Release gibt es nur von `main` (`enginefix-winecx4.7.3-N`).
- `components/sources.json`: `enginefix` (kind `graphics`, `optional` bis zum ersten Release).
- App: `Engine.installEngineFix` legt die Module nur über genau die Dateien, für die sie gebaut sind (Version
  `4.7.3-N` zur Engine, SHA-256 aus `originals.sha256`). Die Originale bleiben als `*.engine` liegen und kommen zurück,
  wenn das Paket fehlt oder nicht passt. Das Paket steht im `EngineBuild`, also hält `EngineRollback` den Stand davor
  zurück, falls ein Spiel mit dem Fix abstürzt. `installMsync` (das msync-Paar der Gcenx-Engine) läuft unter winecx nicht
  mehr, sonst hielte es die `*.engine`-Kopien für seine. Tests in `tests/EngineLayoutTest`.
- **Lokal nicht gebaut:** Den Bau der Wine-Quellen auf diesem Mac hat die Rechteprüfung abgelehnt. Der erste Push des
  Zweigs baut und prüft im CI, ohne etwas zu veröffentlichen. Erst danach mergen.
- `graphics.yml` reagiert nur noch auf seine eigenen Patches (`dxmt-*`, `wine-*`, `winebus-11.18-*`) statt auf ganz
  `engine/**`. Der Merge dieser Änderung baut einmal ein neues Grafikpaket. Das wäre durch die neuen Patches unter
  `engine/` ohnehin passiert.
- **Live prüfen, sobald das Release da ist:** Steam-Anmeldung, ein DX12-Spiel auf D3DMetal (Wukong), ein DXMT-Spiel, ein
  32-Bit-Spiel, Overwatch. Dazu ein 5.1/7.1-Spiel am DENON, einmal mit „7.1 Wide“ und einmal mit Stereo: Ist der Hall weg?

### Engine-Tests (versteckte Schalter, ohne Knopf in der App)

Gelesen einmal pro App-Start, also danach Nightforge neu starten. Nur setzen, wenn kein Spiel läuft.

- `defaults write io.github.lordhayne.nightforge msync -bool false`: Wine ohne msync (`WINEMSYNC=0`). Beim nächsten Start
  beendet Nightforge die laufende Wine-Sitzung samt Steam, weil eine Sitzung nur mit oder nur ohne msync laufen kann.
  `wine.log` meldet dann „msync off from this Wine session on“. Zurück mit
  `defaults delete io.github.lordhayne.nightforge msync`.
- `defaults write io.github.lordhayne.nightforge gameEnvironment.steam.2357570 -dict WINE_SIMULATE_WRITECOPY 1
  CX_HACK_FILESYSTEM_TYPE 1 CX_ACTIVE_GRAPHICS_BACKEND dxmt` setzt Wines und CrossOvers eigene Schalter für **ein**
  Spiel (`gameEnvironment.<Schlüssel des Spiels>`, hier Overwatch auf Steam). Gelesen wird das bei jedem Start, ein
  Neustart von Nightforge ist nicht nötig. Es geht vor das Profilfeld `environment`, erlaubt sind dieselben Namen
  (`GameEnvironment.allowed`). Über Steam startet Steam dafür neu. `wine.log` meldet „<Spiel> starts with … through
  Steam“. Zurück mit `defaults delete io.github.lordhayne.nightforge gameEnvironment.steam.2357570`.
- `defaults write io.github.lordhayne.nightforge wineDebug -string "+loaddll,+timestamp,+pid,+tid"` hängt Wine-Kanäle an
  `WINEDEBUG` an. Erlaubt sind nur Buchstaben, Ziffern und `+ - , _`. Steam startet dafür neu. Das Log wächst damit schnell,
  danach `defaults delete io.github.lordhayne.nightforge wineDebug`.
- `defaults write io.github.lordhayne.nightforge wineSandbox -bool true`: Wine startet in einer macOS-Sandbox, die
  Anmeldedaten sperrt (unten bei „Aus dem Code-Audit“ › Wine-Sandbox). Steam startet dafür neu. Zurück mit
  `defaults delete io.github.lordhayne.nightforge wineSandbox`.

### Profilfeld `environment` (Zweig `claude/engine-env-0f3a`, 3.11.)

- `GameEnvironment`: Wines und CrossOvers eigene Schalter pro Spiel. Erlaubt sind nur `WINE_SIMULATE_WRITECOPY`,
  `CX_HACK_FILESYSTEM_TYPE`, `CX_ACTIVE_GRAPHICS_BACKEND`, `CX_GRAPHICS_BACKEND` und `WINE_LARGE_ADDRESS_AWARE`, mit
  kurzen, schlichten Werten. Nie `DYLD_*`, Pfade oder Leerzeichen, weil ein Profil aus der Online-Liste kommt.
- Wege ins Spiel: Über Steam landen die Schalter in Steams Umgebung (`Engine.prepareLaunchEnvironment`), Steam
  startet neu, wenn sie sich ändern. Das nächste Spiel ohne sie nimmt sie wieder weg. Epic- und GOG-Spiele bekommen
  sie direkt (`Launcher.launchDirect`). Dazu kommt der Testschalter oben.
- `profiles.yml` lehnt anderes ab (`build_profiles.environment_allowed`, dieselbe Liste wie die App, ein Test prüft
  den Gleichlauf).
- **Braucht ein App-Release.** Das Overwatch-Profil bekommt den Eintrag erst, wenn Test E läuft. Er kommt dann über die
  Profilliste, wirkt aber erst mit diesem Release.
- `LibraryModel`: eine Zeile, das Argument `environment:` beim bestehenden Aufruf von `prepareLaunchEnvironment`.

### Später (nicht angefangen)

- Den Pin auf winecx 4.7.4 oder 4.8.1 heben, wenn dappermint/winecx-gptk#24 geklärt ist. Dabei in `enginefix.yml`
  (`WINECX_COMMIT`, `RUNTIME`, `RUNTIME_SHA256`) und in `gamepad.yml` mitziehen.
- Ein Issue bei dappermint: der `alert_fd`-Fix, dazu die Bitte um eine 11.21-Lane oder den Downmix.
- Selbstheilung bei einem Hänger ohne Fenster: Läuft ein Weg drei Minuten ohne Bild und beendet der Spieler das Spiel,
  könnte Nightforge zum nächsten Weg gehen. Heute bleibt der Weg nur unbestätigt.
- Den msync-Fix in `wine-11.18-msync.patch` nachziehen, falls die Gcenx-Engine `wine` bleibt (eine Änderung dort baut
  über `graphics.yml` ein neues Grafikpaket).

## DirectX 12 (D3DMetal)

- **Echtes DX12-Spiel aus den Top 100 testen.** Gemessen ist bisher nur der Wukong-Benchmark
  (D3DMetal 69 FPS im Schnitt). Kandidaten: Elden Ring (offline, ohne EAC),
  Resident Evil 4, Monster Hunter Wilds, Street Fighter 6, Space Marine 2, Planet Zoo 2.
- **Bekannte Stolpersteine** (Stand 1.11., der Wukong-Benchmark ist das Beispiel):
  - `ROSETTA_ADVERTISE_AVX=1` lässt Wukong abstürzen. Das Profil sagt `avx: false`; bei anderen Spielen lernt Nightforge es
    nach einem „illegal instruction“ von selbst (`LearnedFixes.setNoAVX`).
  - Frame Generation schaltet sich beim ersten Start von selbst ein und stürzt das Spiel sofort ab (Absturzbericht: 0 s,
    GameThread). Das Profil dreht `InsertFrame` in `GameUserSettings.ini` auf 0, und der Start wird nach dem Absturz von
    selbst wiederholt (`LibraryModel`, nach `Engine.applyFileEdits`). Die zwei Abstürze vom 1.11., 21:42 und 21:44, sind
    genau das: der erste ist dieser, der zweite (88 s nach dem Start, `InsertFrame=0`) ein anderer. Für andere Spiele gibt
    es das nur mit einem eigenen Profileintrag: Name und Datei der Einstellung sind je Spiel anders.
  - Unreals Warnung „Known issues with graphics driver“: D3DMetal 3.0 meldet AMD 30.0.15.1233, das Unreal auf seiner
    Sperrliste hat, und das „Yes“ beendet das Spiel. `Engine.clearUnrealDriverDenyList` leert die AMD-Liste in
    `Saved/Config/Windows/Hardware.ini` vor jedem Start eines Unreal-Spiels auf D3DMetal. Noch nicht live bestätigt.
- **MTL_HUD** erscheint unter D3DMetal 4.0 nicht (Metal-4-Backend?).
- **Import von Apples Toolkit (Audit M4, 3.11.):** Apple signiert nur `D3DMetal.framework` und `libd3dshared.dylib`,
  weder die Windows-DLLs noch die DMGs (geprüft an `Game_Porting_Toolkit_4.0_beta_3.dmg` und der Evaluation-DMG darin:
  „not signed at all“). Deshalb nimmt der Import nur die DLLs, deren SHA-256 in `D3DMetalSupply.windowsFiles` steht
  (3.0, 4.0b3), und nichts daneben. Eine neue Toolkit-Version wird abgelehnt, bis ihre Liste dort steht:
  `shasum -a 256 redist/lib/wine/x86_64-windows/*.dll` aus Apples DMG. Die Werte für 3.0 stammen aus der
  Kopie, die Nightforge am 2.11. aus `Game_Porting_Toolkit_3.0.dmg` importiert hat (`License.rtf` stimmt mit der App
  überein). Gegen die DMG selbst geprüft ist bisher nur 4.0b3. Eine Datei, die während des Wartens in „Downloads“
  ankommt, wird nicht mehr still importiert, sondern angeboten wie eine schon vorhandene, und Nightforge hüpft im
  Dock. Das ist live noch zu prüfen. Importe von vor dieser Prüfung werden nicht nachgeprüft.
- **Lizenz:** GPTK 4.0b3 erlaubt die Weitergabe nur nicht-kommerziell und unverändert. Nightforge muss
  kostenlos bleiben, D3DMetal.framework wird nur ganz und unverändert weitergegeben. Kein Streaming-Dienst
  damit (2C). Apple kann die Lizenz jederzeit beenden (Abschnitt 5). Plan B wäre dann, dass Nightforge das
  Toolkit aus Apples eigenem Download holt, wie die kommerzielle App Apara es macht.

## Steam und Start

- **Steam-Fragen vor dem Start** (EULA, Controller-Firmware „ShowInterstitials“, Startoption bei
  Mac-Spielen mit mehreren Optionen wie Project Zomboid): Sie erscheinen, wenn der Spieler in Nightforge
  „Bestätige im Steam-Fenster“ klickt. Ein Klick ist für den Nutzer okay. Wünschenswert wäre, die
  Standard-Startoption automatisch zu wählen. Kandidat: `steam://launch/<id>/<Typ>` (Steam kennt die Typnamen
  Default, Option1…). Ein Versuch blieb ohne Wirkung, lief aber, während schon ein Dialog offen war.
  Also ungeklärt.
- **„Aktualisieren & spielen“ zeigt die ganze Zeit 0 %.** OxyRail am 31.10.: 5,8 GB in 4,5 Minuten, der Knopf
  stand bis zum Schluss auf „Aktualisiert … 0 %“. Steam schreibt `BytesDownloaded` im appmanifest erst am Ende
  (während des Updates `StateFlags 1030`, `BytesDownloaded 0`). `LibraryScanner.updateState` las nur das
  Manifest. Gebaut am 3.11. auf `claude/update-progress-1a4e06` (von 29e458a), nur mit Tests geprüft:
  `content_log.txt` nennt nur Anfang („update started : download 0/5809679168, … stage 0/7151561606“) und Ende,
  dazwischen nur „Current download rate“. Steam entpackt das Update nach `steamapps/downloading/<appid>` (die
  Bibliothek des Spiels, auch auf dem Stick) und verschiebt es am Ende ins Spiel („starting commit from
  …\downloading\3907790“); `BytesToStage` im Manifest ist dieselbe Zahl wie „stage“. Jetzt misst
  `updateState` wie bei Erstinstallationen den belegten Platz in diesem Ordner gegen `BytesToStage`
  (`stagedSoFar`; nicht bei Steam für Mac, das alles vorab belegt). Steam setzt die Dateien vorab auf volle
  Größe („preallocated 476 files (6799 MB)“), Wine lässt sie auf APFS dünn (macOS hat kein `posix_fallocate`),
  also zählt nur Geschriebenes; geprüft mit einer 100-MB-Datei, ein Viertel beschrieben → 25 %. Der Knopf geht
  nie zurück, wenn sich der Ordner beim Verschieben leert (`UpdateProgress`), und unter ihm steht nach ein paar
  Sekunden die Geschwindigkeit wie bei Downloads (4.4): „19 MB/s · noch 4 Min. – Steam aktualisiert das Spiel
  zuerst, …“. Offen: auf einem exFAT-Laufwerk wäre eine vorab volle Datei gleich belegt (dann sofort ~95 %).
  Live: ein Steam-Spiel mit wartendem Update (Bibliothek zeigt „Update“) mit „Aktualisieren & spielen“ starten:
  Prozent steigen gleichmäßig bis 99 %, nach einigen Sekunden die Geschwindigkeit darunter, dann startet das
  Spiel von selbst (OxyRail tat das am 31.10. auch). Der Grund, warum das Update
  am Nachmittag dreimal scheiterte, war ein hängendes Steam (Log stand seit 16:46). Die Erkennung dafür liegt auf
  dem GOG-Zweig (557c2c2).
- **Angemeldete Steam nimmt keine Befehle mehr an** (31.10., OxyRail, Branch `claude/gog-7-3-e69c3b`): Seit etwa
  16:46 kam kein `-applaunch` mehr in `console_log` an. Nightforges Client endete trotzdem nach 0,2–0,3 s (macOS-Log,
  wie bei den funktionierenden Starts), und `configstore_log`/`appinfo_log` liefen weiter. Gebaut (`SteamCommands`):
  War Steam angemeldet und fertig gestartet und loggt 15 s lang kein `ExecCommandLine` für den Start, folgt „Steam
  reagiert nicht – wird neu gestartet …“: `wineserver -k` ohne `-shutdown` (nur wenn kein Windows-Spiel läuft;
  ein Client-Update läuft vorher zu Ende), stiller Neustart, Anmeldung abwarten, Start noch einmal. Live prüfen,
  sobald Steam wieder so hängt. Ursache des Hängers selbst offen (letzte Zeile: `SlowJSMethodCall Messaging.PostMessage`).
- **„Zuletzt gespielt: gerade eben“ direkt nach dem Hinzufügen** (1.11., Wukong-Benchmark über „Kostenlos
  hinzufügen“): Steam setzt `LastPlayed` in `localconfig.vdf` schon beim Installieren auf jetzt (21:34:25, noch
  während des Downloads). Nightforge zeigt das an und reiht das Spiel bei „Weiterspielen“ ein. Gebaut am 3.11.
  auf `claude/small-fixes-1a4e06` (von 29e458a), nur mit Tests geprüft: Ohne Spielzeit zählt ein `LastPlayed`
  nicht als gespielt, wenn es von vor dem Ende des Downloads stammt (`LastUpdated` im appmanifest, beim
  Benchmark 21:40:28) oder das Spiel noch gar nicht installiert ist (`LibraryScanner.played`). Ein kurzes
  Spielen danach liegt später und zählt auch mit 0 Minuten; mit Spielzeit zählt es immer. Live: ein kostenloses
  Spiel über „Kostenlos hinzufügen“ laden: während und nach dem Download „Noch nie gespielt“, nicht bei
  „Weiterspielen“; einmal kurz starten und beenden: „Zuletzt gespielt: gerade eben“.
- **steam-shutdown.sh** hält jeden Prozess unter `\steamapps\common\` für ein Spiel, auch in
  Test-Prefixen, und holt Nightforge dann nach vorne.
- **Steam-Anmeldung zwischen den Steams.** Steam für Mac und die Windows-Steam melden sich gegenseitig ab
  („Session Replaced“). Beobachtet wurde auch: Steam hängt, beendet sich nicht oder drängt sich nach vorne.
  Ursache und Plan (Steam für Mac in die Ersteinrichtung, Regeln für den Wechsel): `docs/PLAN-STEAM-FUER-MAC-EINRICHTUNG.md`.
  Wechselregeln (`SteamSwitch`) und Erststart-Baustein (`MacSteamPrep`) sind gebaut, aber noch nicht live getestet.
  Offen: die Haken in `Setup.swift` (nach setup-speed) und die Anzeige in `SetupView` (nach design-setup-home).

### Engine-Rückfall (3.3, Branch `claude/engine-rollback-02a61e`)

- **Nach dem Zusammenführen mit 0.2 (GameID):** `EngineRollback` merkt sich Spiele unter der Steam-App-ID, und
  `LaunchHealth.confirmedWays` liest `launchHealth.<id>`. Beides auf die neue ID umstellen.
- **Nur Abstürze eines Spiels zählen.** Startet Steam selbst mit der neuen Engine nicht, greift der Rückfall nicht.
- **Datum der ersten gehaltenen Engine:** Es ist der Tag, an dem 3.3 zum ersten Mal lief, nicht der Tag, an dem
  diese Engine kam.

## Mac-Versionen

- **Windows-Fallback** hat noch nie wirklich ausgelöst (keine Mac-Version ist bisher abgestürzt).
- **Speicherplatz vor Updates prüfen.** Steam für Mac hat Batman bei einem Auto-Update geleert und
  dann wegen Platzmangel pausiert. Nightforge zeigt das an und bietet „Weiter laden“
  (`Engine.unpauseDownload`). Vor einem *Download* prüft Nightforge den Platz inzwischen (`SpaceCheck`, UX-Roadmap 4.1);
  vor *Updates*, die Steam von selbst startet, noch nicht (Steams `BytesToStage`, `UpdateState.pending`).
- **Ein Laufwerk, das es nicht mehr gibt** (Nutzer, 1.11.). Sonic Mania lag auf dem alten Stick „Spiele test“, und
  Nightforge wartet, dass er wieder angesteckt wird („schließ es an, um es zu spielen oder zu verschieben“). Ist der Stick
  weg, kaputt oder neu formatiert, hängt das Spiel fest. Es gibt kein „Vergessen“, und Deinstallieren braucht das
  Laufwerk.
  - Vorschlag: In Einstellungen › Speicher bei einem nicht angeschlossenen Laufwerk „Laufwerk vergessen“, mit
    Rückfrage. Seine Spiele gelten danach als nicht installiert und lassen sich neu laden, auf den Mac oder ein anderes
    Laufwerk. Dafür die Einträge bei Steam (`libraryfolders.vdf`), Epic (legendary) und GOG (`installed.json`) entfernen.
    Spielstände liegen im Prefix auf dem Mac und bleiben.
  - Auf der Spielseite zusätzlich „Neu laden“, das die alte Kopie vergisst.
- **Platzprüfung, was noch fehlt** (Nutzer, 1.11.: Control von Epic und The Evil Within 2 von GOG zugleich, 44 GB frei).
  Laufende und wartende Downloads zählen mit (`SpaceCheck.committed`), der Mac behält 10 GB, unter 20 GB fragt Nightforge
  vorher, und ein knappes Laufwerk zeigt eine ruhige Meldung (676d87f). Seit 3.11. zählt ein Download mit dem, was er
  auf der Platte belegt (`Game.installedSize`: Epics und GOGs Dateien kommen gepackt, Steam entpackt mehr), nicht mit
  dem, was herunterkommt. Offen:
  - Epic- und GOG-Updates beim Start („Aktualisieren und spielen“) prüfen keinen Platz: Ihre Größe kennt Nightforge
    vorher nicht (`pendingUpdate` ist 0). legendary und gogdl könnten sie nennen.
  - Steam für Mac belegt die ganze Größe eines Spiels gleich zu Beginn (`MacSteamProgress`). Ein laufender Download
    dort zählt trotzdem mit seinem Rest, also womöglich doppelt. Am echten Download prüfen, ob der freie Platz sofort
    fällt; dann für Mac-Downloads von Steam nichts mehr anrechnen.
  - `EpicTest` und `GOGTest` liefen für die neue Größe nicht (am 3.11. hing `ps`). Sie haben noch keinen Fall für
    einen laufenden Download.

## Controller

- **Die meistgenutzten Controller durchgehen** (Nutzer, 1.11.). In Nightforge ist bisher nur der DualSense live
  bestätigt. Prüfen:
  - Welche Controller verbreitet sind: Xbox Series/One, DualShock 4, DualSense Edge, Switch Pro und Joy-Cons, 8BitDo,
    Steam Controller, günstige XInput-/DirectInput-Pads, MFi.
  - Was macOS' GameController je Modell meldet: Tastennamen, Symbole (beim DualSense ist ☰ nur `capsule.portrait`),
    Akku, Licht, Vibration, Gyro.
  - Wie sie in Windows-Spielen unter Wine ankommen (winebus/SDL, Xbox-IDs).
  - Was Nightforge daraus braucht: Hinweis-Symbole je Stil, Belegung (Nintendo hat A und B vertauscht), Tests.
  - Am besten zuerst als Recherche, dann mit den Geräten, die der Nutzer oder Bekannte haben.
- **DualSense in Windows-Spielen auf winecx:** OxyRail funktioniert seit dem Xbox-360-ID-Patch (PR #8).
  Noch offen: Hotplug auf winecx (auf 11.18 geprüft: SDL nimmt den Pad nach Aus/An wieder auf) und weitere
  Spiele (reine XInput-Spiele, Unreal, DirectInput-Spiele).
- **Preis des Xbox-360-ID-Patches:** Windows-Spiele mit eigener DualSense-Unterstützung zeigen Xbox-Symbole,
  adaptive Trigger, Lichtleiste und Bewegungssensor fehlen. Ein besserer Weg bräuchte beides: den rohen Pad
  für solche Spiele und einen XInput-Pad für den Rest (`engine/patches/winebus-*-xbox360-ids.patch`).
- **Mac-Ports mit dem synthetischen Xbox-Pad** (`ControllerCompatibility`): bisher nur mit Batman geprüft.
  Andere alte Ports (Feral, Aspyr) wären gute Kandidaten.
- **PS-Taste im Spiel** (`SteamGuideButton`, 29.10.): Vor jedem Steam-Start schaltet Nightforge „Guide-Taste
  fokussiert Steam“ ab (`Controller_CheckGuideButton` in `userdata/<id>/config/localconfig.vdf`), bei Windows-Steam
  und Steam für Mac. So öffnet die PS-Taste außerhalb von Spielen kein Big Picture mehr. Laut steamui (Stand Oktober 2026)
  fragt Steam die Einstellung im Spiel nicht ab und reicht den Druck ans Overlay weiter. Ungeprüft: was die Taste
  in einem Windows-Spiel tut (dort gibt es kein Overlay, `gameoverlayrenderer=d`), und ob das Overlay in
  Mac-Spielen damit noch aufgeht.
- **Pad holt Nightforge nach vorne** (Nutzer, 1.11., „ja unbedingt“, gebaut auf `claude/tv-fullscreen-61ab1e`,
  `InputRouter.wakeIfIdle`): Läuft kein Spiel und ist eine andere App vorne, holt ein frischer Druck (A, B, X, Y, ☰,
  Steuerkreuz) Nightforge nach vorne, wie Big Picture. Nicht während ein Spiel aus der Bibliothek läuft oder startet,
  und nicht über einer anderen App, die sich als Spiel ausweist (`LSApplicationCategoryType` games). Am TV prüfen:
  Safari vorne, Druck auf A, Nightforge kommt; ein Spiel vorne, nichts passiert.
- **Kleines Controller-Overlay** (0.3.0, Branch `claude/tv-fullscreen-61ab1e`, `GameOverlay.swift`; Anlass: Left 4 Dead 2
  hing am 31.10. im Ladebildschirm, „Man würde auf der Couch sitzen und könnte nichts machen und müsste aufstehen.“):
  - **Gebaut:** Beide Sticks drücken (L3 + R3) und 2 s halten. Dann kommt ein ruhiges Panel über das Spiel:
    Weiterspielen (B oder die Sticks noch einmal halten), Spiel beenden (mit Rückfrage) und Zu Nightforge (das Spiel
    läuft weiter). Alles mit PadFocus bedienbar, abgedunkelt statt weichgezeichnet. Die Kombination steht im Panel und
    in Einstellungen › Controller › „Im Spiel“. Ein Pad ohne Stick-Tasten nimmt ☰ + ⧉.
  - **Warum die Sticks:**
    - Die PS-/Xbox-Taste öffnet seit macOS 26 Apples Game Overlay (support.apple.com/105118).
    - Die „Home-Tasten-Ausnahmen“ gelten nur für die App vorne, und das ist das Spiel. Für Windows-Spiele schaltet
      auch winebus die Geste nicht ab, denn dessen SDL bindet kein GameController.framework ein, nur IOKit/HIDAPI.
    - Create/Share trägt auf macOS 27 eigene Gesten: Bildschirmfoto, Aufnahme, „Highlight“ der letzten 15 s
      (Strings von GameControllerSettingsUI). Auf DualSense ist das `buttonOptions`, also ⧉ in „Share + Options“.
    - Die Stick-Tasten tragen keine System-Geste. Nightforge fasst die Home-Taste gar nicht mehr an.
  - **Beenden:** Nightforge weckt den ganzen Prozessbaum, bittet um Ende (SIGTERM) und tötet nach 3 s (SIGKILL), auch
    ein hängendes Spiel. Dazu gehören die Programme im Spielordner und alles, was sie gestartet haben, nie aber
    wineserver, `C:\windows\…`, Steam oder Nightforge (`GameProcesses.targets`). Danach räumt der normale Ablauf auf
    (`watchForGameEnd`, Willkommen zurück). `wineserver -k` braucht es dafür nicht.
  - **Technik:**
    - Den Pad liest Nightforge auch im Hintergrund (`GCController.shouldMonitorBackgroundEvents`). Das ist erst seit
      macOS 15.5 verlässlich, und Nightforge setzt es erst beim ersten verbundenen Controller (SDL sah sonst
      Abstürze). Im Spiel wertet `InputRouter` nur das Halten aus (`reach`), sonst nichts.
    - Das Panel ist nicht aktivierend (`.nonactivatingPanel`, Level `.screenSaver`, `.canJoinAllSpaces` und
      `.fullScreenAuxiliary`), also kein Space-Wechsel. Hat ein Spiel den Bildschirm exklusiv belegt (Schild-Fenster),
      kommt Nightforge zusätzlich nach vorne.
    - Windows-Spiele hält Nightforge solange mit `SIGSTOP` an. Begründung: Wines Pad-Treiber läuft in
      `winedevice.exe`, XInput liefert beim Weiterlaufen den aktuellen Zustand statt der Zwischendrücke, und der Ton
      setzt aus. Mac-Spiele laufen weiter und reagieren mit, weil GameController ihnen die Drücke sonst gesammelt
      nachliefert.
  - **Am Fernseher prüfen:**
    - Kommt L3 + R3 halten im Windows- und im Mac-Spiel an (DualSense und Xbox)? Löst macOS dabei nichts aus
      (Game Overlay, Bildschirmfoto)? Was macht das Spiel in den 2 s mit den Stick-Drücken?
    - Liegt das Panel über dem Spiel, ohne Space-Wechsel? Steuert der Pad nur das Panel?
    - Ist ein pausiertes Spiel wirklich still, und läuft es nach Weiterspielen ohne verschluckte oder doppelte
      Eingaben weiter? Was macht Steam (Spielzeit, „läuft“)? Ein Online-Spiel nicht lange pausieren.
    - Spiel beenden bei einem hängenden Spiel (Left 4 Dead 2 im Ladebildschirm): Nach höchstens ~3 s ist es weg,
      danach kommt Willkommen zurück. Bleibt Steam dabei heil?
    - Zu Nightforge: Bibliothek vorn, das Spiel läuft weiter, „Zum Spiel wechseln“ führt zurück.
- **Hängendes Spiel von selbst erkennen** (später): Das Spiel lebt, zeichnet aber keine Bilder mehr (Bildzeilen von DXMT
  oder dem Vulkan-Layer stehen) oder sein Fenster antwortet nicht. Dann bietet Nightforge das Overlay mit „Spiel
  beenden“ an, ohne zu raten, wenn ein Ladebildschirm nur lange dauert.
- **Großes Nightforge-Overlay** (nach 0.3.0, der Nutzer will es „später schön ausarbeiten“): Uhrzeit, Controller-Akku,
  laufende Downloads, Bildschirmfoto, Lautstärke, Leistungsanzeige, Bildratenbegrenzung.
- **Zwei Controller, lokaler Koop mit Split-Screen** (Nutzer, 29.10.): ungeprüft. Erwartet wird:
  - Windows-Spiele: winebus/SDL gibt jeden Pad als eigenen Xbox-360-Pad weiter (XInput-Plätze 1–4).
  - Neuere Mac-Spiele mit dem GameController-Framework können mehrere Pads von sich aus.
  - Offen ist, ob macOS bei alten Mac-Ports mit dem synthetischen Xbox-Pad (`ControllerCompatibility`) mehr als einen Pad nachbildet.
  - Nightforge selbst hängt sich an jeden Pad (`InputRouter`), beide steuern die Oberfläche.

  Testen mit zwei Pads (DualSense + Xbox oder zwei DualSense):
  - je ein Windows- und ein Mac-Spiel mit lokalem Koop aus der Bibliothek;
  - ob jeder Spieler seinen eigenen Pad bekommt und die Reihenfolge stimmt;
  - ob ein zweiter Pad, der mitten im Spiel eingeschaltet wird, noch ankommt;
  - ob der Controller-Test der Ersteinrichtung bei zwei Pads sinnvoll bleibt (er zeigt nur einen).
- **L1/R1 zwischen Startseite und Bibliothek** (Nutzer, 31.10., gebaut auf `claude/tv-fullscreen-61ab1e` – die TV-Session
  hat es mitgebaut, weil sie `InputRouter` für das Overlay ändert; `InputRouter.section`): L1 führt immer zur Startseite,
  R1 immer zur Bibliothek, auch von einer Spielseite; kein Umschalten, die Richtung steht fest. In einem Sheet, im
  Download-Panel, bei der Ersteinrichtung und im Spiel tun sie nichts. Die Chips „L1“/„R1“ (Xbox „LB“/„RB“) neben
  „Startseite | Bibliothek“ erscheinen nur mit verbundenem Controller. Der Sprung um fünf Spiele ist weg, L2/R2
  bleiben, ☰ öffnet seit 1.11. die Optionen (`docs/ENTWURF-CONTROLLER.md`); der Controller-Test sagt „Geht zur Startseite/Bibliothek“. Live bestätigt (1.11.). Am Gerät noch ansehen:
  Chips und Beschriftungen im Controller-Test, mit DualSense und Xbox-Pad.
- **Suche mit dem Controller** (Nutzer, 31.10., Idee, noch nicht besprochen): Heute erreicht man die Suche nur mit der
  Tastatur (⌘F oder /). Möglichkeiten:
  - Buchstaben-Sprung ohne Tippen: Bei Sortierung „Name“ springt eine Taste plus Stick oder Steuerkreuz von A nach B
    nach C, eine Buchstabenleiste am Rand zeigt, wo man ist. Klein, wie in Konsolen-Bibliotheken.
  - Eigene Bildschirmtastatur aus Glas: Eine Taste öffnet die Suche, zum Beispiel ⧉ Create/Ansicht. Eine kompakte
    ABC-Tastatur, die man mit dem Steuerkreuz bedient. A tippt, B löscht, die Treffer laufen live mit. Weil
    „rdr2“/„bg3“ schon gehen, reichen meist 2–3 Buchstaben.
  - Sprachsuche über das Mac-Mikrofon (Taste halten und Spielnamen sagen, `SFSpeechRecognizer`): bequem, braucht aber
    eine Freigabe von macOS. Eher später.
  - Empfehlung: Buchstaben-Sprung und Bildschirmtastatur zusammen, Sprache später.

## Darstellung und Leistung

- **MetalFX im Vulkan-Layer** (Retina für Vulkan-Spiele, PR #1): Die Metal-Seite ist geprüft, in einem Spiel noch nicht.
- **MoltenVK 1.4.2** (PR #1) ist in keinem Spiel getestet. 1.4.0 scheiterte an Shadern von No Man's Sky.
- **D3DM_MAX_FPS** wirkt jetzt über Steams Start-Umgebung. Prüfen, ob die gelernte Bildratengrenze
  (FramePacing) auch für D3DMetal-Spiele greift. Für DXMT arbeitet sie: OxyRail schreibt seine Bildrate ins
  Log, hält 60 und bleibt deshalb bei 60 (28.10.). Ein Spiel, das 60 nicht hält, ist noch nicht durchgelaufen
  (es braucht mindestens drei volle Spielminuten am Stück, bevor das Limit auf 40 geht).
- **Automatik nach Hardware im Spiel prüfen** (`Hardware.swift`, PR #31): Nur mit Tests geprüft.
  An einem externen Monitor ohne Retina muss MetalFX in den Optionen „Automatisch (Aus)“ zeigen, das Spiel ohne
  Hochskalieren starten (im Log keine `MetalFX`-Zeile bzw. kein `metalSpatialUpscale` in `dxmt.conf`) und am
  MacBook-Bildschirm wieder mit. Im Stromsparmodus muss das Bildraten-Limit bei 40 (120 Hz) starten und die
  gelernte Grenze für normales Spielen unverändert bleiben (`framePacing.*` mit `"lowPower":true` getrennt).
- **DXMT-Shader-Cache über einen Neustart** (`~/Library/Caches/Nightforge/dxmt`, PR #1): Der Cache füllt sich
  (4,9 MB nach OxyRail), aber seit dem 26.10. hat der Mac nicht neu gestartet. Nach dem nächsten Neustart prüfen,
  dass `shaders_320.db` noch da ist und die erste Spielminute weniger hakt.
- **Einrichtung direkt nach dem Download** (`LibraryModel.prepare`, PR #1): Ist ein Windows-Spiel fertig geladen,
  installiert Nightforge im Hintergrund, was es braucht (winetricks-Pakete aus dem Profil, Wine Mono für .NET),
  damit der erste Start ohne „Setting up the game …“ losgeht. Mit einem echten Download nie geprüft. Ein Spiel
  mit Profil-Paketen oder .NET laden, warten bis es fertig ist, dann Play: kein Einrichtungs-Hinweis, und
  `winetricks.log` im Prefix nennt die Pakete schon vor dem Start.
- **Steam-Browser im Hintergrund beim Spielen** (`SteamPriority.swift`, PR #1): Das Skript läuft bei jedem
  Spielstart (`steam-priority.sh`), geprüft ist es nur mit nachgestellten Prozessen. Während eines Spiels mit
  `ps -axo pri,command | grep -i steamwebhelper` nachsehen, ob die Browser-Prozesse auf Priorität 4 stehen und
  nach dem Spiel zurückgehen.
- **TV-Modus an einem echten TV** (`GameDisplay.swift`, PR #6): Mit einem Monitor am MacBook bestätigt (Fenster
  wandert beim Anstecken, Windows-Spiel öffnet dort, Hauptbildschirm kommt danach zurück). Am TV noch offen: die
  Erkennung am Namen (`Candidate.isTV`, Liste der Marken) und das Vollbild des Launchers.
- **Hinweis „Spielt auf: …“** neben Play, wenn ein externer Bildschirm das Spiel bekommt, damit man weiß, wo es
  aufgeht. Gebaut am 3.11. auf `claude/small-fixes-1a4e06`, nur mit Tests geprüft: eine Zeile direkt unter Play
  (Spielseite und Bühne auf Home, nur bei installierten Spielen) „Spielt auf: LG TV SSCR2“, sobald es mehr als
  einen Ort gibt (ein gespiegelter Bildschirm zählt nicht extra). Genannt wird der Bildschirm mit Nightforges
  Fenster, also auch das MacBook, wenn der TV dran ist und das Fenster zurückgeschoben wurde
  (`GameDisplay.destination`). Aktualisiert beim An- und Abstecken und wenn das Fenster wandert, sonst nichts
  gemessen. Eine Zeile wie die anderen unter Play, kein eigener Fokus: Das Pad steht auf der Seite ohnehin auf
  Play, die Zeile direkt darunter. Live: MacBook mit TV/Monitor: Zeile mit dem Namen des TVs; Fenster aufs
  MacBook ziehen: Name des MacBooks; Kabel ab: Zeile weg; gespiegelt: keine Zeile.
- **Ziel fürs Sofa (28.10.):** MacBook anstecken, Controller einschalten, alles läuft, ohne Maus und Tastatur.
  - **Vollbild am Fernseher** (31.10., Branch `claude/tv-fullscreen-61ab1e`, `GameResolution.swift`): Overcooked 2
    (Epic, Unity) ging am gespiegelten TV als kleineres Fenster auf. Unity und Unreal merken sich die Auflösung des
    letzten Starts, und unter Wine wird Vollbild in einer anderen Größe als der des Bildschirms zum Fenster. Gebaut:
    Vor jedem Start eines Windows-Spiels (Steam, Epic, GOG über `launchDirect`) bekommt ein Spiel im Vollbild die
    Größe des Hauptbildschirms, wie Wine ihn zeigt (Punkte, mit Retina-Modus Pixel; gespiegelt der Master).
    Unity (Modus 0/1) über die Registry: `Screenmanager Resolution Width/Height` und „Use Native“ = 1, nur Werte, die
    das Spiel selbst angelegt hat, Schlüssel aus `<Spiel>_Data/app.info`, per regedit. Unreal (`FullscreenMode`
    0/1) in `GameUserSettings.ini` unter `AppData/Local/<Projekt>/Saved/Config/Windows*/` (bzw. `Documents/My Games`).
    Fenster-Modus bleibt, und solange das Spiel läuft, wird nichts angefasst. `GameDisplay` sieht einen Spiegel-Satz
    als einen Bildschirm (`newMain`, `Candidate.mirrors`) und stellt beim Spiegeln nichts um. Am Fernseher prüfen:
    - Overcooked 2 am gespiegelten TV: Vollbild? In `Logs/wine.log` steht vor dem Start
      `[nightforge] Full screen Overcooked2: 1512×945 → 1920×1080`.
    - Steht die Zeile da und es bleibt ein Fenster, merkt sich Overcooked 2 die Auflösung auch im eigenen,
      verschlüsselten Spielstand (`SettingsOptions`, `Meta_SaveFile.save`). Dann einmal im Spielmenü per Controller
      Vollbild bzw. 1920×1080 wählen und sehen, ob es beim nächsten Start bleibt.
    - Offene Frage: Der einzige Start war am 31.10. um 16:34 (laut `wine.log`), und die 1512×945 wurden beim Beenden
      um 16:35 geschrieben. War der TV da schon gespiegelt angeschlossen, kam das MacBook-Raster von Wine selbst.
      Dann sieht die laufende Wine-Sitzung (Steam im Hintergrund) den angesteckten TV nicht, und erst ein Neustart der
      Sitzung hilft. Prüfen: TV anstecken, ein Unity-Spiel mit „Use Native“ starten (20 Minutes Till Dawn) und
      danach in `user.reg` nachsehen, ob 1920×1080 drinsteht.
    - Ein Unreal-Spiel (Palworld) am TV, danach zurück am MacBook: wieder bildschirmfüllend 1512×982?
    - **Gespeicherte Auflösung in eigenem Format** (1.11., Profilfeld `resolution`, `GameResolution.savedFitted`):
      Ein Profil sagt, wo ein Spiel seine Auflösung speichert, entweder als Zeile mit Werten
      (`fields: {width, height, fullscreen}`, gezählt ab 0) oder in einer .ini (`section`, `keys`). Vor dem Start
      bekommt das Spiel die Größe des Spielbildschirms, aber nur bei Vollbild in einer Größe, die der Bildschirm
      nicht hat. Ein Fenster oder eine vorhandene Größe bleibt. Erster Eintrag: Mafia II (`mac.json` 50130, auch
      gog.1816059595), `AppData/Local/2K Games/Mafia II/Saves/videoconfig.cfg`, `0 0 1512 982 1 0 0 1`. Am TV prüfen:
      Mafia II nur am TV startet in 1920×1080, im Log `[nightforge] Full screen videoconfig.cfg: 1920×1080`.
    - **Frische Wine-Sitzung bei geänderten Bildschirmen** (1.11., `GameDisplay.wineSessionStale`): Wines Zwischenspeicher
      hatte im Spiegelbetrieb noch das MacBook als eigene Primär-Quelle (Altlast der Sitzung). Eine frische Sitzung
      sieht nur den DENON (winecx' `macdrv_get_adapters` überspringt Spiegel). Am TV prüfen: Der erste Start nach dem
      Anstecken zeigt kurz „Steam startet …“, danach läuft Overcooked 2 randlos in 1920×1080. Mafia II hat sich in der
      alten Sitzung 3024×1964 gemerkt (`videoconfig.cfg`): Prüfen, ob es nach der frischen Sitzung von selbst auf
      1920×1080 geht, sonst einmal in seinen Optionen wählen.
    - Spiegeln mit dem MacBook als Master: Spiele laufen in MacBook-Größe, der TV zeigt sie skaliert. Im Spiegelmodus
      wird auch der Launcher nicht von selbst Vollbild, weil `GameDisplay.place` nur beim Verschieben umschaltet.
  - **Zurück aus dem Spiel wie bei einer Konsole** (31.10., gleicher Branch, `GameBackdrop.swift`): Am TV sah man nach
    dem Spiel den Mac-Schreibtisch, bis Nightforge nach 4–7 s wiederkam. Nightforge blendet sich beim Spiel nicht mehr
    aus („Launcher ausblenden“ und „Offen lassen“ verhalten sich jetzt gleich). Hinter dem Spiel liegt eine ruhige
    Seite „<Spiel> läuft …“, unter allen normalen Fenstern und in jedem Schreibtisch-Space des Spielbildschirms. Sie
    kommt schon beim Übergeben an das Spiel. Das Spielende meldet der Prozess selbst (`DispatchSource`, kqueue); die
    Seite zeigt sofort „Zurück zu Nightforge …“, und eine Sekunde später ist Nightforge vorn (lief das Spiel unter
    einer Minute, nach 3 s, falls ein Launcher übergibt). A/Return tun bis dahin nichts. Der Hauptbildschirm bleibt
    nach dem Spiel der Spielbildschirm, solange Nightforges Fenster dort ist; zurück erst beim Verschieben des Fensters
    oder Beenden, also kein Umstellen der Bildschirme zwischen zwei Spielen. Am Fernseher prüfen:
    - Spiel beenden (Windows über Steam, Epic und GOG, ein Mac-Spiel): kein Schreibtisch, „Zurück zu Nightforge …“, dann
      „Willkommen zurück“, Controller steuert sofort. Wie lange dauert es bis Nightforge vorn ist?
    - Der Wechsel von der Seite in Nightforges Vollbild-Space ist eine kurze Space-Animation. Stört sie, wäre der
      nächste Schritt ein randloses Fenster über den ganzen TV statt macOS-Vollbild (`GameDisplay.place`), dann liegt
      Nightforge im selben Space wie das Spiel. Das ist ein größerer Umbau, ungetestet nicht angefangen.
    - Beim Start: Statt des Schreibtischs die Seite „<Spiel> läuft …“, bis das Spiel zeichnet?
    - Menüleiste/Dock: Ist der TV Hauptbildschirm, kann nach dem Spiel kurz das Dock über der Seite erscheinen.
    - Am MacBook allein: Nightforges Fenster liegt hinter dem Spiel, beim Beenden ist es sofort da, die Seite deckt nur
      den Schreibtisch ab. Ein Spiel im Fenstermodus hat die dunkle Seite drumherum statt des Schreibtischs.
    - GOG-Spiele (Mac über `launchGOGMac`, Windows über `launchDirect`): dasselbe beim Beenden.
  - **Vorhang beim Start und Ende** (1.11., Wunsch des Nutzers nach dem Valheim-Test: beim Start der Schreibtisch, am
    Ende kurz der Schreibtisch und Steams Fenster). Gebaut in `GameBackdrop.swift`:
    - Dieselbe Seite wird zum Vorhang über allem (Ebene knapp unter dem Overlay, alle Spaces, auch Vollbild-Spaces),
      als eigener Ladescreen: das Nightforge-N mit seiner blauen Lichtnaht (pulsiert sanft, nur die Naht, nicht bei
      „Bewegung reduzieren“), darunter Spielname und „Wird gestartet …“ bzw. „Zurück zu Nightforge …“, auf der Nacht
      der App mit dem Hintergrundbild des Spiels ganz schwach dahinter. Aufwendigere Animationen später.
    - Er kommt, sobald das Spiel an seinen Store geht, für Steam, Steam für Mac, Epic und GOG
      (`LibraryModel.raiseCurtain`). Er sinkt hinter das Spiel, sobald dessen App vorne ist und ein Fenster ab 640×360
      zeigt, eine Sekunde später (`GameProcesses.showsWindow`).
    - Eine Rückfrage von Steam, ein Fehler oder ein Start, der nicht klappt, nehmen ihn weg. Zeigt ein laufendes Spiel
      60 s lang nichts, fragt das Overlay „<Spiel> startet nicht?“: Weiter warten, Zu Nightforge, Spiel beenden.
    - Am Ende ist der Vorhang sofort da („Zurück zu Nightforge …“), auch schon bei „Spiel beenden“ im Overlay.
      Steam für Mac wird gleich ausgeblendet, danach kommt die Spielseite des Spiels.
    - Nachtest 1.11. (erweitert) und behoben: Beim Start sprang Nightforges Vollbildfenster aufs MacBook, weil das
      Umsetzen des Hauptbildschirms die Ursprünge verschiebt und das Fenster seine Koordinaten behält. Der TV wird
      jetzt Hauptbildschirm, bevor Nightforge dort ins Vollbild geht (`GameDisplay.place`). Nach jedem Umsetzen kommt
      das Fenster auf seinen Bildschirm zurück (`keepWindow`), notfalls aus dem Vollbild und wieder hinein. Vorhang und
      Overlay liegen auf dem Spielbildschirm (`GameDisplay.gameScreen`), nicht beim Fenster. Der Titel wanderte, weil
      das Pulsieren das erste Layout mitanimierte; jetzt ist nur die Naht animiert. Der Vorhang hatte unten einen
      Streifen (`NSHostingView` passte die Fenstergröße an den Inhalt an); jetzt `sizingOptions = []`.
    - Nachtest 1.11. ~03:15 und behoben:
      - **Falsche App vorne:** Seit macOS 14 kann nur die App vorne die Front weitergeben. Fragt eine App von hinten,
        wird das ignoriert, und macOS gibt die Front der nächsten App im Stapel, hier der Claude-App. Unity baut sein
        Fenster für Vollbild neu auf und verliert dabei die Front. Jetzt sinkt der Vorhang erst, wenn das Spiel eine
        Sekunde vorne ist (`LibraryModel.curtainStep`). Ist ein anderes vorne, holt sich Nightforge (unter dem
        Vorhang) die Front und gibt sie an das Programm des Spiels mit Fenster weiter (`handFocus`). Danach achtet es
        8 s darauf und hebt den Vorhang wieder, wenn eine andere App dem Spiel die Front nimmt. „Zum Spiel wechseln“
        geht denselben Weg statt über `activate(options:)`.
      - **Flackern beim Beenden:** Bisher ging der Vorhang hoch, das Overlay-Panel blieb bis zu 5 s mit „Wird
        beendet …“ darüber. Nach dem Spielende senkte `playing()` den Vorhang, sobald ein Prozess aus dem Spielordner
        nachhing oder neu auftauchte; man sah Nightforge, dann ging er wieder hoch. Das Ausblenden lief nach 0,9 s
        auf Zeit, auch wenn der Space-Wechsel noch lief. Jetzt bei „Spiel beenden“: Vorhang hoch und festgehalten,
        Panel sofort weg, dann das Ende. Der Vorhang kommt nach jedem Space-Wechsel wieder nach vorne und geht erst,
        wenn Nightforges Fenster auf dem gezeigten Space vorne ist (`GameBackdrop.hide(once:)`). Hängt er doch, geht
        er nach 20 s.
    - Nachtest mit 9319ca3 und behoben:
      - Mafia II öffnete beim ersten Start hinten. Sein Fenster lag in einem anderen Space, und die Fenstersuche sah
        nur den gezeigten. Jetzt reicht ein Fenster in irgendeinem Space für die Übergabe; gesenkt wird erst, wenn es
        vorne auf dem gezeigten Space ist.
      - „Willkommen zurück“ blitzte zwischen zwei Vorhängen auf. Es kommt jetzt erst, wenn der Vorhang weg ist.
        Während des Space-Wechsels wird der Vorhang laufend nach vorne geholt.
      - Nach 3 s zeigt der Vorhang eine ruhige Zeile, was passiert: den Start-Hinweis („Neuer Start mit WineD3D …“,
        Shader beim ersten Start) bzw. „Warte auf das erste Bild …“.
    - Nachtest mit 645cca8 (Testbuild f03398f, Deckel offen, erweitert, TV Hauptbildschirm) und behoben:
      - „Zu Nightforge“ im Overlay und der Weg aus dem Spiel brachten die Claude-App nach vorn, das Spiel blieb
        dahinter. Nightforge bat bisher nur höflich um die Front (Launch Services), und das verliert gegen jede App mit
        einem Fenster auf dem gezeigten Space. Jetzt holt es sich die Front ausdrücklich (`NSApp.comeToFront`, also
        `activate(ignoringOtherApps: true)`, laut SDK „activates regardless“), dazu Launch Services für den
        Space-Wechsel. Das Overlay-Panel geht erst danach weg. Das Spiel bekommt beim Weiterspielen alle Fenster nach
        vorn (`.activateAllWindows`).
      - Sonic Mania (Epic) lief im Fenster: Das Spiel schreibt beim ersten Start `windowed=y` (848×480). Neues Profil
        `epic.45e7cf3c49054f2fb20b673d9b0ae69e` mit `windowed=n` in `Sega/SonicMania/Settings.ini`, vor jedem Start.
      - Vorhang-Flackern bei Sonic: Ursache nicht belegt, kein EOS-Overlay im Prefix. Ein anderes Windows-Programm
        vorne (Launcher, Overlay, Dialog, nicht Steam) zählt jetzt als Seite des Spiels. Ging der Vorhang einmal wieder
        hoch, sinkt er erst nach 2,5 s statt 1 s Front. Jedes erneute Hochgehen steht in `wine.log`
        („Curtain up again for … in front“), so zeigt der nächste Test, wer die Front nahm.
      - „Spiel beenden“ im Overlay galt bei Sonic als Fehlstart. Jetzt merkt sich LaunchHealth das Beenden durch den
        Spieler (`playerQuit`): Der Startablauf, Steams Log beim nächsten Start (`review`) und der Rückfall von der
        Mac- auf die Windows-Version lernen daraus nichts, egal nach wie vielen Sekunden und mit welchem Exit-Code.
    - Test am Monitor (ASUS MG278, 2560×1440, Deckel zu, Testbuild baff1f5) und behoben:
      - Einmal Fenster, nach erneutem Anstecken Vollbild: Nightforge macht einen Monitor nie selbst zum Vollbild.
        Wahrscheinlich griffen zwei Umschaltungen ineinander (`place` und `leaveFullScreenOffTV` bei derselben
        Bildschirm-Meldung; die zweite sah das Fenster noch auf dem Weg hinaus und schaltete wieder hinein). Jetzt
        läuft jedes Umschalten über `setFullScreen`, das eine laufende Umschaltung abwartet.
      - Entscheidung des Nutzers: Ein Monitor kommt beim ersten Mal ins Fenster. Danach gilt pro Bildschirm, wie der
        Spieler es dort zuletzt hatte (grüner Knopf, ⌃⌘F; `TVSettings.fullScreen`, gleiche Ablage wie der Ton). Ein
        TV startet im Vollbild, solange nichts anderes gemerkt ist.
      - Mafia II im Fenster oben links: `videoconfig.cfg` stand noch auf 1920×1080 vom TV. Das Profilfeld passte nur
        Größen an, die der Bildschirm nicht hat. Wine stellte den Modus auf 1920×1080 um (4 Bildschirmwechsel unter
        dem Vorhang in `wine.log`) und gab ihn zurück, als das Spiel die Front verlor. Jetzt bekommt ein Spiel im
        Vollbild immer die Größe des Bildschirms, auf dem es startet. Ein Fenster bleibt ein Fenster.
      - Warum die Claude-App dabei vorne stand, ist offen; ein erneutes Hochgehen des Vorhangs steht nicht im Log.
        `handFocus` aktiviert Nightforge jetzt ohne Launch Services, dessen Aktivierung nach der Übergabe kommen
        und dem Spiel die Front nehmen konnte.
    - Am Fernseher prüfen: Valheim (Mac) und Overcooked 2 (Windows) starten und beenden, ohne dass der Schreibtisch
      oder Steams Fenster zu sehen ist. Kommt das Spiel nach dem Vorhang ohne schwarzes Bild? Ein Spiel mit Steam-Frage
      (EULA): Der Vorhang geht weg, die Frage ist zu sehen.
  - **Ton aus dem Fernseher** (31.10., gleicher Branch, `GameAudio.swift`): Beim Live-Test blieb der Ton auf den
    MacBook-Lautsprechern, obwohl ein DENON-AVR per HDMI dran war (macOS merkt sich die Ausgabe pro Gerät). Gebaut:
    Zeigt ein Fernseher Nightforge (Fenster auf einem TV, ein AV-Receiver zählt dazu, oder ein Spiegel-Satz mit einem
    externen Bildschirm), geht die Standardausgabe auf dessen HDMI- bzw. DisplayPort-Gerät. Bei mehreren nimmt
    Nightforge das gleichnamige, im Zweifel keins. Umgeschaltet wird nur von den eingebauten Lautsprechern weg, nie von
    Kopfhörern, AirPods, Bluetooth oder USB. Dazu kommt ein kurzer Hinweis „Ton kommt jetzt aus …“. Zurück auf die
    Lautsprecher geht es, wenn Nightforge den TV verlässt und der Ton noch dort ist, wo Nightforge ihn hingelegt hat.
    Wählt der Spieler am TV selbst eine andere Ausgabe, bleibt die, bis der TV weg ist. Wine (winecoreaudio) liest die
    Standardausgabe nur beim Öffnen und hört nicht auf Wechsel: Der Wechsel muss vor dem Spiel liegen, und
    `GameDisplay.enterGame` prüft es vor jedem Start noch einmal. Am Fernseher prüfen:
    - TV mit DENON-AVR anstecken (gespiegelt und erweitert): Ton kommt aus dem Receiver, Hinweis erscheint. Kommt das
      HDMI-Gerät erst Sekunden nach dem Bild, schaltet der Listener auf die Geräteliste nach.
    - Ein Windows-Spiel: Ton da, auch Dialoge? Wine nimmt das bevorzugte Kanal-Layout des Geräts (Audio-MIDI-Setup ›
      „Lautsprecher konfigurieren“), sonst die 8 Kanäle als 7.1. Fehlt etwas, dort „Stereo“ einstellen.
    - Fenster zurück aufs MacBook bzw. TV abziehen: Ton wieder aus den MacBook-Lautsprechern.
    - Am TV in den Systemeinstellungen auf die Lautsprecher stellen: Nightforge schaltet nicht wieder um.
    - Befund 1.11.: Nightforge schaltete doch wieder um, sobald man zu ihm zurückkam. Jeder Fensterwechsel (Spaces,
      Vollbild) galt als „TV verlassen“ und vergaß die Wahl. Jetzt schaltet Nightforge nur zu zwei Anlässen um:
      wenn ein TV angesteckt wird (Bild oder HDMI-Ton kommt dazu) und wenn ein Spiel auf dem TV startet, beide Male
      nur von den eingebauten Lautsprechern aus (`GameAudio.Moment`). Die eigene Wahl gilt bis zum nächsten
      Anstecken. Zurück geht es nur, wenn das Fenster wirklich auf einem Nicht-TV landet oder der TV weg ist.
    - Befund 1.11. mittags: Der Nutzer stellte im Ton-Menü auf die Lautsprecher, der Ton landete wieder am DENON.
      Gespeichert war der Zustand (UserDefaults), aber die Wahl sah Nightforge erst beim nächsten Anlass. Kam der TV
      vor Nightforges Start, war der Zustand „nicht umgeschaltet“, und der Spielstart schaltete zurück. Jetzt hört
      Nightforge auf die Standardausgabe: Was der Spieler wählt, während ein TV da ist, bleibt bis zum nächsten
      Anstecken. Das eigene Umschalten zählt nicht. Als angesteckt gilt nur ein neuer externer Bildschirm oder
      HDMI-Ausgang, nicht der eingebaute beim Aufklappen und nicht einer, der nach unter 30 s wiederkommt.
      Wechselt die Ausgabe während eines Windows-Spiels, sagt das Overlay „Das Spiel spielt seinen Ton bis zum
      nächsten Start über …“: winecoreaudio bleibt beim Gerät, das es beim Start geöffnet hat.
    - Befund 1.11. nachmittags: HDMI ab und wieder an, auf die Lautsprecher gestellt, Mafia II gestartet: wieder
      DENON. Wahrscheinlicher Weg: Beim Umstellen der Bildschirme zum Spielstart verschwand der HDMI-Ton kurz, kam
      wieder und galt als angesteckt; das löschte die Wahl. Seither zählt das nicht mehr (30 s). Dazu die Idee des
      Nutzers: Nightforge merkt sich die Tonwahl pro TV (`TVSettings`, UserDefaults `tvSettings`, Schlüssel die
      UUID des Bildschirms, sonst sein Name). Ein neuer TV bekommt seinen Ton; einer, bei dem der Spieler die
      Lautsprecher gewählt hat, behält sie, auch nach Abstecken, Neustart oder Umstellung; wählt er wieder den
      Receiver, gilt das. Was macOS in den 3 s nach einem Anstecken selbst umstellt, zählt nicht als Wahl.
      Für das Vorhang-Flackern nach dem Wiederanstecken stehen jetzt in `wine.log` die Bildschirmwechsel unter dem
      Vorhang und jede Umstellung des Hauptbildschirms.
    - Befund 1.11. mit Video (Mafia II am ASUS, Spiel beenden): Für etwa ein Bild Nightforges Startseite vor dem
      Vorhang, dann wieder Vorhang, dann die Spielseite. Mit 15 Bildern pro Sekunde sieht man das Gleiten eines
      Space-Wechsels: Der Vorhang glitt mit dem Space des Spiels hinaus, Nightforges Vollbild-Space mit der alten
      Seite herein. Die Ebene war es nicht (der Vorhang lag schon auf `screenSaver − 1`). Ein normales Fenster darf
      nicht in die Vollbild-Spaces anderer Apps. Jetzt ist der Vorhang ein nicht aktivierendes Panel mit
      `.canJoinAllApplications`, das nie Key wird. Auf dem Rückweg ist die Seite fertig (300 ms), bevor Nightforge
      nach vorne kommt, und der Vorhang geht erst, wenn das Fenster auf genau dieser Seite steht
      (`mayUncover`, nach 3 s ohnehin). Live-Test 1.11. abends (Overcooked 2, MacBook, zwei Videos): Der Vorhang
      gleitet trotzdem mit, sobald zwischen Nightforges Vollbild-Space und dem Schreibtisch-Space des Spiels
      gewechselt wird; dabei ist Nightforges Seite zu sehen. `.canJoinAllApplications` und `.stationary` halten ihn
      nicht. Ursache ist der eigene Vollbild-Space von Nightforge: Das Spiel liegt in einem anderen Space (dem
      Schreibtisch oder einem eigenen), also gleitet jede Übergabe. Vorschlag: Nightforges Vollbild ohne
      eigenen Space (randloses Fenster über den ganzen Bildschirm, Menüleiste und Dock per presentationOptions aus,
      solange Nightforge vorne ist), dann liegen Nightforge, Vorhang und Spiel im selben Space. `CaptureDisplaysFor
      Fullscreen` (winecx kennt es) löst das nicht: Die Aktivierung wechselt den Space trotzdem, und die Abschirmung
      läge über Overlay und Vorhang. Die 10-s-Grenze aus e6aa24e ist wieder weg: Sie deckte Nightforges Seite auf,
      wenn das Fenster des Spiels in einem anderen Space lag. In `wine.log` stehen jetzt, wer unter dem Vorhang nach
      vorne kommt, jeder Space-Wechsel unter ihm und beim Senken die Front und die Fenstergröße des Spiels.
      Overlay „Zu Nightforge“ ohne Wirkung: Das Spiel war dabei noch angehalten (SIGSTOP); es läuft jetzt zuerst
      weiter, bleibt die Front trotzdem beim Spiel, steht es in `wine.log`.
      Entscheidung des Nutzers 1.11.: Vollbild ohne eigenen Space (`FullScreen.swift`). Das Fenster liegt über dem
      ganzen Bildschirm, Menüleiste und Dock sind per presentationOptions automatisch ausgeblendet, solange
      Nightforge vorne ist (sie kommen mit der Maus am Rand). Der grüne Knopf (umgeleitet), ⌃⌘F (Darstellung ›
      Vollbild, macOS' eigener Eintrag ist aus) und Esc ohne Zurück schalten es. Das Merken pro Bildschirm bleibt.
      Ein Bildschirmwechsel setzt das Fenster auf die neue Größe; beim Beenden geht es ins Fenster zurück. Live zu
      prüfen: kein Gleiten bei Start und Ende eines Windows-Spiels, ⌘-Tab weg und zurück (Menüleiste und Dock
      wieder aus), Anstecken/Abstecken/Deckel, die Menüleiste am oberen Rand, der Titelbereich ohne Knöpfe.
      Mauszeiger im Spiel: Nur die App vorne kann ihn ausblenden, aber `setHiddenUntilMouseMoves` hält über den
      Wechsel hinaus (Beobachtung des Nutzers). Nightforge ruft es jetzt auf, solange es oder das Overlay noch
      vorne ist (beim Übergeben ans Spiel, beim Schließen des Overlays), wenn zuletzt das Pad benutzt wurde
      (`PadRules.padUsedLast`: in der letzten Minute, Maus seither nicht bewegt). Mitten im Spiel ginge es nur
      über eine private Schnittstelle (CGS „SetsCursorInBackground“) oder indem man die Maus verschiebt, was das
      Spiel als Mausbewegung sieht.
      Live-Test 794b3e4 (1.11. 20:06, MacBook 14", Overcooked 2): kein Gleiten mehr, rein wie raus; Tippzeile da;
      Zeiger in Nightforge weg. Drei Fehler, alle zuerst mit eigenen AppKit-Proben auf dem MacBook nachgestellt:
      1) Vollbild mit Menüleiste, Fenster erst darunter, runde Ecken: Ein Fenster mit Titelleiste drückt macOS
         auf 1512×950 unter den Notch-Streifen, und `.autoHideMenuBar` blendet die Leiste hier nicht aus, weder
         ohne noch nach einem Zeiger-Warp (`menuBarVisible()` sagt trotzdem nein). Jetzt: im Vollbild ohne
         `.titled` (randlos, keine Ecken, ganzer Bildschirm), Menüleiste und Dock per `.hideMenuBar/.hideDock`
         aus. Die Leiste kommt, wenn der Zeiger oben anstößt (`FullScreen.menuBarShown`, dann nur
         `.autoHideDock`), und geht, wenn er sie verlässt und kein Menü offen ist. Der Inhalt bleibt unter der
         Notch (`additionalSafeAreaInsets`), daneben die Nacht der Seite. SwiftUIs Fensterklasse lässt sich
         randlos nicht Key machen; ihre `canBecomeKey/Main`-Antwort ist für Nightforges Fenster erweitert
         (eine eigene Unterklasse per `object_setClass` brachte SwiftUIs KVO zum Absturz). Nach dem Zurück sind
         die Fensterknöpfe neue, der grüne wird wieder umgeleitet.
      2) „Zurück zu Nightforge“ ohne Wirkung: Solange das Overlay-Panel die Tasten hat, meldet `NSApp.isActive`
         ja, obwohl das Spiel vorne ist (Probe: lsappinfo und NSWorkspace sagen „Spiel“). `comeForward()` stieg
         deshalb aus, Nightforge hat nie gefragt. Jetzt `NSApp.isFrontmost`; `leaveGame` holt Nightforges Fenster
         vor und bittet um die Front. Behält das Spiel sie 0,5 s, wird es ausgeblendet (`hide`), und macOS gibt
         die Front der App davor; landet sie bei einer dritten, kommt das Spiel wieder. Das Overlay bleibt bis
         dahin stehen. „Zum Spiel wechseln“ blendet es wieder ein (`handFocus`). Probe: Ausblenden + Einblenden +
         Übergabe zurück klappt; ausgeblendet gibt macOS die Front der App, die vor dem Spiel vorne war.
      3) Zeiger im Ladebildschirm und im Spiel: Probe mit Bildschirmfoto samt Zeiger, Maus ruhig. Er geht nur
         weg, wenn ein Nightforge-Panel die Tasten hat, unter dem Zeiger liegt, Mausereignisse annimmt und ~50 ms
         Zeit hat; dann bleibt er über dem Spiel weg. Ein 1-pt-Panel, ein Panel, durch das die Maus fällt (wie
         der Vorhang), ohne Tasten oder ohne Warten: Er blieb. Jetzt `InputRouter.hidePointerOverGame` (fast
         durchsichtiges Panel über dem Bildschirm des Zeigers, 50 ms Tasten), unter dem Vorhang, sobald das Spiel
         1 s vorne ist, je Mal, dass es nach vorne kommt (vor dem Senken). Beim Hochgehen ist Nightforge noch
         vorne und blendet direkt aus.
      Live zu prüfen: Vollbild-Bild (keine Leiste, keine Ecken, an der Notch nur ein Streifen Nacht), Leiste bei
      Maus oben und wieder weg, ⌘-Tab zurück, Esc/⌃⌘F/Menü, Tasten und Suchfeld im Vollbild; „Zurück zu
      Nightforge“ (zeigt Nightforge, „Zum Spiel wechseln“ bringt das Spiel samt Bild zurück; was `wine.log` dazu
      sagt); Zeiger im Ladebildschirm und im Spiel weg, das Spiel ohne Stocken durch die 50 ms.
      Live-Test 3463b89 (1.11. 21:28): Vollbild, ⌘F, „Zurück zu Nightforge“ (ohne Ausblenden) und der Zeiger beim
      Start bestätigt. Der Zeiger kam noch zurück nach „Zum Spiel wechseln“ und auf dem Rückweg (Overlay ›
      Beenden, ebenso jedes normale Spielende: derselbe Vorhang und `comeBack`) bis in Nightforge. Jedes Wechseln
      der App vorne bringt ihn zurück. Jetzt `InputRouter.hidePointerSoon` (300 ms danach, über Nightforge direkt,
      über einer anderen App mit dem Panel): nach `handFocus` und `bringToFront` ohne Vorhang, bei jeder App,
      die unter dem Rückweg-Vorhang nach vorne kommt, wenn der Vorhang geht, und nach „Zurück zu Nightforge“.
      Live-Test Wukong-Benchmark (1.11. 21:42–22:05, D3DMetal): 1) Unreals Treiber-Warnung (eigenes Fenster des
      Spiels, ~380×330, Ja/Nein) lag unter dem Vorhang. Sie zählte nicht als Fenster des Spiels (ab 640×360), also
      bekam das Spiel nie die Front. Jetzt `GameProcesses.question`: ein normales Fenster des Spiels auf dem
      gezeigten Space, ab 200×100 und kleiner als ein Bild. Das Spiel bekommt die Front, der Vorhang geht
      direkt darunter (`GameBackdrop.makeWay`, normale Fensterebene, fängt Klicks daneben ab), der Zeiger kommt
      zurück, die Statuszeile sagt „Das Spiel fragt etwas – antworte mit Maus oder Trackpad.“, keine
      „startet nicht?“-Frage darüber. Beantwortet und noch kein Bild: Vorhang wieder über alles. Probe (Stand-ins):
      Frage gefunden, auf dem Vorhang sichtbar, Spiel vorne, Zeiger da; danach deckt der Vorhang wieder alles.
      Den Titel kann Nightforge ohne Bildschirmaufnahme nicht lesen, ein Splash ohne Titel gilt also auch als
      Frage (dann steht er auf dem Vorhang, mit Zeiger). Solange die Frage steht, sind Menüleiste und Dock des
      Spiels über dem Vorhang zu sehen. 2) „startet nicht?“ nahm keine Pad-Tasten: Im Code kennt InputRouter die
      Frage (`reach` = .overlay, A geht an das Panel, Steuerkreuz an PadFocus darin), D3DMetal und winecx binden
      GameController nicht ein. Ursache offen; `wine.log` sagt jetzt, wer beim Öffnen des Overlays vorne ist und
      ob das Pad Nightforge danach erreicht („Overlay: the pad reaches Nightforge“).
      Live-Test 2770d2e (22:51): Pad im Overlay geht. Die Warnung kam wieder nicht auf den Vorhang, ohne eine
      Zeile des Vorhangs dazu. Nach „Zu Nightforge“ lag sie über Nightforges Seite, obwohl Nightforge vorne war.
      Das kann nur ein Fenster auf höherer Ebene: Wine hebt topmost-Fenster auf die Floating-Ebene (Layer 3), und
      `question` nahm nur Layer 0. Jetzt Layer 0 bis Modal-Panel (8); Menüs (101) nicht. Offen bleibt, warum
      unter dem Vorhang nicht einmal „In front under the curtain: Nightforge Game“ stand. Dafür schreibt der
      Wächter jetzt seinen Beginn, jedes Ende mit Grund und bei jeder Änderung eine Zeile „Curtain look at …“
      (Prozesse, wer vorne ist mit PID und ob das Spiel, die Fenster des Spiels mit Größe und Layer, Bild,
      asks, Vorhang). „In front under the curtain“ nennt die PID, weil Steams Wine und das Spiel beide
      „Nightforge Game“ heißen.
      Nach 0.3.0 (Entscheidung des Nutzers 1.11. abends: „kleine Anzeigefehler in weiteren Releases“), gebaut am
      2.11. auf `claude/display-polish-03x-1a4e06`, nur mit Tests geprüft, live zu prüfen:
      - **Zeiger** (272061a): `PadRules.padUsedLast` galt nur 60 s nach dem letzten Pad-Druck und nur, solange
        der Zeiger an derselben Stelle stand. Ein längerer Start, ein TV als neuer Hauptbildschirm (verschiebt
        alle Koordinaten) oder Wine, das den Zeiger setzt, machten es falsch, und nichts versteckte ihn, bis das
        Overlay einmal offen war. Jetzt zählt die Hardware: das Pad wurde nach der letzten echten Bewegung,
        dem letzten Klick oder Scrollen von Maus/Trackpad benutzt (`CGEventSource`, HID-Zustand), ohne
        Zeitgrenze. Unter dem Start-Vorhang wird der Zeiger außerdem gleich versteckt, wenn eine andere App als
        das Spiel nach vorne kommt (Steam, Nightforge bei der Übergabe), beim Spiel wie bisher nach 1 s vorne.
        Live: Overcooked 2 mit dem Pad starten (Maus nicht anfassen), auch einen Start über eine Minute (Steam
        frisch, Shader): kein Zeiger auf dem Vorhang (höchstens kurz beim Wechsel der App) und keiner im Spiel,
        ohne das Overlay zu öffnen. Am TV dasselbe. Maus bewegen: Zeiger kommt.
      - **Steam-Frage beim Start** (c43d69e; Wukong 22:51, console_log „waiting for user response to
        ShowInterstitials“): Der Vorhang-Wächter endete, sobald Steam fragte, und niemand hob den Vorhang wieder.
        Jetzt geht der Vorhang für die Frage weg und kommt wieder, sobald sie beantwortet ist und der Start
        weiterläuft (`LibraryModel.steamTurn`, auch für Steams Anmeldung nach einem Neustart); damit sieht der
        Wächter auch danach die Fenster des Spiels (Treiber-Warnung). Steams Fenster wird nach der Antwort
        ausgeblendet wie mit ⌘H (`SteamWindow.hide`, nichts wird beendet), ebenso beim Spielende, falls es noch
        offen ist; vor dem nächsten Zeigen wieder eingeblendet (`SteamWindow.reveal`; winemac blendet die App
        ohnehin ein, sobald Steam ein Fenster zeigt). Live: ein Spiel mit Steam-Frage (Wukong-Benchmark, sonst
        eines mit EULA beim ersten Start): Frage sichtbar, nach der Antwort Vorhang wieder da, in `wine.log`
        „Curtain away for …: Steam asks something“ und „Curtain up again for …: Steam's question is answered“,
        danach weiter „Curtain look at …“. Die Treiber-Warnung liegt über dem Vorhang („Curtain under a window
        … asks something“). Nach dem Spielende kein Steam-Fenster vor dem Vorhang. Bei der nächsten Steam-Frage
        (oder Play, während Steam fragt) kommt Steams Fenster wieder.
      - **Flackern beim Beenden** (e57bc63; Mafia II aus dem eigenen Menü beendet, 2.11.: kurz Nightforge,
        dann Vorhang): Das Fenster des Spiels geht vor seinem Prozess, und winemac gibt die Front dabei nicht ab
        (es deaktiviert eine App ohne Fenster nie). Zu sehen war das Fenster direkt dahinter, Nightforges, bis
        der Prozess weg war und der Vorhang kam; in `wine.log` fehlte zu diesem Ende „In front under the
        curtain“. Jetzt liegt die Seite hinter dem Spiel direkt über Nightforges Fenster, solange eine andere App
        vorne ist (`GameBackdrop.arrange`). Kommt Nightforge nach vorne und das Spiel zeigt noch sein Fenster
        (⌘-Tab, „Zu Nightforge“), geht sie sofort unter Nightforges Fenster; ohne Fenster des Spiels (macOS gibt
        Nightforge die Front, weil das Spiel endet) bleibt sie, bis der Vorhang des Endes kommt, höchstens 3 s.
        Live: Mafia II und Overcooked 2 aus dem Spielmenü beenden: Seite → „Zurück zu Nightforge …“ →
        Nightforge, kein Bild von Nightforge dazwischen (Video mit 30+ fps hilft). Während eines Spiels ⌘-Tab zu
        Nightforge: Nightforge sofort zu sehen, nicht die Seite; zurück ins Spiel per „Zum Spiel wechseln“.
        Ein Spiel im Fenster: drumherum die Seite statt Nightforge.
      - **Ein Vorhang über alle Wege eines Starts** (5d07e59; Control über Epic, 2.11. ~21:00, stürzt auf jedem
        Weg sofort ab; Nutzer: „Ladescreen, Nightforge, hin- und hergespringe – das ist kein sauberer
        Ladescreen“): Zwischen zwei Wegen galt das Ende wie jedes Spielende (`watchForGameEnd`: „Zurück zu
        Nightforge …“, Nightforge nach vorn), der Wächter nahm den Vorhang weg, der nächste Weg hob ihn neu.
        Jetzt bleibt der Vorhang, solange der Start seine ersten Sekunden beurteilt (`judging`, vom Start des
        Spiels bis zum Urteil von `survivesFirstSeconds`) und das Spiel ohne Bild endet. Ein weiterer Weg hebt
        ihn sofort wieder, über alles, was er vorher braucht (Engine, Laufzeiten, Steam-Neustart). Folgt keiner
        mehr („nicht gestartet“, ein Ende, das als das des Spielers gilt, ein Fehler), kommt Nightforge wie nach
        jedem Spiel zurück, auf die Spielseite (`finishJudging`). „Spiel beenden“ im Overlay und ein Ende nach
        einem Bild bleiben normale Enden. Live: Control starten (Pad, Maus ruhig): durchgehend der Vorhang, die
        Zeile wechselt auf „Neuer Start mit …“, kein Nightforge dazwischen; am Ende „Zurück zu Nightforge …“ und
        die Spielseite mit „Control ist nicht gestartet“. In `wine.log` je Weg „Curtain watch for Control ends:
        its processes are gone, the start decides what's next“, kein „the game ended“. Gegenprobe: ein Spiel,
        das läuft, nach 10 s über das Overlay beenden: sofort „Zurück zu Nightforge …“ wie bisher. Zwischen
        Absturz und nächstem Weg vergehen wie bisher etwa 10–20 s (`bringToFront`, `survivesFirstSeconds`).
      - **Spiel, das sein Launcher mit bloßem Namen startet** (37599f2; Control über Epic, 2.11. 21:21, D3DMetal):
        legendary startet `Control.exe` (Launcher, 90 KB), der `Control_DX11.exe -AUTH_LOGIN=… -epicapp=Calluna`
        startet, ohne Ordner in der Befehlszeile. Wine startet jedes Programm mit launchd als Elternprozess, also
        fand Nightforge es auch nicht unter dem Launcher. Mit dem Ende des Launchers galt das Spiel als beendet:
        Vorhang weg, nichts holte das Spiel nach vorn, L3+R3 ging nicht, und das Beenden-Skript hätte die
        Wine-Sitzung unter ihm beendet. Jetzt gehört ein Windows-Programm auch dann zum Spiel, wenn es aus dessen
        Ordner läuft (Arbeitsordner, den Wine als Unix-Arbeitsordner setzt; nicht Windows' oder Steams eigene
        Programme; `GameProcesses.runsFrom`). Eine Regel für alle Stellen: laufende Spiele (Spielzeit, Spielende,
        Play, Overlay), Vorhang und Overlay, `Engine.windowsGameRunning`, `GameResolution`, die Skripte
        `steam-shutdown` und `steam-priority` (per `lsof`). Live: Control (Optionen › D3DMetal) starten: Vorhang
        bis zum Bild, das Spiel kommt nach vorn, L3+R3 öffnet das Overlay, „Spiel beenden“ beendet es, danach
        „Zurück zu Nightforge …“ und die Spielzeit steigt. In `wine.log` kein „Curtain watch for Control ends:
        the game ended“, solange es läuft; „Curtain look at Control“ nennt 1–2 Prozesse.
      - **Pad bei „startet nicht?“** (84b4dca): Ursache weiter offen. Gefunden und behoben: Das Overlay setzte
        die Markierung, indem es die Knöpfe auf dem Bildschirm suchte, eine Runde nach dem Öffnen. Beim ersten
        Öffnen (oft „startet nicht?“) waren sie noch nicht angelegt, nichts war markiert, und das erste A zeigte
        nur, wo man ist. Jetzt sitzt die Markierung per ID auf der sicheren Antwort (`GameOverlay.defaultButton`).
        Neu in `wine.log`: jede Wahl, die beim Overlay ankommt („Overlay: resume on notStarting, … in front“, mit
        „the panel without the keys“, wenn das Panel die Tasten verloren hat) und „Overlay: A with no button
        highlighted“. Live: ein Spiel, das über eine Minute kein Bild zeigt (oder ein Start mit langer
        Shader-Vorbereitung), bei „startet nicht?“ A, B und Steuerkreuz drücken. Geht es nicht: die Zeilen ab
        „Overlay up (notStarting)“ zeigen, ob die Tasten Nightforge erreichen („the pad reaches Nightforge“) und
        bis zum Overlay kommen.
      - **Abfrage von macOS unter dem Vorhang** (Zweig `claude/system-prompt-curtain-1a4e06` von 29e458a, 3.11.;
        Spieletest in der Nacht: Tomb Raider, Mac-Fassung auf dem Stick): macOS fragte nach dem Zugriff auf den
        Wechseldatenträger, das Fenster lag unter dem Vorhang („in front UserNotificationCenter …, asks no“), und
        zweimal kam „startet nicht?“. tccd zeigt seine Abfragen über CFUserNotification, die
        UserNotificationCenter zeichnet, neuere über AuthorizationPromptService; dazu Gatekeeper
        (CoreServicesUIAgent), Bedienungshilfen (universalAccessAuthWarn), Ortung (CoreLocationAgent), Passwort
        und Touch ID (SecurityAgent, coreautha). Zeigt eines dieser Systemprogramme (nach Pfad unter /System)
        ein Fenster auf dem sichtbaren Space, macht der Vorhang Platz wie bei einer Frage des Spiels (darunter,
        über allem anderen), egal wo der Start gerade ist, sagt „macOS fragt um Erlaubnis – antworte mit Maus oder
        Trackpad.“, schließt ein offenes „startet nicht?“ und lässt es nicht kommen, solange gefragt wird. Danach
        Vorhang wieder über allem, bis das Bild kommt. Ist der Vorhang schon unten, bleibt er unten (vorher hob
        ihn die Abfrage als „andere App vorne“ über sie). Der Zeiger wird dabei weder versteckt noch geholt (das
        Panel dafür nimmt die Tasten, auch einem Passwortfeld). Nichts wird bestätigt, keine Einstellung
        geändert. Live: ein Spiel, für das macOS noch fragt (Tomb Raider vom Stick, falls die Erlaubnis noch
        nicht erteilt ist; sonst ein Mac-Spiel auf einem anderen Wechseldatenträger): Abfrage über dem Vorhang,
        die Zeile darunter, kein „startet nicht?“ auch nach über einer Minute; nach der Antwort Vorhang wieder,
        dann das Spiel. In `wine.log` „Curtain under a question of macOS's for …: UserNotificationCenter in
        front“ und „Curtain up again for …: macOS's question is answered“. Nicht live geprüft: auf welcher Ebene
        die Abfrage liegt (der Vorhang geht auf normale Ebene direkt unter sie, das reicht für jede).
    - Wunsch des Nutzers 1.11.: der Vorhang im Look des README-Banners. Die Zeichnung des N (gebürstetes Metall,
      Lichtnaht) und der Nacht liegt jetzt in `BrandArt.swift`; `scripts/render-brand.swift` kompiliert sie mit
      (Bilder dabei byteweise unverändert). Der Vorhang zeichnet das N einmal pro Größe und Backing-Scale, die
      Nacht in einem Viertel der Bildschirmgröße (nur Verläufe). Darunter NIGHTFORGE und der Spielname in
      gesperrten blauen Großbuchstaben; das schwache Spielbild ist weg. Bewegung: Ein Licht läuft an der Naht
      entlang (kleiner Kreis, verschoben, mit der Naht als Maske), mit „Bewegung reduzieren“ atmet die Naht nur.
      Die Statuszeile nennt von Anfang an den echten Schritt (`launchPhase`, „Shader werden beim ersten Start
      vorbereitet …“, „Warte auf das erste Bild …“) und blendet über; die Begründung kommt wie bisher nach 3 s.
      Offen: Die frische Wine-Sitzung nach einem Bildschirmwechsel läuft vor dem Vorhang (der Play-Knopf sagt
      „Steam wird gestartet …“). Den Vorhang früher hochzuziehen würde ein Anmeldefenster von Steam verdecken.
      Beim Zurück steht kein Cloud-Abgleich: Epic/GOG laden danach im Hintergrund hoch (die Spielseite zeigt es),
      Steam meldet nichts.
    - Befund 1.11. (Overwatch, Steam, Stick): `Overwatch.exe` lief ohne Fenster bei 0 % CPU. „Zum Spiel wechseln“
      holte Steams Shop nach vorn, L3+R3 ging nicht, weil Nightforge vorne war (`reach == .app`); beenden ging
      nur von Hand. Offen: Ein laufendes Spiel muss mit dem Pad immer zu beenden sein (L3+R3 auch aus Nightforge
      oder „Spiel beenden“ auf der Spielseite und im ☰-Menü, mit Rückfrage). „Zum Spiel wechseln“ zeigt nie
      Steams Fenster; ohne Fenster sagt Nightforge, dass das Spiel läuft, aber noch kein Bild zeigt, und bietet
      Warten oder Beenden an.

## Anti-Cheat und GeForce Now

- **Store-Suche warnt nicht vor reinen Online-Spielen mit Anti-Cheat** (z. B. Bless Unleashed). Die Sperre
  `antiCheatOnline` braucht Steams Kategorie „Einzelspieler“, die die Store-Suche nicht liefert; in der
  Bibliothek greift sie. Ansatz: `StoreSearch.details` um `categories` erweitern (appdetails, Kategorie 2).
- **GeForce-Now-Link beim allerersten Klick:** Führt er über die Anmeldung, landet man danach auf der
  Startseite statt beim Spiel (getestet 26.10.). Der Erklär-Dialog sagt deshalb, danach noch einmal zu klicken.
  Angemeldet landet der Link direkt auf der Spielseite.
- Anti-Cheat wird nie umgangen. Fortschritt gibt es nur, wenn Entwickler, Epic oder BattlEye macOS/Wine freischalten.

## Abdeckung der Top 100

Übersicht vom 26.10.: https://claude.ai/artifact/TWQ3kkV6W7szsgyPyh6dWp
(Artifact, nur für den Besitzer sichtbar.)

- Etwa 28 Spiele haben eine Mac-Version, etwa 21 laufen wahrscheinlich über Wine, 22 sind durch Anti-Cheat
  blockiert, 9 sind reine DX12-Spiele (jetzt Kandidaten für D3DMetal).
- **Launcher-Spiele** sind ungeprüft: EA app (Sims 4, FC), Rockstar Launcher (GTA V, RDR2),
  Battle.net (Overwatch), REDlauncher (Witcher 3, startet DX12 als Standard).
  - **Rockstar Games Launcher unbedingt testen** (Nutzer, 31.10., „wenn wir Zeit haben“): Geht ein
    Rockstar-Spiel über Steam oder Epic nahtlos, also Launcher-Installation, Anmeldung, Start und Rückkehr zu
    Nightforge, ohne dass der Nutzer den Launcher sieht oder bedienen muss? Bei Epic beachten: Rockstar-Spiele
    erwarten `EpicGamesLauncher.exe` als Elternprozess (siehe Epic-Abschnitt).
  - **Battle.net als eigener Store** (Nutzer, 1.11.: „wird ein Thema für die Zukunft … riesige Anzahl von Spielern“;
    noch nicht anfangen): Overwatch 2, World of Warcraft und die anderen Blizzard-Spiele in der Bibliothek, wie Epic
    und GOG.
    - Mac zuerst: WoW, Hearthstone und StarCraft II gibt es nativ für den Mac (WoW auch für Apple Silicon). Sie
      laufen über die Mac-App von Battle.net, ganz ohne Wine.
    - Overwatch 2 und Diablo IV gibt es nur für Windows, aber auch auf Steam. Prüfen, ob der Steam-Weg reicht oder
      Battle.net unter Wine nötig ist, und wie Blizzards Anti-Cheat unter Wine reagiert.
    - Die Cloud-Recherche „Rockstar, EA, Battle.net, Ubisoft unter Wine“ (1.11.) liefert die Grundlage.
    - Anmelden tut sich der Nutzer selbst, keine Anmeldeversuche durch Sessions.
- **Rocket League:** Die Startoption ohne Anti-Cheat nutzt ein anderes Programm (`RocketLeague.exe`).
  `SteamCatalog.antiCheatOffArguments` übernimmt aber nur Optionen mit demselben Programm. Die Mac-Version ist
  der Stand von 2020 ohne Online-Spiel.
- Übersicht nach DX12- und winecx-Tests aktualisieren (Liste: `ISteamChartsService/GetMostPlayedGames`).

## Mac-Wissen aus Quellen (AGW, Berichte) – Zweig `claude/compat-db-bce7dc`

Entwurf und Regeln: `docs/ENTWURF-BERICHTE.md`. Abdeckung der Top 200: `docs/recherche/mac-abdeckung.md`.

- **In der echten App ansehen** (nur offscreen und mit Tests geprüft): Spielseite eines Windows-Spiels nach unten
  scrollen → „Was andere berichten“ (Bewertungen, Notiz, drei Link-Knöpfe, Pad-Fokus). Ein Spiel ohne
  „Über das Spiel“, das AGW kennt, bekommt den Abschnitt allein. Die Karte „Dieses Spiel“ zeigt bei einem Hinweis
  „Noch kein Profil – zuerst D3DMetal, wie im AppleGamingWiki berichtet“.
- **Control mit dem Hinweis:** D3DMetal kommt nur zuerst, wenn die Analyse DX11 **und** DX12 sieht. Startet Epic
  `Control.exe` (Launcher), hängt das an der Analyse; engine-04 baut dafür das Programmdatei-Feld. Live prüfen, welche
  Leiter Control bekommt (Problembericht-Zeile „Graphics“ nennt „D3DMetal first from AppleGamingWiki“).
- **„Willkommen zurück“:** drei Knöpfe (Lief gut / Mit Problemen / Startet nicht), danach „Bericht teilen …“. Im
  Browser: Sind alle Felder des Formulars gefüllt? Öffnet der alte Problembericht (`issues/new?title=…&body=…`) mit
  dem neuen Vorlagen-Ordner weiter ein leeres Issue? Im Repo das Label `report` anlegen.
- **Nach dem Merge von signed-updates:** `agw.json` in `sign-lists.sh` aufnehmen und `AGWStore.refresh` auf
  `Signature.fetch` umstellen. `profiles.yml`: die Zeilen mit `profiles/profiles.json` im PR-Schritt nehmen
  `profiles/agw.json` mit (`git diff --quiet`, `git add`, `git diff --stat`).
- **Später (nur geplant, Nutzer hat zugestimmt 2.11.): freiwillige, anonyme Spielberichte ohne Konto.** Bedingung:
  erst, wenn die Download-Statistik echte Nutzer zeigt. Vorbild GameHub Lite/BannerHub (über 7.000 Configs per
  „Export Config“ in ein GitHub-Repo, ungeprüft) und EmuReady (Abstimmung, Status „verifiziert“). Unser Gegenstück:
  LaunchHealth kennt pro Spiel den bestätigten Weg, das Wissen bleibt bisher auf einem Mac.
  - Opt-in, ohne Konto, anonym; nur das eine Spiel, keine Bibliotheksliste, kein Name.
  - Inhalt: GameID-Schlüssel, bestätigter oder gescheiterter Weg (Grafikweg, Engine-Version, D3DMetal-Version,
    Profilfelder), Ergebnis (Bild / kein Bild / Absturz), Chipfamilie, macOS- und Nightforge-Version, optional FPS.
  - Zurück in die Profile: Ein Bericht bestätigt oder widerlegt ein Profil; mehrere übereinstimmende machen einen
    Weg zum Standard. Macs sind einheitlich, ein Bericht zählt für fast alle – aber nur für dieselbe Engine-Version.
  - Transport ohne Zugangsdaten in der App (z. B. ein Worker, der in ein Repo schreibt); Entscheidung später.
    Entwurf und Zusammenhang mit `reports.json`: `docs/ENTWURF-BERICHTE.md` › Abschnitt 6.
- **Danach bauen:** `reports.yml` (Berichte prüfen, Labels, schließen) und `scripts/build-reports.py` →
  `profiles/reports.json`, sobald die ersten echten Berichte da sind. MacGamingDB-Anfrage abschicken
  (`docs/recherche/macgamingdb-anfrage.md`), AGW/PCGW-Team kurz informieren (Abruf des ganzen Bestands, „nicht
  kommerziell“).

## Wartung und Community

Ziel: Mac-Gaming gemeinsam voranbringen, keine Konkurrenz und kein Geld. Nightforge soll nicht an einer
Person hängen (Whisky ist 2025 daran gescheitert).

- **Hinweis auf CrossOver.** In der README und in den Einstellungen (Über/Hilfe) erwähnen, dass CodeWeavers
  einen großen Teil der Wine-Entwicklung finanziert und CrossOver für Fortgeschrittene und Support die
  richtige Wahl ist. Freundlich, ohne Vergleichstabelle.
- **Nur geprüfte Komponenten ausliefern.** `components.yml` committet neue Versionen heute direkt ins
  `manifest.json` auf `main`. Besser: ein Bot-PR, den die Tests (`tests/*/run.sh` auf einem macOS-Runner)
  durchlaufen müssen und der erst nach einem kurzen Spieltest gemergt wird. Dazu ein Rückweg: Die vorherige
  Version bleibt im Manifest, und Nightforge kann auf sie zurückfallen (`ComponentStore`).
- **Tests in der CI** laufen seit PR #5 (`ci.yml`: Build, alle `tests/*Test` parallel über `scripts/run-tests.sh`,
  Profil- und Manifest-Prüfung). Von den Python-Tests läuft dort nur `test_build_profiles.py`.
  Offen: dieselben Tests als Pflicht für die Bot-PRs aus dem Punkt darüber. Echte Spiele bleiben Handarbeit.
- **Liegengebliebene Test-Plists aufräumen (macht der Nutzer).** Die Swift-Testreihen schrieben UserDefaults-Domänen
  in das echte `~/Library/Preferences`; jetzt liegen sie im Arbeitsordner jeder Reihe (`tests/Shared/TestDefaults.swift`).
  Übrig sind (Stand 2.11.): 466× `ProfileFilesTest-<UUID>`, 332× `mvt-<UUID>`, 232× `nightforge.engine-rollback-test-<UUID>`,
  61× `nightforge.game-audio-test.<PID>`, 9× `io.github.lordhayne.nightforge.gametest-<UUID>`,
  2× `io.github.lordhayne.nightforge.removal-test-<UUID>` (vom Code-Review-Zweig), je eine
  `io.github.lordhayne.nightforge.removal-test`, `nightforge.duplicate-games-test`, `nightforge.navigation-test`,
  `nightforge.shader-test`, `nightforge.launch-phase-test`, `nightforge.test.oldgame`/`moderngame`/`sdlgame`/`playerchoice`
  und die Standard-Domänen der Testbinaries: `download-rate-test`, `engine-layout-test`, `engine-rollback-test`,
  `gameid-test`, `graphics-preset-test`, `launch-health-test`, `mac-version-test`, `scan-freshness-test`,
  `steam-switch-test`, `store-facts-test`. Ältere Proben ohne Testreihe: `f2w-testA`/`B`/`C`, `nf.test.probe`,
  `local.probe.fullscreen`. Nicht dazu gehören `io.github.lordhayne.nightforge` (die App) und
  `io.github.lordhayne.nightforge.game` (Spiele aus Nightforge). `defaults delete` und `removePersistentDomain` leeren
  eine Domäne nur, die Datei bleibt; also die Dateien selbst löschen, wenn gerade keine Testreihe läuft.
- **Problembericht ausbauen.** `ProblemReport` öffnet schon ein GitHub-Issue. Ergänzen: Komponenten-Versionen,
  Grafik-Layer und Profil mitschicken, Issue-Vorlage im Repo, der Nutzer sieht vorher alles. Nichts automatisch
  senden, kein Tracking. Vorher den Benutzernamen-Befund unter „Aus dem Code-Audit“ beheben.
- **Profile von der Community.** `profiles/` als Ort beschreiben, an dem jeder per PR ein Spiel eintragen kann:
  kurze Anleitung (`CONTRIBUTING.md`), Format erklären, Prüfung per CI (JSON gültig, Felder bekannt).
  Später überlegen, die Profile als offene Liste auch anderen Projekten anzubieten (ähnlich ProtonDB).
- **Fixes an die Ursprungsprojekte zurückgeben.** Kandidaten: DXMT-Patch für Wine 11 (3Shain/dxmt), der
  winebus-Xbox-ID-Patch und msync (Gcenx), die Patches in `engine/patches`. Was dort gemergt wird, müssen wir
  nicht bei jedem Update selbst nachziehen.
- **macOS-Betas früh testen.** Jeden Juni mit der neuen Beta Einrichtung, Steam-Start, ein DXMT-, ein D3DMetal- und
  ein Mac-Spiel durchgehen, damit der September keine Überraschung wird.
- **Ehrlich sagen, was geht.** Eine Liste „geprüft läuft“ in README oder App, alles andere als „probier es aus“.
  Schützt vor Erwartungen, die niemand allein erfüllen kann.
- **Mehr Leute mit Schreibrechten.** Sobald jemand regelmäßig beiträgt, Mitbetreuer aufnehmen. Releases und
  Komponenten-Pakete (`scripts/package-d3dmetal.sh`) so dokumentieren, dass sie nicht nur auf einem Mac gehen.

## Neue Oberfläche (UX-Roadmap, Nacht 26./27.10.) – in der echten App prüfen

Gebaut in PR #27, ein Commit je Roadmap-Punkt (Stand je Punkt in `docs/ROADMAP.md`). Geprüft mit Tests, mit dem echten
`LibraryModel` gegen die echte Bibliothek und mit Offscreen-Renderings – **nicht** per Klick in der laufenden App,
weil die Bildschirmfreigabe abgelehnt war.

- **Navigation mit Maus, Tastatur und DualSense** durchspielen: Startseite ↔ Bibliothek ↔ Spielseite, Esc/B,
  Doppelklick auf nicht installierte Cover, ↑ aus der Leiste und der obersten Rasterzeile in die Knöpfe,
  Filter- und Sortier-Segmente mit dem Pad, Zurück in die Bibliothek an dieselbe Scroll-Position.
- **Live bestätigt am 1.11.:** die Mitteilung „<Spiel> ist bereit zum Spielen“ (Asphalt Legends, Overwatch, Mafia II, Overcooked 2 …), der Download-Ring, das Wachhalten bei einem echten Download (Overwatch, 82 GB über Nacht), „Willkommen zurück“ und das Fehlstart-Sheet.
- **Einmal echt erleben:** Dock-Menü (Rechtsklick aufs Dock-Symbol), Mitteilung „<Spiel> is ready to play“ mit
  „Play“ (macOS fragt beim ersten Mal), `nightforge://play/<id>` und „Add to Applications“ (findet Spotlight die
  App?), „Update & Play“ bei einem echten Update, Download-Ring und Wachhalten bei einem echten Download,
  „Welcome back“ nach einer echten Sitzung (wird die Steam-Cloud-Zeile grün?), das Fehlstart-Sheet, das
  Platz-Sheet.
- **Glas-Look** (`Glass.swift`): Am 27.10. auf dem echten Bildschirm angesehen – der Hintergrund scheint durch, die
  Ränder leuchten, Spielen glänzt bernsteinfarben. „Willkommen zurück“ und die Einstellungen sind seitdem Glas-Dialoge
  im Hauptfenster wie im Entwurf (Branch `claude/ux-roadmap-next`). Seit dem Abend des 27.10. sind auch alle übrigen
  Sheets und alle Alerts Glas-Dialoge (`GlassDialog`/`GlassQuestion` in `Glass.swift`, roter Knopf `Theme.danger`);
  jeden auf dem Bildschirm angesehen, Return/Esc geprüft. Offen: mit einem echten Controller durchgehen (A startet
  jetzt auf der Standardantwort, `padFocus(preferred:)`); die Picker in den Einstellungen bleiben System-Popups mit blauem Pfeil (die Spieloptionen haben seit 2.3 Glas-Segmente); die
  Textfelder im Stores-Tab und der Lade-Kringel im Spielknopf sind noch System (dort arbeiten andere Branches).
- **Entscheidungen (27.10. getroffen):** 2.3 wie vorgeschlagen (siehe Roadmap); „Save battery when unplugged“ (3.4)
  bleibt standardmäßig aus; „Welcome back“ nach jeder Sitzung ab einer Minute. Abweichungen von der Vorlage, die
  angeglichen werden: Genre/Jahr/Store-Zeile über dem Titel, Suche im Bibliothekskopf mit Beispiel, Metascore auf der
  Spielseite, Bibliothekskopf „105 Spiele · aktuell vor 2 Min.“.
- **`syncstate` in `remotecache.vdf`:** Nur „1“ (im Einklang) ist sicher belegt; die anderen Werte während eines
  Uploads einmal beobachten und `CloudSaves` danach schärfen.
- **`LibraryView.swift` (über 1700 Zeilen) und `LibraryModel.swift` (fast 1900)** sind mit der Navigation weiter
  gewachsen. Die drei Ebenen, die Sheets und die Navigation in eigene Dateien ziehen – erst wenn keine anderen
  Branches mehr an diesen Dateien arbeiten.

### Danach gebaut (Branch `claude/ux-roadmap-next`, auf PR #27) – in der echten App prüfen

Nur mit Tests auf Test-Ordnern und Renderings geprüft:

- **Shader-Caches leeren** und **Spielstart** am 27.10. geprüft: 149,7 MB weg, alle Ordner leer; OxyRail startete
  danach „butterweich“ im Vordergrund, „Willkommen zurück“ kam, die Steam-Cloud-Zeile wurde grün. Die Rückkehr zu
  Nightforge dauerte 20–30 s (nach dem Spielende nur alle 10 s geschaut) – behoben, jetzt 4–7 s; einmal nachprüfen.
- **Download-Geschwindigkeit** (4.4): Steht bei einem echten Download „12 MB/s · noch 25 Min.“ unter dem Spiel, und passt die Restzeit ungefähr?
- **Nightforge komplett entfernen** (4.3): **Nicht** im eigenen Konto ausprobieren – es löscht die Windows-Umgebung mit allen Windows-Spielen. Besser mit leerem HOME (`build/fh`, wie beim Test der Ersteinrichtung; am 27.10. mit Test-Spielständen vorbereitet, gelöscht würde nur dort und in den Metal-Caches unter `/var/folders`). Zu prüfen:
  - Landen die Spielstände in `Dokumente/Nightforge Saves/<Datum>`?
  - Fragt macOS nach dem Zugriff auf „Dokumente“?
  - Legt sich die App in den Papierkorb?
- **Spielstand-Wahl** (3.2): Ein Spiel mit Mac- und Windows-Version auf beiden Seiten spielen und dann wechseln. Kommt die Frage „Mit welchem Spielstand …“, und liegt der ersetzte Stand in `Backups/`?
- **Grafik-Voreinstellungen und Karte „This game“** (2.3, Branch `claude/presets-2-3-390808`): Nur offscreen gerendert (echte Views, Deutsch und Englisch) – der Blick in die echte App wurde am 28.10. abgelehnt. In der echten App prüfen: Spieloptionen (Karten, „Expert options“ aufklappen, scrollt es bei kleinem Fenster, folgt der Pad-Fokus?), die Karte rechts neben dem Titel (passt sie bei 980 pt Fensterbreite?), „Back to the Profile“ in der Karte, ein Start mit „Most compatible“ (kommt DXVK bzw. WineD3D zuerst, 60 FPS, ohne MetalFX?).
- **Externes Laufwerk** (4.2/4.3, Branch `claude/external-drive-4-2-710e3d`): Gebaut und mit Test-Ordnern geprüft (auch auf dem USB-Stick „Spiele test“, HFS+), aber noch nie mit echtem Steam. In der echten App prüfen:
  - Ein kleines Windows-Spiel über „Install on Spiele test“ laden (Platz-Sheet oder „Wohin soll …?“). Nimmt Steam die Bibliothek `Z:\Volumes\Spiele test\Nightforge Games` an und lädt dorthin?
  - Dasselbe Spiel in Einstellungen › Speicher mit „Verschieben nach …“ zurück auf den Mac und wieder auf den Stick. Fortschritt im Download-Panel, Steam danach wieder an, findet Steam das Spiel ohne neue Prüfung, startet es?
  - Stick abziehen: „Schließe Spiele test an, um zu spielen“? Wieder einstecken: spielbar, ohne Nightforge neu zu starten? (Beim Einstecken startet Nightforge die Windows-Steam neu, sobald nichts läuft.)
  - Ein Spiel vom Stick deinstallieren und den Stick abziehen: Darf **nicht** „Schließe … an“ zeigen (Steam schreibt seine Liste beim Start neu – sonst bleibt der Eintrag in `apps`).
  - Fragt macOS nach dem Zugriff auf Wechseldatenträger – für Nightforge (Kopieren) und für „Nightforge Helper“ (Steam, Wine)?
  - Mac-Version (Steam für Mac, Bibliothek `…/Nightforge Games/Steam for Mac`) und Epic-Spiel (`…/Nightforge Games/Epic Games`) einmal hin und zurück.
  - Noch nicht gebaut: Ein Laufwerk mit Spielen aus einer früheren Nightforge-Installation wird erst beim nächsten Laden oder Verschieben dorthin wieder als Bibliothek eingetragen (dann mit seinen Spielen), nicht schon beim Einstecken.

### Gefunden beim Test am 27.10.

- **Nur eigene Spiele, Demos für den Rest** (ROADMAP 2.6, Branch `claude/steam-ownership-3b3bdd`): Behoben. Nightforge
  liest Steams Lizenzliste (`userdata/<Konto>/config/licensecache`), 100 von 105 Spielen sind besessen. Noch offen:
  - **Demo ohne Lizenz einmal echt durchspielen.** Der Glas-Dialog und `steam://install/<Demo>` im Windows-Steam sind
    noch nicht in der echten App geprüft. Erscheint Steams Installationsdialog vor Nightforge, und lädt die Demo nach dem Bestätigen?
    Auf diesem Mac hat gerade kein angezeigtes Spiel eine Demo ohne Lizenz.
  - **Steam-Familienbibliothek** ist ungeprüft: Stehen geliehene Spiele in der Lizenzliste (`owner_id` ≠ eigenes Konto)?
  - **Installierte Spiele ohne Lizenz** (z. B. ein Gratis-Wochenende, das nach dem Laden ablief) bleiben „installiert“
    und starten dann nicht. Ansatz: `SteamCatalog.owns` beim Start prüfen und dasselbe ehrlich sagen.
  - **The Last Caretaker Demo** (Unreal 5.7.4): Behoben am 28.10. (Branch `claude/caretaker-demo-black-700351`),
    in der echten App gesehen: D3D12 über D3DMetal, 3024×1964, ~50 FPS mit FSR-Bildgenerierung. Ursache des schwarzen
    Bilds: Unreals DirectX-11-Weg. Unter DXMT bleibt er schwarz, und der Grafikspeicher wächst um ~400 MB/s (die Videos
    sind es nicht, auch ohne `Movies` gleich). DXVK 3 auf KosmicKrisp und D3DMetal stürzen mit `-dx11` ab. Das Profil
    in `profiles/mac.json` startet sie mit DirectX 12 über D3DMetal, ohne AVX-Hinweis (sonst illegale Instruktion beim
    Shader-Vorbereiten nach ~2 min), mit Retina, ohne Nanite und virtuelle Schatten (`Engine.ini`, 30 → 64 FPS), ohne
    Raytracing/MegaLights und mit Startwerten FSR „Performance“ + Bildgenerierung, „Niedrig“. Dafür neu in Profilen:
    `iniSettings`, `retina`, `fileEdits` mit `root`/`once`. Nebenbei behoben: `Engine.installedWineNow` nahm den jüngeren
    Ordner `wine/11.18` statt winecx, damit galt D3DMetal als fehlend und kein D3DMetal-Profil griff (auch Wukong nicht).
    Noch offen:
    - **Erster Start eines neuen Spielers** läuft mit den Werten der Demo (Episch, Raytracing, TSR), weil ihre
      `GameUserSettings.ini` erst danach existiert; die Profil-Änderungen greifen ab dem zweiten Start.
    - **Hintergrundvideo im Menü bleibt schwarz** (4K-H.264, `GStreamer-Video-CRITICAL … gst_caps_is_fixed`). Spielbar,
      aber der Video-Weg in winecx (Electra/WMF über winegstreamer) ist ungeprüft.
    - **Maus im Menü reagiert träge** mit Bildgenerierung (~25–30 echte Bilder/s). Der Nutzer behält sie lieber an.
    - **Ein Start aus Nightforge hing einmal im Ladebildschirm** (Bild eingefroren, 170 % CPU), direkt nach dem ersten
      Umschalten auf Retina und D3DMetal-Variablen. Drei Starts danach liefen durch; Ursache unklar.
    - **„Läuft super“ nach einem schwarzen Start**: `LaunchHealth` bestätigt jeden Weg, der 30 s läuft, und
      `Compatibility.rate` macht daraus „Läuft super“. Für die Demo erledigt (Profil), für Spiele ohne Profil bleibt es so.
      Idee: ein Spiel, das in den ersten Minuten nur Schwarz zeigt oder dessen Speicher davonläuft, als Fehlstart werten.
    - **Retina kostet einen Steam-Neustart** beim Wechsel zwischen einem Retina-Spiel und den anderen. Wine nimmt den
      Retina-Modus nur für eine ganze Sitzung; pro Programm (`AppDefaults\<exe>\Mac Driver`) wirkt er nicht – auch der
      Eintrag für `NMS.exe` im Prefix tut nichts.
  - **Toast „Steam lädt … nicht herunter“** ist in der App nicht gesehen. Der Eintrag selbst wechselte richtig; der Toast
    verschwindet nach 5 s und fiel in die Wartezeit.
- **Beenden mit offenem Dialog geht nicht** (⌘Q und `osascript … quit` tun nichts, solange ein Sheet offen ist). Seit
  die Einstellungen ein Sheet sind, fällt das eher auf; vor dem Beenden Sheets schließen.
- **`osascript … quit` meldet „abgebrochen“ (-128)** (28.10., beim Test von 7.4): Einmal mit offenen Einstellungen –
  die App lief weiter (siehe oben); einmal endete sie trotz der Meldung wenige Sekunden später. Wer Nightforge per
  Skript beendet, darf sich nicht auf den Rückgabewert verlassen, sondern muss mit
  `pgrep -f "Nightforge.app/Contents/MacOS/Nightforge"` warten, bis sie wirklich weg ist – sonst laufen zwei Nightforge
  (ist dabei für ein paar Sekunden passiert, der Testbuild wurde sofort wieder beendet).
- **Ein `build/`-Ordner eines Worktrees wurde von außen geleert** (28.10. gegen 23:08, Worktree `merge-dupes-7-4`):
  `build/Nightforge.app` war weg, während andere Sitzungen bauten und testeten. Ursache unklar – vielleicht ein Aufräumen
  von Worktree-Builds wegen der `nightforge://`-Links oder der Dock-Symbole. Vor dem Start eines Testbuilds prüfen, dass
  er noch da ist; wer Builds anderer Worktrees aufräumt, sagt es in den Sitzungsnotizen.
- **Download-Knopf oben** erscheint nur, solange etwas lädt; im Entwurf ist er immer da (Panel mit „Nichts lädt
  gerade“). Mit dem Nutzer besprechen (gemeldet von der Sitzung „Vorlage angleichen“, 27.10.).
- **Mehrere Steam-Symbole in der Menüleiste** (Nutzer, 27.10. 21:58: drei auf einmal). Vermutlich bildet Wine das
  Tray-Symbol des unsichtbaren Windows-Steam als macOS-Statussymbol ab, und nach Neustarts von Steam bleiben alte stehen
  (dazu kommt das echte Steam für Mac). Prüfen: wer welches Symbol besitzt; Tray-Symbol des Windows-Steam abschalten
  oder beim Beenden aufräumen.
- **Nightforge Helper (Dock-Fix vom 28.10.) – noch offen:** Steam, Wine, Spiele, Epic-Downloads und die Skripte
  starten über `Nightforge Helper.app` (Datenordner, `Detached.swift`), damit eine beendete Nightforge nicht im Dock
  stehen bleibt. Geprüft: ⌘Q mit Steam, ⌘Q während eines Spiels, Neustart, Spielende. Noch nicht gesehen:
  - **Berechtigungen** gehören für macOS jetzt dem Helfer: Abfragen (Spiele/Bibliotheken auf externen Laufwerken,
    lokales Netzwerk, „Steam steuern“ für das Beenden von Steam für Mac) kommen unter „Nightforge Helper“,
    vielleicht einmal neu.
  - **DMG-Installation** (mit Quarantäne-Flag): Der Helfer wird von Nightforge selbst geschrieben und trägt keins.
    Weist macOS ihn trotzdem ab, startet Nightforge nach höchstens 10 s wie früher als Kindprozess und bleibt für
    den Rest des Laufs dabei (dann wieder zwei Symbole).
  - **Mitteilungen und Dock-Menü** nicht eigens geprüft (es gibt nur noch einen Eintrag, also sollten sie treffen).
- **`reopened()` im Beenden-Skript** (`pgrep -f "Nightforge.app/Contents/MacOS/Nightforge"`) zählt jede Befehlszeile,
  die den Pfad nur erwähnt – im Test hielt es eine Shell dafür und beendete sich, ohne Steam zu beenden. Robuster:
  `pgrep -x Nightforge` (Prozessname). `MacVersionTest` ersetzt `pgrep` und müsste mitziehen.
- **`nightforge://`-Links** öffnen die Standard-Kopie (`~/Applications`), auch wenn gerade ein Worktree-Build läuft – nur
  auf diesem Mac mit vielen registrierten Kopien. Zum Testen: `open -a <Build>.app "nightforge://play/<ID>"`.
- **DualSense** fehlte ab 20:08 in Nightforge: zum Laden getrennt, danach scheiterte macOS mit jedem Versuch, ihn
  wieder zu verbinden (bluetoothd „result 329“), obwohl er in der Liste stand. Seit 21:00 wieder verbunden – Nightforge
  zeigte ihn ohne Neustart (Hinweisleiste, Einstellungen › Controller, PlayStation-Symbole). Kein Fehler in Nightforge.

### Epic Games – offene Tests mit echtem Konto (Stand 28.10.)

Schon geprüft: verbinden, Bibliothek (93 Spiele), laden, spielen (20 Minutes Till Dawn, 60 FPS), deinstallieren in der
App (27.10.); Update & Play, Größe vor dem Download, Civ VI mit DLC laden, abbrechen, deinstallieren samt DLC nur ohne
Fenster über ein Testprogramm (28.10., `claude/stoic-gould-8fba7f`). Noch offen – ersetzt die Prüfliste im ersten Punkt
von „Epic Games“ unten:

- [ ] **Cloud-Spielstände:** ein Spiel mit Epic-Cloud (z. B. A Plague Tale, Control) spielen und beenden – vorher
      „Spielstand wird geholt …“, danach im „Willkommen zurück“ „Dein Spielstand ist bei Epic Games“.
- [ ] **Offline-Start:** WLAN aus, ein installiertes Epic-Spiel starten (startet ohne Anmeldecode; „Offline: Bereit“ /
      „Braucht Internet“ auf der Spielseite stimmt).
- [ ] **Weiterladen nach Neustart:** großen Download starten, Nightforge beenden und wieder öffnen (auch nach einem
      Neustart des Macs) – der Download läuft dort weiter, wo er war.
- [ ] **Tempo und Restzeit** im Download-Panel bei einem großen Spiel; zwei Epic-Downloads hintereinander (der zweite
      wartet, läuft danach von selbst an).
- [ ] **In der App selbst** (bisher nur ohne Fenster): „Wird aktualisiert … 42 %“ im Play-Knopf bei einem Update,
      „Download 12 GB · Auf dem Mac 25 GB“ und „Größe wird geprüft …“ auf der Spielseite, Platz-Sheet bei vollem Mac,
      „Deine Zusatzinhalte: …“ auf der Spielseite.
- [ ] **Ownership-Token:** ein Spiel mit `requires_ot` in `installed.json` laden und starten.
- [ ] **Anmeldung:** „Mit Google/Apple anmelden“ im Epic-Fenster; abgelaufene Anmeldung („Erneut anmelden“ im Banner
      und in Einstellungen › Stores) mit einem echt abgelaufenen Login.
- [ ] **Anti-Cheat:** Destiny 2 oder Century – Play öffnet GeForce Now; Fortnite zeigt „Läuft nicht“, ohne Download.
- [ ] **„Spielen“ blendete OxyRail aus** (siehe unten) einmal von Hand nachstellen.

### Epic Games (Branch `claude/epic-games-d52d35`, Roadmap 0.2, 7.1, 7.2)

- **Mit echtem Konto noch prüfen** (verbinden, laden, spielen gingen am 27.10.): ein Spiel mit Epic-Cloud-Spielständen
  (Abgleich vor/nach dem Spielen, Zeile im „Willkommen zurück“), Deinstallieren, Abbrechen eines größeren Downloads,
  Weiterladen nach einem Neustart von Nightforge, Offline-Start, ein Spiel mit Ownership-Token (`requires_ot`),
  „Mit Google/Apple anmelden“ (öffnet im selben Fenster), Tempo/Restzeit im Download-Panel bei einem großen Spiel,
  in der App selbst (28.10. nur ohne Fenster geprüft, siehe Roadmap 7.2): „Wird aktualisiert … 42 %“ im Play-Knopf, offline
  startet die alte Version, „Download 12 GB · Auf dem Mac 25 GB“ und „Größe wird geprüft …“, Platz-Sheet bei vollem Mac,
  „Deine Zusatzinhalte: …“ auf der Spielseite, zwei Epic-Downloads hintereinander (der zweite wartet, läuft dann an).
- **Doppelt gekaufte Spiele (7.4, Branch `claude/merge-dupes-7-4-b22892`):** Am 28.10. in der App mit der Maus gesehen
  (ARK, Karte, Spielseite, Wechsel Steam ↔ Epic, Größe, Zähler 192). Noch offen: Store-Wahl per Pad, ein Download im nicht
  gewählten Store (Fortschritt auf Cover und Spielseite), Ausblenden/Anheften einer zusammengeführten Karte. ARC Raiders
  stand am 28.10. in keiner der beiden Bibliotheken auf dem Mac.
- **Esc auf der Spielseite, wenn die Suche noch den Fokus hatte** (28.10., gefunden beim 7.4-Test, nicht von 7.4): Die
  Bibliothek bleibt hinter einer Spielseite stehen, ihr Suchfeld behielt den Tastaturfokus – Esc leerte die verdeckte
  Suche, statt zurückzugehen, und Buchstaben (H, P, O …) wären in die Suche getippt worden. **Behoben** im selben Branch:
  Das Suchfeld gibt den Fokus ab, sobald die Bibliothek verlassen wird (`LibrarySearchField`, `onChange(of: route)`).
  In der App geprüft (28.10., 23:10): ⌘F, „ark surv“, Spielseite per Klick, Esc → zurück in die Bibliothek, Suche bleibt.
- **„Spielen“ blendete OxyRail aus** (28.10., Prüfung per Fernsteuerung): Ein Klick auf „Spielen“ startete OxyRail und
  zeigte zugleich „OxyRail ist aus deiner Bibliothek ausgeblendet“. Im Code löst nur der Augen-Knopf oder H das aus;
  vermutlich ein Fehlklick, als das Fenster gerade nach vorne kam. Nicht nachvollzogen – im Auge behalten.
- **Update & Play mit DLCs:** Alle Teile zählen gleich viel – bei Spiel + 1-KB-DLC steht der Balken nach dem Spiel auf
  50 % und springt dann auf 100 %. Besser nach Größe gewichten (legendary schreibt die Größe erst, wenn ein Teil startet).
- **DLCs eines schon wartenden Downloads:** Steht ein Spiel schon in `Epic/downloads.json` (von einem Build ohne DLCs),
  kommen seine DLCs nicht dazu; sie folgen erst mit „Aktualisieren & spielen“. Ältere Builds schreiben `library.json`
  ohne `dlcs` – der neue Build holt sie beim nächsten Abgleich zurück.
- **Reste vom Test am 27.10.:** `Prefix/drive_c/Program Files/Epic Games/MinutesTillDawnxgosd` (12 KB, nur
  dxmt.conf/dxvk.conf) – vor dem Fix 6bd8f20 deinstalliert; kann weg.
- **Wartende Epic-Downloads** zeigen „Download wird vorbereitet …“, solange ein anderer Epic-Download läuft (legendary
  installiert nur eins zugleich). Besser: „Wartet auf <Spiel>“ – braucht einen Wartezustand in `InstallState`.
- **Abbrechen während der Zusatzinhalte** entfernt auch das schon geladene Spiel (Spiel und DLCs sind ein Download).
  Vielleicht: dann nur die DLCs abbrechen und das Spiel behalten.
- **Voraussetzungen der Spiele** (VC++-Pakete usw., `prereq_info` in `installed.json`) überspringt legendary mit `-y`.
  Fehlt etwas, lernt Nightforge es aus `wine.log` (winetricks) – oder den Installer des Spiels einmal unter Wine starten.
- **Nicht dabei:** Spiele, die über EA app oder Ubisoft Connect laufen (ausgelassen), Mac-Versionen
  von Epic-Spielen, Rockstar-Spiele, die `EpicGamesLauncher.exe` als Elternprozess erwarten (legendarys Wrapper-Exe).
- **GeForce Now für Epic-Anti-Cheat-Spiele** nur, wenn das Spiel auch auf Steam ist (GeForce-Now-ID des Steam-Zwillings).
  Fortnite & Co. bekommen „Läuft nicht“ ohne GeForce-Now-Knopf; GeForce Nows Katalog hat `EPIC`-Varianten mit eigener ID.
- **Epic ohne Steam:** Die Ersteinrichtung richtet Engine und Prefix nur zusammen mit Steam ein. Wer nur Epic verbindet,
  sieht die Bibliothek, aber Starten scheitert ohne Engine („Nightforges Engine ist noch nicht installiert“).
- **legendary-Updates:** Komponente ist auf 0.21.1 gepinnt (`components/sources.json`). Der Schnellstart (`PackedApp` in
  `Legendary.swift`) nutzt, wie PyInstallers Starter sich selbst startet (`_PYI_APPLICATION_HOME_DIR` usw.). Vor einem
  Update prüfen, dass ein Aufruf aus dem entpackten Ordner weiter ~0,2 s braucht; sonst fällt es auf 5–16 s zurück.
  Sauberer wäre ein eigener onedir-Build per GitHub-Workflow wie bei den Grafik-Paketen.
- **legendary fragt beim Start** `api.legendary.gl/v1/version.json` ab (Epic-Client-Daten, keine Nutzerdaten) – erst
  nach dem Verbinden. In „Über“ erwähnen oder per `config.ini` abschalten (dann fehlen Epics neue Client-Daten).
- **Alte Schlüssel aufräumen:** `GameIDMigration` lässt „options.570“, „library.hidden“ usw. für ältere Builds stehen.
  In einer späteren Version löschen.
- **Noch offen aus der Roadmap:** Store-Filter in der Bibliothek (2.1, mit Warnsymbol bei Sync-Fehler), „Start through
  <anderer Store>“ im Fehlstart-Sheet (1.2; die Store-Wahl selbst ist mit 7.4 da). „Also add Epic Games“ im ersten Start
  (6.1) entfällt nach Entscheidung des Nutzers (29.10.): Epic verbindet man in Settings › Stores.

### GOG (Branch `claude/gog-7-3-e69c3b`, Roadmap 7.3) – offene Tests mit echtem Konto (Stand 31.10.)

Live getestet am 31.10. mit dem echten Konto (0e017bd): Anmeldung, Bibliothek, ein Mac-Download und Spielen klappen. Am
besten weiter im leeren Test-Home (`build/fh`), damit Steam/Epic des Nutzers nicht dazwischenfunken.

- [x] **Anmeldung:** GOGs Seite auf Deutsch, Fenster schließt von selbst, `auth.log` „ended with 0 / answer: credentials“,
      `.runs-packed` angelegt. (Erster Versuch mit a6a2899 scheiterte: gogdl 1.4.0 läuft nicht aus dem entpackten Ordner,
      Roadmap 7.3.) Offen: Zwei-Faktor, Kontoname als Tooltip. Vor dem nächsten Live-Test `tests/GOGTest/run.sh` – mit
      installiertem gogdl startet es das echte Programm.
- [x] **Bibliothek:** 7 Spiele, keine DLCs; Control und The Evil Within 2 mit Epic zu einer Karte zusammengelegt (193 → 198).
- [x] **Mac-Version laden und spielen:** „A New Beginning: Final Cut“, 3,9 GB in ~3 Min. (~21 MB/s), keine gogdl-Reste;
      startet als Mac-App (x86_64 unter Rosetta), „Willkommen zurück“ mit GOG-Cloud-Zeile, danach Platz 1 auf der Startseite.
- [ ] **Nachgebessert, nachprüfen:** „Zuletzt gespielt gerade eben“ statt „in 0 Sekunden“; die Cloud-Zeile in „Willkommen
      zurück“ bricht um (bis 2 Zeilen); im Download-Panel Fortschritt und Tempo/Restzeit in zwei Zeilen; eine GOG-Größe
      „Herunterladen“ vor und während des Downloads und im Panel (die Download-Größe, nicht gogdls Installations-Bytes).
- [x] **Weiterladen** nach Beenden und Neustart von Nightforge (Mafia II, 8,4 GB, deutsch).
- [x] **Doppelt:** Control und The Evil Within 2 als eine Karte EPIC + GOG.
- [ ] **Ein Windows-Spiel – Mafia II (Classic), 1816059595:** Der erste Start (0e017bd) scheiterte an „PhysX SDK not
      initialized“ – Galaxys Abhängigkeiten fehlten. Seit dem Fix (Roadmap 7.3, `GOGRedist`) prüfen: vor dem ersten Start
      „Windows-Bausteine für Mafia II werden eingerichtet …“ mit „Visual C++ Redist 2017“, „NVIDIA PhysX Legacy“,
      „NVIDIA PhysX“ darunter, **kein** Installer-Fenster; `GOG/Redist/__redist/` mit MSVC2017, PHYSXLEGACY, PHYSX, ISI
      (kein DirectX); `Prefix/gog-redist.json` mit den drei und `products` 1816059595; `GOG/Logs/redist.log` mit Exit 0
      je Installer und dem Installationsskript. Dann startet das Spiel ohne PhysX-Fenster (Grafik-Leiter,
      Erstsekunden-Prüfung, Prozess über `\GOG Games\`). Ein zweiter Start richtet nichts mehr ein.
      Live 31.10. (557c2c2): Redists liefen alle (VC_redist 2017 endet mit 102 = 1638 „neuere Version da“, v14 14.51 ist im
      Prefix – zählt richtig als installiert). Mafia II endet dann aber nach 6 s: DXVK-d3d9 bekommt unter winecx kein Gerät
      („DxvkAdapter: Failed to create device“, MoltenVK ohne `geometryShader`/`shaderCullDistance`, siehe oben bei L4D2).
      Seit dem Fix danach: Die alte Bestätigung (ohne Bild-Nachweis) gilt nicht mehr, der Start wird beobachtet und geht nach
      dem Grafikfehler von selbst auf WineD3D – und seit danach beginnt die D3D9-Leiter unter winecx ohnehin mit WineD3D.
      1.11. (TV-Build, nur der TV): Der WineD3D-Start endete nach ~14 s, zwei DXVK-Fehlerzeilen im geteilten Log ließen
      Nightforge ihn als Grafikfehler beenden und auf DXVK weiterschalten (scheitert immer). Behoben: DXVK-Zeilen zählen nur
      auf DXVK, D3D9 unter winecx nur WineD3D. Offen für die TV-Session: `videoconfig.cfg` steht auf 1512×982 Vollbild
      (`0 0 1512 982 1 0 0 1`), den Modus hat der TV nicht – DXVK loggte unter KosmicKrisp um 00:20 genau das
      („D3D9: EnterFullscreenMode: Failed to change display mode“).
      Prüfen: Start mit WineD3D ohne Zutun, kein „Läuft super“ vorher;
      bestätigt erst nach 3 Min. Laufzeit (WineD3D loggt keine Bilder); „Willkommen zurück“ › „Nicht gut“ › gleich „Fertig“
      (oder ×, Esc, B) lässt `rating.gog.1816059595` stehen.
- [ ] **Mafia II ruckelt, der Ton klingt doppelt (WineD3D, 31.10.).** Befunde, Belege und Testanleitung in den
      Notizen der Mafia-II-Sitzung (`mafia-ii.md`).
      - Bis jetzt bekam kein GOG-Spiel ein Profil: Der Start fragte nur Steam-IDs ab. Jetzt gilt „gog.<Produkt-ID>“ in
        `profiles.json`. `mac.json` nennt die GOG-Ausgabe beim Steam-Zwilling (`"gog": ["1816059595"]` bei 50130).
      - Ton: FMOD Ex steckt fest im Programm und gibt unter Windows 10 über WASAPI aus. EAX und OpenAL gibt es nicht im
        Prefix. Die Lautsprecher kommen vom System (MacBook: Stereo, 48 kHz), der Mixer läuft mit 44,1 kHz.
      - Live-Test 31.10. 23:00, ohne Compiler daneben:
        - Das Profil greift, Mafia II startet direkt mit WineD3D.
        - Das Menü klingt sauber. Das Echo im Spiel ist weg, aber Knacken und Aussetzer bleiben.
        - CPU: Menü ~120 %, im Spiel 230–440 %, und dabei zwei Threads mit je ~95 %. Kaum GPU-Last.
        - APEX war schon aus. APEX an ändert nichts, und `windowsVersion: winxp` (DirectSound statt WASAPI) auch nicht.
        - Ausgabeweg und PhysX sind damit ausgeschieden.
        - Folgetest 23:15: Schatten Niedrig, Geometrie Niedrig, AO aus. Kein Unterschied beim Knacken, im Spiel
          weiter 250–460 %, Threads bei 97/88/88/45 %. Die Hebel im Spiel sind damit ausgeschöpft.
        - Für 0.3.0 bleibt Mafia II auf WineD3D: Das Echo ist weg, das Knacken bleibt. Der Weg ist DXVK auf
          KosmicKrisp (Session kosmickrisp-dx9).
      - Ursache, aus winecx gelesen: Mafia II ist ein 32-Bit-Spiel und läuft im neuen WoW64 (winecx hat kein
        `i386-unix`). Jeder OpenGL-Aufruf von WineD3D wird übersetzt. `opengl32.so` kopiert gemappte Puffer um
        („Copying %#zx from wow64 buffer“) und schaltet `GL_ARB_buffer_storage` ab („Disabling … on wow64“).
        Dazu kommt Apples OpenGL unter Rosetta. Das passt zu zwei vollen Threads: Spiel-Thread und WineD3Ds CS-Thread.
      - Ausweg: DXVK über Vulkan. winevulkan braucht für 32-Bit-Spiele `VK_EXT_map_memory_placed`. KosmicKrisp hat es,
        bei MoltenVK ist es offen (Karte „DXVK auf KosmicKrisp“).
      - WineD3D selbst bietet keinen Hebel:
        - `csmt` bleibt an, aus legt beide Threads auf einen.
        - `MaxVersionGL`: WoW64 deckelt bei 4.3, Apple liefert 4.1.
        - `VideoMemorySize` und `strict_shader_math` betreffen die GPU.
        - `OffscreenRenderingMode` gibt es in winecx' wined3d nicht mehr.
        - Eine Bildratengrenze hat WineD3D nicht, das Spiel kennt nur VSync. 60 statt 120 Hz hilft nur, wenn das Spiel
          über 60 FPS kommt.
      - `profile.dat`: Bitfolge, LSB zuerst, mit 32-Bit-Prüfsumme 8 Bytes vor dem Ende (kein CRC32, Adler oder Summe).
        - APEX an statt aus setzt die Bits 39337 und 39370, gleich nach den vier Lautstärken (1.0f).
        - Schreiben kann Nightforge sie nicht. Seit dem Folgetest ist das für Mafia II auch nicht mehr nötig.
- [ ] **Mac-Version, die GOG nicht übers Content-System liefert** oder 32-Bit ist: die Windows-Version muss kommen (Toast).
- [x] **Deinstallieren** (A New Beginning: Ordner weg, Karte, Spielzeit und Bewertung bleiben), **Abbrechen** (Dishonored 2:
      nach 3 s kein gogdl mehr, Ordner weg, `downloads.json` leer) – live 31.10. (159acfa). Danach behoben: kein
      „Spielordner im Finder zeigen“ mehr ohne Ordner (`Game.hasFolder`).
- [ ] **Update & Play** (ein Spiel mit neuerem Build oder später gekauftem DLC; danach läuft das Installationsskript neu),
      **Cloud-Spielstände** (Upload nach Mafia II live 31.10. ✓, `saves.json` aktualisiert), **Offline-Start**.
- [x] **Laufwerk:** auf USB-Stick installiert (`/Volumes/Spiele test/Nightforge Games/GOG Games/`), von dort gespielt, ohne
      Stick „Schließe Spiele test an“ – live 31.10. Danach behoben: Die Kennzahlen sagen „Auf Spiele test · 4,11 GB“ statt
      „Herunterladen · bis zu 4,11 GB“ (alle Stores).
- [x] **Abgemeldet:** „GOG hat dich abgemeldet“ und „Erneut anmelden“ mit umbenannter `auth.json` – live 31.10. Erst nach
      einem Neustart: „Neu einlesen“ (⌘R) fragte die Stores nicht. Danach behoben (`rescan()` mit `refreshStores(force: true)`).
- [x] **Steam-Wechsel:** nach Valheim (Steam für Mac) startet Mafia II, an beiden Steams ändert sich nichts – live 31.10.

Bekannte Lücken (bewusst, siehe Roadmap 7.3):
- Keine Mac/Windows-Wahl in den Optionen eines GOG-Spiels (Automatisch = Mac zuerst). Ist eine Mac-Version zwar
  64-Bit, läuft aber schlecht, gibt es noch keinen Weg zur Windows-Version außer Deinstallieren + Datei `GOG/mac-unfit.json`.
- Galaxys Abhängigkeiten: DirectX (June 2010) und .NET Framework 3.5–4.7.2 laufen bewusst nicht (winecx hat DirectX
  eingebaut; für .NET Framework kommt Wine Mono). Alte v1-Builds: ihre `support_commands` laufen nicht, nur ihre Redists.
- Controller-Unterstützung kennt nur Steam: Ein Spiel nur von GOG (oder Epic) hat keine Angabe – auf der Bühne sagt
  „Für den Anfang“ dann nichts über den Controller (statt „Gespielt wird mit Maus und Tastatur“), und der Controller-Filter
  findet es nicht. GOGs `api.gog.com/v2/games/<id>` nennt `controller_support` unter den Features – ein Abruf pro Spiel.
- Läuft ein Windows-Spiel von GOG (oder Epic), lehnt Nightforge den Start einer Steam-Mac-Version ab („… braucht Steam“).
  Das GOG-Spiel braucht Steam nicht, aber das Stoppen der Windows-Steam kann die Wine-Sitzung beenden, in der es läuft
  (`Engine.stopSteam` → `stopAll`). Zulassen hieße: Steam für Mac meldet die Windows-Steam ab, ohne sie zu stoppen – und
  ein späterer Neustart der Windows-Steam (`restartStuckSteam`) darf dann das laufende Spiel nicht treffen. Text stimmt nicht.

### Trackpad-Gesten (Branch `claude/musing-haslett-71514d`, Roadmap 5.5)

Mit zwei Fingern am 28.10. am echten Trackpad geprüft. Offen:

- **Vor und Cover-Größe gibt es nur am Trackpad.** Die Roadmap-Regel will für jede Aktion einen Tasten- und einen
  Controller-Weg. Möglich wären ⌘[ / ⌘] wie in Safari und ⌘+ / ⌘− für die Cover (`InputRouter.handleKey`,
  `CoverSize.current`), am Pad vielleicht R3 für die Größe.
- **Drei Finger** (`swipe(with:)`) sind nicht ausprobiert, weil beim Nutzer drei Finger zwischen Vollbild-Apps wechseln.
  Die Richtung (`deltaX > 0` = zurück, wie WebKit) ist ungeprüft.
- **macOS 14:** Die Leiste meldet ihre Ränder erst ab macOS 15 (`onScrollGeometryChange`). Unter 14 geht über der Leiste
  nie vor, daneben schon. Nicht auf 14 ausprobiert.
- **Zurück zur Startseite:** Beim Mitgleiten scheint nur die Bibliothek durch (sie liegt schon hinter einer Spielseite).
  Die Startseite erscheint erst am Ende mit dem Überblenden. Sie dahinter vorzurendern wäre schöner.

### Größere Schrift (Branch `claude/larger-text-2-5-2d1360`, Roadmap 2.5)

Nur offscreen gerendert (echte Views, Deutsch und Englisch, aus und an, 1512 × 900 und 980 × 640). Ausgeschaltet
pixelgleich mit vorher, außer den Korrekturen unten. In der echten App prüfen:

- **Umschalten im laufenden Betrieb:** Werden in Einstellungen › Allgemein sofort alle Texte größer, auch im offenen
  Sheet und hinter ihm, ohne dass das Sheet zugeht?
- **Kleines Fenster (980 × 640), Schalter an:** Startseite (runde Knöpfe unter „Spielen“), Spielseite (Logo wird
  kleiner, Knöpfe in zwei Zeilen), Bibliothek (Suchfeld-Hinweis ganz lesbar), Download-Panel, Hinweisleiste mit
  verbundenem Controller (Akku-Pille links) – nicht gerendert.
- **Erster Start unter ~680 pt Fensterhöhe:** Anmeldung (mit QR-Hinweis) und Ergebnis scrollen jetzt, statt die obere
  Leiste hinauszuschieben (die Anmeldung tat das bei 640 pt schon ohne größere Schrift). Holt der Pad-Fokus den Knopf
  am Ende ins Bild? Stört der Scrollbereich das Wischen mit zwei Fingern nicht?
- **Einstellungen und Dialoge im kleinen Fenster** (Nachbesserung nach dem Live-Test, beide Schriftgrößen): Das Sheet
  ist höchstens Fensterhöhe − 40 pt hoch (bei 980 × 640: 568 statt 727/771), Kopf und Tabs stehen, das Formular scrollt.
  Scrollt das Trackpad im Sheet das Sheet und nicht die Bibliothek dahinter? Holt der Pad-Fokus in Allgemein „Größere
  Schrift“ und „Bewegung reduzieren“ ins Bild? Dasselbe im Platz-Dialog (viele Spiele) und in „… ist nicht gestartet“.
  Bei 1512 × 853 bleibt alles wie vorher (771 < 781). Die Werte der System-Popups (Sprache, Nach dem Start) bleiben
  13 pt – wirkt das störend?
- **Bibliothek bei 980 × 640:** Steht das gewählte Spiel in der ersten Reihe, bleibt „Installiert“ mit vollem Abstand
  unter den Filtern, auch nach Spielseite → Esc und nach Pinch auf eine andere Cover-Größe.
- **Spielseite mit vielen Hinweisen** (Kompatibilität, Akku, Low Power Mode, Versionen) bei 640 pt Höhe war schon vorher
  zu hoch und wird mit größerer Schrift höher. Nächster Schritt wäre, dass sie scrollt wie der erste Start.
- **Nicht gerendert:** Controller-Test mit echtem Pad, Epic-Anmeldehinweis und Sync-Banner, leere Bibliothek,
  Store-Wahl (7.4), Hinweise aus der Spielanalyse, Steam-für-Mac-Fortschritt, „Willkommen zurück“ mit Cloud-Zuständen.

## Ideen für später

- **Mauszeiger blitzt beim Spielstart kurz auf** (Nutzer, 1.11.: „detailarbeit für irgendwann mal“): Mit dem
  Pad bleibt der Zeiger im Ladebildschirm, im Spiel, nach „Zum Spiel wechseln“ und beim Beenden weg (TV-Zweig
  72a8432, live bestätigt). Nur im Ladebildschirm ist er einen Moment zu sehen, bis `hidePointerOverGame` greift,
  wenn das Spiel nach vorn kommt. Kandidat: das Verstecken schon beim Übergeben an das Spiel.
- **Tab „Entdecken“** (Nutzer, 31.10.; noch nicht anfangen): neben „Startseite | Bibliothek“ ein dritter Tab, in dem man
  durch Steam, Epic und GOG stöbert und neue Spiele findet.
  - Was Nightforge dabei besser kann als die Stores selbst: Jedes Spiel trägt gleich die Einschätzung für **diesen
    Mac**, also Mac-Version, „läuft wahrscheinlich“ über Wine, Anti-Cheat blockiert oder nur über GeForce Now.
    Dazu ein Filter „Läuft auf meinem Mac“.
  - Inhalte: Angebote, Neu und beliebt, „ähnlich wie deine meistgespielten“, kostenlose Spiele (Epic-Gratisspiele).
    Gekauft wird im Store selbst (Browser oder Store-Seite), danach taucht das Spiel von selbst in der Bibliothek auf.
  - Anfangen bei `StoreSearch` (heute nur Steam), Steams store-browse-API und den Store-Treffern aus dem
    Spielinfo-Design (Zweig `claude/game-metadata-a2cee0`, Commit 91d10a7), `Compatibility.rate` für die Einschätzung.
  - Ganz mit dem Controller bedienbar, wie Startseite und Bibliothek.

- **Mehr Infos pro Spiel („Über das Spiel“)** (Wunsch des Nutzers, 31.10.: „kurze Spielbeschreibung usw.“).
  Recherche und Entwurf mit Bildern liegen in `docs/ENTWURF-SPIELINFOS.md` (Branch `claude/game-metadata-a2cee0`).
  Der Nutzer hat am 31.10. entschieden (alle vier Empfehlungen). In Arbeit seit 31.10. (für 0.3.0) in zwei Abschnitten
  (A: Daten, Filter, Bibliothek; B: Spielseite), jeder mit eigenem Live-Test.
  - **Pad auf der Spielseite (TV-Test 1.11.)**: Es scrollte nicht weich, sprang von Punkt zu Punkt und kam nicht bis unten.
    Behoben: Fokuswechsel scrollen weich mit (Platz für die Spielleiste), ↓/↑ hinter dem letzten/ersten Bedienelement
    scrollen seitenweise bis ans Ende, der rechte Stick scrollt stufenlos (alle Seiten mit Scrollbereich), der Rahmen
    beginnt auf „Spielen“ statt auf den Screenshots. Noch am TV zu prüfen.
  - **Nachbesserung nach dem ersten Live-Blick (31.10. nachts)**, Variante 1 nach Wahl des Nutzers: Beschreibung nur einmal
    (unten), feste Spielleiste beim Scrollen, ruhiges Raster mit zwei Karten, deutsche Beschreibung und Screenshots von GOG,
    wo Steam keine hat. Noch ohne Live-Test.
  - **Abschnitt B gebaut (31.10.)**: Die Spielseite scrollt. Oben 2 Zeilen Beschreibung (weichen im kleinen Fenster),
    unten „Über das Spiel“ mit Screenshot-Leiste, Großbild (← → / Pad, Esc/B/A/Return schließt), Genres, Spielmodi und
    der Karte „Auf einen Blick“. Neu: `GameAbout.swift`. Altersfreigabe: Steam liefert sie je Land, in Österreich PEGI
    (No Man's Sky hat dort keine), in Deutschland USK. Noch ohne Live-Test: Prüfliste „Live-Test B“.
  - **Abschnitt A gebaut (31.10.)**, Branch `claude/game-metadata-a2cee0`; noch ohne Live-Test. Prüfliste: „Live-Test A“ in
    `docs/ENTWURF-SPIELINFOS.md`. Neu: `GameInfo.swift`, `GameInfoStore.swift` (Cache `GameInfo/known.json`),
    `LibraryFilterRow.swift`. Offen für den Live-Test: Ein Epic-/GOG-Spiel mit Steam-Profil zeigt jetzt dessen
    „Läuft super“, der Start nimmt das Profil aber weiter nur über die eigene Steam-App-ID (`ProfileStore.profile(for: appID)`).
    Ob das Steam-Profil auch beim Start gelten soll, je Spiel prüfen.
  - Zusatzauftrag (31.10.): Store-Filter „Alle Stores ▾“ und eine einfachere Filterzeile (Sortier-Chip, „Filter ▾“-
    Panel, aktive Filter als Chips, die Suche lässt die Filter ruhen). Entwurf und Bilder 8–13 im selben Dokument.
  - Store-Treffer der Suche: Sie zeigen auch Spiele, die man schon bei Epic oder GOG hat. Neue Steam-Apps zeigen nur
    ein Platzhalter-Cover (Bilder liegen unter einem Hash-Pfad, `ArtworkStore.remoteURLs` findet sie nicht). Namen
    enthalten `&amp;`. Alles drei kommt in Phase 2.
  - Dazu gehört dieser Fehler: Die Filter „Controller“ und „Läuft super“ greifen nur bei Steam-Spielen. Epic- und
    GOG-Spiele sind immer „keine Controller“ (Overcooked! 2 von Epic zeigt „Maus & Tastatur“), und
    `compatibility(of:)` sucht Profile nur per Steam-App-ID. Die Lösung ist dasselbe Spiel auf Steam: Epic-AppName
    oder GOG-ID → GamesDB → Steam-App-ID, sonst ein genau gleicher Name.

- **Echte Speicherverwaltung unter Einstellungen › Speicher** (Nutzer, 31.10.; noch nicht anfangen):
  - Heute zeigt der Tab ein Laufwerk nur, wenn Spiele oder ein Ordner `Nightforge Games` darauf liegen
    (`StorageSettings.drives`). Ein frisch eingesteckter, leerer Stick taucht nicht auf.
  - Ziel:
    - Nightforge erkennt einen neu eingesteckten Stick oder eine Platte.
    - Ein kleines Pop-up (Toast) „„Spiele test“ eingesteckt · Für Spiele vorbereiten“ führt direkt zu
      Einstellungen › Speicher.
    - Dort stehen alle Laufwerke mit Platz und Format, **oben** direkt unter „Macintosh HD“, ohne Scrollen
      (Nutzer: wer eine externe Platte dabeihat, will den freien Platz sofort sehen). Heute steht ein
      angeschlossenes Laufwerk erst unter der Spieleliste des Macs.
    - „Vorbereiten“ prüft das Format: exFAT und FAT32 taugen nicht (keine Rechte und Links, FAT32 max. 4 GB pro
      Datei), NTFS ist auf dem Mac nur lesbar. Dafür erklärt es, was zu tun ist, und bietet an, das Laufwerk in
      APFS umzuwandeln. Löschen nur nach ausdrücklicher Bestätigung, mit Hinweis, dass alles darauf verloren geht.
    - Danach legt es `Nightforge Games` an.
  - Dazu gehört ein Hinweis bei langsamen Laufwerken (USB-2-Sticks): „Spiele starten von hier spürbar
    langsamer“, gesehen am 31.10. mit A New Beginning auf „Spiele test“.
  - Anfangen bei `ExternalDrive` (Format steht schon in `format`), `DriveLibrary`, `StorageSettings`, `Toasts`.

- **Von steamac lernen** (github.com/fxgl/steamac, Apache-2.0, angeschaut am 31.10.; noch nicht anfangen):
  - steamac lässt Valves ARM64-SteamOS in einer VM laufen. Spiele laufen dort über Proton und FEX, die Grafik geht den
    Weg Vulkan → Venus → virglrenderer → MoltenVK/KosmicKrisp → Metal. Den Weg übernehmen wir nicht: Er bringt zwei
    Übersetzungsschichten mehr und einen festen RAM-Anteil für die VM. Außerdem braucht er ein Disk-Image von bis zu
    150 GB und eine zweite Steam-Anmeldung. Mac-Versionen, Epic und GOG gibt es dort nicht, und Anti-Cheat sperrt VMs.
    Ihre eigenen Zahlen belegen den Aufwand: Death's Door läuft mit 41 FPS über den Vulkan-Weg und mit 117 FPS über
    DXMT direkt auf Metal (M1 Max).
  - Einzelne Ideen, die sich lohnen könnten:
    - Neue Standard-Tonausgabe sofort übernehmen (steamac 1.9). Passt zum HDMI-Ton im TV-Modus.
    - Eine ruhige Karte „Wird vorbereitet …“, wenn ein Spiel beim ersten Start Shader baut und das Bild steht
      (steamac zeigt „Still working…“, wenn die GPU 2 s lang nichts tut).
    - Das Limit für offene Dateien beim Start anheben. Bei steamac verloren Spiele sonst nach einer Weile die GPU
      (1.7.6). Prüfen, ob Wine und MoltenVK bei uns dasselbe trifft.
    - Steam-Anmeldung per QR-Code mit der Steam-App auf dem Handy, für das Sofa ohne Tastatur. Prüfen, ob Steams
      Anmeldefenster den Code bei uns zeigt, und in der Einrichtung darauf hinweisen.
    - KosmicKrisp ist dort auf macOS 26+ der Standard. Unsere früheren Ergebnisse (Caretaker-Demo) mit neuen
      Versionen nachprüfen.

- **Spiele automatisch aktuell halten** (Nutzer, 31.10., nach den laufenden Merges angehen, vorher recherchieren):
  - Heute:
    - **Steam (Windows):** Nightforge setzt `AutoUpdateBehavior 0` (immer aktuell). Steam lädt Updates aber nur, solange es
      läuft, also solange Nightforge offen ist (`scheduleSteamShutdown`), und verschiebt sie nach eigenem Plan.
      OxyRail hatte am 31.10. „Update delayed for 12165 secs“.
    - **Epic und GOG:** Updates nur über „Aktualisieren & spielen“ (`updateEpic`, `beforeGOGStart`).
    - **Steam für Mac:** läuft nur während eines Mac-Spiels.
  - Folge: Nach ein paar Tagen Pause wartet man auf dem Sofa erst auf ein Update.
  - Ziel wie bei einer Konsole:
    - Solange Nightforge offen ist, Updates im Hintergrund holen, eins nach dem anderen. Steam sofort statt
      verzögert; Epic und GOG über legendary bzw. gogdl selbst.
    - Pause, solange ein Spiel läuft. Nur am Netzteil (`ChargerCheck`). Der Mac bleibt wach wie bei Downloads.
    - Auf der Startseite ruhig sichtbar machen („3 Spiele wurden aktualisiert“). „Aktualisieren & spielen“ bleibt als
      Rückfall.
    - Standardmäßig an, höchstens ein Schalter in den Einstellungen.
  - Erst klären: Wie bringt man Steam zuverlässig zu einem sofortigen Update, ohne das Spiel zu starten?
    Kandidaten: Steams Update-Fenster in `config.vdf`, `ScheduledAutoUpdate`, Konsolenbefehl `app_update`.
    Mit Belegen, keine Experimente am echten Konto des Nutzers ohne Absprache.
  - Später vielleicht Updates über Nacht bei geschlossenem Nightforge. Das braucht einen Hintergrunddienst; siehe auch
    Roadmap 4.4 (Reihenfolge, Pause, über Nacht).

- **Lizenzen in „Über“ zum Aufklappen** (Idee des Nutzers, 28.10.; noch nicht anfangen):
  - Ein Klick oder A auf eine Komponente (Wine, DXMT …) wechselt im selben Glas-Sheet in eine Detailansicht, kein
    zweites Sheet darüber. Oben „‹ Zurück“ (B/Esc), weiche Überblendung.
  - Darin der vollständige Lizenztext, scrollbar und sauber gesetzt. Für LGPL-2.1, GPL-3.0, Zlib, Apache-2.0 und MIT
    die Standardtexte mitliefern; bisher liegen nur Nightforges, umu-protonfixes' und AreWeAntiCheatYets Dateien in der App.
  - Unten ein unaufdringlicher Knopf zum Quellcode, möglichst zur mitgelieferten Version. Die `source`-URL steht schon in
    `components/manifest.json`. Wo sie aufs Nightforge-Repo zeigt (eigene Builds: Grafik, Gamepad, cabextract), zwei
    Links: „Original: <Projekt>“ und „Unser Build: Nightforge“.
  - D3DMetal ist Apples Game Porting Toolkit, nicht quelloffen: klar sagen („Proprietär, nur auf Apple-Hardware“),
    Apples Lizenztext, kein Quellcode-Knopf.
- **Startseite direkt nach dem ersten Start** (Nutzer, 29.10., mehrfach: „wirkt sehr karg“, „zu leer“, „sieht
  langweilig aus“): Nach „Los geht's“ zeigt Home bei einem neuen Nutzer nur „Alle 100 Spiele“, „Bibliothek öffnen“
  und ein Band mit der einzigen Kachel „Alle Spiele“. **Gebaut und gemergt am 29.10. (a5103ef):** Home ist die
  Bühne (Entwurf 2d, `HomeStage.swift`) mit „Für den Anfang“ (`StarterPicks.swift`). Offen: mit einem wirklich neuen
  Konto ansehen (weniger als drei gespielte Spiele).
- **Wartezeit der Ersteinrichtung lebendig machen** (Nutzer, 29.10.): **gebaut und gemergt am 29.10. (a5103ef).**
  Rechts neben der Checkliste stehen der Controller-Test mit Tasten-Chips und 11 Tipps; live mit DualSense geprüft.
  Kein Epic in der Ersteinrichtung.
- **Emulation** (Nutzer, 29.10., „was wäre, wenn Nightforge emulation machen könnte“; nur Brainstorming):
  - Idee: Konsolenspiele in derselben Bibliothek, mit Covern und Controller-Bedienung wie alles andere.
  - Emulatoren wären Komponenten wie legendary oder gogdl, z. B. RetroArch-Kerne, Dolphin, DuckStation, PPSSPP
    oder PCSX2. Lizenzen (meist GPL) und Apple-Silicon-Versionen sind je Emulator zu prüfen.
  - Grenzen: Nightforge liefert keine ROMs oder BIOS und lädt keine herunter, nur eigene Dumps des Spielers. Keine
    Switch-Emulatoren: Nintendo hat 2024 Yuzu verklagt, Ryujinx wurde danach eingestellt.
  - Vorbild und Konkurrenz auf dem Mac: OpenEmu. Nightforges Vorteil wäre eine einzige Bibliothek für Steam, Epic, GOG
    und Konsolen.
  - Erst besprechen: Umfang (welche Konsolen), Ordner für ROMs, Cover-Quelle, Speicherstände.
- **Ersteinrichtung weiter beschleunigen** (29.10., Session setup-speed, Branch `claude/setup-speed-ec0a53`; Lauf 5:
  Anmeldefenster nach 2:57). Gebaut, der Live-Lauf mit Zeitmessung steht aus:
  - **Steams Update vorab laden** (`SteamPackages.swift`): Installer, 32-Bit-Schritt (19 Pakete, 247 MB) und 64-Bit-Client
    laufen parallel zu `wineboot`, jede Datei per SHA-256 geprüft. Die 32-Bit-Pakete liegen vor Steams erstem Start in
    `package/`. Die 64-Bit-Pakete kommen erst nach dem „Shutdown“ des 32-Bit-Schritts dazu, denn dessen Aufräumen löscht alle
    Paketdateien. Im Probe-Präfix lud danach keiner der beiden Schritte etwas, vorher waren es 13–24 s je Schritt.
    Erwartet: −25 s.
  - **Wrapper im richtigen Moment**: direkt nach „Verification complete“ von Steams eigenem Neustart; nur in dieser Phase
    schaut Nightforge alle 50 ms nach. Davor legt Steams Prüfung Valves Helper zurück, auch bei gleicher Größe und gleichem
    Datum. Danach startet der Client den Wrapper selbst, und es braucht keinen Neustart mehr. Probe-Präfix: Steam-Start bis
    Anmeldefenster 37 s statt 83 s (Lauf 5). Erwartet: −25…30 s.
  - **Wenn der Moment verpasst wird**: Valves Browser endet, und Steams Client startet den Wrapper (siehe unten);
    ein hängender Browser (Chrome begonnen, 5 s keine Message-Loop) ebenso. Das 20-s-Netz bleibt.
  - **Lauf 6** (29.10., 23:24; Probe-Merge mit steam-guide-dylib und external-drive): 4:24, davon Windows 3:10. Der
    Steam-Teil lief live wie geplant: Steam-Start bis Anmeldefenster 38 s statt 83 s, kein Neustart, 64-Bit-Schritt ohne
    Download. Der 32-Bit-Schritt lud noch die 32-Bit-Varianten von CEF (96 MB, 6 s); jetzt kommen beide Varianten vorab.
  - **Nachmessung** in einem leeren Home (Harness mit dem echten `SetupModel`, echte Downloads, ohne App-Oberfläche):
    - Dieselbe Mischung wie Lauf 6: 2:03 (Engine 26 s, Windows 52 s, Steam 44 s).
    - Endstand: 2:05 und 1:50 (Windows 52 s und 41 s, Steam 45 s und 44 s).
    - a5103ef ohne diesen Branch: Der Neustart nach dem Update hing fünfmal hintereinander, dann gab die Einrichtung auf.
  - **Langsamer Windows-Schritt**: Einmal nachgestellt (2:12). 87 s lang lief `wine wineboot --init` ohne wineserver,
    also Wines erster Start der frisch entpackten Engine (Rosetta übersetzt), sonst 5–7 s. Zeitgleich lief Time Machine.
    Auf das Vorabladen wartet der Schritt nicht. Das Vorabladen kostet dort trotzdem Zeit (ohne 37 s, mit 41–58 s) und
    spart im Steam-Schritt ~39 s. Es startet jetzt erst, wenn wineboot Dateien anlegt.
  - **Hänger der Schleife**: Einmal stand die Einrichtung 12 min (Time Machine aktiv). Der Wrapper kam dabei zu spät, Valves
    Helper lief, danach ein Neustart. Wrapper-Tausch und `ps`-Abfrage laufen jetzt neben dem Main-Thread.
  - **Moment verpasst, Browser hängt** (30.10.): Es endet nur Steams Browser (`Engine.endWebHelpers`), und Steams Client startet
    ihn von selbst neu, nach dem Tausch also den Wrapper. Im Probe-Präfix kam er jedes Mal nach ~8 s wieder (4 von 4,
    „Restart webhelper process“). Erst nach drei Browsern ohne Erfolg, oder wenn 25 s lang keiner kommt, startet ganz Steam
    neu wie bisher. Die 20-s-Regel aus console_log greift nicht mehr, sobald dieser Start einen Browser hatte.
  - **Rosetta**: Der langsame Windows-Schritt kam am 30.10. nachmittags wieder, ohne Time Machine und ohne Vorabladen. Eine
    Stichprobe zeigt Wines Loader 12 min lang in `open()` der eigenen Datei, noch in dyld (über Rosetta). Ein natives `open()`
    derselben Datei ging sofort. Rosettas Übersetzungsdienst `oahd` hing also; später erholte er sich von selbst. Abhilfe
    beim Nutzer: Mac neu starten oder `sudo killall oahd`. Vermutung, nicht belegt: Auch der hängende Browser nach einem
    Neustart wartet auf eine Übersetzung.
  - **Verworfen**: Den htmlcache zu leeren half nicht (Lauf 5). Die Ursache des Hängers bleibt offen. In fünf nachgestellten
    Varianten trat er nie auf (kalte/warme Engine, früh/spät beendet, SIGKILL wie `stopAll`, Game-Mode-Loader). Der erste
    Browserstart in einem frischen Präfix hängt nicht.
  - **Windows-Umgebung aus einer Vorlage**: empfohlen, aber nicht gebaut, denn das braucht CI und Hosting (Entscheidung
    Nutzer/Koordinator).
    - Messwerte: `wineboot` 45 s plus 7 s bis der wineserver weg ist. Ein frisches Präfix hat 567 MB, davon 518 MB
      byte-gleiche Kopien der Engine-DLLs. Mit zstd -19 sind es 94 MB, das Entpacken dauert 2,7 s. Der erste Wine-Aufruf
      danach ist nicht langsamer, solange `.update-timestamp` der mtime von `wine.inf` der Engine entspricht (tar erhält sie).
      Sonst läuft `wineboot --update`, nicht schneller als heute, aber auch nicht langsamer.
    - Lizenz: nur Wines eigene Dateien (LGPL wie die Engine), keine Schriften, kein Mono/Gecko.
    - Beim Bauen entfernen: `dosdevices` außer c:/z: (Volumes des Build-Macs), die Benutzerordner-Links und
      „Desktop/My Mac Desktop“ (Home des Build-Macs).
    - Beim Entpacken `MachineGuid` in system.reg neu würfeln, sonst haben alle Nutzer dieselbe. Schlägt etwas fehl: `wineboot`.
    - Weg: CI baut pro winecx-Version ein Archiv als Komponente, geladen parallel zur Engine. Erwartet: −40…45 s. Dann
      bleibt weniger Zeit fürs Vorabladen; der 32-Bit-Schritt (~12 s) passt noch.
    - Eine lokale Vorlage pro Engine hilft nur bei einer zweiten Einrichtung: verworfen.

## Recherchen vom 1.11. (Cloud, Berichte in `docs/recherche/`)

Sieben Cloud-Recherchen, nur gelesen und gesucht, nichts davon am Mac getestet. Sie gingen vom alten `main` (v0.2.0) aus,
deshalb halten manche Berichte Epic und GOG noch für geplant. Den vollen Text hat jeweils die Datei, den Link zur
Cloud-Session ihre erste Zeile.

- **Verteilung und Gatekeeper** (`gatekeeper.md`):
  - 0.3.0: Der Weg bleibt, wie er ist (ad-hoc-Signatur, curl-Einzeiler, DMG). Apple hat nichts angekündigt, was ihn
    schließt.
  - Klein für 0.3.0: Texte an die Terminal-Einfügewarnung seit macOS 26.4 anpassen. Auf GitHub „Immutable Releases“
    einschalten. Der Updater soll eine klare Meldung zeigen, wenn macOS die App aus einem schreibgeschützten Ort
    startet (Translocation). Die Ed25519-Prüfung der Update-ZIPs kommt nur, wenn sie sich vorher testen lässt, sonst
    in 0.3.1.
  - Bis etwa Q1 2027 entscheiden: Apple Developer Program (99 $ im Jahr). Damit gäbe es ein notarisiertes DMG ohne
    Warnung, eine stabile Identität (keine neuen Freigabe-Abfragen nach Updates) und eine echte Herkunftsprüfung.
    Homebrew und Sparkle lohnen sich erst danach.
- **Spiele automatisch aktuell halten** (`updates.md`):
  - Wahrscheinliche Ursache der Verzögerung: `AutoUpdateBehavior 0` heißt seit Ende 2024 „globale Einstellung“, also
    „Steam entscheidet“. Gespielt in den letzten 72 h → sofort, sonst um etwa 4 Uhr früh, verteilt über bis zu
    14 Tage. **2 = sofort.** Vorschlag: im eigenen Prefix alle Spiele auf 2 setzen, bei beendetem Steam; Nightforge
    steuert das Wann über das Laufen von Steam. Die Tests T1–T5 im Bericht bestätigen das.
  - Einen „Jetzt aktualisieren“-Befehl von außen gibt es nicht. Der CEF-Debug-Port ist rot, weil jedes lokale
    Programm damit Steam fernsteuern könnte.
  - Epic (legendary) und GOG (gogdl) sind grün. Achtung: `legendary … -y` ohne `--skip-dlcs` installiert alle DLCs.
    gogdl führt keine Liste installierter Spiele, also speichert Nightforge buildId und ETag selbst, wie Heroic.
  - Steam für Mac und Wine-Steam nur abwechselnd laufen lassen („Session Replaced“).
- **Engines und Wege** (`engines.md`):
  - Die Aufteilung stimmt: DX12 → D3DMetal, DX10/11 → DXMT, DX9 → WineD3D. DXVK 3 auf KosmicKrisp ist für
    CPU-gebundene 32-Bit-DX9-Spiele schneller, ruckelt aber.
  - Vorschläge:
    - Wine 7.7 abschalten, es fehlen alle Audio-Fixes.
    - Ein Frame-Limiter nur mit Teilern der Bildwiederholrate.
    - Getrennte Shader-Caches.
    - D3DMetal-Version pro Spiel.
    - Offene Daten (highball-db, umu-database) neben den eigenen Profilen.
  - **Ton am AV-Receiver:** Wines winecoreaudio rundet Heimkino-7.1 laut Code auf das alte „7.1 wide“. Das passt
    zur Kanalmaske 0xFF, die der DENON hier meldet. Apple empfiehlt in Audio-MIDI-Setup „7.1 Rear Surround“. Wine 11
    behebt vertauschte Center-/LFE-Kanäle, Knacksen (11.16) und den Downmix (11.21). Idee: ein „Audio-Doktor“ vor dem
    Start, der vor 7.1 wide und Stereo-Aushandlung warnt.
  - Risiken:
    - Rosetta gibt es als Allzweckwerkzeug nur bis macOS 27. Ab macOS 28 (Herbst 2027) bleibt ein Spiele-Subset,
      ob Wine dazugehört, ist offen.
    - MoltenVK soll am 13.10.2026 abgekündigt worden sein (unbestätigt).
    - Die Lizenz von D3DMetal erlaubt die Nutzung nur zum Entwickeln, Testen und Bewerten von Spielen. Rechtlich das
      größte Fragezeichen.
    - Bei DXMT widersprechen sich Nightforges Hinweisdatei und Manifest. Leicht zu beheben.
- **Die 200 meistgespielten Spiele** (`top200.md`): 119 von 200 sind auf dem Mac spielbar (57 nativ, 62 über Wine).
  Funde am Build-Skript, an die Anti-Cheat-Session gegeben:
  - AWACY-Einträge ohne Steam-ID gehen verloren: FiveM, Delta Force, EA FC 26, Space Marine 2, Tarkov, F1 25, skate.
  - EAC/BattlEye mit „Running“ brauchen die Linux-Laufzeit genauso: ARC Raiders, Elden Ring Nightreign, Gray Zone,
    The Isle.
  - Gesperrte Spiele aus `mac.json` bekommen keinen GeForce-Now-Link.
  - Weitere Vorschläge:
    - Startfixes: Helldivers 2 `--use-d3d11`, Witcher 3 `--launcher-skip`, RDR2 über D3DMetal, GTA V Story mit
      `-nobattleye`.
    - Ein Profilfeld für Umgebungsvariablen.
  - Die JSON-Liste aller 200 steht nur in der Cloud-Session.
- **Fremd-Launcher** (`launcher.md`): Reihenfolge:
  1. Steam-Fassungen ohne Launcher freischalten.
  2. Rockstar über Steam, dann über Epic. Nur Story, Online sperrt BattlEye.
  3. Battle.net-Client.
  4. EA app (die Sportspiele sperrt Javelin).
  5. Ubisoft Connect (unsicher).
- **Battle.net als Store** (`battlenet.md`): machbar nach dem Steam-Muster. Die Battle.net-App bleibt Pflicht.
  - Installierte Spiele stehen in `product.db`. Gestartet wird mit `--exec="launch <Code>"`, das Spielende zeigen
    die Prozesse im Installationsordner.
  - Mac-Versionen: WoW, Diablo III, Hearthstone, StarCraft, Heroes, Warcraft III.
  - Overwatch, Diablo IV und D2R gibt es auf Steam, mit bloßer Kontoverknüpfung. Call of Duty ist rot (Ricochet).
  - Die Battle.net-App für den Mac ist noch eine Intel-App (Rosetta-Frist).
- **Entdecken** (`entdecken.md`): eine Tabelle Rubrik × Store mit allen Endpunkten (Angebote, Charts, Neu,
  Gratisspiele, Suche, Genres, Mac- und Controller-Kennzeichen). Gekauft wird immer im Store. Die Cloud-Umgebung
  konnte die Store-Hosts nicht erreichen, deshalb vor dem Einbau live prüfen.
- **macOS-Version** (`macos-14-15.md`, Nachmittag): „macOS 14 oder neuer“ stimmt nicht. winecx 4.7.3 ist für macOS
  26.0 und neuer gebaut. Ab 14.4 fehlt zwar kein Symbol, getestet ist es dort aber nicht. Unter 14.4 startet es sicher
  nicht. AVX braucht macOS 15, KosmicKrisp braucht 26. Die App selbst ist sauber für 14.
  - Für 0.3.0: `LSMinimumSystemVersion` 26.0, die Prüfung in `install.sh`, README und Landingpage auf „macOS 26 oder
    neuer“.
  - Später die weiche Grenze: Unter macOS 26 bleibt die App startbar, mit Mac-Versionen und Cloud-Spielen.
- **D3DMetal-Lizenz** (`d3dmetal-lizenz.md`):
  - Weitergabe ist erlaubt (nicht-kommerziell, unverändert). Die Nutzung ist an „developing, testing, or evaluating
    video games“ gebunden, und das gilt für jeden Spieler. Ob Spielen darunter fällt, ist ungeklärt. Viele Projekte
    liefern es seit 2023 mit, Abmahnungen sind keine bekannt.
  - Eigenes Risiko: Wir verteilen **4.0 beta 3**, eine Vorabversion. Das Release `d3dmetal-4.0b3` ist öffentlich.
  - Empfehlung für 0.3.0: kein stiller Download mehr. Beim ersten DX12-Spiel ein Dialog mit Apples Lizenz und zwei
    Wegen: „Bei Apple laden und importieren“ (empfohlen) und „Von Nightforge laden“. Keine Beta weitergeben, sondern das
    finale 3.0, falls winecx damit läuft. Das Paket in ein eigenes Repo legen.
- **Mac-Kompatibilitätsdaten** (`mac-kompatibilitaet.md`):
  - Keine Quelle kennt genau unsere Technik. Fremde Bewertungen füllen nur „Nicht getestet“ und legen die
    Reihenfolge der Grafikwege fest.
  - Reihenfolge der Quellen:
    1. Wikidata als Brücke zwischen den IDs (CC0).
    2. Links zu AppleGamingWiki, CodeWeavers und MacGamingDB auf der Spielseite.
    3. AppleGamingWiki nächtlich übernehmen (CC BY-NC-SA 3.0, vorher das Team anschreiben).
    4. MacGamingDB um Erlaubnis bitten (neo773, nennt den Grafikweg).
    5. CodeWeavers um Zusammenarbeit bitten.
    6. Parallel eigene Berichte über GitHub-Issue-Formulare und eine Action.
  - Control läuft laut allen Mac-Quellen nur über DX12 mit D3DMetal, nicht über DX11. Das passt zum Absturz.

## Aus dem Code-Audit

Befunde vom 26.10., die noch offen sind. Alles andere ist behoben (PR #4, #5, #11, #12, #14–#19).

### Entscheidungen

- **Updates sind nicht echt signiert.** `Updater.install` prüft nur `codesign --verify` auf eine Ad-hoc-Signatur,
  `scripts/install.sh` lädt ohne Prüfsumme. Bewusst offen gelassen. Wege: ein Ed25519-Schlüssel als Repo-Secret
  (Release-Zip signieren, im Updater und in install.sh prüfen) oder ein Apple-Developer-Account (Developer ID, Notarisierung).

### Wine-Sandbox (Audit M2, Zweig `claude/wine-sandbox`): Live-Test offen

**Worum es geht**
- Wine ist keine Sandbox. Über `Z:` und `\\?\unix\` lesen Windows-Programme jede Datei des Benutzers, auch Epics
  und GOGs Token in `~/Library/Application Support/Nightforge` (`docs/AUDIT-SICHERHEIT.md` M2,
  `docs/ENTWURF-LAUFWERKE.md`).
- Mit dem Schalter `wineSandbox` startet Nightforge Wine über `nightforge-sandbox` (`wrapper/nightforge-sandbox.c`,
  `WineSandbox.swift`). Das Profil erlaubt alles außer:
  - `Epic/legendary` (außer `legendary/tmp`, wo Epic-Spiele ihre Besitz-Datei lesen);
  - `GOG/gogdl` und die beiden `account.json`;
  - `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config`, `~/.kube`, `~/.docker`, `.netrc`, `.git-credentials`, `.npmrc`,
    `.pypirc`;
  - die Browserprofile von Chrome, Firefox, Brave, Edge und Arc, dazu Claude.
- Was ein Programm in der Sandbox startet, bleibt darin. Steams Spiele erben sie.
- Gebaut und getestet ohne den Nutzer:
  - `tests/WineSandboxTest`: Profil, Escaping, Schalter, der Helfer mit dem erzeugten Profil. Es bleiben `DYLD_*`
    erhalten, die `sandbox-exec` verwirft.
  - Wine mit `readprobe` im eigenen Prefix: Token über `Z:` und `\\?\unix\` gesperrt, `~/.ssh` gesperrt,
    `legendary/tmp` lesbar.
- Ausgeschaltet startet Nightforge Wine genau wie vorher.

**Einschalten** (Nightforge beendet, kein Spiel läuft): `defaults write io.github.lordhayne.nightforge wineSandbox
-bool true`, dann Nightforge öffnen. Steam startet beim ersten Spiel neu. Das Profil steht danach in
`~/Library/Application Support/Nightforge/wine-sandbox.sb`.

**Live-Test mit dem Nutzer.** Jeweils, ob es startet, normal läuft und wieder endet:
1. Ein Steam-Spiel aus dem Prefix (z. B. OxyRail): Start, Steam-Fenster, Overlay, Speichern, Beenden, Cloud-Sync.
2. Ein Steam-Spiel von einem externen Laufwerk („Spiele“ oder „Spiele test“): Start aus `Z:\Volumes\…`.
3. Ein Epic-Spiel mit Besitz-Datei (`requires_ot`): Es muss die Datei aus `legendary/tmp` lesen.
4. Ein GOG-Spiel mit Installer-Skript oder Redistributables: frisch installieren lassen.
5. Controller (DualSense) in einem Windows-Spiel.
6. Game Mode: Meldet macOS beim Spiel „Game Mode an“? Bleibt Steam aus dem Dock?
7. Steams Browser: Laden Bibliothek und Shop, klappt die Anmeldung nach einem Neustart?
8. MetalFX/D3DMetal in einem Spiel, das es nutzt (z. B. Wukong).

Dabei jeweils `~/Library/Application Support/Nightforge/Logs/wine.log` auf „nightforge-sandbox:“ und
„Operation not permitted“ prüfen.

**Ausschalten:** `defaults delete io.github.lordhayne.nightforge wineSandbox`, dann Nightforge neu starten.

**Danach:** Läuft alles, den Schalter standardmäßig einschalten. Bricht etwas, steht der Pfad im Log, und die Sperrliste
wird angepasst.

**Bekannte Grenzen**
- `sandbox_init` gilt bei Apple als veraltet. Fällt es weg, beendet sich der Helfer mit 71 und startet nichts. Mit
  Schalter läuft Wine also nie still ohne Sandbox.
- Steams eigene Anmeldedaten im Prefix bleiben für Spiele lesbar, wie unter Windows.
- Der Khronos-Loader (mit KosmicKrisp) sucht auch in `~/.config/vulkan`. Das ist gesperrt; bei Vulkan-Problemen mit
  KosmicKrisp zuerst dort nachsehen.

### Vulkan-Layer und winecx

- **Bestätigt per Probe (3.11., `dxvk-winecx.md` im Notizordner):** Mit MoltenVK direkt scheitert das Gerät, das DXVK
  verlangt (`geometryShader` + `shaderCullDistance`), an `VK_ERROR_FEATURE_NOT_PRESENT`. Über den Khronos-Loader 1.4.350
  mit Nightforges Layer kommt dasselbe Gerät hoch, ohne Layer nicht. Der Hebel steckt in winecx: CW Hack 25909,
  `CX_LIBVULKAN=<Loader>` zusammen mit `CX_ACTIVE_GRAPHICS_BACKEND=wined3d`, dazu `VK_DRIVER_FILES` und
  `VK_ADD_IMPLICIT_LAYER_PATH` auf die Dateien im Spiel-Bundle. Für 32-Bit-Spiele bietet MoltenVK 1.4.2
  `VK_EXT_external_memory_host` und nimmt die `HOST_ALLOCATION`-Puffer an, die Wines WoW64 anlegt (ebenfalls Probe).
  Offen: den x86_64-Loader liefern (Apache-2.0, am besten in CI gebaut) und die Umgebung in `Engine.gameEnvironment`.
  Erst dann L4D2, Mafia II und No Man's Sky auf DXVK bzw. Vulkan prüfen.
- **winecx hat keinen Vulkan-Loader, der Layer wird nie geladen.** Seine `winevulkan.so` lädt `libMoltenVK.dylib`
  direkt (Gcenx' 11.18 ging über `libvulkan.1.dylib`), also findet sich kein Layer aus
  `Nightforge Game.app/…/implicit_layer.d`. Seit PR #7 fehlen damit für Vulkan- und DXVK-Spiele: das Aussortieren
  nicht unterstützter Funktionen (No Man's Sky, DXVK in L4D2 scheitert genau daran), die Sampler-Grenze, der HDR-Filter
  und MetalFX. Ansatz: den Khronos-Loader (aus der Gcenx-Engine oder MoltenVK-Release) in die winecx-Engine legen und
  winevulkan auf ihn lenken (Name `libMoltenVK.dylib` → Loader, MoltenVK per ICD-JSON), dabei die „MoltenVK-ICD-Falle“
  aus den Game-Mode-Notizen beachten. Erst danach lässt sich PR #13 im Spiel prüfen.
- **KosmicKrisp** (LunarGs Vulkan-Treiber auf Metal, 28.10. getestet): Als x86_64 gebaut nach dem Rezept aus
  dappermint/winecx-gptk PR #12 (`shadexternals/mesa-kosmickrisp`, Mesa 063dfae + Patches für `fillModeNonSolid` und das
  Speicherbudget, Khronos-Loader 32fcb94; Homebrew `llvm`, `spirv-llvm-translator`, `spirv-tools`). winecx lädt ihn ohne
  Änderung: `CX_ACTIVE_GRAPHICS_BACKEND=wined3d`, `CX_LIBVULKAN=<libvulkan.1.dylib>`, `VK_DRIVER_FILES=<icd.json>`.
  Mit Unreal 5.7 (The Last Caretaker Demo) aber noch nicht nutzbar: vkd3d-proton 3.1 bricht ab („Lacking support for
  transform feedback“), DXVK 3.1.1 kann keine geteilten Ressourcen anlegen (`VK_KHR_external_memory_win32` fehlt) und das
  Spiel stürzt ab. Nächster Versuch: DXVK mit einem Patch, der geteilte Ressourcen ungeteilt anlegt, und ein Spiel ohne
  geteilte Texturen (DirectX 9–11). Nicht als Komponente ausgeliefert; Bau braucht Netz und LLVM (~2 GB).
  Neu seit 29.10.2026 in Mesa main: Geometry-Shader über „poly“ (9a40f0c6, 5c145789, 531e208d, 14f59d06 „kk: Advertise
  geometryShader“, MR 44786). `shaderCullDistance`, Tessellation und robustness2 waren schon da. Damit bekäme DXVKs
  Direct3D 9 sein Gerät, also Mafia II, Left 4 Dead 2 und die Source-Spiele. Unser Bau vom 28.10. (063dfae) ist älter,
  der nächste muss ≥ 14f59d06 sein. steamac (fxgl/steamac, `host/kosmickrisp/patches`) trägt dieselben vier als 0001–0004
  und dazu Transform Feedback in der GS-Emulation (0010–0014), was vkd3d-proton fehlte. steamac nutzt KosmicKrisp aber
  arm64 auf dem Host über Venus. Wir brauchen x86_64 unter winecx, gebaut in CI.
- **PR #13** (Entwurf): Layer-Fixes (freigegebene `CAMetalLayer`, Speicherleck pro Frame, Abbau, Retina pro Fenster).
  Kompiliert, aber ungetestet, weil der Layer unter winecx nicht läuft (siehe oben).
- **MetalFX auf der exportierten Metal-Queue** verlässt sich darauf, dass MoltenVK synchron einreicht. Mit
  `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0` könnte das Upscaling ein halbfertiges Bild lesen.
- **`steamwebhelper-wrapper.c`** startet den echten Helper ohne Job-Object. Wird der Wrapper beendet, bleibt CEF
  verwaist (passt zu den bekannten Shutdown-Hängern).

### Lieferkette

- **Nächtliche Daten gehen ungeprüft an alle.** `components.yml` und `profiles.yml` committen direkt auf `main`,
  umu-protonfixes und AreWeAntiCheatYet werden ab `HEAD` gelesen. Siehe „Nur geprüfte Komponenten ausliefern“ oben.
- **Build-Eingaben ohne Prüfsumme.** In `graphics.yml` `WINE_TOOLCHAIN_URL`, das Gcenx-Archiv, der inotify-Header und
  Klone per Tag, in `tools.yml` das cabextract-Archiv; dazu `brew install … || true`. Die Actions selbst sind seit dem
  Audit auf Commit-SHAs festgelegt, Dependabot hält sie aktuell.
- **Dependabot-PRs #21–#26** (cache 4→6, upload-artifact 4→7, download-artifact 4→8, setup-python 5→7) erst nach
  einem Release- oder Grafik-Build mergen. Ihre grünen Checks laufen nicht durch `release.yml` und `graphics.yml`, die
  diese Actions nutzen. upload- und download-artifact zusammen hochziehen.
- **Erster Lauf der Lizenz-Pakete (PR #14).** Nach den ersten Releases mit Lizenzen und Quellarchiv prüfen, dass
  `update-components.py` weiter genau ein Asset pro Komponente findet. Beim nächsten DXMT-Update die Lizenz prüfen
  (v0.80 ist MIT, neuere DXMT-Versionen LGPL).

### Steam und Start

- **Steams erstes Update auf einem frischen winecx-Prefix** (früher „rund 11 Minuten“) – Ursache gefunden und behoben
  (29.10., Branch `claude/first-start-6-1-18d92f`, siehe Roadmap 6.1):
  - Nightforge selbst hat die Schleife ausgelöst. Beim Entpacken schreibt Steam Valves `steamwebhelper.exe` zurück. Die
    Einrichtung sah das alle 2 s, tauschte den Wrapper ein und startete Steam neu – mitten in der Installation. Der
    Bootstrapper begann dann wieder mit „installed version 0“, alle 13 s (124-mal in 30 Minuten). Nur wenn die Installation
    zufällig zwischen zwei Prüfungen fertig wurde, ging es weiter.
  - Jetzt liest `SteamBootstrap` Steams Update-Log (nur Marker, die Steam nicht übersetzt). Getauscht und neu gestartet
    wird erst, wenn der neue Client läuft; `stopSteam` und die Hänger-Erkennung warten eine Installation ab.
  - Dazu zwei kleinere Fehler: Der allererste Start mit `-noverifyfiles` prüfte keine Updates und stand 92 s, bis
    Nightforge Steam neu startete. Jetzt startet Steam ohne `-noverifyfiles`, bis der Client da ist, und ein solcher
    Stillstand wird nach 15 s beendet. Und das Quit-Skript beendete Steam ohne `-noverifyfiles`, worauf Steam Valves Helper
    über den Wrapper installierte.
  - Danach hing noch der Neustart nach dem Tausch (93 s): gestartet, während das alte Steam noch beendet wurde. Jetzt
    startet die Einrichtung Steam nur neu, wenn Valves Helper schon läuft, wartet vorher, bis alles von Steam weg ist,
    und startet einen Client, der nach 20 s nicht hochgekommen ist („Client version“ in `console_log.txt`), noch einmal.
  - Gemessen: mit dem Schleifen-Fix 4:39 bis zum Anmeldefenster, im zweiten Lauf (57cb377) 4:13, davon 93 s der hängende
    Neustart, im dritten (a40e22a) 3:09, davon 26 s der hängende Neustart bis zum 20-s-Netz.
  - Der erste Neustart nach dem Update hing in allen drei Läufen beim Einlesen des Browser-Profils (nach „This is Chrome
    version“). Verdacht: Valves Browser hatte seinen Cache (`htmlcache`) halb angelegt, als er beendet wurde (im ersten
    Lauf, 2 s nach dem Client-Start beendet, hing nichts). Seit dem 29.10. leert die Einrichtung den Cache vor dem Neustart
    (vor der Anmeldung steht nichts darin). Ziel um 2:40 – beim nächsten frischen Durchlauf prüfen.
  - Nicht gemacht: den Wrapper schon im ~1-s-Fenster zwischen „Shutdown“ und dem Browser-Start tauschen (schnelleres
    Abfragen). Der neue Client prüft in genau diesem Fenster seine Dateigrößen und lädt einen zu früh getauschten Helper
    neu herunter.

### Leistung

- **Downloads:** Alle 3 s läuft ein kompletter Rescan mit `folderSize` über `downloading/<id>`. Nur die Manifeste der
  ladenden Spiele neu lesen und die Ordnergröße cachen.
- **SwiftUI:** `LibraryModel` ist ein `ObservableObject` mit 26 `@Published`, jede Änderung zeichnet alles neu.
  `@Observable` (ab macOS 14) oder das Modell aufteilen.
- **`MacSteam`** hat eine 1-Hz-Schleife; eine Exit-Quelle (`DispatchSource.makeProcessSource`) wäre ruhiger.

### Wartbarkeit

- `LibraryModel`, `Engine` und `LibraryView` haben je über 1000 Zeilen. Den SDK-Fallback gibt es 7-mal
  (`build.sh`, `tests/*/run.sh`), dazu etwa 10 eigene Process-Helfer und mehrfach definierte Pfadkonstanten.
- **`CompleteRemoval.Places.settingsDomain`** fällt ohne Bundle-ID auf `io.github.lordhayne.nightforge` zurück, und
  ohne Bundle-ID läuft jede Testbinary. Ein Test, der `CompleteRemoval.remove` ohne eigene Domäne aufruft, leert die
  Einstellungen der echten App. `CompleteRemovalTest` setzt seine eigene; sicherer wäre kein Rückfall auf die echte
  Domäne außerhalb der App.
- **`engine/patches`:** Die Patches werden in Glob-Reihenfolge angewendet (`frame-log` baut auf `metalfx-fit-window`
  auf, sortiert aber davor). Nummerieren und eine README mit Upstream-Stand anlegen; ein Umbenennen löst auf `main`
  einen neuen Grafik-Build aus.
