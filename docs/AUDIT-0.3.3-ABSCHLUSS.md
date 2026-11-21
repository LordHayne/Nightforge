# Abschluss-Audit des 0.3.3-Testbuilds (15.11.2026)

Geprüft: `claude/staging-033` bei `f4fd42d`, alles seit `365f393` (8.11., 314 Commits, 93 Quelldateien), in der
Reihenfolge Startschleife, Windows-Wurzel, Testschalter, Laufwerks-Übernahme, Vorhang, Spieletest und Profile. Alles ist
aus dem Code belegt; **Vermutung** steht dabei, wo nur ein Live-Test es klären kann. Zeilennummern gelten für `f4fd42d`.
Keine Nightforge-Fenster, keine Spiele, kein `sample`, kein `winedbg`, nichts auf echten Laufwerken, Tests höchstens `-P 2`.
Nichts gepusht, kein PR. Die Behebungen liegen auf `claude/audit-033-abschluss-d51880`, je Fehler ein Commit mit Test.

**Nachtrag, 15.11. abends:** B1 bis B5 sind im Testzweig (`689520f`). Auf Bitte des Koordinators danach behoben: S1,
S2 und W1 im Kleinen (B6 bis B8, auf `689520f`). Die Abschnitte unten sind nachgeführt; was dabei neu auffiel, steht
unter „Beim Nachtrag aufgefallen“.

## Ergebnis

- **Nichts blockiert das Release**, wenn B1 eingespielt ist (Absturz durch eine Datei auf einem angesteckten Laufwerk).
- **Vier Fehler behoben** (B1 bis B4), dazu ein Test, der die Testschalter aus dem Release hält (B5).
- **S1, S2 und W1 sind im Nachtrag behoben** (B6 bis B8): `ownAntiCheat` zählt in der Startschleife wie Anti-Cheat,
  der Vorhang sagt das Ende, wo kein Versuch mehr kommt, und „Noch einmal von vorn“ vergisst das Gelernte.
- **Keine Endlosschleife** in der Startschleife, die Frage zur Wurzel und die Testschalter halten, was sie versprechen,
  die Übernahme löscht auf dem Laufwerk nichts.

## Behobene Fehler

| Nr. | Schwere | Fehler | Datei | Commit |
|---|---|---|---|---|
| B1 | hoch | Verschachteltes Manifest auf einem Laufwerk bringt Nightforge bei jedem Start zum Absturz | `VDF.swift:112`, `:137` | `6e0784a` |
| B2 | mittel | Ordnername aus Steams Manifest wird ungeprüft zum Pfad, auch aus der Bibliothek heraus | `Library.swift:556`, `DriveFinds.swift:60` | `ca716ab` |
| B3 | niedrig | Aus einer Bibliothek wird jede Datei ganz gelesen, auch Link, Pipe und Gigabytes | `DriveFinds.swift:59`, `:80`, `:100`, `Library.swift:510` | `8c19745` |
| B4 | niedrig | Seit `+pid` füllt ein einziger Fehler die Fehlerliste des Problemberichts | `GameLog.swift:403` | `963f526` |
| B5 | Test | Kein Test hielt die drei Testschalter aus dem Release | `tests/test_release_switches.py`, `ci.yml` | `c2d4950` |
| B6 | mittel | S1: `ownAntiCheat` galt in der Startschleife nicht als Anti-Cheat | `LibraryModel.swift:5043`, `NextStart.swift` | `80a236b` |
| B7 | niedrig | S2: „Noch ein Versuch …“, und dann kam keiner | `LaunchRepair.swift:76`, `LibraryModel.swift:5233` | `148a67c` |
| B8 | niedrig | W1: Kein Knopf nahm eine gelernte Abhilfe zurück | `LibraryModel.swift:5857`, `LaunchHealth.swift` | `9522227` |

### B1 · Verschachteltes Manifest

`VDFParser.parseObjectBody` und `parseNodes` riefen sich je `{` selbst auf, ohne Grenze. Nachgestellt mit dem alten
Stand: 2.000 Ebenen (eine Datei von 4 KB) beenden das Programm auf einem Nebenthread mit SIGBUS (Exit 138), 500 gehen
noch. So ein `appmanifest_1.acf` in „Nightforge Games/Steam/steamapps“ läuft beim Anstecken und bei jedem Start durch
`DriveContents.steamGames`: Absturz bei jedem Start, solange das Laufwerk steckt. Dieselbe Stelle liest jede
Steam-Bibliothek. Jetzt 64 Ebenen (Steams eigene Dateien gehen ein Dutzend tief), darüber ist die Datei keine.

### B2 · Ordnername aus dem Manifest

`LibraryScanner.readManifest` hängte `installdir` an `steamapps/common/`. Mit `../../…` lag `game.installDir` außerhalb
der Bibliothek: dorthin schreibt ein Start `dxmt.conf`, DXVKs DLLs und die Datei-Korrekturen des Profils, „Verschieben“
nimmt den Ordner mit (`GameMove.swift:257`). Bisher kam ein Manifest nur über eine Bibliothek in Steams Liste, die der
Spieler selbst angelegt hat; die Übernahme trägt die eines fremden Laufwerks beim Anstecken ein. Nur das Entfernen prüfte
den Namen schon (`Engine.swift:3009`). Jetzt ist so ein Manifest kein Spiel, im Scan und in dem, was ein Laufwerk hält.

### B3 · Nur eigene, kleine Dateien

`appmanifest_*.acf`, `goggame-*.info` und `.egstore/*.mancpn` wurden mit `Data(contentsOf:)` gelesen, was auch immer sie
waren: ein symbolischer Link (auch nach `/dev/zero`), eine Pipe (liest ohne Ende, der Blick aufs Laufwerk hängt dann
für immer), eine Datei von Gigabytes (ganz in den Speicher, bei jedem Blick). Jetzt nur gewöhnliche Dateien bis 1 MB.
`GOGGameInfo.read` (beim Start eines GOG-Spiels) liest weiter ohne Grenze: dort liegt die Datei im Spielordner, den
der Spieler startet; nicht geändert.

### B4 · Fehlerliste im Problembericht

`GameLog.errors` nahm die Thread-Nummer vor `err:` weg, damit gleiche Zeilen nur einmal zählen. Seit Schritt E5 trägt
jeder Start `+pid` (`CloserLook.everyStart`), die Zeile beginnt mit Prozess- **und** Thread-Nummer; weg ging nur die
erste. Ein Fehler aus zwölf Threads stand zwölfmal in der Liste (höchstens 30 Zeilen) und verdrängte die anderen –
im Problembericht (`ProblemReport.swift:88`) und im Bericht des Spieletests (`GameTestRun.swift:450`).

