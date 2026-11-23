# Spielstart-Zeit: wohin die Sekunden gehen (Entwurf, 23.11.2026)

Auftrag 0.4, Entscheidung 2 „maximal verbessern, was geht“. Grundlage: die echten Starts vom 22.11. auf dem MacBook Pro
M5 Pro (`wine.log`, `wine.previous.log`, Steams `console_log`, `cloud_log`, `start-evidence.jsonl`), dazu eine Durchsicht
des Startwegs im Code. Gestern lief noch die F4-Wartezeit (Steam wartete bei jedem Start 20 s aufs Netz, behoben ab
22.11. 15:18 in neuen Sitzungen), F5 (Steam startet mit den Einstellungen des Spiels) kam am Abend dazu.

## Phasen der Starts vom 22.11.

Klick = „Curtain watch … begins“ beim ersten Mal; „Steam bereit“ = Steams „System startup time“; „Befehl“ = Steams
`ExecCommandLine` mit dem Start; „Prozess“ = `GameAction … CreatingProcess`; „Bild“ = „Curtain down for …“
(Spiel vorn, Bild stabil). Sekunden jeweils ab dem Schritt davor.

| Start | Klick | Steam (neu)start bis bereit | bis Befehl | Steam bis Prozess | Spiel lädt bis Bild | Gesamt |
|---|---|---|---|---|---|---|
| Wukong 00:11 | 00:11:39 | hing beim Anmelden: nach 10 s neu, 40,5 s (bereit 00:12:38) | 2 | 1 | 24 | **86 s** |
| Overwatch 00:14 | 00:14:24 | Neustart fürs Spiel 4 s nach Klick, 38,5 s (00:15:08) | 2 | 2 | 90* | **138 s** |
| Wukong 11:25 | 11:25:49 | Neustart fürs Spiel, 38,4 s (11:26:33) | 6 | 2 | 25 | **77 s** |
| Wukong 16:39 | 16:39:47 | Neustart fürs Spiel, 26,9 s (16:40:20) | 2 | 2 | 34 | **71 s** |
| Wukong 16:47 | 16:47:09 | Steam schlief: Start 39,7 s, dann **20 s Cloud-Warten**, dann Neustart fürs Spiel 40,1 s (16:49:01) | 8 | 3 | 23 | **146 s** |
| Wukong 19:32 | 19:32:19 | Steam lief nicht: Start 13,8 s (19:32:44) | 3 | 1 | 23 | **52 s** |
| Wukong 19:34 | 19:34:26 | lief schon, kein Neustart (F5) | **6** | 0 | 24 | **30 s** |
| Valheim Mac 16:35 | 16:35:26 | Wechsel zu Steam für Mac, Cloud bis 16:35:32 | – | – | – | **30 s** |
| Valheim Mac 00:10 | 00:10:23 | dazu eine Frage von Steam | – | – | – | **43 s** |

\* Overwatch 00:15–00:16: das eigene Vollbild verbarg das Bild, der Vorhang holte das Fenster zweimal zurück und zeigte
„startet nicht?“ (bekanntes Capture-Thema, siehe Direct-Display-Notizen); kein Ladezeit-Wert.

Steam selbst: vom Befehl bis zum Prozess 0–3 s, davon 0–2 s in Steams eigenem Schritt `ShowInterstitials`, den Steam
ohne Nightforge beendet.

**Lesart.** Bis gestern Nachmittag bestimmten Steam-(Neu-)starts die Zeit: 26–40 s je Start, darin die 20 s F4. Seit F4
startet Steam in 5–6 s, und F5 spart den Neustart, wenn Steam schon mit den Einstellungen des Spiels läuft. Der beste
Fall (19:34) bleibt bei 30 s: **6 s Nightforge vor der Übergabe an Steam, 0 s Steam, 24 s lädt das Spiel**. Ein
Kaltstart (Steam schlief oder lief nicht) kostete zusätzlich Steams Start und bis zu **20 s Warten auf einen
Cloud-Abgleich, den es hier nie gibt** (16:36, 16:47).

## Gebaut (Zweig `claude/startzeit-04`)

1. **Kein Warten auf einen Cloud-Abgleich, den dieses Steam nie macht** (`SteamCloudStart.neverSyncs`). Nach einem
   Steam-Start wartete Nightforge auf Steams Abgleich der Controller-Einstellungen (AppID 241100), bis Steam 20 s alt
   war, wenn der Abgleich nicht kam. Die Regel stammt vom 8.11. (Valheim, Steam für Mac auf dem alten Mac: der Abgleich
   und der Start kamen sich in die Quere). Auf diesem Mac machte keins der beiden Steams ihn je: 0 Zeilen in 50 Starts
   des Windows-Steam, auch Steam für Mac nicht. Jetzt: Zeigt das Protokoll mindestens drei frühere Starts desselben
   Steams ohne diesen Abgleich, wartet ein Start nicht mehr. Mit weniger Vorgeschichte (frische Installation) oder einem
   Steam, das ihn je machte, wie bisher. Gewinn: bis zu 20 s bei Starts kurz nach einem Steam-Start (geweckt aus dem
   Schlaf, Nightforge gerade geöffnet, Neustart für ein Spiel). Test: `SteamSwitchTest.cloudStart`.
