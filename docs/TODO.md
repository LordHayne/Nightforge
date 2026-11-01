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
- **Release-Stand einfrieren:**
  - Alle Testreihen grün.
  - Ersteinrichtung mit leerem HOME (`build/fh`, siehe Notizen zum Fresh-Setup-Test).
  - Kurzer Live-Durchlauf: Windows-Spiel über Steam, Mac-Version, Epic, GOG, TV.
  - Version 0.2.1-dev → 0.3.0.
  - Release-Notizen seit v0.2.0 auf Deutsch und Englisch.
- **Veröffentlichen, nur mit ausdrücklichem OK des Nutzers:**
  - Integrationszweig pushen und über einen PR nach `main` bringen.
  - Tag `v0.3.0` löst `release.yml` aus.
  - Danach die zurückgehaltenen Dependabot-PRs #21–#26 prüfen (sie warten auf einen Release- oder Grafik-Build).

## Nach dem Engine-Wechsel neu prüfen

Die Tests vom 26.10. liefen größtenteils noch auf Wine 11.18 (Gcenx). Seit PR #7 läuft winecx 4.7.3.

- **Getestete Spiele auf winecx gegenprüfen.** Palworld (DXMT, 60 FPS), Deadlock (DXVK, 60–120 FPS),
  Left 4 Dead 2 (WineD3D), OxyRail und 7 Days to Die. Die Ergebnisse und Profile in
  `profiles/mac.json` beziehen sich auf 11.18.
- **Left 4 Dead 2.** Auf 11.18 scheitert DXVK an seinen Puffern (`vkCreateBuffer`, MoltenVK lehnt
  externe Speicher-Handles ab). WineD3D läuft, stürzt aber nach etwa einer Minute ab, und im Spiel fehlte der Ton.
  `-vulkan` (Valves DXVK) und WineD3D mit Vulkan starten nicht. Auf winecx (26.10.) scheitert DXVK schon früher:
  `VK_ERROR_FEATURE_NOT_PRESENT` bei `vkCreateDevice`, weil der Vulkan-Layer dort nicht geladen wird (siehe
  „Aus dem Code-Audit“ → Vulkan-Layer). WineD3D bleibt der Weg. Zum Ton:
  In der Cloud-Konfiguration stehen `volume "0.008"` und Quadro-Lautsprecher, also erst im Spiel unter
  Optionen → Audio hochdrehen, bevor man Wine verdächtigt.
- **DXVK unter winecx gar nicht nutzbar?** Mafia II (31.10., GOG) scheitert genau wie L4D2: `vkCreateDevice` lehnt das
  5. und 39. Feature ab (`geometryShader`, `shaderCullDistance`), „DxvkAdapter: Failed to create device“ – viermal in
  `Logs/wine.log`, dreimal davon gleich nach Steams `gldriverquery`. DXVK-macOS 1.10.3 verlangt beide; ohne den Vulkan-Layer
  (winecx hat keinen Loader) bleibt das so. Für D3D10/11 vermutlich genauso (Geometry-Shader ab Feature-Level 10) – mit
  einem D3D11-Spiel auf DXVK nachprüfen. Gebaut: Unter winecx (`Engine.vulkanLayerLoads` false) ist die D3D9-Leiter
  „WineD3D, DXVK“, sonst wie bisher. Eine neue Leiter fängt von vorn an, alte D3D9-Stände starten also bei WineD3D.
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
  Klären, ob der 11.18-Weg noch gebraucht wird.

## DirectX 12 (D3DMetal)

- **Echtes DX12-Spiel aus den Top 100 testen.** Gemessen ist bisher nur der Wukong-Benchmark
  (D3DMetal 69 FPS im Schnitt). Kandidaten: Elden Ring (offline, ohne EAC),
  Resident Evil 4, Monster Hunter Wilds, Street Fighter 6, Space Marine 2, Planet Zoo 2.
- **Bekannte Stolpersteine, die automatisch abgefangen werden sollen** (Plan in den Notizen der DX12-Sitzung):
  `ROSETTA_ADVERTISE_AVX=1` lässt Wukong abstürzen; Unreals Hinweis „AMD driver has known issues“
  (D3DMetal meldet sich als AMD); Frame Generation und DLSS schalten sich beim ersten Start ein und stürzen ab.
- **MTL_HUD** erscheint unter D3DMetal 4.0 nicht (Metal-4-Backend?).
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
  (während des Updates `StateFlags 1030`, `BytesDownloaded 0`). `LibraryScanner.updateState` liest nur das
  Manifest. Kandidat: die Größe von `steamapps/downloading/<appid>` gegen `BytesToStage` rechnen, oder den
  Fortschritt aus `content_log.txt` lesen. Danach ist das Spiel von selbst gestartet. Der Grund, warum das Update
  am Nachmittag dreimal scheiterte, war ein hängendes Steam (Log stand seit 16:46). Die Erkennung dafür liegt auf
  dem GOG-Zweig (557c2c2).
- **Steam bleibt nach dem Beenden von Nightforge noch etwa eine Minute** (Nutzer, 31.10., „hat nur gedauert, bis es
  zu ging“): `steam-shutdown.sh` wartet immer 30 s auf Cloud-Spielstände (`sleep 30`), dann bis zu 20 s auf
  Steams Ende, dann `wineserver -k`. Die 30 s nur, wenn kurz vorher ein Spiel lief (zum Beispiel in den letzten
  5 Minuten, Zeitpunkt aus Nightforge übergeben). Sonst sofort `-shutdown`. Dann ist Steam in wenigen Sekunden weg.
