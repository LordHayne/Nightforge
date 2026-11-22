# Live-Test: DirectX 9 über DXVK auf KosmicKrisp

Für den Nutzer am Mac, ohne Rückfrage machbar. Dauer: etwa 45 Minuten, plus Download des dritten Spiels.

**Worum es geht.** Der Code ist seit 0.3.1 in Nightforge, aber abgeschaltet, weil die Komponentenliste KosmicKrisp nicht
nennt (9a6157e). Grund war der Test vom 4.11. mit Mafia II: 46–60 FPS, aber Stopps von 3–7,7 s, dunkle Rechtecke im Bild,
GPU bei ~1 %, leerer Mesa-Cache. Dieser Test klärt, ob es so bleibt und ob es auch bei anderen Spielen so ist.

**Was der Test nicht anfasst:** Der Testbau entsteht neben dem installierten Nightforge. Dessen App bleibt unverändert.

## Vorbereitung (5 Minuten)

Installiertes Nightforge beenden, es läuft kein Spiel. Dann im Terminal, Zeile für Zeile:

```bash
cd /Users/thomas/Downloads/Nachtschicht/.claude/worktrees/quirky-clarke-81fd65
git switch claude/kosmickrisp-livetest
defaults delete io.github.lordhayne.nightforge vulkanLoader 2>/dev/null; true
./build.sh
bash tests/kosmickrisp/stage-live-test.sh "$HOME/Library/Application Support/Claude/side-session-notes/local_50379bcc-0f0e-4091-a00d-c844cb465b05/kosmickrisp/nightforge-kosmickrisp-27.0.0-devel-44989e5a.tar.gz"
open build/Nightforge.noindex/Nightforge.app
```

- Fehlt der Ordner, geht jeder andere Checkout des Zweigs: `git -C ~/Downloads/Nachtschicht worktree add
  .claude/worktrees/kosmickrisp-live claude/kosmickrisp-livetest`, dann dort weiter.
- Die `defaults`-Zeile schaltet den anderen Testweg (`vulkanLoader`) ab. Ist er an, weicht KosmicKrisp ihm.
- Fragt macOS, ob `codesign` den Schlüssel benutzen darf: „Immer erlauben“. Fragt es nach dem Ordner „Downloads“:
  erlauben, der Testbau liegt dort.
- Beim ersten Start lädt Nightforge DXVK 3.1.1 (18 MB) und legt dessen d3d9 in den Prefix. Steam startet einmal neu.
- Bei allen Spielen in den Optionen **Grafik auf „Automatisch“**. Es läuft kein zweites Windows-Spiel nebenher: Dann
  startet Steam nicht neu, DXVK findet kein Gerät und Nightforge fällt auf WineD3D zurück.

In einem zweiten Terminalfenster mitlesen:

```bash
tail -f "$HOME/Library/Application Support/Nightforge/Logs/wine.log" | grep --line-buffered -i -E "nightforge-vulkan|dxvk|kosmickrisp|err:"
```

**Läuft es über KosmicKrisp?** Im Log stehen `DXVK: v3.1.1` und `Found device: Apple M5 (KosmicKrisp …)`, dann alle 10 s
eine FPS-Zeile `[nightforge-vulkan] <spiel>.exe: … FPS`. Steht dort `No adapters found` oder
`Failed to create Vulkan device`, hat es nicht geklappt. Der nächste Start nimmt dann von selbst WineD3D. Das bitte
notieren, nicht reparieren.

Bei jedem Spiel darauf achten:

| Frage | Was zählt |
|---|---|
| Stopps | Standbilder ab 1 s: wie oft, wie lang, werden sie nach ein paar Minuten seltener? |
| Bild | Dunkle Rechtecke, fehlende Schatten oder Spiegelungen, falsche Farben, Menü |
| Bildrate | Die FPS-Zeilen, an der anstrengendsten Stelle |
| Ton | Knacken, Aussetzer, Echo |
| Stabilität | Läuft es 10 Minuten ohne Absturz? |
| Zweiter Start | Nach dem Beenden noch einmal starten: Sind die Stopps an derselben Stelle kürzer? |