2. **Zeitmarken je Start im Protokoll**, für die Messung heute Abend: `Start phases of <Spiel>: <Schritt> at
   HH:MM:SS.t, n.n s after Play` für Play, „to Steam“, „-applaunch client started“, „Steam started its process“
   (bzw. „starts directly“ / „its process runs“ bei Epic und GOG) und „curtain down“; seit 23.11. auch Epics und GOGs
   eigene Schritte: „Epic's saves: sync begins“/„Epic's saves synced“, „GOG's saves: sync begins“/„GOG's saves
   synced“, „asks Epic for the launch details“/„Epic's launch details came“. Nur mit dem versteckten
   Testschalter `gameTest.startPhases`, ohne Eintrag in der Oberfläche; im Release-Bau gibt es ihn nicht (kein Tracking).
   Damit lässt sich die 6-s-Lücke vor der Übergabe zuordnen, die aus dem Code allein nicht folgt: `GameResolution.fit`
   schrieb um 19:34 nichts (kein regedit), `/usr/bin/open` für den Helfer braucht hier ~30 ms, und der
   `-applaunch`-Weiterreicher lief am 31.10. 0,2 s. Test: `LaunchEdgeTest.startPhases`.

## Befunde, nicht gebaut (Risiko oder Entscheidung des Nutzers)

Nach möglichem Gewinn geordnet.

- **Neustart-Entscheid vor dem Warten auf das alte Steam.** Ob Steam für die Einstellungen des Spiels neu startet,
  entscheidet sich erst nach dem Warten auf Anmeldung und Cloud des Steams, das danach beendet wird (16:47: 20 s Cloud,
  dann Neustart). Vorziehen hieße, die Reihenfolge um Cloud-Abgleich und Spielstand-Übernahme (`takeSavesAlong`) zu
  ändern: Risiko für Spielstände. Seit F5 selten (nur beim Wechsel zwischen Spielen mit anderen Einstellungen kurz
  nach einem Steam-Start), seit dem Cloud-Fund oben kostet der Fall meist nur noch die Anmeldung.
- **Vorhang nach dem ersten Bild: mindestens ~2,3–2,8 s.** Der Vorhang sinkt erst, wenn das Spiel 1 s vorn ist und das
  Bild 2 s seine Größe hält, dann 0,3 s Ausblenden (`curtainStep`, `pictureSteady`). Die 2 s gibt es wegen Overwatch
  (8.11.: zwei Fenstergrößen, dann der Bildschirmmodus, dazwischen blitzten Seite und Schwarz). Vorschlag zur Wahl:
  1 s für ein Spiel, dessen Bild schon die Größe des Bildschirms hat und dessen Weg bestätigt ist (`known`). Spart
  ~1 s bei jedem Start; Risiko: kurzes Aufblitzen bei einem Spiel, das danach noch umschaltet.
- **Epic/GOG: Schritte nebeneinander.** Epic holt Spielstände (`syncSaves`, legendary) und danach die Startangaben
  (`launchCommand`, legendary); GOG gleicht jede Spielstand-Stelle nacheinander ab. Nebeneinander spart das die Dauer
  des kürzeren Schritts. **Geprüft am 23.11. (0.4, Zweig `claude/startphasen-stores-04`), nicht gebaut:**
  - *Gemessen:* Epics Abfrage der Spielstände (`legendary list-saves`, Anmeldung + Liste, wie `sync-saves` ohne neuen
    Stand) dauert hier 1,3–1,8 s, nebeneinander mit einem zweiten legendary-Aufruf genauso. Die Startangaben ließen
    sich nicht messen: alle zehn Epic-Spiele liegen auf dem Laufwerk „Games“, das nicht angeschlossen war, und
    legendary bricht dann vor der Anmeldung ab (0,2 s). Erwartet ist eine ähnliche Dauer (Anmeldung + ein bis zwei
    Abfragen). 7 der 9 Epic-Spiele, die die Bibliothek hier kennt, haben Cloud-Spielstände; bei GOG kostet jeder gogdl-Aufruf ~3 s (kein
    PackedApp), die meisten Spiele haben eine Spielstand-Stelle (dann kein Gewinn).
  - *Sicherheit nach Quelltext (legendary 0.21.1):* Die Anmeldung läuft unter einer Dateisperre auf `user.json`
    (`userdata_lock`), zwei Aufrufe erneuern das Token also nie gleichzeitig. `launch` schreibt nichts. `sync-saves`
    schreibt `installed.json` nur beim ersten Abgleich eines Spiels (Spielstand-Pfad noch leer, `--accept-path`), und
    zwar ohne atomares Ersetzen: ein `launch` zur selben Zeit könnte eine halbe Datei lesen und „nicht installiert“
    melden. Nebeneinander also nur, wenn der Spielstand-Pfad des Spiels in `installed.json` schon steht. Für gogdl
    nicht geprüft (eigene Token-Erneuerung ohne bekannte Sperre): dort nur nacheinander.
  - *Anderer Weg ohne zweiten Aufruf:* die Kette der Laden-Schritte (Spielstände, dann Startangaben) gleich nach dem
    Update-Schritt anwerfen und erst vor `startDirect` abwarten, neben Nightforges eigener Vorbereitung (Profil,
    Analyse, Engine, Laufzeiten, ein Steam-Neustart, der gerade läuft). Gewinn = die kürzere der beiden Strecken; die
    Vorbereitung eines Direktstarts ist ungemessen.
  - *Zum Belegen:* Zeitmarken je Laden-Schritt (unten, Punkt 4 der Messliste). Gebaut wird erst, wenn ein Epic-Start
    zeigt, dass die Schritte zusammen mehr als etwa eine Sekunde ausmachen, die sich verstecken lässt.
