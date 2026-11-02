<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHR8KtHEsXhdqKsNdwD (1.11.2026) -->

## Welche macOS-Version Nightforge wirklich braucht (Stand 1. November 2026)

### Kurzfassung

**„macOS 14 oder neuer“ stimmt für 0.3.0 nicht.** Das liegt an der Engine, nicht an D3DMetal oder der App.

- winecx-gptk 4.7.3 ist nur für macOS 26 und 27 gebaut. Das ist die Engine, die Nightforge bevorzugt. Ihr README sagt: „macos 27 and 26, with a deployment floor of 26.0“. Die Programmdateien bestätigen das: wine, wineserver, ntdll.so, winemac.so und alle 30 Wine-eigenen Unix-Bibliotheken außer winemetal.so sind für macOS 26.0 gebaut (SDK 27.0).
- Auf macOS 14.0 bis 14.3 startet dieses Wine sicher nicht. ntdll.so braucht zwingend os_sync_wait_on_address, und das gibt es erst ab macOS 14.4.
- Auf 14.4 bis 15.x ist das Verhalten unbekannt. Es fehlt zwar kein Symbol mehr. Aber der Code wurde für macOS 26 übersetzt, deshalb hat der Compiler alle Versionsabfragen bis macOS 26 entfernt. Die neueren Pfade laufen also ohne Prüfung. Das ist ungetestet und laut Maintainer nicht unterstützt.
- Nightforge nimmt winecx immer, egal welches macOS läuft (Engine.swift:18-20). DirectX 12 über D3DMetal hängt an winecx und damit praktisch an macOS 26.
- D3DMetal 4.0b3 selbst nennt macOS 14.0 als Minimum. Eine fest eingebundene Teilbibliothek braucht aber faktisch 14.4. Die Metal-4-Teile laufen erst ab 26, laut einer Drittquelle erst ab 27 (unsicher).
- DXMT 0.80 setzt laut eigenem Wiki macOS 14 voraus und empfiehlt 15. Auf 14 zeigt es Bildfehler. Nightforges eigener DXMT-Build ist für minos 15.0 übersetzt, dadurch sind DXMTs eigene Abfragen auf macOS 15 entfernt.
- AVX-Spiele brauchen macOS 15, weil Rosetta AVX erst dort ausführt. KosmicKrisp braucht macOS 26.
- Unkritisch: MoltenVK (12), Steam für Mac (12), legendary und gogdl (11/12), GameController (11.x), MetalFX-Hochskalierung (13), Spielmodus (14).
- Der SwiftUI/AppKit-Code im Repo ist sauber für macOS 14. Er nutzt keine API über 14, deshalb braucht er auch kein #available.

### Empfehlung

1. Für 0.3.0 „macOS 26 Tahoe oder neuer“ schreiben, als Pflicht. Getestet ist auf 26 und 27, und die Engine fängt bei 26.0 an.
  - „macOS 15“ wäre nicht ehrlicher als 14. Der Hauptblocker (winecx) trifft 14 und 15 gleich.
  - „macOS 26 empfohlen“ würde nahelegen, dass 14 und 15 gehen. Das stimmt für die Hauptfunktion (Windows-Spiele) nicht.

2. Minimal umsetzen: LSMinimumSystemVersion 26.0, die Prüfung in install.sh auf 26, README, Release-Text und Landingpage anpassen.
3. Besser, wenn Zeit ist (weiche Grenze): Die App bleibt auf 14 und 15 startbar. Dort funktionieren Mac-Versionen über Steam für Mac und Cloud-Spiele. Unter macOS 26 lädt die App aber keine winecx-Engine und sagt klar, warum.
4. Später, als Weg B: echte Unterstützung für macOS 15 mit Einschränkungen. Dafür braucht es:macOS 14 lohnt sich nicht: Es braucht ohnehin 14.4, hat kein AVX und DXMT zeigt Bildfehler.
  - Gcenx-Wine als Engine unter 26,
  - einen DXMT-Build mit festem Deployment-Ziel,
  - Hinweise „DirectX 12 braucht macOS 26“,
  - einen Test auf einem echten Mac mit macOS 15.

### Wie ich geprüft habe (und was ich nicht konnte)

