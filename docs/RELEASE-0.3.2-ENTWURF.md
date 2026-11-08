# 0.3.2: Entwurf der Release Notes und Checkliste

Stand: `claude/staging-032` (24 Commits nach 0.3.1, 3828f46) und `docs/TODO.md` vom 8.11. Jede Zeile der Notes ist gegen
ihren Commit geprüft. **Für das Release muss Teil A nach `docs/release-notes/v0.3.2.md`:** `release.yml` veröffentlicht
nur diese Datei.

## A. Release Notes

<!-- Zum Kopieren nach docs/release-notes/v0.3.2.md: alles zwischen hier und „B. Checkliste“. -->

## Deutsch

Nightforge 0.3.2 bringt Overwatch auf den Mac, ein neues Menü für deine Launcher und eine Suche über mehrere Stores. Dazu bleiben Spiele zuverlässiger vorne, und macOS fragt seltener nach. Das Wichtigste:

**Voraussetzung** wie bisher: ein Mac mit Apple silicon und macOS 26 (Tahoe) oder neuer.

### Spiele
- **Overwatch läuft** über Steam, auf DXMT. Bisher hing es beim Start ohne Fenster. Der Hinweis „Startet noch nicht“ ist weg.
- **Left 4 Dead 2 lädt seine Karten wieder.** Es hing beim Laden einer Karte, weil Wine ihm vier Lautsprecher meldete. Jetzt startet es in Stereo.
- **Leistungsanzeige auch in Mac-Versionen:** Die Metal-Leistungsanzeige aus den Optionen erscheint jetzt auch in Mac-Spielen und verschwindet wieder, wenn du sie abschaltest.
- **Das Löschen der Shader-Caches ist gründlicher:** Es leert jetzt auch DXMTs Metal-Zwischenspeicher für jedes Spiel.
- Hast du ein Spiel als „Startet nicht“ markiert und bringt sein Spielprofil später eine Korrektur, probiert Nightforge es wieder ganz normal.

### Launcher und Stores
- **Launcher-Menü:** Vier Karten für Steam, Epic, GOG und Battle.net zeigen, wo du angemeldet bist und wie viele Spiele dort liegen. Angemeldet wird direkt von der Karte aus, danach bist du wieder im Menü. Dasselbe gibt es klein oben rechts; am Controller öffnet es die Taste ⧉.
- **Battle.net:** Ist der Battle.net-Client auf deinem Mac angemeldet, verknüpft Nightforge ihn von selbst. Deine Battle.net-Spiele stehen dann in der Bibliothek. Starten musst du sie noch im Battle.net-Client.
<!-- Nur, wenn der Nutzer GOGs Nutzungsbedingungen für die Suche freigibt (siehe C). Sonst „und GOG“ streichen. -->
- **Suche über mehrere Stores:** Die Suche fragt jetzt Steam und GOG. Treffer aus beiden stehen in einer Liste, ein Spiel, das beide verkaufen, ist eine Karte, und was du schon hast, führt zu deinem Spiel.
- **Stores ohne fremde Logos:** Jeder Store zeigt seinen Buchstaben mit einem Farbring in eigenem Ton. Ein Spiel ohne Cover zeigt seinen Namen groß, statt einer leeren Fläche.

### Bibliothek
- **Schnellmenü:** Ein langer Klick auf eine Spielkarte, der Knopf „···“ auf dem Cover oder ☰ gehalten am Controller öffnet die Aktionen des Spiels, dieselben wie im Rechtsklick.
- **Später spielen:** Über das Schnellmenü merkst du dir Spiele vor. In der Bibliothek erscheint dazu ein eigener Filter.
- Der Aktualisieren-Knopf oben ist weg: Die Bibliothek frischt sich selbst auf. ⌘R und „Bibliothek neu einlesen“ im Menü bleiben.
- **Von der Startseite nehmen:** Im Schnellmenü nimmst du ein Spiel von der Startseite, ohne es aus der Bibliothek auszublenden. Es kommt zurück, sobald du es wieder spielst oder anheftest.
- **Zwei Controller:** Die Leiste unten zeigt jeden verbundenen Controller mit seinem Akku, nicht nur den, der gerade bedient.

