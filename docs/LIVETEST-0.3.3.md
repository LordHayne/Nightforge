# Live-Test 0.3.3

Eine Liste für einen Durchgang, nach Spiel und Situation sortiert. Stand: Testzweig `claude/staging-033`, 365f393 (8.11.).
Alle Punkte sind gebaut und, soweit es reine Regeln sind, mit Tests belegt, aber noch nicht live bestätigt.

**So geht's:** Blöcke der Reihe nach, nach jedem Block dem Koordinator die Nummern nennen, die nicht stimmen, mit ungefährer
Uhrzeit. Was stimmt, muss nicht erwähnt werden. Die Logs liest der Koordinator selbst, die Spalte „Log“ sagt ihm, wonach er sucht.

## Reihenfolge

| Block | Situation | Zeit |
|---|---|---|
| A | Nightforge allein, zwei Pads | 15 min |
| B | Steam-Wechsel: The Forest → Valheim → Left 4 Dead 2 → Valheim | 25 min |
| C | Overwatch, dreimal | 15 min |
| D | ABZU mit Shader-Kurztest, dann Control | 15 min |
| E | Steam für Mac fragt: Drawful 2, Touchpad, Neustart, Project Zomboid | 15 min |
| F | Hearthstone über den echten Battle.net-Client | 20 min |
| G | Zwei Pads in Sonic Mania, GOG mit Mafia II | 10 min |
| H | Akku: Steam schläft (gut für eine Pause) | 35 min, davon 30 Warten |
| I | Fernseher | 20 min |
| J | Zum Schluss: Schlaf, Home-Taste, Abmelden | 15 min |

Zusammen rund drei Stunden, davon 30 Minuten Warten. KosmicKrisp ist ein eigener Termin (Block K, 45 Minuten).
Punkte, die nicht planbar sind, stehen unter „Wenn es sich ergibt“.

## Was vorher da sein muss

- **Testbau:** Der Koordinator installiert ihn nach `~/Applications`. Kein Spiel läuft dabei.
- **Controller:** zwei DualSense, geladen. Maus oder Trackpad griffbereit, das Recht „Bedienungshilfen“ geht nur damit.
- **Strom:** am Netzteil, außer in Block H.
- **Einstellung:** Leistungsanzeige in Spielen an (Block D prüft das und startet sonst nicht).
- **Fernseher:** am DENON per HDMI, erst für Block I.
- **Battle.net:** Das eigene Passwort bereithalten, der Client fragt wohl neu, weil „Angemeldet bleiben“ aus ist.

| Spiele | |
|---|---|
| Schon installiert | Left 4 Dead 2, The Forest, Overwatch (Steam); Valheim, Drawful 2 (Steam für Mac); ABZU, Control (Epic); Mafia II (GOG); Hearthstone (Battle.net) |
| Noch laden | Sonic Mania (Epic, 0,2 GB) für G; Project Zomboid (Steam für Mac) für E7, ersatzweise Golf With Your Friends, Amnesia, Arma 3 oder 7 Days to Die |
| Nur für Block K | The Stanley Parable (Epic), ersatzweise Sonic Mania |

**Grenzen:** Left 4 Dead 2 hat VAC, also nur Einzelspieler mit Bots. Während L4D2 oder Overwatch läuft, hängt niemand ein
Diagnosewerkzeug an das Spiel. Bei Hearthstone startet nur Blizzards eigener Client das Spiel.

**Wo die Logs liegen:** `~/Library/Application Support/Nightforge/Logs/wine.log` (ab 8 MB beim nächsten Steam-Start als
`wine.previous.log` beiseite). Battle.net: `~/Library/Application Support/Battle.net/Logs/battle.net-*.log`. Diese Datei kann
Mail und Kontoland enthalten: Nicht einfügen oder weitergeben, der Koordinator sucht darin nur die genannten festen Zeilen.

## A · Nightforge allein (15 min)

Beide Pads an, kein Spiel. Alles hier schreibt nichts ins Log: Sagen, was man sieht.

