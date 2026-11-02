# Anfrage an MacGamingDB (Entwurf zum Abschicken)

Für: den Betreiber von MacGamingDB, auf GitHub **neo773** (https://github.com/neo773/macgamingdb).
Abschicken muss der Nutzer selbst, keine Session schreibt Dritte an.

**Wo:** Am freundlichsten als Discussion oder Issue im Repo `neo773/macgamingdb` (Titel siehe unten), oder an die
Kontaktadresse auf macgamingdb.app, falls dort eine steht. Englisch schicken; die deutsche Fassung ist zum Lesen.

Vor dem Abschicken: `[Name]` ersetzen. Wenn MacGamingDB Bedingungen nennt (Lizenz, Nennung, Abrufweg), bitte an
die koordinierende Session geben – dann bauen wir den Import so, wie es dort gewünscht ist.

---

## English (zum Abschicken)

**Title:** Permission to use MacGamingDB reports in Nightforge (free, open-source Mac launcher)

Hi neo773,

I'm [Name], and I maintain Nightforge (https://github.com/LordHayne/Nightforge), a free, open-source (GPL-3.0)
launcher for macOS. It runs Windows games from Steam, Epic and GOG on Apple silicon through Wine with DXMT,
D3DMetal and DXVK, and prefers native Mac versions. No ads, no paid features, no telemetry.

MacGamingDB is the most useful source we've found, because every report says which graphics backend was used.
That's exactly the question Nightforge has to answer when a game starts for the first time: DXMT, D3DMetal or
DXVK? Today it tries them one after another, and players see the failed starts.

Would you allow us to use the report data? What we have in mind:

- Read it once a night (an export file or your API, whichever you prefer, with an identifying User-Agent and any
  rate limit you set), and keep only per game: backend, rating, chip, software version and date.
- Use it to order the backends Nightforge tries first, and show a short summary on the game's page with a link back
  to the game on MacGamingDB and a clear credit. We already link every game page to MacGamingDB.
- Keep the data in its own file under the licence and attribution you choose, separate from our GPL code.
- Never resell it, put ads on it, or present it as our own.

If you'd like something back: Nightforge players can share how a game ran (opt-in, released under CC0). We'd be
happy to send those to MacGamingDB too, or link players to your report form.

If you'd rather not, that's completely fine – we'll keep just linking to you. Thanks for building MacGamingDB!

[Name]
Nightforge – https://github.com/LordHayne/Nightforge

---

## Deutsch (zum Lesen)

**Titel:** Erlaubnis, MacGamingDB-Berichte in Nightforge zu nutzen (freier, quelloffener Mac-Launcher)

Hallo neo773,

ich bin [Name] und betreue Nightforge (https://github.com/LordHayne/Nightforge), einen freien, quelloffenen
Launcher für macOS (GPL-3.0). Er startet Windows-Spiele von Steam, Epic und GOG auf Apple-Silicon-Macs über Wine mit
DXMT, D3DMetal und DXVK und nimmt native Mac-Versionen, wo es sie gibt. Keine Werbung, keine Bezahlfunktionen,
keine Telemetrie.

MacGamingDB ist die nützlichste Quelle, die wir gefunden haben, weil jeder Bericht sagt, welcher Grafikweg lief.
Genau das muss Nightforge beim ersten Start eines Spiels entscheiden: DXMT, D3DMetal oder DXVK? Heute probiert es
die Wege nacheinander, und die Spieler sehen die Fehlstarts.

Dürfen wir die Berichtsdaten nutzen? So stellen wir es uns vor:

- Einmal pro Nacht abrufen (Export-Datei oder API, wie es dir lieber ist, mit eigenem User-Agent und jedem
  Limit, das du vorgibst) und je Spiel nur behalten: Grafikweg, Bewertung, Chip, Softwareversion, Datum.
- Damit die Reihenfolge festlegen, in der Nightforge die Grafikwege probiert, und auf der Spielseite eine kurze
  Zusammenfassung zeigen, mit Link zum Spiel auf MacGamingDB und klarer Nennung. Jede Spielseite verlinkt
  MacGamingDB schon heute.
- Die Daten in einer eigenen Datei halten, unter der Lizenz und Nennung, die du wählst, getrennt von unserem GPL-Code.
- Sie nie weiterverkaufen, nicht mit Werbung versehen und nicht als unsere ausgeben.

Wenn du etwas zurück möchtest: Nightforge-Spieler können teilen, wie ein Spiel lief (freiwillig, unter CC0). Die
schicken wir gern auch an MacGamingDB, oder wir verweisen auf dein Formular.

Wenn du lieber nicht möchtest, ist das völlig in Ordnung – dann bleibt es beim Verlinken. Danke für MacGamingDB!

[Name]
Nightforge – https://github.com/LordHayne/Nightforge
