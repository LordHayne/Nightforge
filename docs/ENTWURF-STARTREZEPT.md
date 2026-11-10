# Entwurf: Startrezept und Lernkreislauf

Stand 10.11.2026, Entwurf, nichts davon gebaut. Auslöser: der Nutzer, 10.11.: „Wie können wir den Startvorgang
komplett automatisieren, damit wir nicht jedes Game testen müssen? Mir kommt es so vor, als ob die einzelnen
Bauteile nicht richtig vernetzt sind.“

Ziel: Ein Spiel, das Nightforge noch nie gesehen hat, startet beim ersten Druck auf „Spielen“ mit dem Wissen aus
allen Spielen gleicher Sorte. Maßstab bleibt die Erststart-Quote (`StartEvidence.summary`): 9.11. abends 0 von 4,
Nachttest 10.11. 1 von 3.

## 1. Befund im Code (staging-033, f27afd2)

| Nr. | Was fehlt | Beleg |
|---|---|---|
| B1 | Die Startevidenz wird geschrieben, aber von keiner Entscheidung gelesen. | `StartEvidence.note` an fünf Stellen in `LibraryModel`; `load`/`summary` nur für eine Protokollzeile. |
| B2 | Gelernt wird je Spiel, nie je Sorte. | Alle Schlüssel hängen an `GameID`: `launchHealth.<id>`, `learned.winetricks.<id>`, `learned.noAVX.<id>`. |
| B3 | Beim Fehlschlag gibt es einen Hebel: den Grafikweg. | `LaunchAttempt` = `graphics` + `arguments`. Laufzeit, AVX, Dateikorrektur, Engine-Rückfall sind Sonderzweige in der Startschleife (`LibraryModel` 4549–4860, 22 Ausgänge), jeder mit eigenem Speicher. |
| B4 | Die Diagnose kennt zwei Muster. | `StartFailure`: `refusedSwitch`, `needsD3D12`, beide aus dem Meldungstext. Absturzberichte (Minidump) liest niemand aus. |
| B5 | Die Analyse wirft Wissen weg, den Prefix kennt niemand. | `GameAnalysis.middleware` filtert `physx`, `nvapi`, `bink`, `eossdk`, `steam_api` als Rauschen. Was im gemeinsamen Prefix installiert ist, fließt in keine Entscheidung ein. |
| B6 | Der Spieletest füttert das Lernen nicht. | `GameTest` schreibt `report.md` für uns; bestätigt wird nie (60 s Spielzeit, Bestätigung braucht 180 s). |

Das Beispiel der Nacht 10.11.: It Takes Two stürzte auf allen drei Grafikwegen gleich ab (PhysXUpdateLoader64 →
nvapi64 → Adresse 0). B3: Die Leiter konnte nur den Weg wechseln. B4: Der Minidump nannte das Modul, niemand las ihn.
B5: PhysX im Spiel und die PhysX System Software im Prefix waren beide vorab sichtbar.

## 2. Zielbild

Ein Datensatz, ein Kreislauf, Wissen nach Steckbrief.

### 2.1 Das Startrezept

Alles, was einen Start bestimmt, in einem Wert:

```swift
struct StartRecipe: Codable, Equatable {
    var graphics: GraphicsLayer
    var arguments: [String]
    var dllOverrides: [String: String]     // heute: Profil + Engine.gameDllOverrides
    var runtimes: [String]                 // heute: Profil.winetricks + LearnedFixes
    var avx: Bool                          // heute: learned.noAVX
    var engineBuild: String?               // heute: EngineRollback
    var steps: [RecipeStep]                // woher jede Abweichung kommt: Profil, Diagnose, Steckbrief, Bericht
}
```

`LaunchAttempt` wird zum Sonderfall davon. Profile (`mac.json`, `profiles.json`) bleiben, was sie sind: geprüfte
Rezeptteile mit Vorrang. Die Leiter wird eine Liste von Rezepten statt von Grafikwegen.

### 2.2 Der Steckbrief

Was `GameAnalysis` schon liest, plus was sie heute wegwirft, als fester Schlüssel:

- Engine und Engine-Version (Unreal 4.26 steht im Absturzbericht und in den Dateien)
- Grafik-Schnittstellen (wie heute)
- Middleware als Menge statt als Rauschen: PhysX 2 oder 3, Bink, Wwise, EOS, Steamworks, DLSS, Aftermath
- eigener Launcher, Anti-Cheat, 32 oder 64 Bit

Daraus zwei Schlüssel: grob (`unreal4|d3d11+d3d12`) und fein (`unreal4.26|d3d11+d3d12|physx3`).

### 2.3 Die Diagnose

Eine Tabelle Fehlerbild → Abhilfe, in der App, getestet wie `StartFailure` heute:

| Fehlerbild (woran erkannt) | Abhilfe (Rezeptänderung) |
|---|---|
| Meldung „mutually exclusive … -d3d“ | Argumente weglassen (heute `refusedSwitch`) |
| Meldung „requires DirectX 12“ | D3DMetal (heute `needsD3D12`) |
| Minidump: Rücksprung in `nvapi64` aus `PhysXUpdateLoader*` | Update-Loader aus (0df3c58, heute fest für alle) |
| Minidump: Absturz in `nvapi64`/`nvngx` | `nvapi64`, `nvngx` aus (Overwatch, 7.11.) |
| Protokoll: fehlende DLL | Laufzeit dazu (heute `missingRuntimes`) |
| Protokoll: illegal instruction | AVX aus (heute `setNoAVX`) |
| Grafikfehler des Layers | nächster Grafikweg (heute `graphicsFailed`) |
| kein Bild, keine Arbeit | hängt: nächstes Rezept (heute `PictureWatch`) |

