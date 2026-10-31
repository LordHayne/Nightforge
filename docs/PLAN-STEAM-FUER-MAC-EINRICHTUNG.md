# Steam für Mac in der Ersteinrichtung – Plan

Stand 29.10.2026, Sitzung „mac-steam-setup“, Branch `claude/mac-steam-setup-db5892`. Phase 1: Recherche und Plan.
Grundlage: die echten Logs beider Steams auf diesem Mac (nur gelesen, 23.–29.10.), der Code auf `2e296db` und die Quellen unten.
Phase 2 ist teilweise gebaut (Abschnitt „Stand Phase 2“ am Ende).

## Kurz

- **Ursache:** Steam erlaubt mehrere angemeldete Clients pro Konto, aber nur eine Sitzung je *öffentlicher IP + Login-ID*.
  Der echte Steam-Client bildet die Login-ID aus seiner lokalen IP. Zwei Steams auf demselben Mac haben also dieselbe ID,
  und die neuere Anmeldung ersetzt die ältere. Das passiert schon beim Anmelden, nicht erst beim Spielen.
- **Abgemeldet ist nicht ausgeloggt:** Der Rauswurf lässt das gemerkte Anmelde-Token stehen. Ein Neustart meldet die Steam
  still wieder an: 216 von 216 Neustarts auf diesem Mac, ohne Fenster und ohne QR. Steam für Mac ist nach 4,7 s bereit,
  die Windows-Steam nach 11,9 s (Median).
- **Folge:** Einmal pro Steam anmelden reicht (Token gilt hier rund 7 Monate). Nightforge muss nur dafür sorgen, dass immer die
  richtige Steam online ist, die andere *beendet* statt rausgeworfen wird und nie mitten in einem Cloud-Abgleich gewechselt wird.
- **Empfehlung:** Steam für Mac läuft in der Ersteinrichtung im Hintergrund mit. Der zweite QR-Code kommt direkt nach dem ersten,
  aber nur, wenn die Bibliothek Mac-Versionen hat. Das kostet etwa 20–30 s und einen zweiten Scan, danach nie wieder.

## 1. Warum „Session Replaced“?

**Regel (Quellen):** Valve dokumentiert das nicht. SteamKit2 beschreibt es in seiner `LoginID`-Doku: Pro Konto darf je öffentlicher
IP nur eine Sitzung mit derselben Login-ID bestehen. Standardmäßig kommt die ID aus der lokalen Adresse der Maschine, und mehrere
Sitzungen brauchen verschiedene IDs. Der echte Client schickt sie als `obfuscated_private_ip`. Die Betreuer von node-steam-user
bestätigen das: Wer mit gleicher IP und gleicher ID anmeldet, ersetzt die ältere Sitzung („LogonSessionReplaced“). Mit
verschiedenen IDs laufen mehrere Sitzungen desselben Kontos nebeneinander. Auf zwei verschiedenen Rechnern bleiben deshalb beide
angemeldet (Steam Deck + PC). Dort kollidiert erst das *Spielen* (LoggedInElsewhere). Für Nightforge spielt das keine Rolle,
weil nie zwei Spiele gleichzeitig laufen.

**Belege auf diesem Mac** (`connection_log.txt` beider Steams, zu einer Zeitachse zusammengeführt):
- Beide verbinden sich immer von derselben LAN-Adresse (192.168.1.235, .232, .117, je nach DHCP zur selben Zeit). Also schicken
  beide dieselbe Login-ID.
- 81 Rauswürfe: 39 bei der Windows-Steam, 42 bei Steam für Mac. 74 davon fallen in dieselbe Sekunde (±3 s), in der die andere
  Steam „Logged On“ meldet. Der Rauswurf hängt allein an der Anmeldung. Beispiel 27.10. 22:32–22:34: In 2,5 Minuten werfen sich
  beide viermal abwechselnd raus, ohne dass ein Spiel läuft.
