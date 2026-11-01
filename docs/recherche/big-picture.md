<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHRmp8uQySbpDtAFBdb (1.11.2026) -->

## Nightforge Big Picture: Recherche und Entwurf

*Stand der Recherche: 1. November 2026. Die Zahlen in eckigen Klammern verweisen auf die Quellen am Ende. Unsichere Aussagen sind als „unsicher“ markiert.*

### Kurzfassung

- Warum Big Picture und der Deck-Spielmodus beliebt sind: Der ganze Kreislauf „einschalten, weiterspielen, zurückkehren“ geht ohne Maus und Tastatur. Die Startseite zeigt sofort die zuletzt gespielten Spiele. Eine Systemtaste öffnet das Hauptmenü, ein zweites Schnellmenü öffnet sich über dem laufenden Spiel. Deck, Fernseher und Desktop sehen gleich aus [1, 3, 6].
- Was stört:Eine native, leichte Oberfläche wie die von Nightforge setzt genau an diesen Schwächen an.
  - eine schwere Web-Oberfläche mit rund 20 % CPU-Last im Leerlauf [22, 23]
  - Ruckeln im Vollbild [24, 25]
  - Fernseher und Monitore, die sich Big Picture nicht merkt [33, 34]
  - gestrichene Funktionen [31, 32]

- Die Neugestaltung: Die Deck-Oberfläche ersetzte das alte Big Picture von 2012. Beta ab 27. 10. 2022, Standard ab 1. 2. 2023 [1, 42]. Seit Oktober 2026 nimmt Valve mit dem „Big Art Mode“ sogar Store-News und Empfehlungen von der Startseite [53, 54].
- Das smarte Menü hat zwei Ebenen plus eine Variante im Spiel:
  - Kurzdruck: ein Schnellmenü als Seitenleiste rechts (Fortsetzen, Spiel beenden, Lautstärke, Tonausgabe, Controller).
  - Langdruck: ein Ein/Aus-Menü (Ruhezustand, Nightforge neu starten oder beenden, Neustart, Ausschalten).
  - Vorbilder sind Switch, Xbox und Steam [69, 102, 132].

- Der Auslöser muss robust sein. L3+R3 ist der garantierte Weg, die Home-, Guide- oder PS-Taste nur ein Zusatz.
  - macOS 26 beansprucht diese Taste für Game Overlay, die Spiele-App oder Spotlight [173, 177].
  - Ob sie sich abschalten lässt, garantiert Apple nicht [188, 189].
  - Das Spiel sieht dieselben Tastendrücke wie Nightforge [184, 190].

- Die meisten Muss-Funktionen kommen ohne Rückfrage von macOS aus: Ruhezustand, Lautstärke und Tonausgabe, Spiel sofort beenden, Nightforge beenden oder neu starten, Controller-Akku, Vollbild ohne Dock und Menüleiste, Bildschirmtastatur für die eigenen Felder.
  - Start bei Anmeldung kann eine einmalige Freigabe unter „Anmeldeobjekte“ brauchen.
  - Neustart und Ausschalten brauchen ein Apple Event und damit womöglich eine Automation-Freigabe [205, 211, 222, 224, 227, 230].

- Nach Quellenlage nicht möglich:Als Ersatz fürs Wecken eignet sich ein „Couch-Standby“: Der Mac bleibt wach, das Display schläft, und eine Controller-Eingabe schaltet es wieder ein [227].
  - den Mac per Controller aus dem echten Ruhezustand wecken (unsicher) [243, 244]
  - die Lautstärke eines Fernsehers über HDMI regeln [232]
  - Game Mode steuern [210]
  - automatische Anmeldung bei aktivem FileVault [215]

- Größtes Risiko ist die Ad-hoc-Signatur. macOS bindet Freigaben an die Signaturidentität, und die ändert sich bei jedem Build. Erteilte Freigaben können deshalb nach jedem Update verloren gehen [266, 269]. Nightforge sollte mit möglichst wenigen Freigaben auskommen und mittelfristig eine stabile Signatur nutzen.
- Bewusst weglassen: Freunde und Chat, Store und Werbung, Feeds, Videohintergründe und Unschärfe-Effekte, Controller-Umbelegung pro Spiel, einen eigenen Browser oder Musikplayer.

### Was Big Picture beliebt macht

- Controller zuerst, „zuletzt gespielt“ zuerst. Die Startseite beginnt mit den zuletzt gespielten Spielen statt mit der Wahl zwischen Store, Bibliothek und Community [3]. Valve nennt es ein „controller-first interface“ [1].
- Zwei Ebenen, ohne das Spiel zu verlassen. Die Systemtaste öffnet das Hauptmenü. Das Quick Access Menu (QAM) bietet „access to notifications, friends list, quick settings, and more“. Es gleitet als Panel von rechts herein; am Desktop öffnet es mit Guide+A [1, 2, 69].
- Eine Oberfläche überall. Am Desktop ist Big Picture „indistinguishable from Steam Deck UI“ [6]. Tests feierten das Ende des „low resolution and ugly Big Picture Mode“ [4, 5], und die Oberfläche gilt als „snappy“ [7, 8].
- Universelle Suche und ein neuer Controller-Konfigurator kamen zum Start im Februar 2023 [4, 5].
- Schnelles Fortsetzen nach dem Ruhezustand: „literally a second or two“ [10]. Unter Windows 11 ist so etwas „simply not available“ [11, 12]. Das ist eine Leistung des Betriebssystems und lässt sich in einem Launcher nicht nachbauen.
- Einstellungen pro Spiel, die von selbst greifen. Leistungsprofile gelten automatisch, das Performance-Overlay hat mehrere Stufen [15, 16].
- Kurzbefehle für den Notfall: Steam+X öffnet die Bildschirmtastatur, Steam+R1 macht einen Screenshot, Steam+B gehalten (etwa 5 s) beendet ein Spiel erzwungen [74, 75, 81].
- Eine gute Oberfläche am Fernseher. Selbst Tests der Steam Machine (2026), die das Gerät kritisch sehen (Engadget 6,5/10 [41]), nennen die TV-Oberfläche „appreciably slick“ und „fantastic“ [13, 14].
- Die Nachfrage nach Controllern wächst. Der tägliche Anteil der Controller-Nutzung auf Steam stieg von 5 % (2018) auf bis zu 15 %. Die Controller verteilen sich auf 59 % Xbox, 26 % PlayStation und 10 % Deck [19, 20]. Glyphen sollten deshalb zuerst für Xbox und PlayStation stimmen.
- Artwork ist Pflicht für Spiele außerhalb von Steam. Das meistinstallierte Decky-Plugin ist SteamGridDB (rund 1,67 Mio., Zahl unsicher) [83, 84]. NonSteamLaunchers holt Epic und GOG in den Spielmodus [85, 86].
- Nachfrage auf dem Mac. Ein Drittprojekt startet SteamOS in einer virtuellen Maschine auf Apple Silicon, nur um den Spielmodus zu bekommen [63, 64]. Für Epic, GOG und Wine fehlt auf dem Mac eine Controller-Oberfläche. Diese Lücke füllt Nightforge.

#### Was Nutzer stört

