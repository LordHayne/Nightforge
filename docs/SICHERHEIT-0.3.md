# Sicherheitsprüfung vor 0.3.0 (Stand 1.11.2026)

Geprüft: Code des Release-Kandidaten (Integrationszweig plus TV, Spielinfos, GOG, Anti-Cheat), die Skripte in
`scripts/`, die Workflows in `.github/workflows/`, `components/` und `profiles/`. Dazu gezielte Versuche: Archive mit
`..`, absoluten Pfaden und Symlinks gegen `ditto` und `tar`, die Schwärzung an echten Wine-Zeilen, die Rechte der echten
Token-Dateien (nur Dateimodi, keine Inhalte), die Sichtbarkeit von Kommandozeilen für andere Nutzer. Keine GUI gestartet,
kein Spiel, keine Store-Anmeldung, keine Einstellung von macOS geändert.

## Kurzfassung

- **Kritisch: nichts.** Es gibt keinen Weg für Außenstehende, auf einem Mac Code auszuführen, ohne vorher das GitHub-Konto,
  die CI oder einen der gepinnten Upstream-Releases zu übernehmen.
- **Hoch: zwei Funde.** H1 (Problembericht trägt Namen und Anmeldeargumente in ein öffentliches Issue) ist behoben.
  H2 (keine Herkunftsprüfung für Update-ZIP, Komponentenliste und Profile) braucht eine Entscheidung von dir (Schlüssel).
- **Mittel: sechs Funde**, einer davon behoben (M1, Token-Ordner nur für dich lesbar). **Klein: sieben.**
- Zusätzlich auf Wunsch der Roadmap: der Updater meldet jetzt klar, wenn macOS die App aus einem schreibgeschützten Ort
  startet (App Translocation, Disk-Image).

