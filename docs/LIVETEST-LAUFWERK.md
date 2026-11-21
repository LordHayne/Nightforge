# Live-Prüfung: Laufwerk mit Spielen wiedererkennen

Stand: Zweig `claude/sad-nightingale-196da3`, 15.11.2026. Gebaut und mit Tests belegt (`DriveFindsTest`,
`DriveTakeoverTest`), **nichts davon live gelaufen**: kein Nightforge-Fenster, kein echtes legendary, kein echtes Steam.
Diese Liste sagt, wie man es prüft, ohne dem Laufwerk des Nutzers etwas zu tun.

## Was die Übernahme tut, in einem Satz je Laden

- **Steam, Steam für Mac:** Die Bibliothek auf dem Laufwerk kommt in Steams Liste (`libraryfolders.vdf`), bei gestopptem
  Steam; lief es, startet es danach wieder. Auf dem Laufwerk ändert sich nichts.
- **Epic:** `legendary import <App> <Ordner> --platform Windows --skip-dlcs`, danach je Add-on einmal. Braucht die
  Anmeldung und das Netz (legendary holt das Manifest), lädt aber nichts vom Spiel.
- **GOG:** ein Eintrag in Nightforges `GOG/installed.json`, aus der `goggame-<id>.info` des Spiels.
- **Wann:** einmal nach dem Start, nach jedem Anstecken, und wenn etwas Wartendes dran sein könnte (Spiel zu Ende,
  Anmeldung da). Nie, während ein Spiel, ein Download, ein Umzug oder die erste Einrichtung läuft.

## Schutz, der eingebaut ist

- Ein Nightforge in einem **eigenen HOME** (Testumgebung) sieht für die Übernahme **nur Disk-Images** an, nie ein echtes
  Laufwerk (`DriveTakeover.drives`). „Games“ darf also stecken bleiben.
- Eine Testreihe im echten HOME (kein App-Bundle) übernimmt nichts (`GameLog.writes`).
- Der **installierte Testbau im echten HOME** sieht dagegen das echte Laufwerk an. Dort ist heute alles bekannt, also
  hat er nichts zu tun – siehe „Was der Testbau auf ‚Games‘ fände“ in `docs/TODO.md`.

## Teil A – leeres HOME, nachgebautes Laufwerk (Koordinator, 20 min, ohne Anmeldung)

Prüft: Erkennen aus den Dateien, GOG-Übernahme, Warten bei Steam und Epic, und dass auf dem Laufwerk nichts geändert wird.

1. Das installierte Nightforge beenden (sonst sehen die Werkzeuge nur eines der beiden Fenster). `./build.sh`.
2. Laufwerk nachbauen, als Disk-Image:

   ```bash
   hdiutil create -size 200m -fs APFS -volname "NF Test" build/nf-test.dmg && hdiutil attach build/nf-test.dmg
   ```

   ```bash
   D="/Volumes/NF Test/Nightforge Games"; mkdir -p "$D/steamapps/common/Left 4 Dead 2" "$D/Epic Games/ABZU" "$D/GOG Games/Mafia II/pc"
   printf '"libraryfolder"\n{\n\t"contentid"\t\t"4242"\n\t"label"\t\t""\n}\n' > "$D/libraryfolder.vdf"
   printf '"AppState"\n{\n\t"appid"\t\t"550"\n\t"name"\t\t"Left 4 Dead 2"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Left 4 Dead 2"\n\t"SizeOnDisk"\t\t"3000"\n}\n' > "$D/steamapps/appmanifest_550.acf"
   echo x > "$D/steamapps/common/Left 4 Dead 2/left4dead2.exe"; echo x > "$D/Epic Games/ABZU/AbzuGame.exe"; echo x > "$D/GOG Games/Mafia II/pc/mafia2.exe"
   printf '{ "buildId": "1", "gameId": "1816059595", "rootGameId": "1816059595", "languages": ["de-DE"], "name": "Mafia II", "playTasks": [{ "isPrimary": true, "path": "pc/mafia2.exe", "type": "FileTask" }] }' > "$D/GOG Games/Mafia II/goggame-1816059595.info"
   (cd "/Volumes/NF Test" && find . -type f -exec shasum {} + | sort -k2) > build/nf-test.before
   ```