- Gewicht der Web-Oberfläche (CEF): etwa 20 % CPU im Leerlauf, bis zu 45 % beim Wechsel der Ansicht [22, 23]. Nutzer helfen sich mit Notlösungen [27, 28].
- Ruckeln im Vollbild, während es im kleinen Fenster flüssig läuft [24, 25]. Auch vom Mac gibt es Berichte über starke Verzögerung (unsicher) [26, 61].
- Der Konfigurator kann weniger als der alte und braucht „several extra clicks“ [18].
- Bildschirm und Fernseher: Big Picture öffnet auf dem falschen Monitor, vergisst den Fernseher nach dem Ausschalten und macht ihn zum Hauptbildschirm [33, 34]. Gewünscht wird die native TV-Auflösung [40].
- Gestrichene Funktionen: Webbrowser, lokaler Musikplayer und Community-Tabs [31, 32].
- Weniger Inhalt auf dem Bildschirm nach den größeren Elementen im November 2023: „you actually now see less of the list“ [29, 30].
- Fehler auf dem Deck: Menüs reagieren nach dem Aufwachen nicht mehr [37, 38], früh hing die Lautstärke und die Bildschirmtastatur erschien nicht [9, 39].
- Streit um die Guide-Taste: Die QAM-Kombination scheitert mit Controllern, die nicht vom Deck stammen [76, 77]. Unter Windows kollidieren Steam und Xbox [78, 79].
- Auf dem Mac: Controller funktionieren in Big Picture, aber nicht mehr, sobald das Spiel den Fokus hat [59, 60]. Steam nutzt die Guide-Taste nur, wenn das System sie nicht selbst belegt [21].

#### Was die Neugestaltung verbessert hat

| Datum | Ereignis |
|---|---|
| 2012 | Das ursprüngliche Big Picture erscheint und wird danach kaum gepflegt [43, 44] |
| Juli 2021 | Valve kündigt an, dass die Deck-Oberfläche Big Picture ersetzt [45, 46] |
| 27. 10. 2022 | Beta am Desktop (`-gamepadui`), laut Valve noch mit „rough edges“ [1, 47] |
| Nov. 2022 | QAM-Einträge, die nur auf dem Deck funktionieren, werden am Desktop ausgeblendet [48, 49] |
| 1. 2. 2023 | Standard für alle; `-oldbigpicture` bleibt vorerst als Rückweg [3, 42] |
| Feb. 2023 | F11 wechselt zwischen Fenster und Vollbild, Alt+Enter verlässt den Modus [35, 36] |
| ca. Juni 2023 | `-oldbigpicture` fällt weg (nur Angaben aus der Community, unsicher) [50, 51] |
| Nov. 2023 | Viele optische Anpassungen [30] |
| Juni 2025 | Nativer Client für Apple Silicon (Beta), ohne Änderungen an der Oberfläche [57, 58] |
| Sept./Okt. 2026 | „Big Art Mode“: Startseite ohne Store-News, große Cover, Bildschirmschoner [52, 53, 54] |

Konkret besser wurden die zuletzt gespielten Spiele als Einstieg, Systemmenü plus QAM, die universelle Suche, der Konfigurator und die Profile pro Spiel [3, 4]. Das alte Big Picture galt als „blurry“, mit Tabs, „that simply don’t work“ (Wortlaut unsicher) [55, 56].

**Lehre für Nightforge:** Eine einheitliche Oberfläche zählt mehr als viele Funktionen. Die Nutzer nahmen den Verlust von Browser und Musikplayer hin. Valve hat Funktionen, die eine Plattform nicht kann, ausgeblendet statt ausgegraut [48]. Dieses Muster passt auch für Einschränkungen auf dem Mac.

### Vergleich mit anderen Couch-Oberflächen (nur Übertragbares)

| Plattform | Übertragbare Muster | Anti-Muster |
|---|---|---|
| **Switch / Switch 2** | Eine Reihe zuletzt gespielter Spiele. Das HOME-Menü braucht unter 200 KB und verzichtet bewusst auf Musik, damit es schnell bleibt [128, 129]. HOME ≥ 1 s öffnet die Schnelleinstellungen rechts, B schließt sie [132, 133] | gilt als „bland“; große Bibliotheken brauchen eine Extraseite [130, 131] |
| **Apple TV / Apple-Richtlinien** | Fokus sanft hervorheben und nie ohne Eingabe verschieben [141, 142]. Top Shelf: „jump back into active gameplay“, „Avoid showing advertisements or prices“ [143]. A, B und Schultertasten wie üblich; die Home-Taste ist „reserved for system controls“. Glyphen des aktiven Controllers zeigen [144] | Liquid Glass (tvOS 26) braucht viel Leistung, dazu Berichte über Ruckeln (anekdotisch) [146, 147] |
| **PS5** | Control Center über dem Spiel, „Zurück“ setzt fort [110, 111]. Der Switcher kann Spiele schließen [112]. Redesign 2026 mit L1/R1 für die Tabs [119, 120] | Activity Cards als „busywork“ [114, 115]; Werbung 2024 [117, 118]; Ausschalten braucht 6 Eingaben [123] |
| **Xbox** | Der Hintergrund folgt dem fokussierten Spiel [87, 88]. Zeigen, was läuft, und warnen, wenn ein Spiel nicht fortgesetzt werden kann [93, 95]. Guide halten öffnet Ein/Aus [102] | Werbezeilen vor den eigenen Pins [89, 90]; 2026 nur noch zwei statt drei Werbeplätze [91, 92]; Quick Resume schloss Spiele stillschweigend [94] |
| **NVIDIA Shield / Google TV** | Anpassbare Schnelleinstellungen, BACK halten öffnet Ein/Aus [153, 154] | Autoplay-Werbung (2021) [151, 152]; „sluggish over time“ [145] |
| **Playnite (Vollbild)** | Die Guide-Taste wechselt in den Vollbildmodus. Seit 10.61 holt sie den Fokus nur zurück, wenn kein Spiel läuft [156]. Erweiterungen holen den Fokus zurück [157, 158] | Autostart lässt sich nur im Desktop-Modus einstellen [155] |
| **ES-DE** | Start öffnet das Hauptmenü, Select das Kontextmenü. Schultertasten springen 10 Einträge, Trigger an Anfang oder Ende. Automatische Sammlungen, Kiosk- und Kindermodus, Bildschirmschoner „Dim“, Animationen abschaltbar [159] | Auf dem Mac bleibt der Fokus hängen, wenn der Emulator nicht im Vollbild startet [159] |
| **RetroArch** | Das Quick Menu ist ein Pausenmenü (Fortsetzen, Schließen), Auslöser u. a. **L3+R3** oder Start 2 s halten [160]. L2/R2 springen nach Buchstaben [162]. Die Oberfläche Ozone folgt dem Switch-Stil [161] | – |
| **Heroic Console Mode** (2.21, April 2026) | Guide schaltet um, „Start in Console Mode“, Hinweisleiste, Startbildschirm mit „Abbrechen“, Beenden-Knopf in Warnfarbe [163]. Nintendo-A/B stimmt seit 2.22.1 [165] | L3/R3 als Einzeltaste entfernt: „easy to trigger by accident“ [163]; anfangs nur installierte Spiele [164] |
| **Lutris** | Kein eigener Modus. Ein Drittprojekt bietet „Zuletzt gespielt“, Suche mit Bildschirmtastatur, „Now Playing“, Guide über dem Spiel und ein Systemmenü (Ton, Anzeige, Ruhezustand, Neustart, Aus) [166] | Pausieren nur experimentell [166] |
| **Apple Spiele-App / Game Overlay** (macOS 26) | Mit dem Controller bedienbar; das Overlay öffnet über die Xbox- oder PS-Taste oder ⌘+Esc [173, 174] | „nützlich, aber unzuverlässig“ [175, 176], „barebones“ [181, 182]. Es belegt die Home-Taste |
| **Windows Xbox-Vollbild** | Startet direkt in eine Controller-Oberfläche [96, 97] | „not as user-friendly as you’d expect“ [98] |

**Konventionen, die sich durchgesetzt haben:** A bestätigt, B geht zurück, Schultertasten wechseln Bereiche, Trigger springen weit, die Systemtaste öffnet die Systemebene, ein Langdruck öffnet Ein/Aus oder die Schnelleinstellungen [144, 159]. Nightforges Belegung passt dazu. Lohnend wären zusätzlich:

