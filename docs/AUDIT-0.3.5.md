# Audit vor 0.3.5 (23.11.2026)

Geprüft: `git diff main...claude/staging-035` (b0230b3) und `claude/konsolenmodus-a-035` (4304230, Lichtnaht und
Konsolenmodus). Nur gelesen: Code, keine Läufe, kein Spiel. Zeilen gelten für diese beiden Stände. Schwerpunkt auf
Code anderer Worker; die eigenen Zweige (Lichtnaht, Konsolenmodus) stehen am Ende getrennt.

## Kurzfassung

- **Nichts, was den Release verhindert.** Kein Fund mit Absturz- oder Hängergefahr, die Tests nicht abdecken. Keine
  Konto-IDs und keine Pfade mit Benutzernamen in neuen Protokollzeilen. Die Liste der Testschalter in `release.yml`
  ist vollständig (pytest prüft sie gegen den Code). Die Profile bleiben für 0.3.4-Apps lesbar.
- **Eine Entscheidung vor dem Release:** `hide-steam-dock.dylib` läuft in jedem Wine-Prozess, also auch in Overwatch.
  Mit 0.3.5 bringt sie dort zwei Neuerungen mit: eine veränderte Netzwerkliste (`if_nameindex`) und Metal-Code.
  Nach der Regel „nichts in Anti-Cheat-Prozessen“ sollte das vor dem Release eingeschränkt oder bewusst
  freigegeben werden (M1).
- Der Update-Weg von 0.3.4 ist sauber: ein Neustart von Sitzung und Steam, nie unter einem laufenden Spiel.

## Muss vor dem Release (entscheiden)

**M1 · Die Bibliothek ändert in Anti-Cheat-Spielen jetzt das Verhalten.**
`build.sh:97` linkt `network-order.c` und `d3dmetal-pace.m` in `hide-steam-dock.dylib`, und `DockHider` gibt sie per
`DYLD_INSERT_LIBRARIES` an Steam. Damit erbt sie jeder Prozess, den Steam startet, auch Overwatch (`ownAntiCheat`).
- `wrapper/network-order.c:117/137` ersetzt `if_nameindex()` prozessweit, ohne Ausnahme. Gebraucht wird das nur von
  Wines Gerätedienst (nsiproxy in `winedevice.exe`) für Steams Anmeldung. Im Spielprozess ändert es Reihenfolge und
  Umfang der Netzwerkliste, die das Spiel oder sein Anti-Cheat liest.
- `d3dmetal-pace.m` bleibt in Anti-Cheat-Spielen sauber aus: Für sie wird `D3DM_MAX_FPS` aus Steams Umgebung entfernt
  (`Engine.swift:361` setzt „“, `steamEnvironment` lässt leere Werte weg), die Erlaubnisdatei wird gelöscht
  (`D3DMetalPace.prepare`), und der Konstruktor (`d3dmetal-pace.m:77`) kehrt ohne die Variable sofort zurück. Geladen
  wird der Code trotzdem, und mit ihm jetzt fest Metal und QuartzCore (`build.sh:97`, `-framework Metal -framework
  QuartzCore`), in jeden Wine-Prozess, auch in Steams Web-Helfer.
- **Vorschlag:** Die Ersetzung nur in `winedevice.exe` wirken lassen (argv[0] prüfen und im Ersatz sonst die echte Liste
  unverändert zurückgeben). Metal und QuartzCore mit `-weak_framework` linken oder erst in `takeHold` per `dlopen`
  holen. Andernfalls Thomas' ausdrückliches OK, dass die Bibliothek wie bisher in jedem Prozess liegt.

## Sollte (bald, kein Release-Stopper)

**S1 · Die Bildratenbremse hängt an Metal-Interna.** `d3dmetal-pace.m:61` tauscht `presentDrawable:` auf der privaten
Klasse `_MTLCommandBuffer` gegen einen Aufruf von `presentDrawable:afterMinimumDuration:` (Zeile 28). Ruft eine künftige
Metal-Version in `afterMinimumDuration` intern `presentDrawable:` auf, endet das in einer Endlosschleife und das Spiel
stürzt ab. Heute geprüft: Wukong lief am 22.11. mit „D3DMetal frame limit 60 FPS“. Vorschlag: `originalPresent`
(gesichert, aber unbenutzt) als Rückfall nehmen und eine Wiedereintritts-Sperre je Thread einbauen. Nach jedem
macOS-Update einen D3DMetal-Start prüfen.

**S2 · Zwei Nightforge-Kopien beenden sich gegenseitig die Wine-Sitzung.** `Engine.swift:2669/2681` merkt die Sitzung
als Text (`sha256:…`), 0.3.4 als Zahl. Wechselt der Start zwischen Release und Testbuild, beendet jede Seite die
Sitzung der anderen einmal (nie unter einem Spiel, `windowsGameRunningKnown == false`). Steam startet dann jedes Mal
neu. Für Spieler ohne zweite Kopie ist das ohne Folgen. Für die Testphase: die Release-Kopie aus /Applications nehmen
(steht in docs/TODO.md).

