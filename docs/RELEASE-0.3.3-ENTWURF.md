# 0.3.3: Status der Release-Notizen (nur für uns)

**21.11.: Der Nutzer gibt das Release frei, die Arbeitskommentare sind aus `v0.3.3.md` entfernt. Was live bestanden hat und was nach dem Release geprüft wird, steht in `docs/TODO.md` unter „0.3.3: Release“. Die Tabellen unten sind der Stand vom 15.11.**

Stand: `claude/staging-033` bei `60b582b` (15.11. abends), `docs/TODO.md` (Abschlussliste, Liste für 0.3.3, Vorhang nach
der Regel, Live-Ergebnisse vom 15.11.), `docs/AUDIT-0.3.3-ABSCHLUSS.md` und der Code. Ersetzt den Entwurf vom 9.11.

Der öffentliche Text steht in `docs/release-notes/v0.3.3.md` (den veröffentlicht `release.yml`). Dort trägt jeder Punkt,
der noch nicht live bestanden hat, einen HTML-Kommentar. Nach der Live-Runde: bestanden → Kommentar löschen,
gescheitert → Zeile streichen (und die Funktion ausschalten oder auf 0.3.4 schieben).

Status: **live** (Datum, woran) · **nur Tests** (Testreihen grün, nie in der echten App) · **ungeprüft**.

## In den Notizen

### Der Start repariert sich selbst

| Punkt | Status |
|---|---|
| Fehlstart → Abhilfe aus dem Protokoll → zweiter Start, „Noch ein Versuch …“, gelernt fürs nächste Mal | **live** 15.11. 12:09 ABZU (Befund `nvidia-interface` über den Testschalter `testFinding`, zweiter Start mit Bild, `learned.dllsOff`) und 16:40 nach der Regel. E3 (It Takes Two) und E4 (anderes Rezept) nie gesehen; ein echter, nicht ausgelöster Fall fehlt. |
| Fehlerfenster des Spiels zählt als Fehlstart, nächster Weg | **live** 15.11. 15:54 MGS V auf D3DMetal („Failed to load SteamAPI“ → Fehlstart → DXMT). |
| Genauerer Blick (ein Start mit mehr Protokoll) | **live** 15.11. 15:54 MGS V („nothing explains why it ended“ → Steam einmal neu → Diagnose). |
| Ruhiger Ladescreen nach der Regel des Nutzers, L3+R3-Tipp nur beim ersten Start | **live** 15.11. 16:36–16:47 (Testbuild `9bda7de`, ABZU, MGS V). Der Vollbild-Hinweis daraus: siehe „Bekannt“. |
| „Shader werden vorbereitet …“ nur beim ersten Start auf einem Weg | **nur Tests** (Kette auf `bb80f7f` grün, nicht eingespielt). |
| Start-Runde auf dem Endstand | **live** 15.11. 21:03–21:34 (`389cb19`): 21 von 21 mit Bild, auf jedem Weg, kein zweiter Anlauf. Nicht als eigene Zeile in den Notizen, aber der Beleg, dass die umgebaute Startschleife gewöhnliche Starts nicht stört. |

### Laufwerk wiedererkennen

| Punkt | Status |
|---|---|
| Übernahme ohne Download, nichts gelöscht, Zeile „… sind wieder da“ | **live nur für GOG**: Teil A, 15.11. 11:21 (`3c4981c`, leeres HOME, Disk-Image „NF Test“, Mafia II nach 5 s in `GOG/installed.json`, Image unverändert). Steam, Steam für Mac und Epic: Teil B auf dem Mac mini mit dem Nutzer, **ungeprüft**. Die Zeile selbst (Toast) ist nicht gesehen. |
| Zeile mit „Anmelden“ / „Einrichten“ in Einstellungen › Speicher | **nur Tests** (Live-Anleitung B9–B11). |

### Starten und Beenden

