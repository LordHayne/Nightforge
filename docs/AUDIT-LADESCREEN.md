# Audit des Ladescreens (8.11.2026)

Zweig `claude/ladescreen-audit-2f71a4`, aufbauend auf `f30d255` (staging-032). Geprüft wurde alles zwischen dem Druck auf
„Spielen“ und dem Spiel im Vordergrund und zurück. Quellen: der Code, `wine.log` (12 399 Zeilen, 8.11. bis 14:02),
`wine.previous.log`, `console_log.txt` und `bootstrap_log.txt` beider Steams. Zeilennummern gelten für diesen Zweig.

## Kurzfassung

- **Der schwerste Fehler:** Der Vorhang hielt Wines schwarzes Schutzfenster für das Spielbild. Das erklärt das schwarze
  Overwatch von 13:40. Warum Wine das echte Fenster versteckt ließ, ist weiter offen.
- **Die Launcher-Wechsel** liefen 9 bis 27 s ohne Vorhang. Dabei blitzten Steam-Fenster auf, und ein Teil der Wartezeit
  hatte keinen Text.
- **Steams Frage:** Das Zeiger-Panel nahm Steam Helper die Tasten, und Steams Hauptfenster legte sich über Steams eigene
  Dialoge.
- 10 Korrekturen sind auf dem Zweig und getestet. Neues Aussehen gibt es nicht, deshalb kein Board. Was offen bleibt, steht
  unter „Für 0.3.3“.

## Wer was macht

| Teil | Aufgabe |
|---|---|
| `LibraryModel.launch` / `launchMac` / `launchGOGMac` | der Start, seine Phasen (`launchPhase`) und das Warten auf Steam |
| `raiseCurtain` → `watchCurtain` | Vorhang hoch, alle 0,5 s ein Blick, `curtainStep` entscheidet |
| `watchStage` / `GameStage` | ab dem gesunkenen Vorhang: Spiel bleibt erreichbar |
| `watchForGameEnd` → `comeBack` | Spielende: Vorhang „Zurück zu Nightforge …“, Nightforge nach vorn |
| `SteamSwitch` | welches Steam läuft: Windows-Steam ist der Ruhezustand |
| `GameBackdrop` | das Fenster: `.starting` / `.returning` (Vorhang), `.behind` (Seite hinter dem Spiel) |

Die Zustände des Vorhangs:

```
(aus) ─raise→ starting ─lower→ behind ─returning→ returning ─hide(once)→ (aus)
                │  ↑                ↑                 │
       hide/away│  │curtainUp       └──playing()──────┘  (ein Launcher übergibt doch noch)
                ↓  │
              (aus, Steam fragt)
```

## Tabelle: Launcher × Weg × Situation

„Log“ nennt, was die Logs vom 7./8.11. dazu zeigen; „–“ heißt, es gibt keinen Lauf dazu. Seit diesem Zweig kommt der
Vorhang bei beiden Steam-Wegen sofort beim Druck auf „Spielen“.

### Steam, Windows-Spiel (Wine)

| Situation | Soll | Code | Log |
|---|---|---|---|
| Kalt | Vorhang sofort, „Steam wird gestartet …“ | `launch:3514` Vorhang, dann `steamStartup`, `.startingSteam` | 13:37:56 Start, 13:38:08 `-applaunch` |
| Steam läuft | Vorhang, „Starten …“, 1 s nach dem Bild weg | Vorhang, `start()`, `curtainStep` | 37× „the game kept the front“ |
| Wechsel von Steam für Mac | Vorhang, Text zum Wechsel, kein Steam-Fenster | `makeWayForWindows`: Phasen `savingToCloud`, `signingIn`, `startingSteam`; `settle` jetzt mit Text | 13:37:45 Mac-Steam `exit` → 13:38:12 Spiel, **27 s** |
| Frage (`ShowEula`, `KickingOtherSession` …) | Vorhang weg, Steam-Fenster vorn | 3 s Fenster, 8 s `askPlayer`, `steamTurn` `.away`/`.back` | Wukong 1.11. (Notizen) |
| Fehler | Vorhang weg, Meldung | `wentWrong` → `hide` | – |
| Abbruch | Vorhang bleibt, kein Teil-Abbruch | B und jetzt auch Esc tun nichts; „Startet nicht?“ erst mit Prozess | L4D2 Quit über das Overlay |
| Spielende | sofort „Zurück zu Nightforge …“, dann Spielseite | `watchForGameEnd`, `comeBack` | sauber, 2× „the game ended“ |

