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

## Wachhalten beim Download (Nachtrag 8.11., 23:40)

Geprüft auf `claude/staging-033` bei 8870ae2, dazu `pmset -g assertions`, `pmset -g log` (ab 1.11.) und die `content_log.txt` beider Steams. Nur gelesen, kein Steam gestartet oder beendet.

**Für heute Nacht:** Am Netzteil und mit offenem Deckel ist nichts nötig. Mit geschlossenem Deckel schläft das MacBook ein. Dieses MacBook hat am Netzteil `sleep 0`, schläft also ohnehin nicht von selbst ein; auf Akku `sleep 1`. Das Wachbleiben heute Nacht beweist darum nichts über Nightforge, auch wegen der Assertion des Claude-Programms.

| Nr. | Schwere | Fehler | Datei | Commit |
|---|---|---|---|---|
| W1 | mittel | Beim Wechsel der beiden Steams war das Wachhalten 1:28 min weg (mein Fehler aus 5a2369b) | `Downloads.swift` | 9bc8220 |
| W2 | mittel | Mac-Version neben installierter Windows-Version zählte nie als Download | `Downloads.swift`, `Library.swift` | 9bc8220 |
| W3 | mittel | Nach dem Beenden von Nightforge lief der Download weiter, aber ohne Wachhalten | `Engine.swift` (Beenden-Skript) | d45d6c3 |

Zweig: `claude/wachhalten-download-033` von `claude/staging-033`. `DownloadRateTest`, `QuitScriptTest`, `UpdateStateTest` grün (`-P 2`). Der laufende Nightforge hat das noch nicht, das braucht einen neuen Build.

### 1 · Warteschlange

Zwischen zwei Spielen entsteht keine Lücke. Jedes Spiel der Warteschlange hat schon sein Manifest ohne das Bit „fertig“ (jetzt `StateFlags 1026`, in Steams Log `0x40a` für „Update Queued“) und zählt damit. Beleg: Um 23:33 ging GTA V aus, Steam startete neu (23:33:09 bis :16, Ursache nicht im Log), 228980 und It Takes Two liefen an. Die Assertion lief durch, seit 22:29:13 am Stück.

Die echte Lücke lag woanders: 22:27:13 machte das Windows-Steam Platz für Steam für Mac, und 22:27:45 bis 22:29:13 gab es keine Assertion, weil der Scan „Steam läuft nicht“ sah. Auf Akku hätte der Mac dort einschlafen können. Jetzt hat ein Store, der gerade geladen hat, 5 Minuten Zeit zurückzukommen (W1). Eine Pause bekommt keine Frist, und ist nichts mehr zu laden, endet das Wachhalten sofort.

### 2 · Je Store

| Store | Zählt, wenn | Läuft, zählt aber nicht | Zählt, läuft aber nicht |
|---|---|---|---|
| Steam (Windows) | Manifest nicht fertig, nicht pausiert, `steam.exe` läuft | Updates installierter Spiele (`flags & 4`), passt zu „Updates beim nächsten Aufwachen“ (`docs/TODO.md`) | Steam läuft, lädt aber nichts (abgemeldet, kein Netz): kein Bit, keine Grenze |
| Steam für Mac | wie oben, `steam_osx` läuft | war: Mac-Version neben Windows-Version (W2) | wie oben |
| Epic | Auftrag läuft | Update beim Spielstart | keins bekannt |
| GOG | Auftrag läuft | Update beim Spielstart | keins bekannt |
| Battle.net | Operation „update“, Spiel nicht installiert, Mac-Client läuft | Update installierter Spiele; Windows-Client; **Vermutung:** der Agent lädt bei geschlossenem Client weiter | keins bekannt |

**Pausiert erkennen:** `StateFlags 512` ist auf diesem Mac nur für Steams eigene Pause bei vollem Speicher belegt (26.10., `0x602`). Ob der Knopf „Pause“ in Steam das Bit auch setzt, ist **nicht belegt** und muss live geprüft werden.

