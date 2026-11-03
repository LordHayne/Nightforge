# Sicherheitsprüfung vor 0.3.0 (Stand 1.11.2026)

> Den Stand aller Funde der Nachprüfungen vom 3.11.2026 (Review der Probe-Zusammenführung, Signierkette, Sandbox, Profile, Berichte)
> findest du am Ende, unter „Nachprüfungen vom 3.11.2026: Stand je Fund“.

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
| H2 | hoch | Update-ZIP, `manifest.json`, `profiles.json`, `install.sh` ohne Signatur | 0.3.1 gebaut, siehe „Signierte Releases“ |
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
- Entscheidung: „ja, so umsetzen“ (1.11.). Gebaut für 0.3.1, siehe „Signierte Releases“ am Ende.

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

- **K1 – Profil: Zeilenumbruch in `iniSettings`-Werten (behoben, ecf59d4).** `Engine.swift:1780` (`mergingIni`) schreibt `Schlüssel=Wert` ohne
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
- **K5 – Profil-`arguments` werden ungefiltert an Steam und Spiel gehängt (behoben, e5197f1).** `Launcher.swift:512, 561`. Das
  erreicht nur die Kommandozeile des Spiels beziehungsweise von Steam nach `-applaunch`. Vorschlag: nur Einträge mit
  führendem `-` oder `+` zulassen.
- **K6 – `hide-steam-dock.dylib`:** wird per `DYLD_INSERT_LIBRARIES` in jeden Wine-Prozess geladen (`Engine.swift:1600`). Die Datei
  liegt in `Application Support/Nightforge` (644) und wird bei jedem Start von Nightforge mit der gebündelten verglichen
  und überschrieben (`DockHider.swift:36-58`). Ein Nutzer mit Schreibrecht auf den Ordner hätte ohnehin alles.
  Kein Handlungsbedarf.
- **K6a – Erst prüfen, dann auspacken: zwei Lesevorgänge (Review H).** Updater (`Updater.swift`, Signatur, dann
  `ditto`), Komponenten (`Components.swift`, SHA-256, dann `tar`) und `install.sh` (Ed25519, dann `ditto`) lesen das
  Archiv zweimal. Wer als derselbe Nutzer zwischen den beiden Lesevorgängen die Datei tauscht, bekäme ein ungeprüftes
  Archiv ausgepackt. Die Marke `.sha256` einer installierten Komponente nennt außerdem die erwartete Prüfsumme, nicht
  eine später nachgerechnete. Beides setzt einen Prozess voraus, der als derselbe Nutzer schon schreiben kann, und
  der hätte ohnehin alles (wie bei K6). Restrisiko, bewusst so gelassen. Abhilfe wäre, aus einem Ordner mit Rechten
  700 auszupacken, in den nur Nightforge schreibt.
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

## Signierte Releases (ab 0.3.1)

Was Nightforge aus dem Netz holt und ausführt, nimmt es nur noch mit deiner Unterschrift an: das Update-ZIP,
`components/manifest.json`, `profiles/profiles.json` und `profiles/agw.json` (was das AppleGamingWiki sagt; es legt
die Reihenfolge fest, in der ein Spiel probiert wird). Neben jeder Datei liegt eine `.sig` (Ed25519, eine Zeile je
Signatur). GitHub hat keinen privaten Schlüssel: Wer das Konto oder einen Workflow übernimmt, kann Dateien ändern,
aber nicht signieren.

- **Zwei Schlüssel.** Ihre öffentlichen Hälften stehen in `Sources/Nightforge/SigningKeys.swift`, eine gültige
  Signatur von einem der beiden genügt. Der **Hauptschlüssel** liegt in deinem Anmelde-Schlüsselbund
  („Nightforge signing key“). Der **Ersatzschlüssel** liegt nur offline (Passwort-Manager oder USB-Stick), nie auf dem Mac.
- **Ohne gültige Signatur passiert nichts.** Ein Release ohne `.sig` wird nicht angeboten. Ein ZIP, das nicht zur
  Signatur passt, wird nicht entpackt („nicht korrekt signiert“). Ein signiertes, aber älteres Release wird abgelehnt.
  Eine unsignierte Online-Liste bleibt draußen: Es gilt die zuletzt signierte, sonst die mitgelieferte. Dazu steht in
  Einstellungen › Über eine ruhige Zeile. Eine Liste, die 0.3.0 noch ungeprüft gespeichert hat, zählt ebenfalls nicht.
- **Der Code:** `Signature.swift` (Prüfung, CryptoKit), `Updater.swift`, `Components.swift`, `Profiles.swift`. Die Skripte
  bauen `scripts/signing-tool.swift` aus genau diesen Dateien und prüfen deshalb dasselbe wie die App. Tests:
  `tests/SignatureTest` und `tests/test_signing_scripts.py` (Schlüsselbund, Zwischenablage und GitHub sind dort Attrappen).

