# Entwurf: Was Windows-Programme vom Mac sehen (Laufwerk Z:)

Stand: 3.11.2026, auf `claude/ux-roadmap-next` 29e458a. Anlass ist Befund M2 aus `docs/AUDIT-SICHERHEIT.md`:
`Z:` zeigt auf `/`. Jedes Windows-Programm in Nightforges Prefix sieht damit den ganzen Mac, auch die Epic- und
GOG-Token unter `~/Library/Application Support/Nightforge`.

**Ergebnis in einem Satz:** `Z:` umzubauen schützt die Token nicht, kostet aber Sonderfälle und Startfehler. Eine
macOS-Sandbox mit Sperrliste um die Wine-Prozesse schützt sie wirklich, ohne einen Pfad zu ändern. Empfehlung:
`Z:` so lassen und die Sandbox als eigenen Schritt mit Live-Test bauen (unten „Empfehlung“).

## Was Wine 11.17 mit Laufwerken macht (winecx 4.7.3, aus dem Quelltext)

- **`z:` → `/` legt Wine nur beim ersten Anlegen von `dosdevices` an** (`dlls/ntdll/unix/server.c:1350–1355`).
  `wineboot` fasst `dosdevices` nicht an. `mountmgr` übernimmt bestehende Links nur (`dlls/mountmgr.sys/device.c:1077`).
  Ein umgebogenes `z:` bliebe also bestehen.
- **Ein Windows-Pfad zu einem Mac-Pfad** geht über den Link des Laufwerks (`Z:\a\b` → `dosdevices/z:/a/b`). Links
  innerhalb werden verfolgt.
- **Ein Mac-Pfad zu einem Windows-Pfad**, etwa für das Arbeitsverzeichnis beim Start
  (`dlls/ntdll/unix/env.c:1412–1447`): Wine geht den Pfad nach oben durch und vergleicht Gerät und Inode mit dem Ziel
  jedes Laufwerks (`dlls/ntdll/unix/file.c`, `find_drive_nt_root`). Passt keins, startet das Programm laut Quelltext
  in `C:\windows`. Im Versuch kam ein kaputtes `unix\private\…` heraus. Beides bricht Spiele, die ihr Arbeitsverzeichnis
  brauchen.