- 7 Rauswürfe kamen von außen: dasselbe Konto in Test-Prefixen oder anderen Nightforge-Builds. Zuletzt heute um 20:29:37
  (vermutlich der Erststart-Test in `build/fh`). **Nightforges Windows-Steam ist seitdem abgemeldet** und läuft weiter
  (Stand 21:5x). Beim nächsten Windows-Spiel meldet Play sie neu an (Phase „Signing in“).
- **Kein Wiederverbinden:** In jedem Fall steht `not auto reconnecting due to Session Replaced`. Keiner der 81 Fälle hat sich ohne
  Neustart wieder angemeldet.
- **Schaden:** Steam für Mac zeigt 24 und die Windows-Steam 4 Einträge `Failed sync … [login=false]` (26./27.10.), darunter
  „AC Launch“/„AC Exit“ von Batman: Arkham City (200260). Spielstände wurden also weder geholt noch hochgeladen. Seit Play die
  richtige Steam anmeldet, ist kein neuer dazugekommen. Ein Wechsel mitten im Abgleich bleibt aber das Hauptrisiko.

**Beide gleichzeitig online lassen?** Technisch denkbar: Die Windows-Steam bekäme eine andere Login-ID, etwa über eine vorgetäuschte
lokale IP in winecx oder einen IP-Alias. **Nicht empfohlen.** Das täuscht Valves Client über die Maschine, braucht einen Wine-Patch
oder eine Netzwerkänderung mit Admin-Rechten und kann LAN-Funktionen stören (Remote Play, Übertragung im Heimnetz). Das ginge nur
mit ausdrücklicher Entscheidung des Nutzers.

## 2. Stilles Wiederanmelden

- Jede Steam hat ihr **eigenes** Anmelde-Token (JWT, `persistence: 1`), verschlüsselt in ihrer eigenen `local.vdf` (`ConnectCache`).
  - Windows-Steam: ausgestellt 23.10. 22:50, gültig bis 24.05.2027.
  - Steam für Mac: ausgestellt 26.10. 11:09, gültig bis 26.05.2027.
  - In beiden `loginusers.vdf` stehen `RememberPassword 1` und `AutoLogin 1`, `AutoLoginUser` ist gesetzt
    (Mac: `registry.vdf`, Wine: `user.reg`).
- Ein Rauswurf macht das Token nicht ungültig. Seit der ersten Anmeldung lief jede Anmeldung mit demselben Token
  (Windows 199×, Mac 54× „Using JWT …“), jede mit `'OK'`. Steams Anmeldefenster (`WaitingForCredentials`) kam nur am Tag der
  ersten Anmeldung (Windows 23.10., Mac 26.10.).
- **Dauer** („System startup time“, ab dann nimmt Steam `steam://run` an):

  | Steam | Median | p90 |
  |---|---|---|
  | Steam für Mac | 4,7 s | 8,9 s |
  | Windows-Steam | 11,9 s | 14,2 s |

  Die Anmeldung selbst liegt bei 4 s (Mac) bzw. 8 s (Windows) nach „Client version“.
- **Ergebnis:** „Einmal pro Steam“ reicht. Ob Steam das Token vor Ablauf selbst erneuert, ist laut node-steam-user wahrscheinlich,
  hier aber nicht belegt. Nach Ablauf, einer Passwortänderung oder „Alle anderen Geräte abmelden“ fragt jede Steam einmal neu.
- **Ein Token für beide?** Nein. Die `ConnectCache` ist pro Installation verschlüsselt. Sie zu kopieren hieße, Anmeldedaten
  anzufassen, und „Nightforge never sees your login“ gälte nicht mehr. Zwei Steams heißen also mindestens zwei Freigaben.

## 3. Steam für Mac in der Ersteinrichtung – Wege

**Messwerte:**
- Windows-Seite heute: Anmeldefenster 2:57 nach „Let's Go“, Enthüllung etwa 20 s nach dem Scan.
- Steam für Mac (26.10.): `steam.dmg` wiegt ein paar MB, dazu Signaturprüfung und Kopie. Vom ersten Start bis zum Anmeldefenster
  vergingen 53 s: 289 MB Selbst-Update in 24 s, Entpacken, Neustart. Auf der Platte belegt es 1,2 GB
  (`Steam.AppBundle`; `Steam.app` 11 MB).