**Schritt für Schritt** (Schlüssel, erstes Release, Nacht-Listen, Schlüsselverlust): `docs/SIGNIEREN.md`. Hier
stehen die Gründe und die Einzelheiten.

Kurz: Der Hauptschlüssel liegt im Schlüsselbund und fragt bei jedem Signieren nach dem Passwort, der Ersatz liegt
offline. `release.yml` legt nur einen Entwurf an, `scripts/sign-release.sh` signiert und veröffentlicht. Die
öffentlichen Schlüssel stehen einzig in `SigningKeys.swift`.

### Die Nacht-Listen

Beide Bots (`components.yml`, `profiles.yml`) schlagen Änderungen nur noch als Pull Request vor (`bot/components`,
`bot/profiles`) und pushen nie auf `main`.

1. Den Pull Request lesen.
2. `scripts/sign-lists.sh bot/profiles` (bzw. `bot/components`). Das Skript holt den Zweig in einen eigenen Ordner,
   signiert nur Listen, deren Signatur nicht mehr passt, und pusht die `.sig` auf den Zweig. Deine Arbeitskopie bleibt
   unberührt. Vom Zweig läuft nichts: Das Werkzeug, das den privaten Schlüssel bekommt, baut das Skript aus deinem
   Checkout. Einen Zweig, der mehr ändert als die Listen, ihre `.sig` und `components/sources.json`, signiert es
   nicht, ebenso wenig einen, dessen Signier-Quellen von deinen abweichen. Git führt dort keine Hooks aus.
3. Mergen, wenn der Check **Signatures** grün ist, mit dem Befehl, den das Skript ausgibt (`--match-head-commit`). Hat
   der Bot den Zweig inzwischen neu geschrieben, merged GitHub dann nicht, und du signierst den neuen Stand.

`bot/profiles` bringt neben `profiles.json` auch `agw.json`. Das Skript signiert jede Liste, die sich geändert hat.

**Wer signiert wann?** Immer du, auf deinem Mac, **vor** dem Merge, auf dem Zweig des Pull Requests. Der Merge bringt
Liste und `.sig` zusammen nach `main`, und von dort lädt die App beide. Ein CI-Secret mit dem Schlüssel gibt es
absichtlich nicht. Sonst könnte jeder, der einen Workflow ändern oder ein Token stehlen kann, auch signieren, und die
Signatur sagte nichts mehr. Der nächtliche Lauf selbst hat nur die Rechte, die er braucht. Das Bauen und Prüfen
(auch bei Pull Requests) liest nur. Den Zweig `bot/profiles` und seinen Pull Request schreibt ein eigener Job. Nur
der Zeitplan-Job darf Workflows wieder einschalten. Vorher weist der Prüfschritt Listen mit unsicheren
`dllOverrides` oder `arguments` ab (bloße DLL-Namen, Wines Reihenfolgen, keine Pfade aus dem Spiel heraus, keine
Steuer- oder Sonderzeichen), dann entsteht gar kein Pull Request.

Ein Merge ohne Signatur schadet niemandem: Die Apps behalten ihre Liste, und der Check auf `main` wird rot.
Komponenten wie `enginefix` brauchen keine eigene Signatur. Das signierte `manifest.json` nennt ihre SHA-256, und die
App prüft jedes Paket dagegen, bevor sie es auspackt.

### Übergang von 0.3.0

0.3.0 kennt keine Schlüssel und prüft nicht. Sein Updater nimmt die erste Datei auf `.zip`, also das ZIP und nie die
`.sig`, in jeder Reihenfolge (getestet). 0.3.0 kommt also ganz normal auf 0.3.1, erst danach gilt die Pflicht.

`install.sh` prüft ab dem Merge auf `main` selbst. Es lädt die `.sig` zum ZIP und die öffentlichen Schlüssel aus
`SigningKeys.swift` auf `main` und prüft vor dem Auspacken mit Ed25519. Das läuft in Perl, weil jeder Mac Perl hat:
LibreSSL kann kein Ed25519, Python und Swift brauchen die Entwicklerwerkzeuge. Ohne gültige Signatur installiert
es nichts und bittet um ein Issue. Bis `v0.3.1` erscheint, ist `releases/latest` noch 0.3.0, und das hat keine
Signatur. Darum nimmt `install.sh` genau das ZIP von 0.3.0 über seine SHA-256 an (die GitHub für das unveränderliche
Release angibt), sonst nichts Unsigniertes. Ein mit `NIGHTFORGE_ZIP` übergebenes lokales ZIP prüft es nicht.

