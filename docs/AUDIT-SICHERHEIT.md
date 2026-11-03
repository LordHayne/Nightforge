# Sicherheits- und Datenschutz-Audit

Stand: `claude/ux-roadmap-next` 29e458a, 3.11.2026. Was seitdem behoben oder beauftragt ist, steht in der Übersicht und unter jedem Befund
(Stand der Probe-Zusammenführung `claude/staging-031`, 4f0d00a). Die Nachprüfungen desselben Tages – Review der Probe-Zusammenführung,
Signierkette A–H, Sandbox, Profil-Grenzen, Berichte – haben ihren Stand je Fund in `docs/SICHERHEIT-0.3.md` › „Nachprüfungen vom 3.11.2026“.

Wie geprüft: Code, Skripte und Workflows gelesen. Ausgeführt wurde nichts. Einzige Ausnahme sind `ls -ld` und `ls -l`
auf die Orte der Anmeldedaten, um die Dateirechte zu sehen; Inhalte wurden nicht gelesen. Der Zweig `signed-updates`
(noch nicht gemergt) ist nicht Teil dieses Audits.

Schwere:
- **hoch**: Ein einzelner Fehler oder Angriff erreicht alle Nutzer mit fremdem Code.
- **mittel**: Echter Schaden ist möglich, braucht aber eine Vorbedingung.
- **niedrig**: Geringer Schaden oder eine lange Kette von Vorbedingungen.

## Übersicht

| Nr. | Schwere | Thema | Ort | Stand (3.11.) |
|---|---|---|---|---|
| H1 | hoch | App-Update und `install.sh` prüfen nicht, von wem die App stammt | `Updater.swift:115`, `scripts/install.sh:46` | behoben auf `claude/signed-updates-dda700` (29b9f7f); die Nachprüfung der Signierkette (A–H) ist behoben, 907161e bis a71421b |
| M1 | mittel | Nächtliche Profile aus fremdem `HEAD` gehen ungeprüft nach `main` und zu allen Nutzern | `.github/workflows/profiles.yml:45` | behoben: `claude/signed-updates-dda700` (b1c26c9, 700fd70), Profil-CI `claude/profile-ci` (6ec6878), die App prüft Overrides und Argumente beim Lesen selbst (e5197f1) |
| M2 | mittel | Windows-Programme sehen über `Z:` den ganzen Mac, auch Nightforges Anmeldedaten | Prefix `dosdevices/z:` | Entwurf `claude/laufwerke-z`; Sandbox `claude/wine-sandbox` (Schalter aus), nachgebessert 01e234d, a4d0cdd, d493cd4, 77e0bba, 3d257f1, 76f1b50, ae198a1, 5300f05; Live-Test steht aus |
| M3 | mittel | Der Problembericht geht schon beim Öffnen des Links an GitHub | `ProblemReport.swift:88` | behoben auf `claude/report-url-m3` (ce91765) |
| M4 | mittel | D3DMetal-Import übernimmt ungeprüfte Windows-DLLs, auch ohne Rückfrage aus „Downloads“ | `D3DMetalFlow.swift:162`, `Engine.swift:1009` | behoben auf `claude/d3dmetal-import-m4` (7829e1b) |
| N1 | niedrig | `nightforge://play/…` startet installierte Spiele von jeder Webseite aus | `GameShortcut.swift:18` | behoben auf `claude/audit-low` (b0cbf66) |
| N2 | niedrig | Programmnamen gehen ungefiltert in `.reg`-Abschnitte | `Engine.swift:1503` | behoben auf `claude/audit-low` (1b5330f) |
| N3 | niedrig | Spielstand-Regeln dürfen leere Pfade und `*` an der Wurzel haben; `takeNewer` löscht dort | `SaveTransfer.swift:52`, `:122` | behoben auf `claude/audit-low` (271d2a9) |
| N4 | niedrig | `fileEdits` und `iniSettings` prüfen den Ordner ohne Symlinks aufzulösen | `Engine.swift:2014`, `:2032` | behoben auf `claude/audit-low` (3a39b81) |
| N5 | niedrig | Dock-Bibliothek aus dem beschreibbaren Datenordner in jedem Wine-Prozess | `Engine.swift:1865` | offen; mit eingeschalteter Sandbox innen nur lesbar (a4d0cdd) |
| N6 | niedrig | Spieletest-Bericht im öffentlichen Repo nennt die installierten Spiele | `scripts/import-game-test.py` | offen, entscheidet der Nutzer |
| N7 | niedrig | Lücken in der Schwärzung (Laufwerksnamen, Rechnername, GOG-Kennungen) | `GameLog.swift:176` | behoben auf `claude/report-url-m3` (b87dee7); die Berichte des Spieletests 44f09e8 |
| N8 | niedrig | Eingecheckte `steamwebhelper.exe` ohne Prüfsumme in `build.sh` | `wrapper.yml:31`, `build.sh:52` | behoben auf `claude/audit-low` (a652cee) |
| N9 | niedrig | `profiles.yml` hat `actions: write` für alle Läufe | `profiles.yml:28` | behoben auf `claude/signed-updates-dda700` (700fd70); `components.yml` mit Rechten je Job (a71421b) |

