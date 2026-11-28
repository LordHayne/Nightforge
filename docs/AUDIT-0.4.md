# Gegenlese-Audit der wartenden 0.4-Zweige (24.11.2026, Worker K)

Nur gelesen, nichts gebaut, nichts ausgeführt, an den Zweigen nichts geändert. Grundlage: jeder Zweig an seiner Spitze
gegen main 1e605c6b (0.3.5), `git diff 1e605c6b...<zweig>`, und der Code des Zweigs im Zusammenhang. Zeilen gelten für den
Stand des jeweiligen Zweigs. Drei Zweige (d3dmetal4, overlay, steam-pad) haben Helfer gelesen; ihre tragenden Funde sind
hier gegen den Code nachgeprüft (steht dabei).

| Zweig | Spitze | Merge auf main | Ergebnis |
|---|---|---|---|
| start-schneller-04 | 8de4bb1e | ohne Konflikt | in Ordnung, eine Kleinigkeit (SS1) |
| d3dmetal4-messen-04 | 63d4d20d | ohne Konflikt | **DM1**, **DM2**, **DM3**, DM4 – vor dem Merge beheben |
| overlay-glasblatt-04 | 39958992 | ohne Konflikt | **OV1**, OV2, OV3 |
| steam-pad-wahl-04 | 7668f670 | **Konflikte** (3 Dateien) | **SP1**, **SP2**, SP3–SP5 – vor dem Merge neu auf main setzen |
| anticheat-sperren-04 | ac5bb16d | ohne Konflikt | in Ordnung, zwei Hinweise (AC1, AC2) |
| nx-compat-04 | cc40339e | ohne Konflikt | in Ordnung |

Schwere: hoch = bricht etwas sicher oder hält den Merge auf; mittel = falsches Verhalten in einem erreichbaren Fall;
gering = selten oder nur unschön.

## start-schneller-04

**SS1 · Die Vermutung „nächstes Spiel“ prüft nach dem Warten nicht noch einmal, ob ein Start begonnen hat (gering).**
`SteamOnDemand.swift:171–183` (`takeLikelyNextGamesSettings`), aufgerufen in `LibraryModel.swift:3126` mit `!gameUnderWay`.
- `gameUnderWay` wird vor dem `await Engine.offMain { mayTake … }` gelesen. Drückt der Spieler in diesem Moment Spielen (im
  Konsolenmodus direkt nach dem Öffnen naheliegend), setzt `takeRememberedLaunch` trotzdem die Einstellungen des vermuteten
  Spiels. Steam startet damit, und der Start des gedrückten Spiels bezahlt den Neustart (20–23 s), den es mit seinen eigenen
  Einstellungen nicht gebraucht hätte.
- Ein Fehler im Ergebnis ist es nicht: Der Start wartet auf `steamStartup` (`LibraryModel.swift:5091–5094`) und rechnet seine
  Änderungen danach, startet also nie mit falschen Einstellungen.
- Vorschlag: Nach dem `await` `guard !gameUnderWay` wiederholen; besser noch, läuft ein Start, dessen Spiel nehmen
  (`launchingID`).

Geprüft und in Ordnung: Der Testschalter `gameTest.steamUserInitiated` steht im `#else` von `NIGHTFORGE_RELEASE`, in
`release.yml` und in `test_release_switches.py`, und `release-check.sh` liest die Liste aus `release.yml`. Der Helfer nimmt
`NIGHTFORGE_SPAWN_QOS` aus der Umgebung, ehe das Programm startet. Sein Bau kommt aus `build.sh`, die Kopie im Datenordner wird
nach Inhalt erneuert (`copyShippedHelper`). `NextSteamGame` ist rein und getestet. Unbekannte Prozessliste heißt: nichts ändern.

## d3dmetal4-messen-04

**DM1 · Solange die Sitzung auf D3DMetal 4 läuft, lässt sich der Standard nicht wechseln (mittel).**
`D3DMetalFlow.swift:230` (`finishD3DMetal`) gegen `Engine.swift:1010–1015`, `1030` (`ensureEngine`).
- `ensureEngine` stempelt die Fassung der Sitzung (`launchD3DMetal`, z. B. `apple-4.0b3`), `finishD3DMetal` vergleicht den
  Stempel mit dem Standard aus `D3DMetalSupply.current()` (z. B. `3.0`). War das letzte Steam-Spiel auf 4, meldet das Blatt
  nach „Ändern …“ „D3DMetal didn't go into the engine …“, und „Schließen“ nimmt die Wahl zurück.
