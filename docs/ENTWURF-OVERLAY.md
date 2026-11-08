# Entwurf: Das große Nightforge-Overlay

Stand 8.11.2026, Konzept ohne App-Code. Das Board `Overlay.dc.html` zeigt drei Varianten, der Nutzer wählt, danach wird gebaut.

Belege: **[Code]** Datei:Zeile auf `origin/main` (2276ccb), **[Wine]** Quelltext von Wine upstream (`master`, nicht unser winecx-Stand),
**[SDK]** macOS-SDK 26, **[Quelle n]** Liste am Ende, **[Vermutung]** nicht belegt, **[Live]** nur am echten Gerät zu klären.

---

## Kurz gesagt

- Das heutige Panel wird zur Fläche aus **Bausteinen**. Jeder Baustein sagt selbst, ob er für dieses Spiel und diesen Mac geht. Neue Funktionen kommen dazu, ohne das Overlay umzubauen.
- Es bleibt ein **eigenes Fenster über dem Spiel**. Nichts wird ins Spiel geladen, das Spiel behält die Tastatur.
- **Die wichtigste Frage ist beantwortet, nur nicht gelöst:** Das Spiel bekommt die Eingaben immer mit, macOS kann sie ihm nicht nehmen. Windows-Spiele hält heute nur `SIGSTOP` an, Mac-Spiele laufen und reagieren. Das ist tragbar, solange man kurz im Overlay ist. Das große Overlay lädt zum Verweilen ein, deshalb braucht es zwei Dinge: Schließen erst beim Loslassen (klein) und für Online-Spiele eine stille Eingabe in `winebus` statt der Pause (mittel).
- **Beim Lesen gefunden, schon heute falsch:** „Weiterspielen“ löst beim *Drücken* aus. Das Spiel läuft wieder an, während A noch unten ist, und sieht den Druck (Abschnitt 4).
- Empfehlung fürs Board: **Variante A, Seitenleiste**. Der Spieler wählt.

---

## 1. Was heute da ist

| Was | Stand | Beleg |
|---|---|---|
| Auslöser | L3 + R3, 2 s halten; Pad ohne Stick-Tasten: ☰ + ⧉ | [Code] `GameOverlay.swift:503`, `InputRouter.swift:545` |
| Warum nicht die PS-Taste | Sie gehört macOS (Game Overlay, Spiele, Spotlight). Ausnahmen gelten nur für die App vorne, und das ist das Spiel | [Quelle 1], `docs/TODO.md:927` |
| Fenster | `NSPanel`, `.nonactivatingPanel`, Level `.screenSaver` oder darüber, auf allen Spaces | [Code] `GameOverlay.swift:318–330` |
| Tasten | Nimmt das Panel nur bei „startet nicht?“, sonst nie; Grund: The Forest legte sich am 8.11. sonst ins Dock | [Code] `GameOverlay.swift:168–174` |
| Bild | Abgedunkelt, keine Unschärfe | [Code] `GameOverlay.swift:356` |
| Inhalt | Weiterspielen, Spiel beenden (mit Rückfrage), Zu Nightforge, Spiel neu starten (nur Controller kam zu spät) | [Code] `GameOverlay.swift:379–433` |
| Zustände | `OverlayStep` und die reine Funktion `transition` | [Code] `GameOverlay.swift:251, 341` |
| Hinweis ohne Eingriff | `GameHint`: nie Tasten, keine Klicks, 6 s | [Code] `GameHint.swift` |

Das ist ein guter Kern. Er bleibt, wie er ist, und bekommt eine Fläche drumherum.

---

## 2. Aufbau, der mitwächst

**Grundsatz: Das Overlay kennt Bausteine, keine Funktionen.** Nichts außerhalb des Bausteins weiß, was Lautstärke oder Leistungsanzeige ist.

```text
OverlayContext   einmal beim Öffnen gebaut, nur Werte:
                 Spiel, Plattform, Engine, pausiert?, HUD-fähig gestartet?, Pads, Tonausgabe,
                 Recht „Bedienungshilfen“, Fernseher?, Maßstab

OverlayTile      id, Zone (Kopf | Aktion | Regler | Werkzeug), Reihenfolge
                 availability(context) -> ready | nextStart(Satz) | needsRight(Satz) | hidden
                 view(context)      nur SwiftUI, ohne eigene Timer
                 refresh            nie | beim Öffnen | einmal pro Minute
```