## Hoch

### H1 App-Update und `install.sh` prüfen nicht, von wem die App stammt

**Stand 3.11.:** Behoben auf `claude/signed-updates-dda700` (29b9f7f). Die Nachprüfung der Signierkette (Review A–H, 3.11.) fand
Lücken um die Signatur herum, alle behoben: A 907161e, B 4584ecf, C 400bd06, D 5fdcbbb, E 407f122, F 3f510f9, G a71421b, H 83d10d2
(als Restrisiko K6a notiert). Einzelheiten: `docs/SICHERHEIT-0.3.md` › „Nachprüfungen vom 3.11.2026“.

**Wo**
- `Sources/Nightforge/Updater.swift:21–37`: Nimmt das erste Asset aus `releases/latest`, dessen URL `Nightforge-` enthält
  und auf `.zip` endet.
- `Updater.swift:105–115`: Lädt die Zip und packt sie aus. Danach prüft es die Bundle-ID und ruft
  `codesign --verify --deep` auf, **ohne Anforderung (`-R`)**.
- `Updater.swift:121`: Tauscht die App aus.
- `build.sh:84`: Releases werden nur ad hoc signiert (`--sign -`). `--verify` belegt damit nur, dass die Zip heil ist,
  nicht, wer sie gebaut hat: Jede ad hoc signierte App mit der Bundle-ID `io.github.lordhayne.nightforge` besteht.
- `scripts/install.sh:46–50`: `releases/latest` ohne Prüfsumme. `:64` entfernt die Quarantäne, also prüft Gatekeeper
  die App nie.
- `.github/workflows/release.yml:11`, `:85`: Jeder Tag `v*` veröffentlicht ein Release, das Updater und `install.sh`
  sofort als neueste Version sehen.

**Szenario:** Ein gestohlenes GitHub-Token mit Schreibrecht, ein übernommenes Konto oder ein manipulierter Release-Lauf
legt einen Tag `v0.3.9` an oder lädt eine eigene Zip in ein Release. Jede installierte Nightforge meldet beim
nächsten Start „Update verfügbar“. Ein Klick ersetzt die App durch fremden Code mit allen Rechten des Nutzers:
Dateien, Anmeldedaten der Stores, alles, was der Nutzer selbst darf. Neue Nutzer bekommen denselben Code über
`curl | bash`, ohne jede Warnung von macOS.

**Vorschlag**
- Den Zweig `signed-updates` mergen. Die Release-Zip mit einem eigenen Schlüssel signieren (z. B. Ed25519/minisign,
  öffentlicher Schlüssel fest in der App) und diese Signatur vor `replaceItemAt` prüfen. `install.sh` prüft dieselbe
  Signatur oder eine SHA-256 aus einer signierten Datei.
- Mit einer Developer-ID zusätzlich `codesign --verify -R='anchor apple generic and certificate leaf[subject.OU] =
  "<Team-ID>"'`, so wie es `MacSteam.swift:157` für Steam schon macht.
- Bis dahin: Tags `v*` in den Repo-Einstellungen schützen und den Release-Job hinter ein GitHub-Environment mit
  manueller Freigabe legen.

## Mittel

### M1 Nächtliche Profile aus fremdem `HEAD` gehen ungeprüft nach `main` und zu allen Nutzern

**Stand 3.11.:** Behoben. `claude/signed-updates-dda700`: b1c26c9 nimmt DLL-Overrides und Startargumente aus umu-protonfixes nur noch als
einfache Werte, 700fd70 vergibt die Rechte in `profiles.yml` pro Job (die Signatur bleibt beim Maintainer). `claude/profile-ci`: 6ec6878 prüft
auch `fileEdits`, `iniSettings`, `resolution`, `saves` und `mac.json`, bevor etwas signiert wird. `claude/profile-limits`: e5197f1 liest
`dllOverrides` und `arguments` mit denselben Regeln wie `build-profiles.py` (die App verlässt sich nicht auf die CI), dazu die Grenzen
18c92d2, ecf59d4, b149a87, 0daa1b8, 05c16ce, 63053eb, 6e8dc40. Offen: Die CI übernimmt die strengeren Regeln der App noch nicht
(15 weitere winetricks-Verben, Grenzen für `frameLimit`, `vulkanSamplers` und die Zahl der Overrides), kein Widerspruch.