3. Testumgebung `build/fh` (kurzer Pfad, Wine verträgt keine langen), GOG „verbunden“ ohne Anmeldung, Epic verbunden
   und abgemeldet:

   ```bash
   S="build/fh/Library/Application Support/Nightforge"; mkdir -p "$S/GOG" "$S/Epic"
   echo '{ "username": "test" }' > "$S/GOG/account.json"; echo '{ "displayName": "test" }' > "$S/Epic/account.json"
   echo '{ "games": [{ "id": "1816059595", "title": "Mafia II", "mac": false, "dlcs": [] }] }' > "$S/GOG/library.json"
   echo '{ "games": [{ "appName": "Quail", "title": "ABZU", "namespace": "", "folder": "ABZU", "cloudSaves": false }] }' > "$S/Epic/library.json"
   ```

4. Starten und nichts anklicken; **in dieser Umgebung nie bei Steam anmelden** (der QR-Code meldet das echte Steam ab):

   ```bash
   env CFFIXED_USER_HOME="$PWD/build/fh" HOME="$PWD/build/fh" build/Nightforge.app/Contents/MacOS/Nightforge
   ```

5. Nach etwa einer Minute, in einem zweiten Terminal:

| Nr. | Erwartet | Wo |
|---|---|---|
| A1 | Mafia II steht mit Ordner `/Volumes/NF Test/Nightforge Games/GOG Games/Mafia II`, `build` 1, `language` de-DE | `build/fh/…/Nightforge/GOG/installed.json` |
| A2 | Kein Eintrag für ABZU: Epic ist abgemeldet, legendary wurde nicht gerufen | `…/Epic/legendary/installed.json` fehlt |
| A3 | Steams Liste ist nicht angelegt: dieses Steam ist nicht eingerichtet | `…/Prefix/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf` fehlt |
| A4 | Auf dem Image ist nichts anders | `(cd "/Volumes/NF Test" && find . -type f -exec shasum {} + \| sort -k2) \| diff build/nf-test.before -` ist leer |
| A5 | In der Bibliothek (falls die Einrichtung sie schon zeigt): Mafia II als installiert, Spielen statt Laden | Fenster |

   Offen und hier mitzuprüfen: ob die Schleife, die den Blick auslöst, schon während der ersten Einrichtung läuft. Kommt
   A1 erst nach dem Schließen der Einrichtung, ist das in Ordnung, soll aber notiert werden.

6. Beenden über den Pfad (`osascript -e 'tell application "<Pfad>/build/Nightforge.app" to quit'`), dann
   `hdiutil detach "/Volumes/NF Test"`, `build/fh` und `build/nf-test.*` löschen.

## Teil B – der echte Fall, nur mit dem Nutzer

Das Einzige, das Steam, Steam für Mac und Epic wirklich prüft, ist ein Nightforge, das das Laufwerk nicht mehr kennt.
Dafür gibt es einen Weg ohne Neuinstallation, der nichts auf dem Laufwerk löscht – er ändert aber Nightforges echte
Listen und ist darum **die Entscheidung des Nutzers**:

1. Vorher sichern, aus `~/Library/Application Support/Nightforge`: `Epic/legendary/installed.json` und
   `Epic/legendary/manifests/`, `GOG/installed.json`, `GOG/gogdl/heroic_gogdl/manifests/` und `GOG/Support/` – das
   Vergessen räumt die Manifeste und GOGs Zusatzdateien mit weg –, dazu je Steam beide `libraryfolders.vdf` (`config/`
   und `steamapps/`; Nightforges Steam im Prefix, Steam für Mac in `~/Library/Application Support/Steam`). Kein Spiel,
   kein Download läuft.