**Regeln:**

- **Der Kern ist kein Baustein.** Weiterspielen, Beenden, Zu Nightforge und Neu starten bleiben in `OverlayStep`/`transition`. Geht ein Baustein schief, fehlt nur er. Der Weg aus dem Spiel bleibt immer offen, dafür wurde das Overlay gebaut (L4D2 am 31.10.).
- **Vier Antworten, kein Raten.** `hidden`: hier sinnlos, fehlt ganz (Lautstärke, wenn die Ausgabe keine regelbare hat). `nextStart`: geht beim nächsten Start, steht da mit einem Satz. `needsRight`: fehlendes Recht, ein Satz und der Weg in die Einstellungen. Am Sofa fragt macOS nie etwas, denn das Recht lässt sich nur mit echter Maus erteilen (Zweig `claude/touchpad-tastatur-033`).
- **`availability` ist eine reine Funktion.** Testbar wie `PadRules`, ohne Controller und ohne Spiel.
- **Bausteine fassen das Spiel nicht an.** Was sie auslösen, geht durch eine schmale Brücke: `setVolume`, `setHUD`. Prozesse anhalten oder beenden bleibt allein bei `GameOverlay`.
- **Feste Reihenfolge, keine Einstellungen.** Passt zum Leitsatz „einschalten und genießen“. Anpassen wie am PS5 **[Quelle 3]** lässt sich später ergänzen, wenn es Bedarf gibt.
- **Fokus je Baustein über `padFocus`-IDs** (`overlay.<baustein>.<teil>`), die Markierung startet wie heute auf der sicheren Antwort.
- **Zum Protokoll:** Eine Zeile in `wine.log` beim Öffnen: welche Bausteine da sind und warum die anderen nicht.

Eine neue Funktion ist damit eine neue Datei und ein Eintrag in der Liste.

---

## 3. Funktionen in Stufen

Aufwand: **S** bis 1 Tag, **M** mehrere Tage, **L** eigene Arbeit mit Live-Proben.

### Stufe 1: Überblick und Weg hinaus

Warum zuerst: alles liegt schon vor, kein Recht, keine Engine, und es macht aus dem Notausgang ein Overlay.

| Funktion | Datenquelle | Aufwand | Grenze |
|---|---|---|---|
| Spielname | `state.game` | – | – |
| Spielzeit dieser Sitzung | Startzeit des Spielprozesses, `proc_bsdinfo.pbi_start_tvsec` (`GameProcesses.alive` liest dieselbe Struktur); anzeigen in Minuten | S | Zählt Pausen mit |
| Uhr | Systemuhr, einmal pro Minute | S | – |
| Akku je Controller | `ControllerStatus` aus `InputRouter.refreshBattery` (`:387`) | S | Wird heute nur gelesen, wenn Nightforge aktiv ist (`LibraryModel.swift:611`), also beim Öffnen einmal anstoßen. `.unknown` zeigt nichts statt einer falschen Zahl |
| Weiterspielen, Beenden, Zu Nightforge | vorhanden | S | Beenden behält die Rückfrage |

Dazu gehören drei Grundlagen (Abschnitt 4): Weiterspielen beim Loslassen, `canBecomeKey` fest verdrahten, TV-Maßstab.

### Stufe 2: Was man im Spiel wirklich ändert

