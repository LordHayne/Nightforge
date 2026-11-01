<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHQb4wMCUMF6PtuYKtu (1.11.2026) -->

## Nightforge 0.3.0: Taugt der Verteilweg ohne Apple-Entwicklerkonto? Recherchebericht, Stand 1.11.2026

**Methode:** Ich habe nur gelesen und gesucht, am Repo ist nichts geändert. Direkt abrufbar waren in dieser Umgebung nur `developer.apple.com` und `raw.githubusercontent.com`. Über Letzteres habe ich die Repo-Dateien gelesen, den Homebrew-Quellcode samt Doku und Blog sowie Quellcode und Doku von Sparkle. `support.apple.com`, `eclecticlight.co`, Foren und Presse waren gesperrt.

**Kennzeichnung:**

- [sekundär]: Aussage stammt aus Suchergebnis-Zusammenfassungen, nicht von der Quelle selbst gelesen.
- [Schluss]: meine eigene Folgerung.
- [testen]: muss auf einem echten Mac geprüft werden.

---

### Kurzfassung

- 0.3.0: Verteilweg so lassen (ad-hoc-Signatur, curl-Einzeiler als Hauptweg, DMG als Zweitweg). Apple hat nichts angekündigt, was den curl-Weg oder ad-hoc-signierte Apps schließt, auch nicht für macOS 27.
- Für 0.3.0 nur wenig ändern:
  - Texte an die neue Terminal-Einfügewarnung seit macOS 26.4 anpassen. Sie trifft genau die Zielgruppe des Einzeilers.
  - Immutable Releases einschalten.
  - Eine bessere Meldung im Updater, wenn macOS die App von einem schreibgeschützten Ort startet (Translocation).
  - Die Ed25519-Prüfung der Update-ZIPs nur, wenn sie sich vor dem Tag per Dry-Run testen lässt, sonst in 0.3.1.

- Später, Entscheidung bis etwa Q1 2027: Das Apple Developer Program lohnt sich voraussichtlich. Nicht weil Apple den heutigen Weg schließt, sondern aus drei Gründen:
  - Ein notarisiertes DMG ohne jede Warnung ist das eigentlich idiotensichere Ziel. Das Terminal schreckt Laien seit 26.4 ab.
  - Eine stabile Identität, sodass macOS Freigaben nach Updates nicht neu abfragt.
  - Echte Herkunftsprüfung der Updates über die Team-ID.
  - Es kostet 99 $/Jahr. Eine Befreiung gibt es für Einzelpersonen nicht.

- Homebrew: Ohne Notarisierung bleibt nur ein eigener Tap, der die Quarantäne entfernt. Homebrew missbilligt das, und für Laien bringt es nichts. Lohnt sich jetzt nicht.
- Sparkle 2: Ohne Developer ID bringt Sparkle wenig gegenüber dem eigenen Updater mit Ed25519-Prüfung über CryptoKit. Interessant wird Sparkle erst mit Developer ID.
- Das größte Risiko liegt woanders, bei Rosetta: Laut Apple ist macOS 27 das letzte Release, das Rosetta allgemein unterstützt. Danach bleibt nur Unterstützung für „ältere, nicht mehr gepflegte Spiele“. Ob Wine darunter fällt, ist offen (Details unten).

---

### 1. Gatekeeper heute und morgen

#### Was sich geändert hat