2. „Games“ auswerfen. In den Einstellungen unter Speicher „Laufwerk vergessen …“ wählen. Alle Spiele darauf stehen
   jetzt als „nicht installiert“ da: der Zustand nach einer Neuinstallation, mit Anmeldungen.
3. „Games“ anstecken, nichts anklicken.

| Nr. | Erwartet | Log (`wine.log`) |
|---|---|---|
| B1 | Steam-Spiele sind binnen etwa einer Minute wieder installiert; Steam startete dafür einmal neu | `Drive takeover: … game(s) on Games are back` |
| B2 | Steam-für-Mac-Spiele ebenso. War Steam für Mac sichtbar offen: erst nach dessen Beenden | dieselbe Zeile, später |
| B3 | GOG: Mafia II sofort wieder da, startet | dieselbe Zeile |
| B4 | Epic: jedes Spiel kommt einzeln zurück, je einige Sekunden (legendary fragt Epic); Downloads-Feld bleibt leer | dieselbe Zeile; je Weigerung `legendary didn't take …` mit Grund |
| B5 | Ein Epic-Spiel mit Add-on (Guardians, Hogwarts) zeigt danach **kein** „Aktualisieren“ | – |
| B6 | Ein übernommenes Epic-Spiel und ein Steam-Spiel starten | – |
| B7 | Währenddessen ein Spiel starten: der Rest wartet und kommt nach dem Beenden | – |
| B8 | Abstecken, anstecken: nichts passiert noch einmal, Steam startet nicht neu | keine neue Zeile |

**Was der Nutzer sieht (Vorlage A, gewählt 15.11.):**

| Nr. | Erwartet |
|---|---|
| B9 | Unten im Fenster einmal eine Zeile „14 Spiele auf „Games“ sind wieder da“ (bei einem Spiel sein Name), sonst nichts; sie geht nach ein paar Sekunden. Epic kommt später als Steam und GOG und kann eine zweite Zeile bringen. |
| B10 | Der Dialog „Laufwerk vergessen“ endet jetzt mit „Steckst du Games später wieder an, sind seine Spiele ohne Download wieder da.“ |
| B11 | Nur wenn ein Laden abgemeldet oder Steam für Mac nicht eingerichtet ist: in Einstellungen › Speicher beim Laufwerk und unter Läden eine Zeile wie „9 Epic-Spiele auf „Games“ warten auf die Anmeldung“ mit „Anmelden“ (bzw. „Einrichten“). Mit dem Controller anwählbar; der Knopf schließt die Einstellungen und öffnet die Anmeldung. Nach der Anmeldung verschwindet die Zeile, die Spiele kommen von selbst. |

Was B nicht zeigt und nur eine echte Neuinstallation oder ein zweiter Mac zeigt: das Zusammenspiel mit der ersten
Einrichtung (die Spiele sollen beim ersten Blick auf die Startseite schon da sein) und Epic direkt nach der ersten
Anmeldung. Der Mac mini ist dafür kein Testgerät.

## Bekannte Grenzen, die beim Prüfen auffallen können

- **Epic nimmt den neuesten Stand an.** legendary trägt die Version des aktuellen Manifests ein, auch wenn die Dateien
  älter sind, und merkt das Spiel zur Prüfung vor. Nightforge zeigt deshalb kein Update an, bis Epic wieder einen
  neuen Stand hat; dann prüft legendary alle Dateien und lädt nur, was abweicht (so gelesen, nicht gelaufen).
- **Epic-Download, der nicht fertig wurde:** Fehlen mehr als 5 % der Dateien, bleibt das Spiel „nicht installiert“.
  Fehlt weniger, gilt es als installiert.
- **GOG-Update nach der Übernahme:** gogdl hat für das Spiel kein gespeichertes Manifest. Ob das nächste Update dann
  nur das Geänderte oder alles lädt, ist aus der mitgelieferten Fassung nicht sicher zu lesen (vermutlich alles).
- **Steam nimmt die Bibliothek ganz.** Ein halb geladenes Steam-Spiel darin lädt Steam von selbst weiter.