### Steam für Mac

| Situation | Soll | Code | Log |
|---|---|---|---|
| Kalt | Vorhang sofort, „Steam für Mac wird gestartet …“ | `launchMac:2642`, `.startingSteamForMac`; Fenster unter dem Vorhang | 13:35:57 Start → 13:36:06 Spiel, **9 s** |
| Steam läuft | Vorhang, Spiel | Warteschleife, jetzt mit Text | 12:54:30 → 12:54:39 |
| Wechsel vom Windows-Steam | wie kalt | `makeWayForMac`, Windows-Steam geht nebenher | 13:36:00 Shutdown Windows, nebenher |
| Anmeldung läuft ab | Vorhang weg, Steam-Fenster vorn | `.signInAgain`/`.signInInSteamWindow` in `startAsksPlayer` (neu) | – |
| Frage | Vorhang weg, **die Frage** vorn, nicht der Store | `MacSteam.show`, `waitsInDialog` (neu) | Drawful 13:30: Panel, Store darüber |
| Fehler | Vorhang weg, Meldung oder Windows-Version | `fallBackToWindows`, `errorMessage` | – |
| Abbruch in der Frage | Vorhang bleibt weg, Steam-Fenster geht | `.over` versteckt das Fenster jetzt | – |
| Spielende | Vorhang, Steam bleibt unsichtbar, danach zurück zum Windows-Steam | `MacSteam.hide` (jetzt mit Helper), `afterMacGame` | 12:55: Steam Helper mehrfach vorn |

### Epic (Windows, ohne Launcher)

| Situation | Soll | Code | Log |
|---|---|---|---|
| Kalt | Vorhang, „Bei Epic anmelden …“ | Update und Spielstand **vor** dem Vorhang (Play-Knopf), `startDirect` | Control 13:3x sauber |
| Ausgeloggt | Anmelde-Bühne statt Start | `needsEpicSignIn` → `connectEpic`, kein Vorhang | – |
| Fehler | Vorhang weg, Meldung | `errorMessage` | – |
| Spielende | wie Steam, Spielstand danach hoch | `afterEpicSession` | – |

### GOG (Windows und Mac)

| Situation | Soll | Code | Log |
|---|---|---|---|
| Windows, kalt | Teile und Update zuerst, dann Vorhang | `beforeGOGStart` ohne Vorhang, `setUpGOG` unter dem Vorhang | Mafia II 31.10. |
| Mac | Vorhang, App startet | `launchGOGMac:562` | – |
| „Nicht alle Teile“ | Hinweis, Spiel startet trotzdem | `errorMessage`, und das nimmt den Vorhang weg (B5) | – |

### Battle.net

Spielen zeigt die Meldung „kann noch nicht aus Nightforge starten“, es gibt keinen Vorhang (`launch:3488`). Das Starten
ist 0.3.3 (`claude/battlenet-start-033`).

## Befunde

### Belegte Fehler, behoben (blockieren 0.3.2)

