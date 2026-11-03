<!-- Entwurf für die Release Notes von 0.3.1, Stand claude/staging-031 bis Runde 8 (d3269e3), 3.11.2026.
     Für das Release kommt der Text nach docs/release-notes/v0.3.1.md, dort setzt release.yml ihn vor den
     Installationstext. Diese Datei kam mit claude/stable-codesign (Staging f068346) und hat nur den Absatz zur Frage
     nach dem Laufwerk; der steht hier unter „Bekannt“. Erscheint 0.3.1 ohne die feste Signatur, diesen Punkt streichen.
     Nicht erwähnt, weil hinter einem Schalter, der aus ist: Wine-Sandbox, DXVK für DirectX 9, Unitys „Play!“-Helfer. -->

## Deutsch

Nightforge 0.3.1 macht 0.3.0 runder: Mehr Windows-Spiele starten gleich auf dem richtigen Weg, Nightforge hängt seltener und lässt sich immer beenden, und Updates kommen nur noch signiert vom Entwickler. Das Wichtigste:

**Voraussetzung** wie bei 0.3.0: ein Mac mit Apple silicon und macOS 26 (Tahoe) oder neuer.

### Spiele
- **Control** von Epic (und GOG) startet jetzt sein eigenes DirectX-12-Programm über D3DMetal. Bisher startete Epic die DirectX-11-Fassung, und die stürzte gleich ab.
- **DirectX 11 zuerst:** Spiele, die neben DirectX 11 auch Microsofts DirectX-12-Dateien mitbringen, galten bisher als reine DirectX-12-Spiele und liefen nur über D3DMetal. Jetzt versucht Nightforge zuerst DXMT. Unreal-4-Spiele wie ABZU laufen über DXMT mit DirectX 11, ABZU im Test auf einem M5 mit rund 57 FPS. Ältere Unreal-Spiele wie ABZU gehen jetzt auch im Vollbild in der Auflösung des Bildschirms auf.
- **D3DMetal für DirectX 11:** Jedes DirectX-11-Spiel probiert D3DMetal jetzt als letzten Weg, und in den Optionen kannst du es selbst wählen.
- **Epic-Spiele starten mit ihrem Spielprofil**, Sonic Mania zum Beispiel gleich im Vollbild.
- **Ton und Stabilität:** Ein Zusatz zur Engine mischt 5.1- und 7.1-Ton richtig herunter und behebt einen Fehler, bei dem das Ende eines Threads eine andere Datei des Spiels schließen konnte.
- **Programm wählen:** Bringt ein Spiel mehrere Programme mit, wählst du in seinen Optionen unter „Programm“, welches startet. Das geht auch bei Steam-Spielen, über Steams eigene Startoptionen.
- **Was andere berichten:** Die Spielseite zeigt, wie das Spiel laut AppleGamingWiki auf dem Mac läuft, je Weg, mit Links zu AppleGamingWiki, CodeWeavers und MacGamingDB. Beim ersten Start nimmt Nightforge diesen Hinweis mit.
- **Willkommen zurück** fragt jetzt „Lief gut“, „Mit Problemen“ oder „Startet nicht“. Bei „Startet nicht“ nimmt Nightforge beim nächsten Start den nächsten Weg.
- **Bericht teilen:** Nach dem Spiel kannst du mit „Bericht teilen …“ auf GitHub erzählen, wie es lief. Der Bericht ist öffentlich, und nichts geht weg, bevor du ihn dort selbst absendest.

### Starten und Beenden
- **Beenden geht immer:** ⌘Q, das Dock und das Menü beenden Nightforge jetzt auch, wenn gerade ein Dialog offen ist oder ein Fenster auf eine Datei wartet.
- **Weniger Hänger:** Nightforge wartet auf kein Hilfsprogramm mehr unbegrenzt. Antwortet die Prozessliste von macOS nicht, stockt Nightforge höchstens kurz, statt hängen zu bleiben, und hält ein Spiel auch nicht für beendet, nur weil die Liste fehlt. „Komplett entfernen“ bleibt nicht mehr stehen.
- **Steam geht schneller aus:** Nach dem Beenden von Nightforge schließt Steam sofort. Die 30 Sekunden für Cloud-Speicherstände wartet es nur noch, wenn in den letzten fünf Minuten ein Spiel lief oder gestartet wurde.
- **Spiele, die ein Starter nur mit ihrem Namen aufruft**, etwa Control über Epic, erkennt Nightforge jetzt als laufend. Ladebildschirm, Controller-Menü (L3 + R3) und Beenden arbeiten dann wie bei anderen Spielen.
- **Rückfall auf die vorige Engine** auch dann, wenn Steam auf einer neuen Engine nicht hochkommt, nicht nur bei Spielen, die sofort enden. „Läuft mit der vorigen Engine vom …“ nennt jetzt den richtigen Tag.