Eine Liste, die 0.3.0 ohne `.sig` gespeichert hat, zählt in 0.3.1 nicht. Bis die erste signierte Liste da ist,
gilt die mitgelieferte, und die kann älter sein. Dann räumt Nightforge keine installierten Komponenten weg
(`removeUnusedComponents` läuft nur nach einer signierten Liste), sonst ginge eine neuere Engine verloren. Den
0.3.0-Cache einmal gelten zu lassen hieße, einer unsignierten Datei zu trauen. Das Risiko liegt deshalb nur in 0.3.1 selbst: Ist dort die Prüfung kaputt, kommen seine
Spieler nur noch per Einzeiler weiter. Darum gilt diese Reihenfolge vor dem Tag `v0.3.1`:

1. Schlüssel erzeugen, `SigningKeys.swift` committen.
2. Den Zweig mergen und die Listen auf `main` signieren. Sonst zeigt jede 0.3.1 sofort die Zeile „nicht signiert“
   und bleibt bei ihrer mitgelieferten Liste.
3. Den Test-Release durchspielen (nächster Abschnitt).
4. Erst dann `v0.3.1` taggen und signieren.

### Test-Release: „App lädt, prüft, ersetzt sich“

Ein Tag mit Zusatz (`v0.3.1-rc.1`) wird ein **Prerelease**. Weder die App (`/releases/latest`) noch `install.sh`
bieten ihn an, kein Spieler sieht ihn. Nur ein Mac, auf dem `UpdateTestRelease` gesetzt ist, fragt gezielt nach.

1. `v0.3.1-rc.1` und `v0.3.1-rc.2` auf `main` taggen (gleicher Commit geht), beide mit
   `scripts/sign-release.sh <tag> --publish` signieren.
2. rc.1 mit dem Installationsskript installieren, das dabei die Signatur prüft:
   `NIGHTFORGE_RELEASE=https://api.github.com/repos/LordHayne/Nightforge/releases/tags/v0.3.1-rc.1 bash scripts/install.sh`.
3. `defaults write io.github.lordhayne.nightforge UpdateTestRelease v0.3.1-rc.2`, Nightforge neu starten.
   Erwartet: „Auf 0.3.1-rc.2 aktualisieren“ → laden, prüfen, ersetzen, Neustart; Einstellungen › Über zeigt rc.2. In
   Einstellungen › Über steht keine Zeile „nicht signiert“.
4. Gegenproben, beide auf rc.2:
   - `v0.3.1-rc.3` taggen und **ohne** Signatur veröffentlichen (`gh release edit v0.3.1-rc.3 --draft=false
     --prerelease`), `UpdateTestRelease` auf `v0.3.1-rc.3`. Erwartet: kein Update-Angebot, in `wine.log` die Zeile
     „has no signature“. Dasselbe `install.sh` wie in Schritt 2 mit `…/tags/v0.3.1-rc.3` bricht mit „isn't signed
     by its maintainer“ ab und lässt rc.2 stehen.
   - `v0.3.1-rc.4` taggen und vor dem Veröffentlichen die `.sig` von rc.2 als `Nightforge-0.3.1-rc.4.zip.sig`
     hochladen (`gh release upload`), `UpdateTestRelease` auf `v0.3.1-rc.4`. Erwartet: das Update wird angeboten, beim
     Installieren kommt „nicht korrekt signiert“, Nightforge bleibt auf rc.2.
5. `defaults delete io.github.lordhayne.nightforge UpdateTestRelease`. Die Prereleases kann man danach löschen.
6. Nach dem echten `v0.3.1`: rc.2 bietet 0.3.1 von selbst an (ein Release ist neuer als seine Tests). Dass 0.3.0
   auf 0.3.1 kommt, zeigt eine 0.3.0 auf dem MacBook (nicht auf dem Mac mini, der ist kein Testgerät).

### Wenn ein Schlüssel verloren geht

Die Schritte stehen in `docs/SIGNIEREN.md` › 8. Der Grund für das doppelte Signieren nach einem neuen
Hauptschlüssel: Die installierten Apps kennen nur den alten Haupt- und den Ersatzschlüssel und nehmen die
Ersatz-Signatur. Apps mit dem neuen Release nehmen die neue Haupt-Signatur. Sind beide Schlüssel weg, erreicht kein
Update die installierten Apps mehr, dann hilft nur die Neuinstallation per Einzeiler.

### Was bleibt

- `install.sh` läuft per `curl | bash` direkt von `main` und lädt die Schlüssel von dort. Es schützt vor fremden
  oder ausgetauschten Release-Dateien, nicht vor jemandem, der auf `main` schreiben kann: Der ändert Skript und
  Schlüssel zusammen. Die App ist stärker, ihre Schlüssel sind eingebaut. Dagegen helfen Regeln auf GitHub und ein
  Anker außerhalb von GitHub (beides in `docs/TODO.md`).