**Wo**
- `.github/workflows/profiles.yml:45`: klont `umu-protonfixes` per `--depth 1` ab `HEAD`, also ungepinnt.
- `profiles.yml:49`: lädt `AreWeAntiCheatYet/HEAD/games.json`.
- `profiles.yml:114–126`: committet und pusht direkt auf `main`.
- Jede App lädt beim Start `profiles/profiles.json` von `main` (`Resources/Info.plist:51`).
- Die Validierung (`profiles.yml:57–91`) prüft `registry`, `winetricks`, `executable`, `graphics` und weitere Felder,
  **nicht aber `dllOverrides` und `arguments`**. Die übersetzt `scripts/build-profiles.py:194–201` aus umu.
- Angewendet werden sie in `Engine.swift:1504` (AppDefaults des Spiels) und `Launcher.swift:529` bzw. `:587` (an die
  Befehlszeile des Spiels).

**Szenario:** Ein Commit im fremden umu-protonfixes, böswillig oder versehentlich, setzt für ein beliebtes Spiel
`dllOverrides` wie `"d3d11": ""` oder fragwürdige Startargumente. Nachts landet das ungeprüft auf `main`, morgens
bei allen Nutzern: Das Spiel startet nicht mehr oder anders. Ein falscher Eintrag in AreWeAntiCheatYet sperrt Spiele
mit „Anti-Cheat läuft nicht auf dem Mac“. Mac-Code ausführen kann ein Profil dank der Registry- und Verb-Filter nicht.
Das begrenzt den Schaden auf Spielstarts.

**Vorschlag**
- Wie bei `components.yml`: Der nächtliche Lauf schlägt die Änderung als Bot-PR vor, statt auf `main` zu pushen.
  Alternativ die Quellen auf einen Commit pinnen und Sprünge per PR machen.
- Die Validierung erweitern: `dllOverrides` mit Namen `[a-z0-9_.-]{1,64}` und Werten aus der festen Liste von
  `OVERRIDE_ORDERS`; `arguments` ohne Steuerzeichen, mit begrenzter Länge und Anzahl.
- Dieselbe Prüfung in der App beim Lesen (`Profiles.swift`), so wie es `isSafeWinetricksVerb` schon für Verben tut.

### M2 Windows-Programme sehen über `Z:` den ganzen Mac, auch Nightforges Anmeldedaten

**Stand 3.11.:** Entwurf auf `claude/laufwerke-z` (98b98e7): `Z:` bleibt, geschützt werden die Anmeldedaten. Die Sandbox steht auf
`claude/wine-sandbox` (ce39bf7), hinter einem Schalter, der **aus** ist. Nach dem Review der Probe-Zusammenführung und zwei externen
Reviews: jeder Wine-Start läuft in ihr (01e234d), was Nightforge außen ausführt, ist innen nur lesbar (a4d0cdd), kein Helfer heißt kein
Wine-Start (d493cd4), das Beenden-Skript startet Steams `-shutdown` in ihr (3d257f1), Steuerdateien und Einstellungen sind innen nicht
änderbar (77e0bba), die Caches der signierten Listen nur lesbar und die Spiel-Apps gesperrt (76f1b50), kein Ordner über einem
geschützten Ort lässt sich verschieben (ae198a1), das Umschalten steht unter einer Sperre (5300f05). Offen: der Live-Test, ohne den der
Schalter nicht eingeschaltet wird. Die Dateien im Datenordner, die nur Nightforge schreibt (darunter `Epic/destinations.json` und
`GOG/installed.json`), sind innen nur lesbar (5cc5402); beschreibbar bleiben `Prefix/`, legendarys `tmp`, `GOG/Redist` und
`GOG/Support/<id>` (siehe `docs/SICHERHEIT-0.3.md`).

**Wo**
- Im Prefix zeigt `dosdevices/z:` auf `/`. Das ist Wines Standard aus `wineboot`. Nightforge verlässt sich darauf:
  - `Legendary.swift:236–238`: Spielpfade auf `Z:`.
  - `ExternalDrives.swift:227`: externe Laufwerke.
  - `Engine.swift:1370`: `msiexec` mit `Z:`-Pfad.
- Orte und Rechte der Anmeldedaten, gemessen am 3.11. (nur Rechte, keine Inhalte):

