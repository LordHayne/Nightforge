# Entwurf: Bildraten-Sperre unter D3DMetal (0.3.5)

Stand 22.11.2026. Weg A gebaut (OK des Koordinators), Zweig `claude/d3dmetal-fps-035`; Messung offen. Auftrag: Nightforges Sperre (z. B. 60 FPS) soll auch auf D3DMetal greifen,
gleichmäßig und ohne spürbare Eingabeverzögerung. Spiele mit Anti-Cheat bleiben unberührt.

## Befund

- D3DMetal 3.0 (winecx 4.7.3 und der eigene Baustein, dieselbe Datei) kennt keinen Schalter für die Bildrate: 27
  `D3DM_`-Schalter, keiner dafür. Die Abgabe läuft in `DXGISwapChain::Present1` über `-[MTLCommandBuffer
  presentDrawable:]`; daneben `setMaximumDrawableCount:`, `setDisplaySyncEnabled:`, Semaphoren und `usleep`.
  `presentDrawable:afterMinimumDuration:` fehlt.
- **DXMT taktet genau damit.** `winemetal.so` (Baustein 11.18-dxmt0.80-17) enthält
  `presentDrawable:afterMinimumDuration:` und `displaySyncEnabled`; `d3d11.preferredMaxFrameRate` aus `dxmt.conf`
  geht dorthin. Das ist die Sperre, die bei MGS V, Frostpunk und The Forest 60 hält und die Thomas mag.
- Neuere Versionen: Apples Forum nennt für GPTK 4.0 beta 3 fünf Umgebungsvariablen in der Read Me, keine für die
  Bildrate (nicht selbst gelesen). CrossOver hat keine Sperre für D3DMetal, CodeWeavers verweist auf die Sperre im
  Spiel.

## Wege

### A – Abgabe umlenken wie DXMT (Empfehlung)

Ein Einhänger in `hide-steam-dock.dylib` (schon in jedem Wine-Prozess, kein neuer Ladeweg) ersetzt in
D3DMetal-Prozessen `-[_MTLCommandBuffer presentDrawable:]` durch `presentDrawable:afterMinimumDuration:1/limit`.
`setDisplaySyncEnabled:NO` wird dort auf `YES` gehalten, sonst gibt es keinen Bildschirmtakt, an dem sich die
Mindestdauer ausrichtet. Wukong mit Ø 201 FPS läuft offenbar ohne Sync.

- **Im Test belegt (x86_64 unter Rosetta, wie D3DMetal, M5 Pro, macOS 27.2):** Der Befehlspuffer ist
  `AGXG17XFamilyCommandBuffer`. `presentDrawable:` implementiert nur die Basisklasse `_MTLCommandBuffer` (Metal.framework),
  mit und ohne `MTL_HUD_ENABLED`. Umgelenkt dort liefen 5 von 5 Abgaben über `afterMinimumDuration`, ohne Schleife.
  Die Klasse wird über ihren Namen gefunden, ein Gerät muss nicht angelegt werden.
- **Nur wo gewollt:** Es wird nur eingehängt, wenn (1) D3DMetal.framework im Prozess geladen wird
  (`_dyld_register_func_for_add_image`) und (2) `D3DM_MAX_FPS` in der Umgebung steht. DXMT, DXVK, Steam und
  Mac-Programme laden D3DMetal nicht und bleiben unberührt. Nightforge setzt `D3DM_MAX_FPS` heute schon nur für
  D3DMetal-Starts.
  Neu: Für Spiele mit Anti-Cheat (`antiCheat`, `ownAntiCheat`) setzt `prepareLaunchEnvironment` es immer auf leer.
  Damit ist der Einhänger dort aus, auch wenn ein D3DMetal-Spiel davor lief. Das kostet höchstens einen Steam-Neustart
  beim Wechsel. Fehlt `_MTLCommandBuffer` nach einem macOS-Update, geschieht nichts, und das Spiel läuft wie heute.
- **Gleichmäßigkeit:** wie DXMT, also an den Bildschirmtakt gebunden. 60 auf 120 Hz heißt jedes Bild zwei Takte.
  Krumme Werte (z. B. 50 auf 120 Hz) wechseln zwischen zwei und drei Takten, wie bei DXMT.
- **Eingabeverzögerung:** wie DXMT. Die CPU läuft vor, bis D3DMetal kein Drawable mehr bekommt, also bis zu
  `maximumDrawableCount − 1` Bilder Warteschlange (bei 3: bis ~33 ms bei 60 FPS). Welchen Wert D3DMetal setzt, ist
  ungeprüft (es ruft `setMaximumDrawableCount:`).
  Möglicher Zusatz A2: vor der Abgabe auf der CPU bis kurz vor den Termin warten, wie DXVKs Limiter. Dann ist die
  Schlange leer, und die Mindestdauer richtet nur noch am Takt aus. Erst nach Messung von A, wenn sich A träge anfühlt.