| Nr. | Tun und sehen | Log |
|---|---|---|
| A1 | Beide Pads einschalten: Die Kapseln unten zeigen „1 · DualSense · …“ und „2 · DualSense · …“, die Lichtleisten leuchten blau und rot. | Sagen, ob macOS auch die kleinen Spieler-LEDs setzt. |
| A2 | Pad 1 aus, 10 Sekunden warten, wieder an: Erst kommt „getrennt“, dann „Controller verbunden“, und er hat wieder die 1 und Blau. | – |
| A3 | Touchpad: Ein Finger bewegt den Zeiger ohne Sprung beim Aufsetzen, oben/unten so schnell wie links/rechts, Drücken klickt ohne Zucken, zwei Finger scrollen, mit zwei drücken ist Rechtsklick. | – |
| A4 | A auf einem Knopf vibriert kurz, und mit Einstellungen › Controller › Vibration aus ist es still (danach wieder an). | Sagen, ob der DualSense über Bluetooth überhaupt vibriert. |
| A5 | Einstellungen › Startseite nur mit dem Pad: Schalter und Pfeile gehen, die Markierung wandert mit dem Spiel, die Startseite ändert sich nach jedem Schalter, alle Quellen aus lässt nur die Kachel „Alle Spiele“. | – |
| A6 | Dort die Quelle „Später spielen“ einschalten (ab Werk aus) und ein noch nicht geladenes Spiel vormerken: Es erscheint auf der Startseite. | – |
| A7 | Launcher-Karten und das Menü oben rechts gehen mit dem Pad, und Create öffnet das kleine Menü statt ein Bildschirmfoto zu machen. | – |
| A8 | Nach einem Spiel suchen, das auch bei GOG liegt: Die Treffer stehen im Raster, die Doppelkarte zeigt „Auch im GOG-Store“, der Epic-Link öffnet. | – |

## B · Steam-Wechsel (25 min)

Beide Pads aus, Start mit der Maus. B1 bis B7 laufen in einer Sitzung von The Forest.

| Nr. | Tun und sehen | Log |
|---|---|---|
| B1 | The Forest starten und erst im Spiel Pad 1 einschalten: Eine kurze Meldung, das Spiel bleibt im Vollbild und folgt dem Pad, kein Angebot „Spiel neu starten“. | Kein `Stage: fetching The Forest back`. |
| B2 | Pad 1 aus und nach 10 Sekunden wieder an: „getrennt“, „Controller verbunden“, und das Spiel folgt ihm wieder. | – |
| B3 | Das Touchpad anfassen: Der Zeiger bewegt sich nicht. | – |
| B4 | L3 + R3 eine Sekunde halten und loslassen: Es vibriert ansteigend, kein Menü; dann 2 Sekunden halten: Menü kommt, Vollbild bleibt, das Pad bedient das Menü. | `Overlay up (menu)`, danach kein `Stage: fetching`. |
| B5 | Mit B schließen, Menü wieder öffnen, mit der Maus auf „Weiterspielen“: Das Spiel ist im Vollbild und verschluckt keine Eingaben. | – |
| B6 | Mit ⌘-Tab weg und zurück, dann im Spiel die Grafikeinstellungen ändern: Kein Vorhang beim ⌘-Tab, bei den Einstellungen höchstens kurz. | Kein `Stage: the page lay over`. |
| B7 | Create im Spiel drücken: Sagen, ob macOS ein Bildschirmfoto macht (am 8.11. nicht). | – |
| B8 | Übers Menü „Spiel beenden“ und sofort Valheim starten: Vorhang beim Druck auf „Spielen“, passender Text, kein Desktop beim Wechsel ins Vollbild, kein Steam-Fenster, keine Frage „Unable to Sync“. | `Steam switch: the Windows Steam makes way…`, `Space changed under the curtain`, nur bei Bedarf `Steam Cloud: Steam finishes its first sync`. |
| B9 | Während Valheim startet, in den ersten 30 Sekunden B und Esc drücken: Nichts passiert, der Start läuft weiter. | – |
| B10 | Noch auf dem Vorhang das Touchpad anfassen: Der versteckte Zeiger kommt zurück. | – |
| B11 | In Valheim: Die Leistungsanzeige ist zu sehen, Pad 1 aus und nach 10 Sekunden wieder an bringt kein Angebot „Spiel neu starten“, L3 + R3 öffnet und schließt das Menü ohne Verlust des Vollbilds. | `Overlay up (menu)`. |
| B12 | Valheim im Spielmenü beenden, nicht übers Overlay: Der Vorhang steht, bevor die Spaces gleiten, danach ist kein Steam-Fenster da, auch nicht hinter Nightforge (⌘-Tab). | `A game's process ended` oder `The game's picture went`. |
| B13 | Pad ausschalten, sofort Left 4 Dead 2 starten, Solo › Dead Center laden, dann Pad einschalten: Die Karte lädt, es kommt „Controller nach dem Start verbunden“ mit „Spiel neu starten“. | `Steam switch: Steam for Mac makes way…`. |
| B14 | L4D2 übers Menü beenden und gleich wieder Valheim starten: Vorhang sofort, passender Text, kein Steam-Fenster. | `Steam switch:` mit Uhrzeit. |