| Funktion | Datenquelle | Aufwand | Grenze, ehrlich |
|---|---|---|---|
| Leistungsanzeige an/aus | `claude/dxmt-hud-toggle-033`: Darwin-Notification, DXMT setzt `developerHUDProperties` | M | **Nur DXMT**, und nur wenn das Spiel mit `MTL_HUD_ENABLED=1` gestartet ist. Noch in keinem Spiel getestet, Kosten eines versteckten HUD unbekannt. Andere Engines und Mac-Versionen: `nextStart` (`Prefs.performanceHUD`, `MacGameHUD`) |
| Lautstärke | Standardausgabe über CoreAudio, `GameAudio.outputDevices` kennt die Geräte | S–M | Nur wenn die Ausgabe sich regeln lässt, sonst `hidden`. An HDMI und Verstärker oft nicht **[Vermutung]**, am DENON prüfen. Beim pausierten Spiel fehlt das Hörbild: nach dem Ändern ein kurzer Klang |
| Downloads-Stand | `model.downloads`, `downloadRates`, `DownloadsPanel.status` | S | Nur Stand, kein Steuern. Steam kann eigene Downloads während des Spiels anhalten, dann steht dort „pausiert“ |
| Spielernummern | `claude/spielernummern-033`, `PlayerSlots` | S | Sind Nightforges Nummern. In Windows-Spielen vergibt XInput die Plätze selbst, „Spieler 1“ dort kann der andere Pad sein (`docs/TODO.md` auf dem Zweig) |
| Touchpad als Maus | `claude/touchpad-tastatur-033`, `PadPointer` | M | Braucht „Bedienungshilfen“, sonst `needsRight`. Pads ohne Touchpad nehmen den rechten Stick. Gilt nur solange gewählt, im Spiel bleibt es sonst beim Spiel |

### Stufe 3: Werkzeuge

| Funktion | Datenquelle | Aufwand | Grenze, ehrlich |
|---|---|---|---|
| Bildschirmfoto | Siehe unten | M–L | Der Knackpunkt ist das Recht |
| Tastenbelegung | `PadDrawing` für das Bild; Spielbelegung aus den Profilen | L | Zeigen, nicht ändern. Eine allgemeine Quelle für die Belegung eines Spiels gibt es nicht, also Handarbeit für die meistgespielten Spiele |
| Bildschirmtastatur | `PadKeyboard.swift` (`claude/touchpad-tastatur-033`), Board `Tastatur.dc.html` wartet auf die Wahl | M | Das Panel nimmt keine Tasten, die Zeichen gehen als Ereignisse ans Spiel: braucht „Bedienungshilfen“ |

**Bildschirmfoto, die Wege:** Create macht im Spiel heute keins (`docs/TODO.md:99`, Verdacht: SDL in winebus sperrt die Geste).

| Weg | Recht | Bewertung |
|---|---|---|
| Create wieder zum Laufen bringen | keins | **Zuerst.** Die Taste gehört macOS, dann gibt es auch dessen Aufnahme und „Highlight“. Erst Ursache klären [Live] |
| Nightforge sendet ⌘⇧3 an macOS | „Bedienungshilfen“, das schon für Touchpad und Tastatur gebraucht wird | Zweitbester Weg. macOS speichert wie eingestellt, das Overlay muss vorher zu sein **[Vermutung]** |
| ScreenCaptureKit | „Bildschirmaufnahme“, seit macOS 15 mit wiederkehrender Nachfrage **[Quelle 7]** | Passt nicht zu „keine Fragen fürs Sofa“. Kann aber Nightforges Fenster ausnehmen |
| DXMT kopiert das Bild selbst | keins | Nur DXMT, eigene Engine-Arbeit, Reserve |

### Später prüfen: Erfolge und Freunde

Ehrliche Einschätzung: **nicht einplanen**. Nightforge ist kostenlos und verteilt keine Schlüssel, die Launcher bieten dafür keinen offiziellen Weg.

| Launcher | Was möglich ist | Urteil |
|---|---|---|
| Steam | Web-API braucht einen API-Schlüssel und öffentliches Profil **[Quelle 8]**. Steam legt Statistiken lokal ab, Format undokumentiert **[Vermutung]**. Das Steam-Overlay ist in Windows-Spielen abgeschaltet (`gameoverlayrenderer=d`, `docs/TODO.md:913`) | Allenfalls „12 von 40 Erfolgen“ aus lokalen Dateien, einzeln prüfen. Freunde: nein |
| GOG | SDK nur je Spiel mit Zugang des Herstellers. Laut GOG zählen Erfolge nur mit dem Galaxy-Client **[Quelle 9]**, Nightforge startet ohne ihn. Inoffizielle REST-Schnittstelle existiert **[Quelle 10]** | Nein: Es würden kaum Erfolge entstehen |
| Epic | Nichts Belastbares gefunden | Nicht einplanen |
| Battle.net | Keine belegte Schnittstelle für Freunde | Nicht einplanen |
| Apple (Game Center) | Nur für Spiele, die es selbst nutzen, und Apples Overlay zeigt das schon | Apple überlassen |