### 3 · Ende von Nightforge

Steam bleibt oben: Das Beenden-Skript wartet auf laufende Downloads, höchstens 12 h. Wach blieb der Mac dabei nicht, denn die Assertion stirbt mit Nightforge (`ClientDied` 12:36:35 und 22:25:25; beim ersten Mal 17:29 min ohne, ohne Schaden nur wegen `sleep 0`). Das Skript hält den Mac jetzt selbst wach (`caffeinate -i -w`), nur solange ein Download der Grund ist (W3). „Steam nur bei Bedarf“ stoppt ein ladendes Steam nicht.

**Offen:** Epic und GOG laden als eigener Prozess (`DetachedProcess`) weiter, das Skript kennt sie nicht, sie haben nach dem Beenden kein Wachhalten.

### 4 · Deckel zu

Dagegen hilft nichts, was eine App ohne Admin-Recht tun darf. Apples Header zu dieser Assertion: „The system may still sleep for lid close“ (`IOPMLib.h`); die stärkere Art `PreventSystemSleep` ist dort als nicht mehr unterstützt markiert. `pmset disablesleep` bräuchte Admin-Rechte und ändert eine Systemeinstellung, das soll Nightforge nicht tun. Zugeklappt läuft ein MacBook nur mit externem Bildschirm, Netzteil und Tastatur oder Maus weiter. Im Log: 12 „Clamshell Sleep“ seit 1.11., 3 davon am Netzteil.

Nightforge sollte es sagen, statt es zu versprechen. Vorschlag für die Downloads, nur am MacBook ohne externen Bildschirm: „Lass den Deckel offen, bis der Download fertig ist. Der Bildschirm darf ausgehen.“ Aussehen und Ort gehören aufs Board (Design first).

### 5 · Akku, Hitze, nach dem Ende

- **Akku:** Das Wachhalten gilt auch auf Akku, bis macOS wegen niedrigem Stand schläft. `IdleAwake` gilt dagegen nie auf Akku.
- **Hitze:** Keine Warnung (`pmset -g therm`, nach über einer Stunde Download). Mehr wurde nicht gemessen.
- **Nach dem Ende:** Nichts bleibt zurück: Die Assertion geht beim Scan nach dem letzten Download (Beleg 13:09:59). Mit W1 bleibt sie nur, solange noch ein Download gelistet ist.
- **Mac mini als Konsole:** Passt, solange etwas lädt. `IdleAwake` ist getrennt, standardmäßig aus, und zählt ab der letzten Eingabe. Die eine Ausnahme ist ein toter Download ohne Pausen-Bit (Tabelle oben): Der hält wach, solange Nightforge offen ist.

### 6 · `pmset -g log`

Seit 1.11.: 442 Mal Schlaf (251 „Sleep Service Back to Sleep“, 177 „Maintenance Sleep“, 12 Deckel, 2 Idle, beide auf Akku). In den sechs Download-Zeiträumen und bis 3 min danach: keiner. Von den Steam-Läufen in beiden `content_log.txt` überspannte keiner einen Schlaf. Ein abgerissener Download ist damit nicht belegt. Das beweist aber wenig, denn am Netzteil ist hier kein Idle-Schlaf eingestellt und das Log beginnt erst am 1.11.

### 7 · Was die Oberfläche sagen sollte (nur Vorschlag, nichts gebaut)

Der Nutzer hielt den Mac für eingeschlafen, dabei war nur der Bildschirm aus. Der gewünschte Satz steht schon seit 27.10. in den Downloads (`Downloads.swift:177`: „Dein Mac bleibt wach, solange Spiele laden. Der Bildschirm darf trotzdem ausgehen.“). Er hilft nur nicht, aus zwei Gründen:

- **Er steht am falschen Ort.** Das Feld öffnet sich nur auf Klick, der schwarze Bildschirm kommt später und ohne Zusammenhang. Während er aus ist, kann Nightforge nichts anzeigen; sagen lässt es sich nur vorher oder danach.
- **Er stimmt nicht immer.** Er steht bei jedem gelisteten Download, seit 5a2369b und ee63ab8 also auch, wenn der Mac schlafen darf (alles pausiert, Store beendet). Und er verschweigt den Deckel.