- `codesign --verify` im Updater prüft ohne Anforderung (`-R`): Die Releases sind ad hoc signiert, eine Anforderung
  gäbe es erst mit einer Developer-ID. Woher die App stammt, belegt die Ed25519-Signatur davor.
- Das DMG ist nicht signiert (Ad-hoc wie bisher, es dient nur der Hand-Installation).
- Ein signiertes, älteres Listen-Exemplar (aus der Git-Geschichte zurückgelegt) nimmt die App nicht mehr. Jede Liste
  trägt in den signierten Bytes ihren Stempel `generated`. Ist die Online-Liste älter als die zuletzt angenommene,
  bleibt diese, und Einstellungen › Über sagt es. `scripts/sign-lists.sh` signiert keine geänderte Liste, deren
  Stempel nicht neuer ist als der auf `main`. Offen bleibt der erste Abruf: Ein Mac ohne gespeicherte Liste nimmt
  auch eine alte, signierte (für Profile gilt dann noch die neuere mitgelieferte).
- Was Nightforges eigene Builds enthalten (Grafik, Gamepad, `enginefix`), baut GitHub Actions. Deine Signatur über
  `manifest.json` bestätigt die Prüfsumme dieses Builds, nicht seinen Inhalt.

## Nachprüfungen vom 3.11.2026: Stand je Fund

Die Probe-Zusammenführung für 0.3.1 (`claude/staging-031`, Stand 4f0d00a) wurde am 3.11. mehrfach geprüft: von der Sitzung code-review
(Bericht `docs/REVIEW-STAGING-031.md` auf `claude/review-staging-031`, dazu `docs/CODE-PRUEFUNG.md` auf `claude/code-review-plan-2f9ae5`) und
von unabhängigen Durchsichten (Signierkette, Sandbox, Profile, Berichte, ein Review anderer Modelle). **Wer weiter prüft, fange hier an: Was hier
steht, ist bekannt.** Jede Zeile nennt den Fund und den Commit, der ihn behebt (der Zweig steht in Klammern, alle Commits stehen auf
`claude/staging-031`), oder warum er offen bleibt. „Behoben“ heißt gebaut und mit einem Test, nicht live am laufenden Mac gesehen, wo
nichts anderes steht. Der Schalter der Sandbox (`wineSandbox`) ist **aus**, die Sandbox-Zeilen gelten also für den Tag, an dem er an geht.
Die Funde des Audits vom 3.11. (H1, M1–M4, N1–N9) stehen in `docs/AUDIT-SICHERHEIT.md`.

### 1. Review der Probe-Zusammenführung, erster Durchgang (H1–H3, M1–M10, L1–L10)