- Steam für Mac wartete am 26.10. 40 Minuten mit offenem QR (10:29–11:09), und der Scan klappte danach trotzdem.

| Weg | Scans | Mehrzeit | Wann der Spieler da sein muss | Nachteil |
|---|---|---|---|---|
| **A – parallel, 2. QR direkt nach dem 1. (Empfehlung)** | 2 (1, wenn keine Mac-Version) | ca. +20–30 s | einmal, Handy bleibt in der Hand | Steam für Mac wird vorbereitet, bevor klar ist, ob es gebraucht wird |
| A′ – Mac-QR zuerst, in der Wartezeit | 2 | ±0 | zweimal (~1:15 und ~3:00) | kein Weggehen in den 3 Minuten; immer 1,2 GB, auch ohne Mac-Spiel |
| B – erst bei Bedarf (heute) | 1 + 1 später | 0 | beim ersten Mac-Spiel, mitten im „Play“ | genau das, was der Nutzer nicht will |
| C – vorhandene Anmeldung übernehmen | 0 zusätzlich | 0 | – | nur, wenn Steam für Mac schon mit *diesem* Konto angemeldet ist |

**Empfehlung: A, mit C, wo es passt, und B als Rückfall.**

1. Nach dem Engine-Download (dann ist die Leitung frei) startet parallel `MacSteam.install()`: Download, Valve-Signatur, Kopie nach
   `/Applications`. Danach startet Steam für Mac **versteckt**, lädt sein Update und bleibt verborgen an seinem Anmeldefenster stehen.
   - Schon angemeldet (C, `loginusers.vdf` mit derselben SteamID wie die Windows-Steam nach Scan 1): Steam für Mac wird gar nicht
     gestartet, der Schritt ist fertig.
   - Ein anderes Konto in Steam für Mac: nicht anfassen. Der Schritt entfällt, und der Rückfall B bleibt.
2. Bei ~3:00 kommt das Windows-Anmeldefenster, Scan 1. Die Bibliotheksprüfung läuft wie heute.
3. Sobald die Zahl der Spiele steht, weiß Nightforge, wie viele eigene Spiele über die Mac-Version laufen würden
   (`VersionChoice` → `.mac`). Bei n > 0 kommt das wartende Steam-für-Mac-Fenster nach vorne: Scan 2. Nach `Logged On` und
   `loginusers.vdf` (+4 s) beendet Nightforge Steam für Mac und startet die Windows-Steam versteckt neu (stilles Anmelden ~12 s,
   im Hintergrund, während die Enthüllung schon steht).
4. Bei n = 0 wird Steam für Mac beendet und, falls Nightforge es eben erst installiert hat, wieder entfernt (siehe offene Frage 2).
5. „Later“ (Esc/B) am zweiten QR: Mac-Versionen kommen dann wie heute beim ersten Bedarf (B). Die Windows-Versionen laufen sofort.

**Warum nicht A′:** Der Spieler müsste zweimal im Abstand von zwei Minuten zum Bildschirm. Außerdem käme Steam für Mac immer auf den
Mac, ohne dass jemand weiß, ob das Konto Mac-Spiele hat. A′ hat aber einen Vorteil: Die Windows-Steam meldet sich zuletzt an und
muss nicht neu starten. A′ bleibt die Alternative, wenn die Mehrzeit von A stört.

## 4. Was sich in der Oberfläche ändert (nur beschrieben – `SetupView` gehört design-setup-home)

- **Checkliste:** Ein neuer letzter Schritt „Setting up Steam for Mac“ (`SetupModel.Step.macSteam`). Er arbeitet parallel, ab dem
  Engine-Schritt. Wie ein zweiter laufender Schritt aussieht, entscheidet design-setup-home (z. B. ein kleiner Nebenstrich).
  Live-Zeilen aus echten Daten:
  - „Downloading Steam for Mac …“
  - „Steam for Mac updates itself · 120 of 289 MB“ (`bootstrap_log`)
  - „Ready – you sign in right after Steam“
  - am Ende: „Signed in“ / „Already signed in“ / „Not needed – none of your games has a Mac version“