| Stufe | Was | Wann |
|---|---|---|
| A | Satz nach dem echten Zustand: „Dein Mac bleibt wach, solange Spiele laden. Der Bildschirm darf ausgehen.“ Am MacBook ohne externen Bildschirm dazu: „Lass den Deckel offen.“ Alles pausiert: „Pausiert: Der Mac darf schlafen.“ Steam beendet: „Steam läuft nicht, der Download steht.“ | im Feld „Downloads“ |
| B | Derselbe Satz einmal als kurze Meldung, wenn ein Download beginnt und jemand hinschaut | beim ersten Download der Sitzung |
| C | Beim Zurückkommen der Beweis: „Der Download lief weiter: 12 GB, während der Bildschirm aus war.“ | wenn der Bildschirm wieder angeht und in der Zeit geladen wurde |

**Empfehlung: A und C.** A macht den Satz wahr, C beantwortet genau die Frage, die sich beim schwarzen Bildschirm stellt. B fällt weg, wenn C da ist, denn beim Spielstart stört jede Meldung mehr. Den Bildschirm anzulassen ist keine Lösung: Das kostet Strom und widerspricht „der Bildschirm darf ausgehen“.

Für A braucht die Oberfläche `KeepAwake`s Zustand (heute privat), für C `NSWorkspace.screensDidSleepNotification` und die Summe aus `downloadRates`. Aussehen und Ort gehören aufs Board (Design first).

### Fragen an den Nutzer

1. Auf Akku wachhalten: wie heute bis macOS abschaltet, oder ab 20 % nicht mehr, oder gar nicht?
2. Ein Download ohne jeden Fortschritt: nach 30 min nicht mehr wachhalten? Das bräuchte Nightforges gemessene Geschwindigkeit, denn Steam schreibt seine Zahlen nur selten.
3. Epic und GOG nach dem Beenden: sollen sie den Mac auch wachhalten?
4. Die Hinweise aus Abschnitt 7: nur A, A und C, oder alle drei? Dafür ein Board?

### Live prüfen

1. Download läuft, Nightforge beenden: `pmset -g assertions` zeigt `caffeinate`, nach dem Ende nicht mehr.
2. Windows-Download läuft, Mac-Spiel starten: Die Nightforge-Assertion bleibt durchgehend.
3. In Steam „Pause“ drücken: Im Manifest steht `StateFlags` mit Bit 512, die Assertion geht.
4. Mac-Version neben installierter Windows-Version laden: Assertion da.

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

## Gesamtprüfung vor dem Release (9.11.)

Geprüft: `claude/staging-033` bei `1e6ed95` gegen `origin/main` (`2276ccb`, 0.3.2), 189 Commits, 263 Dateien. Das lokale `main` steht auf `785c65d` (26.10.) und taugt nicht zum Vergleich. Nur Code, Logs von GitHub und Dateien gelesen; keine Nightforge-GUI, kein Spiel, kein Push. Zeilennummern gelten für diesen Zweig. **Vermutung** steht, wo nur ein Live-Test es klären kann.

### Ergebnis