### B5 · Test für die Testschalter

Mit `NIGHTFORGE_RELEASE` baute bisher nur der Release-Workflow. Der neue Test liest die Quellen: Die Schlüssel stehen
nur im `#else`, `release.yml` sucht nach genau diesen, jeder ist länger als 15 Byte, und was im Release für einen
Schalter einspringt, liest keine Einstellungen. Von Hand geprüft: `swiftc -typecheck -D NIGHTFORGE_RELEASE` über alle
193 Quelldateien läuft durch.

## Blockiert das Release

Aus diesem Audit nichts außer B1 (behoben). Die bekannten Schritte des Nutzers bleiben: Profilliste signieren
(`ownAntiCheat`, `fullscreenHint` sind neue Felder), Version, Release-Notizen.

## Sollte vor dem Release behoben werden (im Nachtrag behoben)

### S1 · `ownAntiCheat` gilt in der Startschleife nicht als Anti-Cheat (behoben, `80a236b`)

**Behoben:** `NextStart.handsOff` sagt jetzt, für welche Spiele die Regel des Nutzers gilt (nichts ändern, was sie
laden; kein Werkzeug am Prozess; ihre Dateien nicht ansehen): Anti-Cheat wie bisher **oder** `profile.ownAntiCheat`.
Die Startschleife fragt dort statt bei `ShaderCaches.hasAntiCheat`. Für Overwatch heißt das: Seine Dumps werden nicht
gelesen, keine Regel schaltet eine DLL ab, die Entscheidung bekommt nur die fünf Abhilfen von vor Schritt E, kein
Befund vom Testschalter, keine Frage zur Wurzel. Wie vom Koordinator gewünscht bleibt der leise zweite Start (er
ändert nichts am Spiel), und der genauere Blick ist gehalten wie bei Anti-Cheat-Spielen: **es gibt ihn nicht.**

Was der genauere Blick ist: kein Werkzeug und kein Debugger, sondern ein weiterer Start mit mehr von Wines eigenen
Protokoll-Kanälen in der Umgebung (`WINEDEBUG` mit `warn+debugstr,+wintrust,+chain` zu den `+pid,+loaddll,+msgbox`
jedes Starts, `CloserLook.channels`); für ein Steam-Spiel startet Steam dafür neu. Gelesen wird danach nur Wines
Protokoll. Am Spiel und an dem, was es lädt, ändert er nichts; er kostet einen Start. Die Kanäle jedes Starts
(`CloserLook.everyStart`) bekommt auch ein Anti-Cheat-Spiel, wie bisher.

Nicht geändert: `ShaderCaches.hasAntiCheat` selbst (sonst verlöre Overwatch die frühe Shader-Übersetzung), der leise
zweite Start und das Warten aufs Bild. So stand es davor:

`ShaderCaches.hasAntiCheat` (`ShaderCaches.swift:30`) kennt `antiCheat`, `antiCheatOnline`, die Sperre und die Dateien
von EAC/BattlEye, nicht `profile.ownAntiCheat`; `analysis.antiCheat` kommt ebenfalls aus Dateien. Overwatch
(`steam.2357570`, das einzige Profil mit dem Feld) läuft deshalb durch `LibraryModel.swift:5043`, `:5144`, `:5160` wie
ein gewöhnliches Spiel:

- Seine Absturzberichte und Dumps werden gelesen (nur Dateien).
- Der genauere Blick startet es mit `warn+debugstr,+wintrust,+chain`, die Frage zur Wurzel und der leise zweite Start
  gelten (`LaunchHealth.startsAgainQuietly` sagt selbst: bei Anti-Cheat wäre das eine zweite Kopie).
- Eine Regel der Tabelle dürfte eine DLL abschalten. **Heute trifft das nichts:** Die zwei Regeln mit `dllsOff` nennen
  `physxupdateloader(64)` (für jedes Spiel schon aus, `Engine.swift:2040`) und `nvapi64`/`nvngx` (in Overwatchs Profil
  schon aus), und was das Rezept schon aus hat, ist keine Änderung (`NextStart.swift:88`). Die nächste Regel hätte
  diesen Schutz nicht.

Ein Werkzeug wird nirgends angehängt: `/usr/bin/sample` gibt es nur im Spieletest (`GameTestRun.swift:673`), dort
hinter `GameTest.handsOff`, das `ownAntiCheat` kennt (auch über das Steam-Gegenstück eines Battle.net-Spiels).
Auslösen: Overwatch endet ohne Bild. Empfehlung: an den drei Stellen `profile?.ownAntiCheat == true` wie Anti-Cheat
behandeln (nur die Abhilfen von vor Schritt E, kein genauerer Blick, kein leiser zweiter Start). Zwei Zeilen und ein
Test; nicht gebaut, weil es Overwatchs Startverhalten ändert.

### S2 · „Noch ein Versuch …“, und dann kommt keiner (behoben, `148a67c`)

**Behoben:** `LaunchRepair.after` antwortet für `.keepsItsPlace` und `.noOtherWay` mit dem Ende (`keptPlace`,
`noOtherWay`): „Das hat nicht geklappt.“ mit „Gleich bist du zurück in der Bibliothek.“, drei Sekunden
(`LaunchRepair.endStands`), dann die Seite. Keine neuen Texte; das Protokoll sagt, welches Ende es war. Ein Test hält
fest: Der Vorhang verspricht genau dort einen Versuch, wo einer kommt. Eine Änderung dabei, die über den Text
hinausgeht: `.noOtherWay` endet jetzt wie die anderen Enden mit `return`. Bisher lief es ans Ende der Schleife und
trat „hinter das Spiel“ (`stepBack`), das es nicht mehr gab – mit der Einstellung „Launcher beenden“ beendete sich
Nightforge nach dem Fehlstart. So stand es davor:

`sayRepair(.looking)` (`LibraryModel.swift:5030`) schreibt nach jedem Ende ohne Bild „Noch ein Versuch …“ auf den
Vorhang. Entscheidet `NextStart.after` danach `.keepsItsPlace` (ein bewährter Weg hat seine Versuche hinter sich,
`:5236`) oder `.noOtherWay` (Grafik von Hand gewählt, `:5233`), sagt `LaunchRepair.after` nichts (`LaunchRepair.swift:76`),
der Start endet, und der Spieler steht ohne ein Wort auf der Seite des Spiels. Auslösen: ein Spiel mit bestätigtem
Weg endet dreimal in Folge in den ersten Sekunden (leiser Start, genauerer Blick, dann Schluss). Bis 0.3.2 endete das
genauso still, aber ohne das Versprechen davor. Empfehlung: für beide Fälle die ehrliche Zeile („Das hat nicht
geklappt.“, `LaunchRepair.endStands` lang), wie bei `.gaveUp` und `.rootDeclined`.

