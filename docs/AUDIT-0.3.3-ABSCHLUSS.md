# Abschluss-Audit des 0.3.3-Testbuilds (15.11.2026)

Geprüft: `claude/staging-033` bei `f4fd42d`, alles seit `365f393` (8.11., 314 Commits, 93 Quelldateien). Alles ist aus
dem Code belegt; **Vermutung** steht dabei, wo nur ein Live-Test es klären kann. Zeilennummern gelten für `f4fd42d`.
Keine Nightforge-Fenster, keine Spiele, kein `sample`, kein `winedbg`, nichts auf echten Laufwerken, Tests höchstens `-P 2`.

**Arbeitsstand (wird nachgeführt):** Abschnitte 1 bis 4 geprüft, 5 und 6 offen. Behebungen zu L1 bis L3 stehen noch aus.

## Notizen je Abschnitt (Rohfassung, wird am Ende in die vier Gruppen sortiert)

### 1 · Startschleife und Reparatur

- **Endlosschleife: nein.** Jede Runde von `starts:` (`LibraryModel.swift:4742`) endet mit `return`, `break` oder
  einem von fünf `continue`, und jedes ist gedeckelt: der leise zweite Start einmal (`startedQuietlyAgain`, `:5110`),
  die Engine davor einmal (`EngineRollback.afterFailedStart` löscht `lastGood` und danach den Pin,
  `EngineRollback.swift:335`), derselbe Weg höchstens dreimal je „Spielen“ über alle Wege zusammen
  (`NextStart.againLimit`, `sameWayAgain` zählt auch die Wurzel-Frage, `:5201`, `:5218`), die Leiter nur vorwärts
  (`NextStart.way` nimmt nur Wege hinter `index`, `LaunchHealth.advance(to:)` schreibt ihn fest). Über mehrere
  „Spielen“ hinweg wiederholt sich eine Abhilfe nicht: was schon im Rezept steht, ist keine Änderung
  (`Learned.applying` gibt `nil`, der Filter in `NextStart.swift:88`).
- **S1 · `ownAntiCheat` zählt in der Startschleife nicht als Anti-Cheat** (sollte vor dem Release entschieden werden).
  `ShaderCaches.hasAntiCheat` (`ShaderCaches.swift:30`) kennt `antiCheat`, `antiCheatOnline`, die Sperre und die
  Dateien von EAC/BattlEye, nicht `profile.ownAntiCheat`; `analysis.antiCheat` kommt ebenfalls nur aus Dateien.
  Overwatch (`steam.2357570`, einziges Profil mit `ownAntiCheat`) läuft deshalb als gewöhnliches Spiel durch
  `LibraryModel.swift:5043`, `:5144`, `:5160`: Seine Absturzberichte und Dumps werden gelesen, eine Regel der Tabelle
  darf eine DLL abschalten (`physx-update-loader`; `nvapi64`/`nvngx` hat sein Profil schon aus), der genauere Blick
  startet es mit `warn+debugstr,+wintrust,+chain`, die Frage zur Wurzel und der leise zweite Start gelten. Ein
  Werkzeug wird nicht angehängt (einzige Stelle mit `/usr/bin/sample` ist `GameTestRun.swift:673`, davor
  `GameTest.handsOff`). Auslösen: Overwatch endet ohne Bild und hinterlässt einen Dump mit `physxupdateloader` in der
  Kette. Empfehlung: `profile?.ownAntiCheat == true` an den drei Stellen wie Anti-Cheat behandeln (nur die Abhilfen
  von vor Schritt E, kein genauerer Blick). Ändert das Verhalten für Overwatch, deshalb nur beschrieben.
- **S2 · Gelerntes gilt weiter, wenn ein Spiel später als Anti-Cheat-Spiel erkannt wird** (kann warten, gehört zu S1).
  `StartRecipe.of(way:learned:…)` (`StartRecipe.swift:44`) trägt `learned.dllsOff` ohne Blick aufs Anti-Cheat ein.
  Nur `NextStart.after` lernt bei Anti-Cheat nichts dazu. Auslösen: Spiel lernt eine DLL, danach kommt per Profilliste
  oder Spiel-Update ein Anti-Cheat dazu. Empfehlung: beim Bau des Rezepts `dllsOff` für solche Spiele weglassen.