| Nr. | Fund | Stand |
|---|---|---|
| H1 | Der Wineserver einer Sitzung startete außerhalb der Sandbox (`importRegistry`, `installWineMono`) | behoben 01e234d (`wine-sandbox`): jeder Wine-Start geht über `WineSandbox.process`, ein Test liest die Quellen. Unitys Play!-Helfer 5dd6d71 (nur auf Staging, gehört zu `unity-play`); das Beenden-Skript 3d257f1 (unten) |
| H2 | Von innen änderbar, was Nightforge später ohne Sandbox ausführt; das Profil lag als Datei im Datenordner | behoben a4d0cdd (`wine-sandbox`): `Components/`, Helfer-App, Dock-Bibliothek, Skripte, D3DMetal, GOG-Mac-Spiele, die App und die Anfragen des Helfers sind innen nur lesbar, das Profil geht als Text über argv. Nachgebessert: 77e0bba, 76f1b50, ae198a1 (unten) |
| H3 | Ohne den Helfer der Sandbox startete Wine still ohne Sandbox | behoben d493cd4 (`wine-sandbox`): `HelperMissing`, Wine startet nicht |
| M1 | Eine ältere, richtig signierte Liste wurde angenommen | behoben d36f7b1 (`signed-updates`): Stempel `generated` in den signierten Bytes. Danach B 4584ecf, F 3f510f9, N5/N6 9f7c5ec. Offen: der erste Abruf eines Macs ohne gespeicherte Liste nimmt auch eine alte signierte (für Profile gilt dann noch die mitgelieferte) |
| M2 | `install.sh`: Schlüssel und Skript kommen aus demselben Repository | die Texte stimmen jetzt (0fa0330, `signed-updates`): Schutz vor ausgetauschten Release-Dateien, nicht vor Schreibrecht auf `main`. Offen: Regeln auf GitHub und ein Anker außerhalb von GitHub (`docs/TODO.md`) |
| M3 | `ps` hängt oder fehlt, und die leere Liste heißt „nichts läuft“ | 69ad783 (`h1-h3-031`), unvollständig; der Rest steht unter N1, N3, N4, N7 und den Zusatzfunden |
| M4 | `SteamProgram` fasst die Starteinstellung des Spielers an, ohne Sicherung | behoben d92494f (`steam-program-m4`): nur Zeilen, die Nightforge selbst schrieb (`launchoptions-written.json`), Kopie `localconfig.vdf.nightforge-backup`, nur bei bekannt ausgeschaltetem Steam. Nachbesserung 49f721f (Zusatzfund 4) |
| M5 | `sign-release.sh` bestätigt nur, was im Entwurf liegt | behoben ca3d748 (`signed-updates`): zeigt SHA-256 der ZIP, den Commit des Tags und den Wrapper-Vergleich und fragt. `wrapper.yml` schlägt die neu gebaute `.exe` per Pull Request vor |
| M6 | Perl-Ed25519 in `install.sh` ohne Gegenprobe | behoben 435e399 (`signed-updates`): RFC 8032 §7.1 und ungültige Signaturen, je gegen CryptoKit verglichen |
| M7 | Das Beenden per Apple Event antwortet, bevor Nightforge sich beendet | gebaut 38b4418 (`quit-always`). Offen: Live-Test (`osascript … quit` mit offenen Einstellungen, Abmelden) |
| M8 | Eine Frage von macOS hielt den Start ohne Ende | behoben a9a7b5e (`system-prompt-curtain`): nach drei Minuten geht der Start ohne sie weiter |
| M9 | Zwischengespeicherte Listen von 0.3.0 werden ignoriert | gewollt (593e80e, `signed-updates`): `removeUnusedComponents` läuft nur nach einer signierten Liste, der 0.3.0-Cache zählt nicht (eine unsignierte Datei gälte sonst) |
| M10 | Kurzbefehle: der erste Klick nach dem Update, der Schlüssel im Klartext in den Skripten | Hinweis 324d46b (`audit-low`); der Schlüssel entsteht mit Modus 600 von Anfang an (9ba69ab). Bleibt: Er steht im Klartext im Skript der Spiel-Apps, das Bedrohungsmodell ist „eine Webseite kann ihn nicht lesen“; mit der Sandbox sind die Apps innen gesperrt (76f1b50) |
| L1 | Die `LastPlayed`-Regel blendet ein kurz gespieltes, danach aktualisiertes Spiel aus „Weiterspielen“ aus | offen, nur Anzeige |
| L2 | `folderSize` liest zwei Eigenschaften mehr je Datei | offen, nur Leistung (läuft nicht auf dem Hauptthread) |
| L3 | D3DMetal: Prüfsummen für 3.0/4.0b3 nicht gegen Apples Images prüfbar; `hdiutil` ohne Frist | offen, Hinweis. Jede neue Toolkit-Fassung wird abgelehnt, bis Nightforge sie kennt |
| L4 | Hauptthread: `DetachedProcess.run()` bis 20 s synchron | teilweise: Steam starten geht nicht mehr über den Hauptthread (00a03bf); die übrigen Stellen stehen offen in `docs/CODE-PRUEFUNG.md` |
| L5 | Swift 6.3/6.4 | offen bis zum Lauf der CI mit 6.3; im Diff stand kein Konstrukt, das nur 6.4 kennt |
| L6 | Signatur ohne Zweckbindung (ein Schlüssel für ZIP und Listen, kein Präfix) | offen; bei den heutigen Inhalten (ZIP, JSON) nicht zu verwechseln |
| L7 | Beenden während „Entfernen“ steht nur in `wine.log` | offen, Hinweis |
| L8–L10 | `GameShortcut.addKey`, `Updater` (`notNewer`, `releaseURL`), `.option` in `SteamProgram` | in Ordnung, kein Handlungsbedarf |

### 2. Nachtrag (N1–N14)