- Wahrscheinlichkeit: mittel für jeden, der D3DMetal 4 nutzt, also gerade in Thomas' Messreihe.
- Vorschlag: In `finishD3DMetal` gegen das Label vergleichen, das `ensureEngine` schreibt
  (`D3DMetalVersions.label(Engine.launchD3DMetal, standard: wanted?.version)`), oder `launchD3DMetal` vor `setUpD3DMetal` auf nil
  setzen. Test dazu.

**DM2 · Beta-Import mit gewähltem, aber nicht eingebautem Standard: das Spiel startet ohne D3DMetal (mittel/gering).**
`D3DMetalFlow.swift:193–205` (`betaImport`, Fall `.beside`).
- `betaImport` prüft nur `standard != nil`. `current()` ist aber schon da, sobald die Wahl „Download from Nightforge“
  gespeichert ist, auch wenn der Download scheiterte. Ablauf: Download scheitert → „Download from Apple and Import“ → 4.0b3 →
  `.beside` → Hinweis „bereit“ → Start mit `d3dMetalChecked: true`, die Frage vor dem Start entfällt, die Engine hat kein D3DMetal.
- Vorschlag: `.beside` nur bei `Engine.d3dMetalReady`, sonst wie `.downloadStandard` (Wahl lassen, `setUpD3DMetal()`).

**DM3 · Eine importierte Beta schlägt das fertige D3DMetal 4 (mittel, sicher sobald Apple 4.0 fertig ausliefert).**
`D3DMetalVersions.swift:57–62` (`imported4`). **Nachgeprüft:** `["4.0", "4.0b3"].max { $0.compare($1, options: .numeric) ==
.orderedAscending }` ergibt `4.0b3`, ebenso gegen `4.0.1`.
- Folge: Nach dem Import des fertigen 4.0 behält `pruneImports` die Beta, Spiele mit `d3dmetal4` bekommen sie (`pick`), Steam
  startet für den Tausch neu, und die Einstellungen zeigen zwei 4er-Fassungen.
- Vorschlag: Fertige Fassungen vor Betas ordnen (Beta-Teil abtrennen, dann vergleichen); nil, wenn der Standard selbst ≥ 4 und
  nicht älter ist. Test mit `["4.0", "4.0b3"]` und `["4.0.1", "4.0b3"]`.

**DM4 · Nach „D3DMetal entfernen“ bleibt `launchD3DMetal` stehen (gering).**
`Engine.swift:2886–2907` (`applyD3DMetalVersion`), `D3DMetalFlow.swift:264` ff. (`removeD3DMetal`).
- Wird im selben Lauf neu eingerichtet, schreibt `applyD3DMetalVersion` das Label der entfernten Beta in den Stempel, baut
  aber den Standard ein. `d3dMetalSwapNeeded` sagt dann „passt“, das nächste `ensureEngine` baut die Grafik neu auf, und Steam-
  Starts beenden die Sitzung, bis ein D3DMetal-Spiel den Wert neu setzt.
- Vorschlag: In `removeD3DMetal` `Engine.launchD3DMetal = nil`; in `applyD3DMetalVersion` das Label aus dem tatsächlich
  eingebauten Payload bilden.

Geprüft und in Ordnung: kein neuer Testschalter (Messen über das vorhandene `gameTest.measurePlay`), keine Pfade im Log,
Texte nach den Regeln, Lock-Reihenfolge `launchSettings` → `sessionD3DMetal` ohne Umkehr, alte `RememberedLaunch`-Einträge lesen
sich als nil, `GameOptions.d3dMetal4` kodiert rückwärtsverträglich, `D3DM_MTL4` in `GameEnvironment.allowed` und
`build-profiles.py`. Zu DM1–DM3 fehlen Tests.

## overlay-glasblatt-04

**OV1 · Karten unter dem sichtbaren Rand erreicht das Pad nicht (mittel, wegen „Pad-only hart“).**
`OverlayView.swift:298–313` (`ScrollView` der Karten, `reveal(id, top: 0, bottom: 0)`) mit `PadFocus.swift:42`.
**Nachgeprüft:** `entries` nimmt nur Controls mit `view.visibleRect.width > 0`.
- Eine Karte, die beim Öffnen ganz unter dem Rand liegt, kennt `move` nicht; „runter“ springt von der letzten sichtbaren
  Karte zu „Weiterspielen“. `reveal` rollt nur bis zur Unterkante der fokussierten Karte, die nächste bleibt verdeckt. Der
  rechte Stick rollt über dem Overlay nicht (`scrollWithStick` verlangt `reach == .app`).