- Archive: Ich habe die Release-Archive aus `components/manifest.json` geladen. Die SHA-256-Werte stimmen mit dem Manifest überein.
- Mindestversion der Binärdateien: Mit llvm-objdump habe ich LC_BUILD_VERSION (minos und SDK) ausgelesen.
- Symbolabgleich: Die importierten System-Symbole habe ich mit den .tbd-Stubs der macOS-SDKs 14.0, 14.2, 14.4, 14.5 und 15.0 verglichen [64]. Die Objective-C-Selektoren habe ich mit den Headern der SDKs 14.0 und 15.0 verglichen. Beide Abgleiche arbeiten mit Heuristiken.
- Nichts ausgeführt: Die Umgebung war ein Linux-Container ohne Mac. Ob etwas auf 14 oder 15 wirklich läuft, ist deshalb nirgends getestet.
- Annahme zu dyld (unsicher): Nach meinem Kenntnisstand lehnt dyld eine Bibliothek nicht allein wegen eines höheren minos ab, sondern scheitert erst an fehlenden Symbolen. Dafür spricht: D3DMetal 3.0 enthält eine für 15.4 gebaute Teilbibliothek und gilt trotzdem als lauffähig ab 14. Auf echter Hardware nicht geprüft.
- Gesperrte Hosts: Für folgende Seiten habe ich nur Suchergebnis-Ausschnitte; die Aussagen dazu sind entsprechend unsicher:
  - help.steampowered.com, store.steampowered.com, steamcommunity.com
  - support.apple.com, www.apple.com
  - macrumors.com, eclecticlight.co, applegamingwiki.com, appleinsider.com, www.phoronix.com
  - www.codeweavers.com, support.codeweavers.com
  - docs.mesa3d.org, www.lunarg.com, vulkan.lunarg.com
  - ports.macports.org

- GitHub: Die API für Repos außerhalb dieser Sitzung antwortete mit 403. raw.githubusercontent.com, Release-Downloads und developer.apple.com (einschließlich der Doku-JSONs) gingen.

### Baustein → Mindestversion → Folge auf 14 und 15