- **`\??\unix\`**: Windows-Programme erreichen jeden Mac-Pfad auch ohne Laufwerk, als `\\?\unix\Users\…`
  (`dlls/ntdll/unix/file.c:3733–3772`, `unix_prefixW` Zeile 250). Ein Laufwerk wegzunehmen hält also nur Programme
  auf, die Laufwerke durchsuchen (Dateidialoge, Launcher, Windows-Schadsoftware, die Buchstaben abklappert). Wer
  gezielt nach einer Datei greift, kommt hin. Ein Programm kann außerdem direkt Systemaufrufe machen, denn Wine ist
  keine Sandbox.
- **`mountmgr` vergibt Buchstaben nur an Wechselmedien** (`dlls/mountmgr.sys/diskarb.c:162–186`, `DAMediaRemovable`).
  Im Prefix des Nutzers ist `d:` → `/Volumes/Spiele` so entstanden. Feste externe SSDs bekommen keinen Buchstaben,
  Spiele dort erreicht Wine heute nur über `Z:`.

## Was Nightforge über Z: braucht

| Wofür | Ort | Pfad unter Z: |
|---|---|---|
| Steam-Bibliotheken auf Laufwerken (`libraryfolders.vdf`) | `ExternalDrives.swift:227–228`, `DriveMoves.swift:241`, `:330` | `Z:\Volumes\<Laufwerk>\Nightforge Games` |
| Epic- und GOG-Spiele außerhalb des Prefix | `Engine.windowsPath(of:)` `Engine.swift:190–196`, `Launcher.swift:587` | `Z:\Volumes\…` |
| Arbeitsverzeichnis bei Direktstarts (Mac-Pfad, Wine rechnet um) | `Launcher.swift:589`, `GOGStore.swift:745` | braucht ein Laufwerk über dem Ordner |
| Epics Besitz-Datei (`-epicovt=`) | `Legendary.swift:225–228` | `Z:\Users\<name>\Library\Application Support\Nightforge\Epic\legendary\tmp\…`, liegt neben `user.json` |
| GOG-Redistributables und Installer-Skript | `GOGRedist.swift:160–184`, `GOGRedist.folder` (`GOG/Redist`) | `Z:\Users\…\Nightforge\GOG\Redist\…` |
| GOGs `supportDir` | `GOGRedist.swift:183`, `GOGDL.supportDir` (`GOG/Support/<id>`) | `Z:\Users\…\Nightforge\GOG\Support\…`, neben `GOG/gogdl` mit dem Token |
| Wine Mono | `Engine.swift:1370` | `Z:\Users\…\Components\…\share\wine\mono\…` |
| Steam-Installer (Mac-Pfad aus dem Temp-Ordner) | `Setup.swift:369` | Wine rechnet `/var/folders/…` um |
| Nightforge liest Laufwerke selbst zurück | `Library.swift:605–663` (`missingVolume`, `macPath`) | folgt dem Link von `z:` |

Steam selbst, Epics und GOGs Standardordner und alle Spielstände liegen auf `C:` im Prefix. DXMT, D3DMetal, der
Vulkan-Layer und die Shader-Caches arbeiten auf der Mac-Seite mit Mac-Pfaden und brauchen kein Laufwerk.

## Was andere machen (aus Kenntnis, nicht am Gerät geprüft; hier gibt es keine Flaschen)

- **Wine:** `c:` und `z:` → `/`. Laut Wine-FAQ ist Wine keine Sandbox, und `Z:` zu entfernen schützt nicht wirklich.
- **CrossOver:** wie Wine, dazu `y:` → Home-Ordner.
- **Whisky:** wie Wine.
- **Proton** behält `z:` → `/`. Valve schränkt die Sicht stattdessen mit einem Container ein (pressure-vessel, Steam
  Linux Runtime): Abgegrenzt wird außen, nicht über Laufwerksbuchstaben.

## Versuche (3.11., eigener Prefix im Scratchpad, installiertes winecx 4.7.3 nur gelesen)

Nachbau: `tests/laufwerke/probe-zugriff.sh` mit `tests/laufwerke/readprobe.c`. Das Windows-Programm liest eine
„geheime“ und eine „offene“ Datei, einmal über `Z:` und einmal über `\\?\unix\`.

| Variante | geheim über `Z:` | geheim über `\\?\unix\` | offen über `Z:` | `Z:\` zeigt | Arbeitsverzeichnis |
|---|---|---|---|---|---|
| heute (`z:` → `/`) | gelesen | gelesen | gelesen | den ganzen Mac | richtig |
| **Sandbox** mit Sperre auf den geheimen Ordner | **gesperrt** | **gesperrt** | gelesen | den ganzen Mac | richtig |
| Sandbox, Kindprozess von `cmd.exe`, wineserver vorher ohne Sandbox gestartet | **gesperrt** | **gesperrt** | gelesen | – | – |
| `z:` auf einen Spiegel nur des offenen Ordners | nicht gefunden | **gelesen** | gelesen | nur den Spiegel | **kaputt** (`unix\…`) |

Die Sandbox ist `sandbox-exec` mit `(allow default)(deny file-read* file-write* (subpath …))`.
- Sie gilt auch unter Rosetta (x86_64) und für alles, was der gesperrte Prozess startet. Spiele sind Kinder von Steams
  Prozess.
- Es macht nichts, wenn der wineserver ohne Sandbox läuft: Wine öffnet Dateien im Programm selbst.

## Die Varianten

### A: `Z:` auf einen Spiegel-Ordner umbiegen (nicht empfohlen)

`z:` zeigt auf einen Ordner im Prefix, der nur freigegebene Orte enthält, als Links an ihrer echten Stelle (z. B.
`drive_z/Volumes/T7/Nightforge Games` → `/Volumes/T7/Nightforge Games`). Alle bisherigen `Z:\…`-Pfade dorthin
bleiben gleich, eine Umstellung bestehender Bibliotheken wäre nicht nötig.

Dagegen spricht:
- **Schützt die Token nicht.** `\\?\unix\` liest sie weiter (Versuch).
- **Ganz `/Volumes` freizugeben geht nicht.** `/Volumes/Macintosh HD` ist ein Link auf `/`. Dazu kämen Time-Machine-
  Backups und Netzfreigaben (hier „lexi“). Der Spiegel müsste jeden Spielordner einzeln führen und bei jedem neuen
  Laufwerk und jeder Bibliothek nachziehen. Das Laufwerk-Wählen in Steams eigener Oberfläche sähe nur diese Ordner.
- **Arbeitsverzeichnis.** Für Ordner, über denen kein Laufwerk liegt, wird es kaputt (Versuch). Feste externe SSDs
  bekommen von `mountmgr` keinen Buchstaben. Direktstarts von GOG- und Epic-Spielen dort bräuchten eigene Buchstaben
  je Spielordner, die Nightforge vergibt und gegen `mountmgr` verteidigt.
- **Sonderfälle**, jeder mit eigenem Weg:
  - Epics `legendary/tmp` liegt im Token-Ordner.
  - GOGs `Redist` und `Support` liegen neben `gogdl`.
  - Wine Mono und der Steam-Installer kommen von Mac-Pfaden außerhalb.
  - `Library.missingVolume` und `macPath` lesen das Ziel von `z:` mit.
- **Nicht live prüfbar ohne den Nutzer:** Steam mit externen Bibliotheken (die Laufwerksdaten von `Z:` ändern sich,
  denn `~/Library` liegt auf dem Datenvolume, `/` auf dem Systemvolume), GOG-Installer-Skripte, Epic-DRM.

Nutzen: Dateidialoge und Programme, die Laufwerke abklappern, sehen den Home-Ordner nicht mehr. Das ist echt, aber
klein, gemessen an Aufwand und Bruchgefahr.

### B: Sandbox mit Sperrliste um alle Wine-Prozesse (empfohlen)

Nightforge startet Wine über `/usr/bin/sandbox-exec -p <Profil> <wine> …`. Das Profil erlaubt alles außer einer
Sperrliste. Pfade und Laufwerke bleiben, wie sie sind, und es gibt nichts zu migrieren.

Gesperrt (lesen und schreiben):
- `~/Library/Application Support/Nightforge/Epic/legendary`, **außer** `…/legendary/tmp`, denn Epic-Spiele lesen dort
  ihre Besitz-Datei. Im SBPL-Profil gewinnt die spätere Regel: erst `deny`, dann `allow` für `tmp`.
- `~/Library/Application Support/Nightforge/GOG/gogdl` und die beiden `account.json`.
- Gängige Zugangsdaten, die macOS selbst nicht schützt: `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config`, `~/.netrc`,
  `~/Library/Keychains`, Browserprofile (`~/Library/Application Support/Google/Chrome`, `…/Firefox`,
  `…/BraveSoftware`, `…/Microsoft Edge`, `…/Arc`), `~/Library/Application Support/Claude`.
  Dokumente, Schreibtisch, Downloads, Mail, Nachrichten und Safari schützt macOS (TCC) schon.

Nicht gesperrt:
- Steams eigene Anmeldedaten im Prefix. Steam braucht sie, und die Spiele laufen unter Steam, wie unter Windows auch.

Wo umhüllen, an den Stellen, die Wine starten:
- `Engine.startSteam` (`Engine.swift:2256`). Die Spiele erben davon.
- `Launcher.swift:535`: Übergabe an Steam, die selbst Steam wird, wenn keins läuft.
- `Launcher.swift:585`: Direktstarts von GOG und Epic.
- `Engine.run` (`:1879`): Installer.
- Wine Mono (`:1369`), `regedit` (`:1646`), das winetricks-Skript (`:1445`).
- `GOGRedist.runWindows` (`GOGRedist.swift:323`).

Am besten zentral: eine Funktion, die aus `wine` + Argumenten `sandbox-exec` + Profil + `wine` + Argumenten macht, mit
einem internen Ausschalter für die Fehlersuche. Spätere Kinder (Spiele, Steams Helfer, Installer) erben die Sperre.
Ein Browser, den `winebrowser` öffnet, startet über LaunchServices und ist frei.

Risiken, die ein Live-Test klären muss:
- `sandbox-exec` gilt bei Apple als veraltet. In macOS 27 läuft es (Versuch), Apple könnte es aber entfernen.
  Dann startet Nightforge ohne Sandbox wie heute; das muss der Ausschalter abdecken.
- Game Mode: Startet der Loader aus „Nightforge Game.app“ unter `sandbox-exec` noch als dieses Bundle (Game Mode, Dock,
  Mitteilungen)?
- Steams CEF, Steam Overlay, Controller (winebus/SDL), MetalFX und D3DMetal unter der Sandbox.
- Ein Epic-Spiel mit DRM (Besitz-Datei aus `legendary/tmp`) und ein GOG-Installer-Skript.

Tests ohne den Nutzer:
- Das Profil aus der App mit Einheitstests prüfen: Pfade richtig, `tmp` erlaubt, Anführungszeichen in Pfaden.
- `probe-zugriff.sh` mit dem echten Profil im Scratch-Prefix laufen lassen.

### C: beides

Erst B. A danach nur, wenn Dateidialoge oder Launcher, die den Home-Ordner zeigen, wirklich stören. Ist B einmal da,
kann A auch kleiner ausfallen: `Z:` bliebe, nur die Sperrliste wüchse.

## Empfehlung

1. **`Z:` jetzt nicht umbauen.** Gegen gezielten Zugriff hilft es nicht (`\\?\unix\`). Es braucht pro Laufwerk und
   Bibliothek eigene Pflege und bricht Direktstarts von festen externen SSDs. Eine Umstellung bestehender
   Installationen wäre zwar nicht nötig, aber der Umbau ist ohne Live-Test mit Steam-Bibliotheken auf Laufwerken zu
   riskant.
2. **Die Sandbox mit Sperrliste (B) als nächsten Schritt bauen,** auf eigenem Zweig, mit einem Schalter, der zuerst
   aus steht. Danach ein Live-Test mit dem Nutzer: ein Steam-Spiel, ein Spiel von einem externen Laufwerk, ein
   Epic-Spiel mit DRM, ein GOG-Spiel mit Installer, Controller, Game Mode. Erst dann standardmäßig an.
3. Den Satz „Windows-Spiele sehen den ganzen Mac“ bis dahin ehrlich in die Doku: Wine ist keine Sandbox.

## Wer schreibt was im Datenordner (3.11., aus dem Code von Staging 4f0d00a)

Alles unter `~/Library/Application Support/Nightforge` außer `Prefix/`. „Außen“ heißt: Nightforge selbst oder seine
Mac-Werkzeuge legendary und gogdl, die nie in der Sandbox laufen. „Innen“ heißt: Wine oder ein Windows-Programm. Was nur
außen geschrieben wird, ist in der Sandbox nur lesbar (`WineSandbox.readOnlyInSupport`) oder ganz gesperrt
(`deniedInSupport`).

| Datei oder Ordner | Wer schreibt | In der Sandbox |
|---|---|---|
| `Components/` (Engines, Grafik, legendary, gogdl, winetricks, Komponentenliste mit `.sig`) | Nightforge (ComponentStore) | nur lesbar |
| `D3DMetal/`, `Nightforge Helper.app`, `hide-steam-dock.dylib` | Nightforge | nur lesbar |
| `steam-shutdown.sh`, `steam-priority.sh`, `steam-priority.pid` | Nightforge, die PID das Skript (läuft außen) | nur lesbar |
| `profiles.json(.sig)`, `agw.json(.sig)`, `launchoptions-written.json` | Nightforge | nur lesbar |
| `shortcut-key` | Nightforge (GameShortcut) | gesperrt |
| `Epic/legendary/` (Anmeldung, Metadaten, `assets.json`, `installed.json`) | legendary (außen) | gesperrt |
| `Epic/legendary/tmp/` (Besitz-Token der Spiele, `.resume`) | legendary; Epic-Spiele lesen | les- und schreibbar (Ausnahme) |
| `Epic/account.json` | Nightforge | gesperrt |
| `Epic/library.json`, `sizes.json`, `downloads.json`, `destinations.json`, `playtime.json` | Nightforge (EpicStore) | nur lesbar |
| `Epic/Logs/` | legendarys Ausgabe, von Nightforge geöffnet | nur lesbar |
| `GOG/gogdl/`, `GOG/account.json` | gogdl, Nightforge | gesperrt |
| `GOG/library.json`, `sizes.json`, `builds.json`, `downloads.json`, `installed.json`, `releases.json`, `playtime.json`, `saves.json`, `mac-unfit.json` | Nightforge (GOGStore) | nur lesbar |
| `GOG/Logs/` (`<id>.log`, `redist.log`, `auth.log`) | gogdl und Nightforge; Wines Ausgabe über einen außen geöffneten Handle | nur lesbar |
| `GOG/Games/` (Mac-Spiele) | gogdl | nur lesbar |
| `GOG/Redist/` | gogdl lädt; Wine führt die Installer von dort aus | **schreibbar**, Live-Test J |
| `GOG/Support/<id>/` | gogdl; GOGs Installationsskripte in Wine (`/supportDir=`) | **schreibbar**, Live-Test J |
| `GameInfo/known.json` | Nightforge (GameInfoStore) | nur lesbar |
| `GameTests/` | Nightforge (Spieletest, `sample` läuft außen) | nur lesbar |
| `Backups/` | Nightforge (SaveTransfer) | nur lesbar |
| `Logs/` (`wine.log`, `winetricks.log` und die `.previous`) | Nightforge; Wine und winetricks über Handles, die der Helfer außen öffnet | nur lesbar |
| `Steam packages/` | Nightforge (SteamPrefetch), danach als Hardlinks in Steams Paketordner im Prefix | nur lesbar |
| `Prefix/` (samt `gog-redist.json`) | Wine, Steam, Spiele, Installer | schreibbar |

Außerhalb des Datenordners schreibt DXMT seinen Shader-Cache nach `~/Library/Caches/Nightforge/dxmt`. Das muss in
der Sandbox schreibbar bleiben.