## Kann warten

- **W1 · Eine gelernte Abhilfe lässt sich nicht zurücknehmen** – **im Kleinen behoben (`9522227`):**
  `LaunchHealth.reset` löschte das Gelernte nicht. Jetzt vergessen die zwei Knöpfe nach „Das hat nicht geklappt“
  („Nochmal mit dem ersten Weg versuchen“, „‚Am verträglichsten‘ versuchen“) alles Gelernte (`LearnedFixes.forget`: `learned.dllsOff`,
  `.steps`, `.winetricks`, `.noAVX`), mit einer Zeile im Protokoll, was ging. Was ein Spiel wirklich braucht, lernt
  es beim nächsten Fehlstart neu: dort wird jeder Start beobachtet. **Bewusst nicht** beim dritten Aufrufer, dem
  Sichern der Optionen mit von Hand gewählter Grafik (`SettingsViews.swift:359`): Das läuft bei jedem Sichern, und
  ein Start auf einem von Hand gewählten Weg, der schon einmal gut lief, wird nicht beobachtet
  (`EngineRollback.needsWatch`) – eine Abhilfe, die das Spiel braucht, käme dann nie wieder, und es startete nicht
  mehr. Offen bleibt damit der Fall „Abhilfe hat geholfen, kostet aber etwas“ (kein DLSS nach `nvidia-interface`):
  dafür gibt es weiter keinen Knopf. So stand es davor (im Entwurf als offen vermerkt,
  `docs/ENTWURF-STARTREZEPT.md:571`). `LearnedFixes.keep` (`LaunchHealth.swift:640`) schreibt vor dem Start, der die
  Abhilfe prüft; nichts löscht `learned.dllsOff.*`, `learned.steps.*`, `learned.noAVX.*` je wieder – nicht
  `LaunchHealth.reset` (`:437`), nicht das Entfernen des Spiels. Dauerhaft schlechter stellt das ein Spiel in zwei
  Fällen: `nvidia-interface` schaltet mit `nvapi64` auch `nvngx` ab (kein DLSS/MetalFX über D3DMetal mehr, auf allen
  Wegen), und `noAVX` bleibt, auch wenn ein Update AVX verlangt (gab es schon vor 0.3.3). Ausweg heute nur
  `defaults delete`. Empfehlung für 0.3.4: `reset` vergisst auch das Gelernte, oder die Abhilfe geht zurück, wenn
  derselbe Befund trotz ihr wiederkommt.
- **W2 · Gelerntes gilt weiter, wenn ein Spiel später als Anti-Cheat-Spiel erkannt wird.** `StartRecipe.of`
  (`StartRecipe.swift:44`) trägt `learned.dllsOff` ohne Blick aufs Anti-Cheat ein; nur `NextStart.after` lernt bei
  Anti-Cheat nichts dazu. Auslösen: Spiel lernt eine DLL, danach bringt die Profilliste oder ein Update ein Anti-Cheat.
- **W3 · „Fenster ohne Meldungstext vor dem ersten Bild = Fehlstart“ trifft auch ein kleines eigenes Startfenster**
  (**Vermutung**, welche Spiele). `LaunchHealth.ownQuestionWasAChoice` (`:504`) lässt ein Ende an einem Fenster nur als
  Wahl des Spielers gelten, wenn es eine Meldungsbox mit Frage war oder `showsOwnWindow` (`:512`) zutrifft: Unity,
  `-nolauncher` im Programm, einer von vier Launchern (`GameAnalysis.swift:248`). Ein anderes Fenster zwischen 200×100
  und 640×360 (`GameOverlay.swift:834`; größere gelten als Bild und damit als gelungener Start) – Sprachwahl,
  Einstellungsdialog, kleiner Launcher eines älteren Spiels –, das der Spieler mit „Beenden“ schließt, ist seit dem
  15.11. ein Fehlstart: auf einem bewährten Weg kommt das Spiel bis zu zweimal wieder (leiser Start, dann genauerer
  Blick, für Steam-Spiele mit Steam-Neustart), auf einem neuen einmal je Weg, am Ende „Das hat nicht geklappt“. Bis
  0.3.2 endete das sofort. Empfehlung: das zweite solche Ende im selben „Spielen“ als Wahl des Spielers nehmen.
- **W4 · Übernommene Dateien prüft niemand.** Ein Spiel auf einem fremden Laufwerk gilt nach dem Anstecken als
  installiert, wenn das Konto es besitzt, und sein Programm startet beim nächsten „Spielen“. Steam prüft nichts,
  legendary zählt nur, ob 95 % der Dateien da sind (und nimmt ein Manifest aus `.egstore` des Laufwerks: **Vermutung**
  aus legendarys Quelltext), GOG prüft nichts; der Startpfad aus GOGs Infodatei bleibt im Ordner
  (`GOGLibrary.swift:304`). Der Spieler liest die eine Zeile „… sind wieder da“. Empfehlung für 0.3.4: Epic und GOG
  vor dem ersten Start einmal prüfen lassen.
- **W5 · Steams Spiele zählen vor dem Besitz.** `DriveTakeover.take` (`DriveTakeover.swift:284`) meldet jedes Manifest
  der Bibliothek als „wieder da“, auch halbe Downloads und Spiele eines anderen Kontos; Epic und GOG fragen vorher das
  Konto.
- **W6 · Auf dem Laufwerk wird an einer Stelle geschrieben:** `SteamLibraries.ensure` legt `steamapps/common` an und
  schreibt `libraryfolder.vdf`, wenn sie fehlt oder keine `contentid` hat (`ExternalDrives.swift:285`–`:294`,
  unverändert seit 4.2). Gelöscht wird nichts. Der Satz „nichts auf dem Laufwerk wird überschrieben“
  (`DriveTakeover.swift:119`) stimmt bis auf diese Datei.
- **W7 · Versteckte Schalter, die ein Release weiter kennt** (Entscheidung, kein Fehler): `gameTest` mit `.only`,
  `.pictureWait`, `.playSeconds`, `.stop`, `.basket`, `.frameLog` (der ganze Spieletest, mit Bildraten-Protokoll seiner
  eigenen Starts und `sample` bei hängenden Spielen ohne Anti-Cheat; schon in 0.3.2), `closerLook` (jeder Start mit
  allen Kanälen, **auch bei Anti-Cheat-Spielen**, `LibraryModel.swift:4835`), `wineDebug`, `vulkanLoader`, `msync`,
  `wineSandbox`, `gameEnvironment.<Spiel>`, `dxmtEarlyShaders`, `parkPointerOverGames`, `unityDialogPlay`,
  `battleNetStore`, `resolutionFitOff`, `UpdateTestRelease`. Keiner zeichnet ohne Zutun etwas auf, nichts verlässt den
  Mac. Neu in 0.3.3 und immer an ist `start-evidence.jsonl` (je Start eine Zeile mit Spiel, Weg, Rezept, Dauer;
  bleibt auf dem Mac, wird nie gekürzt, `StartEvidence.swift:58`): Gedächtnis der Startlogik, kein Messen beim
  Spielen – gehört aber in die Release-Notizen.