| Baustein (Version in Nightforge) | Mindestversion mit Beleg | Folge auf macOS 14 | Folge auf macOS 15 |
|---|---|---|---|
| **winecx-gptk 4.7.3** (Wine 11.17 mit Änderungen aus CrossOver 26.3; bevorzugte Engine) | README: „deployment floor of 26.0“ [1][2]. Binärdateien: minos 26.0, SDK 27.0 (eigene Prüfung). `ntdll.so` braucht zwingend `os_sync_wait_on_address`, das es ab 14.4 gibt [3] | **14.0–14.3: Wine startet nicht**, weil dyld ein Symbol fehlt (aus dem Symbolabgleich sicher). 14.4 und neuer: nicht unterstützt, ungetestet | Kein fehlendes Symbol, aber nicht unterstützt. Die Versionsabfragen sind wegoptimiert, das Verhalten ist **unsicher** |
| **Gcenx Wine 11.18** (Engine `wine`, bleibt im Manifest) | „macOS Catalina and greater“ [4]. Binärdateien: minos 10.15, `os_sync` nur schwach eingebunden | läuft, aber ohne D3DMetal | läuft, aber ohne D3DMetal |
| **D3DMetal 4.0b3** (Beta von GPTK 4) | Text in der Binärdatei: „D3DMetal requires Apple silicon and macOS 14.0 Sonoma or higher“, `LSMinimumSystemVersion` 14.0. Die fest eingebundene `libdxccontainer.dylib` hat aber minos 26.4 und braucht `operator delete(void*, __type_descriptor_t)`, das erst ab dem 14.4-SDK existiert. Metal 4 (`MTL4*`, ab 26) [30], `MTLResidencySet` (ab 15) [29], Frame-Interpolation und Denoiser (ab 26) [27][28] sind nur schwach eingebunden | **14.0–14.3: lädt nicht.** 14.4 und neuer: lädt vermutlich mit dem Metal-3-Pfad, ist aber an winecx gebunden | lädt vermutlich, ist aber an winecx (26) gebunden. Der Metal-4-Pfad kommt laut Drittquellen erst mit macOS 27 [12][13] (**unsicher**) |
| Ältere GPTK-Versionen (zum Vergleich) | 1.0: macOS 14 (Sonoma-Beta) [6]. 2.1 und 3.0: „macOS 14 Sonoma or higher“ [7]. AVX über Rosetta ab GPTK 2 mit macOS 15 [9]. D3DMetal in CrossOver brauchte „Sonoma“ [14]. CrossOver 26 liefert D3DMetal 3.0 [12] | — | — |
| **DXMT 0.80** (eigener Build `graphics-11.18-dxmt0.80-13` und Upstream) | Wiki: Minimum macOS 14, „really recommended“ macOS 15 [15]. Auf 14 werden Shaderfunktionen aus Metal 3.2 zu No-ops, das gibt Bildfehler [16]. `winemetal.so` hat in beiden Builds minos 15.0 und SDK 15.1 | **Bildfehler** möglich, das sagt das Projekt selbst. Dazu kommt: Die Zweige mit `@available(macOS 15, *)` [18] sind wegkompiliert. Selektoren erst ab macOS 15 wie `addMeshRenderPipelineFunctionsWithDescriptor:error:` oder `binaryArchives` an Mesh- und Tile-Deskriptoren laufen dann ungeschützt. Das kann abstürzen, falls DXMT Binärarchive nutzt (**unsicher**) | läuft wie vorgesehen |
| **MetalFX** | Spatial und Temporal Scaler ab 13.0 [25][26]. Frame-Interpolation und Temporal Denoised Scaler ab 26.0 [27][28]. DXMT: Umweg DLSS → MetalFX Temporal „should work on Sonoma+“ [17] | Hochskalierung geht (DXMT, D3DMetal und der Vulkan-Layer). Frame-Generierung und Denoising gehen nicht | wie auf 14 |
| **MoltenVK 1.4.2** | „Raise minimum target to macOS 12.0“ [20], minos 12.0 | läuft | läuft |
| **DXVK-macOS 1.10.3** | keine eigene Angabe, braucht MoltenVK ≥ 1.2 [21] | läuft | läuft |
| **KosmicKrisp** | macOS 26, nur Apple silicon, Metal 4 [22][23][24] | **nicht verfügbar**, nur MoltenVK | **nicht verfügbar**, nur MoltenVK |
| **Rosetta 2 und AVX** | AVX/AVX2 ab macOS 15 [9][10]. `ROSETTA_ADVERTISE_AVX=1` sorgt nur dafür, dass Rosetta AVX gegenüber dem Programm meldet [11]. Rosetta als Allzweck-Werkzeug gibt es bis macOS 27, danach nur noch eine Teilmenge für ältere Spiele [31][33] | **AVX-Spiele** brechen mit „illegal instruction“ ab oder starten nicht. Die Variable wirkt nicht | AVX und AVX2 gehen, AVX-512 nicht |
| **Steam für Mac** | ab macOS 12 seit dem 15.10.2025 [34]. Nativ für Apple silicon gibt es ihn seit 2025 als Beta; ob das schon im stabilen Kanal ist, ist **unsicher** [35] | läuft | läuft |
| Windows-Steam in Wine | Windows 10 oder neuer, seit 2026 nur 64 Bit [36][37]. Hängt nicht von macOS ab | — | — |
| **legendary / gogdl** (Roadmap) | legendary-README: „macOS (12.0+)“ [38]. Die aktuellen arm64-Binärdateien von legendary und gogdl haben minos 11.0 (PyInstaller auf `macos-15`) [39] | läuft | läuft |
| **Spielmodus** | macOS 14, Apple silicon, nur im Vollbild [41]. `LSSupportsGameMode` gibt es erst ab 26.0 [43]. Auf 14 und 15 entscheidet die Kategorie games [42]. macOS 26 aktiviert den Spielmodus nicht für Programme, die direkt aus dem Terminal gestartet werden [32] | Im Prinzip ja, über die Kategorie im Spiel-Bundle. Ob er bei direkt gestartetem Wine greift, ist **unsicher** | wie auf 14 |
| **GameController** | `GCDualSenseGamepad`, `GCDualSenseAdaptiveTrigger` und `shouldMonitorBackgroundEvents` ab 11.3. `GCDeviceBattery`, `Light` und `Haptics` ab 11.0 [44]–[47] | alles vorhanden | alles vorhanden |
| **Gatekeeper** (ad-hoc signiert, nicht notarisiert) | macOS 15 hat „Ctrl-Klick → Öffnen“ abgeschafft [48] | Ctrl-Klick → Öffnen geht noch | nur noch über Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“ |
| **Die App selbst** | `Package.swift` `.macOS(.v14)`, Info.plist 14.0. Der Code nutzt nichts über 14 | läuft | läuft |

### Was das auf macOS 14 und 15 konkret heißt