| Nr. | Fund | Stand |
|---|---|---|
| N1 | Ein Ausfall von `ps` ließ ein laufendes Spiel in den ersten Sekunden als „nicht da“ gelten (Rückstufung der Engine, zweiter Start) | behoben 7034fc7 (`review-n-031`): eine alte Liste sagt nur „da“, nie „weg“ (`GameProcesses.Presence`, `FirstSecondsWatch`) |
| N2 | Die Pfadregeln der Sandbox schützen die Elternordner nicht (umbenennen, dann lesen) | behoben ae198a1 (`wine-sandbox`), mit dem echten Helfer nachgewiesen |
| N3 | `SteamStartCheck` urteilte ohne Prozessliste „läuft nicht“ | behoben fd9b821 (`review-n-031`) |
| N4 | Der Vorhang fragte `ps` zweimal je Blick | behoben 260c2de (`review-n-031`) |
| N5 | Ein Stempel aus der Zukunft sperrt den Kanal einer Liste | behoben 9f7c5ec (`signed-updates`), auch `sign-lists.sh` lehnt ihn ab |
| N6 | Komponenten nur gegen die gespeicherte Liste verglichen | behoben 9f7c5ec |
| N7 | Weitere Stellen mit „leere Liste heißt nichts läuft“ (Engine-Wechsel, msync) | behoben f39b3b1 (`review-n-031`). Bleibt: `DockHider`, `Setup`, `SteamSwitch` lesen `isSteamRunning` zur Anzeige oder zum Warten, `false` ist dort das Vorsichtige |
| N8 | Sandbox: Rennen beim Umschalten, Steam beim Wechsel ungefragt beendet, Hauptthread | behoben 5300f05 (`wine-sandbox`) |
| N9 | Apple Event: die Antwort geht vor `terminate` hinaus | offen, Live-Test (wie M7) |
| N10 | Der Problembericht ersetzt den Inhalt der Zwischenablage (Universal Clipboard) | offen, bewusst: der Text ist geschwärzt, der Hinweis sagt es |
| N11 | `SteamProgram`: die Sicherung wird nie erneuert, ungültiges UTF-8 wird ersetzt, die Rechte der Datei gehen beim atomaren Schreiben verloren | offen, Hinweis; die Sicherung ist der Grund, es dabei zu lassen |
| N12 | `Engine.lastSteamStart` ohne Sperre | behoben 22d800b (`review-n-031`) |
| N13 | `wrapper.yml`: Hashes der Actions offline nicht prüfbar; ein Pull Request von `GITHUB_TOKEN` löst keine Workflows aus | offen, Hinweis (bei `components.yml` und `profiles.yml` genauso) |
| N14 | `sign-release.sh`: der Digest-Vergleich entfällt, wenn GitHub keinen nennt | gewollt: er prüft die Übertragung, den Inhalt prüft der Mensch |

### 3. Zusatzfunde der zweiten Durchsicht und das externe Review der Robustheit

| Fund | Stand |
|---|---|
| Zusatz 1: Epic/GOG: die zuletzt bekannte Menge laufender Downloads begann leer, nach einem Neustart mit `ps` aus startete ein zweiter Download desselben Spiels | behoben 2b5596a (`review-n-031`): `nil` entscheidet nichts |
| Zusatz 2: ein `ps`, das gar nicht startet, wurde bei jedem Blick neu versucht | behoben 75bb9ce: die Pause gilt auch dafür |
| Zusatz 3: Steam starten lief über den Hauptthread (`showSteamWindow`, `openSteam`, Setup, `addDemoLicense`) | behoben 00a03bf: `Engine.startSteamOffMain`, ein Test liest die Quellen |
| Zusatz 4: `SteamProgram.apply` behielt einen vorab notierten Wert, auch wenn kein Schreiben gelang | behoben 49f721f: beansprucht wird nur, was eine Datei wegen dieses Laufs hält |
| Extern 1: `BinaryKV.parse` ohne Tiefengrenze, `appinfo.vdf` liegt im Prefix (Stapelüberlauf bei jedem Scan) | behoben fb48a4c: 64 Ebenen |
| Extern 2: `URL(string:)!` im Link eines Spiels, GOG-IDs ungeprüft | behoben adea626: Link aus Teilen gebaut, GOG nimmt nur Produkt-IDs, `create` verweigert unbrauchbare |
| Extern 3: ein Play-Link galt mit beliebig vielen Pfadsegmenten | behoben 26611c6: genau eins |
| Extern 4: Rennen beim Anlegen des Schlüssels der Spiel-Apps | behoben b0d6863. Offen für die Sandbox: die Zwischendatei `shortcut-key.<UUID>.tmp` im Datenordner besteht einen Augenblick (nur für den Spieler lesbar); die Regel sperrt nur den Namen `shortcut-key`. Ein Präfix-Muster fehlt noch |

### 4. Signierkette, externes Review A–H (`signed-updates`)

| Nr. | Fund | Stand |
|---|---|---|
| A | `sign-lists.sh` baute das Signierwerkzeug aus dem Zweig, den es signiert; der private Schlüssel geht in dieses Werkzeug | behoben 907161e: gebaut aus dem eigenen Checkout. Ein Zweig, der mehr ändert als Listen, ihre `.sig` und `components/sources.json`, oder andere Signierquellen hat, wird nicht signiert |
| B | `ProfileStore` verglich die mitgelieferte Liste ohne den Schutz vor Stempeln aus der Zukunft | behoben 4584ecf |
| C | Der Updater prüfte nur „neuer als diese Kopie“: ein signiertes ZIP unter einem anderen Tag ging durch | behoben 400bd06: die Version im ZIP muss die des Tags sein. Bleibt: Wer das Repository beschreiben kann, hält Updates zurück (ein falsches „latest“, Releases löschen); Regeln für Tags (`docs/TODO.md`) |
| D | `signatures.yml` prüfte Pull Requests mit dem Prüfer und den Schlüsseln des Pull Requests selbst | behoben 5fdcbbb: Prüfer und Schlüssel von der Basis, rot, wenn der Pull Request sie ändert |
| E | „Eine geänderte Liste braucht einen neueren Stempel“ galt nur für Zweige | behoben 407f122: auch auf `main`, gegen den Stand beim letzten Signieren |
| F | Stempel wurden als Text verglichen (Zeitzone, Sekundenbruchteile) | behoben 3f510f9: als Datum |
| G | Eingaben der CI nicht an Hashes gebunden; `components.yml` lief mit Schreibrechten | behoben a71421b: Tarball von cabextract per SHA-256, dmgbuild mit `--require-hashes`, Rechte je Job |
| H | Erst prüfen, dann auspacken: zwei Lesevorgänge | als Restrisiko K6a notiert (83d10d2): es braucht einen Prozess desselben Benutzers. Abhilfe wäre ein Ordner mit 700 zum Auspacken |