- **Vier Fehler behoben**, je ein Commit mit Test (G1 bis G4, Zweig `claude/audit-033-gesamt`).
- **Blockiert das Release:** `profiles/profiles.json` ist nicht signiert (`scripts/check-signatures.sh`: „the signature doesn't hold“). Dazu fehlen `docs/release-notes/v0.3.3.md` und `wrapper/pad-answer.exe`. Reihenfolge unten.
- **Vor dem Merge zu entscheiden:** E1 und E2. Der Merge veröffentlicht von selbst zwei neue Pakete.
- `claude/staging-033` liegt nicht auf GitHub. **CI ist auf diesem Stand noch nie gelaufen**, die Tests liefen nur auf diesem Mac.

| Nr. | Schwere | Fehler | Datei | Commit | Seit |
|---|---|---|---|---|---|
| G1 | mittel | Pad und Tasten erreichen, was unter dem Vorhang liegt | `InputRouter.swift:148` | 2ae8990 | 0.3.2, in 0.3.3 schlimmer durch die Tastatur |
| G2 | niedrig | Fenster über dem Spiel bleibt nach dem Spiel gemerkt, und das Overlay schützt nicht vor der Übergabe | `LibraryModel.swift:1773`, `:2188` | 99cbae7 | 0.3.3 |
| G3 | mittel | Battle.net-Frage steht als „Steam fragt etwas“ auf dem Vorhang (O1 von oben, war noch offen) | `LibraryModel.swift:1442` | 38b063a | 0.3.3 |
| G4 | niedrig | „Mac schlafen legen“ fehlt bei pausiertem Download (O5 von oben, war noch offen) | `LauncherViews.swift:195` | 0d186de | 0.3.3 |

**G1.** Nightforge bleibt unter dem Vorhang oft die aktive App, bis das Spiel die Front nimmt (`raiseCurtain`: „Nightforge in front still“). Das sind die ersten Sekunden, bei einem Steam-Update Minuten. `reach` war dann `.app`. Nur B und Esc kannten den Vorhang (`PadRules.back`). Y öffnete die Tastatur und wechselte zur Bibliothek, X und L1/R1 änderten die Seite, ☰ öffnete Optionen, A drückte den markierten Knopf, das Steuerkreuz verschob die Auswahl, ⌘⌫ fragte unsichtbar nach dem Entfernen. Jetzt gilt für all das `PadRules.curtainCovers`. Das Overlay über dem Vorhang behält das Pad. A und B für die Frage eines Windows-Spiels gehen weiter vor.

**G2.** `overGame` wurde nur in `watchStage` gesetzt und blieb am Ende stehen. Stand beim Spielende ein kleines Steam-Fenster über dem Spiel, bekam Steam beim nächsten Fingerauflegen die Front, mit dem Spieler schon in Nightforge. Unter offenem Overlay gab `reachWindowOverGame` die Front ebenfalls ab, obwohl die Bühnenwache dort stillhält (`handsOff`).

**Tests:** Alle Reihen außer `DetachedProcessTest` (wartet in Checkouts unter `~/Downloads` auf eine macOS-Frage), `-P 2`, 107 von 108 grün. `EpicTest` scheiterte an einer festen Wartezeit von 300 ms (ein von drei Läufen); keine dieser Änderungen berührt Epic; behoben in a67799a, danach 6 von 6 grün. Die Python-Tests liefen nicht, keine dieser Änderungen betrifft sie. Im echten Programm ist nichts davon gesehen.

### 1 · Wer nimmt wem was weg

| Paar | Ergebnis | Beleg |
|---|---|---|
| Vorhang, Steams Lizenz | Hält. Vorhang liegt unter Steams hinterstem Fenster, das Nach-vorn-Holen stoppt dann | `LibraryModel.swift:1469`, `GameBackdrop.swift:432` |
| Lizenz, Zeiger | Hält. Nur verschoben, kein Klick, nur wenn das Pad zuletzt benutzt wurde. Die durchsichtige Tastenfläche kommt nicht, die Schleife endet vorher mit `continue` | `InputRouter.swift:935`, `LibraryModel.swift:1480` |
| Lizenz, Zeiger-Parken | Hält. Parken nur ohne Vorhang | `InputRouter.swift:827` |
| Lizenz, B | Hält. B führt hinaus, Steam fragt beim nächsten Start wieder | `LibraryModel.swift:1251` |
| Lizenz, Tastatur | War offen: G1 | |
| Overlay, Vorhang | Hält. Overlay liegt immer über dem Vorhang | `GameOverlay.swift:225`, `GameBackdrop.swift:448` |
| Overlay, Tasten des Spiels | Hält. Nimmt die Tasten nur ohne Bild („Startet nicht?“, Ausweg) | `GameOverlay.swift` `takesKeys` |
| Overlay, Steam-Fenster | War offen: G2 | |
| Touchpad, Tastatur | Hält. Bei offener Tastatur tippt das Touchpad, es zeigt nicht | `TouchpadPointer.swift` `works` |
| Touchpad, Parken | Hält. 3 s nach der letzten Berührung wird nicht geparkt | `PadPointer.touchedRecently` |
| Parken, Steam-Fenster | Hält. Solange ein Fenster über dem Spiel steht, wird nicht geparkt | `InputRouter.swift:830` |
| Tastatur, Overlay-Griff | Hält. Sobald das Overlay das Pad hat, schließt die Tastatur | `InputRouter.swift:694` |

Offen, alle niedrig:

- **N1, Fokuswache:** Erscheint ein großes Fremdfenster in den ersten 8 s nach dem Vorhang, gibt die Bühnenwache ihm die Front, und `watchCurtain` holt sie dem Spiel zurück (`.raiseAgain`). Danach liegt das Fenster hinter dem Spiel. Aus dem Code abgeleitet, nicht beobachtet.
- **N2, Pad ohne Touchpad:** Ein kleines Fenster über dem Spiel bekommt die Front nur per Finger (`pointer.works`). Der Stick fragt `stickIsPointer` und ruft die Übergabe nie auf.
- **N3, zwei Pads:** Die Leiste der Lizenz sagt „Touchpad“, sobald irgendein Pad eins hat, auch wenn das andere in der Hand liegt (`LibraryModel.swift:1347`).
- **N4, spätes Lizenz-Wort:** Kommt `.licence` erst, nachdem Steam schon allgemein gefragt hat, bleibt die Leiste „Steam fragt etwas“ ohne Rahmen (`LibraryModel.swift:1444` wird nur einmal erreicht). Der Start läuft normal weiter.
- **O2, O3, O4** von oben: behoben, siehe „Nachtrag: die kleinen Befunde“. N2 bis N4 ebenso, N1 bleibt offen.

### 2 · Download-Hinweise mit Wachhalten, Pause, Spielstart, Steam nur bei Bedarf

- **Hält:** „Mac bleibt wach“ steht nur, wenn die Assertion wirklich gehalten wird. In der 5-Minuten-Frist beim Steam-Wechsel stimmt das auch (`KeepAwake.held`).
- **Hält:** Der Hinweis fällt weg, sobald ein Spiel, der Vorhang oder das Overlay kommt (`DownloadProof.moment`). Die Hauptschleife prüft das auch, wenn die Zeile noch wartet.
- **Hält:** Steam nur bei Bedarf schickt kein ladendes Steam schlafen (`SteamOnDemand.unneeded`, `!facts.downloading`). Ein pausierter Download zählt dort weiter als Download, Steam bleibt also an. Das ist die sichere Seite.
- **Hält:** Schläft Steam und ein halber Download ist gelistet, steht „Steam läuft nicht, der Download steht“. Das stimmt.
- **War falsch:** „Mac schlafen legen“ bei pausiertem Download, G4.
- **Offen, schon bekannt:** Epic und GOG halten den Mac nach dem Beenden nicht wach. Ob Steams Pause-Knopf Bit 512 setzt, ist nur live zu klären.

### 3 · Merge-Konflikte

Geprüft mit `git show --remerge-diff` für alle 45 Merges seit 0.3.2. `Strings.swift`, `GameBackdrop.swift` und `Launcher.swift` hatten **keinen** Konflikt. Zwölf Merges hatten welche oder Nacharbeit, davon neun in Swift-Quellen.

| Merge | Datei | Lösung | Urteil |
|---|---|---|---|
| 7624ba7 | `SteamOnDemand` | Beide Sperren in einem `guard`, `wakeSteam` ohne die alte `macSteamBusy`-Prüfung | Stimmt, `wakeWay` deckt das ab |
| 1fe63bc | `InputRouter` | `pressed` neu, `held` bleibt | Stimmt |
| 2bb2442 | `InputRouter` | A: Tastatur und Frage zuerst, dann die Anmelde-Bühne | Stimmt |
| f3c8909 | `Profiles` | `needsRosettaLibrary` und `msync` beide | Stimmt, auch im `CodingKeys` und `init` |
| a9e0006 | `InputRouter`, `LibraryModel` | B mit Ausweg und Tastatur, Status mit Fortschritt und Pad-Antwort, beide `defer`-Zeilen | Stimmt |
| 365f393 | `InputRouter` | Spielernummern plus Meldungen | Stimmt |
| 568282a | `LibraryModel` | `.battleNetAsks` in `startAsksPlayer` | Stimmt für sich, das Zusammenspiel war G3 |
| 546d0c3 | `LibraryModel` | Abbruchprüfung vor `raiseCurtain` | Stimmt |
| 388db06 | `GameOverlay`, `OverlayView`, `InputRouter` | Altes `OverlayView` raus, `.stuck` in die neue Ansicht | Stimmt, `takesKeys` deckt `.stuck` ab |

Der einzige Fehler aus dieser Runde ist G3: Die Audit-Notiz O1 wurde beim Merge nicht umgesetzt.

### 4 · Was beim normalen Spieler anders ist

| Teil | Beim Spieler nach dem Update | Auf diesem Mac | Rückfall ohne Paket |
|---|---|---|---|
| **winebus-Stille** | `gamepad` 4.7.3-15 ohne den Patch | Engine-`winebus.so` lokal getauscht: `strings` findet `nightforge.pad-silence`, das Paket nicht | Sauber. Der Treiber antwortet nicht, `PadSilence.heard` ist falsch, das Spiel wird angehalten wie in 0.3.2 (`GameOverlay.swift:202`). Die Anfrage selbst bleibt folgenlos |
| **`pad-answer.exe`** | Fehlt, solange sie nicht im Repo liegt. `release.yml` installiert kein mingw | Lokale Builds haben sie: mingw liegt in `/opt/homebrew/bin` | Sauber. `PadAnswerRun.available` ist falsch, A und B gehen nicht an die Frage, der Vorhang sagt „mit Maus oder Trackpad antworten“ |
| **DXMT-Patch** | `graphics` -17, kein `prepareShaders` im `d3d11.dll` | Installiert ebenfalls -17, nur ein lokaler Testbau im Cache hat den Patch | Sauber. Die Zeile steht in `dxmt.conf`, nur die gepatchte DLL fragt sie ab (`Engine.swift:2543`, Patch Zeile 324) |
| **Gamepad-Paket fehlt ganz** | Wie seit 0.3.0: DualSense erreicht Windows-Spiele nicht | Installiert | Unverändert gegenüber 0.3.2 |
| **Klick ins Steam-Fenster** | Braucht „Bedienungshilfen“ und eine echte Maus zum Einschalten | **Vermutung:** schon erteilt | Sauber. Leiste sagt „mit der Maus“, sonst erklärt ein Hinweis den Weg |
| **PS-Taste** | Nur macOS 27 | macOS 27 | `HomeButtonSetup.exists` ist auf macOS 26 falsch |

`pad-answer.c` baut mit den Flags des Workflows (`-Werror`). Beide Patch-Sätze wurden lokal schon gebaut (`build-winebus-local.sh`, `build-dxmt-local.sh`).

**Für Spieler sichtbar anders:** Online-only-Windows-Spiele wie Overwatch werden unter dem Overlay angehalten, auf diesem Mac laufen sie weiter. Wer das live prüft, sieht also nicht, was Spieler sehen, bis das Paket verteilt ist.

### Entscheidungen

- **E1, 15 Minuten:** Steams Frage wartet laut Kommentar „so lange wie nötig“, die Schleife endet aber nach 900 s (`LibraryModel.swift:3609`, `:4859`). Bleibt die Lizenz 15 Minuten offen, sagt Nightforge „Steam reagiert nicht“, obwohl das Fenster noch steht. Gab es schon in 0.3.2, mit dem Lizenz-Rahmen fällt es eher auf. Vorschlag: nicht abbrechen, solange eine Frage steht; B führt ohnehin hinaus. **Entschieden 9.11.: weiter warten, eingebaut** (`LibraryModel.followsSteam`): die Zeit der offenen Frage zählt nicht, B führt hinaus, ein beendetes Steam nimmt die Frage mit. Nur als Regel getestet, live nicht.
- **E2, was der Merge auslöst:** `graphics.yml` und `gamepad.yml` veröffentlichen beim Push auf `main` sofort ein Release. Beides sind Builds, die laut Commit ef8d560 und `ENTSCHEIDUNG-DXMT-LGPL.md` eine eigene Freigabe brauchen. An Spieler gehen sie erst über Manifest und Signatur, also Schritt 9. Für alte 0.3.2-Kopien sind sie wirkungslos, solange niemand fragt. **Vermutung**, mit einem Spiel nie getestet. Vorschlag: mergen, aber Schritt 9 erst nach einem Live-Test.

### 5 · Schritte vor dem Release, in dieser Reihenfolge

Die Regel „main schützen“ lässt nur Pull Requests zu, ohne Pflicht-Checks und ohne Freigabe (`gh api …/rulesets/26713432`). Signieren macht der Nutzer auf seinem Mac.

| Nr. | Schritt | Wer | Warum hier |
|---|---|---|---|
| 1 | Offene Zweige in Staging, darunter dieser | Koordinator | |
| 2 | Live-Test nach `docs/LIVETEST-0.3.3.md` und der Liste unten | Nutzer | |
| 3 | E1 und E2 entscheiden | Nutzer | |
| 4 | `docs/release-notes/v0.3.3.md` schreiben, `Resources/Info.plist` auf 0.3.3 | Koordinator | `release.yml` übernimmt nur diese Datei |
| 5 | `claude/staging-033` pushen, PR nach `main` | mit OK | **Erster CI-Lauf** dieses Stands. Der Check „Signatures“ ist bis Schritt 6 rot; die Regel verlangt keinen grünen Check |
| 6 | Merge, danach sofort `scripts/sign-lists.sh main`, dann `scripts/check-signatures.sh` | Nutzer | Bis dahin lehnt jede laufende Kopie die Profilliste ab und behält ihre |
| 7 | Der Merge löst aus: `ci`, `graphics` und `gamepad` (neue Releases), `pad-answer` (PR `bot/pad-answer`), `profiles` (erneuert `bot/profiles`). Läufe prüfen | Koordinator | |
| 8 | `bot/pad-answer` prüfen und mergen | mit OK | **Vor dem Tag**, sonst fehlen A und B im Release |
| 9 | `components.yml` starten oder 04:17 abwarten, `scripts/sign-lists.sh bot/components`, PR #41 mergen | Nutzer | Nur nach dem Live-Test der neuen Pakete (E2). Geht auch nach dem Release |
| 10 | #40 (`bot/profiles`) erst nach dem neuen Lauf aus Schritt 7, dann signieren und mergen | Nutzer | **Der heutige Stand von #40 kennt `needsRosettaLibrary` nicht:** Overwatch verlöre die D3DMetal-Frage |
| 11 | #39 (`unity-play.exe`) entscheiden | Nutzer | Muss vor dem Tag sein, wenn es mit soll |
| 12 | Tag `v0.3.3-rc.1`, `scripts/sign-release.sh v0.3.3-rc.1 --publish`, installieren, `pad-answer.exe` in `Resources` prüfen | Nutzer | Prerelease, wird niemandem angeboten |
| 13 | Tag `v0.3.3`, `scripts/sign-release.sh v0.3.3 --publish` | Nutzer | Muss auf `main` liegen |
| 14 | Landing Page, Download-Zahlen | Koordinator | |

### Live prüfen

1. Y, X, A und L1 unter dem Vorhang, während Nightforge noch vorne ist: Es passiert nichts, nach dem Spiel ist die Seite unverändert. B führt weiter hinaus, wenn der Ausweg angeboten wird.
2. Kleines Steam-Fenster beim Spielende offen lassen, zurück in Nightforge den Finger aufs Touchpad: Steam kommt nicht nach vorn.
3. Battle.net fragt beim Start: Der Vorhang geht sofort, das Client-Fenster steht vorne, kein „Steam fragt etwas“.
4. Download in Steam pausieren: Im kleinen Menü erscheint „Mac schlafen legen“.

### Nachtrag: die kleinen Befunde (9.11.)

Zweig `claude/audit-033-rest` von `claude/staging-033` (`f5dd846`), je Befund ein Commit mit Test. E1 und E2 bleiben beim Nutzer.

| Nr. | Ergebnis | Was jetzt gilt | Commit |
|---|---|---|---|
| O2 | behoben | „Nightforge komplett entfernen“ meldet das Anmeldeobjekt ab, sobald alles andere weg ist. Bleibt etwas liegen, bleibt es wie die Einstellungen für den zweiten Versuch. Nur im Test mit Ersatz geprüft, nie ausgeführt | 98e2a4c |
| O3 | behoben | Das Touchpad bewegt den Zeiger nicht mehr über einem Spiel, das unter dem Overlay weiterläuft. Eine Frage von macOS bekommt ihn weiterhin. Das Overlay selbst geht weiter mit der Pad-Markierung | ab7d937 |
| O4 | behoben | Stick und jeder Trigger gehören dem Pad, das sie zuerst nahm, bis es loslässt. Geht ein Controller, lässt nur er los | eed0ff5 |
| N2 | teilweise | Solange das Spiel die Front hat, bleiben Stick und R2 auch unter einem kleinen Fenster beim Spiel; als Maus zählen sie erst, wenn die App des Fensters vorne ist | 5b0fb45 |
| N3 | behoben | Die Lizenz-Leiste richtet sich nach dem zuletzt benutzten Pad | 4fcde7d |
| N4 | behoben | Stellt sich eine schon stehende Frage als Lizenz heraus, kommt der Rahmen beim nächsten Blick | a81097f |

**O3 ist enger als oben beschrieben:** Seit dem großen Overlay werden auch Mac-Spiele ohne Online-Zwang angehalten (`OverlayRules.stillness`). Betroffen waren nur noch die Spiele, die weiterlaufen.

**Entscheidung offen (N2):** Mit einem Pad ohne Touchpad lässt sich ein kleines Fenster über dem Spiel nur mit der Maus erreichen. Der rechte Stick und R2 gehören dem Spiel, also bräuchte es eine eigene Geste. Große Fenster bekommen die Front ohnehin von selbst.

**Offen:** N1 (Fenster in den ersten 8 s nach dem Vorhang). Der Eingriff in das Zusammenspiel von Vorhang und Bühnenwache ist den kleinen Nutzen vor dem Release nicht wert.

Live prüfen:

1. Mac-Spiel mit Online-Zwang unter dem Overlay: Der Finger auf dem Touchpad bewegt weder Zeiger noch Kamera.
2. Zwei Pads ohne Touchpad über einem Steam-Fenster: Spieler 1 bewegt den Zeiger, der Stick von Spieler 2 stört nicht. Spieler 2 schaltet ab, während Spieler 1 R2 hält: Der Klick bleibt gedrückt.
3. Pad ohne Touchpad, kleiner Steam-Hinweis über dem Spiel: Stick und R2 wirken nur im Spiel. Großes Steam-Fenster: Nach spätestens einer Sekunde ist der Stick die Maus.
4. DualSense und Xbox-Pad, Lizenz beim ersten Start: Die Leiste passt zum Pad, das zuletzt benutzt wurde. **Vermutung:** `GCController.current` folgt dem Pad auch, solange Steam vorne ist.