#### macOS 14 (Sonoma)

- 14.0 bis 14.3: Windows-Spiele gehen gar nicht. winecx und D3DMetal 4.0b3 laden nicht.
- 14.4 und neuer: Die Engine läuft außerhalb ihres Supports und ist ungetestet. Selbst wenn sie startet, gilt:
  - AVX-Spiele fallen weg. Viele neuere Spiele brauchen AVX; Rosetta auf 14 hat es nicht.
  - DXMT zeigt laut Projekt Bildfehler.
  - KosmicKrisp, Frame-Generierung und Metal 4 fallen weg.
  - DirectX 12 hängt an winecx und ist damit offen.

- Was geht: Mac-Versionen über Steam für Mac, die App-Oberfläche, Controller, MetalFX-Hochskalierung und vermutlich der Spielmodus.
- Gatekeeper: Ctrl-Klick → Öffnen funktioniert hier noch.

#### macOS 15 (Sequoia)

- AVX geht, und DXMT läuft auf seiner empfohlenen Version.
- winecx ist offiziell nicht unterstützt. Mit winecx hängen auch D3DMetal und DirectX 12 in der Luft.
- Es fehlen: KosmicKrisp, Metal 4, Frame-Interpolation und der Denoiser.
- Gatekeeper:
  - Es geht nur noch über „Dennoch öffnen“ in Datenschutz & Sicherheit [48].
  - xattr -dr com.apple.quarantine funktioniert laut Community-Berichten weiter auf 15 und 26 [51]; eine Aussage von Apple gibt es dazu nicht.
  - Unter 15.1 sollen unsignierte Apps zeitweise ganz blockiert gewesen sein, behoben in 15.2 [50] (unsicher).
  - Unter 26.6 soll „Überall“ nur noch signierten, nicht notarisierten Apps helfen [52] (unsicher).
  - App Translocation für Apps mit Quarantäne-Attribut ist unverändert [53].
  - Die Installation per curl setzt kein Quarantäne-Attribut, der Gatekeeper-Schritt entfällt dort ganz.

#### Für alle Versionen

- Unter macOS 27 wird Rosetta nach dem Upgrade nicht automatisch wiederhergestellt [33]. Der Knopf „Install Rosetta“ in Nightforge ist dafür richtig.
- Ab macOS 28 ist Rosetta nur noch für „legacy games“ vorgesehen [31][33]. Ob x86_64-Wine dazuzählt, sagt Apple nicht. Das ist ein Risiko für jede Nightforge-Version (unsicher).

### SwiftUI und AppKit

**Stand im Repo:**

- Es gibt kein #available. Weil das Package auf macOS 14 zielt, würde der Compiler jede ungeschützte API ab 15 als Fehler melden. Der Repo-Code nutzt keine.
- Was der Code nutzt:
  - ObservableObject statt @Observable
  - .ultraThinMaterial (ab 12)
  - onChange(of:) { _, _ in } (ab 14)
  - NSApp.activate() ohne Argument (ab 14) [63]
  - die Window-Szene mit .windowStyle(.hiddenTitleBar)
  - GameController nur mit Basis-APIs (ab 11)
  - SF Symbols bis Version 5, zum Beispiel visionpro (ab macOS 14)

- Der Objective-C-Wrapper wrapper/nightforge-vulkan-metalfx.m:45,69 ist sauber geschützt: @available(macOS 13.0, *) und -weak_framework MetalFX in build.sh:60.

**Ab welcher macOS-Version typische APIs eines heutigen Launchers verfügbar sind** (aus den Doku-JSONs von Apple):

| API | macOS ab |
|---|---|
| `onGeometryChange` | 13.0 (zurückportiert) [62] |
| `@Observable`/`@Bindable` [59], `onChange(of:initial:_:)`, `ContentUnavailableView`, `symbolEffect`, `scrollTargetBehavior`, `onKeyPress`, `containerBackground(_:for:)`, `toolbar(removing:)`, `NSApplication.activate()` | 14.0 |
| `onScrollGeometryChange` [58], `onScrollPhaseChange`, `onScrollVisibilityChange`, `ScrollPosition`, `Tab`/`.sidebarAdaptable`, `toolbarBackgroundVisibility` [60], `windowToolbarFullScreenVisibility`, `windowBackgroundDragBehavior`, `containerBackground(…, for: .window)` [61], `WindowStyle.plain`, `pointerStyle`, `presentationSizing`, `MeshGradient` | 15.0 |
| `glassEffect` [54], `GlassEffectContainer` [55], `.buttonStyle(.glass)`, `ToolbarSpacer` [57], `backgroundExtensionEffect`, `scrollEdgeEffectStyle`/`scrollEdgeEffectHidden`, `safeAreaBar`, `ConcentricRectangle`, `NSGlassEffectView` [56] | 26.0 |