### Ladebildschirm
- **Fragen von macOS bleiben sichtbar:** Fragt macOS beim Start um Erlaubnis, etwa für ein externes Laufwerk, legt sich der Ladebildschirm darunter und sagt: „macOS fragt um Erlaubnis – antworte mit Maus oder Trackpad.“ Bisher lag die Frage verdeckt dahinter.
- **Steams Fragen:** Steams Fenster kommt wie bisher nach 3 Sekunden. Nightforge bittet dich aber erst dazu, wenn die Frage 5 Sekunden später noch steht. Die meisten erledigen sich vorher von selbst. Nach deiner Antwort schließt Steams Fenster, und der Ladebildschirm kommt zurück.
- Bei **„Startet nicht?“** ist die sichere Antwort vom ersten Moment an markiert, so zählt schon der erste Druck auf dem Controller.
- **Ein Ladebildschirm für den ganzen Start**, auch wenn Nightforge nacheinander mehrere Wege probiert. Kein Wechsel mehr zwischen Ladebildschirm und Nightforge dazwischen.
- Mit dem Controller bleibt der **Mauszeiger** versteckt, auch bei langen Starts und wenn Steam kurz nach vorne kommt.
- Nach dem Spiel erscheint gleich die Spielseite, nicht kurz Nightforge davor.
- Unreals Treiber-Warnung, etwa beim Wukong-Benchmark, kommt nicht mehr dazwischen.
- Steams Symbol steht nicht mehr mehrfach in der Menüleiste.

### Downloads und Updates
- **„Aktualisieren & spielen“** zeigt jetzt Fortschritt, Tempo und Restzeit. Bisher stand es bis zum Ende auf 0 %.
- Die **Speicherprüfung** rechnet laufende Downloads mit dem Platz, den sie ausgepackt brauchen, nicht mit ihrer kleineren Downloadgröße.
- Die Speicheranzeige zählt die aufgehobene vorige Engine nicht mehr doppelt. Unter Einstellungen › Speicher verlieren die Spiele eines externen Laufwerks ihre Zeilen nicht mehr, und kein Abschnitt steht doppelt.
- Der **Installationsbefehl** ersetzt eine vorhandene Nightforge dort, wo sie liegt (im Ordner „Programme“ des Macs oder in dem in deinem Benutzerordner), statt eine zweite Kopie anzulegen.
- Ein gerade installiertes Spiel steht nicht mehr als „gerade eben gespielt“ in der Bibliothek.
- Mit Fernseher oder zweitem Bildschirm steht unter „Spielen“, wo das Spiel aufgeht: „Spielt auf: …“.

### Sicherheit
- **Signierte Updates:** Ab 0.3.1 installiert Nightforge nur Updates, die mit dem Schlüssel des Entwicklers signiert sind (Ed25519). Dasselbe gilt für die Listen, die Nightforge online lädt (Spielprofile, Komponenten, AppleGamingWiki), und für den Installationsbefehl im Terminal. Fehlt die Signatur, bleibt die zuletzt geprüfte Liste.
- **D3DMetal-Import:** Nightforge übernimmt Apples Windows-Dateien nur, wenn ihre Prüfsummen zu Apples Toolkit passen, und importiert nichts mehr ungefragt aus „Downloads“.
- **Problembericht:** Der Link zu GitHub enthält nur noch feste Angaben (Spiel, Versionen, Mac, was Nightforge erkannt und versucht hat). Fehlerzeilen kommen in die Zwischenablage, du entscheidest, ob du sie einfügst. Geschwärzt werden jetzt auch Laufwerks- und Rechnernamen und GOG-Kennungen.
- **Links:** Ein `nightforge://play`-Link von einer Webseite startet kein Spiel mehr, er zeigt die Spielseite. Direkt starten nur Nightforges eigene Spiel-Apps.
- **Spielprofile dürfen weniger:** Sie schreiben nicht über Verknüpfungen aus ihrem Ordner hinaus, Spielstand-Regeln nie in einen ganzen Ordner wie „Dokumente“, und aus umu-protonfixes kommen nur einfache DLL-Einstellungen und Startargumente. In Steams Startoptionen ändert Nightforge nur seine eigene Zeile und legt vorher eine Kopie an.
- Nicht mehr benutzte Komponenten löscht Nightforge nur nach einer signierten Liste.