- **W8 · A für „Neu starten“ kommt auch im Spiel an** (**Vermutung**, was es dort auslöst). Die Pad-Stille gilt nur
  bei offenem Overlay (`PadSilence`); `restartsHiddenGame` (`LibraryModel.swift:2064`) beendet das Spiel sofort danach.
  Im unsichtbaren Menü bestätigt ein A den markierten Punkt, etwa „Akzeptieren“ unter einer Lizenz; mehr als ein
  Druck kommt nicht an. Live an Overwatch ansehen.
- **W9 · „Hinzufügen und starten“ ist vorgewählt** (`OverlayView.swift:207`). Sobald eine Wurzel in
  `WindowsRoots.onRequest` steht, ist die Frage mit einem A bejaht.

## Beim Nachtrag aufgefallen (nur beschrieben)

- **N1 · Der Anti-Cheat-Weg liest weiter die Absturzberichte des Spiels** (Textdateien, keine Dumps). „Der Befund nur
  aus Wines Protokoll“ stimmt für Dumps, Debug-Kanäle und alles aus Schritt E, nicht für diese vier Stellen, die es
  schon vor Schritt E gab und die für jedes Spiel laufen: `crashed` bei bestätigtem Weg (`LibraryModel.swift:5016`),
  `crashedAtAll` (`:5061`), `crashTexts` (`:5137`) und `GameLog.illegalInstruction` (`:5149`). Sie durchsuchen den
  Spielordner und den Prefix nach `CrashContext.runtime-xml` seit dem Start und lesen die Meldung. Darauf beruhen die
  Abhilfen „ohne die Schalter“ und „braucht DirectX 12“, die auch Anti-Cheat-Spiele bekommen. Meint die Regel „ihre
  Dateien nicht ansehen“ auch diese Berichte, ist das ein eigener kleiner Schritt für alle solchen Spiele, mit dem
  Preis, dass die zwei Abhilfen dort entfallen. Nicht gebaut.
- **N2 · Drei weitere Enden nach „Noch ein Versuch …“ ohne Versuch**, alle dort, wo das Ende als das des Spielers
  gilt und „Das hat nicht geklappt.“ falsch wäre: ein bewährter Weg endet zum ersten Mal früh und bekommt keinen
  leisen zweiten Start (eigener Launcher oder Anti-Cheat, `:5093`), das Spiel endete an seiner eigenen Frage und der
  Spieler hat gewählt (`:5077`), und beim leisen Start ist nicht sicher, ob das Spiel weg ist (`:5109`). Die Zeile
  steht dort nur, solange Nightforge liest (unter einer Sekunde). Empfehlung: `sayRepair(.looking)` in diesen Fällen
  gar nicht sagen; ob es das Ende des Spielers sein kann, steht vor dem Lesen fest (`outcome`, `ownQuestionEnd`).
- **N3 · W2 bleibt:** Was ein Spiel gelernt hat, bevor es als Spiel mit (eigenem) Cheat-Schutz galt, trägt das Rezept
  weiter ein (`StartRecipe.swift:44`). In einem Release hat kein Spiel etwas gelernt, bevor 0.3.3 es kennt.

## Geprüft, in Ordnung

- **Keine Endlosschleife.** Jede Runde von `starts:` (`LibraryModel.swift:4742`) endet mit `return`, `break` oder einem
  von fünf `continue`, jedes gedeckelt: der leise zweite Start einmal (`:5110`), die Engine davor einmal
  (`EngineRollback.afterFailedStart` löscht `lastGood`, dann den Pin, `EngineRollback.swift:335`), derselbe Weg
  höchstens dreimal je „Spielen“ über alle Wege zusammen (`NextStart.againLimit`; auch die Wurzel-Frage zählt, `:5201`),
  die Leiter nur vorwärts (`NextStart.way` nimmt nur Wege hinter `index`). Über mehrere „Spielen“ wiederholt sich
  eine Abhilfe nicht: was im Rezept steht, ist keine Änderung (`Learned.applying` gibt `nil`).
- **Anti-Cheat (EAC, BattlEye, Sperre):** Dateien werden nicht gelesen (`:5043`), die Entscheidung bekommt nur die fünf
  Abhilfen von vor Schritt E (`NextStart.asBefore`), `dllsOff` wird verworfen (`NextStart.swift:84`), kein genauerer
  Blick (`CloserLook.step`), kein Befund vom Testschalter. Die Kanäle jedes Starts (`+pid,+loaddll,+msgbox`) sind
  Wines eigene Ausgabe.
- **Aufstieg von 0.3.2:** Ein dort bestätigter Weg übernimmt das Rezept des ersten Starts (`LaunchHealth.adoptRecipe`)
  und bleibt bestätigt; der Shader-Hinweis liest den alten Eintrag (`LaunchPhase.seenSignatures`).
- **Windows-Wurzel:** `onRequest` ist leer (`WindowsRoots.swift:62`), im Release kommt die Frage nie. Jede Wurzel ist
  eine Konstante mit SHA-1 und SHA-256, beide werden vor dem Eintragen geprüft (`:22`); der Name aus dem Protokoll
  wählt nur unter den Konstanten. Eingetragen wird allein in `HKCU\…\SystemCertificates\Root` des Prefix
  (`Engine.swift:2068`); im Quelltext gibt es keinen Aufruf von `security`, `SecTrustSettings` oder `SecItemAdd`. Ein
  Nein trägt nichts ein (`LibraryModel.swift:5199`), es bleibt nur der Name der Wurzel beim Spiel für die nächste
  Frage. Die Frage antwortet genau einmal, auch bei abgebrochenem Start (`GameOverlay.swift:362`).
- **Testschalter:** `gameTest.measurePlay`, `gameTest.testFinding`, `testRootQuestion` stehen samt Schlüssel nur im
  `#else` (`GameTest.swift:54`, `StartDiagnosis.swift:247`, `WindowsRoots.swift:100`); ohne gesetzten Schalter wirkt
  keiner. Die Schlüssel haben 20, 20 und 16 Byte; der Schritt in `release.yml:67` findet sie (`bash -e` ohne
  `pipefail`). `sign-release.sh` baut nicht neu, es signiert das Zip aus dem Workflow (`:57`).