- **W1 · Eine gelernte Abhilfe lässt sich nicht zurücknehmen** (kann warten, im Entwurf als offen vermerkt,
  `docs/ENTWURF-STARTREZEPT.md:571`). `LearnedFixes.keep` (`LaunchHealth.swift:640`) schreibt vor dem Start, der sie
  prüft; nichts löscht `learned.dllsOff.*`, `learned.steps.*`, `learned.noAVX.*` je wieder – auch nicht
  `LaunchHealth.reset` (`:437`, „Grafik von Hand“ und der Dialog nach „Das hat nicht geklappt“), nicht das Entfernen
  des Spiels. Dauerhaft schlechter stellt das ein Spiel in zwei Fällen: `nvidia-interface` schaltet mit `nvapi64` auch
  `nvngx` ab (kein DLSS/MetalFX über D3DMetal mehr, auf allen Wegen), und `noAVX` bleibt, auch wenn ein Update des
  Spiels AVX verlangt (das gab es schon vor 0.3.3). Einziger Ausweg heute: `defaults delete`. Empfehlung für 0.3.4:
  in `LaunchHealth.reset` auch das Gelernte vergessen, oder zurücknehmen, wenn derselbe Befund trotz Abhilfe wiederkommt.
- **W2 · „Fenster ohne Meldungstext vor dem ersten Bild = Fehlstart“ trifft auch ein kleines eigenes Startfenster**
  (kann warten; **Vermutung**, welche Spiele es trifft). `LaunchHealth.ownQuestionWasAChoice` (`:504`) lässt ein
  Ende an einem Fenster nur dann als Wahl des Spielers gelten, wenn es eine Meldungsbox mit Frage war oder
  `showsOwnWindow` (`:512`) zutrifft: Unity, `-nolauncher` im Programm, einer von vier bekannten Launchern
  (`GameAnalysis.swift:248`). Ein anderes Fenster zwischen 200×100 und 640×360 (`GameOverlay.swift:834`; größere
  gelten als Bild) – Sprachwahl, Einstellungsdialog, kleiner Launcher eines älteren Spiels –, das der Spieler mit
  „Beenden“/„Abbrechen“ schließt, gilt seit dem 15.11. als Fehlstart: auf einem bewährten Weg startet das Spiel
  bis zu zweimal neu (leiser Start, dann genauerer Blick, für Steam-Spiele mit Steam-Neustart), auf einem neuen
  einmal je Weg der Leiter, am Ende „Das hat nicht geklappt“. Bis 0.3.2 endete das sofort. Empfehlung: zweites
  solches Ende im selben „Spielen“ als Wahl des Spielers nehmen.
- In Ordnung: `CloserLook.read` liest nur Text; die Kanäle jedes Starts (`+pid,+loaddll,+msgbox`) sind Wines eigene
  Ausgabe, kein Werkzeug am Prozess. `NextStart.asBefore` lässt Anti-Cheat-Spielen (EAC, BattlEye, Sperre) nur die
  fünf Abhilfen von vor Schritt E; `dllsOff` wird für sie in `NextStart.swift:84` verworfen; der Testschalter-Befund
  kommt hinter derselben Schranke (`:5043`).

### 2 · Frage zur Windows-Wurzel

- In Ordnung: `WindowsRoots.onRequest` ist leer (`WindowsRoots.swift:62`); im Release ist `askable` damit leer,
  `toAsk` immer `nil`, die Frage kommt nie. Jede Wurzel ist eine Konstante mit SHA-1 und SHA-256, `verified` prüft
  beide vor dem Eintragen (`:22`); der Name aus dem Protokoll wählt nur unter den Konstanten aus. Eingetragen wird
  allein in `HKCU\Software\Microsoft\SystemCertificates\Root` des Prefix (`registrySection`, über
  `Engine.applyGameSettings`, `Engine.swift:2068`); im ganzen Quelltext gibt es keinen Aufruf von `security`,
  `SecTrustSettings` oder `SecItemAdd`. Ein Nein trägt nichts ein (`LibraryModel.swift:5199`), es bleibt nur
  `windowsRoots.needed.<Spiel>` (der Name, für die nächste Frage). Die Frage antwortet genau einmal, auch wenn der
  Start abgebrochen wird (`GameOverlay.close` → `answerRoot(false)`, `GameOverlay.swift:362`).