### Spielen
- **Spiele bleiben vorne:** Manche Unity- und Unreal-Spiele, etwa The Forest, verschwanden kurz nach dem Ladebildschirm ins Dock, weil Nightforge ihnen einen Moment lang die Tastatur nahm. Das passiert nicht mehr, und verschwindet ein Spiel trotzdem, holt Nightforge es zurück.
- **Controller zu spät eingeschaltet:** Schaltest du den Controller erst ein, wenn ein Windows-Spiel schon läuft, erscheint ein kurzer Hinweis über dem Spiel, und im Controller-Menü steht der Neustart des Spiels ganz oben.
- **Nightforge neu starten:** Im Menü „Nightforge“ und in den Einstellungen beendet „Nightforge neu starten“ Steam, Wine und alles, was im Hintergrund läuft, und startet Nightforge frisch. Das hilft, wenn etwas hängt.
- **Steam geht nach dem Beenden wieder mit:** Ein abgebrochener Download eines Steam, das gar nicht mehr lief, hielt Steam für Mac bis zu zwölf Stunden offen.
- **Mac-Spiele mit mehreren Startarten** wie Drawful 2 starten gleich in ihrer eigenen Version. Bisher wartete Steam auf eine Auswahl in einem Fenster, das nicht nach vorne kam.

### macOS
- **Eine Frage weniger:** „Nightforge Helper“, über den Nightforge Steam, Wine und die Spiele startet, kommt jetzt fertig signiert mit der App. macOS fragt deshalb nur noch einmal nach dem Zugriff auf externe Laufwerke und behält die Antwort über Updates hinweg.

### Bekannt
- Battle.net-Spiele startest du noch im Battle.net-Client. Blizzards Mac-Spiele bleiben auf der internen Platte, weil Blizzards Mac-Agent nicht auf externe Laufwerke darf.
- Mit dem Controller kann der Mauszeiger über einem Spiel stehen bleiben, das ihn nicht selbst versteckt.
- Weiter wie bisher: Online-Spiele mit Anti-Cheat laufen in ihrer Windows-Version nur über GeForce Now, DirectX 9 läuft meist über WineD3D, oft langsamer und ohne MetalFX, und Anmelden und Suchen brauchen noch eine Tastatur.

---

## English

Nightforge 0.3.2 brings Overwatch to the Mac, a new menu for your launchers and a search across more than one store. Games also stay in front more reliably, and macOS asks less often. The main changes:

**Requirements** as before: a Mac with Apple silicon and macOS 26 (Tahoe) or later.

### Games
- **Overwatch runs** through Steam, on DXMT. Until now it hung at the start without a window. The "Doesn't start yet" note is gone.
- **Left 4 Dead 2 loads its maps again.** It hung loading a map because Wine reported four speakers to it. Now it starts in stereo.
- **Performance HUD in Mac versions too:** the Metal performance HUD from the options now shows in Mac games as well, and goes away again when you switch it off.
- **Clearing the shader caches goes deeper:** it now also empties DXMT's Metal caches for each game.
- If you marked a game "Didn't start" and its game profile later brings a fix, Nightforge tries it the normal way again.

### Launchers and stores
- **Launcher menu:** four cards for Steam, Epic, GOG and Battle.net show where you're signed in and how many games are there. You sign in right from the card and land back in the menu. The same comes small at the top right; on a controller, the ⧉ button opens it.
- **Battle.net:** when the Battle.net client is signed in on your Mac, Nightforge links it by itself. Your Battle.net games then show in the library. You still start them in the Battle.net client.
<!-- Only if the user clears GOG's terms for the search (see C). Otherwise drop "and GOG". -->
- **Search across stores:** search now asks Steam and GOG. Hits from both share one list, a game both sell is one card, and what you already own leads to your game.
- **Stores without other people's logos:** each store shows its letter with a ring in a tone of its own. A game without a cover shows its name in large type instead of an empty tile.