**Auch später:** Bildratenbegrenzung (`docs/TODO.md:980`, heute fest beim Start, also `nextStart`) und „Spiel hängt, Overlay von selbst“ (`docs/TODO.md:976`).

---

## 4. Technische Grenzen

### Die Tastatur bleibt beim Spiel

Bleibt so: `.nonactivatingPanel`, kein `makeKey` über einem Spiel mit Bild. Daraus folgt:

- **Keine Textfelder im Overlay**, auch keine fremden Controls, die das Panel zum Key-Fenster machen. Heute verhindert das nur `becomesKeyOnlyIfNeeded`, `canBecomeKey` steht fest auf `true` (`GameOverlay.swift:347`). **Vorschlag:** wie bei `HintPanel` an `takesKeys` binden, dann kann es gar nicht passieren.
- **Regler selbst zeichnen** und mit `PadFocus` bedienen, nicht über `Slider`.
- Nightforge zu aktivieren wäre der einfache Weg, dem Spiel den Pad zu nehmen (Abschnitt unten), ist aber genau das Verbotene.

**Anti-Cheat:** Nichts wird geladen oder versteckt, das Overlay ist ein normales Fenster eines normalen Programms. `SIGSTOP` kommt von außen und gilt nur für Spiele, die Nightforge selbst gestartet hat. Die Leistungsanzeige sitzt in der Engine (`winemetal.so`), nicht als Einspritzung. Spiele mit Anti-Cheat bleiben bei den bestehenden Regeln.

### Bekommt das Spiel die Eingaben, während das Overlay offen ist?

**Ja, immer. Nur ob es sie verarbeitet, ist verschieden.**

| Spiel | Weg der Eingabe | Was passiert | Beleg |
|---|---|---|---|
| Windows | SDL in `winebus` (läuft in `winedevice.exe`) liest das Pad, unabhängig von Fenster oder Fokus. `hidclass` puffert, XInput liest im Prozess des Spiels | Spiel steht wegen `SIGSTOP`, `winedevice` läuft weiter und sammelt | [Code] `GameOverlay.swift:11–16, 307, 702`, `LibraryModel.swift:1689`; [Wine] `sdl_bus_wait`, `hid_update_thread_proc` |
| Mac-Version | GameController liefert an die App vorne, und das bleibt das Spiel | **Spiel läuft und reagiert mit**, der Spieler geht mit | [Code] `GameOverlay.swift:14–16`; [SDK] `GCController.h:161–169` |
| Nightforge | `shouldMonitorBackgroundEvents` | Hört das Pad, auch wenn das Spiel vorne ist | [Code] `InputRouter.swift:402, 118` |

**Zeitlich genauer:**

| Moment | Windows-Spiel | Mac-Version |
|---|---|---|
| Die 2 s Halten | Sieht L3 + R3 | Sieht L3 + R3 |
| Panel offen bis zur Pause (300 ms, wegen ABZU) | Sieht alles | Sieht alles |
| Overlay offen | Steht, nichts passiert | Läuft, reagiert |
| Weiterspielen mit A oder B | **Läuft an, solange die Taste unten ist** | wie bisher |
| Danach | Holt die gepufferten Reports nach | – |

**Der Fehler von heute:** Die Pad-Handler reagieren auf das Drücken (`InputRouter.swift:426, 452`), „Weiterspielen“ ruft also sofort `cont()`. Die Taste ist dabei noch unten, das Spiel sieht A oder B. Beim Schließen durch erneutes Halten sind es die Stick-Tasten. Dazu kommt ein Nachlauf: `hidclass` hält pro Handle bis zu 32 Reports und gibt den ältesten zuerst [Wine: `hid_queue_create`, `hid_queue_pop_report`]. XInput arbeitet sie ab und gibt immer den letzten Zustand aus, nur aus dem Zustandsvergleich entstehen Tastendrücke [Wine: `get_current_state`, `check_for_keystroke`]. Das erklärt, warum das meist gutgeht, aber nicht immer **[Vermutung, Live]**.

