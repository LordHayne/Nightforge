# Audit des 0.3.3-Testbuilds (8.11.2026)

Geprüft: `claude/staging-033` bei `365f393`, elf zusammengeführte Zweige, 169 Dateien. Schwerpunkt war, was erst im
Zusammenspiel schiefgehen kann. Alles ist aus dem Code belegt; **Vermutung** steht dabei, wo nur ein Live-Test es
klären kann. Zeilennummern gelten für `365f393`. Keine Nightforge-GUI, keine Spiele, Tests höchstens `-P 2`.

## Ergebnis

- **Sechs Fehler behoben**, je mit Test, jeder auf einem eigenen Zweig (B1 bis B6).
- **Blockiert 0.3.3:** Nach dem Merge muss die Profilliste signiert werden (`scripts/sign-lists.sh main`), siehe B4.
- **Beim Merge von `claude/ruhiger-ladescreen-033` beachten:** Battle.net landet sonst im „Steam fragt“-Vorhang (O1).
- Die drei von Hand gelösten Konflikte sind in Ordnung (Abschnitt „Geprüft, in Ordnung“).

## Behobene Fehler

| Nr. | Schwere | Fehler | Datei | Zweig, Commit | Ursprung |
|---|---|---|---|---|---|
| B1 | hoch | Zweiter Controller verhindert das Overlay | `InputRouter.swift:577` | `claude/audit-033-overlay-zwei-pads` 98d9ac1 | main |
| B2 | mittel | Aufgewecktes Steam meldet Steam für Mac ab, startet unter Spielen | `SteamOnDemand.swift:136` | `claude/audit-033-steam-bei-bedarf` 36ef977 | `claude/steam-on-demand-033` |
| B3 | mittel | Battle.net-Fenster verschwindet unter seiner eigenen Fehlermeldung | `LibraryModel.swift:1708` | `claude/audit-033-battlenet-fenster` 202b21b | `claude/battlenet-start-033` |
| B4 | hoch | Overwatch verliert die D3DMetal-Frage | `profiles/profiles.json:5919` | `claude/audit-033-listen-stempel` df9a1cf | `claude/audit-033` |
| B5 | mittel | Halber oder pausierter Download hält den Mac wach | `LibraryModel.swift:2183` | `claude/audit-033-wachhalten` 5a2369b, ee63ab8 | main |
| B6 | niedrig | Nach B auf dem Vorhang geht noch ein Startbefehl an Steam | `LibraryModel.swift:3322`, `:3328` | `claude/audit-033-nachsenden` fae0667 | main |

Zweige für Code, den es auf `origin/main` noch nicht gibt, beginnen an der Spitze ihres Ursprungszweigs; von `origin/main`
aus gäbe es die Stellen nicht. B1, B5 und B6 beginnen an `origin/main`.

### B1 · Zweiter Controller verhindert das Overlay

`watchHold` läuft bei jedem Ereignis jedes Controllers, `overlayHold` gibt es aber nur einmal. Hält Spieler 1 beide Sticks,
setzt jedes Ereignis von Spieler 2 mit `pressed == false` die Zeit zurück (`OverlayHold.update`). Im Spiel zu zweit erreicht
der Griff die zwei Sekunden daher nicht, und der Controller hat keinen anderen Weg aus dem Spiel. Der Fix fragt während eines
laufenden Griffs alle Controller ab, sonst nur den meldenden (das Ereignis kommt hunderte Male pro Sekunde).

Beim Merge in Staging gibt es einen kleinen Konflikt in `watchHold`: Die neue Zeile `let pressed = …` und `let held = …` bleiben
beide stehen. Außerdem sollte `feel(.overlayOpens, on: pad.controller)` danach den haltenden Controller meinen; jetzt kann der
Abschluss-Tipp am anderen Controller ankommen (niedrig).

### B2 · Aufgewecktes Steam gegen Steam für Mac

`startSteamAgain` prüfte nur `!macSteamBusy`. Der Start beim Öffnen von Nightforge (`startBackgroundSteam`) beendet dagegen
zuerst ein von Nightforge gestartetes Steam für Mac, und `SteamSwitch` sagt ausdrücklich „Never while the other side plays,
starts or uploads a save“. Drei Folgen:

- Nach einem Mac-Spiel oder während eines Mac-Downloads meldete das aufgeweckte Windows-Steam Steam für Mac ab. Cloud-Upload oder Download brachen ab.
- Am Netzteil startete es unter einem laufenden Epic-, GOG- oder Mac-Spiel (ein Steam-Start braucht 3 Kerne und mehr).
- Kam der Spieler genau während `await SteamWindow.isOpen()` zurück, stand ein Stopp hinter dem Aufwecken.

Jetzt: Steam für Mac beendet zuerst, ein Mac-Spiel oder -Download lässt Steam weiter schlafen, ein Windows-Spielstart geht vor.

### B3 · Battle.net-Fenster