- **Laufwerks-Übernahme:** Gelöscht wird auf dem Laufwerk nichts (Steam: ein Eintrag in der Liste; Epic: legendarys
  Liste, ein unvollständiges Spiel wird mit `--keep-files` vergessen, `EpicStore.swift:773`; GOG: `installed.json`).
  Abziehen mittendrin: `ensure` scheitert am Laufwerk, bevor eine Liste geschrieben ist, Steam startet wieder
  (`DriveTakeover.swift:427`). Zwei Laufwerke mit demselben Spiel: das zweite gilt als bekannt (`:211`). Zweimal
  laufen: `looking`, `handedOver`, idempotentes `ensure`. Links auf Ordner zählen nicht (`DriveFinds.swift:119`),
  GOG-Kennungen, Sprache, Add-ons und Epics App-Namen sind geprüft, der Pfad geht als eigenes Argument an legendary.
  **Vermutung:** `legendary import` schreibt nichts in den Spielordner (live in Teil B ansehen).
- **Vorhang:** Jede Zeile, die vom Schirm ging, steht im Protokoll („Start phase: …“ mit dem ganzen Satz,
  `LibraryModel.swift:133`; „Curtain: …“ mit `LaunchRepair.logLine`, `:2115`). Alle 1.313 Texte aus `L10n.t` haben
  ihre deutsche Fassung, keiner fehlt. „Neu starten“ gibt es nur, solange der Hinweis steht und kein Overlay offen
  ist; das Ende zählt als das des Spielers (`LaunchHealth.playerQuit`), es startet nichts von selbst wieder.
- **Spieletest und Profile:** Vor `sample` steht immer `handsOff` (`GameTestRun.swift:395`). `build-profiles.py:363`
  lässt für `ownAntiCheat` nur `true`/`false` zu und für `fullscreenHint` ein Wörterbuch mit `en`, einzeilig, bis 80
  Zeichen. Der Dump-Leser prüft jede Stelle gegen die Dateigröße (`CrashDump.swift`).
- Nicht vertieft: `scripts/laeuft-liste.py` (Entwicklerwerkzeug, läuft nicht beim Spieler, eigene Tests).

## Tests

Nach den `.rc`-Dateien in `build/test-logs`, je Lauf `scripts/run-tests.sh -P 2 <Reihen>`:

- 24 Reihen rund um Manifeste, Scan und Laufwerke, alle 0: BugManifestNumbers, BugMenuMissingDrive,
  BugQuitExternalLibraries, CompleteRemoval, DriveFinds, DriveTakeover, DuplicateGames, Epic, ExternalDrive, GOG,
  LauncherMenu, MacVersion, ModelFlows, QuitDrives, QuitScript, ScanFreshness, ShaderCaches, SpaceCheck,
  SteamBackground, SteamOwnership, SteamProgram, SteamSwitch, UpdateState, VDF (1 min 45 s).
- 6 Reihen für B4 und die Startregeln, alle 0: LaunchHealth, EngineLayout, GameTest, StartDiagnosis, CloserLook,
  StartRecipe.
- `python3 -m unittest tests/test_release_switches.py tests/test_workflow_scripts.py`: 7 Tests, OK.
- Nicht gelaufen: die übrigen rund 90 Reihen und die anderen pytest-Dateien. Vor dem Einspielen einmal die ganze Kette.
- Nachtrag (B6 bis B8, auf `689520f`), 18 Reihen, alle 0: CloserLook, CurtainKeeper, EngineLayout, ExperienceAudit,
  GameMenu, GameOverlay, GameTest, LaunchEdge, LaunchHealth, ModelFlows, ModelNavigation, PadAndCurtainFuzz,
  SmallLogic, StartDiagnosis, StartRecipe, StartRules, StringRules, Strings. Die ganze Kette lief auch hier nicht.

Ein Fehler von mir unterwegs, behoben: Der Ordner heißt in git `tests/`, ich hatte `Tests/` angegeben, und die ersten
drei Commits enthielten ihre Testdateien nicht. Ich habe die drei lokalen, nicht gepushten Commits neu gebaut, jeder
jetzt mit seinem Test; der Baum ist derselbe wie davor plus die Tests.

## Zweite Runde (17.11.)

Geprüft: `claude/staging-033` bei `376f0ea` (darin B1 bis B8), mit dem Blick auf das, was die Live-Runde anfasst und
noch nie live lief, und quer über den ganzen Unterschied `origin/main..376f0ea`. Regeln wie in der ersten Runde,
Zeilennummern in diesem Abschnitt gelten für `376f0ea`. Die
zwei Commits liegen auf `claude/audit-033-abschluss-d51880`, je mit Test. Gelesen habe ich die riskanten Stellen jedes
Teils (Netz, Warteschleifen, Fortsetzungen, Zustand nach Abbruch, Pad-Wege), nicht jede Zeile der rund 3.800 Zeilen;
was ich nicht gelesen habe, steht unter „Nicht vertieft“.

### Ergebnis

- **Kein neuer Fehler** in den durchgesehenen Teilen. Nichts blockiert die Live-Runde.
- **N2 und W3 gebaut**, je ein eigener Commit (B9, B10). W3 hat einen Preis, der unten steht; es lässt sich einzeln
  zurücknehmen (`git revert e1f79e6`), N2 hängt nicht daran.
- `swiftc -typecheck -D NIGHTFORGE_RELEASE` über alle Quellen auf dem Endstand (`e1f79e6`): keine Fehler.

### Behoben

| Nr. | Schwere | Was | Datei | Commit |
|---|---|---|---|---|
| B9 | niedrig | N2: „Noch ein Versuch …“ stand auch dort kurz, wo das Ende das des Spielers sein kann und kein Start folgt | `LibraryModel.swift:5030`, `LaunchRepair.swift` | `3afd0b1` |
| B10 | mittel | W3: Ein Spiel, das der Spieler an einem kleinen eigenen Fenster schließt, kam je Weg der Leiter wieder | `LaunchHealth.swift:504`, `LibraryModel.swift:5068` | `e1f79e6` |

**B9 · N2.** `LaunchRepair.saysLooking` entscheidet, ob die Zeile gleich am Ende eines Starts kommt. Nicht mehr,
wenn ein bewährter Weg zum ersten Mal früh endet (`.keep`: „früh beendet, dem Anschein nach“) und nicht, wenn das
Spiel an seiner eigenen Frage endete und der Spieler geantwortet hat. Der leise zweite Start sagt seine Zeile weiter
selbst (`onceMore`), sobald sicher ist, dass das Spiel weg ist; wird ein Ende an der Frage doch ein Fehlstart, sagt
die Entscheidung danach den Versuch oder das Ende. Damit sind alle drei Enden aus N2 abgedeckt.