| Nr. | Schwere | Fund | Stand |
|---|---|---|---|
| H1 | hoch | Schwärzung im Problembericht lückenhaft | behoben (`45e6b63`) |
| H2 | hoch | Update-ZIP, `manifest.json`, `profiles.json`, `install.sh` ohne Signatur | Vorschlag 0.3.1, Entscheidung nötig |
| M1 | mittel | Epic-/GOG-Token-Dateien für alle lesbar (644 in 755) | behoben (`c9ceb49`) |
| M2 | mittel | Anmeldecodes in Kommandozeilen (für andere Nutzer des Macs per `ps` sichtbar) | Hinweis, nicht abstellbar |
| M3 | mittel | winetricks und DXMT folgen ungeprüft dem neuesten Upstream, Bot pusht direkt auf `main` | erledigt (`2f53abc`) |
| M4 | mittel | Komponenten-URL: jeder HTTPS-Host erlaubt, Prüfsumme aus derselben Quelle | Vorschlag |
| M5 | mittel | Update-ZIP: kein Abgleich mit GitHubs Digest, Adresse nicht auf das eigene Repo geprüft | Vorschlag (klein) |
| M6 | mittel | Windows-Spiele sehen über `Z:\` den ganzen Mac | Design, Vorschlag |
| – | Wunsch | Updater: klare Meldung bei App Translocation | erledigt (`1e2ddc2`) |

## Hoch

### H1 – Problembericht: Name und Anmeldeargumente gelangen ins öffentliche Issue (behoben)

- Ort: `Sources/Nightforge/GameLog.swift:155` (`redacted`, vor der Korrektur), `Sources/Nightforge/ProblemReport.swift:66`.
- Weg: Der Bericht nimmt Fehlerzeilen aus `wine.log` (`GameLog.errors`) und das Feld „Launch options“ und baut daraus
  den Text eines GitHub-Issues. Geschwärzt wurden nur der Home-Pfad, `users\<name>` mit **einem** Backslash und Steam-IDs.
  1. Wine schreibt Pfade in Meldungen mit **doppelten** Backslashes (`L"C:\\users\\thomas\\AppData\\…"`,
     `Z:\\Users\\thomas\\Library`). Das Muster griff dort nicht: der Kontoname stand im Klartext im Issue
     (vor der Korrektur am Beispiel nachgestellt, die Zeile kam unverändert zurück).
  2. Epics Startargumente (`-AUTH_LOGIN`, `-AUTH_PASSWORD=<Austauschcode>`, `-epicusername=<Name>`, `-epicuserid=<ID>`)
     wurden nicht geschwärzt. Sie landen in `wine.log`, sobald ein Spiel, Wine oder der Absturzdialog die Kommandozeile
     ausgibt (so am 1.11. beobachtet). Der Austauschcode gilt einige Minuten und einmal; Name und ID bleiben.
  3. Tokens (`access_token`, `refresh_token`, `Bearer …`), E-Mail-Adressen und die Steam-Kontonummer in
     `userdata\<Nummer>\…` wurden nicht geschwärzt.
  4. „Launch options“ (frei eingetippt) ging ungeschwärzt in das Issue.
- Behoben: `redacted` erkennt Pfade mit ein oder zwei Backslashes oder Slash (nicht `users\thomasine`), schwärzt die
  Epic-Argumente (auch mit Leerzeichen im Namen, in Anführungszeichen), Tokens und Schlüssel/Wert-Paare, Bearer-Tokens,
  E-Mail-Adressen und `userdata\<Nummer>`; „Launch options“ läuft durch dieselbe Schwärzung. Test: `tests/LaunchHealthTest`.
  Bewusst bleibt stehen, was bei der Diagnose hilft (`-AUTH_TYPE=exchangecode`, `-epicapp=…`, Bibliotheksnamen).
- Rest: Die Schwärzung ist eine Liste bekannter Muster. Ein unbekanntes Format kann durchrutschen; der Bericht öffnet
  die Seite zum Bearbeiten, nichts geht ab, bevor der Spieler „Submit“ drückt (steht schon so im Code-Kommentar).
  Kleine Nebenwirkung: `icon@2x.png` wird als E-Mail-Adresse geschwärzt.

### H2 – Keine Herkunftsprüfung für Update-ZIP, Komponentenliste, Profile und `install.sh` (offen, Entscheidung nötig)

- Ort: `Sources/Nightforge/Updater.swift:20-34, 98-101`, `Sources/Nightforge/Components.swift:20-27, 113-131, 186-216`,
  `Sources/Nightforge/Profiles.swift:309`, `Resources/Info.plist:49-52`, `scripts/install.sh:44-50`,
  `.github/workflows/components.yml:44-45`, `.github/workflows/profiles.yml:106-108`.
- Weg: Alles, was Nightforge ausführt, hängt an GitHub:
  - Das Update-ZIP kommt aus `releases/latest`. Geprüft wird nur, dass die Bundle-ID stimmt und `codesign --verify --deep`
    besteht. Bei einer ad-hoc-Signatur beweist das nur die Unversehrtheit, nicht die Herkunft: jedes ZIP mit
    gleicher Bundle-ID besteht.
  - `components/manifest.json` und `profiles/profiles.json` werden von `raw.githubusercontent.com/…/main/` geladen und
    ungeprüft benutzt. Die SHA-256 in der Liste stammen aus derselben Quelle: sie sichern Übertragung, nicht Herkunft.
    Komponenten laufen **nativ** auf dem Mac (legendary, gogdl, winetricks) oder unter Rosetta (Wine).
  - `install.sh` wird aus `main` geladen und von `curl | bash` ausgeführt.
  - Der Nacht-Bot (`components.yml`, `profiles.yml`) schreibt ohne Prüfung durch einen Menschen direkt auf `main`.
  Wer das GitHub-Konto, einen Workflow oder ein Token mit Schreibrecht übernimmt, führt beim nächsten App-Start Code auf
  allen Macs aus. Das ist die Lage aller GitHub-verteilten Apps ohne Signatur, setzt aber die Übernahme des Kontos
  voraus, daher nicht „kritisch“.
- Geprüft und in Ordnung: ein manipuliertes Archiv schreibt nicht aus dem Zielordner (siehe „Geprüft“).
- Vorschlag (0.3.1, wie in `docs/recherche/gatekeeper.md`):
  1. Ed25519-Signatur über Update-ZIP **und** `manifest.json`/`profiles.json` (CryptoKit, keine Abhängigkeit); der
     öffentliche Schlüssel steht im Programm. Fehlt oder stimmt die Signatur nicht, wird nichts installiert und die
     gebündelte Liste gilt.
  2. Der private Schlüssel liegt **nicht** bei GitHub, sondern auf deinem Mac. Ablauf: CI legt den Entwurf des Releases an,
     du signierst lokal und veröffentlichst. Für die Nacht-Listen genügt anfangs, dass nur noch ein Pull Request sie ändert.
  3. Immutable Releases einschalten (steht in der Recherche).
  Warum nicht jetzt: ohne einen echten Release lässt sich der Weg „App lädt, prüft, ersetzt sich“ nicht ganz durchspielen.
  Eine falsch gesetzte Pflichtprüfung würde bestehende Installationen vom Update abschneiden (nur der curl-Einzeiler bliebe).
- Entscheidung nötig: siehe „Fragen“.

## Mittel

### M1 – Token-Ordner für alle lesbar (behoben)

- Ort: `Sources/Nightforge/Legendary.swift:98` und `:104` (Epic), `Sources/Nightforge/GOGDL.swift:99` (GOG).
- Weg: `~/Library/Application Support/Nightforge/Epic/legendary/user.json` (Zugriffs- und Aktualisierungstoken) und
  `GOG/gogdl/auth.json` lagen mit Modus 644 in Ordnern mit 755. Geschützt hat nur, dass `~/Library` 700 ist. Jeder andere
  Weg an die Dateien (Backup-Programm, Synchronisierung des Ordners, ein zweiter Nutzer nach einer Rechteänderung) hätte
  die Anmeldung geliefert. Epic- und GOG-Anmeldung wird nicht in der Keychain gehalten (legendary/gogdl legen Dateien an).
- Behoben: `PackedApp.keepPrivate` setzt beide Ordner auf 700, bei jedem Start von legendary/gogdl, auch für bestehende
  Installationen. Test: `tests/EpicTest`. Die Dateien selbst behalten ihren Modus; der Ordner sperrt.
- Rest: Prozesse desselben Nutzers lesen die Dateien weiter (nicht zu ändern).

### M2 – Anmeldecodes stehen in Kommandozeilen (Hinweis)

- Ort: `Sources/Nightforge/EpicStore.swift:476` (`legendary auth --code <Code>`), `Sources/Nightforge/GOGStore.swift:327`
  (`gogdl auth --code <Code>`), `Sources/Nightforge/Launcher.swift:561` (Epics `-AUTH_PASSWORD=<Austauschcode>` als
  Argument des Spiels).
- Weg: Unter macOS zeigt `ps -axww` auch Argumente von Prozessen anderer Nutzer (hier geprüft: Argumente von
  `root`-Prozessen sind sichtbar). Ein zweiter Nutzer auf demselben Mac sieht den Code für die Dauer des Prozesses. Die
  Codes gelten einmal und kurz (Epic: Minuten; der Austauschcode des Spielstarts wird beim Start eingelöst), der Spielprozess
  trägt ihn aber so lange, wie das Spiel läuft.
- Vorschlag: nichts zu tun, solange ein Mac nur von einem Menschen benutzt wird. legendary und gogdl nehmen den Code nur
  als Argument; das Spiel braucht Epics Argumente, wie Epics eigener Launcher sie übergibt. Auf der Platte bleibt nichts
  liegen: die Anfrage-Datei von `DetachedProcess` löscht der Helfer sofort nach dem Lesen (`wrapper/nightforge-helper.c:84`).

### M3 – winetricks und DXMT folgen dem neuesten Upstream; Bot pusht direkt auf `main`

- Ort: `components/sources.json` (Einträge `winetricks`, `dxmt`: kein `tag`), `.github/workflows/components.yml:44-45`,
  `scripts/update-components.py:45-76`.
- Weg: Sechs von zwölf Komponenten sind auf einen Tag festgenagelt, vier sind Nightforges eigene Builds (neuester Release des
  eigenen Repos). winetricks (ein Shell-Skript, **nativ als dein Nutzer**
  ausgeführt) und DXMT (DLLs unter Wine) nehmen jede Nacht den neuesten Release ihres Upstreams, rechnen die Prüfsumme neu
  und veröffentlichen die Liste sofort. Ein vergiftetes Upstream-Release erreicht alle Nutzer innerhalb eines Tages, ohne
  dass ein Mensch es sieht.
- Vorschlag: beide wie die sechs anderen mit `tag` festnageln (die Daten, nicht der Code, ändern sich) und neue Versionen über
  einen Pull Request des Bots freigeben (`peter-evans/create-pull-request` oder `gh pr create` im Workflow).
- **Erledigt (`2f53abc`):** Beide sind auf `20260125` (winetricks) und `v0.80` (DXMT) festgenagelt. `update-components.py --propose`
  schlägt die jeweils neueste stabile Version vor; der Workflow legt sie als Pull Request auf dem Zweig `bot/components` ab
  (`gh pr create`) und pusht nie auf `main`. Die Beschreibung nennt jede Version, die sich bewegt, und hebt eine Datei hervor,
  die unter gleicher Version ersetzt wurde. Voraussetzung: die Repository-Einstellung „Allow GitHub Actions to create and approve
  pull requests" (Settings › Actions › General).

### M4 – Komponenten-URL: nur „https“ wird verlangt

- Ort: `Sources/Nightforge/Components.swift:20-27`.
- Weg: `isSafeToInstall` verlangt `https` und einen schlichten Dateinamen, aber keinen Host. Ein veränderter Eintrag im
  online geladenen `manifest.json` kann auf jede HTTPS-Adresse zeigen; die Prüfsumme dazu liefert dieselbe Datei.
- Vorschlag: nur Adressen annehmen, die mit dem Präfix (`https://github.com/<Besitzer>/<Repo>/releases/download/` oder
  `https://raw.githubusercontent.com/Winetricks/winetricks/`) einer Quelle der **gebündelten** Liste beginnen. Neue Quellen
  brauchen dann eine neue App-Version. Hilft nur gegen eine veränderte Liste, nicht gegen ein vergiftetes Release (M3).