Nach einer Frage (`steamAsked`) endet der Vorhang mit `.over`, und `hideSteamWindow` versteckt den Client. Das geschah eine
halbe Sekunde, nachdem `sayBattleNetFailed` ihn nach vorn geholt hatte, unter dem Text „Press Play in its window“. `.noAnswer` traf das
immer, denn dieser Fall folgt stets auf eine Frage. Jetzt bleibt das Fenster, wenn eine Meldung steht.

### B4 · Listen-Stempel (mein eigener Fehler aus der vorigen Runde)

Das Feld `needsRosettaLibrary` kam von Hand in `profiles.json`, der Stempel `generated` blieb gleich. Bei gleichem Stempel gewinnt die behaltene Liste
(`ProfileStore.loadLocalIfNeeded`, `SignedLists.isOlder`). Wer schon eine signierte Liste hat, also jeder von 0.3.2 kommende Spieler,
bekam das Feld nicht, und die feste Liste im Code ist weg. Overwatch hätte ohne D3DMetal also wieder ohne Frage gehangen.
`build-profiles.py` hätte den Stempel auch nicht bewegt. Jetzt ist der Stempel `2026-11-08T20:00:00Z`.

**Bleibt nötig:** `scripts/sign-lists.sh main` gleich nach dem Merge. `profiles.json` auf Staging hat die Prüfsumme `b8a90b44…`, signiert ist `7e1271b4…`
(Commit 55b89b5). Bis dahin lehnt jede laufende Kopie, 0.3.2 eingeschlossen, die Online-Liste ab und behält ihre. Nur diese eine Liste ist betroffen;
`components/manifest.json` und `agw.json` sind unverändert. Das Signieren braucht den Schlüssel des Nutzers.

### B5 · Wachhalten

`KeepAwake` zählte jeden Download nach den Dateien seines Stores (`flags & 4 == 0`, bei Battle.net die Operation in `product.db`). Ein halber
Download ohne laufendes Steam hielt den Mac wach, solange Nightforge offen ist; mit Start beim Anmelden wäre das den ganzen Tag.
Das widerspricht „hält den Mac nie vom Schlafen ab“. Jetzt zählt er nur, wenn der zuständige Client läuft.

**Pausiert (Entscheidung des Nutzers, 8.11.):** „Pausieren heißt, er darf schlafen“, ohne Frist. Steams Pausen-Markierung (`StateFlags` 512, im Log `0x602`
„Update Required,Update Paused,Update Started“) kommt jetzt in `Game.downloadPaused`, und so ein Download zählt nicht mehr. Pause und Weiterladen lösen sofort einen
vollen Scan aus, das Wachhalten folgt also gleich. Ein laufender Download, den Steam nur nicht bedient (in der Warteschlange), zählt weiter.

### B6 · Nachsenden nach B

`waitForMacStart` prüft den Abbruch am Schleifenanfang, danach kommen aber zwei Wartestellen vor dem `send()`. Ging der Spieler dort über den Vorhang zurück, kam
der Befehl trotzdem an. Bei `-applaunch`-Spielen geht das Nachsenden über `steam://run`, Steam könnte also die Startoption fragen, ohne dass jemand da ist.

## Für offene Zweige (nicht doppelt gebaut)

| Nr. | Schwere | Punkt | Zweig |
|---|---|---|---|
| O1 | mittel | „Steam fragt“-Vorhang gilt auch für Battle.net | `claude/ruhiger-ladescreen-033`, 6d8d789 |
| O2 | niedrig | Anmeldeobjekt bleibt nach „Nightforge komplett entfernen“ | `claude/touchpad-tastatur-033` |
| O3 | niedrig | Zeiger über einem Mac-Spiel bei offenem Overlay | `claude/touchpad-tastatur-033` |
| O4 | niedrig | Stick-Zeiger hat keinen Besitzer, Abgang eines Controllers lässt alles los | `claude/touchpad-tastatur-033` |
| O5 | niedrig | Pausierter Download versteckt weiter „Mac schlafen legen“ | `claude/touchpad-tastatur-033` |

**O1.** Mit 6d8d789 bleibt der Vorhang bei `.battleNetAsks` stehen (`steamAsksOnCurtain` kennt nur die Spielstand-Wahl). Dann sucht
`steamWindowsOnScreen` die Fenster von Steam für Mac, nicht die von Battle.net. Acht Sekunden steht „Steam fragt etwas“ über dem Battle.net-Fenster; läuft Steam für Mac
sichtbar, legt sich der Vorhang sogar unter dessen Fenster. Vorschlag: `steamAsksOnCurtain(savesToChoose: saveChoice != nil || game.provider == .battlenet)`, dann geht der Vorhang wie heute.

**O2.** `CompleteRemoval` meldet `SMAppService.mainApp` nicht ab. Ein Aufruf von `unregister()` vor dem Löschen reicht. **Vermutung:** macOS räumt den Eintrag später selbst auf.

**O3.** `PadPointerRules.works` lässt den Zeiger bei offenem Overlay zu. Windows-Spiele sind dabei angehalten, Mac-Spiele nicht (`pauses = platform == .windows`). Die Bewegung erreicht dort das Spiel (mit Bedienungshilfen-Recht).