| Punkt | Status |
|---|---|
| Beenden beim ersten Mal, auch mit offenem Blatt (E12) | **live** 14.11. abends, viermal beim ersten Anlauf. |
| Kein Flackern, kein Desktop (ruhiger Ladescreen, Punkte 1–13 vom 8.11.) | **ungeprüft**. |
| Updates von Epic/GOG auf dem Ladescreen, B bricht ab (Punkt 10) | **ungeprüft**. „Restzeit“ bewusst weggelassen, wie schon bei 0.3.1. |
| „Hängt es? Zurück zu Nightforge“ nach 30 s (Punkt 9) | **ungeprüft**. |
| Steams Fragen auf dem Ladescreen (Punkt 11) | **ungeprüft**. |
| Lizenz beim ersten Start | **ungeprüft** (GTA V Enhanced; „Abbrechen“ in Steams Fenster hat noch nie ein Zeichen gezeigt). |
| Battle.net-Spiele für den Mac aus Nightforge | **ungeprüft** (Hearthstone startete in der Runde nicht; Spiele des Windows-Clients starten bewusst nicht, `LibraryModel.launch`). |

### Controller und Sofa

| Punkt | Status |
|---|---|
| Menü im Spiel als Leiste rechts, Spiel daneben sichtbar (`OverlayView.swift`, Overlay-Entwurf) | **ungeprüft** (Overlay-Größen, R1). Die Leiste selbst ist im Build; „Overlay-Variante B“ der 0.3.4-Liste ist etwas anderes. |
| Tastatur für den Controller | **ungeprüft, aber an**: Y öffnet sie (`InputRouter.swift:610`, `LibraryModel.openPadKeyboard`). Die Liste für 0.3.3 schiebt die Bildschirmtastatur auf 0.3.4 („Board fehlt“). **Entscheidung nötig:** live prüfen oder vor dem Release ausschalten. |
| Touchpad als Maus | **ungeprüft**, ab Werk an (`Prefs.padPointer` = true). |
| Spieler 1 und 2 | **ungeprüft** (zwei Pads). |
| Anmelden am Sofa (GOG per QR) | **ungeprüft**. |
| Einstellungen › Startseite | **ungeprüft**. |
| Fernseher (Schrift, Ränder, Erkennen an der Größe) | **ungeprüft** (T1–T5, 4K nie gelaufen). |

### Downloads und Strom

| Punkt | Status |
|---|---|
| Mac bleibt wach beim Laden, Zeile beim Zurückkommen | **ungeprüft** (Download-Hinweise). |
| Ruhe im Leerlauf, Steam schläft nach 30 min | **ungeprüft** (Koordinator am Protokoll einer Nacht). |

### Privatsphäre

`start-evidence.jsonl` liegt in `Engine.supportDir` (`StartEvidence.swift:58`), ist immer an, wird nie gekürzt (Audit W7,
Kürzen für 0.3.4) und von nichts gesendet. Der Problembericht nimmt daraus nur eine Zahl (`sortGames`, „wie viele
Spiele dieser Art hier laufen“), und den sendet der Spieler selbst. Die drei Testschalter (`gameTest.measurePlay`,
`gameTest.testFinding`, `testRootQuestion`) stehen nur im `#else` und fehlen im Release (B5, `release.yml:67`).

**Bewusst nicht** geschrieben: „die Test- und Messschalter gibt es im Release nicht“. Laut Audit W7 kennt das Release
weiter versteckte Schalter, darunter den Spieletest mit eigenem Bildraten-Protokoll (`gameTest.frameLog`, schon in
0.3.2), `closerLook` und `wineDebug`. Sie zeichnen nur auf, wenn jemand sie setzt. Die Notizen sagen deshalb nur, dass
das Messen beim Spielen nicht enthalten ist. Ebenso nicht „Nightforge misst nichts“: Die Zeilen mit Bildraten von DXMT
stehen wie bisher im lokalen Protokoll.

### Bekannt