### M5 – Update-ZIP: nur Integrität, Adresse nicht eingeschränkt

- Ort: `Sources/Nightforge/Updater.swift:20-34` (Auswahl des Assets), `:101` (`codesign --verify --deep` ohne `--strict`).
- Weg: Die Download-Adresse kommt aus der API-Antwort und wird nicht auf `github.com/LordHayne/Nightforge/releases/download/`
  geprüft. GitHub liefert pro Asset `digest` (`sha256:…`); Nightforge gleicht ihn nicht ab.
- Vorschlag: Adresse auf das eigene Repo beschränken, `digest` vergleichen, wenn vorhanden, `--strict` ergänzen. Alles
  klein, aber auch das gehört zusammen mit H2 in 0.3.1: Ein Abgleich mit dem Digest schützt nur vor Übertragungsfehlern.

### M6 – Windows-Programme sehen den ganzen Mac über `Z:\`

- Ort: Wine-Standard; Nightforge selbst nutzt es (`Sources/Nightforge/Legendary.swift:237`, `-epicovt=Z:\…`).
- Weg: Jedes Windows-Programm (Spiel, Installer, Launcher) läuft ohne Sandbox als dein Nutzer und liest über `Z:` alles,
  was du lesen darfst (`~/.ssh`, Dokumente, Browserdaten). Ein bösartiges Spiel oder ein kompromittiertes Spiel-Update
  kommt so an deine Dateien. Das gilt für Whisky, CrossOver und Heroic genauso.