- **Unabhängige Vorbereitung neben der Anmelde-Wartezeit.** Profil, Analyse des Spiels, Engine-Prüfung, Laufzeiten
  und `FramePacing.learn` laufen erst nach dem Warten auf Steams Anmeldung. Nebeneinander spart das bei einem
  Kaltstart ihre Dauer (meist klein, die Analyse ist zwischengespeichert). Die Engine-Prüfung kann aber Steam
  beenden (Engine-Wechsel): nicht ohne genaue Prüfung.
- **10 s, bis ein nicht laufendes Steam beim Anmelden als hängend gilt.** Gestern 00:11 einmal. Die 10 s schützen vor
  einem Neustart mitten in Steams eigenem Update-Neustart; kürzer nur mit Blick auf Steams Bootstrapper.
- **Prozessliste (`ps`) ohne Zwischenspeicher.** Vorhang (0,5 s), Bühne (1 s), laufende Spiele und Startschleifen
  fragen je eigens. **Geprüft am 23.11., nicht gebaut, kein Gewinn zu zeigen:** Ein `ps -axo pid=,ppid=,command=` kostet
  hier 23 ms (7,7 ms Nutzer-, 15,3 ms Systemzeit, 762 Prozesse). Alle Blicke laufen abseits des Hauptfadens
  (`Task.detached`, `.utility`), die UI stockt also nicht. Die Bühne schaut über `CGWindowList`, nicht `ps`. Beim
  Start kommen rund drei `ps` je Sekunde zusammen (Vorhang 0,5 s, erste Sekunden 1 s, laufende Spiele 3 s), ein
  Zwischenspeicher von 0,5 s spart davon etwa einen: ~25 ms Rechenzeit je Sekunde auf einem von 15 Kernen, neben Wine
  und dem ladenden Spiel nicht messbar. Im Spiel fragt fast nur der Blick auf laufende Spiele (10 s mit Nightforge
  dahinter), unbeschäftigt zählte eine Minute lang 2 Kindprozesse von Nightforge. Dagegen stünde ein Risiko: Eine
  bis 0,5 s alte Liste gälte als „frisch“, und nur eine frische Liste darf „das Spiel ist weg“ sagen.
- **1-s-Pausen vor dem ersten Blick** nach `-applaunch` und beim direkten Start (Epic/GOG): halten das erste Bild nicht
  auf (der Vorhang schaut selbst alle 0,5 s), nur Nightforges Wissen um den laufenden Prozess.

Geprüft und nicht nötig: `regedit` vor dem Start läuft nur bei Änderungen (gestern 19:34: keins). Steams
`ShowInterstitials` beendet Steam selbst in 0–2 s, Nightforge muss dafür kein Fenster zeigen.

## Für die Messung heute Abend (Liste für den Nutzer)

Vorher `defaults write io.github.lordhayne.nightforge gameTest.startPhases -bool true`, danach
`defaults delete io.github.lordhayne.nightforge gameTest.startPhases`. Ein Spielstart je Fall, danach
`grep -a "Start phases of" ~/Library/Application\ Support/Nightforge/Logs/wine.log` und Steams `console_log`
(ExecCommandLine, GameAction):
1. Warm: Steam läuft seit Minuten mit den Einstellungen des Spiels (zweiter Start desselben Spiels).
2. Kalt: nach Steams Schlaf (30 min nichts) oder gleich nach dem Öffnen von Nightforge – zeigt den Cloud-Fund.
3. Ein Spiel mit anderen Einstellungen direkt danach (Neustart für das Spiel).
4. Mit angeschlossenem Laufwerk „Games“: ein Epic-Spiel mit Cloud-Spielständen (7 der 9 hier), zweimal. Aus den
   Zeilen: Dauer des Abgleichs (sync begins → synced), der Startangaben (asks → came) und was dazwischen liegt
   (Nightforges Vorbereitung). Nebeneinander spart die kürzere von Abgleich und Startangaben, der andere Weg die kürzere
   von Laden-Kette und Vorbereitung. Ein GOG-Spiel, wenn eins mit Cloud-Spielständen da ist.