- L2/R2 für Sprünge nach Buchstaben [162]
- B = Abbrechen auf dem Ladebildschirm [163]
- A/B-Tausch für Nintendo-Controller [165]
- Einstellungen des Konsolenmodus im Konsolenmodus erreichbar, anders als bei Playnite [155]

### Die smarten Menüs der Plattformen

| Plattform | Kurzdruck | Langdruck / zweite Taste | Auffällig |
|---|---|---|---|
| **Steam Deck / Big Picture** | Steam-Menü; unter „Power“: Herunterfahren, Neustart, zum Desktop [70, 71] | „…“ bzw. Guide+A öffnet das QAM: Benachrichtigungen, Freunde, Schnelleinstellungen (Helligkeit, Ton, WLAN, Bluetooth), Leistung (Overlay, FPS-Limit, TDP), Soundtracks, Hilfe [1, 69, 72, 73]. Steam halten zeigt die Kurzbefehle [74] | Die QAM-Kombination ist am Desktop unzuverlässig [76, 77]. Eine aktuelle vollständige Menüliste von Valve fehlt (unsicher) |
| **Xbox Series** | Guide mit Tabs: Home, People, Parties & chats, Achievements, Capture & share, Profile & system [100, 101] | Halten: Konsole aus, Neustart, Controller aus (nur Ratgeber, unsicher) [102, 103] | Spiel beenden braucht 3 Eingaben [108]; „Aus“ ist bei Instant-On nur Standby [103, 104] |
| **ROG Xbox Ally / Windows** | Game Bar mit Schnelleinstellungen und Leistung [105, 107] | Halten: Task View [106] | – |
| **PS5** | Control Center: Karten plus Leiste (Home, Switcher, Benachrichtigungen, Game Base, Musik, Ton, Mikrofon, Zubehör/Akku, Profil, Ein/Aus), anpassbar [112, 121] | Halten führt zu Home (unsicher) [113, 122] | Ausschalten in 6 Eingaben [123], Spiel schließen in 4 oder mehr [124, 125] |
| **Switch 2** | HOME-Menü; in der unteren Leiste u. a. GameChat, eShop, Album, Controller, Einstellungen, Standby [137, 138] | HOME ≥ 1 s: Standby, Helligkeit, Lautstärke, Flugmodus [133, 135] | Standby in 2 Eingaben [135]; Screenshots über eine eigene Taste [140] |
| **Apple TV** | – | TV-Taste halten: Kontrollzentrum (Profile, Ruhezustand, Ton/AirPlay, Controller) [149, 150] | – |
| **Shield** | Schnelleinstellungen [153] | BACK halten: Ruhezustand, Neustart, Aus [154] | – |
| **PC-Handhelds** (ASUS, Lenovo, MSI) | Helligkeit, Leistungsmodus, FPS-Limit, Kacheln (MSI: 12) [169, 170, 171, 172] | MSI: Task View [172] | Leistungsregler gibt es nur auf Handhelds |

**Was wirklich genutzt wird:** Kein Hersteller veröffentlicht Nutzungszahlen. Sony sagt nur, die Telemetrie zeige, was „most popular“ ist [126]. Indirekte Signale:

- Ratgeber „schneller …“ betreffen fast immer Ausschalten und Spiel beenden [123, 124].
- Die Hersteller machen ihre Menüs anpassbar [112, 168].
- Xbox hat 2020 den Guide für „notifications, search, and audio settings“ vereinfacht [100].

**Gemeinsamer Kern:** Home bzw. Bibliothek, Spiel beenden, Ein/Aus, Ton (Lautstärke und Ausgabe), Benachrichtigungen, Controller und Akku, Einstellungen. Screenshots laufen fast immer über eine eigene Taste [127, 140].

Kein Konsolenmenü kann ein hängendes Spiel wirklich beenden; dann bleibt nur, den Netzschalter etwa 10 s zu halten [108, 125]. Am nächsten kommt Steam+B gehalten [81].

### Entwurf des smarten Menüs

#### Auslöser: L3+R3 garantiert, die Home-Taste nur als Zusatz

- Unter macOS 26 „might open Game Overlay, Games, or Spotlight“ ein Druck auf die Home-Taste [177]. Das System bekommt die Taste zuerst [187]. preferredSystemGestureState = .disabled „isn’t guaranteed to be respected“ und fiel in macOS 14.2 schon einmal aus [188, 189].
- Hintergrund-Eingaben (shouldMonitorBackgroundEvents) kommen ohne dokumentierte Freigabe an [184]. Sie sind aber nicht exklusiv: Das Spiel sieht dieselben Tasten [190]. Exklusiver Zugriff würde dem Spiel den Controller nehmen [191].
- Garantierter Weg ist L3+R3. Er ist als Overlay im Spiel schon vorhanden; RetroArch macht es genauso [160]. Vorschlag (ungetestet): Die Kombination löst erst nach etwa 0,5 s Halten aus, damit Spiele, die L3+R3 selbst nutzen, weniger gestört werden.
- Zusatzweg ist Home/Guide/PS. Solange Nightforge vorne ist, schaltet es die Systemgeste wie SDL ab [190]; im Spiel klappt das nur vielleicht. Die Hinweisleiste zeigt deshalb immer „L3+R3“.
- Tastatur: ⌘+Esc gehört dem Game Overlay [173]. Ein globales Kürzel bräuchte die Eingabeüberwachung [194], deshalb verzichtet Nightforge darauf. Esc geht zurück, wenn Nightforge vorne ist.

#### Ebenen

1. Nightforge-Oberfläche (Bühne, Bibliothek), mit der bestehenden Belegung.
2. Schnellmenü (Kurzdruck): Seitenleiste rechts, etwa ein Drittel der Breite, wie Switch, QAM und Apple TV [69, 135]. B schließt. Im Spiel gibt es eine eigene Variante mit einer Karte zum laufenden Spiel.
3. Ein/Aus-Menü (Langdruck oder letzter Eintrag im Schnellmenü): ein kleines zentriertes Blatt, wie bei Xbox und Shield [102, 154].
4. Bestätigungsblatt für alles, was Spielstand oder die Sitzung kosten kann.

**Im Spiel in zwei Stufen:**

- (a) Robust und sofort: Nightforge kurz nach vorn holen. Das Spiel verliert dabei den Fokus und damit Game Mode [204, 271].
- (b) Ziel: ein Panel über dem Vollbildspiel, das das Spiel nicht in den Hintergrund schickt. Apple-DTS hat das Rezept für macOS 26 bestätigt, das Spiel bleibt vorne [200]. Dafür braucht es einen kleinen Agent-Helfer, der nur während des Spiels läuft.

Weil Eingaben auch beim Spiel ankommen, bekommt „Fortsetzen“ den Standardfokus, und das Menü bleibt kurz.

#### Tastenbelegung

| Eingabe | In Nightforge | Menü offen | Im Spiel |
|---|---|---|---|
| A | Auswählen / Starten | Ausführen | gehört dem Spiel |
| B | Eine Ebene zurück | Schließen; im Spielmenü = Fortsetzen | gehört dem Spiel |
| ☰ kurz (beim Loslassen) | Optionen zum fokussierten Element | – | gehört dem Spiel |
| ☰ halten (≥ 1 s) | Ein/Aus-Menü | – | gehört dem Spiel |
| Y | Suche | – | gehört dem Spiel |
| L1 / R1 | Startseite / Bibliothek | – | gehört dem Spiel |
| L2 / R2 (neu) | Sprung nach Buchstabe oder Seite [162] | – | gehört dem Spiel |
| Steuerkreuz / linker Stick | Fokus | Fokus; links/rechts ändert Regler | gehört dem Spiel |
| **L3+R3 (ca. 0,5 s)** | Schnellmenü | Schließen | **Schnellmenü im Spiel (garantiert)** |
| Home/Guide/PS kurz | Schnellmenü (wenn möglich) | Schließen | nur vielleicht; kann Apples Game Overlay öffnen |
| Home/Guide/PS halten | Ein/Aus-Menü (wenn möglich) | – | nur vielleicht |
| L3 oder R3 einzeln | keine Funktion [163] | – | gehört dem Spiel |
| A halten (ca. 1,5 s) | – | bestätigt Neustart, Ausschalten, Sofort beenden | – |

