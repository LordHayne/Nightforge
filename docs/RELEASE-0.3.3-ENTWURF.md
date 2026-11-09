# 0.3.3: Entwurf der Release Notes

Stand: `claude/staging-033` 1e6ed95 und `docs/TODO.md` vom 9.11. **Für das Release muss Teil A nach `docs/release-notes/v0.3.3.md`:** `release.yml` veröffentlicht nur diese Datei. Die Versionsnummer setzt `release.yml` aus dem Tag; bei 0.3.1 und 0.3.2 stand sie zusätzlich in `Resources/Info.plist`.

Nichts davon ist veröffentlicht. Was der Live-Test nicht bestätigt, fliegt vor dem Release aus Teil A (siehe Teil B).

## A. Release Notes

<!-- Zum Kopieren nach docs/release-notes/v0.3.3.md: alles zwischen hier und „B. Hängt am Live-Test“. -->

## Deutsch

Nightforge 0.3.3 macht deinen Mac mehr zur Konsole. Suchen und Zeigen gehen jetzt mit dem Controller, im Spiel gibt es ein neues Menü, und der Ladescreen bleibt ruhig stehen, bis das Spiel da ist. Das Wichtigste:

**Voraussetzung** wie bisher: ein Mac mit Apple silicon und macOS 26 (Tahoe) oder neuer.

### Controller
- **Tastatur für den Controller:** Y öffnet sie. Am DualSense tippst du mit beiden Daumen auf dem Touchpad und mit L2 und R2, bei anderen Controllern führt jeder Stick eine Hälfte. Die Suchleiste rückt groß über die Tastatur, und Treffer kommen ab dem ersten Buchstaben.
- **Touchpad als Maus:** Ein Finger bewegt den Zeiger, Drücken klickt, zwei Finger scrollen. Controller ohne Touchpad nehmen den rechten Stick. Für Klicks in anderen Programmen braucht Nightforge einmal das Recht „Bedienungshilfen“, unter Einstellungen › Controller › Als Maus.
- **Der Mauszeiger geht aus dem Weg,** sobald du mit dem Controller spielst. Maus oder Touchpad holen ihn zurück.
- **Spieler 1 und 2:** Die Leiste unten zeigt, welcher Controller welche Nummer hat, und am DualSense leuchtet die Lichtleiste passend. Ein ausgeschalteter Controller behält seinen Platz.
- **Meldungen im Spiel:** Controller verbunden, getrennt oder Akku unter 15 % erscheinen auch über einem Spiel, ohne ihm etwas wegzunehmen.
- **Vibration** beim Bestätigen, beim Spielstart und beim Öffnen des Menüs, abschaltbar unter Einstellungen › Controller.
- **PS-Taste:** Auf macOS 27 richtest du sie unter Einstellungen › Controller ein. Der lange Druck öffnet dann Nightforge, der kurze führt zur Startseite, solange Nightforge vorn ist.
- **Windows-Fragen vor dem Spiel** beantwortest du mit A und B.
- **Ein und Aus:** Im kleinen Menü auf ⧉ legst du den Mac schlafen oder beendest Nightforge. Ein Controller weckt das Bild wieder.
- Sobald ein Controller verbunden ist, bietet Nightforge am MacBook einmal das Vollbild an.

### Im Spiel
- **Neues Menü:** L3 und R3 halten öffnet rechts eine Spalte mit Spielname, Spielzeit, Uhr, Controller-Akku, Weiterspielen, Spiel beenden und Zu Nightforge. Das Spiel steht, solange sie offen ist.
- **Steams Fenster über einem Spiel,** etwa für herunterladbare Inhalte, kommt nach vorn und lässt sich bedienen. Machst du es zu, ist das Spiel wieder im Vollbild da.

### Starten und Beenden
- **Ein ruhiger Ladescreen:** Er steht sofort beim Druck auf „Spielen“ und bleibt, bis das Spiel da ist. Kein Flackern, kein Desktop dazwischen, auch beim Beenden und beim direkten Wechsel zum nächsten Spiel.
- **Updates auf dem Ladescreen:** Lädt Epic oder GOG vor dem Start etwas nach, siehst du Fortschritt, Tempo und Restzeit. B bricht ab, und beim nächsten Start geht es dort weiter.
- **Ein Ausweg, wenn Steam hängt:** Nach 30 Sekunden ohne Spiel steht auf dem Ladescreen „Hängt es? Zurück zu Nightforge“.
- **Steams Fragen liegen auf dem Ladescreen,** statt dass kurz die Nightforge-Seite aufblitzt.
- **Die Lizenz beim ersten Start:** Steam fragt bei manchen Spielen einmal nach der Lizenz. Nightforge sagt das an, rahmt Steams Fenster ein und startet das Spiel nach deinem Ja einmal neu, weil das Windows-Steam von selbst nicht weitermacht. Zustimmen musst immer du selbst.