### Library
- **Quick menu:** a long click on a game card, the "···" button on the cover or ☰ held on a controller opens the game's actions, the same as the right-click menu.
- **Play Later:** mark games for later from the quick menu. The library gets a filter of its own for them.
- The refresh button at the top is gone: the library refreshes by itself. ⌘R and "Rescan Library" in the menu stay.
- **Remove from Home:** in the quick menu you take a game off Home without hiding it from your library. It comes back once you play it again or pin it.
- **Two controllers:** the bar at the bottom shows every connected controller with its battery, not only the one in use.

### Playing
- **Games stay in front:** some Unity and Unreal games, like The Forest, slipped into the Dock right after the loading screen, because Nightforge took their keyboard for a moment. That no longer happens, and if a game disappears anyway, Nightforge brings it back.
- **Controller switched on late:** if you switch your controller on after a Windows game started, a short note shows over the game, and restarting the game comes first in the controller menu.
- **Restart Nightforge:** in the Nightforge menu and in Settings, "Restart Nightforge" ends Steam, Wine and everything running in the background, and starts Nightforge fresh. It helps when something hangs.
- **Steam goes again when you quit:** a stopped download of a Steam that no longer ran kept Steam for Mac open for up to twelve hours.
- **Mac games with several ways to start**, like Drawful 2, start their own version right away. Until now Steam waited for a choice in a window that didn't come to the front.

### macOS
- **One question less:** "Nightforge Helper", which Nightforge starts Steam, Wine and the games through, now comes signed inside the app. So macOS asks only once for access to external drives and keeps your answer across updates.

### Known
- You still start Battle.net games in the Battle.net client. Blizzard's Mac games stay on the internal disk, because Blizzard's Mac agent can't reach external drives.
- With a controller, the mouse pointer can stay over a game that doesn't hide it by itself.
- Still as before: online games with anti-cheat only run through GeForce Now in their Windows version, DirectX 9 mostly runs through WineD3D, often slower and without MetalFX, and signing in and searching still need a keyboard.

## B. Checkliste

### 1. Vor dem Release live prüfen (Stand `docs/TODO.md`, 8.11.)

- [ ] **Overwatch** über Steam: Start, Spiel, Beenden. Lief am 7.11. aus Nightforge (DXMT, Direct). Die Rosetta-Registrierung
      (`CX_APPLEGPTK_LIBD3DSHARED_PATH`, 3616bae) ist laut Notizen mit anderen Spielen noch ungetestet: Gegenprobe mit
      Control (D3DMetal), Wukong-Benchmark, OxyRail (DXMT) und ABZU.
- [ ] **Launcher-Menü** (TODO „Launcher-Menü“: „Nichts davon lief in der echten App“): Epic und GOG auf der Bühne (Tastatur,
      Zwei-Faktor, „Mit Google anmelden“), Battle.net-Fenster über dem Vorhang, B bei fremdem Fenster vorn, Pad auf Karten und
      Menü, Erststart mit den Karten nach Steams Anmeldung, ⧉ bzw. Create am DualSense (Create soll im Spiel weiter
      Bildschirmfotos machen).
- [ ] **Battle.net:** Verknüpfen lief live am 7.11. (93c10f2). Noch: Abmelden ohne „Angemeldet bleiben“ (Karte zeigt
      „Abgemeldet“, nur „Erneut anmelden“), „Trennen“ bleibt gemerkt, „Spielen“ verweist auf den Client.
- [ ] **Vorhang und Bühnenwache** (TODO „Vorhang und Bühnenwache“, live offen): The Forest, ABZU (verschwand 10–20 s nach dem
      Vorhang), Valheim. Dazu der Zeiger mit Pad über einem Spiel.