Offen: Die Änderungen an `components.yml`, `release.yml`, `signatures.yml` und `tools.yml` sind nur lokal geprüft (als YAML gelesen); auf GitHub ist keiner
gelaufen.

### 5. Sandbox: Beenden-Skript, Caches, Steuerdateien (zweites Review der Sandbox)

| Fund | Stand |
|---|---|
| `steam-shutdown.sh` startete Steams `-shutdown` außerhalb der Sandbox (ein verändertes `steam.exe` im Prefix lief dann ohne sie, und die Sitzung blieb unsichtbar für `settleSession`) | behoben 3d257f1 (`wine-sandbox`) |
| `launchoptions-written.json`, die Einstellungen mit dem Schalter und `shortcut-key` waren von innen änderbar oder lesbar. `defaults write` aus der Sandbox schreibt über cfprefsd: nur beide Verbote zusammen (Einstellungen der Domäne und Datei) halten | behoben 77e0bba. Die Einstellungen anderer Programme bleiben schreibbar, damit Wines eigene nicht stören |
| Die Caches der signierten Listen (`profiles.json`, `agw.json`, je mit `.sig`) waren löschbar; `~/Applications/Nightforge Games` war nur lesbar, die Skripte tragen den Schlüssel im Klartext | behoben 76f1b50: die Caches innen nur lesbar, der Ordner der Spiel-Apps ganz gesperrt |
| Ein Ordner über einem geschützten Ort ließ sich umbenennen | behoben ae198a1 (N2) |
| `Epic/destinations.json` (Ziel je Epic-Spiel) und `GOG/installed.json` (Pfade der GOG-Spiele) waren von innen beschreibbar: ein Programm in der Sandbox konnte dort Pfade ändern, nach denen sich Nightforge später richtet | behoben 5cc5402 (`wine-sandbox`): alles im Datenordner außerhalb von `Prefix/`, was nur Nightforge schreibt, ist innen nur lesbar (Epic und GOG: Bibliothek, Größen, Downloads, Ziele, Installationen, Spielzeiten, Logs; dazu `GameInfo/`, `GameTests/`, `Backups/`, `Logs/`, Steams `packages/`). Wines Ausgabe erreicht `wine.log` über ein draußen geöffnetes Handle. **Offen für den Live-Test:** `GOG/Redist` (Wine führt dort die Installer aus) und `GOG/Support/<id>` (GOGs Installationsskripte schreiben dorthin) bleiben beschreibbar, wie `Prefix/` und legendarys `tmp` |
| **Offen:** die Zwischendatei `shortcut-key.<UUID>.tmp` (siehe Extern 4) | eine Regel mit Präfix |
| **Offen:** der Schalter bleibt aus, bis Steam, Spiele, Epic, GOG, Controller und der Spielmodus mit der Sandbox zusammen live gelaufen sind | `docs/TODO.md` |

### 6. Profil-Grenzen, externes Review der Profile (Punkte 1–8, K1)

| Nr. | Fund | Stand |
|---|---|---|
| 1 | Eine Dateiänderung, deren Ersetzung ihr Suchmuster enthält, ließ die Datei bei jedem Start wachsen | behoben 18c92d2 (`profile-limits`) |
| 2 | `.ini`-Werte, Abschnitte und Schlüssel konnten Zeilen und Abschnitte einfügen (K1) | behoben ecf59d4 |
| 3 | Winetricks-Verben für Windows-Versionen und andere Einstellungen liefen im gemeinsamen Prefix | behoben b149a87: 19 Windows-Versionen und die übrigen Einstellungen stehen auf der Liste |
| 4 | Die Auflösungsdatei wurde durch einen Link des Spiels nach außen geschrieben | behoben 0daa1b8 |
| 5 | `SaveTransfer.windowsRoot`: ein Ordner `Prefix-evil` neben dem Prefix zählte als innen | behoben 05c16ce |
| 6 | Die App prüfte `dllOverrides` und `arguments` nicht selbst (nur die CI) | behoben e5197f1 |
| 7 | `frameLimit` und `vulkanSamplers` ohne Grenze (`-1` wurde als `%u` gelesen) | behoben 63053eb |
| 8 | Das gewählte Programm lag nur dem Pfad nach im Spielordner | behoben 6e8dc40 |
| – | Die Profil-CI prüfte `fileEdits`, `iniSettings`, `resolution`, `saves` und `mac.json` nicht | behoben 6ec6878 (`profile-ci`) |

