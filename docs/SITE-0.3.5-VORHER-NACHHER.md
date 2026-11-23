# Landingpage und README für 0.3.5: Vorher/Nachher

Stand 23.11.2026, Zweig `claude/site-035` (von `claude/staging-035`, 5f8ec320). Nichts davon ist online. Du entscheidest je Zeile
vor dem Release; was du nicht willst, nehme ich wieder heraus. Grundlage der Aussagen: `docs/release-notes/v0.3.5.md`.
Design, Bilder und Aufbau sind unverändert, es sind nur Texte.

Spalte „Stand“: **gebaut** heißt im Release-Stand und gemessen; **[offen]** heißt gebaut, aber die Prüfung live steht noch aus
(Abnahme heute Abend). Bleibt ein [offen]-Punkt in der Abnahme hängen, fliegt der Satz vor dem Release wieder heraus.

**Freigabe des Nutzers, 23.11.2026 abends (nach der Abnahme):** Den Rest der Texte hat er freigegeben, mit zwei Änderungen. Erstens bekommt Zeile 1 eine neue Fassung, ohne Sekundenzahl und mit einer bescheidenen Überschrift: „0.3.5: Konsolenmodus“ / „Verbindest du einen Controller, fragt Nightforge einmal nach dem Konsolenmodus. Dann füllt es den Bildschirm, und das Dock bleibt beim Spielen weg. Während ein Spiel lädt, läuft ein Licht die Naht im Nightforge-Logo entlang. Steam startet gleich beim Öffnen von Nightforge im Hintergrund, so wartest du beim ersten Spiel weniger. Dazu kommt die 60-FPS-Grenze auch bei D3DMetal.“ Die Zahl stimmt nicht immer: Auf Akku brauchte Steam am 23.11. oft 15–25 s. Zweitens fällt der Satz, nach dem der Mauszeiger verschwindet, bis man die Maus wieder bewegt, auf der Landingpage und in der README weg, weil der Zeiger noch zwischendurch aufblitzt. Die Tabellen unten zeigen den Entwurf davor.

## Landingpage (`site/index.html`)

| # | Stelle | Vorher | Nachher | Stand |
|---|---|---|---|---|
| 1 | Zeitleiste, neuer Eintrag (0.3.4 verliert dafür die Markierung „jetzt“) | – | **DE:** „0.3.5: Konsolenmodus und ein schnelleres Steam. Steam startet eine Sekunde nach dem Öffnen von Nightforge und meldet sich auf einem MacBook Pro mit M5 Pro nach 5–6 statt 25 Sekunden an. Dazu kommen ein ruhiger Ladebildschirm, der Konsolenmodus, sobald du einen Controller verbindest, und die 60-FPS-Grenze auch bei D3DMetal.“ **EN:** „0.3.5: Console mode and a quicker Steam. Steam starts one second after Nightforge opens and, on a MacBook Pro with M5 Pro, signs in after 5–6 seconds instead of 25. There's also a calm loading screen, console mode as soon as you connect a controller, and the 60 FPS limit on D3DMetal too.“ | Steam-Start: gebaut. Anmeldung: gemessen auf dem MacBook Pro mit M5 Pro, [offen] auf anderen Macs und mit Kabel. Ladebildschirm, Konsolenmodus: [offen] live. D3DMetal: [offen] Wukong mit dem fertigen Stand |
| 2 | „So geht's“, Schritt 2 „Steam verbinden“ | DE: „… Du meldest dich nur in Steams eigenem Fenster an, deine Anmeldung sieht Nightforge nie.“ EN: „… so Nightforge never sees your login.“ | Satz angehängt. DE: „Danach startet Steam im Hintergrund, sobald Nightforge offen ist.“ EN: „After that, Steam starts in the background as soon as Nightforge is open.“ | gebaut |
| 3 | „Schön & flüssig“, Fußzeile der Grafik-Tafel | DE: „… schafft damit im Schnitt 68 FPS (Niedrig, FSR, 1512 × 982, M5, Nightforge 0.3). DirectX 9 läuft über …“ | Satz eingefügt. DE: „Seit 0.3.5 gilt die 60-FPS-Grenze auch dort.“ EN: „Since 0.3.5 the 60 FPS limit holds there too.“ | [offen] Wukong 60 FPS mit dem fertigen Stand |
| 4 | Controller, Spalte „Am Fernseher“, Anfang | DE: „Am Fernseher starten Spiele im Vollbild …“ EN: „On a TV, games start full screen …“ | Davor gesetzt. DE: „Verbindest du einen Controller, fragt Nightforge einmal nach dem Konsolenmodus. Dann füllt es den Bildschirm, auch am Fernseher, und das Dock bleibt auch beim Spielen weg.“ EN: „When you connect a controller, Nightforge asks once about console mode. It then fills the screen, a TV too, and the Dock stays away while you play.“ | [offen] Konsolenmodus am Spiel, live |
| 5 | Controller, Spalte „Am Fernseher“, Ende | DE: „… und ein Ladebildschirm überbrückt das Warten.“ EN: „… and a loading screen covers the wait.“ | DE: „… und während ein Spiel lädt, läuft ein Licht die Naht im Nightforge-Logo entlang.“ EN: „… and while a game loads, a light runs along the seam in the Nightforge logo.“ | [offen] Lichtnaht live |