**B10 · W3.** Das erste Ende eines „Spielen“ an einem Fenster, das nichts sagt (keine Meldungsbox, kein bekanntes
eigenes Fenster, kein Fehler in der Tabelle), bleibt ein Fehlstart wie seit Schritt E5. Das zweite im selben
„Spielen“ gilt als Wahl des Spielers, wenn nichts gefunden wurde, das dagegen spricht
(`StartDiagnosis.speaksAgainstAChoice`: jede Diagnose außer bloßer Debug-Ausgabe). Der Spieler bekommt also einen
Neustart zu viel statt einem je Weg.

- Die live gesehene Kette von Metal Gear Solid V bleibt: Der zweite Start (mit genauerem Blick) findet
  `untrusted-root`, das spricht dagegen, es geht weiter zur Frage nach der Wurzel. Im Test nachgestellt.
- **Preis:** Die Leiter bleibt, wo das erste Ende sie hinstellte. Bei einem Spiel, das wirklich auf den ersten zwei
  Wegen mit einem eigenen Fenster scheitert und auf dem dritten liefe, kommt der dritte erst mit dem nächsten
  „Spielen“. Umgekehrt steht ein Spiel, dessen Fenster der Spieler zweimal absichtlich geschlossen hat, danach auf
  dem zweiten Weg statt auf dem ersten; läuft es dort, bleibt es dort. Zurückstellen wollte ich die Leiter nicht:
  dann käme ein wirklich scheiterndes Spiel nie über den zweiten Weg hinaus.
- **Zweiter Preis:** Ist das Fenster doch die Fehlermeldung des Spiels und findet sich auch beim zweiten Mal nichts,
  endet der Start nach dem zweiten Fenster still auf der Seite: ohne „Das hat nicht geklappt.“ und ohne den Dialog
  mit „Am verträglichsten“ und „Nochmal mit dem ersten Weg“, die bisher nach dem letzten Weg kamen. Der Spieler hat
  dann nur gesehen, was das Fenster des Spiels selbst sagte.
- Gilt auch für Spiele mit Anti-Cheat oder eigenem Cheat-Schutz (dort wird nichts gefunden, also nie etwas dagegen).

### Sollte vor dem Release

Nichts Neues. Offen bleibt aus dem Nachtrag N1 (der Anti-Cheat-Weg liest die Absturzberichte des Spiels), als
Entscheidung des Nutzers.

### Kann warten

- **Z1 · Anmelden vom Sofa läuft über einfaches HTTP im eigenen Netz** (bekannt, `docs/ENTWURF-ANMELDEN.md:8`, `:138`).
  Token und GOGs Einmal-Code gehen unverschlüsselt vom Handy zum Mac; wer im selben WLAN mitlesen kann, sieht beide.
  Sonst hält die Seite, was sie verspricht: an die Adresse des Macs im Netz gebunden, nur dessen Teilnetz, 256 Bit
  Zufall im Pfad, Vergleich ohne Zeitspur, höchstens 8 Verbindungen und 16 KB, nichts vom Besucher kommt in einer
  Antwort zurück, zu nach dem ersten Code oder nach zehn Minuten (`PhoneSignInServer.swift`, `PhoneSignIn.swift`).
- **Z2 · Die Übernahme für Steam für Mac steht in keiner Warteschlange** (**Vermutung**).
  `takeOverMacSteamLibrary` (`DriveTakeover.swift:436`) beendet ein von Nightforge gestartetes Steam für Mac, schreibt
  die Liste und startet es wieder; anders als beim Windows-Steam (`:398`, über `steamStartup`) wartet ein Start eines
  Mac-Spiels in genau dieser Sekunde nicht darauf. Startet Steam für Mac, während die Liste geschrieben wird, kann es
  sie beim Beenden überschreiben; die Spiele des Laufwerks fehlen dann bis zum nächsten Anstecken oder Start.
- **Z3 · Laufwerk weg mitten im Start.** Die Schleife prüft nur am Anfang, ob das Spiel installiert ist. Fehlt der
  Ordner danach, geht der nächste Versuch an Steam und endet nach dessen zwei Minuten ohne Lebenszeichen; B führt
  vorher heraus (`CurtainEscape`). Kein Hänger, aber ein langer Vorhang.
- **Z4 · Bei Spielen mit Cheat-Schutz fällt auch weg, was allein aus Wines Protokoll käme** (der Text einer
  Meldungsbox, `CloserLook.read`): Er wird mit den Dumps zusammen gelesen (`StartDiagnosis.finding`) und deshalb mit
  ihnen ausgelassen. Eine Fehlermeldung solcher Spiele gilt damit nur nach der Fenster-Regel.

### Geprüft, in Ordnung

- **Anmelden vom Sofa:** Bühne und Seite schließen zusammen (`signingIn`-Wechsel schließt die Tür, `LibraryModel.swift:285`;
  `onDisappear`). A holt nach Ablauf einen neuen Code, X wechselt zur Tastatur und zurück, B bricht ab, auch wenn ein
  fremdes Fenster vorn ist. Ohne Heimnetz sagt die Bühne es und nennt den Weg mit der Tastatur.
- **Pad-Wege:** Solange die Bildschirmtastatur offen ist, hält jede andere Taste still (A, B, X, Y, ☰, L1/R1, Sticks,
  Scrollen); sie schließt, wenn der Controller geht oder Nightforge nicht mehr vorn ist (`InputRouter.swift:723`), und
  ihr Takt läuft nur, solange sie offen ist. „Neu starten“ wirkt einmal: der Hinweis ist nach dem ersten A weg.
- **Lizenz beim ersten Start:** Nightforge beantwortet sie nie und schreibt nichts davon; die Regeln stehen auf
  Messungen (`SteamLicence.swift`). Mit dem Pad lässt sie sich nur beantworten, wenn der Zeiger an ist und macOS
  die Bedienungshilfen freigegeben hat; sonst sagt die Leiste „mit der Maus“.
- **Battle.net-Start:** Jede Schleife hat eine Frist (90 s bis bereit, 10 min fürs Anmelden, 5 min nach der Frage),
  jeder Abbruch setzt `awaitingSteam` und `launchPhase` zurück, jedes Ende hat seinen Satz.
- **Zwei Controller, Startseite, neue Einstellungen:** Platz 5 bekommt keine Nummer statt eines Absturzes; alle neuen
  Einstellungen haben einen Wert ohne Eintrag (`padPointer`, `padHaptics`, `parkPointerOverGames` an, `keepAwakeMinutes`
  0, Quellen der Startseite), der Zeiger fragt nur aus den Einstellungen nach der Freigabe.