| Punkt | Status |
|---|---|
| Overwatch im exklusiven Vollbild ohne Bild, „Randloses Fenster“ hilft | **live** 15.11. 15:36–15:45 (`306c29f`): 3 von 3 mit Bild im randlosen Fenster, vorher etwa jeder zweite Start ohne. |
| Hinweis dazu auf dem Ladescreen mit „Neu starten“ | **ungeprüft** (ein ⌘⇥, „Neu starten“ per Pad, W8). Braucht die signierte Profilliste mit `fullscreenHint`. Der deutsche Menüwortlaut („Optionen › Video › Randloses Fenster“) ist ein Arbeitswort, in Overwatch nachsehen. |
| 60-FPS-Limit greift auf D3DMetal nicht | belegt 14.11. (Wukong Ø 201, Control Ø 113 bei Limit 60; D3DMetal kennt keinen Schalter dafür). Weg A ist auf 0.3.4. |
| Mac-Fassungen ohne Bildraten-Messung | belegt (Messlauf 14.11.). |
| Grenzen der Laufwerks-Übernahme (Epic braucht Anmeldung und Netz, nur Spiele des Kontos; GOGs nächstes Update lädt vermutlich alles) | aus dem Code gelesen (TODO, „Offen, gelesen und nicht belegt“ 1–4), nicht gelaufen. |

## Weggelassen, und warum

- **Frage nach einer älteren Windows-Wurzel (Zertifikat):** Die Mechanik ist drin und live an MGS V belegt, aber nur
  mit dem Testschalter `testRootQuestion`; `WindowsRoots.onRequest` ist leer (Audit), im Release kommt die Frage nie.
- **A und B in Windows-Fragen:** braucht `pad-answer.exe` im Bundle. Ein Release-Build nimmt die eingecheckte Datei
  (`build.sh:86`), die es nicht gibt; `pad-answer.yml` schlägt sie erst als Bot-PR vor.
- **Weniger Ruckeln durch frühe Shader-Übersetzung:** In der App ab Werk an (`dxmtEarlyShaders`), wirkt aber nur mit dem
  DXMT-Patch `dxmt-0.80-prepare-shaders` im Grafik-Baustein. Den bringt erst Bot-PR #41 (graphics `-17` → `-18`), der an
  der LGPL-Entscheidung zu DXMT hängt. Steht ohnehin auf der 0.3.4-Liste.
- **Inhalt des Menüs im Spiel** (Spielzeit, Uhr, Akku, wie im Entwurf vom 9.11.): nicht nachgeprüft, darum nennen die
  Notizen nur die Leiste rechts.
- **Auf 0.3.4 laut Liste:** Limit auf D3DMetal, Create-Taste, Klänge, TV-Stufe G2, Konsolen-Modus, HUD im Spiel
  umschalten, Mac-Fassungen messen, FPS auf der Landingpage.
- **Nicht genannt, obwohl im Zweig:** Regedit nur bei Änderung (live 15.11. als Protokollzeile, Nutzen ungemessen),
  msync je Spiel (kein Profil nutzt es), Mac-Startarten über `-applaunch`, Valheims „Cloud Out of Date“, PS-Taste und
  Ein/Aus, Vibration, „Beim Anmelden öffnen“, „Mac wach halten“. Alles ungeprüft. Wer davon live besteht, kann eine
  Zeile bekommen.
- **„Noch einmal von vorn“ vergisst Gelerntes (B8):** Den Knopf und seinen Wortlaut habe ich nicht gefunden, darum ohne
  Zeile.

## Offen vor dem Release

1. Tastatur für den Controller: live prüfen oder ausschalten (siehe oben).
2. Live-Runde mit dem Nutzer (Abschlussliste Punkt 2), danach die Kommentare in `v0.3.3.md` abarbeiten.
3. `scripts/sign-lists.sh main` (neue Felder `ownAntiCheat`, `fullscreenHint`), sonst fehlt der Overwatch-Hinweis.
4. Overwatchs deutscher Menüwortlaut für „Randloses Fenster“.
5. Datum und Version: Version in `Info.plist` und Landingpage kommen mit dem Release (nicht Teil dieses Auftrags).