- Hinweis für später: „Hinzufügen und starten“ ist der vorgewählte Knopf (`OverlayView.swift:207`). Sobald eine
  Wurzel in `onRequest` steht, ist das ein Ja mit einem Druck auf A.

### 3 · Versteckte Testschalter

- In Ordnung: `gameTest.measurePlay`, `gameTest.testFinding`, `testRootQuestion` stehen samt Schlüssel und Lesefunktion
  nur im `#else` von `#if NIGHTFORGE_RELEASE` (`GameTest.swift:54`, `StartDiagnosis.swift:247`, `WindowsRoots.swift:100`);
  mit der Flagge antworten die Funktionen fest „nein“/`nil`. Ohne gesetzten Schalter wirkt keiner (Tests in
  `GameTestTest`, `StartRecipeTest`, `WindowsRootsTest`). Die Schlüssel haben 20, 20 und 16 Byte, liegen also als Text
  im Programm; der Schritt in `release.yml:67` findet sie (`bash -e` ohne `pipefail`, `grep -q` entscheidet).
  `sign-release.sh` baut nicht neu, es signiert das Zip aus dem Workflow (`:57`). Selbst geprüft:
  `swiftc -typecheck -D NIGHTFORGE_RELEASE` über alle 193 Quelldateien läuft durch (23 s).
- **T1 · Kein Test baut mit der Flagge** (kann warten): Ein Verweis auf einen der drei Schlüssel außerhalb des `#else`
  fiele erst beim Release-Tag auf. Empfehlung: der Typecheck oben als Schritt in der CI, oder ein pytest, der die
  Quellen darauf prüft.
- **T2 · Weitere versteckte Schalter, die ein Release kennt** (Entscheidung des Nutzers, kein Fehler): `gameTest` mit
  `.only`, `.pictureWait`, `.playSeconds`, `.stop`, `.basket`, `.frameLog` (der ganze Spieletest samt Bildraten-Protokoll
  seiner eigenen Starts und `sample` bei hängenden Spielen ohne Anti-Cheat; schon in 0.3.2), `closerLook` (jeder Start
  mit allen Kanälen, **auch bei Anti-Cheat-Spielen**, `LibraryModel.swift:4835`), `wineDebug`, `vulkanLoader`, `msync`,
  `wineSandbox`, `gameEnvironment.<Spiel>`, `dxmtEarlyShaders`, `parkPointerOverGames`, `unityDialogPlay`,
  `battleNetStore`, `resolutionFitOff`, `UpdateTestRelease`. Keiner zeichnet ohne Zutun etwas auf, nichts verlässt
  den Mac. Neu in 0.3.3 und immer an: `start-evidence.jsonl` (je Start eine Zeile mit Spiel, Weg, Rezept, Dauer;
  bleibt auf dem Mac, wird nie gekürzt, `StartEvidence.swift:58`) – das ist Gedächtnis der Startlogik, kein
  Messen beim Spielen, sollte aber in den Release-Notizen stehen.

### 4 · Laufwerks-Übernahme

- Gelöscht wird auf dem Laufwerk nichts: Steam bekommt nur einen Eintrag in seiner Liste (`SteamLibraries.ensure`,
  `ExternalDrives.swift:283`, unverändert seit 4.2), `legendary import` schreibt in legendarys eigene Liste (ein
  unvollständiges Spiel wird mit `--keep-files` wieder vergessen, `EpicStore.swift:773`), GOG ist ein Eintrag in
  `installed.json` (`GOGStore.swift:664`). **Geschrieben** wird auf dem Laufwerk an einer Stelle: `ensure` legt
  `steamapps/common` an und schreibt `libraryfolder.vdf` neu, wenn die Datei fehlt oder keine `contentid` hat
  (`:285`–`:294`). **Vermutung:** `legendary import` selbst schreibt nichts in den Spielordner (so legendarys Quelltext;
  live in Teil B ansehen).