- Vorschlag: für 0.4. Die `Z:`-Zuordnung im Prefix entfernen oder auf Nightforges Ordner und die Spielebibliotheken
  einschränken (Nightforge nutzt `Z:` selbst, etwa für `-epicovt`; vorher prüfen, was sonst darauf zugreift). In die Anleitung gehört
  der Satz, dass Spiele aus unbekannter Quelle hier nicht abgeschirmt sind.

## Klein

- **K1 – Profil: Zeilenumbruch in `iniSettings`-Werten.** `Engine.swift:1780` (`mergingIni`) schreibt `Schlüssel=Wert` ohne
  Steuerzeichen zu entfernen; ein Wert mit `\n` fügt Zeilen und Abschnitte in die `.ini` **des Spiels** ein. Bleibt in der
  Spielkonfiguration (Pfad ist auf Windows-Wurzel/Spielordner begrenzt). Vorschlag: Steuerzeichen in Schlüssel und
  Wert verwerfen, wie `regString` es tut.
- **K2 – `nightforge://play/<ID>` startet ein installiertes Spiel.** `MacIntegration.swift:53-60`. Eine Webseite kann
  den Link auslösen; der Browser fragt vorher „Nightforge öffnen?“. Die ID ist auf Buchstaben, Ziffern, `-`, `_` geprüft
  (`GameID(key:)`). Folge: höchstens ein Spielstart. Kein Handlungsbedarf.