- **Nebenläufigkeit:** Zwei schnelle Drücke starten nicht zweimal (`mayStart`). Ein Start wartet auf eine laufende
  Übernahme des Windows-Steam (`steamStartup`), die Übernahme prüft `takeoverBusy` vor jedem Schritt. Die Frage zur
  Wurzel antwortet genau einmal. Der Zustand der Startschleife gehört dem einen Task auf dem Hauptakteur.
- **Lebenszyklus:** Ein genauerer Blick steht in Steams Kennung (`steamConfigSignature` über `launchEnvironment`):
  Nach einem Neustart von Nightforge startet ein Steam, das noch die Kanäle trägt, neu. Der Updater wartet, solange
  ein Spiel läuft oder eines verschoben wird. Controller weg mitten in einer Frage: Tastatur und Maus antworten weiter.
- **Aufstieg von 0.3.2:** `steamConfigVersion` 11 startet Steam einmal neu; ein bestätigter Weg ohne Rezept bleibt
  bestätigt; alte `shaders.*`-Einträge werden übernommen; der Stempel der Profilliste liegt nicht in der Zukunft.
  Die signierte Liste bleibt Sache des Nutzers.
- **Protokoll-Leser und `+pid`:** Außer `GameLog.errors` (B4) hängt keiner am Zeilenanfang: Bildraten kommen aus
  DXMTs eigenen Zeilen oder über `CloserLook.Line`, fehlende Laufzeiten und Grafikfehler über den Text.
- **Texte:** Alle 1.313 Texte aus `L10n.t` haben ihre deutsche Fassung, auch auf dem Endstand.
- **Meine acht Behebungen und `3c4981c`, `9bda7de`** noch einmal gelesen: ohne Befund.

### Nicht vertieft

`PadKeyboard.swift` (die Tastatur selbst, 414 Zeilen), `TouchpadPointer.swift` (Gesten), `GameBackdrop.swift`
(Bilder des Ladebildschirms), `TVLayout`/`TVRules`, `IdleRest`, `SteamOnDemand`, Ruhezustand und Aufwachen. Dort habe
ich nur die Stellen gelesen, an denen sie die Startschleife oder das Pad berühren.

### Für die Live-Runde

- **Anmelden am Sofa (GOG, QR):** Ist die macOS-Firewall an, kann macOS beim Öffnen der Seite fragen, ob Nightforge
  eingehende Verbindungen annehmen darf (**Vermutung**, im Entwurf als „live prüfen“ vermerkt). Die Frage nimmt nur
  die Maus. Handy im Gast-WLAN: Die Seite lädt nicht, der Code läuft nach zehn Minuten ab; dann A für einen neuen.
- **Lizenz (GTA V):** Was die Leiste sagt (Touchpad, Stick oder Maus) und ob der Klick ankommt. Ohne Freigabe der
  Bedienungshilfen ist „mit der Maus“ richtig, kein Fehler.
- **Tastatur für den Controller:** Y in der Bibliothek; ☰, A oder R2 auf „Fertig“ und B schließen, ohne dass die Seite
  dahinter den Druck noch bekommt. Controller ausschalten, während sie offen ist: Sie muss zugehen.
- **Zwei Controller:** Der zweite hält beide Sticks nicht: Das Overlay muss beim ersten trotzdem aufgehen (B1 vom 8.11.).
- **Battle.net:** Abbrechen mit B, während der Client sich anmelden will: zurück zur Seite, kein stehender Vorhang.
- **Overwatch im Vollbild:** der Hinweis, ein ⌘⇥, „Neu starten“ per Pad; im Protokoll „the player restarts … with the
  pad“, danach kein „Noch ein Versuch …“ und kein Fehlstart.
- **Ein bewährtes Spiel in den ersten Sekunden beenden** (ohne Launcher): Der Vorhang darf nicht mehr „Noch ein
  Versuch …“ zeigen, bevor der leise zweite Start wirklich kommt (N2).
- **Ein Spiel mit kleinem eigenem Startfenster, dort „Beenden“:** einmal kommt es wieder, beim zweiten Schließen ist
  Schluss; im Protokoll „a window that says nothing, for the second time in this Play … the player's choice“ (W3).
- **Metal Gear Solid V mit `testRootQuestion`** (nur Testbuild): Die Kette bis zur Frage muss wie am 15.11. laufen;
  W3 darf sie nicht nach dem zweiten Fenster beenden.
- **Laufwerk Teil B:** Steam für Mac: nicht in derselben Sekunde ein Mac-Spiel starten (Z2). Epic: der Spielordner
  nach `legendary import` unverändert. Die eine Zeile „… sind wieder da“ zählt bei Steam auch halbe Downloads (W5).

### Tests der zweiten Runde

Auf dem Endstand der Quellen (`e1f79e6`), nach den `.rc`-Dateien in `build/test-logs`:

- `scripts/run-tests.sh -P 2`, die ganze Kette: **121 Reihen, alle 0** (3 min 16 s).
- `python3 -m unittest discover -s tests -p 'test_*.py'`: **286 Tests, OK** (24 Dateien, 75 s).
- `swiftc -typecheck -D NIGHTFORGE_RELEASE` über alle Quelldateien: keine Fehler.
- Vor den Commits einzeln: `SmallLogicTest` (N2) und `StartRecipeTest` (W3), beide 0. Beide Tests prüfen neue Regeln
  (`LaunchRepair.saysLooking`, die zwei neuen Angaben von `LaunchHealth.ownQuestionWasAChoice`); vor der Änderung
  bauen sie nicht, ein „vorher rot“ im engeren Sinn gibt es deshalb nicht.
- Nichts live: keine Nightforge-Fenster, keine Spiele.

## Live prüfen

- Overwatch im Vollbild: ein ⌘⇥ reicht, „Neu starten“ per Pad, und was das A im unsichtbaren Spiel auslöst (W8).
- Ein Spiel mit kleinem eigenem Startfenster, dort „Beenden“: kommt es wieder (W3)?
- Laufwerk Teil B: bleibt der Spielordner nach `legendary import` unverändert; die Zeile bei einem fremden Konto (W5).
- Ein bewährtes Spiel dreimal in den ersten Sekunden beenden: was der Vorhang zuletzt sagt (S2) – jetzt
  „Das hat nicht geklappt.“ für drei Sekunden, dann die Seite.
- Overwatch nach einem Ende ohne Bild: im Protokoll keine „Diagnosis for …“-Zeile aus Dumps, kein genauerer Blick,
  der nächste Weg wie vor Schritt E (S1).