## C · Overwatch (15 min)

Nur bis ins Menü, mit Pad. Die drei Starts zählen zusammen.

| Nr. | Tun und sehen | Log |
|---|---|---|
| C1 | Start 1: Das Bild kommt ohne Klick im Dock, kein Schwarz dazwischen, kein Flackern. | Kein `Stage: Overwatch didn't come back`. `The curtain goes over a captured display's shield` nur, wenn der Vorhang wechselt. |
| C2 | Übers Overlay beenden: Der Vorhang bleibt stehen, kein falsches Bild, nichts von der Seite, kein Desktop. | `A game's process ended` oder `The game's picture went`. |
| C3 | Start 2, im Spielmenü beenden: wie C1 und C2. | wie oben |
| C4 | Start 3 direkt danach: wieder Bild ohne Dock-Klick. | In `dxmt.conf` im Spielordner keine Zeile `d3d11.prepareShaders`. |

## D · ABZU und Control (15 min)

Nightforge ganz beenden, dann im Terminal starten. Das Skript sagt jeden Schritt an und stellt am Ende alles zurück.

```bash
"$HOME/Library/Application Support/Claude/side-session-notes/local_50379bcc-0f0e-4091-a00d-c844cb465b05/shader-messung/ablauf.sh" test
```

| Nr. | Tun und sehen | Log |
|---|---|---|
| D1 | Nightforge öffnen, ABZU starten, „Fortsetzen“, nach dem Ton im Spielmenü beenden: Sofort der Vorhang, kein anderes Fenster davor, kein Desktop. | `The game's picture went` oder `A game's process ended`. Sagen, welche Auflösung die Leistungsanzeige nennt. |
| D2 | Zweite Runde: L3 + R3, das Panel ist zu sehen, „Pausiert“, das Bild steht erst danach; Menü schließen, nach dem Ton dort „Spiel beenden“. | `Overlay up (menu)`. Bei unsichtbarem Panel `Overlay still not seen`. |
| D3 | Nightforge ganz beenden: Das Terminal sagt „Der Schalter war in einem Spiel an.“, vor „rechtzeitig“ steht eine Zahl über null, und ABZU sah normal aus. | `[nightforge-dxmt] prepare: on, level`. Logs liegen unter `shader-messung/reihe-*`. |
| D4 | Nightforge öffnen, Control starten und beenden: Der Vorhang deckt bei Start und Ende den ganzen Schirm, nichts von der Seite. | `The page follows the screen`. |

## E · Steam für Mac fragt (15 min)

In Drawful 2 unter den Optionen als Startparameter `-condebug` eintragen. Ist „Bedienungshilfen“ schon erlaubt, entfällt E2.

