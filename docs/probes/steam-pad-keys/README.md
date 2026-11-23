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
… Sitzung erreicht (WINEMSYNC=1)
  vorher: hwnd=0x… proc=steamwebhelper.exe class=… size=…x… foreground=0
… Öffne Steams Installationsfenster für App <ID> (steam://install, nichts wird bestätigt)
  neu: hwnd=0x… proc=steamwebhelper.exe class=… size=…x… foreground=…
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
| `kein neues Steam-Fenster in 30 s` | Demo schon installiert, oder Steam zeigt ein anderes Fenster; andere Demo wählen. |
| `Dialog noch offen` | Weg B trägt nicht für Esc; mit der Maus abbrechen. Ergebnis in den Entwurf. |

Ergebnis bitte in `docs/ENTWURF-STEAM-PAD.md`, Abschnitt 5, nachtragen: Klasse und Größe des Fensters, die Exit-Codes, ob der
Fokus sichtbar wanderte.