- **K3 – Steam lauscht auf `*:27036`.** Beim laufenden Steam im Wine-Prefix sichtbar (`lsof`): Remote Play, Valve-Standard,
  im ganzen Netz erreichbar. Vorschlag: In Steams Einstellungen „Remote Play“ aus; Nightforge könnte es beim ersten
  Start in `config.vdf` voreinstellen (prüfen, ob Steam das beim Start überschreibt).
- **K4 – `SteamSetup.exe` wird nicht auf Signatur geprüft.** `Setup.swift:645-651`: HTTPS vom Valve-CDN, Ausführung unter Wine.
  Steam für Mac wird dagegen per Team-ID geprüft (`MacSteam.swift:12, 157`). Windows-Authenticode lässt sich auf dem Mac nicht
  einfach prüfen; Risiko gering (HTTPS, Valve-Host fest im Code).
- **K5 – Profil-`arguments` werden ungefiltert an Steam und Spiel gehängt.** `Launcher.swift:512, 561`. Das
  erreicht nur die Kommandozeile des Spiels beziehungsweise von Steam nach `-applaunch`. Vorschlag: nur Einträge mit
  führendem `-` oder `+` zulassen.
- **K6 – `hide-steam-dock.dylib`:** wird per `DYLD_INSERT_LIBRARIES` in jeden Wine-Prozess geladen (`Engine.swift:1600`). Die Datei
  liegt in `Application Support/Nightforge` (644) und wird bei jedem Start von Nightforge mit der gebündelten verglichen
  und überschrieben (`DockHider.swift:36-58`). Ein Nutzer mit Schreibrecht auf den Ordner hätte ohnehin alles.
  Kein Handlungsbedarf.
- **K7 – `install.sh` prüft die Adresse nicht auf `https://github.com/LordHayne/Nightforge/`.** `scripts/install.sh:47-50` nimmt
  die erste `browser_download_url` mit `Nightforge-…zip` aus der API-Antwort. Gehört zu H2/M5.

## Geprüft und in Ordnung

- **Archive:** `ditto -x -k` (Update-ZIP) und `tar -xf` (Komponenten) mit `../datei`, absolutem Pfad und Symlink-dann-Datei
  versucht (eigene Testarchive in einem leeren Ordner): `ditto` legt `../` und `/tmp/…` **unter** dem Zielordner ab,
  verweigert Schreiben durch einen Symlink; `tar` verweigert `..` und Schreiben durch Symlinks, schneidet das führende `/`
  ab. Nichts wurde außerhalb des Zielordners geschrieben. Das eigene PyInstaller-Entpacken (`PackedApp.unpackOnce`) prüft
  Namen und Link-Ziele (`isInside`).
- **Herkunft der Komponenten:** HTTPS erzwungen (kein `NSAllowsArbitraryLoads` in `Info.plist`, `Components.swift:26`),
  SHA-256 vor dem Entpacken, Entpacken in einen Zwischenordner, der erst danach den Platz einnimmt. Sechs von zwölf
  Komponenten auf feste Tags gepinnt, vier eigene Builds; nur winetricks und DXMT folgen fremdem Upstream (M3).