| Nr. | Tun und sehen | Log |
|---|---|---|
| E1 | Spielen: Der Vorhang geht, Steams Frage nach der Startoption liegt vorn, nicht unter dem Store, und ist mit der Maus anklickbar. | `Steam asks in a dialog of its own`. Kein `Pointer: the sheer panel takes the keys from Steam Helper`. |
| E2 | Frage offen lassen, Touchpad benutzen: Der Zeiger läuft, der Klick wirkt nicht, Nightforge sagt „Erlaube es einmal unter Einstellungen › Controller, mit Maus oder Trackpad.“ | – |
| E3 | Abbrechen wählen: Steams Fenster verschwindet, Nightforge steht ohne Vorhang. | – |
| E4 | Einstellungen › Controller › Als Maus › „Erlauben …“ mit dem Trackpad: macOS fragt, danach steht ohne Neustart „Erlaubt“, ein zweiter Druck öffnet die Bedienungshilfen. | – |
| E5 | Drawful 2 noch einmal, die Frage nur mit dem Touchpad beantworten: Der Klick wirkt, und du zählst, wie oft die Maus nötig war. | – |
| E6 | Drawful 2 beenden, noch einmal starten, bei offener Frage Menü „Nightforge neu starten“: Nightforge kommt von selbst wieder, Steam startet frisch. | `Restart asked for`. |
| E7 | Startparameter wieder leeren, Project Zomboid starten: Es startet ohne Frage in Steam für Mac. | Kein eigener Eintrag: Fragt Steam doch, griff `-applaunch` nach 15 s nicht. |

## F · Hearthstone (20 min)

Battle.net vorher ganz beenden. Spalte „Log“ meint hier den Battle.net-Log, wenn nichts anderes steht.

| Nr. | Tun und sehen | Log |
|---|---|---|
| F1 | Spielen: Der Client kommt versteckt hoch; ist er abgemeldet, kommt sein Fenster nach vorn und Nightforge sagt „Melde dich im Battle.net-Fenster an“. Selbst anmelden, „Angemeldet bleiben“ ankreuzen. | `Account manager state has changed to: Ready`, `GameController initialization complete`. |
| F2 | Danach startet Hearthstone ohne Klick; kommt nach 30 Sekunden das Client-Fenster mit „Battle.net wartet auf dich“, dort Spielen drücken: Nightforge folgt dem Spiel, aber der Punkt gilt als nicht bestanden. | `Game launch options: programId=`, `Game is now running with game launch behavior`. Fehlt die erste Zeile bei einem normalen Start, ist die 30-Sekunden-Grenze zu knapp. |
| F3 | Während das Spiel läuft: Im Dock steht keine zweite Battle.net-App. | – |
| F4 | Mindestens eine Minute spielen, im Spiel beenden: Zurück in Nightforge, „Willkommen zurück“, Spielzeit auf der Karte. | wine.log: `A game's process ended`. |
| F5 | Der Client läuft noch, Spielen: Vorhang, Spiel startet ohne Klick und ohne sichtbares Client-Fenster. | wie F2 |
| F6 | L3 + R3, „Spiel beenden“: Hearthstone ist weg, der Client bleibt versteckt offen. | wine.log: `Overlay up (menu)`. |
| F7 | Battle.net beenden, Spielen, gleich B oder Esc: Der Start bricht ab, kein Spiel kommt. | Kein `Game launch options` danach. |
| F8 | Battle.net wieder beenden, Spielen, diesmal abwarten: Kein Fenster, das Spiel startet (gemerkte Anmeldung). | wie F1 und F2 |

## G · Zwei Pads, GOG (10 min)

| Nr. | Tun und sehen | Log |
|---|---|---|
| G1 | Sonic Mania mit zwei Spielern starten: Vorhang sofort beim Druck auf „Spielen“, und jedes Pad steuert seine eigene Figur. | – |
| G2 | Sagen, welcher Pad im Spiel Spieler 1 ist und welche Nummer er in Nightforge hat. | – |
| G3 | Pad 2 aus und wieder an: Bekommt er seine Figur zurück? | – |
| G4 | Spiel beenden: Zeigen die Lichtleisten wieder Blau und Rot? Nightforge schreibt die Farbe nur neu, wenn sich die Nummer ändert. | Sagen, welche Farbe bleibt. |
| G5 | Mafia II starten und beenden: Vorhang sofort, passender Text, kein Fenster blitzt auf. | `Curtain down for Mafia II`. |

## H · Akku (35 min, davon 30 Warten)