**A1 · Schwere 1 · Der Vorhang sank für einen schwarzen Bildschirm.**
`GameOverlay.swift:767` (`showsWindow`), `LibraryModel.swift:1513`.
Ablauf: Ein Spiel setzt den Anzeigemodus, Wine legt ein Schutzfenster (Ebene 2147483628) über den Schirm, das echte
Fenster des Spiels bleibt versteckt. `showsWindow` zählte das Schutzfenster als Bild.
Beleg: `wine.log:12221` zeigt beim schwarzen Lauf von 13:40 nur `1512×982 L2147483628, 7 hidden`, dazu `Overlay up` in
Zeile 12232 mit demselben Stand. In allen anderen Läufen liegt ein Fenster darüber: Overwatch `L…630` (Zeile 12325), ABZU
`L…630`, Control `L…629`. DXMT zeichnete derweil 57 FPS ins Leere.
Korrektur: Das Schutzfenster gilt nicht mehr als Bild. Die Stufe `bringBack` holt das Spiel nun bis zu zweimal zurück, und
der Vorhang sinkt nicht mehr für Schwarz. Bleibt es schwarz, kommt nach 60 s „Startet nicht?“ über dem Schutzfenster.
**Offen:** Warum Wine das Fenster versteckt ließ. Auffällig war nur das kleine `54×104`-Fenster davor. Ob das Zurückholen
wirkt, zeigt erst der Live-Test.

**A2 · Schwere 1 · Der Vorhang nahm fremden Apps die Tasten.**
`LibraryModel.swift:1467` (`pointerUnderCurtain`), `InputRouter.swift:707`.
Ablauf: Mit dem Pad zuletzt benutzt kommt Steam Helper nach vorn, und das Zeiger-Panel nimmt ihm 50 ms die Tasten.
Beleg: 28 Zeilen `Pointer: the sheer panel takes the keys from …` in `wine.log`, davon 11910 kurz bevor Steams Frage den
Vorhang wegnahm, 11985–11989 fünfmal auf dem Rückweg, dazu Claude, Chrome und Finder.
Korrektur: Das Panel läuft nur noch über dem Spiel selbst, solange es kein Bild zeigt. Preis: Mit dem Pad kann der Zeiger
sichtbar bleiben, solange Steam vorn ist.

**A3 · Schwere 1 · Der Steam-Wechsel lief ohne Vorhang.**
`LibraryModel.swift:2642` und `3514` (vorher kam `raiseCurtain` erst nach dem Wechsel).
Beleg: Mac → Windows dauerte 27 s (13:37:45 → 13:38:12), Windows → Mac 9 s (13:35:57 → 13:36:06), und `Curtain watch …
begins` steht im Log erst danach. Der Spieler sah in der Zeit nur den Play-Knopf, und Steams Fenster kam kurz hoch.
Korrektur: Der Vorhang kommt sofort. Damit er nichts verdeckt, was der Spieler braucht, nimmt `startAsksPlayer` ihn für
Anmeldung und Spielstand-Wahl weg.

**A4 · Schwere 2 · Steams Store legte sich über Steams Dialoge.**
`MacSteam.swift:269`, `296` (`waitsInDialog`).
Beleg: `console_log` von Steam für Mac: 13:30:57 und 13:31:03 `open/main` während der Frage. c475580 behob das nur für
`ShowLaunchOption`; dieselben Dialoge gab es als `ShowEula` (5×), `SynchronizingCloud` „syncfailed“ (6×) und „cloudconflict“
(1×), `KickingOtherSession` nur beim Windows-Steam (2×).
Korrektur: Für alle Fragen mit eigenem Fenster gilt dasselbe. `ShowInterstitials` und `CreatingProcess` bleiben wie gehabt.

**A5 · Schwere 2 · Wartezeit ohne Text beim Zurückwechseln.**
`SteamSwitch.swift:196`, `230`. `settle()` wartete bis zu 90 s auf den Wechsel zurück, ohne Phase.
Korrektur: Phase vor dem Warten; `launchMac` nennt auch das noch startende Steam.