- Wann: am Fernseher mit allen Karten knapp an 1080 pt; „Spiel neu starten“, der Ton-Hinweis, die Eingabe-Zeile oder ein
  zweizeiliger Name reichen zum Überlauf (Rechnung des Helfers, live zu bestätigen).
- Vorschlag: `reveal` mit einem Rand von einer Kartenhöhe, oder im Overlay erst weiterrollen (`page(down:)`), ehe die
  Markierung zu den Wegen springt. Oder die Karten am Fernseher so kompakt, dass nie gerollt wird.

**OV2 · Die Lautstärke-Karte regelt den Standardausgang, auch wenn das Spiel noch auf dem alten Gerät spielt (gering).**
`GameOverlay.swift:178–194`, `LibraryModel.swift:2715`, `2750`.
- Nach einem Wechsel des Ausgangs während des Spiels zeigt das Overlay den Hinweis „bleibt auf …“ und zugleich einen Regler,
  der das andere Gerät ändert.
- Vorschlag: Bei `soundStaysOn != nil` die Karte ausblenden oder stattdessen den Hinweis zeigen.

**OV3 · Ein Mausklick auf die Lautstärke-Karte schaltet stumm (gering).**
`OverlayView.swift:364` mit `OverlayTiles.swift:427`: Der Klick ist „A“, also „Ton aus“; Ändern geht mit der Maus nicht.
Vorschlag: Klick links/rechts der Mitte als `adjust(-1/+1)`, oder die Karte ohne Maus.

Zum Ansehen im Live-Test, kein Fund: `OverlaySeamView.layout()` startet die Animation bei jedem Layout neu. Springt das Licht bei
Fokuswechseln nach oben, gehört der Start aus `layout()` heraus.

Geprüft und in Ordnung: Abbau bei Schließen und Spielende, kein Spiel → kein Overlay, Bildschirm des Spiels, Pad-Wege und B,
kein Blur und kein Schatten über dem Spiel (`Glass.leaf`), Naht als schmale Core-Animation-Ebene nur bei `shown` und ohne
„Bewegung reduzieren“, Foto ohne Erlaubnisfrage, keine Testschalter, deutsche Texte vollständig.

## steam-pad-wahl-04

**SP1 · Der Zweig geht nicht ohne Konflikte auf main, und zwei Quelltext-Tests schließen sich danach aus (hoch).**
**Nachgeprüft:** `git merge-tree` meldet Konflikte in `LibraryModel.swift`, `SteamQuestion.swift`, `tests/LaunchEdgeTest/main.swift`.
- main hat die Mac-Startstelle mit 836ba4a1 umgebaut (`SteamProgram.macHandOver`, `-applaunch` mit
  `Launcher.splitArguments(withScreen)`); der Zweig setzt seine Wahl (`chosenType`, `chosenArguments`, `handed`) auf den alten
  Stand (`LibraryModel.swift:3976–4024`).
- `tests/SteamProgramTest/main.swift` mergt ohne Konflikt, prüft danach aber im Quelltext sowohl main's
  `MacSteam.applaunch(appID, arguments: Launcher.splitArguments(withScreen))` als auch des Zweigs
  `MacSteam.applaunch(appID, arguments: handed)` (Zeile 677): einer wird rot, wie man auch auflöst.
- `SteamQuestion`: main ordnet `ShowGameArgs` schon als `.arguments` mit eigener Überschrift ein; im Zweig landet es bei
  `.other`. main's Fassung behalten.
- Vorschlag: Zweig neu auf main setzen, die Wahl in `macHandOver` einbauen (`chosenType` → `.launch(type)`, `chosenArguments` →
  `.applaunch` mit `extra + withScreen`), beide Quelltext-Prüfungen angleichen.

**SP2 · Der Weg `.type` umgeht Ebene und Programm und lässt die Argumente des Starts fallen (mittel).**
`Launcher.swift:588–596`, `645–648`; `SteamLaunchChoice.swift:61` (`way`), `86` (`steered`). **Nachgeprüft:** `chosen` wird
nur bei `route == .standard` bestimmt, `steered` sieht nur Programmwahl, Profilprogramm und Profilargumente.
- `.type` ist für jede Option erlaubt, auch eine, die ein anderes Programm startet. Die Ebene hat Nightforge aber für Steams
  erstes Programm gewählt, und bei `steam://launch/<id>/<Type>` fallen `recipe.arguments` (Schalter des Wegs wie `-dx11`, der
  Schalter am Launcher-Fenster vorbei), die Anti-Cheat-Aus-Argumente und `options.extraArgs` weg (nur geloggt).