Netzteil ab, Nightforge offen, eine andere App vorn, kein Steam-Fenster offen, kein Download. Das letzte Spiel liegt mindestens 5 Minuten zurück.

| Nr. | Tun und sehen | Log |
|---|---|---|
| H1 | 30 Minuten warten: Danach laufen keine Steam-Prozesse mehr. | `Steam sleeps: on battery`. |
| H2 | Zurück zu Nightforge: Steam ist nach kurzer Zeit wieder da und angemeldet, ein Spiel startet normal. | `Steam wakes`. |
| H3 | Wenn Zeit bleibt, noch einmal 30 Minuten, dann ein Spiel über seine Verknüpfung starten: Es startet. | `Steam wakes`. |

## I · Fernseher (20 min)

| Nr. | Tun und sehen | Log |
|---|---|---|
| I1 | HDMI am DENON einstecken: Die Seite baut sich ohne Hänger neu auf, die Schrift ist von selbst größer, die Markierung dicker. | `Main display:` mit dem Namen. |
| I2 | Aus 3 m: Hinweisleiste, Spieltitel und Akku sind lesbar, die Leisten liegen ganz im Bild, oben die Uhr auch. | Ein Foto vom Fernseher hilft. |
| I3 | Eine andere App nach vorn, A am Pad: Nightforge kommt nach vorn. | – |
| I4 | Im Terminal `pmset displaysleepnow`, dann eine Taste am Pad: Das Bild kommt wieder, und der Fernseher schaltet an? | – |
| I5 | The Forest nur mit dem Pad, Maus nicht anfassen: Kein Zeiger auf dem Vorhang und im Spiel, Ton kommt über den DENON, L3 + R3 löst nichts bei macOS aus. | `Curtain down for The Forest`. |
| I6 | Mit laufendem Spiel eine Taste am Pad: Nightforge kommt nicht nach vorn; übers Overlay beenden. | Kein `Stage: fetching`. |
| I7 | Drawful 2 mit `-condebug`, die Frage am Fernseher nur mit dem Pad beantworten: Zählen, wie oft die Maus nötig war, dann den Parameter wieder löschen. | – |
| I8 | Kabel ziehen: Die Seite kommt ohne Hänger aufs MacBook zurück, die Schrift wieder normal. | `Main display:`. |

## J · Zum Schluss (15 min)

Am Ende, weil das Abmelden alles schließt und der lange Druck ein Spiel stören kann.

| Nr. | Tun und sehen | Log |
|---|---|---|
| J1 | Einstellungen › Controller: Die Zeile für die Home-Taste ist da, der Knopf öffnet die richtige Seite, und mit Nightforge eingetragen steht der Haken. | – |
| J2 | In The Forest die PS-Taste lange drücken: Nightforge kommt, und du sagst, ob das Spiel minimiert oder im Vollbild bleibt. | `Stage:`-Zeilen ab da. |
| J3 | Spiel laufen lassen, Deckel zu, nach einer Minute auf: Laufen Ton, Pad und Bild weiter, und wer ist vorn? | `Stage:`-Zeilen ab da. |
| J4 | Mac in den Ruhezustand legen, PS-Taste: Wacht er auf? Einmal am Netzteil, einmal auf Akku. | – |
| J5 | Einstellungen › Allgemein › „Beim Anmelden öffnen“ an, abmelden, anmelden: Nightforge kommt nach vorn, und du sagst, ob macOS dazu etwas meldet. | `Quit by`. |

## K · KosmicKrisp (eigener Termin, 45 min)

Eigener Testbau, den der Koordinator bereitstellt. Anleitung und Ergebnistabelle: `docs/LIVE-TEST-KOSMICKRISP.md` (auf
`claude/staging-033`). Mafia II, Left 4 Dead 2 nur Einzelspieler, The Stanley Parable, dann die Gegenprobe. Es prüft nur, ob
DirectX 9 dort taugt; nichts aus den Blöcken oben hängt daran.

## Wenn es sich ergibt