| Was | Ort | Datei | Ordner |
|---|---|---|---|
| Epic (legendary) | `~/Library/Application Support/Nightforge/Epic/legendary/user.json` (`Legendary.swift:12`) | 644 | 700 (`keepPrivate`, `Legendary.swift:280`) |
| GOG (gogdl) | `…/Nightforge/GOG/gogdl/auth.json` (`GOGDL.swift:12–14`) | 644 | 700 |
| Steam (Windows) | `…/Nightforge/Prefix/drive_c/Program Files (x86)/Steam/config/` (`loginusers.vdf`, `config.vdf`), dazu `Prefix/user.reg` | 644 | 755 |
| Anmelde-Webviews | nicht gespeichert (`.nonPersistent()`, `EpicSignIn.swift:25`, `GOGSignIn.swift:29`) | – | – |

`~/Library` hat 700, andere Benutzer des Macs kommen also nicht heran.

**Szenario:** Ein Windows-Spiel, ein Mod oder ein Trainer liest
`Z:\Users\<name>\Library\Application Support\Nightforge\Epic\legendary\user.json` und hat damit das Epic-Refresh-Token.
Über `Z:` sieht es auch Daten anderer Apps unter `~/Library` und Schlüssel unter `~/.ssh`. Ausgenommen sind nur die
von macOS geschützten Ordner (Dokumente, Schreibtisch, Downloads). Wine hat keine Sandbox; CrossOver und Whisky
verhalten sich genauso.

**Vorschlag**
- `Z:` nicht auf `/` zeigen lassen, sondern nur auf das, was Spiele und Nightforge brauchen: `/Volumes`, die
  Spielbibliotheken und, für den `msiexec`-Aufruf, einen festen Ordner. Nightforges eigene `Z:`-Pfade bekämen dann
  eigene Laufwerksbuchstaben.
- Vorher prüfen, was bricht: Steam-Bibliotheken auf externen Laufwerken, GOG- und Epic-Spiele außerhalb des Prefix,
  Launcher, die über `Z:` Mac-Pfade erwarten.
- Anmeldedaten danach außerhalb des für Wine sichtbaren Baums ablegen. Legendary und gogdl erwarten Dateien; mit
  eingeschränktem `Z:` reicht dafür ein Ordner außerhalb der freigegebenen Pfade.

### M3 Der Problembericht geht schon beim Öffnen des Links an GitHub

**Stand 3.11.:** Behoben auf `claude/report-url-m3` (ce91765): Der Link trägt nur feste Fakten (Spiel, Versionen, Mac, Erkanntes), Fehlerzeilen
und Startoptionen liegen auf der Zwischenablage, jede Zeile durch die Schwärzung. Die Texte in den Optionen, im Blatt „Startet nicht?“, in
den Einstellungen, in der README, auf der Landingpage und in `compat-report.yml` sagen jetzt, dass GitHub die Werte beim Öffnen der Seite
bekommt und der Bericht erst beim Absenden öffentlich ist.

**Wo**
- `Sources/Nightforge/ProblemReport.swift:20–21`: Der Kommentar sagt „Nothing leaves the Mac unless the player submits
  it there“.
- `:73–79`: Bis zu 3500 Zeichen Fehlerzeilen aus `wine.log`.
- `:81–86`: gogdl-Fehlerzeilen.
- `:88–93`: Alles steht als `title`- und `body`-Parameter in der URL.
- Das Issue-Formular sagt in `.github/ISSUE_TEMPLATE/compat-report.yml:9` „Nothing was sent before you press Submit“.

**Szenario:** Der Nutzer klickt „Startet nicht?“, der Browser öffnet die vorausgefüllte Issue-Seite und bricht dann ab.
Titel und Text samt Fehlerzeilen sind trotzdem schon unterwegs:
- per GET an GitHub, in dessen Server-Logs;
- in den Browser-Verlauf;
- je nach Browser per iCloud- oder Chrome-Synchronisation auf andere Geräte.

Die Schwärzung (N7) ist eine Heuristik. Was sie übersieht, steht danach an diesen Orten.
Beim Bewertungsbericht (`CompatReport.swift`) sind es nur feste Werte, dort ist das unkritisch.

**Vorschlag**
- Fehlerzeilen nicht in die URL schreiben. Die App legt sie in die Zwischenablage oder als Datei zum Anhängen, das
  Formular sagt „Fehler einfügen (in der Zwischenablage)“.
- Die Texte richtigstellen: „Beim Öffnen wird das Formular an GitHub übertragen, veröffentlicht wird es erst beim
  Absenden.“ Das gilt im Kommentar und im Template.