Die Belegung folgt der Tastenposition; bei Nintendo-Controllern tauscht Nightforge Glyphen und A/B [156, 165]. Die Hinweisleiste zeigt die Glyphen des aktiven Controllers [144].

#### Einträge in Reihenfolge

**Schnellmenü im Spiel:**

1. Kopfzeile: Cover, Spielname, Spielzeit der Sitzung, Uhrzeit, Controller-Akku
2. Fortsetzen: Standardfokus, B tut dasselbe
3. Spiel beenden …: mit Bestätigung, bei Bedarf danach „Sofort beenden“
4. Zu Nightforge: Das Spiel läuft weiter, auf der Startseite erscheint die Karte „Läuft gerade“ [166]
5. Lautstärke: Regler; bei einem HDMI-Fernseher steht dort „Lautstärke am Fernseher regeln“ [232]
6. Tonausgabe: Geräteliste, die Wahl wird pro Fernseher gemerkt (vorhanden)
7. Controller: verbundene Pads mit Akkustand, sonst „keine Angabe“ [195, 197]
8. Leistung: FPS-Anzeige, Bildratenlimit; gilt ab dem nächsten Spielstart [264]
9. (Kann) Bildschirmtastatur: nur mit Freigabe, sonst ausgeblendet
10. (Kann) Screenshot: Das Menü schließt zuerst, dann wird aufgenommen
11. Ein/Aus …

**Schnellmenü in Nightforge:** Lautstärke · Tonausgabe · Controller · Downloads (nur sichtbar, wenn etwas lädt) · Anzeige (Fernseher bzw. Bildschirm, Auflösung) · Konsolenmodus (Start bei Anmeldung, Couch-Standby) · Ein/Aus …

**Ein/Aus-Menü**, sortiert von harmlos bis folgenreich:

1. Ruhezustand (Standardfokus, ohne Rückfrage)
2. Nightforge neu starten
3. Konsolenmodus verlassen
4. Nightforge beenden
5. Neustart …
6. Ausschalten …
7. (Kann) Abmelden …

#### Regeln für folgenreiche Aktionen

- Ruhezustand: ohne Rückfrage, wie auf Switch, Apple TV und PS5 [135, 149].
- Spiel beenden:Das entspricht Steam+B gehalten [81]. Die Technik ist da: `wineserver -k`, `forceTerminate()` [264, 270].
  1. Ein Blatt fragt „Spiel beenden? Nicht gespeicherter Fortschritt geht verloren.“ Der Fokus steht auf „Abbrechen“.
  2. Nightforge beendet das Spiel regulär.
  3. Läuft der Prozess nach etwa 10 s noch, erscheint „Spiel reagiert nicht – Sofort beenden“, bestätigt mit A halten.

- Nightforge neu starten, beenden, Konsolenmodus verlassen: sofort, wenn weder Spiel noch Download läuft; sonst fragt Nightforge nach und sagt, was mit Spiel oder Download passiert.
- Neustart, Ausschalten, Abmelden:
  1. Ein Blatt erscheint, der Fokus steht auf „Abbrechen“, A halten führt aus.
  2. Nightforge beendet zuerst Steam und Wine sauber.
  3. Dann folgt das Apple Event.
  4. Verhindert eine andere App das Ausschalten (das ist erlaubt [222]), zeigt Nightforge das an, statt still zu scheitern.

- Immer: B bricht ab. Keine folgenreiche Aktion liegt auf einem einzelnen Stick-Klick [163]. Der Fokus bewegt sich nie von selbst [141].

#### Bildschirmtastatur und Suche

- Layout: ein Gitter mit großen Tasten, wie bei tvOS und Microsofts neuer Gamepad-Tastatur [99, 148].
- Bedienung: Live-Ergebnisse nach ein bis zwei Zeichen. X löscht, die Schultertasten bewegen den Cursor [159].
- Weniger Tippen dank Buchstabensprung und automatischer Regale [162, 166].
- Eine echte Tastatur funktioniert immer im selben Feld [144].
- Lehre aus Steam: Die automatische Erkennung von Textfeldern ist am Desktop unzuverlässig. Deshalb braucht es zusätzlich einen festen Aufruf [67, 68].

### Funktionsliste

| Funktion | Priorität | Aufwand | Nutzen | Machbarkeit auf dem Mac |
|---|---|---|---|---|
| Auslöser L3+R3 in Nightforge und im Spiel (Hintergrund-Eingabe) | Muss | M | ohne ihn kein Menü im Spiel | leicht; keine Rückfrage; Fehler in macOS 15.4 beachten |
| Schnellmenü als Seitenleiste (beide Varianten) | Muss | M | Kern des Big-Picture-Gefühls | leicht in Nightforge; über dem Spiel siehe Overlay |
| Fortsetzen / Zu Nightforge / Karte „Läuft gerade“ | Muss | S | Rückweg ohne ⌘+Tab | leicht (weitgehend vorhanden) |
| Spiel beenden und Sofort beenden (zweistufig) | Muss | S | Hänger nur mit dem Controller lösen | leicht (vorhanden) |
| Ruhezustand | Muss | S | häufigste Ein/Aus-Aktion | leicht, keine Rückfrage |
| Neustart / Ausschalten mit Bestätigung | Muss | M | Couch ganz ohne Tastatur | mit Einschränkungen (Apple Event, eventuell Automation-Freigabe) |
| Nightforge neu starten / beenden / Konsolenmodus verlassen | Muss | S | ausdrücklich gewünscht, Ausweg bei Problemen | leicht |
| Lautstärke und Stumm | Muss | S | ständig gebraucht | leicht; bei HDMI-Fernsehern nicht möglich, dann ein Hinweis |
| Tonausgabe wählen (pro Fernseher gemerkt) | Muss | S | Fernseher oder Kopfhörer | leicht; einzelnes AirPlay-Ziel: schwer |
| Controller und Akku | Muss | S | leere Pads vermeiden | leicht, je nach Gerät |
| Vollbild ohne Dock und Menüleiste | Muss | S | Konsolengefühl | leicht |
| Start bei Anmeldung (Schalter im Konsolenmodus) | Muss | S | „einschalten und spielen“ | leicht; mit Ad-hoc-Signatur testen |
| Bildschirmtastatur für eigene Felder | Muss | M | Suche ohne Tastatur | leicht (reines SwiftUI) |
| Hinweisleiste mit Glyphen, Nintendo-A/B nach Position | Muss | S | Orientierung, weniger Fehlgriffe | leicht |
| Zustände sichtbar machen (Ladebildschirm mit B = Abbrechen, Hinweis bei verlorenem Fokus) | Muss | S | Vertrauen | leicht |
| Overlay über Vollbildspielen (Panel plus Agent-Helfer) | Sollte | L | Spiel bleibt vorne, Game Mode bleibt an | mit Einschränkungen |
| Couch-Standby (Mac wach, Display schläft, Controller weckt das Display) | Sollte | M | Ersatz für „Controller weckt den Mac“ | mit Einschränkungen |
| Downloads im Schnellmenü | Sollte | S | Status ohne Umweg | Steam leicht (vorhanden); Epic mit Einschränkungen; GOG offen |
| Leistung: FPS-Anzeige und Bildratenlimit | Sollte | S | für Fortgeschrittene, spart Akku | leicht (vorhanden, gilt ab dem nächsten Start) |
| Anzeige: Fernseher, Auflösung, Bildrate (Standard: native TV-Auflösung) | Sollte | M | löst die TV-Probleme, die Big Picture plagen | leicht |
| Automatisch in den Konsolenmodus, wenn Fernseher oder Controller kommt (einmal fragen) | Sollte | M | Komfort wie bei Playnite und Heroic | machbar (nicht eigens geprüft) |
| L2/R2-Sprung, automatische Regale | Sollte | S | große Bibliotheken ohne Tippen | leicht |
| Abkürzungen in die Systemeinstellungen (Bluetooth, WLAN, Ton, Displays) | Sollte | S | Ausweg, wenn etwas fehlt | leicht; die Systemeinstellungen selbst sind kaum per Controller bedienbar |
| Artwork für alle Stores, automatisch und offline zwischengespeichert | Sollte | M | Spiele außerhalb von Steam wirken sonst zweitklassig | keine Hürde |
| Abdunkeln bei Leerlauf statt Video-Bildschirmschoner | Sollte | S | schont den Fernseher, bleibt ruhig | leicht |
| Hinweise in der App (Download fertig, Akku schwach) | Sollte | S | ersetzt ein Mitteilungscenter | leicht, ohne Freigabe |
| Helligkeit (eingebautes Display, DDC-Monitore) | Kann | M | MacBook am Sofa | mit Einschränkungen (private APIs); Fernseher nicht möglich |
| Bildschirmtastatur für andere Apps | Kann | M | z. B. Anmelden in Steam unter Wine | mit Einschränkungen (Bedienungshilfen-Freigabe) |
| Screenshot | Kann | S (Hinweis auf Systemfunktion) / M (eigene Aufnahme) | Erinnerungen | Systemweg leicht; eigene Aufnahme mit Einschränkungen |
| Controller-Kopplung in der App | Kann | L | Erstkontakt ohne Systemeinstellungen | mit Einschränkungen (Bluetooth-Freigabe, Henne-Ei-Problem) |
| WLAN-Status | Kann | S | Diagnose | Status leicht; WLAN beitreten schwer |
| Abmelden; Zufallsspiel; Kindermodus | Kann | S–M | mehrere Nutzer, Spaß, Familie | leicht |