**Eine größere Schwachstelle:** `pauses` gilt für jedes Windows-Spiel, ohne Rücksicht auf Online (`LibraryModel.swift:1689`). Das kleine Menü verlässt man in Sekunden. Im großen Overlay schaut man länger, und bei Overwatch kann eine längere Pause die Verbindung trennen **[Vermutung, Live]**. `docs/TODO.md:953` warnt schon davor.

**Lösungswege:**

| # | Weg | Für | Aufwand | Bewertung |
|---|---|---|---|---|
| 1 | **Weiterlaufen erst beim Loslassen**: `cont()` wartet, bis nichts mehr gedrückt ist, höchstens 1 s | Windows | S | Sofort, auch fürs heutige Overlay |
| 2 | **Stille Eingabe in `winebus`**: Eine Darwin-Notification (wie beim HUD-Schalter) lässt `winebus` Neutralstellung melden und Reports zurückhalten. Beim Schließen einmal der echte Stand | Windows, besonders online | M | **Der richtige Weg.** Spiel und Ton laufen weiter, das Spiel „sieht“ den Pad nicht mehr, kein Nachlauf. Sitzt in `winedevice.exe`, nicht im Spiel. `sdl_bus_wait` → `bus_event_queue_input_report` ist die Stelle [Wine]. Patch für beide Engines wie `winebus-*-xbox360-ids.patch`, Workflow-Build nötig |
| 3 | Mac-Spiele auch anhalten | Mac | S | Laut Kommentar kämen die Events danach gesammelt. Das ist unbelegt, Spiele, die den Zustand abfragen, träfe es nicht **[Vermutung]**. Erst eine kleine Probe (GameController-Testprogramm, `SIGSTOP`, drücken, `SIGCONT`, loggen) |
| 4 | Mac-Spiele laufen lassen und es sagen | Mac | S | **Vorläufig so.** Eine Zeile: „Das Spiel läuft mit“ |
| 5 | Pad exklusiv belegen (`kIOHIDOptionsTypeSeizeDevice`, CoreHID `seizeDevice`) | beide | L | **Nein.** Laut SDK empfangen dann „the system and other clients“ nichts, also vermutlich auch Nightforges eigenes GameController. Nightforge müsste DualSense- und Xbox-Reports selbst lesen. Was Wine dabei tut, ist offen **[SDK, Quelle 11]** |
| 6 | Nightforge aktivieren: das Spiel ist nicht mehr vorne, GameController liefert ihm nichts mehr | Mac | S | **Verboten**, nimmt dem Spiel die Tastatur, kann Space wechseln oder das Spiel minimieren |

**Nur live zu klären:**

1. Mac-Version: Reagiert sie wirklich auf alle Drücke (Valheim, Batman)?
2. Testprogramm: Kommt nach `SIGCONT` ein Stau an?
3. Windows-Spiel: 30-mal drücken im Overlay, weiterspielen. Passiert danach etwas?
4. Overwatch: Wie lange trägt eine Pause?
5. `winebus` still: Sehen Spiele den Pad noch, wenn nichts mehr kommt? Spiele mit Steam Input?
6. Was tut das Spiel in den 2 s Halten?

### Das Spiel darf keine Bilder verlieren

- **Keine Unschärfe**, weder live noch als Standbild: Ein Foto des Spiels bräuchte „Bildschirmaufnahme“.
- **Kein `.ultraThinMaterial`, kein großer Schatten**, keine Dauer-Animation. Ein Öffnen in höchstens 150 ms, dann steht die Fläche.
- **Timer:** höchstens einmal pro Minute. Sitzungszeit in Minuten, nie Sekunden.
- **Geschlossen ist weg**: `orderOut`, nicht unsichtbar.
- **Fensterfläche:** Heute ist das Panel so groß wie der Bildschirm. Bei einer Seitenleiste reicht ein Fenster von einem Drittel. Das spart beim laufenden Mac-Spiel Mischarbeit.
- **„Direct“ geht verloren, solange das Overlay offen ist.** Ein Fenster über dem Spiel macht „Composited“ (Notizen zu `direct-display`). Darum ist auch ein Dauer-Widget über dem Spiel kein Thema, das Overlay lebt nur, wenn es offen ist.
- **Rückmeldung beim Halten:** Ab 0,5 s ein kleiner Ring wie `GameHint`, klickt nicht, nimmt nichts. Haptik über GameController könnte mit SDL um den Motor streiten **[Live]**, daher vorerst nur das Bild.