Neu ist der Minidump-Leser: Ausnahmeadresse, Modulliste, erste Rücksprünge im Stapel des abgestürzten Threads. Das
ist reines Dateilesen, kein Debugger. Für Anti-Cheat-Spiele bleibt er aus.

Regel: Eine Abhilfe kommt nur aus dieser Tabelle oder aus einem geprüften Profil. Nightforge erfindet keine.

### 2.4 Der Kreislauf

```
planen → starten → beobachten → diagnostizieren → Rezept ändern → festhalten
   ↑                                                                  │
   └──────────── Wissen: Spiel, Steckbrief fein, Steckbrief grob ─────┘
```

- **Planen:** Profil > eigener Beweis des Spiels > Beweise gleicher Steckbriefe auf diesem Mac > Berichte (Highball,
  PCGamingWiki, AGW) > Dateien > Standard. Neu ist die dritte Stufe.
- **Beobachten:** wie heute (Bild, FPS, Prozesse, Protokoll, Absturzberichte), aber als ein Befund-Wert.
- **Festhalten:** `StartEvidence` bekommt Steckbrief und Rezept dazu und wird gelesen.

Eine Schleife ersetzt die 22 Ausgänge: Jeder Sonderzweig wird eine Zeile der Diagnose-Tabelle.

### 2.5 Wer den Kreislauf fährt

Drei Auslöser, ein Ablauf:

1. der Spieler drückt „Spielen“ (wie heute)
2. der Probelauf nach dem Download (offen, Machbarkeit siehe 4)
3. der Nachttest (`GameTest`), der dann Evidenz schreibt statt nur einen Bericht

## 3. Stufen

Jede Stufe ist für sich nützlich und einzeln testbar.

| Stufe | Inhalt | Nutzen sofort | Risiko |
|---|---|---|---|
| 1 | Steckbrief: Middleware und Engine-Version aus `GameAnalysis` behalten; Evidenz schreibt Steckbrief und volles Rezept mit. | Daten sammeln sich ab sofort, ohne dass sich ein Start ändert. | klein |
| 2 | Minidump-Leser und Diagnose-Tabelle; `StartFailure` zieht um. Befund steht im Protokoll und im Problembericht. | Fehlstarts erklären sich selbst; wir sehen neue Fehlerbilder ohne Handarbeit. | klein |
| 3 | `StartRecipe` als Datensatz; Abhilfen aus der Tabelle ändern das Rezept, auch DLL-Schalter. Die Sonderzweige ziehen in die Tabelle. | It-Takes-Two-Fälle heilen beim ersten Start von selbst. | mittel: Umbau der Startschleife |
| 4 | Planen nach Steckbrief: Beweise gleicher Sorte ordnen die Leiter. | Neue Spiele beginnen mit dem, was bei ihresgleichen lief. | mittel: falsche Verallgemeinerung, darum nur Reihenfolge, nie Ausschluss |
| 5 | Nachttest und Probelauf fahren denselben Kreislauf. | Fehlversuche passieren, bevor der Spieler spielt. | Probelauf offen |
| 6 | Rezepte teilen: aus bewiesenen Rezepten Vorschläge für `mac.json`, mit OK je Bericht. | Jeder Mac lernt von jedem. | Entscheidung des Nutzers, Datenschutz |

Stufe 1 und 2 ändern keinen Start und können sofort gebaut werden. Stufe 3 ist der eigentliche Umbau.

## 4. Offene Fragen

- **Probelauf nach dem Download:** Fenster unterdrücken? Denuvo-Aktivierungen? Spielzeit bei Steam? Erst prüfen.
- **Steckbrief-Wissen und Engine-Stand:** Ein Beweis gilt für einen winecx-Stand. Verfällt er beim Engine-Wechsel
  oder wird er nur abgewertet?
- **Wie viel Beweis verallgemeinert?** Vorschlag: ab zwei Spielen gleicher feiner Sorte, grob erst ab drei.
- **Gemeinsamer Prefix:** Laufzeiten für Spiel A wirken auf Spiel B (PhysX). Soll das Rezept festhalten, was es im
  Prefix voraussetzt, damit der Nachttest nach jeder neuen Laufzeit gezielt die betroffenen Spiele prüft?
- **Anzeige:** Was sagt der Vorhang, während Nightforge ein Rezept ändert? Design zuerst (Board).

## 5. Grenzen, die bleiben

- Kein Umgehen von Anti-Cheat: keine Spieldateien ändern, nichts verstecken, keine Hardware vortäuschen. Der
  Kreislauf diagnostiziert Anti-Cheat-Spiele nicht (kein Minidump, kein zweiter Start).
- Lizenzen und Anmeldungen bleiben beim Spieler.
- Gemeinschaftsdaten ordnen nur erlaubte Wege. Argumente, Registry und Laufzeiten kommen aus geprüften Profilen, den
  Dateien des Spiels oder der Diagnose-Tabelle.
- Keine KI beim Start, kein Punktesystem: erst läuft es, dann wird verglichen.