**S3 · Lange Startpause nach einem Steam-Ende.** `waitForSteamToEnd` (`Engine.swift:3141`) wartet bis zu 15 s auf
Steam-Reste, bevor Steam wieder startet: in `ensureSteamRunning` (`Engine.swift:2794`), `restartSteamInBackground` und `restartHungSteam`. Es läuft
abseits des Main-Threads (Swift 5.9, nichtisolierte async-Funktion) und beendet nichts. Ein Hänger kann so nicht
entstehen, die Wartezeit sieht der Spieler aber als Ladescreen. Belegt ist nur der Nutzen (27–32 s gegen 5–6 s am
22.11.). Live beobachten, wie oft die 15 s ausgeschöpft werden (Protokollzeile „still there … s after steam.exe“).

## Später

**L1 · F5-Gedächtnis mit Pfaden.** `rememberLaunch` (`Engine.swift`, `steamLaunchMemory`) legt Steams Umgebung
mitsamt Werten in UserDefaults ab, darunter Pfade mit Benutzernamen (KosmicKrisp, Vulkan-Loader). Das bleibt lokal und
wird nicht protokolliert (`changedParts` nennt nur Namen). Gehört aber in die Liste dessen, was ein Problembericht nie
mitnehmen darf.

**L2 · `if_nameindex` je Aufruf.** `network-order.c:117` holt bei jedem Aufruf `getifaddrs` und zwei ioctl je
Schnittstelle (23 auf dem M5 Pro). Wie oft Wine fragt, ist nicht gemessen; bei M1 erledigt sich das mit.

**L3 · `errno` bleibt nicht erhalten,** wenn `getifaddrs` fehlschlägt (`network-order.c`, früher Rücksprung vor
`errno = saved`). Harmlos, aber unsauber.

## Geprüft, in Ordnung

- **Update-Weg von 0.3.4:** `steamConfigVersion` 11 → 12 (`Engine.swift:74`). Die neue Signatur startet Steam nur neu,
  wenn nichts zu tun ist (`!busy`). `librarySession` war bei 0.3.4 eine Zahl und wird hier als Text gelesen: die Sitzung
  endet einmal, nie unter einem Spiel. Danach ist sie gemerkt.
- **F5** (`rememberedLaunch`, `Engine.swift:252`): Es wird nur übernommen, was zur aktuellen Version passt, solange die
  genannten Dateien noch da sind und msync erlaubt ist. Sonst bleibt alles wie vorher. Der statische Startwert liest
  nur UserDefaults und das Dateisystem; es gibt keinen Zyklus mit `msyncSwitch`.
- **`stopAll(reason:)`:** Alle Aufrufer geben einen Namen mit, nie einen Pfad.
- **DockHider.prepare/FileIdentity:** `lstat` je Aufruf ist billig. Ist die Datei ersetzt worden, wird sie per
  Umbenennen erneuert; laufende Prozesse behalten ihre alte Datei.
- **SteamQuestion / holdsClick:** Nightforge beantwortet nie selbst etwas. Ein Klick genau dort, wo Nightforge den
  Zeiger abgesetzt hat, wird zurückgehalten, bis der Zeiger bewegt wurde.
- **Profile:** `geforce-now.json` wird streng geprüft (`read_geforce_now`). Das neue Feld `sources["geforce-now"].from`
  lässt 0.3.4 unbeachtet (`ProfileDocument` liest es nicht). Nightforge fragt NVIDIA nicht mehr ab.
- **build.sh / sdk-lib.sh:** Fällt nur bei den Command Line Tools ohne SwiftUI-Makros auf 26.5 zurück. `.noindex`
  hält Testbuilds aus Spotlight heraus. `release.yml` prüft den neuen Pfad.
- **Energie:** Neu im Arbeitszweig ist nur ein Warten von höchstens 15 s; es gibt keine dauernden Timer.

## Eigene Zweige (Lichtnaht, Konsolenmodus)

- **E1 (sollte):** `watchConsoleFocus` (`LibraryModel.swift:4276`, konsolenmodus-a) wacht im Konsolenmodus viermal je
  Sekunde auf, auch während eines Spiels und wenn Nightforge hinten ist. Die Prüfung `NSApp.isActive` (Zeile 4283)
  greift erst nach dem Aufwachen. Billig, aber ein Dauer-Timer. Vorschlag: nur laufen lassen, solange Nightforge vorne
  ist (`didBecomeActive`/`didResignActive`).
- **E2 (live prüfen):** `GameStage.wentDark` (`GameStage.swift:68`, 3 s) mit `endsInBackground` (10 s): Ein Spiel, das
  vorne bleibt und über 13 s kein Fenster zeigt (lange Moduswechsel ohne Schutzfenster), käme zu Nightforge zurück.
  Kommt das Fenster wieder, wird es wieder das Spiel. Nur bei Wukong belegt.
- **E3 (in Ordnung):** `DockAutoHide` startet das Dock nur bei einer echten Änderung neu (`killall`,
  `DockAutoHide.swift:85`), nie im Test, nur im Konsolenmodus, mit Zeile im Protokoll.