**Risiken im neueren lokalen Code mit Liquid Glass** (den ich nicht sehen konnte):

1. Den Compiler als Sicherheitsnetz behalten. Das Deployment-Ziel 14 macht ungeschützte APIs ab 15 und 26 zu Compiler-Fehlern. Das Ziel nicht anheben, nur um Fehler loszuwerden. Ein Muster dafür:
2. Was der Compiler nicht prüft:
  - Namen von SF Symbols aus Version 6 oder 7 bleiben auf 14 und 15 leer.
  - Selektoren, die über perform/value(forKey:) aufgerufen werden.
  - Info.plist-Schlüssel.
  - Den Glas-Look normaler Steuerelemente bringt das SDK 26 automatisch mit. Auf 14 und 15 sehen sie klassisch aus, das Design muss mit beidem funktionieren.

3. Der Release-Build läuft auf `macos-15` ohne `xcode-select` (`.github/workflows/release.yml`). Glas-APIs brauchen das SDK 26, also Xcode 26, auch mit #available. Entweder Xcode 26 im Workflow auswählen oder #if compiler(>=6.2) drumherum setzen. Welches Xcode der Runner standardmäßig nimmt, ändert sich mit der Zeit (unsicher).

### Code-Stellen mit Risiko

1. `Sources/Nightforge/Engine.swift:18-20`: engineComponent nimmt immer winecx. Unter macOS 26 ist das eine nicht unterstützte Engine, unter 14.4 startet Wine gar nicht. Vorschlag:Dabei aufpassen: Ein Engine-Wechsel betrifft bestehende Präfixe, weil winecx den Benutzerordner „crossover“ nennt (`Engine.swift:763`). Für die weiche Grenze lädt man unter 26 stattdessen gar keine Windows-Engine.
2. `.github/workflows/graphics.yml:71-116` (Job dxmt): Er läuft auf macos-15 mit Xcode 16.1 (Zeile 105) und meson setup (Zeile 113), ohne Deployment-Ziel. Clang nimmt dann die Host-Version, deshalb hat winemetal.so minos 15.0, und DXMTs @available(macOS 15, *)-Abfragen sind weg.
  - Abhilfe: MACOSX_DEPLOYMENT_TARGET: "14.0" als Job-Umgebungsvariable setzen. Ob die Unix-Seite von DXMT damit gebaut wird, prüfen.
  - CI-Prüfung ergänzen: otool -l …/winemetal.so | grep -A4 LC_BUILD_VERSION.
  - Die Upstream-Komponente dxmt im Manifest und die winemetal.so in winecx haben dasselbe Problem.

3. AVX-Lernlogik in `Sources/Nightforge/Engine.swift:58-60`, `Sources/Nightforge/LibraryModel.swift:1148-1152` und `Sources/Nightforge/GameLog.swift:44-56`:
  - Auf macOS 14 ist der AVX-Hinweis wirkungslos. Ein Absturz mit „illegal instruction“ heißt dort „kein AVX vorhanden“ und nicht „der Hinweis hat geschadet“.
  - Trotzdem setzt die App learned.noAVX.<appID> dauerhaft. Nach einem Upgrade auf 15 startet das Spiel weiter ohne AVX-Hinweis.
  - Abhilfe: Unter 15 nichts lernen und stattdessen den AVX-Hinweis zeigen.

