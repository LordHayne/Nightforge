# Entwurf: Startrezept und Lernkreislauf

Stand 10.11.2026. Stufe 1 und 2 sind gebaut (Abschnitt 3.1), sie ändern keinen Start. Stufe 3 bis 6 sind Entwurf. Auslöser: der Nutzer, 10.11.: „Wie können wir den Startvorgang
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
| Signaturprüfung antwortet `800b0109` (Wurzel fehlt, nur mit Debug-Kanälen sichtbar, 3.2 C) | Wurzel in den Prefix, je Wurzel mit OK des Nutzers (`WindowsRoots`) |
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

### 3.1 Gebaut am 10.11.2026 (Stufe 1 und 2)

- `GameKind` (Steckbrief): Engine mit Version, Schnittstellen, Middleware, Launcher, Anti-Cheat, 32/64 Bit. Unreals
  Version steht in der Versionsressource des Programms (`PEImports.facts`), Unitys am Anfang der Spieldaten.
  Schlüssel `coarse` und `fine`. An den installierten Spielen geprüft: ABZU `unreal4.12`, It Takes Two `unreal4.26`,
  Hogwarts `unreal4.27`, Wukong `unreal5.0`, REANIMAL `unreal5.4`, The Forest `unity5.6`, OxyRail `unity6000.3`.
- `StartRecipe`: Grafikweg, Argumente, alle DLL-Schalter, Laufzeiten, AVX, Windows-Version als ein Wert.
- `StartEvidence` schreibt bei jedem Start `kind` und `recipe`, bei einem Fehlschlag `diagnosis`. Alte Zeilen lesen sich weiter.
- `CrashDump`: liest Minidumps als Datei (x64 und x86): Ausnahme, Modul der Adresse, Module auf dem Stapel des
  abgestürzten Threads. Kaputte Dateien ergeben nichts (Kürzungen und 400 Zufallsfehler im Test).
- `StartDiagnosis`: die Tabelle Fehlerbild → Abhilfe (`rules`), `finding` sammelt Meldungen, Dumps und Protokoll. Das
  Ergebnis steht im Protokoll („Diagnosis for …“), in der Evidenz und im Problembericht. Nie bei Anti-Cheat-Spielen.
- Probe an den 28 echten Dumps dieses Macs: alle acht von It Takes Two → `physx-update-loader`. Neue Fehlerbilder, die
  dabei sichtbar wurden und noch keine Regel haben: Unity `0xc06d007e` (nachgeladenes Modul fehlt) über `winemetal.dll`
  (OxyRail); Unreal-Assert `0x4000` über `kernelbase` (Hogwarts, steht schon als Meldung da).
- Offen aus diesen Stufen: Die Diagnose läuft nur nach einem frühen Ende ohne Bild, nicht bei Abstürzen mitten im Spiel.
  Live an einem scheiternden Start noch nicht gesehen (nur an den vorhandenen Dumps und in `StartDiagnosisTest`).
- Live gesehen am 10.11. 20:55 (988e721): Die Evidenzzeile von It Takes Two trägt `kind` (unreal 4.26, aftermath, apex,
  physx3, steamworks) und `recipe` (d3dmetal, `-dx12`, zehn DLL-Schalter).

### 3.2 Gebaut am 11.11.2026 (Evidenz vollständig, Stufe 4 in erster Form)

Auslöser war der Engine-Test vom 11.11. (vier Spiele mit nie gestarteten Engines, `docs/TODO.md`): Kein Fehlstart lag
am Grafikweg, und die Diagnose schwieg, weil die Information im Fehlerfenster des Spiels und in Wines Debug-Ausgabe
stand. Daraus die Reihenfolge A bis E:

- **A, gebaut (4d7806c):** Jeder aufgezeichnete Start bekommt einen Ausgang. Neu ist `ended` (vom Spieler beendet, an
  einer eigenen Frage geschlossen, vor der Bestätigung beendet), mit `picture` und `seconds`; ein bewährter Weg, der
  wieder früh endet, bekommt `failed`.
- **B, gebaut (4d7806c), Stufe 4 in erster Form:** `StartEvidence.proofs` liest je Spiel Sorte und Wege,
  `kinship` wiegt die Verwandtschaft (gleiche Sorte 4, gleiche Engine-Version und Schnittstellen 3, gleiche Generation
  und Schnittstellen 2, gleiche Generation 1), `sortScores` wertet die Wege, `LaunchHealth.ordered` stellt sie um.
  Rang: Profil > eigener Stand des Spiels > Beweise gleicher Sorte > Berichte > Dateien. Nur Reihenfolge; ein Spiel
  behält die Ordnung, mit der es gestartet ist. Der Startplan nennt den Grund.
  Bewusst eng, nach einer Probe an den echten Daten: nur Erfolge zählen (It Takes Two „scheiterte“ auf DXMT wegen
  PhysX, nicht wegen des Wegs); nur Starts ohne Profil (`GameProfile.shapesStart`, `speaksForItsWay`: It Takes Two
  läuft auf D3DMetal mit dem `-dx12` des Profils); nur Unreal und Unity mit bekannter Version.
  Live 11.11.: Dishonored auf WineD3D bestätigt; für Batman (gleiche Generation `unreal3`) sagt der Plan aus den echten
  Daten „a game of its sort (unreal3) runs on it on this Mac“.
  Live 14.11.: Batmans echter Erststart (normaler Start des Nutzers) trug genau diesen Plan im Protokoll, begann auf
  WineD3D, zeigte nach 90 s ein Bild und wurde nach 181 s als `worked` festgehalten – ohne einen Fehlversuch.
  Damit ist die Kette Steckbrief → Beweis einer Sorte → erster Weg eines neuen Spiels einmal ganz gesehen.