### M4 D3DMetal-Import übernimmt ungeprüfte Windows-DLLs, auch ohne Rückfrage aus „Downloads“

**Stand 3.11.:** Behoben auf `claude/d3dmetal-import-m4` (7829e1b): die Windows-DLLs nach SHA-256 je Version (3.0, 4.0b3), ein Download wird angeboten statt importiert.

**Wo**
- `Sources/Nightforge/D3DMetalSupply.swift:247–268`: Nur `libd3dshared.dylib` und `D3DMetal.framework` werden mit
  `anchor apple` geprüft (`Engine.isAppleSigned`, `Engine.swift:1180`). Kopiert wird dagegen das ganze `lib/`, samt
  `wine/x86_64-windows/*.dll`.
- `Engine.swift:1009–1011`, `:1017–1022`: Diese Windows-DLLs kommen als Direct3D-Builtins in die Engine.
- `D3DMetalFlow.swift:147–162`: Nach „Bei Apple laden und importieren“ beobachtet Nightforge 30 Minuten lang den
  Ordner „Downloads“. Jede neue Datei mit passendem Namen (`D3DMetalSupply.swift:343`: `game_porting`, `gptk`, …)
  wird **ohne Rückfrage** importiert. Eine schon vorhandene Datei wird dagegen erst angeboten (`:130–135`).

**Szenario:** Der Nutzer hat Apples Download-Seite offen. In dieser Zeit landet eine präparierte
`Game_Porting_Toolkit_3.0.dmg` in „Downloads“, etwa als automatischer Download einer anderen Seite. Sie enthält
Apples echte, signierte Rahmenwerke, die frei kursieren, und manipulierte `d3d11.dll`/`d3d12.dll`. Nightforge
importiert sie still. Die DLLs laufen in jedem DirectX-11/12-Spiel auf D3DMetal und haben über `Z:` (M2) Zugriff auf
den Mac. Die Unix-Brücken legt Nightforge zwar selbst als Links auf Apples signierte Bibliothek an (gut), das schützt
aber nicht die Windows-Seite.

**Vorschlag**
- Für die bekannten Toolkit-Versionen (3.0, 4.0b3) die SHA-256 jeder übernommenen DLL in der App führen und nur
  diese annehmen. Eine unbekannte Version würde abgelehnt oder ausdrücklich nachgefragt.
- Auch beim Auto-Import vorher fragen („Diese Datei importieren?“), wie bei einer schon vorhandenen.

## Niedrig

### N1 `nightforge://play/…` startet installierte Spiele von jeder Webseite aus

**Stand 3.11.:** Behoben auf `claude/audit-low` (b0cbf66): Ein Play-Link startet nur mit dem Schlüssel der eigenen Spiel-Apps, sonst zeigt er die Spielseite. Nebenwirkung: Eigene Kurzbefehle mit `nightforge://play` zeigen nur noch die Seite.

**Wo:** `GameShortcut.swift:18–25`, `MacIntegration.swift:39–46`, `App.swift:64`.

**Szenario:** Eine Webseite öffnet `nightforge://play/<id>`. Nach der Nachfrage des Browsers („Nightforge öffnen?“)
startet ein installiertes Spiel, Steam wird dafür womöglich neu gestartet. Nicht installierte Spiele öffnen nur ihre
Seite. Es wird nichts geladen und nichts installiert.

**Vorschlag:** Kam der Link, während Nightforge nicht vorne war, einmal bestätigen lassen oder nur die Spielseite
zeigen. Die Apps in `~/Applications/Nightforge Games` könnten einen eigenen Parameter mitgeben, der den
Direktstart erlaubt.

### N2 Programmnamen gehen ungefiltert in `.reg`-Abschnitte

**Stand 3.11.:** Behoben auf `claude/audit-low` (1b5330f).

**Wo:** `Engine.swift:1503`: `[HKEY_CURRENT_USER\Software\Wine\AppDefaults\<exe>]` mit dem Dateinamen aus dem
Spielordner. Werte laufen durch `regString`, der Schlüssel aber nicht durch `isAllowedRegistryKey`.

**Szenario:** Ein Spiel oder Mod liefert eine `.exe`, deren Name `]`, einen Zeilenumbruch und einen weiteren
Abschnitt enthält, etwa den Autostart-Schlüssel `…\CurrentVersion\Run`. Beim Start schreibt Nightforge diesen in
den Prefix. Gering, weil ein Spiel ohnehin Code ausführt.

**Vorschlag:** Namen mit Steuerzeichen, `[` oder `]` überspringen, wie `isAllowedRegistryKey` es für Profile tut.