| Version | Änderung | Beleg |
|---|---|---|
| **macOS 15.0 Sequoia** (Herbst 2024) | Ctrl-Klick bzw. Rechtsklick → „Öffnen“ übergeht Gatekeeper nicht mehr. Stattdessen: Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“. Apple: *„users will no longer be able to Control-click to override Gatekeeper … They’ll need to visit System Settings > Privacy & Security“* | [Apple Developer News, 6.8.2024](https://developer.apple.com/news/?id=saqachfa) |
|  | Die Verschärfung greift nur bei Apps mit Quarantäne-Flag. Lokal gebaute, ad-hoc-signierte Apps ohne Flag laufen wie zuvor. | [eclecticlight, 10.8.2024](https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/) [sekundär] |
|  | Der Knopf „Dennoch öffnen“ erscheint erst nach einem blockierten Startversuch und laut Apple-Hilfe (macOS 13) etwa eine Stunde lang. | [Apple Mac-Hilfe](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/13.0/mac/13.0) [sekundär] |
| **15.1** | Berichte, „Dennoch öffnen“ fehle ganz. Laut Forenstand betraf das Apps ganz ohne oder mit beschädigter Signatur; ad-hoc-signierte Apps bekommen den Knopf weiterhin. | [OSNews](https://www.osnews.com/story/141055/bug-or-intentional-macos-15-1-completely-removes-ability-to-launch-unsigned-applications/), [MacRumors-Forum](https://forums.macrumors.com/threads/macos-15-1-completely-removes-ability-to-launch-unsigned-applications.2441792) [sekundär] |
|  | Nativer arm64-Code braucht mindestens eine ad-hoc-Signatur. Nightforge erfüllt das. Apple: *„a simple ad-hoc signature is sufficient“* | [Big Sur Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes) |
| **`spctl`** | `sudo spctl --master-disable` schaltet Gatekeeper seit Sequoia nicht mehr ab. Es blendet nur die Option „Überall“ ein, die man in den Einstellungen bestätigen muss. Unter Tahoe 26.6 erlaubt das danach nur signierte, nicht notarisierte Apps; Gatekeeper und XProtect laufen weiter. Für Nutzer also kein Weg, nicht empfehlen. | [eclecticlight, 6.8.2026](https://eclecticlight.co/2026/08/06/can-you-disable-gatekeeper-and-xprotect/) [sekundär] |
| **macOS 26 Tahoe** | Keine dokumentierte neue Gatekeeper-Regel für nicht notarisierte Apps gefunden. |  |
| **26.4** (März 2026) | **Terminal-Einfügeschutz:** „Possible malware, Paste blocked“ mit den Knöpfen „Don’t Paste“ und „Paste Anyway“ (deutscher Wortlaut nicht geprüft). Erscheint, wenn jemand, der das Terminal nicht regelmäßig nutzt, einen Befehl aus Browser, Chat oder Mail einfügt. Bei bekannter Malware steht dort „Malware Detected, Paste Blocked“, ohne Weiter-Knopf. | [Apple Support 127377](https://support.apple.com/127377) [sekundär], [MacRumors](https://www.macrumors.com/2026/03/25/macos-26-4-terminal-security-feature/), [9to5Mac](https://9to5mac.com/2026/06/15/apple-reveals-why-macos-might-block-your-terminal-prompt/) |
|  | Die Warnung erscheint nicht, wenn das Terminal in den letzten 30 Tagen geöffnet wurde oder Entwicklerwerkzeuge installiert sind (Jeff Johnson). | [mjtsai, 3.4.2026](https://mjtsai.com/blog/2026/04/03/macos-26-4-paste-protection/) [sekundär] |
|  | Zusätzlich verfolgt XProtect den Prozessbaum eingefügter Befehle. | [Apple Platform Security](https://support.apple.com/guide/security/terminal-and-script-protections-sece3b202c4b/web) [sekundär] |
| **macOS 27 Golden Gate** (erschienen 14.9.2026 [sekundär]) | Keine Ankündigung zu Gatekeeper, Notarisierung oder ad-hoc-Signaturen gefunden. Im Apple-Developer-News-Feed (Nov. 2024 bis 29.10.2026) gibt es keine einzige Meldung dazu; den Feed habe ich direkt gelesen. | [News-Feed](https://developer.apple.com/news/) |
|  | Apples Sicherheitshinweise zu 27 nennen behobene Gatekeeper-Umgehungen, u. a. über präparierte ZIPs. Das sind Bugfixes, keine neuen Regeln. | [Apple Support 149035](https://support.apple.com/en-us/149035) [sekundär] |
|  | Der Terminal-Schutz ist auch in 27 enthalten. | [AppleInsider, 6.8.2026](https://appleinsider.com/articles/26/08/06/one-pasted-terminal-command-opens-the-door-to-mac-crypto-wallet-theft) [sekundär] |

**Gibt es Pläne, nicht notarisierte Apps weiter einzuschränken?**

- Bekannt ist nichts. eclecticlight (Januar 2026): Apple habe „no warnings, yet, of any changes to requirements for developer certificates, notarisation, or ad hoc code signing to come in macOS 27 or beyond“ (Artikel, [sekundär]).
- [Schluss] Der Trend geht seit Jahren in kleinen Schritten zu mehr Kontrolle:
  - 10.15: Notarisierung
  - 13: App Management und Integritätsprüfung notarisierter Apps
  - 15: Ctrl-Klick entfällt
  - 26.4: Terminal-Warnung
  - Oktober 2026: Apple kündigt strengere Kontrollen für Full Disk Access an (Apple News, 2.10.2026). Nightforge nutzt Full Disk Access nicht; ich habe den Code danach durchsucht.

- Bisher kamen solche Schritte mit Vorlauf: Sequoia wurde im August angekündigt und kam im September.

#### Bleibt der curl-Weg ohne Quarantäne erlaubt?

**Stand heute: ja.**

- Quarantäne ist opt-in. Apple sagt dazu (WWDC19, Session 701): „quarantine is an opt-in model … when an app downloads files in the background as part of, for example, a self-update, those files generally never get quarantined. The exception there is if the app is App Sandboxed.“ (Session, Zitat direkt geprüft)
- curl setzt das Flag nicht (Apple DTS [sekundär]).
- Die Gatekeeper-Prüfung gilt nur für Dateien mit Quarantäne-Flag. Den Malware-Scan bekommt aber alle Software (selbe WWDC19-Session).
- Die Integritätsprüfung bei jedem Start gilt seit Ventura nur für notarisierte Apps: „Gatekeeper will now check the integrity of all notarized apps, not just quarantined apps“ (WWDC22, Session 10096, Zitat geprüft).

**Anzeichen, dass Apple den Weg schließt:** Für curl selbst nicht. Apple setzt einen Schritt davor an, beim Einfügen ins Terminal (26.4). **[Schluss]** Apple sieht `curl | bash` als Angriffsweg („ClickFix“). Technisch bleibt der Weg offen, für Laien wird er aber abschreckender. Genau diese Gruppe sieht die Warnung.

#### Wie verhält sich die Selbstaktualisierung?

- Quarantäne: URLSession setzt in einer nicht-sandboxed App keine Quarantäne (siehe WWDC19-Zitat). Ausnahme: LSFileQuarantineEnabled ist gesetzt; der Standard ist „false (Default) Files created by this app are not quarantined by default“ (Apple-Doku). Nightforges `Resources/Info.plist`

 setzt den Schlüssel nicht, also kommen Updates ohne Flag an.
- Entpacken: tar und ditto würden die Quarantäne eines Archivs auf die entpackten Dateien übertragen.
  - tar: belegt im Quellcode von Apples libarchive.
  - ditto: laut Manpage ist --qtn Standard (Manpage).
  - Das spielt nur eine Rolle, wenn das Archiv selbst ein Flag trägt; heute trägt es keins.

- App Translocation: Sie greift nur, wenn eine quarantänisierte App von ihrem Download-Ort gestartet wird (Apple DTS [sekundär]). Updates sind also nie betroffen. Betroffen ist nur der DMG- bzw. Browser-Weg, wenn jemand die App direkt aus dem DMG oder aus „Downloads“ startet.
  - Dann ist der Pfad schreibgeschützt. Der Updater meldet heute .notWritable mit „Download the update from the release page instead“ und schickt Nutzer damit zurück auf den DMG-Weg.
  - Sparkle erkennt /AppTranslocation/ und sagt stattdessen: in den Programme-Ordner verschieben (Quellcode SPUUpdateDriver.m).

- App Management (seit Ventura): „Apps validly signed by the same developer account or team will continue to be able to update each other“. Was ein fremdes Team ändert, blockiert macOS (WWDC22, Session 10096, geprüft).
  - Eine ad-hoc-App hat keine Team-ID. Sparkles Installer behandelt den Tausch eines Bundles ohne Team-ID ausdrücklich als unproblematisch (SUPlainInstaller.m).
  - Berichte aus 2026: Der Schutz gilt notarisierten Apps, und das Ersetzen eines ganzen Bundles wird nicht blockiert (lapcatsoftware, Mysk [sekundär]).
  - [Schluss, testen] Der In-App-Updater und das Update per install.sh (erst rm -rf, dann ditto) sollten heute ohne Abfrage laufen. Nach einer Notarisierung neu prüfen.

- Nebenwirkung der ad-hoc-Signatur: Apple: „Ad hoc signed code … has a DR but it’s tied to that specific version of the code … macOS can’t reliably track the identity of the code“ (TN3127, geprüft).
  - [testen] Freigaben wie der Zugriff auf Wechseldatenträger (für Spiele auf externen Laufwerken) werden nach jedem Update vermutlich neu abgefragt.
  - Apple DTS bestätigt dieses Muster für die Bildschirmaufnahme (Forum [sekundär]).

#### Nachgeladene dylibs und Programme

- Library Validation: Nightforge läuft ohne Hardened Runtime, im eigenen Prozess gibt es also keine Library Validation. Apple zu Entitlements: „You add entitlements only to executables … libraries … inherit the entitlements of their host executable“ (Hardened Runtime).
  - [Schluss] Wine und die anderen Programme, die per Process() starten, sind eigene Executables mit eigener Signatur. Sie erben weder die Hardened Runtime noch Entitlements.

- Architekturen: x86_64-Code unter Rosetta braucht keine Signatur, arm64-Code mindestens eine ad-hoc-Signatur (Big Sur Release Notes). In einem Prozess gibt es nur eine Architektur (Rosetta-Doku). hide-steam-dock.dylib als x86_64 ist also richtig.
- Quarantäne auf Komponenten: Wine-Builds, DXVK, D3DMetal und KosmicKrisp kommen per URLSession und /usr/bin/tar ohne Flag an (Components.swift) und werden deshalb von Gatekeeper nicht geprüft.
  - Apple empfiehlt zwar: „If you use a network installer, separately notarize both the installer and the items it downloads“ (Notarization Workflow). Bei Dateien ohne Flag wird das aber nicht erzwungen. Whisky und Heroic arbeiten genauso (siehe Abschnitt 2).

- `DYLD_INSERT_LIBRARIES`: Die Variable wirkt, weil Wine nicht „hardened“ ist. SIP entfernt DYLD_* beim Start geschützter Programme wie /bin/sh (SIP-Guide). Wine muss also weiter direkt gestartet werden; Engine.run macht das bereits.
- [Schluss] Das ganze Laufzeitmodell hängt daran, dass LSFileQuarantineEnabled nie gesetzt wird. Das sollte im Code dokumentiert sein.

---

### 2. Notarisierung

**Kosten:**

- 99 USD pro Mitgliedsjahr (Enroll).
- Eine Gebührenbefreiung gibt es nur für Nonprofit-Organisationen, akkreditierte Bildungseinrichtungen und Behörden. Ausdrücklich ausgeschlossen: „Not be an individual, sole proprietor, or single-person business“ (Fee Waiver, direkt geprüft). Für Nightforge als Einzelprojekt gibt es also keine Befreiung.
- Als Einzelperson meldet man sich mit dem bürgerlichen Namen an, und dieser wird als Anbieter angezeigt. Für eine Organisation braucht es eine juristische Person; Phantasie- oder Handelsnamen akzeptiert Apple nicht (Enroll).
- Zertifikate: Das alte Developer-ID-Zwischenzertifikat endet am 1.2.2027. Neue Zertifikate kommen von „G2“ und „expire annually and must be renewed each year“. Notarisierte Apps mit Zeitstempel laufen danach weiter (Apple News, 1.10.2026).

**Was sich technisch ändern müsste:**

- Hardened Runtime ist Pflicht (Hardened Runtime). Der Notardienst lehnt ausdrücklich nur get-task-allow ab (Notarizing). Ausnahme-Entitlements werden akzeptiert: Heroic ist notarisiert und hat allow-jit, allow-unsigned-executable-memory und disable-library-validation (Repo-Datei entitlements.mac.plist, geprüft).
- [Schluss] Nightforge selbst braucht vermutlich keine JIT- oder Library-Entitlements, weil Wine als Kindprozess läuft. Auch allow-dyld-environment-variables ist nicht nötig, denn DYLD_* geht nur an das Kind.
  - Kandidat: com.apple.security.automation.apple-events plus NSAppleEventsUsageDescription, weil Nightforge osascript für „quit“-Befehle nutzt. Whisky hatte dieses Entitlement ebenfalls. [testen]

- Signieren: Jede Mach-O-Datei im Bundle braucht eine Developer-ID-Signatur mit --options runtime --timestamp: das Hauptprogramm, hide-steam-dock.dylib und nightforge-vulkan-layer.dylib. Ohne Hardened Runtime bzw. Zeitstempel meldet der Dienst „does not have the hardened runtime enabled“ bzw. „does not include a secure timestamp“. steamwebhelper.exe ist eine Windows-Datei und für die Notarisierung kein Mach-O. [Schluss]
- Nicht abgedeckt sind die zur Laufzeit geladenen Komponenten und das zur Laufzeit gebaute „Nightforge Game.app“. Sie funktionieren weiter nur, weil sie ohne Quarantäne entstehen, wie heute.

**Lassen sich Wine-Apps notarisieren? Ja.**

| Projekt | Stand | Beleg |
|---|---|---|
| **CrossOver** | Developer ID „CodeWeavers Inc.“, notarisiert. Der Cask (26.3.0) ist im offiziellen Homebrew-Tap aktiv, besteht also Homebrews Notarisierungsprüfung [Schluss]. | [desktopinsights](https://desktopinsights.com/apps/crossover) [sekundär], [Cask](https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/c/crossover.rb) |
| **Whisky** (eingestellt) | Developer ID und Hardened Runtime laut Xcode-Projekt. Entitlements: `allow-unsigned-executable-memory`, `apple-events`, Mikrofon und Kamera ([geprüft](https://raw.githubusercontent.com/Whisky-App/Whisky/main/Whisky/Whisky.entitlements)). WhiskyWine wird per `URLSession` geladen und nach Application Support entpackt, ohne Quarantäne-Behandlung. Ob die Builds notarisiert waren, ist unbelegt. | Wartungshinweis: *„no longer actively maintained“*, *„buy CrossOver“* ([whisky-book](https://raw.githubusercontent.com/Whisky-App/whisky-book/main/src/maintenance-notice.md)); Archivierung Mai 2025 [sekundär] |
| **Heroic** | Electron-App, notarisiert (Entitlements siehe oben). Wine und GPTK von Gcenx werden per axios und `tar` geladen, ohne Quarantäne-Code. Der Cask 2.22.4 ist aktiv. Die README empfiehlt noch das abgeschaffte `--no-quarantine`. | Repo |
| **Porting Kit** | Signiert und notarisiert. | [desktopinsights](https://desktopinsights.com/apps/portingkit) [sekundär] |
| **Sikarugir** (Nachfolger von Kegworks/Wineskin) und **Gcenx GPTK** | Unsigniert. Installation über einen eigenen Homebrew-Tap, der die Quarantäne entfernt und die App ad-hoc neu signiert. | [sikarugir.rb](https://raw.githubusercontent.com/Sikarugir-App/homebrew-sikarugir/HEAD/Casks/sikarugir.rb), [game-porting-toolkit.rb](https://raw.githubusercontent.com/Gcenx/homebrew-wine/master/Casks/game-porting-toolkit.rb) |
| **Gcenx-Wine im offiziellen Tap** | `wine-stable`, `wine@devel` und `wine@staging` sind seit 1.9.2026 abgeschaltet: `disable! date: "2026-09-01", because: :fails_gatekeeper_check`. | [wine-stable.rb](https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/w/wine-stable.rb), geprüft |

**Notarisierung in GitHub Actions:**

- notarytool ist das Werkzeug; altool funktioniert seit 1.11.2023 nicht mehr.
- Eine ZIP lässt sich notarisieren, aber nicht „stapeln“. Also: App stapeln, dann neu zippen. Das DMG separat signieren, notarisieren und stapeln. Limit: 75 Einreichungen pro Tag (Notarization Workflow).
- Der API-Schlüssel muss ein Team-Key sein: „Individual keys aren’t able to use … notaryTool“ (API Keys).
- Das Zertifikat kommt als base64-kodiertes .p12-Secret in eine temporäre Keychain (GitHub-Doku).
- Der Runner macos-15 reicht.
- Aufwand (Schätzung): 1–2 Tage einrichten und testen, danach läuft es automatisch. Dazu kommt die jährliche Zertifikatserneuerung.

---

### 3. Homebrew

**`--no-quarantine`** (geprüft im Homebrew-Quellcode an den Release-Tags und im [Blog zu 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)):

- 5.0.0 (12.11.2025): veraltet. Zitat: „Homebrew does not wish to easily provide circumvention to macOS security features“
- 5.1.0 (10.3.2026): abgeschaltet, die Option führt zu einem Fehler.
- 6.0.0 (11.6.2026): entfernt.
- HOMEBREW_CASK_OPTS=--no-quarantine wird nicht mehr ausgewertet.

**Offizieller Tap (homebrew-cask): nicht für Nightforge.**

- 5.0.0 kündigte an: „We will disable all Homebrew/homebrew-cask casks that fail Gatekeeper checks in September 2026“. Das ist umgesetzt (siehe die Wine-Casks oben). Abgeschaltete Casks werden ein Jahr später gelöscht (Deprecating-Disabling-and-Removing).
- Neue Casks prüft ein Audit mit codesign --verify -R=notarized: „The homebrew/cask tap requires all casks to be signed and notarized by Apple.“
- Regeltext: „must pass Homebrew’s Gatekeeper checks and must not require … Gatekeeper to be disabled or bypassed“ (Acceptable Casks, geprüft).

**Eigener Tap: möglich, aber kaum ein Gewinn.**

- Erlaubt: „Software that does not meet the official criteria can generally be maintained in a third-party tap“ (Package Acceptance Policy).
- Tap Trust seit 6.0.0: Nutzer müssen einen Tap ausdrücklich freigeben (brew trust …) oder per vollem Namen installieren (Tap Trust, Blog 6.0.0).
- Homebrew setzt bei jedem Cask-Download die Quarantäne. Ausweg ist ein postflight_steps-Block mit xattr (seit 5.1.14), wie bei AeroSpace und Sikarugir. Alte Ruby-postflight-Blöcke erzeugen in Fremd-Taps bis 11.12.2027 Warnungen (Blog 7.0.0).
- Homebrews Sicherheitsdoku spricht davon, kein „normalising a security bypass“ zu betreiben. Ein Audit gegen xattr in Fremd-Taps habe ich im Code nicht gefunden.
- Ohne Entfernen der Quarantäne: Seit 6.0.22 überträgt brew upgrade die frühere Freigabe nur, wenn der Signierer gleich bleibt. [Schluss] Bei ad-hoc ändert er sich mit jedem Build, also wäre nach jedem Update erneut „Dennoch öffnen“ nötig.
- [Schluss] Die Zielgruppe hat meist kein Homebrew. Ein Tap ohne Notarisierung ist nur ein weiterer Weg, die Quarantäne zu entfernen, diesmal von Homebrew missbilligt.

**Mit Notarisierung (später):** Ein offizieller Cask ist möglich, sobald diese Bedingungen erfüllt sind ([Policy](https://docs.brew.sh/Package-Acceptance-Policy), geprüft):

- mindestens 30 Forks, 30 Watcher oder 75 Sterne; bei Selbsteinreichung durch den Repo-Inhaber 90/90/225
- Repo mindestens 30 Tage alt
- funktionierender livecheck
- wegen des Selbst-Updates auto_updates true
- Hinweis: macOS 14 ist in Homebrew 7 nur noch „Tier 3“, läuft also noch, wird aber nicht mehr unterstützt.

---

### 4. Selbst-Update

#### Sicherheit des heutigen Wegs

- `codesign --verify --deep` beweist bei ad-hoc nichts über die Herkunft. Laut codesign-Manpage identifiziert eine ad-hoc-Signatur „exactly one instance of code“. Jede ZIP mit gleicher Bundle-ID und gültiger ad-hoc-Signatur besteht alle Prüfungen in Updater.install. Der Doku-Kommentar „checks its signature“ verspricht mehr, als passiert.
- Die ganze Vertrauenskette ist der GitHub-Account und alles, was Releases anlegen oder auf main schreiben kann. Dazu gehören die nächtlichen Bot-Commits von components.yml und profiles.yml auf main.
  - install.sh wird selbst von main geladen. Jeder Push dorthin ändert, was curl | bash ausführt.
  - Die SHA-256-Werte in manifest.json stammen aus derselben Quelle. Sie sichern die Unversehrtheit, nicht die Herkunft.
  - `docs/TODO.md`

 führt das bereits als „bewusst offen“.

#### Sparkle 2 im Vergleich

- Stand: Version 2.10.1, ab macOS 12, per Swift Package Manager einbindbar (Package.swift im Sparkle-Repo). Funktionen:
  - EdDSA-Signaturen, generate_appcast, signierter Feed seit 2.9 (SURequireSignedFeed)
  - verweigert Downgrades, erkennt Translocation
  - entfernt die Quarantäne und ruft gktool scan auf
  - die XPC-Dienste nur für sandboxed Apps (Quellcode und Doku im Repo).

- Ohne Developer ID ist EdDSA der einzige Anker. Regel im Quellcode: „Either DSA must be valid, or Apple Code Signing must be valid“ (SUUpdateValidator.m, geprüft). Die ad-hoc-Identität des neuen Builds passt nie zur alten, also muss EdDSA gelingen.
  - Schlüsselrotation gibt es nur für Developer-ID-Apps. Geht der Schlüssel verloren, kann über Sparkle kein Update mehr kommen.

- Mit Developer ID prüft Sparkle zwei Anker (EdDSA und Team-ID), und der Schlüssel lässt sich tauschen.
- Sparkle hatte selbst Lücken: 1.13.1 (Man-in-the-Middle bis zur Codeausführung), 2.6.4 (Umgehung der EdDSA-Prüfung), lokale Rechteausweitungen behoben in 2.7.3 und 2.9.6 (Sicherheits-Doku des Projekts). Man muss die Abhängigkeit also aktuell halten.
- [Schluss] Empfehlung: Ohne Notarisierung reicht der eigene Updater plus Ed25519-Prüfung mit CryptoKit (Curve25519.Signing, im System enthalten, keine Abhängigkeit). Sparkle lohnt sich mit Developer ID, oder wenn Standard-UI und Delta-Updates gewünscht sind.

#### Wo der Signaturschlüssel liegt, entscheidet über den Nutzen

- Liegt der private Schlüssel als GitHub-Secret vor, kann ein kompromittierter Account oder Workflow auch signieren. Die Signatur schützt dann vor allem vor Manipulation außerhalb der CI.
- Stärker: lokal auf dem Mac des Maintainers signieren. Die CI legt einen Entwurf an, der Maintainer signiert und veröffentlicht. Das passt auch zu „Veröffentlichung nur mit ausdrücklichem OK“.
- Immutable Releases (allgemein verfügbar seit 28.10.2025): Nach dem Veröffentlichen lassen sich Assets weder ändern noch hinzufügen (GitHub Changelog). Die Signatur muss also vor dem Veröffentlichen hochgeladen sein. v0.2.0 ist laut API "immutable": false.
- GitHub liefert seit 3.6.2025 pro Asset einen SHA-256-digest (Changelog). v0.2.0 hat ihn. Ein Abgleich schützt vor Übertragungsfehlern, nicht vor einem gekaperten Account.

---

### 5. Vertrauen und erster Eindruck

- Was die Projekte für Laien gemacht haben: CrossOver, Porting Kit, Heroic und früher Whisky sind alle notarisiert und brauchen keine Erklärung. [Schluss] Das ist der Maßstab für „idiotensicher“.
- Unsignierte Projekte richten sich an Fortgeschrittene und setzen auf Homebrew:
  - AeroSpace sagt offen „not notarized“, begründet das und entfernt die Quarantäne über seinen Tap (README).
  - Sikarugir nutzt Homebrew mit brew trust und warnt vor einer gefälschten Domain (sikarugir.com) (README). Bei unsignierter Software kann niemand eine Entwickler-Identität prüfen, Nachahmer haben es also leicht.

- Was sich bewährt (aus diesen Beispielen und Apples Hilfe abgeleitet):
  1. Ein Satz zum Warum: kostenlos, nicht bei Apple registriert, das kostet 99 $/Jahr. Die Warnung ist kein Malware-Befund.
  2. Genaue Klicks mit Screenshots. Hinweis, dass der Knopf erst nach dem ersten Startversuch erscheint und nur etwa eine Stunde bleibt.
  3. Nur von github.com/LordHayne/Nightforge laden.
  4. Nutzern kein xattr und kein spctl empfehlen.

- Die README macht davon schon viel richtig; Screenshots sind in `docs/ROADMAP.md`

 geplant. [Schluss] Der Terminal-Weg ist seit 26.4 die Schwachstelle für Laien. Mittelfristig ist ein notarisiertes DMG am besten (laden, ziehen, öffnen). Der Einzeiler bleibt dann als Alternative.

---

### Nebenbefunde

1. Rosetta, das größte strategische Risiko (Apple News, 1.9.2026, direkt geprüft):
  - „macOS 26.4 or later: Users may receive a system notification when launching apps that rely on Rosetta“
  - „macOS 27: Final release to support Rosetta — Intel-only apps will no longer run on Mac computers with Apple silicon after this update.“
  - „Rosetta functionality for older, unmaintained gaming titles that rely on Intel-based frameworks will continue to be supported.“
  - Das x86_64-Wine braucht Rosetta. Offen ist, ob Wine-Prozesse die Benachrichtigung auslösen und ob Wine unter macOS 28 (erwartet Herbst 2027) in die Spiele-Ausnahme fällt. Im Apple-Forum ist dazu eine Frage offen (Thread [sekundär]). Auch CrossOver hängt noch an Rosetta [sekundär]. [testen auf 26.4+/27]

2. Release-Kennzeichnung ist in Ordnung: Die Komponenten-Releases (graphics.yml, gamepad.yml, tools.yml) nutzen --latest=false. releases/latest liefert v0.2.0 mit ZIP und DMG (geprüft). Installer und Updater finden also das richtige Release.

---

### Empfehlung und Zeitachse

#### 0.3.0 (jetzt): Verteilweg so lassen, wenig ändern

**Begründung:** Kein Apple-Signal gegen ad-hoc-Signatur oder curl, auch nicht in 27. Eine Notarisierung in wenigen Tagen ist Zusatzaufwand und Risiko ohne Not.

**Für 0.3.0, geringes Risiko:**

1. README und Release-Notes: die Terminal-Warnung erklären.
2. README: genauer erklären, wann „Dennoch öffnen“ erscheint.
3. Immutable Releases aktivieren (Repo-Einstellung).
4. Updater: Meldung bei Translocation bzw. schreibgeschütztem Ort.

**Optional, nur mit Dry-Run vor dem Tag:** Ed25519-Prüfung im Updater. Ohne Test lieber in 0.3.1. Fällt die Prüfung durch einen Bug aus, bleibt der curl-Einzeiler als Ausweg.

**Vor dem Release auf macOS 15, 26.x und 27 testen** [testen]:

- curl-Einzeiler in einem frischen Benutzerkonto: Terminal 30 Tage nicht benutzt, keine Command Line Tools. Erscheint die Warnung?
- DMG: Erscheint „Dennoch öffnen“ für die ad-hoc-App auch auf 27?
- Update 0.2.0 → 0.3.0 per In-App-Updater und per install.sh: keine Abfrage zu App Management? Fragt macOS die Laufwerksfreigabe erneut ab?
- xattr -l auf nachgeladenen Komponenten: keine Quarantäne?
- Erscheint die Rosetta-Benachrichtigung beim Start von Steam oder Spielen?

#### Später

| Zeitraum | Schritt | Kosten | Aufwand (Schätzung) | Risiken |
|---|---|---|---|---|
| 0.3.x (Nov./Dez. 2026) | Ed25519-signierte Updates (falls nicht in 0.3.0), Entwurfs-Release mit lokaler Signatur, `install.sh` als Release-Asset, später auch `manifest.json` signieren | 0 € | ~1 Tag | Schlüsselverlust: Updates nur noch per Neuinstallation; nächtliche Manifeste bräuchten einen CI-Schlüssel |
| Entscheidung bis Q1 2027 | Apple Developer Program | 99 $/Jahr | 1–2 Tage CI, jährliche Zertifikatspflege | Bürgerlicher Name öffentlich; laufende Kosten; Komponenten bleiben auf dem Weg ohne Quarantäne; Apple kann Zertifikate widerrufen |
| Nach Notarisierung | DMG wird Hauptweg; Updater und `install.sh` prüfen die Team-ID; offizieller Homebrew-Cask, sobald die Schwelle erreicht ist; Sparkle optional | – | 1–2 Tage | App Management und TCC neu testen |
| Bis Herbst 2027 (macOS 28) | Rosetta-Frage klären | – | – | Betrifft das ganze Wine-Modell, nicht nur die Verteilung |

**Optionen im Vergleich:**

| Option | Kosten | Nutzen | Risiko |
|---|---|---|---|
| So lassen | 0 | – | Terminal-Warnung; keine Herkunftsprüfung der Updates; Freigaben nach Updates neu |
| Eigenes Ed25519 | 0, ~1 Tag | Echte Herkunftsprüfung, wenn der Schlüssel außerhalb von GitHub liegt | Schlüsselverlust; Fehler im Update-Pfad |
| Sparkle 2 ohne Developer ID | 0, 1–2 Tage | Ausgereifte Funktionen | Keine Schlüsselrotation; Abhängigkeit pflegen |
| Notarisierung | 99 $/Jahr | DMG ohne Warnung, stabile Identität, Homebrew möglich | Name öffentlich; Daueraufwand |
| Eigener Tap ohne Notarisierung | 0, ~½ Tag | Nur für Homebrew-Nutzer | Von Homebrew missbilligt; `brew trust` nötig; für Laien wertlos |

---

### Konkrete Änderungen

#### `scripts/install.sh`

1. Optional die ZIP-Prüfsumme gegen den digest aus der GitHub-API vergleichen (shasum -a 256). Zum Auslesen des JSON nicht grep nehmen; plutil -extract oder osascript -l JavaScript sind robuster [testen]. Schützt nur vor Übertragungsfehlern.
2. Optional das Skript als Release-Asset ausliefern (…/releases/latest/download/install.sh). Dann ändert sich das, was curl | bash ausführt, nur mit einem Release, nicht mit jedem Push auf main. Die alte Adresse sollte weiter funktionieren.
3. xattr -dr com.apple.quarantine … behalten. Es schadet nicht und ist bei curl ein No-op.
4. Mit Developer ID: vor dem Installieren codesign --verify --deep --strict -R='anchor apple generic and certificate leaf[subject.OU] = "TEAMID"', so wie MacSteam.swift es schon für Valve macht.
5. Eine Ed25519-Prüfung in Bash ist auf Standard-macOS schwierig. Ob das mitgelieferte LibreSSL-openssl Ed25519 kann, ist unsicher. Darum hier besser Digest plus später Team-ID.

#### `.github/workflows/release.yml`

1. Den Release-Text ergänzen: Hinweis auf die Terminal-Warnung, SHA-256 der Assets in die Notes (wird heute nur ins Log geschrieben).
2. Mit Immutable Releases müssen alle Assets beim Anlegen hochgeladen sein. Ob gh release create erst als Entwurf hochlädt und dann veröffentlicht, ist unsicher; vorher im Dry-Run prüfen.
3. Bei Ed25519: --draft anlegen, dann lokal signieren, Nightforge-X.zip.sig hochladen und veröffentlichen.
4. Später mit Developer ID:
  - Secrets anlegen: .p12 (base64) mit Passwort, Team-API-Key, Key-ID und Issuer-ID.
  - Temporäre Keychain einrichten.
  - Erst die beiden dylibs, dann die App signieren, jeweils mit --options runtime --timestamp.
  - notarytool submit --wait, dann stapler staple auf die App, dann neu zippen.
  - Das DMG signieren, notarisieren und stapeln.

#### `Sources/Nightforge/Updater.swift`

1. Das Asset .sig laden und mit Curve25519.Signing.PublicKey(rawRepresentation:) und isValidSignature(_:for:) gegen einen im Code hinterlegten Schlüssel prüfen. Bei Fehler Failure.signature.
2. notWritable aufteilen: Liegt der Pfad unter /AppTranslocation/ oder auf einem schreibgeschützten Volume, „Bitte Nightforge in den Programme-Ordner verschieben“ melden, statt auf die Release-Seite zu verweisen.
3. Den Doku-Kommentar ehrlich machen: Bei ad-hoc prüft codesign nur die Integrität. --strict ergänzen; mit Developer ID -R mit der Team-ID.
4. Einen Kommentar ergänzen, dass LSFileQuarantineEnabled nicht gesetzt werden darf, weil sonst alle Updates und Komponenten Quarantäne bekämen.

#### `README.md`

1. Beim Einzeiler: Seit macOS 26.4 kann „Possible malware, Paste blocked“ erscheinen. Bei der Zeile von der offiziellen Seite „Paste Anyway“ wählen. Dazu ein Link auf `scripts/install.sh`

, damit man sieht, was es tut. Den deutschen Wortlaut auf einem deutschen Mac prüfen.
2. Beim DMG: Der Knopf „Dennoch öffnen“ erscheint erst nach dem ersten Versuch und bleibt etwa eine Stunde; Administratorpasswort nötig; Screenshots.
3. Ein kurzer Absatz „Warum die Warnung?“ und: nur von github.com/LordHayne/Nightforge laden.
4. Nach einem Test eventuell der Hinweis, dass macOS nach Updates Freigaben (externe Laufwerke) erneut abfragen kann.
5. Kein xattr oder spctl für Nutzer empfehlen.

---

### Unsicher oder nicht geprüft

- Ob die Terminal-Warnung beim Nightforge-Einzeiler aus der GitHub-Seite tatsächlich erscheint; die Bedingungen stammen aus Sekundärquellen. Den deutschen Wortlaut habe ich nicht gesehen.
- App Management: dass ad-hoc-Apps und das Ersetzen ganzer Bundles nicht betroffen sind. Plausibel, aber nicht getestet.
- Dass macOS die Laufwerksfreigabe nach jedem Update neu abfragt; aus TN3127 abgeleitet.
- Ob ditto -x -k die Quarantäne eines ZIPs überträgt. Für Nightforge heute egal.
- Ob Wine die Rosetta-Benachrichtigung auslöst und ob Wine unter die Spiele-Ausnahme in macOS 28 fällt.
- Das Ein-Stunden-Fenster für „Dennoch öffnen“; belegt nur über die macOS-13-Hilfe.
- Ob Whisky notarisiert war, sowie das Release-Datum von Sparkle 2.10.1.
- Die Aufwandsschätzungen sind meine eigenen.

Für eine Prüfung am Primärtext müssten `support.apple.com`, `eclecticlight.co`, `brew.sh` und `github.com` in den Netzwerkeinstellungen der Umgebung freigegeben werden.