4. `Sources/Nightforge/LibraryModel.swift:1159`: Hier landet die Logik für Spiele mit nur einem Weg (DirectX 12 oder Vulkan). Das ist die richtige Stelle für „DirectX 12 braucht macOS 26“, wenn die Engine kein D3DMetal kann (isGPTKCapable).
5. `scripts/install.sh:26-27`: Prüft nur die Hauptversion ≥ 14. Auf die neue Grenze anpassen; bei Weg B Haupt- und Nebenversion prüfen (14.4 bzw. 15).
6. `Resources/Info.plist:32-33` (LSMinimumSystemVersion 14.0) und `Package.swift:6`: Für die harte Grenze in der Info.plist 26.0 eintragen. Package.swift kann bei .v14 bleiben, dann kompiliert die CI auf macos-15 weiter.
7. Texte: README.md:11 (Badge), README.md:37, README.md:45 (Gatekeeper), `.github/workflows/release.yml:69` („macOS 14 or newer“) und die Landingpage.
8. Nur zur Info, unkritisch:
  - Engine.swift:1262-1263: LSSupportsGameMode gibt es erst ab 26. Auf 14 und 15 zählt LSApplicationCategoryType, und beide Schlüssel sind gesetzt.
  - build.sh:54-62, die Gcenx-, Graphics- und Gamepad-Builds mit -mmacosx-version-min=11.0, MoltenVK und SDL2 sind in Ordnung.

### Hinweise, die die App auf älterem macOS zeigen sollte

- Beim Einrichten unter macOS 26 (weiche Grenze):
  - DE: „Windows-Spiele brauchen macOS 26 Tahoe oder neuer. Dieser Mac hat macOS %@. Die Mac-Versionen deiner Steam-Spiele kannst du trotzdem starten.“ Dazu ein Knopf „Softwareupdate öffnen“.
  - EN: “Windows games need macOS 26 Tahoe or later. This Mac runs macOS %@. You can still play the Mac versions of your Steam games.”

- DirectX-12-Spiel ohne D3DMetal-Engine (Spielen-Knopf ausgegraut, wie bei „VR only“):
  - DE: „DirectX 12 braucht macOS 26“
  - EN: “DirectX 12 needs macOS 26”

- AVX-Absturz auf macOS 14:
  - DE: „Dieses Spiel braucht AVX-Befehle. Rosetta führt sie erst ab macOS 15 aus.“
  - EN: “This game needs AVX instructions, which Rosetta runs from macOS 15 on.”

- Nur bei Weg B:
  - DE: „Bitte aktualisiere auf macOS 14.4 oder neuer.“ (für 14.0 bis 14.3)
  - DE: „Auf macOS 14 kann DXMT Grafikfehler zeigen. Empfohlen ist macOS 15 oder neuer.“

- Frame-Generierung und Denoising, falls es diese Optionen gibt: unter 26 ausblenden oder mit „ab macOS 26“ beschriften.

### Textvorschlag für README und Landingpage

**Variante A (empfohlen für 0.3.0)**

Badge im README:

README (Englisch):

> You need a Mac with Apple silicon (M1 or newer) and **macOS 26 Tahoe or later**. Nightforge is tested on macOS 26 and 27. The engine that runs Windows games (Wine with CrossOver’s changes, which Apple’s D3DMetal needs for DirectX 12) is built for macOS 26 and later only.

> Prefer clicking? Download the DMG, open it and drag Nightforge onto the Applications folder. On first launch macOS says it can’t verify Nightforge (it’s free and not registered with Apple): open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Control-click → Open no longer works since macOS 15. The Terminal line skips this step.

Release-Text in `release.yml:69`:

> Free launcher for Windows Steam games on Apple silicon Macs (macOS 26 Tahoe or newer).

Landingpage (Deutsch):

> **Voraussetzungen:** Mac mit Apple Silicon (M1 oder neuer) und **macOS 26 Tahoe oder neuer**. Getestet auf macOS 26 und 27.

> Beim ersten Start meldet macOS, dass es Nightforge nicht überprüfen kann. Nightforge ist kostenlos und nicht bei Apple registriert. Öffne **Systemeinstellungen → Datenschutz & Sicherheit**, scrolle nach unten und klicke auf **„Dennoch öffnen“**. Mit der Terminal-Zeile entfällt dieser Schritt.

**Variante B** (erst nach Engine-Rückfall, DXMT-Neubau und Test auf einem echten Mac mit macOS 15)

- EN: “Apple silicon (M1 or newer) and macOS 15 Sequoia or later; macOS 26 Tahoe or later recommended. DirectX 12 games and the newest graphics features (Metal 4, frame generation) need macOS 26.”
- DE: „Mac mit Apple Silicon (M1 oder neuer) und macOS 15 Sequoia oder neuer, empfohlen ist macOS 26 Tahoe. DirectX-12-Spiele und die neuesten Grafikfunktionen (Metal 4, Frame-Generierung) brauchen macOS 26.“