Offen: Die CI übernimmt die strengeren Regeln der App noch nicht (15 weitere winetricks-Verben, Grenzen für `frameLimit`, `vulkanSamplers` und die Zahl der
DLL-Overrides). Ein Widerspruch ist es nicht: Die App lässt aus oder begrenzt, was die CI durchlässt.

### 7. Berichte und Schwärzung

| Fund | Stand |
|---|---|
| Audit M3: der Problembericht trug Fehlerzeilen in der Adresse | behoben ce91765 (`report-url-m3`) |
| Audit N7: Lücken in der Schwärzung (Laufwerke, Rechnername, GOG-Kennungen, Kontoname) | behoben b87dee7 |
| Berichte des Spieletests: die Notizen des Laufs ungeschwärzt, die Prüfung vor dem Import kannte zu wenig und zu viel (Teilwörter des Rechnernamens) | behoben 44f09e8 (`game-test-fixes`): alles, was `GameLog.redacted` noch ändern würde, hält den Import an; nur bekannte Apps beim Namen |
| Audit N6: der Bericht im öffentlichen Repo nennt die installierten Spiele | offen, entscheidet der Nutzer |
| Die Schwärzung ist eine Liste bekannter Muster | bleibt; ein unbekanntes Format kann durchrutschen. Nichts geht ab, bevor der Spieler absendet |

### 8. „Komplett entfernen“, externes Review des Löschens und Beendens

| Nr. | Fund | Stand |
|---|---|---|
| 1 (mittel) | Die Sicherung der Spielstände ließ Spiele aus, die neben ihrem Programm im eigenen Ordner speichern (`steamapps/common` im Prefix); der Prefix ging danach mit ihnen weg, obwohl das Blatt „Spielstände werden kopiert“ sagt | behoben 7bd0488: `gameFolderSaves` nimmt Steam Clouds Regeln mit der Wurzel `gameinstall` und die Profile der Spiele im Prefix und kopiert die genannten Dateien einzeln, nicht das Spiel. Bleibt: Epic- und GOG-Spiele im Prefix (`Program Files\Epic Games`, `GOG Games`) – Nightforge kennt für sie keine Regeln, ihr Ordner geht mit; Spiele auf einem externen Laufwerk werden nicht gelöscht |
| 2 (niedrig) | Der Sicherungsordner hieß nach dem Datum allein und wurde vor dem Kopieren gelöscht: eine zweite Entfernung am selben Tag löschte die erste Sicherung, ein Fehler danach ließ nichts übrig | behoben e71ebde: `Nightforge Saves/<Datum-Uhrzeit>`, bei Gleichheit `-2`, nichts wird vorher entfernt, ein fehlgeschlagenes Kopieren nimmt den begonnenen Ordner weg und bricht ab |
| 3 (niedrig) | Ohne Pid-Datei beendete `endScripts` jeden bash, in dessen Befehlszeile der Pfad des Skripts stand (auch `bash -c … <Pfad>`) | behoben 72bd3c0: das Skript muss das erste Argument von bash sein |
| – | Orte außerhalb der App (Test, der den echten Ort selbst nennt) | behoben 10b9f12 (`namesTheRealApp`) |

### 9. Was offen ist und warum

- **Live-Tests, die noch fehlen:** der Schalter der Sandbox mit allem zusammen, darunter die zwei Ordner, die innen beschreibbar bleiben (`GOG/Redist`, `GOG/Support/<id>`; 5cc5402); M7/N9 (Apple Event beim Beenden und Abmelden).
- **Auf GitHub noch nicht gelaufen:** die geänderten Workflows (Abschnitt 4); die Einstellungen von GitHub selbst (Schutz für `main` und Tags, „Allow GitHub Actions to create and approve pull requests“) sieht man im Code nicht (`docs/AUDIT-SICHERHEIT.md` › „Zu prüfen“).
- **Bewusst gelassen:** K3 (Steam lauscht auf 27036), K4 (`SteamSetup.exe`), K6/K6a (derselbe Benutzer hat ohnehin alles), N5 (Dock-Bibliothek ohne Sandbox), N10, N11, N13, die Hinweise L1–L7.
- **Ein Anker für `install.sh` außerhalb von GitHub** und Regeln für `main`/Tags (M2, C): `docs/TODO.md`.