### Fernseher und Controller

- **Komplett mit dem Pad.** Steuerkreuz und linker Stick führen, A wählt, B geht zurück und schließt zuletzt.
- **Lesbar auf 3 m:** Maße aus `docs/ENTWURF-KONSOLE.md`, Abschnitt 3: Text mindestens 24 pt bei 1080p, Haupttext 28–30 pt, Rand 5 %, Rahmen 6 pt statt 3 pt.
- **Eine 1920×1080-Fläche**, die aufs Display skaliert wird. Das ist eine Transformation, und `followDisplay` zieht schon mit, wenn ein Spiel den Modus wechselt. Ob `PadFocus` dabei richtig rechnet, klärt K3 **[Vermutung]**.
- **Auslöser bleibt L3 + R3.** Die PS-Taste gehört macOS, Apples Overlay bleibt dort erreichbar und stört nicht. Nightforge fängt nichts ab.

---

## 5. Was die anderen gut machen

| | Gut | Passt zum Sofa? | Für Nightforge |
|---|---|---|---|
| **Steam Overlay / Big Picture** | Zwei Ebenen: Spiel-Overlay (Erfolge, Anleitungen) und Schnellzugriff für Freunde, Mitteilungen und Einstellungen **[Quelle 5]**. Notizen und Fenster anheften **[Quelle 6]** | Ja, der Schnellzugriff am rechten Rand | Rechte Leiste, Reihenfolge nach Bedarf. **Nicht** die Technik: Steam sitzt im Spiel, Nightforge bleibt draußen |
| **Xbox Game Bar** | Bausteine (Widgets) für Aufnahme, Leistung, Anzeige, mit Kompakt-Modus für Controller **[Quelle 4]** | Der Kompakt-Modus ja, die volle Version nicht | Bausteine als Idee, aber wenige und fest |
| **PlayStation-Kontrollzentrum** | Eine Leiste, klare Einträge: Ton, Zubehör mit Akku, Wechsler; Karten nach Spiel; anpassbar **[Quelle 3]** | Sehr, das ist das Vorbild für „ein Griff“ | Akku, Ton und „kurz öffnen, kurz zu“. Variante B ist nah dran |
| **Apples Game Overlay** | Klein in der Ecke, Game Mode umschalten **[Quelle 1]**, Helligkeit, Lautstärke, Freunde **[Quelle 2]**. Öffnet per Home-Taste, „might“ laut Apple | Klein und ruhig: ja | Zurückhaltung abschauen. Fehlt laut Kritik: Leistung, Uhr, Spielzeit **[Quelle 2]**, genau das bringen wir mit |

**Was daraus folgt:** Kurz öffnen, weniges zeigen, ein Griff. Weder Fenster noch Web noch Freunde. Das eigene Merkmal ist, dass Nightforge weiß, wie das Spiel läuft: Engine, Leistungsanzeige, Ton am Fernseher, Controller.

---

## 6. Die drei Varianten

Alle zeigen dieselben Bausteine. Das Board stellt jede bei 1080p dar, in Stufe 2 groß und in Stufe 1 klein.

| | A: Seitenleiste | B: Streifen unten | C: Raum |
|---|---|---|---|
| Idee | Spalte rechts, das Spiel bleibt links sichtbar | Eine Reihe unten, Regler öffnen darüber eine Karte | Abgedunkelter Bildschirm, Kacheln in der Mitte |
| Bedienung | Hoch und runter, ein Weg | Links und rechts, ein Klick mehr für Regler | Vier Richtungen |
| Wächst | Einfach nach unten, scrollt | Bis etwa 9 Einträge, dann eng | Kacheln, aber bald voll |
| Fensterfläche | Ein Drittel | Etwa ein Drittel | Ganzer Bildschirm |
| Am TV | Sehr lesbar | Gut, Karten klein | Sehr lesbar |
| Nähe zu heute | Neu, Liste bleibt | Neu | Am nächsten am Panel |