- **QR-Hinweis** (`signInNote`):
  - Vor Scan 1 bleibt er wie heute. Ist Steam für Mac schon fertig vorbereitet, kommt dazu: „Then a second one for Steam for Mac.“
  - Während Scan 2: „One more: this window is Steam for Mac. It gets the Mac versions of 12 of your games – they run without any
    Windows translation. Scan its QR code too.“
  - Knöpfe „Show Steam window again“ und „Later“.
- **Enthüllung:** Eine Zeile unter dem Balken: „12 of them play as their Mac version.“ Bei „Later“: „12 have a Mac version – Nightforge
  sets it up the first time you play one.“ (`LibraryReveal` bekommt dafür ein Feld `mac`.)
- **Wiederholung** („Show the First Start Again“): Sie ändert sich nicht und fragt nichts ab.
- **Rechtliches:** Die Welcome-Zeile oder der Mac-Schritt übernimmt den SSA-Satz aus `MacSteamSetupView`
  („By installing you accept Valve's Steam Subscriber Agreement“).

## Danach: nie wieder fragen, nie sichtbar rauswerfen (Regeln für Phase 2)

- **R1 – Immer genau eine Steam online.** Die andere wird *beendet*, höflich und mit Token, nicht rausgeworfen. Heute läuft die
  rausgeworfene Steam abgemeldet weiter. Genau das erzeugt hängende Downloads, fehlgeschlagene Abgleiche und Fenster, die nach vorne
  drängen (TODO „Steam-Anmeldung zwischen den Steams“).
- **R2 – Ruhezustand:** Die Windows-Steam ist online (die meisten Spiele, sofortiges Play), Steam für Mac ist aus. Ausnahmen:
  - Eine Mac-Version startet oder läuft.
  - Ein Mac-Download hat seinen Zug (`takeTurnsDownloading`).
  - Der Spieler hat Steam für Mac selbst geöffnet. Dann bleibt sie, und Nightforge meldet die Windows-Steam erst bei Windows-Play wieder an.
- **R3 – Wechseln an den Rändern, im Hintergrund:**
  - Mac-Play: Die Windows-Steam wird beendet (wenn ihr Abgleich ruht), dann startet Steam für Mac versteckt (bereit nach ~5 s) und
    danach `steam://run`.
  - Nach dem Mac-Spiel: Nightforge wartet auf den Upload (`CloudSaves`: „AC Exit“ + `syncstate` 1). Dann wird Steam für Mac beendet
    und die Windows-Steam versteckt gestartet. Das nächste Windows-Play zeigt dann kein „Signing in“ mehr.
  - Kosten: Dasselbe Mac-Spiel noch einmal starten dauert ~5 s länger.
- **R4 – Kein Wechsel, solange die andere Seite spielt oder abgleicht.** `macSteamBusy`/`otherSteamFree` gibt es schon. Neu kommt
  „gleicht gerade ab“ dazu.
- **R5 – Abgelaufenes Token:** Zeigt eine sonst still startende Steam `WaitingForCredentials`, kommt *ihr* Fenster mit
  „Steam asks you to sign in again – it does that every few months.“ Für Steam für Mac gibt es das schon (`waitingForPlayer`),
  für die Windows-Steam über `SteamWindow`.
- **R6 – Fremde Anmeldungen** (Test-Prefixe, andere Builds) lösen R3 nicht aus. Sie werden wie heute erst beim nächsten Play geheilt.

## Erwartung

- **Anmeldungen:**
  - Ersteinrichtung: 2 Scans. Nur 1, wenn das Konto keine Mac-Version hat oder Steam für Mac schon mit diesem Konto angemeldet ist.
  - Danach: 0 bei jedem Wechsel Mac ↔ Windows.
  - Erst wieder nach Ablauf des Tokens (hier Mai 2027, falls Steam es nicht verlängert), einer Passwortänderung oder dem Abmelden
    aller Geräte – je Steam einmal.
- **Zeit:**
  - Windows-Anmeldefenster wie heute (2:57). Der parallele Teil (289 MB, ~40 s Arbeit) fällt in die Umgebungs- und Steam-Schritte.
    Ein Aufschlag von bis zu 15 s ist möglich und muss gemessen werden.
  - Vom ersten Scan bis zur Enthüllung ~35–45 s statt ~20 s.

## Risiken

1. **Bibliotheksprüfung und Rauswurf:** Scan 2 wirft die Windows-Steam raus, solange sie noch App-Infos lädt. Deshalb kommt Scan 2
   erst, wenn die Zahl steht, und die Windows-Steam startet gleich danach neu. Das ist zu testen.
2. **Versteckt wartendes Anmeldefenster:** `guardWindows` versteckt heute nur, wenn schon jemand angemeldet ist. Für den Halt braucht
   es eine eigene Freigabe. Ein 40 Minuten offener QR funktionierte am 26.10.
3. **Bandbreite:** Erst nach dem Engine-Download starten. Die Windows-Steam lädt danach ihr eigenes Update, und die Konkurrenz um
   die Leitung ist zu messen.
4. **Anderes Konto in Steam für Mac:** Nicht umstellen, Rückfall B (siehe offene Frage 3).
5. **Cloud-Abgleich beim Wechsel:** Belegt durch 28 fehlgeschlagene Abgleiche. R3/R4 sind die eigentliche Arbeit von Phase 2.
6. **1,2 GB für Konten ohne Mac-Spiel:** Wieder entfernen, siehe offene Frage 2.
7. **Testfalle:** Ein Erststart-Test mit `HOME=build/fh` startet `/Applications/Steam.app` über LaunchServices *mit dem echten
   Home*. Dann meldet sich die echte Steam für Mac still an und wirft die echte Windows-Steam raus, und der frische Weg wird gar
   nicht getestet. Phase 2 braucht dafür einen Testmodus: Steam.app in `build/fh/Applications` installieren und das Binary direkt
   mit Umgebung starten statt über `NSWorkspace`.
8. **Token-Verlängerung unbelegt:** Ob Steam vor Mai 2027 ein neues Token holt, zeigt sich am „issued“-Datum in
   `connection_log`. R5 fängt den Fall ab, dass es das nicht tut.

## Dateien und Aufteilung

| Datei | Wer | Was |
|---|---|---|
| `MacSteam.swift`, `MacSteamSetup.swift` | diese Sitzung | `prepare()` (Installieren + versteckter erster Start bis zum Anmeldefenster), `account` (SteamID aus `loginusers.vdf`), `waitingForCredentials`, Halt in `guardWindows`, `quitWhenSynced()`. `MacSteamSetup` bleibt als Rückfall und nutzt `prepare()` mit. |
| neu `SteamSwitch.swift` + kleine Haken in `LibraryModel.swift` (`launchMac`, Spielende, `startBackgroundSteam`) | diese Sitzung | R1–R6. `LibraryModel` gehört keiner der parallelen Sitzungen, Home in `LibraryView.swift` bleibt unberührt. |
| `Setup.swift` | **setup-speed** ändert Interna | Von mir nur Haken (~30 Zeilen): neuer `Step.macSteam`, ein paralleler `Task` nach dem Engine-Schritt, Scan 2 vor `finish()`. Vorschlag: Ich setze sie auf den Stand von setup-speed, nachdem der zusammengeführt ist, oder setup-speed lässt dafür eine Stelle frei. Die Logik liegt in `MacSteam`/`MacSteamPrep`, nicht in `Setup.swift`. |
| `SetupDetail.swift`, `LibraryReveal.swift` (`mac`-Zähler), `L10n` | diese Sitzung | Texte und Live-Zeilen. |
| `SetupView.swift`, Home in `LibraryView.swift` | **design-setup-home** | Anzeige des neuen Schritts, zweiter QR-Hinweis, Zeile in der Enthüllung (Abschnitt 4). |
| `Engine.swift` | setup-speed | Von mir nur eine Zeile in `scheduleSteamShutdown` (`MacSteam.endsWithNightforge()`, für den Testmodus). |
| Tests | diese Sitzung | `tests/SteamSwitchTest/` mit echten Log-Auszügen: Anmeldezustand, gemerktes Konto, die Regeln, Spielstand unterwegs, Erststart-Entscheidung, Testmodus. |

## Entscheidungen (Nutzer, 29.10.2026)

1. **Reihenfolge A:** Der zweite QR kommt direkt nach dem ersten, nur wenn die Bibliothek Mac-Versionen hat.
2. **Konto ohne Mac-Version:** Das eben installierte Steam für Mac wird wieder entfernt.
3. **Steam für Mac mit einem anderen Konto** bleibt in Ruhe (Rückfall B).
4. **Ruhezustand:** Steam für Mac wird nach jedem Mac-Spiel beendet (R2/R3).
5. **Kein „beide gleichzeitig online“.**

## Stand Phase 2

**Gebaut** (nur lokal committet, nicht live getestet):
- `SteamSwitch.swift`
  - `SteamLogin`: Anmeldezustand aus `steamui_login.txt`, gemerktes Konto aus `loginusers.vdf`.
  - `SteamSwitch`: R1–R6.
    - Nach einem Mac-Spiel wartet Nightforge auf den Cloud-Upload (höchstens 3 min), dann beendet es Steam für Mac und
      startet die Windows-Steam versteckt.
    - Vor einem Mac-Spiel geht die Windows-Steam, nachdem ihr letzter Spielstand oben ist (höchstens 60 s).
    - Vor einem Windows-Spiel geht Steam für Mac auf dieselbe Weise, und eine beendete Windows-Steam startet wieder.
    - Die Download-Züge beenden die andere Steam, statt sie rauswerfen zu lassen.
- `MacSteam.swift`
  - `prepare()`, `account`, `waitingForCredentials`, `hold()` (der Fenster-Wächter versteckt das Anmeldefenster),
    `quitWhenSynced()`, `removeFreshInstall()` (nur ein von Nightforge auf einen Mac ohne Steam für Mac gelegtes).
  - **Testmodus** (`isTestHome`: `HOME`/`CFFIXED_USER_HOME` ≠ echtes Home): `Steam.app` nur in `<Test-Home>/Applications`,
    Start direkt über `DetachedProcess` mit der Umgebung, `running` nur Prozesse unter dem Test-Home, kein Beenden per
    Bundle-ID im Shutdown-Skript.
- `MacSteamPrep.swift`: der Erststart-Schritt (vorbereiten → entscheiden → zweiter QR / bereits angemeldet / anderes Konto /
  nicht nötig → entfernen, „Later“) mit Texten. Noch nicht in `Setup.swift` eingehängt.
- `LibraryModel.swift`, Haken an fünf Stellen:
  - Spielende
  - Mac-Start (R5: das Fenster kommt sofort, wenn Steam nach Anmeldedaten fragt; bis zu 10 min, B/Esc bricht ab)
  - Windows-Start
  - Download-Züge
  - App-Start: Ein übrig gebliebenes eigenes Steam für Mac wird höflich beendet, bevor die Windows-Steam startet.
- `restartStuckSteam`: R5 für die Windows-Steam.
- `LaunchPhase`: `.savingToCloud` und `.signInAgain`.
- `SetupDetail.macSteam`, `LibraryReveal.mac`/`macLine`. Alle Texte auf Deutsch.
- **Anzeige** (auf `claude/ux-roadmap-next` a5103ef):
  - Checkliste: eine eigene Zeile „Setting up Steam for Mac“ unter den Windows-Schritten, mit eigenem Zustand
    (läuft nebenher → bereit → angemeldet / nicht nötig).
  - Der QR-Hinweis der Windows-Anmeldung sagt, dass ein zweiter Code folgen kann.
  - „Checking your library“: Sobald die Zahl steht und es Mac-Versionen gibt, ersetzt die Karte „Steam für Mac“ (Zeile,
    QR-Hinweis mit Anzahl, „Show Steam window again“, „Later“) den Skip-Knopf. ↩/A zeigt das Fenster, Esc/B ist „Later“.
  - Enthüllung: eine Zeile zu den Mac-Versionen, bei „Later“ mit dem Hinweis, dass sie beim ersten Spielen kommen.
  - `LibraryReveal.checkLibrary` ruft `MacSteamPrep.finish` vor der Enthüllung auf, aber nur, wenn die Vorbereitung lief.
    Ohne den Haken in `Setup.swift` ändert sich am Erststart also nichts.

- **Haken in `Setup.swift`** (nach setup-speed, 31.10.):
  - `SetupModel.onSignInReady` feuert, sobald Steams Anmeldefenster steht (oder Steam schon angemeldet war). `LibraryModel`
    startet dann `macSteamPrep`.
  - `SetupModel.onClosed` lässt eine noch laufende Vorbereitung bei „Skip“ fallen.
  - **Abweichung vom Plan:** Nicht nach dem Engine-Schritt. Seit setup-speed lädt Steams Update während wineboot, und
    Steams erster Start ist die zeitkritische Phase (Wrapper bei der Dateiprüfung, Browser-Neustart). Steam für Macs 289 MB
    und sein erster Start hätten sich Leitung und Mac damit geteilt. Ab dem Anmeldefenster wartet die Windows-Seite nur noch
    auf den Spieler, der Windows-Weg (2:11) bleibt also unberührt. Dafür kommt der zweite Code rund 30–40 s später
    (Steam für Mac braucht ~70 s bis zu seinem Anmeldefenster). Auf „Checking your library“ zeigt die Mac-Zeile so lange,
    was sie tut.
  - **Kein `Step.macSteam`:** Die Schritte von `SetupModel` laufen nacheinander (ein aktueller Schritt), Steam für Mac
    nebenher. Als Step stünde es auf „fertig“, sobald die Windows-Schritte fertig sind. Seine Zeile hat deshalb ihren
    eigenen Zustand (`MacSteamPrep.state`).
  - **Der zweite Code kommt vor der Enthüllung,** nicht vor `SetupModel.finish()`: Die Entscheidung braucht die Zahl der
    Mac-Versionen, die erst die Bibliotheksprüfung kennt. Vorher wartet `MacSteamPrep` (höchstens 60 s), bis die
    Windows-Steam nach ihrem Hintergrund-Neustart wieder angemeldet ist. Sonst würde sie Steam für Mac rauswerfen, bevor
    es sein Konto gespeichert hat.
- **Testmodus – Leck am 31.10. und die Lösung:**
  - **Was passiert ist:** Ein Erststart in `build/f2` startete um 01:19:32 die echte Steam für Mac
    (`~/Library/Application Support/Steam/Steam.AppBundle/…/steam_osx -silent`). Sie meldete sich mit dem echten Konto an
    und warf die echte Windows-Steam raus.
  - **Ursache** (statisch in Valves Starter nachgesehen): Nach der Installation seines Clients beim ersten Start, und nach
    jedem Update, startet Steam sich selbst neu: über `/bin/sh -c "sleep 1; open -n … --args …"` und über NSWorkspace
    `launchApplicationAtURL`. Beides geht über die Launch Services, und der neue Prozess bekommt die Umgebung der
    Anmeldesitzung: echtes `HOME`, echter Steam-Ordner, echte Anmeldung. Valves Steam für Mac lässt sich im selben
    macOS-Benutzer also nicht in ein Test-Home sperren.
  - **Lösung:** Ein Test-Home startet nie Valves Steam für Mac. An seine Stelle tritt ein Platzhalter (`TestSteam`,
    `MacSteamTestHome.swift`) in `<Test-Home>/Applications/Nightforge Test Steam.app`. Er schreibt nur, was Nightforge liest:
    - das Update in `bootstrap_log` (Dauer über `NIGHTFORGE_TEST_STEAM_SECONDS`, Standard 50 s);
    - das Anmeldefenster in `steamui_login`;
    - die Anmeldung in `connection_log` und `loginusers.vdf`, sobald der Tester „scannt“, also
      `<Test-Home>/Library/Application Support/Steam/sign-in-now` anlegt;
    - `steam://`-Befehle in `console_log`.
  - **Sperren (mehrfach):**
    1. `MacSteam.app` ist im Test-Home nur der Platzhalter. Eine Kopie von Valves Steam.app dort zählt nicht.
    2. `TestSteam.mayLaunch` erlaubt genau ein Programm, das des Platzhalters.
    3. Der Platzhalter selbst bricht ohne `HOME` oder im echten Home ab.
    4. `TestSteam.guardRealSteam` beendet im Test-Home alle 0,25 s jeden Steam-für-Mac-Prozess von Valve (echtes Home,
       `/Applications`, Kopie im Test-Home), der seit dem Start gestartet ist, und meldet das im Fenster und in
       `nightforge-test-guard.log`.
  - **Tests:** `tests/SteamSwitchTest` (Lauf im Test-Home) spielt einen ganzen Erststart mit dem Platzhalter durch und prüft,
    dass kein Steam-für-Mac-Prozess aus dem echten Home startet und das echte `connection_log` unverändert bleibt. Der
    Platzhalter läuft dort im echten Home unter `sandbox-exec` mit gesperrtem echtem Steam-Ordner.
  - **Echter Ende-zu-Ende-Test mit Valves Steam für Mac:** nur in einem eigenen macOS-Benutzerkonto (eigene
    Anmeldesitzung) oder einer VM.
- **Spieler mit eigener Steam für Mac (Regel C):** `prepare` lässt eine schon angemeldete in Ruhe (wie bisher). Eine
  offene, nicht angemeldete wird nicht versteckt und nicht neu gestartet. Nach dem zweiten Code wird nur eine von
  Nightforge gestartete beendet.
- **ipcserver:** Ein verwaistes `ipcserver` der echten Steam für Mac läuft seit 27.10. 23:47:25. Es startete in der Sekunde,
  in der jene Steam-Sitzung endete, das einzige bei über 50 Beendigungen. `MacSteam.quit()` beendet jetzt ein an launchd
  gefallenes `ipcserver` aus Steams eigenem Ordner, sobald kein Client mehr läuft.

## Quellen

- SteamKit2, `LogOnDetails.LoginID` (Doku im Quelltext): https://github.com/SteamRE/SteamKit/blob/master/SteamKit2/SteamKit2/Steam/Handlers/SteamUser/SteamUser.cs
- node-steam-user-Forum, LogonSessionReplaced und logonID: https://dev.doctormckay.com/topic/2553-how-to-fix-error-logonsessionreplaced/
- node-steam-user-Forum, mehrere Sitzungen ohne Unterbrechung: https://dev.doctormckay.com/topic/4539-logging-into-an-account-without-interrupting-existing-steam-network-sessions/
- node-steam-user-Forum, Lebensdauer der Refresh-Tokens: https://dev.doctormckay.com/topic/4607-access-tokens-and-refreshtoken-lifetime
- Steam-Community, zwei PCs werfen sich mit „Session Replaced“ raus: https://steamcommunity.com/discussions/forum/1/4625856213666500441/
- Steam-Community, auf mehreren Rechnern angemeldet, gespielt wird auf einem: https://steamcommunity.com/discussions/forum/0/3874842132571689460
- CrossOver-Nutzer mit zwei Konten für Mac- und PC-Spiele (Umweg, nicht für uns): https://www.reddit.com/r/Codeweavers_Crossover/comments/1ihy50r/question_about_managing_multiple_games/