### N3 Spielstand-Regeln dürfen leere Pfade und `*` an der Wurzel haben; `takeNewer` löscht dort

**Stand 3.11.:** Behoben auf `claude/audit-low` (271d2a9).

**Wo**
- `SaveTransfer.swift:52–58`: Geprüft wird nur auf `..`.
- `:122–145`: Nach einer Sicherung löscht `takeNewer` im Ziel, was auf der anderen Seite fehlt.
- Die Regeln kommen aus `profiles/mac.json` und aus Steams Cloud-Regeln der Spiele (appinfo, vom Entwickler gesetzt).

**Szenario:** Eine Regel mit `macRoot` „MacAppSupport“, leerem `macAddPath`, leerem `path`, Muster `*` und rekursiv.
Wechselt der Nutzer von der Windows- zur Mac-Version und nimmt „Neuere Spielstände übernehmen“, sichert Nightforge
`~/Library/Application Support` und löscht dort alles, was die Windows-Seite nicht hat. Die Sicherung gibt es, aber
andere Apps verlieren ihre Daten mitten im Betrieb.

**Vorschlag:** Das Ziel muss mindestens eine Ebene unter `MacAppSupport` bzw. `MacCaches` liegen. `*` mit
`recursive` direkt an einer Wurzel ablehnen.

### N4 `fileEdits` und `iniSettings` prüfen den Ordner ohne Symlinks aufzulösen

**Stand 3.11.:** Behoben auf `claude/audit-low` (3a39b81).

**Wo:** `Engine.swift:2014–2016` und `:2032–2033`. Die Prüfung `standardizedFileURL` mit `hasPrefix` behandelt `..`
richtig, folgt aber keinen Links. Für die Wurzel selbst prüft `SaveTransfer.windowsRoot` (`:182`) mit aufgelösten
Links, für den Pfad darunter nicht.

**Szenario:** Liegt im Spiel- oder Benutzerordner des Prefix ein Link nach außen (`users\<name>\Documents` zeigte
früher bei Wine auf den Mac-Ordner), schreibt eine `iniSettings`-Regel durch ihn hindurch. Die Werte stammen nur aus
`mac.json`, deshalb gering.

**Vorschlag:** Datei und Basis vor dem Vergleich mit `resolvingSymlinksInPath()` auflösen.

### N5 Dock-Bibliothek aus dem beschreibbaren Datenordner in jedem Wine-Prozess

**Stand 3.11.:** Offen. Mit eingeschalteter Sandbox ist die Datei innen nur lesbar (a4d0cdd); ohne sie bleibt es bei der Überlegung unten
(derselbe Benutzer darf ohnehin alles).

**Wo:** `Engine.swift:1862–1866` setzt `DYLD_INSERT_LIBRARIES` auf die Bibliothek in
`~/Library/Application Support/Nightforge` (`DockHider.swift:3–43`). Steam reicht sie an alles weiter, was es startet,
also auch an Spiele.

**Szenario:** Ein anderer Prozess desselben Benutzers tauscht die Datei aus und läuft danach in jedem Spiel mit.
Das bringt ihm wenig, weil er als derselbe Benutzer ohnehin alles darf. Gewollt und dokumentiert.

**Vorschlag:** Vor dem Setzen die Signatur der Datei prüfen (`codesign -R 'identifier "…"'`).

### N6 Spieletest-Bericht im öffentlichen Repo nennt die installierten Spiele

**Stand 3.11.:** Offen. Die Entscheidung liegt beim Nutzer.

**Wo:** `GameTestRun.swift`, `GameTestReport.swift:65–73`, `scripts/import-game-test.py`. Die Berichte landen in
`docs/spieletest/`.

**Szenario:** Home-Ordner und Kontoname sind geschwärzt und werden beim Import ein zweites Mal geprüft (gut). Der
Bericht nennt aber Spiel für Spiel, was installiert ist, wann getestet wurde und wie es lief, und das öffentlich.
Das ist ein kleines Nutzungsprofil des Maintainers.

**Vorschlag:** Bewusst entscheiden. Möglich wäre, nur Spiele aus dem Testkorb aufzunehmen und Uhrzeiten auf das
Datum zu kürzen.

### N7 Lücken in der Schwärzung

**Stand 3.11.:** Behoben auf `claude/report-url-m3` (b87dee7): Laufwerksnamen (`<drive>`), Rechner- und Hostnamen (`<computer>`), der
Ordner `/var/folders/<id>`, GOG-Benutzerkennungen (`<id>`, `<gog user>`) und der Kontoname in anderen Zeilen (`<user>`, als Wort, damit
„Thomas Was Alone“ bleibt). Die Berichte des Spieletests laufen in `claude/game-test-fixes` (44f09e8) durch dieselbe Schwärzung, auch die
Notizen des Laufs; die zweite Prüfung vor dem Import (`GameTest.leaks`, `scripts/import-game-test.py`) kennt dasselbe.

