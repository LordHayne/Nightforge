# Probe B: Steams Dialoge mit Tasten aus Wine (23.11.2026)

Gehört zu `docs/ENTWURF-STEAM-PAD.md`, Weg B. Frage: Nimmt ein Dialog des Windows-Steam (steamwebhelper unter Wine)
Esc und Tab an, wenn ein Programm in derselben Wine-Sitzung sie per `SendInput` schickt, ganz ohne die macOS-Erlaubnis
„Bedienungshilfen“? Wenn ja, können Ⓐ/Ⓑ und das Steuerkreuz Steams Fragen bedienen wie heute die Fragen der Spiele (G4).

**Vorbereitet von einem Worker, ausgeführt nur vom Koordinator, vor 16:30.**

## Was das Skript tut und was nie

- `steam-keys.c` kennt nur **Esc, Tab und Umschalt-Tab**. Enter, Leertaste und Klicks gibt es darin nicht. Damit kann
  nichts bestätigt, installiert, gekauft oder verstellt werden.
- `probe.sh` öffnet `steam://install/<Demo-ID>`. Das ist Steams Installationsfenster, das erst mit „Weiter“ bzw.
  „Installieren“ etwas tut. Das Skript schickt zweimal Tab, einmal Umschalt-Tab und dann Esc. Danach prüft es, dass das Fenster zu ist.
  Schließt SendInput es nicht, versucht es Esc per PostMessage.
- Keine Anmeldung, kein Spielstart, kein Steam-Neustart durch das Skript. Ausgegeben werden nur Fensternummern,
  Fensterklassen und Größen, keine Titel, keine Konten und keine Prozess-Argumente.
- Schutzprüfungen vorab: nicht ab 16:30, eine Wine-Sitzung von Nightforge mit laufendem Windows-Steam, nichts aus einem
  Spielordner läuft, mingw-w64 ist da (`/opt/homebrew/bin/x86_64-w64-mingw32-gcc`).

## Erster Lauf (23.11., 08:18–08:19, App 440) und was sich seitdem geändert hat

- Der Aufruf **kam bei Steam an**: console_log 08:18:59 `ExecCommandLine` und `ExecuteSteamURL: "steam://install/440"`.
  Das Skript sah danach nur kein neues *sichtbares* Fenster.
- Wahrscheinliche Gründe: Nightforge versteckt Steams Helfer-Apps unter seiner Oberfläche und holt sie erst vor einer
  eigenen Steam-Frage zurück (`SteamWindow.hide`/`.reveal`). Oder Steam zeigt die Frage in seinem Hauptfenster, das es mit
  `-silent` verborgen hält.
- Neu deshalb:
  - `list` zeigt auch verborgene Fenster (`visible=0/1`). Kleine neue Fenster werden einmal notiert.
  - Ein Hauptfenster, das von verborgen auf sichtbar wechselt, zählt als die Frage. Ob sie nach Esc weg ist, sieht dann
    nur das Auge (Ergebnis `exit 3`).
  - Der Aufruf von steam.exe läuft wie `Engine.startSteam`: mit Steams Startargumenten (`Engine.steamArguments`) und mit
    der Umgebung des laufenden Steam (gelesen wie `DockHider.startValue`). Ist die nicht lesbar, wird sie wie
    `Engine.environment(wine:)` nachgebaut: `DYLD_INSERT_LIBRARIES`, `NIGHTFORGE_LIBRARY`, `WINEDLLOVERRIDES` wie für
    Steam, `WINELOADER` im Spielmodus, Rosetta-Bibliothek. Das Protokoll sagt, welcher Weg genommen wurde.
  - Ist Wines Sandbox an, bricht die Probe ab: Ihr Profil baut nur Nightforge (auf diesem Mac ist sie aus).
  - Das Protokoll nennt `ExecCommandLine` und `ExecuteSteamURL` aus Steams console_log, mit Uhrzeit, ohne Argumente.

## Zweiter Lauf (23.11., 08:38) und die Betriebsarten ohne Befehl

Lauf 08:38: Die Umgebung kam vom laufenden Steam (88 Einträge), Programm Nightforge Game.app. Steam bekam
`steam://install/440` (ExecCommandLine, ExecuteSteamURL um 08:38:14), zeigte aber **kein Fenster**, auch kein kleines oder
verborgenes. Lesart: Im Hintergrundbetrieb unter Nightforge nimmt Steam den Befehl an und zeigt die Installationsfrage nicht.

Deshalb zwei Betriebsarten, die **nichts schicken außer den Tasten**. Sie sind für die Abnahme am Abend mit dem Nutzer gedacht, der
die Frage selbst auslöst, und deshalb auch ab 16:30 zulässig. Alle anderen Schutzregeln gelten weiter (Nightforges Sitzung, Windows-Steam
läuft, kein Spiel läuft, keine Sandbox).