- **Einschleusen in Befehle:** Die Shell-Skripte (`steam-shutdown.sh`, `steam-priority.sh`, der Neustart im Updater, der Wrapper
  für gogdl) bekommen Spielnamen und Pfade nur als Argumente (`"$1"`…), nie im Skripttext. Die `osascript`-/AppleScript-Texte
  (`Engine.swift:746`, `Setup.swift:391`, `install.sh`) sind Festtexte. Die Verknüpfung (`GameShortcut.swift:67`) enthält nur
  eine ID aus `[A-Za-z0-9_-]`, der Name steht im Plist (serialisiert), im Dateinamen ist `/` ersetzt.
- **Online-Profil:** `registry` nur unter `Software\<Hersteller>` (nicht Microsoft, Classes, Policies, Wine) und `MountedDevices`
  (`Engine.swift:1337`), Werte werden maskiert (`regString`); `winetricks`-Verben nur `[a-z0-9_]` und keine Befehle
  (`Engine.swift:1203`); `fileEdits`, `iniSettings`, `resolution`, `saves` bleiben im Spielordner/Windows-Wurzel
  (Präfix-Prüfung nach `standardizedFileURL`, `..` abgewiesen). Ein Profil kann keine Umgebungsvariablen setzen.
- **Löschen:** Epic und GOG entfernen Ordner nur direkt in den bekannten Spieleordnern (`EpicStore.swift:652-656`,
  `GOGStore.swift:578-585`). IDs werden vor dem Gebrauch als Dateiname auf `[A-Za-z0-9_-]` geprüft.
- **Anmeldefenster:** Epics Code wird nur auf `epicgames.com/id/api/redirect` gelesen und muss alphanumerisch sein; GOGs Code nur von
  `https://embed.gog.com/on_login_success`, begrenzte Zeichen. Beide Fenster speichern nichts (`.nonPersistent()`), die Codes laufen durch eine Zeichen-Whitelist, bevor sie an legendary/gogdl gehen.
- **Steam-Bibliothek `dylib`/CEF:** Nightforge setzt weder `-cef-enable-debugging` noch legt es `.cef-enable-remote-debugging`
  an (Suche im ganzen Repository; dieser Weg ist in `docs/recherche/updates.md` bewusst verworfen). Im laufenden Steam ist die
  Datei nicht vorhanden; Das laufende Steam hielt bei der Prüfung `127.0.0.1:53411/53412` und `*:27036` (K3) offen.
- **Anfrage-Datei von `DetachedProcess`:** enthält die Befehlszeile und das Environment, der Helfer löscht sie sofort nach dem Lesen
  (`wrapper/nightforge-helper.c:84`); der Ordner liegt in `$TMPDIR` (700).

## Fragen an dich

1. **Ed25519 für 0.3.1 (H2):** Soll der Updater (und die Nacht-Listen) künftig nur noch signierte Dateien annehmen, mit einem
   Schlüssel, der auf deinem Mac liegt (nicht bei GitHub)? Das bedeutet: Release als Entwurf, lokal signieren, dann veröffentlichen;
   Schlüsselverlust heißt „nur noch Neuinstallation per Einzeiler“. Ohne Apple-Entwicklerkonto ist das die einzige Herkunftsprüfung.
2. **winetricks und DXMT festnageln (M3)?** Ja = ein Tag in `components/sources.json`, Aktualisierungen kommen als Pull Request.
3. **Z:-Laufwerk (M6):** Soll das in 0.4 eingeschränkt werden, auch wenn manche Spiele-Launcher darüber auf Mac-Ordner zugreifen?

## Prüfsuiten

Nach den drei Commits alle `tests/*Test/run.sh` mit echten Exit-Codes: 47 von 47 `rc=0` (darunter `LaunchHealthTest` mit den neuen
Schwärzungs-Fällen, `EpicTest` mit der Rechteprüfung, `UpdateStateTest` mit der Translocation-Erkennung, `StringsTest`).
`python3 -m pytest -q tests/test_build_profiles.py`: 15 passed.