**Wo:** `GameLog.swift:176–207`.

Abgedeckt sind:
- der Home-Ordner;
- `users\<name>` und `users/<name>`;
- Steam-IDs (`[U:1:…]`, `7656119…`, `userdata\<nummer>`);
- E-Mail-Adressen;
- Token-Schlüsselwörter und `Bearer`;
- Epics Anmeldeargumente.

Nicht abgedeckt sind:
- Namen externer Laufwerke (`/Volumes/Thomas SSD/Nightforge Games/…`, auch als `Z:\Volumes\…`);
- der Rechnername;
- GOG-Benutzerkennungen;
- der Kontoname außerhalb von `users\…`, z. B. in Pfaden wie `/private/var/folders/…` oder in Zeilen anderer Programme.

**Szenario:** Ein Problembericht (M3) mit einer Fehlerzeile von einem externen Laufwerk trägt dessen Namen, oft den
Vornamen des Nutzers.

**Vorschlag:** `/Volumes/<Name>` durch `/Volumes/<drive>` ersetzen (auch in der `Z:`-Schreibweise), dazu Rechner- und
Hostnamen. Tests mit echten Logzeilen.

### N8 Eingecheckte `steamwebhelper.exe` ohne Prüfsumme in `build.sh`

**Stand 3.11.:** Behoben auf `claude/audit-low` (a652cee): `build.sh` prüft die eingecheckte Datei gegen eine SHA-256, die der Workflow daneben schreibt.

**Wo:** `.github/workflows/wrapper.yml:31–40` baut die Datei bei jedem Push und committet sie in den jeweiligen Zweig.
`build.sh:52` nimmt die eingecheckte Datei, wenn mingw fehlt. Sie ersetzt in Steam bei allen Nutzern den echten Helper.

**Szenario:** Ein Binärdiff lässt sich im Review nicht lesen. Eine manipulierte Datei in einem PR fällt nicht auf.
Ein Release-Build auf einem Mac ohne mingw liefert sie aus.

**Vorschlag:** `build.sh` prüft die eingecheckte Datei gegen eine SHA-256, die der Workflow neben ihr einträgt
(Textdatei, im Review lesbar). Alternativ baut der Release sie immer selbst.

### N9 `profiles.yml` hat `actions: write` für alle Läufe

**Stand 3.11.:** Behoben auf `claude/signed-updates-dda700` (700fd70): Rechte pro Job, der Bau liest nur. Dasselbe für `components.yml`
(a71421b, Review G): „update“ liest nur und holt ohne Zugangsdaten, nur „propose“ schreibt. Auf GitHub ist noch keiner dieser Workflows
gelaufen (nur als YAML gelesen und lokal geprüft).

**Wo:** `.github/workflows/profiles.yml:28–30`: `contents: write` und `actions: write` gelten für den ganzen
Workflow, auch für `pull_request` aus dem eigenen Repo. `actions: write` braucht nur der Zeitplan-Schritt, der die
Workflows aktiv hält.

**Szenario:** Ein Collaborator-Branch mit geändertem Python-Code läuft im PR mit Schreibrechten. Forks bekommen von
GitHub ohnehin nur Leserechte.

**Vorschlag:** Rechte pro Job vergeben: PR-Läufe mit `contents: read`, der nächtliche Job mit den nötigen Rechten.

## Zu prüfen

- **GitHub-Einstellungen**, aus dem Code nicht zu sehen:
  - Schutz für `main` und Tags `v*`;
  - Pflicht-Review für `bot/components` und künftige Bot-PRs;
  - wer Releases anlegen darf;
  - die Actions-Einstellung „Allow GitHub Actions to create and approve pull requests“ (sollte aus sein).
- **`dllOverrides` und `arguments` in der aktuellen `profiles.json`** einmal durchsehen: Was ist heute drin, und was
  würde eine Validierung (M1) ablehnen?
- **Symlinks in Komponenten-Archiven.** `tar` entpackt mit seinen sicheren Voreinstellungen (keine absoluten Pfade,
  kein `..`), Links mit Zielen außerhalb legt es aber an. Spätere Schreibvorgänge in den Engine-Ordner
  (`installMoltenVK`, `installGraphics`) würden ihnen folgen. Relevant nur bei einer bösartigen Komponente, die dann
  ohnehin Code ausführt.