| Aufruf | Tut |
|---|---|
| `probe.sh --warten [Sekunden]` | Merkt sich Steams Fenster, sagt „jetzt die Frage auslösen“ und wartet (Standard 180 s) auf ein neues Fenster ab 300×200 oder eines, das sichtbar wird. Dann wie oben: Tab, Tab, Umschalt-Tab, Esc. |
| `probe.sh --jetzt` | Für eine Frage, die schon steht: nimmt das **eine** sichtbare Steam-Fenster ab 300×200. Bei keinem oder mehreren schickt es nichts. |

Ablauf am Abend, zum Beispiel mit der Startoption von Drawful 2:
1. `bash docs/probes/steam-pad-keys/probe.sh --warten` starten.
2. In Nightforge Drawful 2 spielen. Steam fragt nach der Startoption.
3. Hinsehen, ob der Fokusrahmen bei Tab wandert. Esc bricht den Start ab, das ist Absicht; danach normal starten.
4. Ergebnis wie unten. Bleibt das Fenster mit der Frage stehen: mit der Maus „Abbrechen“, nicht „Spielen“.

Valheims Cloud-Frage geht genauso, nur dass Esc dort den Start ebenfalls abbricht.

## Ablauf

1. Steam von Nightforge läuft (nach dem Neustart durch den Koordinator), kein Spiel, kein Download.
2. Eine Demo wählen, die **nicht** installiert ist. Am besten eine, die schon in der Bibliothek liegt, sonst fragt Steam
   vielleicht erst nach einer Lizenz. Die Nummer steht in der Store-Adresse.
3. Im Terminal, aus dem Worktree:
   `bash docs/probes/steam-pad-keys/probe.sh <Demo-ID>`
   Das Protokoll geht nach `./steam-pad-probe-<Zeit>.log`, oder nach `PROBE_LOG=<Datei>`.
4. **Hinsehen**, solange das Skript „Jetzt hinsehen“ meldet (etwa 8 s): Wandert in Steams Fenster ein Fokusrahmen von Knopf
   zu Knopf? Das kann nur ein Mensch sehen.
5. Bleibt am Ende „Dialog noch offen“ stehen: das Fenster mit der Maus über **Abbrechen** schließen.

## Was im Protokoll stehen soll

```
… Sitzung erreicht; Umgebung vom laufenden Steam übernommen (… Einträge); Programm: …
  vorher: hwnd=0x… proc=steamwebhelper.exe class=… size=…x… visible=0 foreground=0
… Öffne Steams Installationsfenster für App <ID> (steam://install, nichts wird bestätigt)
… Der zweite steam.exe endete nach 1 s mit exit 0
  console_log …: ExecCommandLine mit steam://install/<ID>
  console_log …: ExecuteSteamURL mit steam://install/<ID>
  neu: hwnd=0x… proc=steamwebhelper.exe class=… size=…x… visible=1 foreground=…
… Jetzt hinsehen: …
… Tab 1 per SendInput: exit 0
… Tab 2 per SendInput: exit 0
… Umschalt-Tab per SendInput: exit 0
… Esc per SendInput: exit 0
… ERGEBNIS: Esc schließt Steams Dialog (SendInput). Fenster ist zu.
```

Was die Zeilen bedeuten:

| Zeile | Heißt |
|---|---|
| `ERGEBNIS: Esc schließt … (SendInput)` + Fokus wanderte | Weg B trägt. Ⓑ = Esc und Steuerkreuz = Tab sind baubar; Ⓐ = Enter erst nach einer zweiten Probe mit einem harmlosen Knopf. |
| `… (PostMessage)` | Tasten kommen nur direkt ans Fenster an; baubar, aber ohne Vordergrund-Wechsel. |
| `exit 4` bei Tab/Esc | Wine gab dem Fenster den Vordergrund nicht; dann zählt nur PostMessage. |
| `exit 3` | Das Fenster gehört nicht zu Steam (falsches Fenster gefunden), nichts geschickt. |
| `kein neues Steam-Fenster in 30 s` mit `ExecuteSteamURL` | Steam bekam den Link, zeigte aber kein Fenster, das Wine sieht. Die Zeilen `neu, klein:` ansehen; sonst auf den Bildschirm schauen, ob Steam etwas zeigt. |
| `kein neues Steam-Fenster` ohne `ExecuteSteamURL` | Der Aufruf kam nicht bei Steam an. Die Zeile „Umgebung …“ und den Exit des zweiten steam.exe ansehen. |
| `ERGEBNIS (nur per Auge)`, exit 3 | Die Frage stand in Steams Hauptfenster (oder bei `--jetzt` blieb das Fenster). Ob Esc sie schloss, sieht nur das Auge. |
| `… sichtbare Steam-Fenster ab 300×200, nichts geschickt` | `--jetzt` fand keines oder mehrere; `--warten` nehmen. |
| `Dialog noch offen` | Weg B trägt nicht für Esc; mit der Maus abbrechen. Ergebnis in den Entwurf. |

Ergebnis bitte in `docs/ENTWURF-STEAM-PAD.md`, Abschnitt 5, nachtragen: Klasse und Größe des Fensters, die Exit-Codes, ob der
Fokus sichtbar wanderte.