### Fernseher und Sofa
- **Am Fernseher** ist die Schrift größer, die Ränder sind breiter und die Markierung ist dicker. Nightforge erkennt Fernseher auch an ihrer Größe.
- **Beim Anmelden öffnen:** Nightforge startet mit dem Mac und kommt nach vorn.
- **Mac wach halten:** Am Netzteil bleibt der Mac so lange wach, wie du es einstellst, damit der Controller ihn bereit findet. Ab Werk aus, auf Akku nie.
- **Anmelden am Sofa:** GOG geht jetzt per QR-Code mit dem Handy. Bei Epic sagt Nightforge vorher, dass einmal eine Tastatur nötig ist.

### Spiele und Launcher
- **Battle.net-Spiele starten aus Nightforge,** ohne dass du den Client bedienen musst.
- **Weniger Ruckeln am Anfang:** Bei DirectX-11-Spielen auf DXMT ohne Anti-Cheat übersetzt Nightforge Shader früher.
- **Startseite einstellen:** Unter Einstellungen › Startseite wählst du die Quellen und die Reihenfolge deiner angehefteten Spiele.
- **Valheim und andere Mac-Versionen:** Die Meldung „Cloud Out of Date“ nach einem Wechsel zwischen den beiden Steam-Versionen sollte nicht mehr kommen.

### Downloads und Strom
- **Der Mac bleibt wach, solange geladen wird,** bei allen Stores, auch mit ausgeschaltetem Bildschirm. Am Ring steht, ob der Mac wach bleibt oder schlafen darf, und kommst du zurück, sagt eine Zeile, wie viel in der Zwischenzeit geladen wurde.
- **Nightforge ruht, wenn niemand da ist:** Ohne Eingabe schaut es seltener nach, und Steam geht nach 30 Minuten schlafen, wenn nichts es braucht, auch am Netzteil. Auf Akku reicht es, wenn Nightforge so lange nicht vorn war. Steam wacht auf, sobald du zurückkommst.
- **Updates nach dem Aufwachen:** Lief der Mac eine Weile nicht, schaut Nightforge beim Aufwachen nach Neuem, ohne Admin-Rechte und ohne den Mac dafür zu wecken. Ein Spielstart hat immer Vorrang.

### Bekannt
- In Windows-Spielen vergibt das Spiel die Spielerplätze selbst. Spieler 1 im Spiel kann der andere Controller sein.
- Die Epic-Anmeldung braucht einmal eine Tastatur.
- Blizzards Mac-Spiele bleiben auf der internen Platte, weil Blizzards Mac-Agent nicht auf externe Laufwerke darf.
- Weiter wie bisher: Online-Spiele mit Anti-Cheat laufen in ihrer Windows-Version nur über GeForce Now, und DirectX 9 läuft meist über WineD3D, oft langsamer und ohne MetalFX.

---

## English

Nightforge 0.3.3 makes your Mac more of a console. Searching and pointing now work with a controller, there's a new in-game menu, and the loading screen stays calm until the game is there. The main changes:

**Requirements** as before: a Mac with Apple silicon and macOS 26 (Tahoe) or later.

### Controller
- **A keyboard for the controller:** Y opens it. On a DualSense you type with both thumbs on the touchpad and L2 and R2; on other controllers each stick drives one half. The search field moves large above the keyboard, and hits come from the first letter.
- **Touchpad as a mouse:** one finger moves the pointer, pressing clicks, two fingers scroll. Controllers without a touchpad use the right stick. For clicks in other apps Nightforge needs the Accessibility right once, under Settings › Controller › As a mouse.
- **The mouse pointer gets out of the way** as soon as you play with a controller. The mouse or the touchpad brings it back.
- **Player 1 and 2:** the bar at the bottom shows which controller has which number, and a DualSense's light bar matches. A controller you switch off keeps its place.
- **Notes in a game:** controller connected, disconnected or battery below 15 % also show over a game, without taking anything from it.
- **Vibration** when confirming, when a game starts and when opening the menu; switch it off under Settings › Controller.
- **PS button:** on macOS 27 you set it up under Settings › Controller. A long press then opens Nightforge, a short press goes to Home while Nightforge is in front.
- **Windows questions before a game** answer to A and B.
- **On and off:** in the small menu on ⧉ you put the Mac to sleep or quit Nightforge. A controller wakes the picture again.
- Once a controller connects, Nightforge offers full screen on a MacBook, one time.