**A6 · Schwere 3 · Der Vorhang folgte dem Anzeigemodus nicht.**
`GameBackdrop.swift:98` (`followScreen`), `GameDisplay.swift:113`.
Beleg: 7× `Screens changed under the curtain` bei 28× `Setting display mode`; die Größe setzte nur `put`. Das Overlay
brauchte denselben Fix am 4.11. (ABZU, 1920×1200).
Sichtbar nur, wenn kein Schutzfenster darüber liegt, vor allem auf dem Rückweg. Das mehrfache „Screens changed“ selbst ist
kein Fehler.

**A7 · Schwere 3 · Esc brach auf dem Vorhang nur Nightforges Warten ab.**
`InputRouter.swift:163`. Der Fall ist bei der Pad-Taste B seit 1.11. gelöst (`PadRules.swift:37`). Esc rief weiter
`cancelLaunch`, Steam startete das Spiel trotzdem, dann ohne Vorhang.

**A8 · Schwere 3 · Steams Fenster blieb nach einer abgebrochenen Frage offen.** `LibraryModel.swift:1023`.

**A9 · Schwere 3 · `MacSteam.hide` versteckte nur den Client.**
`MacSteam.swift:390`. Seit 616ecce ist bekannt, dass die Fenster Steam Helper gehören. Der Code ist eindeutig; wie stark
man es sah, ist Vermutung (Mac-Steam lief beim Audit nicht). Live-Punkt 6 prüft das.

**A10 · Schwere 4 · Log.** Die falsche Zeile „Curtain up again … macOS's question“ bei gesunkenem Vorhang (`wine.log:11967`)
ist weg. Neu: Uhrzeiten an Vorhang, Spielende und Steam-Wechsel. Bisher ließen sich Nightforges Zeilen nicht mit Steams
Zeiten verbinden.

### Belegt, nicht behoben (für 0.3.3)

**B1 · „Stage: Overwatch didn't come back“ (13:58).** Das Spiel war wohl gerade am Enden: `wine.log:12357` setzt erneut den
Anzeigemodus, in 12358 kommt Steams Wine-Prozess nach vorn, und Steam meldet das Ende um 13:58:50 mit Exit-Code 0, also
regulär. `GameStage` holt ein Spiel, dessen Fenster gerade verschwindet, dreimal zurück. Folge: kurzes Flackern am Spielende,
die Meldung ist irreführend. Ohne Uhrzeit in Nightforges Zeilen bleibt der Zusammenhang eine Vermutung; die neuen Zeilen
klären ihn.

**B2 · Kein Ausweg vom Vorhang, solange das Spiel keinen Prozess hat.** `LibraryModel.swift:1254` verlangt `!pids.isEmpty`,
B tut nichts. Bei einem hängenden Steam dauert das bis 120 s, bei einem Steam-Update unbegrenzt (`updating` zählt nicht).

**B3 · Steams Frage nimmt den Vorhang ganz weg**, die Seite blitzt auf. Schöner wäre die Frage auf dem Vorhang (`makeWay`),
aber das ändert das Aussehen und braucht ein Board.

**B4 · Epic und GOG: Update und Spielstand laufen vor dem Vorhang** (Play-Knopf, B bricht ab). Einheitlich wäre schöner,
kostet aber den Abbruch.

**B5 · Hinweise nehmen den Vorhang weg.** `wentWrong` (`LibraryModel.swift:1005`) unterscheidet nicht zwischen Fehler und
Hinweis („startet trotzdem“ bei GOG-Teilen und Spielständen).

**B6 · Text.** Zeigt der Vorhang schon ein Bild, springt „Warte auf das erste Bild …“ für 1 s auf „Starten …“ zurück
(`curtainStatus`).

### Vermutungen

- **V1:** Nach einem Mac-Spiel könnte Steam Helper die Front behalten, `hide(once:)` gibt nach 3 s auf und der Vorhang geht
  über Steam weg. Belegt ist das nicht, die Datenbasis ist aber klein: In den 9 Abläufen, nach denen Nightforge beendet wurde,
  war 7× Nightforge zuletzt vorn; die 2× Steam Helper waren Abbrüche an Steams Frage (Beenden über das Dock).