### Bewusst weglassen

- Freunde, Chat, Party, Online-Status. Das braucht Konto und Server und widerspricht „kein Konto, keine Telemetrie“. Steam und Apples Game Overlay decken es schon ab [173]. GameChat auf der Switch kostet sogar ein Abo [139].
- Store, Angebote, Werbung, „News“. Das ist der meistkritisierte Fehler aller Couch-Oberflächen [89, 117, 151]. Apple rät davon ab [143]. Valve räumt 2026 selbst die Startseite auf [53].
- Erfolgs- und Aktivitäts-Feeds, „Vorschläge für dich“. Gelten als „busywork“ [114, 115] und brauchen ein Konto oder Telemetrie.
- Videohintergründe, Autoplay-Trailer, Hintergrundmusik, schwere Glas- und Unschärfe-Effekte.Eine statische Überblendung des Covers genügt.
  - Die Switch bleibt unter 200 KB und verzichtet auf Musik [128].
  - Liquid Glass auf tvOS 26 frisst Leistung [146].
  - Die CPU-Last ist die meistgenannte Klage über Big Picture [22].

- Controller-Umbelegung pro Spiel oder eine eigene Eingabeschicht wie Steam Input.
  - Der Konfigurator war ein Hauptkritikpunkt [18].
  - Steam Input stört auf dem Mac [60, 65].
  - macOS bietet eine eigene Tastenbelegung [192].

- Eigener Browser, Musikplayer, Medien-Apps. Valve hat genau das gestrichen und Ärger geerntet [31, 32]. Besser gar nicht erst versprechen.
- WLAN in der App beitreten, HDR-Schalter, AirPlay-Ziele, TV-Lautstärke oder CEC über HDMI. Dafür gibt es keinen sauberen Weg [232, 235, 241, 250, 253].
- Mehrere pausierte Spiele wie Quick Resume. Mit Wine- und Mac-Spielen nicht nachzubauen. Besser ehrlich zeigen, was gerade läuft [93, 95].
- Kiosk-Sperren (⌘-Tab oder Sofort beenden blockieren) [205]. Das wäre nutzerfeindlich.
- Automatische Anmeldung einschalten. Dafür gibt es keine API, und mit FileVault geht sie gar nicht [215, 216]. Nightforge kann das nur erklären.
- Hintergrunddienst, LaunchAgent, Daemon. SMAppService.mainApp reicht [211]. Ein Overlay-Helfer läuft nur als Kindprozess während des Spiels [200].
- Systemweite Maussteuerung per Controller und macOS-Mitteilungsbanner. Beides bräuchte Freigaben, die bei jedem Update verloren gehen können [194, 269].

### Machbarkeit auf macOS