### In a game
- **New menu:** holding L3 and R3 opens a column on the right with the game's name, play time, clock, controller battery, Continue Playing, Quit Game and Go to Nightforge. The game stands still while it's open.
- **Steam's window over a game,** for downloadable content for example, comes to the front and can be used. Close it and the game is back in full screen.

### Starting and quitting
- **A calm loading screen:** it's there the moment you press Play and stays until the game is. No flicker and no desktop in between, also when quitting and when going straight to the next game.
- **Updates on the loading screen:** when Epic or GOG has something to fetch before a start, you see progress, speed and time left. B cancels, and the next start picks up where it stopped.
- **A way out when Steam hangs:** after 30 seconds without a game the loading screen says "Stuck? Back to Nightforge".
- **Steam's questions sit on the loading screen,** instead of the Nightforge page flashing up.
- **The licence at the first start:** Steam asks some games' licence once. Nightforge announces it, frames Steam's window and starts the game once more after your yes, because the Windows Steam doesn't go on by itself. Agreeing is always up to you.

### TV and couch
- **On a TV** the text is larger, the margins are wider and the selection is thicker. Nightforge also recognises a TV by its size.
- **Open when you log in:** Nightforge starts with the Mac and comes to the front.
- **Keep the Mac awake:** plugged in, the Mac stays awake for as long as you set, so the controller finds it ready. Off by default, never on battery.
- **Signing in from the couch:** GOG now works with a QR code and your phone. For Epic, Nightforge says up front that a keyboard is needed once.

### Games and launchers
- **Battle.net games start from Nightforge,** without you operating the client.
- **Less stutter at the start:** for DirectX 11 games on DXMT without anti-cheat, Nightforge translates shaders earlier.
- **Set up Home:** under Settings › Home you choose the sources and the order of your pinned games.
- **Valheim and other Mac versions:** the "Cloud Out of Date" message after switching between the two Steam versions shouldn't come any more.

### Downloads and power
- **Your Mac stays awake while games download,** for all stores, also with the display off. The ring says whether the Mac stays awake or may sleep, and when you come back a line says how much was downloaded meanwhile.
- **Nightforge rests when nobody's there:** with no input it looks around less often, and Steam goes to sleep after 30 minutes when nothing needs it, also when plugged in. On battery it's enough that Nightforge hasn't been in front for that long. Steam wakes as soon as you come back.
- **Updates after waking:** when the Mac has been away for a while, Nightforge looks for what's new as it wakes, without admin rights and without waking the Mac for it. A game start always comes first.

### Known
- In Windows games the game hands out the player slots itself. Player 1 in the game can be the other controller.
- Signing in to Epic needs a keyboard once.
- Blizzard's Mac games stay on the internal disk, because Blizzard's Mac agent can't reach external drives.
- Still as before: online games with anti-cheat only run through GeForce Now in their Windows version, and DirectX 9 mostly runs through WineD3D, often slower and without MetalFX.

## B. Hängt am Live-Test

Diese Zeilen bleiben nur, wenn der Test sie bestätigt:

| Zeile | Was es braucht |
|---|---|
| Lizenz beim ersten Start | GTA V Enhanced, Abendliste L1–L4; „Abbrechen“ in Steams Fenster ist noch ungeprüft |
| Battle.net-Spiele starten | Hearthstone, `docs/LIVETEST-0.3.3.md` Block F; ob `launch WTCG` greift, ist nur statisch belegt |
| Weniger Ruckeln | Shader-Kurztest, Abendliste S1–S3; die Wirkung ist nicht gemessen, der Nutzer hat die Messung vertagt. Bis dahin vorsichtig formuliert. Braucht ein Grafik-Paket |
| Das Spiel steht, solange das Menü offen ist | Controller still im Windows-Spiel: braucht das neue `gamepad`-Paket (`winebus`-Patch), bis dahin wird angehalten wie bisher |
| A und B in Windows-Fragen | Binärprogramm aus `pad-answer.yml`, sonst bleibt A/B beim Spiel; live noch nie gelaufen |
| PS-Taste, Ein und Aus, Wecken | Block J und I; Schlafen ohne Admin-Abfrage und Wecken sind ungeprüft |
| Vibration | Ob der DualSense über Bluetooth vibriert, ist offen (A4) |
| Anmelden am Sofa | GOG bis zum Ende mit dem Handy, macOS-Firewall und Port |
| Valheim „Cloud Out of Date“ | Abendliste R7 |
| Nightforge ruht, Updates nach dem Aufwachen | Block H und Abendliste W1, W2; ob das Windows-Steam den Schlaf sperrt, ist offen |
| Fernseher | Abendliste T1–T5, 4K ist noch nie gelaufen |

Die Schritte bis `main` (Workflows, Manifeste, Signaturen) kommen aus der Gesamtprüfung in `docs/AUDIT-0.3.3.md`.