### Bekannt
- **Nach diesem Update fragt macOS ein letztes Mal nach dem Laufwerk.** Nightforge hat ab 0.3.1 eine feste eigene Signatur, an der macOS die App über Updates hinweg wiedererkennt. Deshalb fragt macOS nach diesem Update **noch einmal** nach dem Zugriff auf ein externes Laufwerk (und, falls du sie erlaubt hattest, nach Bedienungshilfen oder Automation). Bitte erlauben: Danach behält macOS deine Antwort bei jedem weiteren Update.
- **Overwatch startet noch nicht.** Nightforge sagt das am Spiel mit „Startet noch nicht“.
- **Unity-Spiele mit eigenem Startfenster:** Manche zeigen vor dem Spiel ein Fenster für Auflösung und Grafik. Dort einmal auf „Play!“ klicken, dann geht es weiter.
- Spiel-Apps aus 0.3.0 (in „Nightforge Games“) zeigen einmal die Spielseite statt zu starten, wenn ihr erster Klick nach dem Update Nightforge erst öffnet. Eigene Kurzbefehle mit `nightforge://play`-Links zeigen immer die Spielseite.
- Weiter wie bei 0.3.0: Online-Spiele mit Anti-Cheat laufen in ihrer Windows-Version nur über GeForce Now, DirectX 9 läuft über WineD3D oft langsamer und ohne MetalFX, Anmelden und Suchen brauchen noch eine Tastatur. Rund um den Ladebildschirm kann noch ein kleiner Anzeigefehler auftauchen.

---

## English

Nightforge 0.3.1 rounds off 0.3.0: more Windows games start the right way straight away, Nightforge hangs less and always quits, and updates only come signed by the maintainer. The main changes:

**Requirements** as for 0.3.0: a Mac with Apple silicon and macOS 26 (Tahoe) or later.

### Games
- **Control** from Epic (and GOG) now starts its own DirectX 12 program through D3DMetal. Until now Epic started the DirectX 11 build, which crashed right away.
- **DirectX 11 first:** games that bring Microsoft's DirectX 12 files along with DirectX 11 used to count as DirectX 12 only and ran through D3DMetal alone. Now Nightforge tries DXMT first. Unreal 4 games like ABZU run through DXMT with DirectX 11; ABZU at around 57 FPS in our test on an M5. Older Unreal games like ABZU now also open full screen at the screen's resolution.
- **D3DMetal for DirectX 11:** every DirectX 11 game now tries D3DMetal as its last way, and you can pick it yourself in the options.
- **Epic games start with their game profile**, Sonic Mania for one straight in full screen.
- **Sound and stability:** an addition to the engine mixes 5.1 and 7.1 sound down correctly and fixes a bug where a thread ending could close another file of the game.
- **Pick the program:** when a game comes with more than one program, its options let you choose under "Program" which one starts. That works for Steam games too, through Steam's own launch options.
- **What others report:** the game page shows how the game runs on a Mac according to AppleGamingWiki, per way, with links to AppleGamingWiki, CodeWeavers and MacGamingDB. Nightforge takes that hint into the first start.
- **Welcome back** now asks "Ran well", "With problems" or "Didn't start". With "Didn't start", Nightforge takes the next way at the next start.
- **Share a report:** after playing, "Share Report …" lets you tell how it ran on GitHub. The report is public, and nothing goes out until you submit it there yourself.