| Nr. | Situation | Tun und sehen | Log |
|---|---|---|---|
| X1 | Steam lädt ein Update oder hängt | Nach 30 Sekunden steht „Hängt es? Zurück zu Nightforge“ auf dem Vorhang, B oder Esc fragt, „Weiter warten“ lässt es laufen, „Zu Nightforge“ führt auf die Spielseite, und der nächste Start läuft sauber. | – |
| X2 | Epic oder GOG hat ein Update | Vorhang sofort mit Prozent, Tempo und Restzeit; B bricht ab, beim nächsten „Spielen“ läuft es weiter, wo es stand. | – |
| X3 | „Spielstand holen“ läuft | B: Der Start ist weg, das Spiel kommt nicht, der Abgleich läuft unsichtbar zu Ende. | – |
| X4 | Ein Windows-Spiel hängt | „Startet nicht?“ liegt über dem Vorhang und ist bedienbar, ⌘-Tab geht, seine Leiste ist darunter nicht zu sehen. | `Overlay up`. |
| X5 | GOG-Spiel, dem ein Windows-Teil fehlt | Der Vorhang bleibt, der Hinweis wartet danach auf der Seite. | – |
| X6 | Steam-Anmeldung abgelaufen oder Spielstand-Wahl beim Versionswechsel | Vorhang weg, das Fenster oder Sheet ist vorn und bedienbar. | – |
| X7 | Battle.net hat ein Update, oder WoW Classic ist installiert | Update: Client öffnet die Spielseite, Nightforge sagt es. Classic: startet ohne Klick (Ableitung, kein Beleg). | wie F2 |
| X8 | Fernseher ohne AV-Receiver dazwischen | Ab 40 Zoll wird er als Fernseher erkannt, auch ohne bekannten Namen (am DENON nicht zu sehen). | `Main display:`. |
| X9 | Ein Xbox-Pad ist zur Hand | Über Steam: rechter Stick und R2 als Maus; Bildschirm aus, Taste bringt das Bild; 11 Minuten nur Pad, der Bildschirm bleibt an. | `pmset -g assertions \| grep UserIsActive` |
| X10 | Mikrofonfrage noch einmal sehen (im Terminal `tccutil reset Microphone io.github.lordhayne.nightforge.helper`, nur du selbst) | Left 4 Dead 2, Karte laden: Das Touchpad erreicht die Frage von macOS, „Nicht erlauben“, und die Karte lädt trotzdem. | – |
| X11 | Kein Netz | Mafia II startet offline. | – |
| X12 | Ein Pad fällt unter 15 % | Einmal je Ladung die Meldung „…: Akku bei … %“, auch über einem Spiel, ohne ihm etwas wegzunehmen. | – |
| X13 | Die Einrichtung von Steam für Mac läuft | „Steam-Fenster wieder zeigen“ zeigt das Fenster weiter an. | – |

## Nicht in diesem Durchgang

- **Erststart mit leerem Konto** (Mitteilungsfrage nach der Einrichtung, Karten nach Steams Anmeldung): braucht ein frisches Test-HOME, der Koordinator baut es.
- **Selbstupdate** (Zip vor dem Beenden): zeigt sich erst beim Update von 0.3.3 auf die nächste Version.
- **„Komplett entfernen“ und das Beenden-Skript im Test-HOME** (Liste H1–H3), **Apple Event beim Beenden** und die **Wine-Sandbox** (Schalter aus): Sie ändern sich in 0.3.3 nicht.
- **Shader-Vergleich mit und ohne Schalter:** vom Nutzer für heute abgewählt, Block D zeigt nur, dass es läuft.
- **Noch nicht gebaut oder nicht im Testbau:** Tastatur fürs Pad, An/Aus-Menü, Steams Frage auf dem Vorhang (Boards gewählt), HUD-Umschalter, großes Overlay.

## Gestrichen, weil schon bestätigt

Drawful 2 ohne Frage (8.11. 12:54), zwei Controller in der Leiste, Steams schwarzer Hinweis beim ersten Start (REANIMAL),
Steam ↔ Steam für Mac, Control, Wukong, OxyRail und ABZU samt Leistungsanzeige, die Mikrofonfrage von L4D2 mit „Erlauben“,
Schnellmenü und „Später spielen“ (7.11.), Update von 0.3.1 auf 0.3.2.