- Abziehen mittendrin: `ensure` scheitert zuerst am Laufwerk, bevor eine Liste geschrieben ist; Steam startet wieder,
  wenn es lief (`DriveTakeover.swift:427`). GOG und Epic scheitern an der fehlenden Datei, der nächste Blick findet
  das Laufwerk nicht mehr. Zwei Laufwerke mit demselben Spiel: das zweite gilt als bekannt (`knownInstalls` wird je
  Laufwerk neu gelesen, `:211`). Zweimal laufen: `looking`, `handedOver` und das idempotente `ensure` decken es.
- **L1 · Ein verschachteltes Manifest bringt Nightforge zum Absturz** (sollte vor dem Release behoben werden, wird
  behoben). `VDFParser.parseObjectBody`/`parseNodes` (`VDF.swift:97`, `:122`) rufen sich je `{` selbst auf, ohne
  Grenze. Eine `appmanifest_1.acf` aus einigen tausend `a{` auf einem Laufwerk mit „Nightforge Games/Steam“ läuft beim
  Anstecken und bei jedem Start durch `DriveContents.steamGames` (`DriveFinds.swift:59`): Stapelüberlauf, Absturz bei
  jedem Start, solange das Laufwerk steckt.
- **L2 · Der Ordnername aus Steams Manifest wird ungeprüft zum Pfad** (sollte behoben werden, wird behoben).
  `LibraryScanner.readManifest` (`Library.swift:556`) hängt `installdir` an `steamapps/common/`; mit `../../…` zeigt
  `game.installDir` aus dem Laufwerk heraus. Dorthin schreibt ein Start `dxmt.conf`, DXVKs DLLs und die Datei-Korrekturen
  des Profils, „Verschieben“ nimmt den Ordner mit (`GameMove.swift:257`). Bisher kam so ein Manifest nur über eine
  Bibliothek in die Liste, die der Spieler selbst angelegt hat; die Übernahme trägt die eines fremden Laufwerks ohne
  Frage ein. Nur das Entfernen prüft den Namen schon (`Engine.swift:3009`).
- **L3 · Dateien vom Laufwerk werden ohne Größengrenze gelesen** (kann warten, wird mit behoben, weil klein):
  `appmanifest_*.acf`, `goggame-*.info`, `.egstore/*.mancpn` (`DriveFinds.swift:59`, `:80`, `:100`).
- **L4 · Übernommene Dateien prüft niemand** (kann warten; Entscheidung). Ein Spiel auf einem fremden Laufwerk gilt
  nach dem Anstecken als installiert, wenn das Konto es besitzt; sein Programm startet beim nächsten „Spielen“. Steam
  prüft dabei nichts, legendary zählt nur, ob 95 % der Dateien da sind (und nimmt ein Manifest aus `.egstore` des
  Laufwerks, **Vermutung** aus legendarys Quelltext), GOG prüft nichts; der Startpfad aus der GOG-Infodatei ist auf den
  Ordner begrenzt (`GOGLibrary.swift:304`). Der Spieler sieht die eine Zeile „… sind wieder da“. Empfehlung für
  0.3.4: bei Epic und GOG vor dem ersten Start einmal prüfen lassen (`legendary repair`, gogdl), oder die Zeile sagt,
  dass die Dateien ungeprüft sind.
- In Ordnung: symbolische Links auf Ordner in „Epic Games“/„GOG Games“ zählen nicht als Ordner (`DriveFinds.swift:119`);
  GOG-Kennungen, Sprache, Add-ons und Epics App-Namen sind geprüft (`GOGRelease.isProductID`, `isLanguageCode`,
  `GameID.isPlain`); der Pfad geht als eigenes Argument an legendary, nie durch eine Shell; in einem Test-Home werden
  nur Disk-Images angesehen (`DriveTakeover.swift:252`).