| Funktion | API / Weg | Rechte / Rückfragen von macOS | Hürde | Bewertung |
|---|---|---|---|---|
| Controller-Tasten im Hintergrund lesen | `GCController.shouldMonitorBackgroundEvents` (ab 11.3) [184] | keine dokumentiert | Fehler in 15.4, behoben in 15.5 [185, 186]; das Spiel bekommt die Eingaben mit | leicht |
| Guide/Home/PS abfangen, während ein Spiel vorne ist | `buttonHome` + `preferredSystemGestureState` [187, 188] | keine | das System hat Vorrang [177, 178]; Abschalten nicht garantiert, Rückschritt in 14.2 [189] | schwer (unzuverlässig) |
| Home-Taste in Nightforge selbst | wie oben, solange Nightforge vorne ist [190] | keine | nicht garantiert [188] | mit Einschränkungen |
| L3+R3 als Auslöser | GameController, Hintergrund-Eingabe | keine | Spiele, die L3+R3 selbst nutzen | leicht |
| Exklusiver Controller-Zugriff | IOHID Seize [191] | Eingabeüberwachung, wenn alle HID-Geräte geöffnet werden [193] | nimmt dem Spiel den Controller | nicht sinnvoll |
| Ruhezustand | `IOPMSleepSystem` [227], `pmset sleepnow` [228] | keine („root or the console user“) | – | leicht |
| Neustart, Ausschalten, Abmelden | Apple Event an loginwindow (QA1134) [222, 223] oder System Events [224] | System Events: Automation-Rückfrage plus `NSAppleEventsUsageDescription` [224, 225]; loginwindow direkt: ungetestet | andere Apps können abbrechen [222]; ohne Usage-String scheitert es still mit −1743 [226] | mit Einschränkungen |
| Nightforge beenden / neu starten | `NSApp.terminate`, `NSWorkspace.openApplication` [271, 272] | keine | – | leicht |
| Spiel sofort beenden | `wineserver -k`, `forceTerminate()` [229, 264, 270] | keine (nicht sandboxed) | Prozessbaum dem Spiel zuordnen | leicht (vorhanden) |
| Lautstärke, Stumm | CoreAudio `VirtualMainVolume` [230] | keine | HDMI/DisplayPort ohne Lautstärkeregler [232, 233] | leicht; Fernseher über HDMI: nicht möglich |
| Tonausgabe wählen | Standard-Ausgabegerät per CoreAudio setzen [231] | keine | einzelne AirPlay-Ziele nicht gezielt wählbar [235, 236] | leicht; AirPlay: schwer |
| Helligkeit, eingebautes Display | privates DisplayServices [237, 238] | keine | kann mit jedem Update brechen | mit Einschränkungen |
| Helligkeit, externer Monitor | DDC über privates `IOAVService` [234, 239] | keine | nicht über HDMI an manchen Mac minis; Fernseher meist ohne DDC [234] | mit Einschränkungen; Fernseher: nicht möglich |
| Auflösung, Bildrate, Hauptbildschirm | `CGConfigureDisplayWithDisplayMode` (vorhanden) [240, 265] | keine | Nebenwirkungen bei gespiegelten Displays [240] | leicht |
| HDR an/aus | keine öffentliche API [241, 242] | UI-Skripting bräuchte Bedienungshilfen | nur Umschalten, kein fester Zustand | schwer |
| Anmeldeobjekt | `SMAppService.mainApp.register()` (ab 13) [211] | eventuell Freigabe unter „Anmeldeobjekte“ [211, 212] | Verhalten mit Ad-hoc-Signatur undokumentiert [213, 214] | leicht (testen) |
| Automatische Anmeldung | keine API | mit FileVault gesperrt [215, 216] | – | nicht möglich |
| Vollbild ohne Dock und Menüleiste | `presentationOptions` `[.hideDock, .hideMenuBar]` mit `toggleFullScreen` [203, 205] | keine | Kombinationsregeln, sonst Exception [205]; gilt nur, solange Nightforge vorne ist; mehrere Displays ungetestet | leicht |
| Kiosk-Sperren | `disableProcessSwitching` usw. [205] | keine | nutzerfeindlich | möglich, nicht empfohlen |
| Mac per Bluetooth-Controller wecken | kein Weg; die alte Bluetooth-Weckoption galt Tastatur und Maus und ist auf Apple Silicon verschwunden [243, 244] | – | kein Beleg für Controller [245] | nicht möglich (unsicher) |
| Couch-Standby als Ersatz | `IOPMAssertionCreateWithName` + `IOPMAssertionDeclareUserActivity` [227] | keine („No special privileges are necessary“) | nur solange Nightforge läuft; mehr Stromverbrauch | mit Einschränkungen |
| Bildschirmtastatur für eigene Felder | SwiftUI | keine | – | leicht |
| Bildschirmtastatur für andere Apps | `CGEvent` posten, `CGRequestPostEventAccess` [194, 217] | Bedienungshilfen [218] | sichere Eingabefelder offen [219]; Freigabe geht nach Updates verloren | mit Einschränkungen |
| Bedienungshilfentastatur von macOS öffnen | nur UI-Skripting [220, 221] | Bedienungshilfen | fragil | nicht zuverlässig möglich |
| Overlay über Vollbildspiel in einem anderen Space | `NSPanel` `.nonactivatingPanel`, Ebene `.screenSaver`, `[.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]`, App als `.accessory` [200, 201] | keine | Agent-Helfer nötig; nicht über „captured displays“ [202]; Direct-to-Display entfällt, solange das Overlay sichtbar ist [203]; mit Wine ungetestet | mit Einschränkungen |
| Einträge in Apples Game Overlay | keine API gefunden | – | – | nicht möglich |
| Controller-Kopplung in der App | `IOBluetoothDeviceInquiry`, `IOBluetoothDevicePair` [246, 247] | Bluetooth-Freigabe, `NSBluetoothAlwaysUsageDescription` [248] | Henne-Ei-Problem; mit DualSense, Xbox und Switch Pro ungetestet | mit Einschränkungen; Deep-Link in die Einstellungen: leicht [249] |
| WLAN beitreten | CoreWLAN `associate(to:password:)` [253] | Ortungsdienste für Netznamen [250]; eventuell Admin-Passwort [253] | Netznamen teils leer [251, 252] | schwer; Status plus Deep-Link: leicht |
| Screenshot (eigene Aufnahme) | ScreenCaptureKit `SCScreenshotManager` [254, 255] | Bildschirmaufnahme; seit Sequoia monatliche Bestätigung, für 26/27 unsicher [256, 257] | Freigaben verschwinden [258, 269] | mit Einschränkungen |
| Screenshot über die Systemfunktion | Tastenaktion des Controllers in macOS 26 (Bild, Clip bis 15 s) [178, 183] | keine für Nightforge | nur ein Hinweis möglich | leicht |
| FPS-Anzeige, Bildratenlimit | `MTL_HUD_ENABLED`, `dxgi.maxFrameRate`, `d3d11.preferredMaxFrameRate`, `D3DM_MAX_FPS` [206, 207] | keine | gilt ab dem nächsten Spielstart [264]; die Anzeige zeigt die Übersetzungsschicht [208] | leicht (vorhanden) |
| Game Mode | automatisch über `LSSupportsGameMode`, Vollbild und vorne [204, 210] | – | keine API; schaltet der Nutzer ihn ab, bleibt er aus [209] | nicht steuerbar |
| Downloads | Steam: `appmanifest_*.acf`, `content_log.txt` [273, 274]; Epic: Legendary [259] | keine | Epic-Launcher für macOS nicht importierbar [259]; GOG unbekannt | Steam leicht (vorhanden); Epic mit Einschränkungen; GOG offen |
| Controller-Akku | `GCController.battery` [195, 196] | keine | manche Pads liefern `nil` oder hängen bei 0 [197, 198] | leicht, je nach Gerät |
| Mac-Akku, Stromsparmodus | IOPowerSources, `isLowPowerModeEnabled` [227, 271] | keine | – | leicht |

### Risiken und offene Tests

**Risiken:**

1. Ad-hoc-Signatur und Freigaben. build.sh signiert mit codesign --force --deep --sign - [266]. Die App ist nicht notarisiert, nicht sandboxed und aktualisiert sich selbst [267]. macOS bindet Freigaben an die Signaturidentität, und die ändert sich bei jedem Build [269]. Usage-Strings fehlen bisher [268].
  - Alle Muss-Funktionen ohne Freigaben bauen.
  - Freigabepflichtiges nur auf Wunsch anbieten und den Status bei jedem Start prüfen.
  - Eine stabile Signaturidentität anstreben; ob ein selbst signiertes Zertifikat genügt, ist ungeprüft.

2. Die Home-Taste bleibt Sache des Systems. macOS 27 ist laut Drittquellen seit 14. 9. 2026 verfügbar [262, 263]. Es soll die Controller-Einstellungen und das Game Overlay verändern (unsicher) [260, 261].
3. Eingaben sind nicht exklusiv. Das Spiel sieht die Navigation im Menü mit [184, 190].
4. Fokus und Game Mode. Holt sich Nightforge nach vorn, endet Game Mode [204]. Ein normales Fenster kann ein Vollbildspiel aus seinem Space verdrängen [200].
5. Private APIs brechen. Ein Beispiel: MonitorControl braucht für macOS 27 Version 4.4.0 [234]. Helligkeit bleibt deshalb Kann.
6. macOS 15.4 in die Tests aufnehmen. Dort fielen Hintergrund-Eingaben aus [185].
7. Steam für Mac und Steam Input können Controller oder die Guide-Taste beanspruchen [60, 65].
8. Couch-Standby kostet Strom und sollte auf MacBooks nur am Netzteil gelten [227].
9. Rosetta 2: macOS 27 ist laut Berichten die letzte Version mit voller Unterstützung (unsicher) [57, 62]. Das betrifft den Weg über Wine.
10. Älterer öffentlicher Code. Ausgewertet wurde nur der öffentliche Stand (Commit ffd6285). Aussagen wie „fehlt noch“ können den lokalen Stand unterschätzen [275].

**Auf einem echten Mac testen (macOS 14, 15.4/15.5, 26, 27):**