- **Aufwand:** ~120 Zeilen Objective-C in `wrapper/` (eigene Datei, in `hide-steam-dock.dylib` gebaut), Probe und
  Regeltest nach dem Muster `tests/NetworkOrderTest`, ~20 Zeilen Swift (Anti-Cheat leert `D3DM_MAX_FPS`, Kommentar
  „Apple's readme“ richtigstellen, `GameTestMeasure`/`limitState`: D3DMetal hält wieder), `DockHider.sessionVersion` 2
  (F4-Weg: die Sitzung startet einmal neu). Kein Patch an Wine, DXMT oder D3DMetal.
- **Risiko:** gering bis mittel. Eingehängt wird in eine private Metal-Klasse, nur im D3DMetal-Spielprozess. Prüfen:
  MetalFX (`D3DM_ENABLE_METALFX`), Vollbild/„Direct“, `D3DM_ENABLE_ASYNC_COMMIT`, Alt-Tab und verdecktes Fenster (Apple-Forum:
  D3DMetal hängt in present bei verdecktem Fenster; die Mindestdauer darf das nicht verschlimmern).

### B – Sperre im Spiel setzen (Einstellungsdatei)

Für Unreal-Spiele (Wukong, Hogwarts, It Takes Two) `FrameRateLimit` in `GameUserSettings.ini`, über den
vorhandenen Weg `Engine.applyFileEdits`. Keine Injektion, oft die beste Latenz, weil die Engine selbst taktet.
Dagegen spricht: Es gilt nur je Spiel oder Engine (Control/Northlight nicht), es ändert eine Einstellung, die der
Spieler im Spiel sieht, und Spiele können sie überschreiben. Taugt als Ergänzung für einzelne Profile, nicht als Lösung.

### C – Nur Sync erzwingen

`setDisplaySyncEnabled:` immer `YES`. Das deckelt auf die Bildschirmrate (120), nicht auf 60. Als Teil von A nötig,
allein nicht genug.

### D – Patches (nur beschrieben)

D3DMetal ist Apples Binärdatei, also kein Patch. Ein Wine-Patch (LGPL) in winemac käme an die Abgabe nicht heran, die
liegt in D3DMetal. Ein DXGI-Shim auf der Windows-Seite (Present abfangen und schlafen) wäre eine Injektion in den
Windows-Prozess: mehr Aufwand und für Anti-Cheat heikler als A. Nicht empfohlen.

## Was ungeprüft ist

- Frame-Zeiten und Eingabeverzögerung in einem echten Spiel. Die Zeitmessung hier ist nicht aussagekräftig: Diese
  Session läuft gedrosselt im Hintergrund, und selbst natives `mach_wait_until` wachte bis zu 126 ms zu spät auf. Das
  betrifft auch A2.
- Ob `afterMinimumDuration` bei `displaySyncEnabled = NO` den Takt hält. Deshalb erzwingt A den Sync.
- Welche `maximumDrawableCount` D3DMetal setzt.

## Messplan (Starts über den Koordinator, nach dem Bau)

Wukong Benchmark Tool (D3DMetal, ohne Anti-Cheat), Sperre 60, Messung über die versteckten Schalter
(`GameTestMeasure`, HUD-Frame-Log):
1. vorher (heute Ø 201) und mit A: Ø, 1-%-Tiefs, Streuung der Frame-Zeiten;
2. Gegenprobe ein DXMT-Spiel mit 60 (OxyRail): Streuung vergleichbar?
3. Thomas' Eindruck zu Eingabe und Gleichmäßigkeit; wenn träge, A2 nachziehen;
4. Overwatch und andere Anti-Cheat-Spiele: im Protokoll kein Einhängen (eine Zeile im wine.log nur, wenn eingehängt wird).

## Gebaut (Weg A)

- `wrapper/d3dmetal-pace.m` (+ Regeln in `d3dmetal-pace-rules.c`, in `hide-steam-dock.dylib`): Der Prozess beobachtet
  das Laden nur, wenn `D3DM_MAX_FPS` gesetzt ist. Er hängt sich ein, wenn D3DMetal.framework lädt, die Freigabedatei
  `~/Library/Application Support/Nightforge/d3dmetal-pace` („<Limit>\n<Windows-Ordner des Spiels>“) dasselbe Limit
  nennt, `argv[0]` (Wines Windows-Pfad des Programms) in diesem Ordner liegt und `_MTLCommandBuffer`
  `presentDrawable:` sowie `presentDrawable:afterMinimumDuration:` hat. Sonst ändert sich nichts, auch nicht der Sync.
  Dabei entsteht eine Protokollzeile je Prozess.
- Anti-Cheat auf allen Wegen: `prepareLaunchEnvironment(antiCheat:)` und `directLaunchEnvironment(antiCheat:)` geben einem
  Spiel mit `NextStart.handsOff` nie `D3DM_MAX_FPS`. Hat Steam die Variable noch, startet es neu. Das gilt auch für die
  gemerkte Umgebung aus F5, denn gemerkt wird nach `prepare`. Läuft schon ein anderes Spiel in Steam und kann es
  deshalb nicht neu starten, fehlt die Freigabe: `D3DMetalPace.prepare` löscht sie bei jedem Start eines Anti-Cheat-Spiels
  und bei jedem Start auf einer anderen Schicht.
- `DockHider.sessionVersion` 2: Die Wine-Sitzung startet einmal neu und lädt die neue Bibliothek.
- Tests: `tests/D3DMetalPaceTest` (Regeln, dazu die Bibliothek mit der Bauzeile aus build.sh in einem x86_64-Programm
  mit Bild unter D3DMetals Namen; sieben Fälle) und `EngineLayoutTest.antiCheatPace` (alle Wege und die Freigabe).
- Bleibt: `GameTestMeasure` und die Läuft-Liste zählen D3DMetal weiter als „hält kein Limit“, bis die Messung zeigt,
  dass die Sperre hält. A2 (vorher auf der CPU warten) ist eine Notiz für nach der Messung.