## 1. Mafia II (GOG, auf „Games“, 15 Minuten)

Starten und in der Stadt fahren, dieselbe Strecke zweimal. Die Grafikeinstellungen im Spiel nicht ändern.

- Vergleichswerte: WineD3D am 31.10. 230–440 % CPU mit zwei vollen Threads und Knacken; KosmicKrisp am 4.11. siehe oben.
- CPU, während es läuft:

```bash
ps -Ao %cpu,comm | grep -i -E "mafia2|wineserver" | grep -v grep
```

- Welcher Thread voll läuft (nur bei Mafia II), aus dem Ordner des Zweigs:

```bash
python3 -I tests/kosmickrisp/thread-cpu.py $(pgrep -f -i mafia2.exe | head -1) 5
```

- Echo ist hier kein Maßstab: Es kommt bei Mafia II auch mit WineD3D, also nicht vom Grafikweg.

## 2. Left 4 Dead 2 (Steam, auf „Games“, 10 Minuten)

**Das Spiel hat VAC.** Deshalb nur **Einzelspieler** mit Bots, nicht online und auf keinem VAC-Server. Während des Spiels
**kein `winedbg`, kein `sample`, kein `lsof`, kein `thread-cpu.py`** und nichts am Spiel ändern. Beobachten nur über
`wine.log` und Augen.

- Steam startet vor dem Spiel einmal neu. Danach prüfen: Zeigt Steams Fenster normal an?
- Fragt macOS nach dem Mikrofon: „Erlauben“.
- Der Ton kann sehr leise sein (Cloud-Einstellung `volume 0.008`): im Spiel unter Optionen › Audio hochdrehen.
- Mindestens 10 Minuten spielen. Auf WineD3D gab es hier früher Abstürze nach etwa einer Minute.

## 3. The Stanley Parable (Epic, 10 Minuten)

Drittes DirectX-9-Spiel: Source-Engine wie Left 4 Dead 2, aber **ohne VAC**, und es geht über den Direktstart statt über
Steam. Vorher in Nightforge auf „Games“ installieren. Wer nicht laden will, nimmt **Sonic Mania** (Epic, 0,2 GB).

Gestartet, zehn Minuten gespielt, dieselben Fragen. Hier dürfen `ps` und `thread-cpu.py` mitlaufen.

## 4. Gegenprobe und Rückbau (5 Minuten)

Mit dem Testbau noch **Oxygen Train** (DXMT) starten. Erwartet: kein Steam-Neustart, läuft wie immer.

Dann den Testbau beenden und zurückbauen, aus dem Ordner des Zweigs:

```bash
bash tests/kosmickrisp/stage-live-test.sh --undo
open -a "$HOME/Applications/Nightforge.app"
```

Das installierte Nightforge setzt den Prefix beim nächsten Start selbst auf DXVK-macOS' d3d9 zurück. Danach läuft
Mafia II wieder auf WineD3D, ohne DXVK-Versuch.

## Ergebnis (an die Koordinator-Sitzung)

| Spiel | KosmicKrisp im Log? | FPS | Längste Stopps, 1. / 2. Start | Bildfehler | Ton | 10 min stabil? |
|---|---|---|---|---|---|---|
| Mafia II | | | | | | |
| Left 4 Dead 2 | | | | | | |
| The Stanley Parable | | | | | | |

**Entscheidung danach:**
- **Hält es** (keine Bildfehler, Stopps unter 1 s nach den ersten Minuten): `kosmickrisp` zurück in
  `components/sources.json` und die Profile 50130, `gog.1816059595` und 550 auf `graphics: dxvk`. Beides nur mit dem OK
  des Nutzers.
- **Hält es nicht:** Es bleibt aus, Mafia II bleibt auf WineD3D. Nächste Versuche, einzeln und mit Messung:
  der Mesa-Cache-Patch `scripts/kosmickrisp/proposed/0003` (der Cache war am 4.11. leer), ein neuerer Mesa-Stand, oder
  DXVK-macOS 1.10.3-async auf KosmicKrisp gegen die Pipeline-Stopps (das nicht bei Left 4 Dead 2).