### Starting and quitting
- **Quitting always works:** ⌘Q, the Dock and the menu now quit Nightforge even while a dialog is open or a window waits for a file.
- **Fewer hangs:** Nightforge no longer waits on a helper program without a limit. When macOS's process list doesn't answer, Nightforge stalls for a moment at most instead of hanging, and doesn't take a game for ended just because the list is missing. "Remove completely" no longer gets stuck.
- **Steam closes sooner:** after you quit Nightforge, Steam closes at once. It only waits the 30 seconds for cloud saves when a game ran or was started in the last five minutes.
- **Games a launcher starts by their bare name**, like Control through Epic, now count as running. The loading screen, the controller menu (L3 + R3) and quitting then work as with other games.
- **Back to the previous engine** also when Steam doesn't come up on a new engine, not only when games end right away. "Runs with the previous engine from …" now names the right day.

### Loading screen
- **macOS's questions stay in view:** when macOS asks for permission at a start, say for an external drive, the loading screen moves under it and says "macOS is asking for permission – answer it with the mouse or trackpad." Until now the question lay hidden behind it.
- **Steam's questions:** Steam's window still comes after 3 seconds, but Nightforge only asks you to step in when the question is still there 5 seconds later. Most go away by themselves before that. Once you've answered, Steam's window closes and the loading screen comes back.
- On **"Not starting?"** the safe answer is highlighted from the first moment, so the first press on the controller already counts.
- **One loading screen for the whole start**, even when Nightforge tries several ways one after the other. No more switching between the loading screen and Nightforge in between.
- With a controller, the **mouse pointer** stays hidden, also through long starts and when Steam comes forward for a moment.
- After a game, its page shows straight away, without Nightforge flashing up first.
- Unreal's driver warning, as in the Wukong benchmark, no longer gets in the way.
- Steam's icon no longer shows up several times in the menu bar.

### Downloads and updates
- **"Update & Play"** now shows progress, speed and time left. Until now it stood at 0 % until the end.
- The **space check** counts running downloads at the space they take unpacked, not at their smaller download size.
- The storage view no longer counts the kept previous engine twice. In Settings › Storage, an external drive's games no longer lose their rows, and no section shows twice.
- The **install command** replaces an existing Nightforge where it is (in /Applications or ~/Applications) instead of adding a second copy.
- A game you just installed no longer shows up as "played just now" in the library.
- With a TV or a second screen, the line under Play says where the game opens: "Plays on: …".

### Security
- **Signed updates:** from 0.3.1 on, Nightforge only installs updates signed with the maintainer's key (Ed25519). The same goes for the lists Nightforge loads online (game profiles, components, AppleGamingWiki) and for the install command in Terminal. Without a signature, the last checked list stays.
- **D3DMetal import:** Nightforge takes Apple's Windows files only when their checksums match Apple's toolkit, and no longer imports anything from "Downloads" without asking.
- **Problem reports:** the link to GitHub now holds only fixed facts (game, versions, Mac, what Nightforge detected and tried). Error lines go to the clipboard, and you decide whether to paste them. Drive and computer names and GOG ids are now hidden too.
- **Links:** a `nightforge://play` link from a web page no longer starts a game; it shows the game's page. Only Nightforge's own game apps start a game directly.
- **Game profiles may do less:** they don't write through links out of their folder, save rules never name a whole folder like "Documents", and from umu-protonfixes only plain DLL settings and launch arguments come through. In Steam's launch options Nightforge only changes its own line, and keeps a copy first.
- Nightforge removes unused components only after a signed list says so.

### Known
- **After this update macOS asks about your drive one last time.** From 0.3.1 on, Nightforge carries a fixed signature of its own, by which macOS recognises the app across updates. So after this update macOS asks **once more** for access to an external drive (and, if you had allowed them, for Accessibility or Automation). Please allow it: from then on macOS keeps your answer through every update.
- **Overwatch doesn't start yet.** Nightforge says so on the game with "Doesn't start yet".
- **Unity games with their own start window:** some show a window for resolution and graphics before the game. Click "Play!" there once and it goes on.
- Game apps from 0.3.0 (in "Nightforge Games") show the game's page once instead of starting it, when their first click after the update has to open Nightforge first. Your own shortcuts with `nightforge://play` links always show the game's page.
- Still as in 0.3.0: online games with anti-cheat only run through GeForce Now in their Windows version, DirectX 9 runs through WineD3D, often slower and without MetalFX, and signing in and searching still need a keyboard. A small display glitch can still show up around the loading screen.