Bewusst **nicht** geändert, zur Entscheidung:
- **Bekannte Punkte, „Ladebildschirm“** („ein Mauszeiger, der kurz aufblitzt, oder ein Fenster, das kurz davor auftaucht“): Die
  Release-Notizen behaupten nicht, dass das behoben ist. Zeigt die Abnahme heute Abend keinen davon mehr, kann der Punkt weg.
- **Versionszeile beim Download** (Version 0.3.4, 12,2 MB): `main.js` holt Version und Größe beim Laden von GitHub. Die feste
  Zeile ist nur der Rückfall, sie wird mit der echten DMG-Größe nach dem Bau des Release gesetzt, wie bei #51.
- **Datum in der Zeitleiste**: 23. Nov. ist angenommen; am Tag des Release anpassen.
- **„Was als Nächstes kommt“**: unverändert. Das Overlay aus 0.4 steht dort nicht, weil es noch nicht gebaut ist.
- Die Zeitleiste zählt drei Neuerungen auf, wie der Eintrag zu 0.3.4. Das ist eine Liste, kein Dreiklang als Stilmittel; wenn du
  es kürzer willst: „Dazu kommen der Konsolenmodus und die 60-FPS-Grenze auch bei D3DMetal.“

## README (`README.md`)

| # | Stelle | Vorher | Nachher | Stand |
|---|---|---|---|---|
| 6 | „Sharp & smooth“ | „… an even frame rate that fits your display – 60 FPS on a 120 Hz screen.“ | „… – 60 FPS on a 120 Hz screen, since 0.3.5 on D3DMetal too.“ | [offen] Wukong 60 FPS mit dem fertigen Stand |
| 7 | „From the couch“, vor „On a TV …“ | – | „When you connect a controller, Nightforge asks once about console mode: it then fills the screen, a TV too, and the Dock stays away while you play.“ | [offen] Konsolenmodus am Spiel, live |
| 8 | „From the couch“ | „… and a loading screen covers the wait.“ | „… and while a game loads, a light runs along the seam in the Nightforge logo.“ | [offen] Lichtnaht live |
| 9 | Liste, „A start that repairs itself“ | „… and starts it once more; the loading screen only says what's happening.“ | „… and starts it once more.“ (Der Ladebildschirm zeigt seit 0.3.5 keine Schritte mehr, der Halbsatz stimmte nicht mehr.) | gebaut |
| 10 | „Install“, erster Start | „… while it installs, you can try out your controller.“ | Satz angehängt: „After that, Steam starts in the background as soon as Nightforge is open.“ | gebaut |

Auch im README unverändert: „Around the loading screen …“ unter „Good to know“, aus demselben Grund wie oben.

## Was nirgends steht

Keine Zahlen, die einen bestimmten Mac erkennbar machen; die Gerätebezeichnung „MacBook Pro mit M5 Pro“ steht so auch in den
Release-Notizen. Keine Namen, Konten oder Pfade. Neue Bildschirmfotos gibt es keine (die brauchen dich).