- **C, gebaut am 14.11.2026 (`CloserLook`), live noch nicht gesehen:** der genauere Blick. Endet ein Start der Leiter
  und die Diagnose findet nichts außer ihren Auffangzeilen (`StartDiagnosis.unexplained`: gar nichts, `crash`, `said`,
  `debug-said`, `hung`), tragen die folgenden Starts dieses „Spielen“ Wines Debug-Kanäle
  (`+pid,+loaddll,warn+debugstr,+wintrust,+chain,+msgbox`), und was sie drucken, liest die Diagnose.
  - **Wann.** Gibt es noch einen Weg, startet der nächste und der Rest der Leiter mit den Kanälen; das kostet keinen
    eigenen Start. War es der letzte Weg (auch bei nur einem), startet derselbe Weg einmal still noch einmal mit den
    Kanälen, danach endet die Leiter wie bisher. Einmal je „Spielen“, einmal je Spiel und Engine-Stand
    (`closerLook.<Spiel>` = z. B. `winecx@4.7.3`). Nie bei Anti-Cheat, nie bei von Hand gewähltem Grafikweg, nicht
    solange ein anderes Windows-Spiel läuft (Steam startet dann nicht neu). Die Entscheidung ist `CloserLook.step`.
  - **Nicht dabei:** Ein bewährter Weg, der wieder früh endet, bekommt den Blick noch nicht. Er behält heute seinen
    Platz ohne zweiten Start; ein Start mehr würde ihn in derselben Runde auf die Leiter schicken. Das gehört zu E.
  - **Wie die Kanäle zum Spiel kommen.** `Engine.setCloserLook` legt `WINEDEBUG` in die Startumgebung;
    `Engine.wineDebug` geben Steam, der Prozess, der ein Spiel an Steam übergibt, und der Direktstart (Epic, GOG)
    weiter. Ein Steam-Spiel erbt die Umgebung seines Steam: Steam startet dafür neu, und beim nächsten Start ohne
    Kanäle noch einmal. Der Direktstart braucht keinen Neustart. Damit ist die Frage von vorher erledigt: Der Blick
    hängt nicht am Schalter `wineDebug`, der nur beim App-Start gelesen wird.
  - **Was gelesen wird (`CloserLook.read`).** Nur die Prozesse des Spiels: Ein Prozess gehört dazu, wenn er eine Datei
    aus dem Spielordner lädt. Wine vergibt Prozessnummern neu, sobald genug frei sind (`server/process.c`, die am
    längsten freie zuerst), und eine Steam-Sitzung lebt lange; darum zählt eine Nummer nur von einem `ntdll`-Laden
    bis zum nächsten. Daraus: Signaturprüfungen mit Antwort ≠ 0 (Datei, Code, Unterzeichner
    und Wurzel der letzten Kette vor der Antwort; der Abschluss-Aufruf mit Antwort 0 zählt nicht), die letzten Zeilen
    für den Debugger, die geladenen Grafik-Bibliotheken, die Texte der Meldungsfenster. Prüfungen einer Datei im
    Spielordner zählen auch ohne `+pid`, wie am 11.11.
  - **Neue Regeln.** `untrusted-root` (`800b0109`, Abhilfe „Wurzel in den Prefix“ nur als Aussage: jede Wurzel
    braucht das OK des Nutzers und geht über `WindowsRoots`), `signature` (andere Antwort für eine Datei des Spiels,
    ohne Abhilfe), `loads-direct3d9` (nur `d3d9.dll` geladen auf D3DMetal oder DXMT → WineD3D, nur gesagt),
    Auffangzeile `debug-said`. Die Diagnose bleibt Aussage: Protokoll, Evidenz, Problembericht.
  - **Evidenz und Testschalter.** `started` hält fest, dass der Start die Kanäle trug (`closerLook`).
    `defaults write io.github.lordhayne.nightforge closerLook -bool true` lässt jeden Start die Kanäle tragen.
  - **Geprüft** am echten Protokoll vom 11.11. (`tests/CloserLookTest/fixtures`): Die Regel nennt `steam_api64.dll`,
    Valve und die VeriSign-Wurzel. 4 MB Protokoll liest der Leser in 0,15 s. **Offen, nur live zu sehen:** ein
    scheiternder Start mit Kanälen, der Steam-Neustart hin und zurück, der Direktstart eines Epic-Spiels.
- **D, erste Form mit C gebaut, live noch nicht gesehen:** `+msgbox` druckt den Text jedes Windows-Meldungsfensters,
  `trace:msgbox:MSGBOX_OnInit L"…"` (`dlls/user32/msgbox.c`, in Wine 9.0 und 10.0 gleich; Kanal und Funktionsname
  stehen in der `user32.dll` von winecx 4.7.3). Der Text aus den Prozessen des Spiels zählt als Wort des Spiels: Er
  speist `refused-switch`, `needs-d3d12` und `said`. Grenzen: nur der Text, nicht der Titel; nur echte
  `MessageBox`-Fenster, keine selbst gezeichneten Dialoge (eigene Launcher, SDL); Wine kürzt bei rund 290 Zeichen; nur
  in Starts mit Kanälen, also nach dem ersten unerklärten Fehlstart. Was bleibt für D: Fenster ohne `MessageBox`.
- **E, offen:** `StartRecipe` als das, womit gestartet wird (Umbau der Startschleife). Die Probe zu B zeigt, warum:
  Ein Beweis gilt für ein Rezept, nicht für einen Grafikweg.

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