- [ ] **Schnellmenü und „Später spielen“:** Laut Notizen am 7.11. angesehen, die TODO-Punkte sind noch nicht abgehakt: langer Klick,
      „···“ auf der kleinsten Kartengröße, ☰ gehalten und kurz, ☰ + ⧉ an einem Pad ohne Stick-Tasten, der Filter in der Bibliothek.
- [ ] **Store-Suche:** Treffer aus Steam und GOG, ein Spiel aus zwei Stores als eine Karte, eigene Spiele führen zum Spiel.
- [ ] **HUD in Mac-Versionen:** mit Valheim (TODO: „Live prüfen mit Valheim“), an und wieder aus.
- [ ] **Left 4 Dead 2:** eine Karte laden. Offen bleibt, warum winecx vier Kanäle meldet.
- [ ] **Helper mit Zertifikat:** Update von 0.3.1 auf den Kandidaten, dann ein Spiel von der externen NVMe. Wie oft fragt macOS,
      und für welche App?
- [ ] **Controller spät:** ein Windows-Spiel starten, erst dann den Pad einschalten. Hinweis über dem Spiel, Neustart oben im Menü.
- [ ] **Shader-Caches löschen:** danach ist `$DARWIN_USER_CACHE_DIR/dxmt/<exe>` leer.
- [ ] Alle Testreihen (`scripts/run-tests.sh -P 2`), pytest und `tests/ProcessListLive/run.sh`.

### 2. Release-Kette

Signieren macht der Nutzer im Mac-Terminal, aus `.claude/worktrees/release-main`.

1. ~~Teil A nach `docs/release-notes/v0.3.2.md` und die Version auf 0.3.2 setzen~~ Erledigt 8.11.: Die Datei liegt auf Staging, `Resources/Info.plist` sagt 0.3.2. Ändert sich Teil A noch, beide Stellen nachziehen.
2. Pull Request `claude/staging-032` → `main` (Ruleset), Merge mit dem OK des Nutzers.
3. `scripts/sign-lists.sh main` (Nutzer).
4. enginefix- bzw. components-Workflow laufen lassen. Er legt einen Bot-PR auf `bot/components` an.
5. `scripts/sign-lists.sh bot/components` (Nutzer), dann den Bot-PR mergen.
6. rc-Tag setzen (mit Suffix, etwa `v0.3.2-rc1`: wird ein Vorab-Release), Kandidaten installieren und Teil 1 durchgehen.
7. `scripts/sign-release.sh <tag> --publish` (Nutzer).

### 3. Offene Entscheidungen

- **GOGs Nutzungsbedingungen, Klausel 11.1(e):** Die Store-Suche fragt GOGs öffentlichen Katalog. Die gemeldete Klausel zu
  - **Entschieden (8.11., Nutzer): Die GOG-Suche bleibt.** Gelesen am 8.11.: 11.1(e) verbietet Software, die mit GOGs
    Diensten interagiert, auch nicht autorisierte Drittprogramme, die Informationen sammeln. Das trifft Nightforges
    ganze GOG-Anbindung (wie bei Heroic), die Suche ändert daran wenig. Keine Rechtsberatung.
  automatisiertem Zugriff ist laut TODO unbestätigt. Entscheidet der Nutzer dagegen, ist die Stelle zum Abschalten
  `GOGStore.search`, und in den Notes fällt „und GOG“ weg.
- **Battle.net-Bilder über Steam-Zwillinge:** Overwatch, Diablo IV und Call of Duty aus Battle.net holen ihr Logo weiter von
  Steams CDN (`steamTwin` in `Artwork.remoteURLs`). Ob das nach der Rechtsprüfung bleiben darf, entscheidet der Nutzer.
- Wartet auch aufs OK, ist aber kein Release-Blocker: Battle.nets Fenster in Nightforges Rahmen legen (`CGWindowListCopyWindowInfo`, TODO
  „Launcher-Menü“).