- **Windows-Steam ignoriert manchmal `steam.exe -shutdown`.** Dann hilft nur `wineserver -k`. Läuft Steam gar
  nicht, startet `-shutdown` ein neues Steam. Nightforges eigenes Beenden darauf prüfen.
- **Angemeldete Steam nimmt keine Befehle mehr an** (31.10., OxyRail, Branch `claude/gog-7-3-e69c3b`): Seit etwa
  16:46 kam kein `-applaunch` mehr in `console_log` an. Nightforges Client endete trotzdem nach 0,2–0,3 s (macOS-Log,
  wie bei den funktionierenden Starts), und `configstore_log`/`appinfo_log` liefen weiter. Gebaut (`SteamCommands`):
  War Steam angemeldet und fertig gestartet und loggt 15 s lang kein `ExecCommandLine` für den Start, folgt „Steam
  reagiert nicht – wird neu gestartet …“: `wineserver -k` ohne `-shutdown` (nur wenn kein Windows-Spiel läuft;
  ein Client-Update läuft vorher zu Ende), stiller Neustart, Anmeldung abwarten, Start noch einmal. Live prüfen,
  sobald Steam wieder so hängt. Ursache des Hängers selbst offen (letzte Zeile: `SlowJSMethodCall Messaging.PostMessage`).
- **steam-shutdown.sh** hält jeden Prozess unter `\steamapps\common\` für ein Spiel, auch in
  Test-Prefixen, und holt Nightforge dann nach vorne.
- **Steam-Anmeldung zwischen den Steams.** Steam für Mac und die Windows-Steam melden sich gegenseitig ab
  („Session Replaced“). Beobachtet wurde auch: Steam hängt, beendet sich nicht oder drängt sich nach vorne.
  Ursache und Plan (Steam für Mac in die Ersteinrichtung, Regeln für den Wechsel): `docs/PLAN-STEAM-FUER-MAC-EINRICHTUNG.md`.
  Wechselregeln (`SteamSwitch`) und Erststart-Baustein (`MacSteamPrep`) sind gebaut, aber noch nicht live getestet.
  Offen: die Haken in `Setup.swift` (nach setup-speed) und die Anzeige in `SetupView` (nach design-setup-home).

### Engine-Rückfall (3.3, Branch `claude/engine-rollback-02a61e`)

- **Speicher-Anzeige zählt die gehaltene Engine doppelt.** Sie ist ein APFS-Klon und teilt ihre Blöcke mit dem
  Original. `Library.folderSize` summiert aber `totalFileAllocatedSize`, also erscheint sie in Einstellungen ›
  Speicher mit voller Größe (bis 1,4 GB), solange das Original noch da ist.
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

## Controller

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
  „Startseite | Bibliothek“ erscheinen nur mit verbundenem Controller. Der Sprung um fünf Spiele ist weg, L2/R2 und ☰
  bleiben; der Controller-Test sagt „Geht zur Startseite/Bibliothek“. Live bestätigt (1.11.). Am Gerät noch ansehen:
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
  (FramePacing) auch für D3DMetal-Spiele greift.
- **TV-Modus an einem echten TV** (`GameDisplay.swift`, PR #6): Mit einem Monitor am MacBook bestätigt (Fenster
  wandert beim Anstecken, Windows-Spiel öffnet dort, Hauptbildschirm kommt danach zurück). Am TV noch offen: die
  Erkennung am Namen (`Candidate.isTV`, Liste der Marken) und das Vollbild des Launchers.
- **Hinweis „Spielt auf: …“** neben Play, wenn ein externer Bildschirm das Spiel bekommt, damit man weiß, wo es
  aufgeht. Ansatz: `GameDisplay.screen?.localizedName` in `LibraryView`, nur bei mehr als einem Bildschirm.
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
- **Tests in der CI** laufen seit PR #5 (`ci.yml`: Build, alle `tests/*/run.sh`, Profil- und Manifest-Prüfung).
  Offen: dieselben Tests als Pflicht für die Bot-PRs aus dem Punkt darüber. Echte Spiele bleiben Handarbeit.
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

## Aus dem Code-Audit

Befunde vom 26.10., die noch offen sind. Alles andere ist behoben (PR #4, #5, #11, #12, #14–#19).

### Entscheidungen

- **Updates sind nicht echt signiert.** `Updater.install` prüft nur `codesign --verify` auf eine Ad-hoc-Signatur,
  `scripts/install.sh` lädt ohne Prüfsumme. Bewusst offen gelassen. Wege: ein Ed25519-Schlüssel als Repo-Secret
  (Release-Zip signieren, im Updater und in install.sh prüfen) oder ein Apple-Developer-Account (Developer ID, Notarisierung).

### Vulkan-Layer und winecx

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
- **`engine/patches`:** Die Patches werden in Glob-Reihenfolge angewendet (`frame-log` baut auf `metalfx-fit-window`
  auf, sortiert aber davor). Nummerieren und eine README mit Upstream-Stand anlegen; ein Umbenennen löst auf `main`
  einen neuen Grafik-Build aus.