- **Epic-Austauschcodes in `wine.log`.** Legendary übergibt `-AUTH_PASSWORD=<code>` als Startargument. Ob Wine oder
  ein Spiel diese Zeile ins Log schreibt, ist nicht geprüft. Lokal liegt das Log in `~/Library` (700), aber über `Z:`
  (M2) lesbar. Die Codes leben kurz.
- **`SteamSetup.exe`** kommt über HTTPS von Valves CDN, ohne eigene Prüfsumme (`Engine.swift:40`,
  `SteamPackages.swift:144`). Die Pakete beim Vorabladen prüft Nightforge dagegen mit Steams SHA-256 (gut).
- **Der Abschalt-Check im Shutdown-Skript.** `reopened` (`Engine.swift`, `steamShutdownScript`) sucht per `pgrep -f` nach
  dem Pfad der App. Jeder Prozess, dessen Befehlszeile diesen Pfad enthält (auch ein `grep` im Terminal), hält Steam
  am Laufen. Das ist kein Sicherheitsproblem, aber eine Falle bei Tests.

## Gut gelöst

**Komponenten**
- Nur HTTPS; `id`, `version` und Dateiname müssen schlichte Namen sein (`Component.isSafeToInstall`,
  `Components.swift:21–26`).
- SHA-256 vor dem Entpacken, Entpacken in einen Staging-Ordner, unbekannte Einträge werden ausgelassen statt die
  Liste zu verwerfen.
- Updates der Liste kommen als Bot-PR (`components.yml:41–69`, „Nothing reaches the app until this is merged“).

**Profile**
- Registry nur unter `Software\<Hersteller>` ohne Microsoft, Classes, Policies und Wine; nur `REG_SZ` und `REG_DWORD`;
  Steuerzeichen und Klammern werden abgewiesen. Geprüft in der App (`Engine.swift:1582`), im Build-Skript und im
  Workflow.
- winetricks-Verben nur `[a-z0-9_]` und keine Befehle wie `annihilate`, ebenfalls dreifach geprüft.
- `executable` bleibt im Spielordner (`GameProgram.swift:23–31`).
- `fileEdits` und `iniSettings` haben feste Wurzeln im Prefix.
- `SaveTransfer` weist `..` ab.

**Fremde Programme**
- PackedApp prüft Namen und Link-Ziele beim Entpacken (`isInside`, `Legendary.swift:315`).
- Die Token-Ordner von Epic und GOG bekommen 700.
- Steam für Mac wird vor der Installation gegen Valves Code-Anforderung geprüft (`MacSteam.swift:157`).
- D3DMetals Rahmenwerke werden mit `anchor apple` geprüft, vor und nach dem Kopieren. Die Unix-Brücken legt Nightforge
  selbst als Links an.

**Anmeldung**
- Die Webviews speichern nichts.
- Die Weiterleitung wird an Host und Pfad erkannt (`EpicSignIn.swift:82`, `GOGSignIn.swift:67`).

**Shell und Prozesse**
- Die Skripte (`steamShutdownScript`, `SteamPriority`, gogdl über `sh -c`, Neustart im Updater) sind fester Text.
  Daten kommen nur als Argumente, stehen in Anführungszeichen und werden mit `grep -F --` gesucht.
- Spielargumente gehen als argv-Liste an Wine, nie durch eine Shell.
- Das Spiel-Beenden im Overlay trifft nur `.exe`-Prozesse mit Spielordner-Marker und deren Kinder.

**Workflows**
- Kein `pull_request_target`, keine `${{ github.event.* }}` in `run:`. Alle Actions sind auf Commit-SHAs festgelegt.
- Schreibende Schritte laufen nicht bei Pull Requests. Releases entstehen nur von `main` oder Tags.

**Lokale Rechte**
- „Komplett entfernen“ löscht nur Nightforges Orte und folgt den Laufwerkslinks im Prefix (`z:` → `/`) nicht.
- Bildschirmänderungen gelten nur für die Sitzung (`GameDisplay.swift:342`, `.forSession`).
- Schlafsperren werden wieder freigegeben. Es gibt keine Anmeldeobjekte und keine LaunchAgents.
- Die Quarantäne entfernt die App nur bei ihrem eigenen Helfer (`Detached.swift:230`); `install.sh` tut es bewusst
  für die App, siehe H1.
- Rosetta wird über den Admin-Dialog von macOS mit festem Befehl installiert.

**Berichte**
- Die Schwärzung deckt die üblichen Kennungen ab (siehe N7).
- Der Bewertungsbericht enthält nur feste Werte.
- Der Spieletest wird geschwärzt und vor dem Import ins Repo ein zweites Mal geprüft.