- **V2:** Wird `hide` von einem neuen `put` abgebrochen, geht „Willkommen zurück“ verloren.
- **V3:** Ob `NSRunningApplication.hide` bei Steam Helper (ohne Dock-Symbol) wirkt, ist ungetestet. Wirkt es nicht, bleibt
  alles wie vorher.

## Was blockiert 0.3.2

| Punkt | Stand |
|---|---|
| A1–A5 | behoben, getestet, Live-Prüfung nötig |
| A6–A10 | behoben, gering, gehen mit |
| B1–B6, V1–V3 | 0.3.3 |

Einordnung im Funktionsstopp: Alle Punkte sind Fehler aus den Live-Tests vom 7./8.11. oder dieselbe Klasse. Die größte
Verhaltensänderung ist A3, weil der Vorhang früher kommt.

## Tests

Neu in `tests/GameOverlayTest`: Schutzfenster gegen Bild, `curtainStep` mit `shieldOnly`, `pointerUnderCurtain`,
`startAsksPlayer`, `waitsInDialog`, `shouldFollow`.

Grün mit `scripts/run-tests.sh -P 2`: GameOverlayTest, GameStageTest, StageTest, SteamSwitchTest, PadRulesTest,
GameTestTest, LaunchHealthTest, MacVersionTest, LauncherMenuTest, GameDisplayTest, GameResolutionTest, UnityDialogTest,
SteamStopTest, SteamBackgroundTest, GameMenuTest. Die volle Reihe (66) steht vor dem Release noch aus. `./build.sh` läuft durch.
Die Änderungen an Vorhang und Steam-Fenstern selbst sind nur live prüfbar: Nichts davon wurde an einem echten Spiel getestet.

## Live-Prüfung (der Nutzer, Build vom Koordinator)

Nach jedem Punkt die neuen Zeilen in `wine.log` ansehen. Fragen an Steam nur mit der Maus beantworten.

1. **Overwatch, 3× starten.** Erwartet: Bild oder, falls schwarz, nach etwa 4 und 8 s `Curtain: … fetching it back` und nach
   60 s „Startet nicht?“. Kein `Curtain down` bei nur `L2147483628`.
2. **Wechsel hin und her:** Valheim (Mac) starten, nach einer Minute beenden, sofort L4D2 oder Overwatch (Windows), beenden,
   wieder Valheim. Erwartet: Vorhang sofort beim Druck auf „Spielen“, passender Text, kein Steam-Fenster sichtbar. Im Log
   `Steam switch: …` mit Uhrzeit.
3. **Drawful 2 mit eigenem Startparameter** (`-condebug`): Vorhang geht, die Frage nach der Startoption ist anklickbar und
   nicht vom Store verdeckt. Im Log kein `Pointer: … Steam Helper`.
4. **In Steams Frage Abbrechen wählen:** Steams Fenster verschwindet, Nightforge bleibt ohne Vorhang.
5. **Esc auf dem Vorhang:** Nichts passiert, der Start läuft weiter.
6. **Ende eines Mac-Spiels:** Nach „Zurück zu Nightforge …“ steht kein Steam-Fenster mehr da, auch nicht hinter Nightforge
   (⌘-Tab, Fenster ansehen).
7. **ABZU oder Control (ändern die Auflösung):** Vorhang und Rückweg decken den ganzen Schirm, im Log `The page follows the
   screen`.
8. **Wenn es sich ergibt:** Steam-Anmeldung abgelaufen (Vorhang weg, Fenster vorn) und Spielstand-Wahl beim
   Versionswechsel (Sheet sichtbar).
9. **Rückblick Einrichtung:** „Steam-Fenster wieder zeigen“ in der Mac-Steam-Einrichtung zeigt das Fenster weiter (wegen A9).