**Test-Tipp (unsicher):** Eine VM mit macOS 15 auf dem M5 (Virtualization.framework, etwa UTM oder Tart) kann mit Rosetta prüfen, ob Wine startet und Steam sich anmeldet. Die GPU ist dort aber paravirtualisiert, für Spiele und D3DMetal ist das nicht aussagekräftig.

### Unsicher und offen

- Lädt dyld Bibliotheken mit höherem minos wirklich und scheitert erst an fehlenden Symbolen?
- Wie verhält sich winecx 4.7.3 auf 14.4 bis 15.x tatsächlich?
- Läuft D3DMetal 4.0b3 auf 15? Kommt der Metal-4-Pfad wirklich erst mit macOS 27?
- Trifft DXMT auf macOS 14 die Pfade, die erst ab 15 vorgesehen sind?
- Greift der Spielmodus bei direkt gestartetem Wine auf 14 und 15?
- Die Gatekeeper-Details unter 15.1 und 26.6.
- Ist Steam nativ für Apple silicon schon im stabilen Kanal?
- Die Abgleiche gegen SDK-Stubs und Header arbeiten mit Heuristiken. Wegoptimierte Versionsabfragen finden sie nur dort, wo DXMT Quellcode hat.

### Quellen

1. winecx-gptk README
2. winecx-gptk Release runtime-v4.7.3
3. Apple: os_sync_wait_on_address (macOS 14.4)
4. Gcenx macOS_Wine_builds
5. Apple Game Porting Toolkit
6. GPTK 1.0 README (Spiegel)
7. Gcenx GPTK-Repacks
8. apple/game-porting-toolkit
9. WWDC24: Port advanced games to Apple platforms
10. 9to5Mac zu GPTK 2 und AVX2
11. Heroic Issue #4193 (ROSETTA_ADVERTISE_AVX)
12. webmonarch/crossover-dx12-fix
13. highball Issue #85
14. CodeWeavers: CrossOver 23.5 (D3DMetal braucht Sonoma)
15. DXMT Wiki: Device/System/Runtime Specifications
16. DXMT v0.71 Release Notes
17. DXMT Wiki: Vendor Extensions
18. DXMT v0.80 winemetal_unix.c
19. DXMT DEVELOPMENT.md
20. MoltenVK Releases
21. DXVK-macOS Releases
22. Mesa: KosmicKrisp
23. LunarG: The State of Vulkan on Apple (Jan. 2026)
24. LunarG: Getting Started with the macOS Vulkan SDK
25. MTLFXSpatialScaler
26. MTLFXTemporalScaler
27. MTLFXFrameInterpolator
28. MTLFXTemporalDenoisedScaler
29. MTLResidencySet
30. MTL4CommandQueue
31. Apple: About the Rosetta translation environment
32. macOS 26 Release Notes
33. macOS 27 Release Notes
34. MacRumors: Steam braucht ab 15.10. macOS 12
35. TechRadar: Steam nativ auf Apple silicon
36. TechSpot: Steam beendet Windows 7/8
37. PC Gamer: Steam nur noch 64 Bit
38. legendary README
39. heroic-gogdl build.yaml
40. Heroic Games Launcher README
41. Apple Support: Spielmodus (gesperrt, nur Suchausschnitt)
42. Apple Developer Forums: Game Mode
43. LSSupportsGameMode
44. GCDualSenseGamepad
45. GCDualSenseAdaptiveTrigger
46. GCDeviceBattery
47. GCController.shouldMonitorBackgroundEvents
48. Apple Developer News: Gatekeeper in macOS Sequoia
49. dev.to: App permissions on macOS Sequoia
50. MacRumors Forum: macOS 15.1 und Gatekeeper
51. MacRumors Forum: xattr und Gatekeeper
52. Eclectic Light: Can you disable Gatekeeper and XProtect? (gesperrt, nur Suchausschnitt)
53. Eclectic Light: Is Tahoe quicker to launch apps first time? (gesperrt, nur Suchausschnitt)
54. SwiftUI glassEffect(_:in:)
55. SwiftUI GlassEffectContainer
56. AppKit NSGlassEffectView
57. SwiftUI ToolbarSpacer
58. SwiftUI onScrollGeometryChange
59. Observation: Observable()
60. SwiftUI toolbarBackgroundVisibility
61. SwiftUI ContainerBackgroundPlacement.window
62. SwiftUI onGeometryChange
63. AppKit NSApplication.activate()
64. macOS-SDK-Archive für den Symbolabgleich (joseluisq/macosx-sdks)