- Ablauf: Option „DirectX 12“ gewählt, die Ebene ist für das DX11-Programm gewählt → schwarzes Bild oder Absturz → die
  Leiter rückt weiter, obwohl die Wahl schuld war.
- Vorschlag: `.type` nur, wenn die Option Steams erstes Programm startet (`option.starts(first.executable)`); sonst gilt die
  Programmwahl der Optionen. Oder `steered` auch bei nicht leeren `recipe.arguments`/`extraArgs`. Test dazu.

**SP3 · Mac-Version: ein erneutes Senden verliert die Wahl (gering).** `LibraryModel.swift:4006`, `4015–4024`. `run()` dient
auch als `send:` für `waitForMacStart`; dann ist `handOver` schon false, und `MacSteam.open(command)` schickt die erste Option
ohne die gewählten Argumente. Mit SP1 mitbehandeln.

**SP4 · Die Leiste sagt „einmal erlauben“, obwohl schon erlaubt ist (gering).** `LibraryModel.swift:1504` mit
`SteamLicence.swift:154`: `mayClick: PadPointerAccess.granted` ist der Wert vom App-Start; nach dem Erlauben im laufenden
Betrieb (`state == .afterRestart`) bleibt der alte Satz. `ConsoleMode` liest richtig `state != .missing`. Vorschlag: den Zustand
„nach Neustart“ eigens behandeln („gilt ab dem nächsten Start“).

**SP5 · Der Bogen „Zeiger erlauben“ gilt als beantwortet, auch wenn Nightforge ihn schließt (gering).** `LibraryView.swift`
(`onDismiss: pointerAccessClosed`), `LibraryModel.swift:3832`, `4378`: Räumt ein Start die Bögen (`closeSheets()`), wird
`console.accessAsked` gesetzt, und der Spieler wird nie gefragt. Vorschlag: nur bei „Später“, „Erlauben“ und B/Esc setzen.

Geprüft und in Ordnung: **keine Lizenz wird bestätigt** (kein Event an `ShowEula`, `ShowLaunchOption` wird nur erkannt), keine
Testschalter, Log ohne Konten und Pfade, deutsche Texte vollständig, Beta-Optionen und Bedingungen sperren die Wahl, Merken nach
Inhalt der Option je Spiel und Steam. Hinweis: `conditional` sperrt schon bei `osarch` im `config`; ob echte `appinfo.vdf` das oft
tragen, an einer echten Datei prüfen.

## anticheat-sperren-04

**AC1 · Die Liste ist bis zur Unterschrift auf main unsigniert (Hinweis).** `profiles/profiles.json` ist von Hand ergänzt,
`profiles.json.sig` nicht. Zwischen Merge und `scripts/sign-lists.sh` ist der Check „Signatures“ auf main rot, und die App nimmt
weiter die letzte signierte Liste (also ohne die zwei Sperren). Kein Fehler, nur: gleich nach dem Merge signieren.

**AC2 · Die neue Testklasse steht hinter `if __name__ == "__main__"` (gering).** `tests/test_build_profiles.py:562–566`. pytest
findet sie, `python tests/test_build_profiles.py` aber nicht, weil `unittest.main()` vorher läuft. Vorschlag: Klasse vor den Block
ziehen.

Geprüft und in Ordnung: WARDOGS (1867240) und FC 27 (4080220) mit Begründung und Quelle, kein Weg um die Sperre (keine
`arguments`), Benennung `EA anticheat` wie bei FC 25/26, `generated` neu, `mac.json` und `profiles.json` stimmen überein (Test).

## nx-compat-04

In Ordnung. `PEImports.nxCompat` liest nur die Köpfe und prüft das Magic; `withoutNXCompat` nur bei 32 Bit, höchstens 256 DLLs je
Ordner. Nightforges eigene Kopien neben dem Spiel (DXVK, ab `klassiker-bau-04` auch D7VK und DXVKs d3d8) tragen NX_COMPAT und
erscheinen nicht. Die Zeile im Log nennt nur Dateinamen. Am Start ändert sich nichts. `klassiker-bau-04` und dieser Zweig mergen
gegeneinander ohne Konflikt.

## Reihenfolge für die Fixes (Vorschlag)

1. SP1 (neu auf main), dabei SP2 und SP3.
2. DM1–DM3 mit Tests, DM4 mit.
3. OV1, dann OV2/OV3.
4. SS1, AC2 klein; AC1 beim Signieren.