1. Bekommt Nightforge im Hintergrund buttonHome? Getrennt prüfen bei SDL-, Wine- und nativen Spielen.
2. Lässt sich der Kurzdruck der Home-Taste in den Systemeinstellungen abschalten?
3. Wie oft kollidiert L3+R3 mit Spielen, und hilft eine Haltezeit von 0,5 s?
4. Fragt macOS bei Apple Events direkt an loginwindow nach?
5. Erscheint das Panel über Vollbildspielen (nativ, Wine, CrossOver)? Bleibt Game Mode an?
6. Überleben Anmeldeobjekt und Freigaben ein Update mit Ad-hoc-Signatur oder selbst signiertem Zertifikat?
7. Welche Controller melden ihren Akku?
8. Weckt irgendein Controller einen Mac aus dem Ruhezustand?
9. Koppelt IOBluetoothDevicePair DualSense, Xbox und Switch Pro?
10. Blendet hideMenuBar bei mehreren Displays nur auf dem Fernseher aus?
11. Kommen gepostete Zeichen in Wine-Feldern an?
12. Wie oft fragt macOS 26/27 erneut nach der Bildschirmaufnahme?
13. Erkennt das Game Overlay die Spiele, die Nightforge startet?
14. Reagiert Steam für Mac auf die Guide-Taste, während ein Nightforge-Spiel läuft?

### Unsicherheiten und gesperrte Hosts

**Wie belastbar die Ergebnisse sind:**

- Viele Seiten ließen sich in der Rechercheumgebung nicht öffnen.
- Für die Stimmung um Big Picture und für die Guide-Menüs war kein Abruf ganzer Seiten möglich. Diese Teile stützen sich auf Auszüge aus Suchergebnissen; Zitate sind deshalb nur nahezu wörtlich.
- Es gab keinen praktischen Test auf einem Mac.
- Reddit wurde nicht als Quelle genutzt.

**Gesperrt oder nicht erreichbar** (DNS-Sperre oder Proxy 403):

- Video und Wissen: youtube.com (deshalb keine Videotests), wikipedia.org, reddit.com
- Apple-Umfeld: support.apple.com, macstories.net, forums.macrumors.com, 9to5mac.com, weblog.rogueamoeba.com
- Konsolenhersteller: xbox.com, news.xbox.com, playstation.com, blog.playstation.com, nintendo.com, en-americas-support.nintendo.com. Offizielle Seiten werden zitiert, wo die Suche sie fand, ihr Volltext wurde aber nicht gelesen.
- Launcher und Frontends: playnite.link, api.playnite.link, es-de.org, libretro.com, docs.libretro.com, lutris.net, heroicgameslauncher.com, openemu.org, chimeraos.org
- Presse: pcgamer.com, pcgamesn.com, theverge.com, kotaku.com, windowscentral.com, pushsquare.com, digitalcitizen.life, howtogeek.com, gamingonlinux.com
- Sonstige: dev.to, support.logi.com, GitHub-REST-API
- Laut Proxy-Protokoll ebenfalls abgewiesen: retroarch.com, bazzite.gg, moonlight-stream.org, web.archive.org, support.google.com