**Empfehlung A.** Eine Richtung reicht, es wächst ohne Umbau, verdeckt am wenigsten, und das kleinste Fenster schont das Spiel.

---

## 7. Reihenfolge

1. **Sofort, unabhängig vom Board:** Weiterspielen beim Loslassen; `canBecomeKey` an `takesKeys` binden.
2. **Nach der Wahl:** Bausteinaufbau und Stufe 1 mit TV-Maßstab.
3. **Live-Runde** (Liste oben, Punkte 1, 3, 6), dazu das GameController-Testprogramm.
4. **`winebus` still**, Patch für beide Engines; danach Regel für Online-Spiele.
5. **Stufe 2**, je nach Merge der drei Zweige.
6. **Stufe 3**, Bildschirmfoto mit Ursachenklärung zuerst.

---

## 8. Fragen an den Nutzer

1. **Welche Variante?** Empfehlung A.
2. **Online-Spiele:** bis `winebus` still da ist wie heute pausieren, oder lieber weiterlaufen lassen, auch wenn die Figur mitgeht? Empfehlung: weiter pausieren und kurz im Overlay bleiben.
3. **Leistungsanzeige:** Alle DXMT-Spiele mit verstecktem HUD starten, damit der Schalter immer geht? Empfehlung: erst messen, was es kostet.
4. **Bildschirmfoto:** Wäre „Bedienungshilfen“ als einmaliges Recht in Ordnung, falls Create nicht zu retten ist?

---

## Quellen

1. Apple, Use Game Mode: https://support.apple.com/en-us/105118 (Command-Esc, Ecke, Home-Taste „might“, Stand 14.9.2026).
2. Gizmodo, Apple's New Game Overlay in macOS 26 Could Be So Much More: https://gizmodo.com/apples-new-game-overlay-in-macos-26-could-be-so-much-more-2000633326 (Beta, Juli 2025).
3. PlayStation, Customize the PS5 console control center: https://www.playstation.com/en-us/support/games/customize-ps5-control-center/
4. Windows Central zum Kompakt-Modus: https://windowscentral.com/gaming/pc-gaming/xbox-game-bars-new-pc-compact-mode-offers-a-glimpse-at-microsofts-gaming-handheld-future (Text nur aus der Suche, Volltext nicht abrufbar); Xbox, ROG Ally Tipps: https://news.xbox.com/en-us/2025/10/15/rog-xbox-ally-handheld-essential-tips-getting-started/
5. SteamDeckHQ, Neues Big Picture: https://steamdeckhq.com/ja/news/new-big-picture-now-in-beta-for-steam-based-on-deck-game-mode/
6. PC Gamer, Steam-Overlay-Update: https://pcgamer.com/steams-big-update-with-has-left-beta-now-everyone-can-pin-notes-videos-and-web-pages-to-the-screen-while-they-play (nur Titel abrufbar).
7. TidBITS zur Nachfrage bei Bildschirmaufnahme: https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly (2024, Stand für macOS 27 nicht geprüft).
8. Valve, Steam Web API: https://developer.valvesoftware.com/wiki/Steam_Web_API
9. GOG, Statistics and Achievements: https://docs.gog.com/sdk-stats-and-achievements/
10. timendum/gog_achievements (inoffiziell): https://awesome.ecosyste.ms/projects/github.com%2Ftimendum%2Fgog_achievements
11. Apple, `seizeDevice()`: https://developer.apple.com/documentation/corehid/hiddeviceclient/seizedevice() ; SDK `IOHIDKeys.h`.
12. Wine upstream: `dlls/winebus.sys/bus_sdl.c`, `dlls/xinput1_3/main.c`, `dlls/hidclass.sys/device.c` (https://github.com/wine-mirror/wine, `master`, nicht winecx e0aa380).