**O4.** Zwei Controller ohne Touchpad teilen `stickVelocity` und `heldTriggers`; ein ruhender zweiter Stick kann die Bewegung kurz stoppen. `controllerLeft` lässt auch den Klick des verbliebenen Controllers los. Beides nur kurz störend.

**O5.** `LauncherViews.swift:195` (7729450) übergibt `downloading: !model.downloads.isEmpty`. Nach der Entscheidung zu B5 gehört dort `model.downloads.contains { !$0.downloadPaused }` hin, sobald beide Zweige zusammen sind.

## Weitere Beobachtungen

| Schwere | Punkt | Beleg |
|---|---|---|
| entschieden | Frühes Shader-Übersetzen ist standardmäßig an, ausgenommen nur `overwatch.exe`; Spiele mit `antiCheatOnline` werden wie Overwatch ausgenommen (Nutzer, 8.11.), das baut die Shader-Session | `ShaderCaches.swift:30`. Wirkt erst mit gepatchter `d3d11.dll` |
| niedrig | Esc auf dem Vorhang wirkt nur, wenn Nightforge aktiv ist (lokaler Monitor), der Hinweis sagt es aber auch mit Steam vorn. **Vermutung**, siehe „Live prüfen“ | `InputRouter.swift:53`, `CurtainEscape.tip` |
| niedrig | `anyDown` in `wakeIfIdle` wird wie B1 von jedem Controller überschrieben: ein gehaltener Knopf kann als neuer Druck zählen | `InputRouter.swift:719` |
| niedrig | `LogFollower` beginnt nach `send`, eine sehr schnelle Ablehnung würde übersehen | `LibraryModel.swift:615`, `:673` |
| niedrig | TV-Wechsel baut die ganze Oberfläche neu (`.id`), offene Blätter gehen zu | `App.swift:24` |
| niedrig | R2/L2 lesen im Spiel bei Pads ohne Touchpad bei jedem Druck die Fensterliste | `PadPointer.trigger`, `pointerWorks` |

## Geprüft, in Ordnung

- **Konflikte von Hand:** `refreshBattery` meldet Änderungen und setzt Spielernummern richtig. `startAsksPlayer` enthält `.battleNetAsks`. Die Abbruchprüfung vor `raiseCurtain` in `launchMac` sitzt richtig.
- **`-applaunch`:** `SteamCommands.isLaunch` erkennt die Zeile, auch mit Argumenten. `MacSteam.applaunch` startet kein eigenes Steam. Vor der Übergabe wird der Abbruch geprüft.
- **Vorhang und Steam nur bei Bedarf:** Ein Windows-Start weckt und wartet in `steamStartup`, auch hinter einem laufenden Stopp. Der Vorhang steht schon und sagt „Steam startet“.
- **Autostart und Wachhalten:** Staging hält den Mac nur für Downloads und Spieletests wach. `DisplayWake` meldet nur bei schlafendem Bildschirm und frischem Knopfdruck Nutzung an. `IdleAwake` (d9c9b9f, noch nicht auf Staging) ist standardmäßig aus, nur am Netzteil und zeitlich begrenzt.
- **Tastatur:** G1 (26b3a2c, noch nicht auf Staging) sperrt Zeiger, Stick, Trigger und Menüknöpfe, solange sie offen ist, auch für den zweiten Controller. Auf Staging selbst gibt es noch keine Tastatur.
- **Touchpad bei zwei Controllern:** `owner` hält den zweiten Finger sauber fern.
- **Battle.net-Fragen:** Client geht vor dem Vorhang weg, kommt für Fragen zurück, und der Weg über B bricht das Nachsenden ab.

## Entscheidungen des Nutzers (8.11.)

1. Frühes Shader-Übersetzen: Spiele mit `antiCheatOnline` werden ausgenommen wie Overwatch. Baut die Shader-Session.
2. Ein in Steam pausierter Download hält den Mac gar nicht wach, ohne Frist. Gebaut in ee63ab8 (B5).

## Live prüfen

1. Zwei Controller im Spiel: Spieler 1 hält L3+R3, Spieler 2 bewegt den Stick, das Overlay kommt nach 2 s.
2. Akku, Steam schläft, Mac-Download läuft: zurück zu Nightforge, Steam für Mac bleibt angemeldet.
3. Am Netzteil einstecken während eines Epic-Spiels: Steam startet erst nach dem Spiel (`Steam wakes` im `wine.log`).
4. Battle.net: Start ohne Antwort oder mit Ablehnung, das Client-Fenster bleibt unter der Meldung offen.
5. Overwatch ohne D3DMetal, mit vorhandener alter Liste: Die Frage kommt.
6. Mac schlafen lassen mit halbem Download und beendetem Steam, und mit in Steam pausiertem Download: Er schläft beide Male ein (`pmset -g assertions` zeigt Nightforge nicht mehr).
7. Spiel mit mehreren Startoptionen: während des Wartens B und zurück, Steam fragt nicht mehr nach.
8. Ohne Controller, Steam vorn unter dem Vorhang: Führt Esc hinaus?