**Was funktionierte:** developer.apple.com (Doku-Endpunkte für JSON und Markdown, Richtlinien, Developer Forums), raw.githubusercontent.com (SDL-Code, libretro-Doku), die Rohdatei des ES-DE-Handbuchs auf GitLab und GitHub-Seiten (Releases von Playnite und Heroic, Heroic-PR [#5490](https://github.com/LordHayne/Nightforge/pull/5490), Lutris Gamepad UI, Spiegel der SDK-Header, MonitorControl, blueutil, Legendary).

**Ausdrücklich unsicher:**

- alles zu macOS 27
- der Langdruck bei PS5 und Xbox
- die Download-Zahlen von Decky
- ob ein Controller den Mac weckt
- ob Nightforge im Hintergrund buttonHome bekommt
- ob macOS bei Apple Events an loginwindow nachfragt
- wie oft macOS nach der Bildschirmaufnahme fragt
- die vollständige Menüliste von Steam
- die Schnelleinstellungen der Switch 1
- die Daten rund um -oldbigpicture
- die Pin-Limits bei Xbox

### Quellen

#### Steam Big Picture und Steam Deck: Ankündigung, Tests, Lob

- [1] Valve / Steam
- [2] Digital Trends
- [3] ComputerBase
- [4] Liliputing
- [5] Pocket-lint
- [6] Notebookcheck
- [7] Tom’s Guide
- [8] GameStar Steam-Deck-Test
- [9] Digital Trends
- [10] TechRaptor
- [11] GamingOnLinux
- [12] HotHardware
- [13] Club386
- [14] PCGamesN
- [15] Wccftech
- [16] MakeUseOf
- [17] ResetEra
- [18] Steam Client Beta (Forum)
- [19] Valve / Steam
- [20] TechRadar
- [21] Steam Support

#### Steam Big Picture: Kritik und Fehlerberichte

- [22] Steam Client Beta (Forum)
- [23] Steam-Forum
- [24] Steam-Forum
- [25] Steam-Gruppe Big Picture
- [26] Steam Client Beta (Forum)
- [27] Steam Client Beta (Forum)
- [28] TheWindowsClub
- [29] ResetEra
- [30] GamingOnLinux
- [31] Steam-Forum
- [32] Steam Client Beta (Forum)
- [33] Steam-Forum
- [34] Steam-Forum
- [35] Linux Today
- [36] playingtux
- [37] Steam-Deck-Forum
- [38] Steam-Deck-Forum
- [39] TechRadar
- [40] Gamers Nexus
- [41] Engadget

#### Steam Big Picture: Neugestaltung und Zeitleiste

- [42] Valve / Steam
- [43] Wikipedia
- [44] WinFuture
- [45] ResetEra
- [46] Tom’s Guide
- [47] Neowin
- [48] GamingOnLinux
- [49] GamingOnLinux
- [50] Steam-Community-Guide
- [51] Steam-Forum
- [52] PC Gamer
- [53] GamingOnLinux
- [54] Mixed-news
- [55] PC Gamer
- [56] Notebookcheck

#### Steam auf dem Mac

- [57] TechRadar
- [58] Tom’s Guide
- [59] Apple Community 256249135
- [60] Steam für Mac (Forum)
- [61] Steam für Mac (Forum)
- [62] Steam für Mac (Forum)
- [63] GitHub fxgl/steamac
- [64] FX Steam Launcher
- [65] Klei Forums
- [66] Steam-Forum

#### Steam-Menü, Quick Access Menu und Kurzbefehle

- [67] Defold Forum
- [68] Steam-Deck-Forum
- [69] Steam-Community-Guide
- [70] Pi My Life Up
- [71] XDA
- [72] PCWorld
- [73] overkill.wtf
- [74] holdtoreset
- [75] Digital Trends
- [76] Steam-Deck-Forum
- [77] Steam Client Beta (Forum)
- [78] Steam-Forum
- [79] Steam-Forum
- [80] Steam-Deck-Forum
- [81] Beebom

#### Decky Loader und SteamOS-Erweiterungen

- [82] TwelfTech (SteamOS 3.8, Wecken per Steam Controller; schwache Quelle)
- [83] Nerdzap
- [84] shattered.io
- [85] Windows Central
- [86] Beebom

#### Xbox und Windows

- [87] Pure Xbox
- [88] iPhone in Canada
- [89] PiunikaWeb
- [90] Windows Central
- [91] Windows Central
- [92] Digital Citizen
- [93] VGC
- [94] GamesRadar
- [95] GameSpot
- [96] Xbox Wire
- [97] AllThings.How
- [98] FullCleared
- [99] Engadget
- [100] Xbox Wire
- [101] Game Rant
- [102] How-To Geek
- [103] TheWindowsClub
- [104] Pureinfotech
- [105] Xbox Wire (ROG Xbox Ally)
- [106] Pure Xbox
- [107] Microsoft Support
- [108] Xbox Support
- [109] Xbox Wire 2023

#### PlayStation 5

- [110] GamesRadar
- [111] PlayStation Blog
- [112] PlayStation Support
- [113] Mein-MMO
- [114] TechRadar
- [115] PlayStation LifeStyle
- [116] GamesRadar
- [117] VGC
- [118] heise
- [119] Push Square
- [120] The Shortcut
- [121] Android Central
- [122] PlayStation Support (Tastenfunktionen)
- [123] Kotaku
- [124] Alphr
- [125] StealthOptional
- [126] TechRadar
- [127] MakeUseOf

#### Nintendo Switch und Switch 2

- [128] Nintendo Life
- [129] Nintendo Wire
- [130] MyNintendoNews
- [131] Vooks
- [132] Nintendo Support
- [133] Nintendo Support
- [134] dbltap
- [135] Nintendo Support AU
- [136] Nintendo Support
- [137] Nintendo Support SG
- [138] Nintendo UK
- [139] Nintendo Support (GameChat)
- [140] Notebookcheck

#### Apple TV, tvOS und Apple-Richtlinien

- [141] Apple HIG: Focus and selection
- [142] Apple HIG: Designing for tvOS
- [143] Apple HIG: Top Shelf
- [144] Apple HIG: Game controls
- [145] Android Authority
- [146] AppleInsider
- [147] MacRumors Forum
- [148] Apple HIG: Virtual keyboards
- [149] Apple Support
- [150] Apple Support

#### NVIDIA Shield und Google TV

- [151] Android Authority
- [152] 9to5Google
- [153] NVIDIA SHIELD Quick Settings
- [154] NVIDIA SHIELD TV Shortcuts

#### PC-Frontends, Launcher und Handheld-Software

- [155] Playnite-Doku
- [156] Playnite-Releases (GitHub)
- [157] ControlUp
- [158] GamepadDesktop
- [159] ES-DE USERGUIDE.md
- [160] libretro-Doku: Quick Menu
- [161] libretro-Doku: Ozone
- [162] libretro-Doku: Input and controls
- [163] Heroic PR #5490 (GitHub)
- [164] GamingOnLinux
- [165] Heroic-Releases (GitHub)
- [166] lutris-gamepad-ui (GitHub)
- [167] Gizmodo
- [168] ASUS
- [169] ASUS: 15 Tipps
- [170] Lenovo Legion Go S Benutzerhandbuch
- [171] VideoCardz
- [172] MSI Center M Versionshinweise

#### Apple Spiele-App und Game Overlay (macOS 26)

- [173] MacStories
- [174] Apple Support
- [175] Sir Apfelot
- [176] Apple Community 256157905
- [177] Apple Support
- [178] Apple Support
- [179] Apple Community 253836660
- [180] Apple Community 254343300
- [181] Engadget
- [182] Gizmodo
- [183] MacRumors Forum

#### macOS: Controller-Eingabe und Akku

- [184] Apple-Doku: shouldMonitorBackgroundEvents
- [185] Apple Developer Forums 780929
- [186] Apple Developer Forums 782461
- [187] Apple-Doku: buttonHome
- [188] Apple-Doku: preferredSystemGestureState
- [189] Apple Developer Forums 743753
- [190] SDL: SDL_mfijoystick.m
- [191] SDL: hidapi mac/hid.c
- [192] Apple-Doku: GCSupportsControllerUserInteraction
- [193] WineHQ-Fehlerliste
- [194] Apple Developer Forums 789896
- [195] Apple-Doku: battery
- [196] GCController.h
- [197] Apple Developer Forums 680734
- [198] SDL-Commit
- [199] iGeeksBlog

#### macOS: Fenster, Overlay, Vollbild, Game Mode, Leistungsanzeige

- [200] Apple Developer Forums 826308
- [201] Apple-Doku: nonactivatingPanel
- [202] Apple-Doku: CGShieldingWindowLevel()
- [203] Apple-Doku: Managing your game window for Metal in macOS
- [204] Apple Developer Forums 739387
- [205] Apple-Doku: PresentationOptions
- [206] Apple-Doku: Monitoring your Metal app’s graphics performance
- [207] Apple-Doku: Customizing Metal Performance HUD
- [208] Whisky Issue 600
- [209] Apple Community 256258694
- [210] Apple-Doku: LSSupportsGameMode

#### macOS: Anmeldeobjekt und automatische Anmeldung

- [211] Apple-Doku: SMAppService
- [212] go-macos/servicemanagement
- [213] smappservice-rs
- [214] Apple Developer Forums 777520
- [215] STIG APPL-26-000033
- [216] Apple Community 256199871

#### macOS: Bildschirmtastatur und synthetische Eingaben

- [217] Apple-Doku: CGRequestPostEventAccess()
- [218] Apple Developer Forums 724603
- [219] Objective-See
- [220] Touch-Base
- [221] Keyboard Maestro Forum

#### macOS: Ein/Aus und Beenden

- [222] Apple QA1134
- [223] AERegistry.h
- [224] Apple Developer Forums 722807
- [225] Apple-Doku: NSAppleEventsUsageDescription
- [226] Apple Developer Forums 108815
- [227] IOPMLib.h
- [228] Apple Community 1805421
- [229] Apple-Doku: forceTerminate()

#### macOS: Audio

- [230] AudioHardwareService.h
- [231] switchaudio-osx
- [232] Rogue Amoeba
- [233] mattmontag.com
- [234] MonitorControl README
- [235] JUCE Forum
- [236] Keyboard Maestro Forum

#### macOS: Helligkeit, Anzeige und HDR

- [237] Hammerspoon Issue 2668
- [238] s-age/brightness
- [239] MonitorControl Arm64DDC.swift
- [240] Apple-Doku: CGConfigureDisplayWithDisplayMode
- [241] Gist skempken
- [242] BetterDisplay CLI Wiki

#### macOS: Wecken aus dem Ruhezustand

- [243] Apple Community DOC-10684
- [244] Logitech
- [245] Microsoft Q&A

#### macOS: Bluetooth und WLAN

- [246] Apple-Doku: IOBluetoothDevicePair
- [247] IOBluetooth-Header
- [248] Apple-Doku: NSBluetoothAlwaysUsageDescription
- [249] bvanpeski/SystemPreferences
- [250] Apple Developer Forums 732431
- [251] Apple Developer Forums 769950
- [252] Apple Developer Forums 739945
- [253] Apple-Doku: associate(to:password:)

#### macOS: Screenshots und Bildschirmaufnahme

- [254] Apple-Doku: SCScreenshotManager
- [255] Apple-Doku: captureImage(in:completionHandler:)
- [256] MacRumors 2024
- [257] TechRadar
- [258] Apple Developer Forums 818415

#### macOS: Downloads (Epic)

- [259] derrod/legendary

#### macOS-Versionen

- [260] MacRumors Forum
- [261] MacRumors
- [262] MacRumors
- [263] Mr. Macintosh

#### Nightforge-Repository (öffentlicher Stand) und Signatur

- [264] Nightforge: Engine.swift
- [265] Nightforge: GameDisplay.swift
- [266] Nightforge: build.sh
- [267] Nightforge: README.md
- [268] Nightforge: Info.plist
- [269] Apple Developer Forums 819406 (Ad-hoc-Signatur und Freigaben)
- [270] Nightforge: MacSteam.swift
- [271] Nightforge: LibraryModel.swift
- [272] Nightforge: Updater.swift
- [273] Nightforge: Library.swift
- [274] Nightforge: MacSteamProgress.swift
- [275] Nightforge: Quellcode

---

*Eine ausführlichere Fassung mit denselben Quellennummern liegt als Datei „Big Picture Modus für Nightforge.md“ vor.*