- Nach „Das hat nicht geklappt“ auf „Nochmal mit dem ersten Weg versuchen“: im Protokoll „… starts over: what earlier
  starts taught is forgotten – …“, wenn das Spiel etwas gelernt hatte (W1).

## Nachlese des Koordinators (17.11.)

Neben der zweiten Runde, auf demselben Stand (`376f0ea`), ohne Nightforge-Fenster und ohne Spiele.

### Behoben

| Nr. | Schwere | Was | Datei | Commit |
|---|---|---|---|---|
| B11 | hoch für das Release | Die Prüfkette auf GitHub scheiterte am Test der Bau-Abkürzung; alle Schritte danach liefen nicht | `tests/test_testbuild.py` | `b61b765` |
| B12 | hoch für das Release | Eine von 121 Testreihen baute auf GitHub nicht: der von Swift erzeugte Initialisierer ist dort privat | `TouchpadPointer.swift:52` | `be14133` |

**B11 · Die Prüfkette auf GitHub.** `ci.yml` läuft nur bei `main`, einem PR oder von Hand; für den am 15.11. gesicherten
Zweig (`78ac7d0`) war sie nie gelaufen. Von Hand angestoßen (Lauf 44177202673): Der Bau der App ist grün, der Schritt
„Test build shortcut“ rot (21 Fehlschläge, 5 Abbrüche, jeder Aufruf des Skripts endet mit 72), und damit wurden die
Swift-Tests und alle weiteren Schritte übersprungen. Ursache: Der Test gibt dem Skript einen erfundenen SDK-Pfad
(`SDKROOT=/sdk`) und ruft es über dessen erste Zeile auf, `/usr/bin/python3`. Mit einem ausgewählten Xcode ist das ein
Stub, der `xcrun` fragt, und `xcrun` gibt bei einem SDK auf, das es nicht gibt. Nur mit den Command Line Tools (dieser
Mac) stört der Pfad nicht, deshalb war der Test lokal immer grün. Die acht Tests derselben Datei, die den Pfad
entfernen („git asks the real SDK“), waren auch auf GitHub grün. Nachgestellt mit `DEVELOPER_DIR=/nonexistent` (stellt
die Stubs kalt): dasselbe Bild, 21 Fehlschläge und 5 Abbrüche. Behoben: Das Skript und das Python des Compiler-Ersatzes
laufen im Test mit dem Interpreter des Tests, nie über den Stub. Danach mit kaltgestellten Stubs 16 von 16 (die übrigen
acht brauchen `git`), normal 24 von 24, auch mit Python 3.14. Die Testkette selbst (`scripts/run-tests.sh`) ist nicht
betroffen: Sie setzt auf einem Mac mit Xcode keinen SDK-Pfad.

**B12 · Eine Testreihe baute nur hier.** Nach B11 gepusht (mit OK des Nutzers) und neu gestartet (Lauf 44181523836
auf `c7397f2`): der Test der Abkürzung grün, 120 von 121 Reihen grün, `TouchpadPointerTest` rot beim Bauen
(„argument passed to call that takes no arguments“), die neun Schritte danach übersprungen. `TouchpadPointer` hat
neben `screenScale` nur private Eigenschaften; den Initialisierer, den Swift selbst erzeugt, macht das Swift von
Xcode 26.6 (GitHubs Runner) deshalb privat, das Swift 6.4 dieses Macs nicht. Die App ruft ihn nur im Typ selbst
auf, die Testreihe aus ihrer eigenen Datei. Behoben: der Initialisierer steht ausgeschrieben da.

**Ergebnis auf GitHub:** dritter Lauf (44186316561 auf `be14133`) **ganz grün**, alle 14 Schritte, zum ersten Mal
seit 0.3.2. Lokal davor: ganze Kette grün (121 Reihen, 286 Python-Tests), die neun Schritte hinter den Swift-Tests
einzeln mit Python 3.14 grün. Gemerkt für später: `ci.yml` läuft nur bei `main`, einem PR oder von Hand; nach
jedem Push eines Testzweigs von Hand anstoßen (`gh workflow run ci.yml --ref <Zweig>`).

### Geprüft, in Ordnung

- **Mechanische Durchsicht des ganzen Unterschieds `origin/main..376f0ea`** (14.072 neue Zeilen in `Sources`): jede
  neue Stelle, die löscht, verschiebt oder überschreibt (13: Bausteine, Shader-Übersetzungen, Updater, eigene
  Merkdateien; nichts im Spielordner oder auf einem Laufwerk), erzwungenes Auspacken und harte Abbrüche (6, alle
  durch die Zeile davor gedeckt), Zugriffe mit festem Index (rund 40, alle hinter einer Längenprüfung), Warteschleifen
  (33, jede mit Frist oder Abbruch), neue Unterprozesse (5). Ohne Befund.
- **Ganz gelesen, weil die zweite Runde sie nicht vertieft hat:** `PadKeyboard.swift`, `PadKeyboardView.swift` mit dem
  Öffnen, Füttern und Schließen in `InputRouter.swift` und `LibraryModel.swift` (Y öffnet nicht zweimal; ein Schließen
  mit der Maus räumt der nächste Takt auf), `IdleRest.swift`, `PhoneSignIn.swift`, `PhoneSignInServer.swift`; dazu die
  Änderungen seit `365f393` an `SteamOnDemand.swift`, `TouchpadPointer.swift`, `PadPointer.swift` und
  `GameBackdrop.swift`. Ohne Befund. `TVLayout.swift` und `TVRules.swift` sind seit dem Audit vom 8.11. unverändert.
- **Compiler-Warnungen** eines frischen Baus (26): Hinweise zu `Sendable` und zu schwachen Bezügen, nichts Inhaltliches.
- **Einstellungen des Nutzers vor der Live-Runde:** kein Testschalter gesetzt (nur `battleNetStore` und der Pfad des
  Testkorbs), kein Spiel hat etwas gelernt (`learned.dllsOff`, `learned.steps` leer).
- **Bundle:** keine Daten von AppleGamingWiki oder PCGamingWiki darin (`agw.json`, `pcgw.json`, `agw-notes.json`
  bleiben im Repository und werden nachgeladen).

### Für das Release gemerkt

- Der Testbuild hat `pad-answer.exe` (auf diesem Mac mit mingw gebaut), ein Release erst, wenn der Bot-PR von
  `pad-answer.yml` nach dem Merge auf `main` angenommen ist. Was die Live-Runde zu A und B in Windows-Fragen zeigt,
  gilt für das Release nur dann.
- Anmelden vom Sofa: Der Server hält sich über die beiden Abschluss-Funktionen selbst fest und wird nach dem Schließen
  nicht freigegeben (wenige Kilobyte je Anmeldung, die Tür ist dann zu). Kein Fehler, den jemand bemerkt.
