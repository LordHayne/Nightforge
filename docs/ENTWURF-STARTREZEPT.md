# Entwurf: Startrezept und Lernkreislauf

Stand 14.11.2026. Stufe 1 und 2 sind gebaut (Abschnitt 3.1), sie ändern keinen Start. Von Stufe 3 steht die reine Logik (3.3), verdrahtet ist sie nicht; Stufe 4 läuft in erster Form (3.2), 5 und 6 sind Entwurf. Auslöser: der Nutzer, 10.11.: „Wie können wir den Startvorgang
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
- **E, Teil 1 gebaut am 14.11.2026, nicht verdrahtet:** `StartRecipe` als das, womit gestartet wird (Umbau der
  Startschleife). Die Probe zu B zeigt, warum: Ein Beweis gilt für ein Rezept, nicht für einen Grafikweg. Plan und
  Stand in 3.3.

### 3.3 Plan für E (Stufe 3): Das Rezept trägt den Start

Stand 14.11.2026, spät. **Teil 1 ist gebaut:** die reine Logik mit Tests (`tests/StartRecipeTest`, `CloserLookTest`).
**Teil 2 verdrahtet sie** in der Startschleife, in den Schritten E1 bis E6 unten; was davon steht, sagt der Abschnitt
„Teil 2: Was verdrahtet ist“. Der Nutzer hat die vier Entscheidungen am 14.11. getroffen, alle wie empfohlen.

**Der Gedanke.** Ein Rezept hat drei Quellen: den Weg der Leiter (Grafikweg mit seinen Schaltern), das Profil und
das, was die Diagnose-Tabelle für dieses Spiel schon geändert hat (`StartRecipe.Learned`: DLLs aus, Laufzeiten, ohne
AVX, dazu die Namen der Regeln). `StartRecipe.of(way:learned:profile:…)` setzt daraus zusammen, was Wine bekommt.
Nach einem Fehlstart ändert eine einzige Entscheidung (`NextStart.after`) entweder das Gelernte – derselbe Weg noch
einmal – oder den Weg. Eine Abhilfe kommt nur aus der Tabelle (`StartDiagnosis.rules`) oder aus einem geprüften
Profil, nie geraten.

**Maßstab.** It Takes Two (10.11.): Der erste Fehlstart nennt im Minidump den PhysX-Update-Loader, derselbe Weg
startet noch einmal mit dem Loader aus, der zweite Start hat ein Bild. Der Spieler merkt eine längere Wartezeit. Als
Test nachgestellt (`StartRecipeTest`, mit einem Profil, das den seit 0df3c58 für alle abgeschalteten Loader
zurückholt): zwei Starts statt drei Wege und Aufgeben.

#### Was Teil 1 gebaut hat

| Baustein | Wo | Was es tut |
|---|---|---|
| Abhilfe ändert das Rezept | `StartRecipe.Learned.applying`, `StartRecipe.of(way:learned:…)` | DLLs aus, Laufzeiten, ohne AVX; die Regel steht in `steps`. Was schon drin ist, ändert nichts. Eine Direct3D-DLL wird nie abgeschaltet. Gelerntes geht über die DLL-Schalter von Profil und Layer. |
| Abhilfe wählt einen Weg | `NextStart.way(answering:)` | Schalter weg, bestimmter Layer, anderer Layer: der erste passende Weg, der noch kommt, sonst der nächste. Für die drei Meldungen von heute wählt es wie `LaunchHealth.advance(answering:)` (auf fünf Leitern, jedem Platz geprüft). |
| Entscheidung nach einem Fehlstart | `NextStart.after` | Eingang: Leiter und Platz, bewährt oder nicht, Gelerntes, Diagnose, Anti-Cheat, wie oft schon derselbe Weg, dazu drei Tatsachen von außerhalb der Tabelle (Engine davor, Datei korrigiert, genauerer Blick). Ausgang: derselbe Weg noch einmal, ein anderer Weg, „behält seinen Platz“, „kein anderer Weg“, Aufgeben. |
| Gedächtnis | `LearnedFixes.learned` / `keep` | Alles Gelernte eines Spiels als ein Wert. Laufzeiten und AVX liegen unter den Schlüsseln, die sie seit 0.2 haben; neu sind `learned.dllsOff.<Spiel>` und `learned.steps.<Spiel>`. |
| Leiter | `LaunchHealth.advance(_:_:to:)` | Setzt die Leiter auf den gewählten Weg. |
| Beweise je Rezept | `StartEvidence.Proof.workedWith`, `failedWith`, `holds`, `steps(on:)` | Siehe „Beweise“ unten. |
| Fehlerfenster | `CloserLook.Reading.endedAtBox`, `CloserLook.box`, `LaunchHealth.ownQuestionWasAChoice`, `CloserLook.everyStart` | Siehe „Fehlerfenster oder Frage“ unten. |

**Die Entscheidung, in dieser Reihenfolge:**

1. Die Engine davor (EngineRollback hat sie schon festgehalten): derselbe Weg noch einmal.
2. Alles, was die Tabelle am Rezept ändert, **in einem Start** – nicht ein Start je Abhilfe – zusammen mit den
   Dateikorrekturen des Profils. Auch für einen bewährten und einen von Hand gewählten Weg, wie heute.
3. Keine Leiter (Grafikweg von Hand): Ende ohne Wechsel.
4. Genauerer Blick am letzten Weg: derselbe Weg einmal mit den Kanälen.
5. Ein bewährter Weg behält seinen Platz, außer der Layer selbst sagt, dass er nicht zeichnen kann (`graphics-failed`).
6. Der Weg, auf den die Befunde zeigen, sonst der nächste. Keiner mehr: Aufgeben.

Grenzen darin: höchstens drei Starts „derselbe Weg noch einmal“ je „Spielen“ (`NextStart.againLimit`; heute gibt es
keinen Deckel), der Start auf der Engine davor zählt nicht mit. Bei Anti-Cheat wird nie eine DLL abgeschaltet;
Laufzeiten und AVX aus Wines Protokoll wirken dort wie bisher. Eine Wurzel ändert nichts von selbst. 3.000
zufällige „Spielen“, die nie gelingen, enden alle (Test): die Leiter geht nur vorwärts, der Deckel hält.

#### Die Ausgänge der Schleife heute und wohin sie gehen

`LibraryModel.launch`, Stand 70b38c1, in der Reihenfolge der Schleife:

| Heute | Künftig |
|---|---|
| Start kam nicht zustande; nicht beobachtet; überlebt; vom Spieler beendet; Bild, dann Ende | bleibt: Das ist Beobachten, vor jeder Abhilfe. |
| Ende an einer eigenen Frage | bleibt, bekommt die Fenster-Regel (E5). |
| Bewährter Weg, stiller zweiter Start (ABZU) | bleibt eigener Zweig: Er entscheidet ohne Diagnose und vor der Prozessprüfung. |
| Spiel läuft noch oder hängt | bleibt: Schutz vor einer zweiten Kopie. |
| Engine-Rückfall | bleibt bei `EngineRollback`, geht als Tatsache in die Entscheidung. |
| Fehlende Laufzeit → installieren, derselbe Weg | Tabelle: `missing-runtime` → `.runtimes`. |
| Dateikorrektur des Profils → derselbe Weg | Tatsache `filesFixed`: Das Profil ist geprüft, nur der Zeitpunkt ist besonders. |
| Illegal instruction → ohne AVX, derselbe Weg | Tabelle: `illegal-instruction` → `.noAVX`. |
| Von Hand gewählt oder keine Leiter | `.noOtherWay`. |
| Bewährter Weg ohne Grafikfehler behält seinen Platz | `.keepsItsPlace`. |
| Genauerer Blick (C) | Tatsache `look`. |
| Nächster Weg, der auf die Meldung antwortet | `.way`: jede Zeile der Tabelle mit einem Weg als Abhilfe, nicht nur die drei Meldungen. |
| Aufgeben | `.giveUp`. |
| neu | Tabelle: `physx-update-loader`, `nvidia-interface` → `.dllsOff`, derselbe Weg. |

Sieben Zweige werden eine Entscheidung. In die Tabelle ziehen die Laufzeit und AVX; was sie lernen, steht mit den
abgeschalteten DLLs in einem Wert (`StartRecipe.Learned`). Engine-Rückfall, Dateikorrektur und genauerer Blick
bleiben, was sie sind, mit ihrem eigenen Gedächtnis, und kommen als Tatsachen dazu.

#### Umbau in Schritten

Jeder Schritt ist einzeln testbar und einzeln einspielbar. In Klammern die Dateien außerhalb der reinen Logik.

- **E1 – ein Rezept je Start, ohne Wirkung.** Die Schleife baut das Rezept einmal aus Weg, Profil und
  `LearnedFixes.learned`. Evidenz, DLL-Schalter und Windows-Version im Prefix, Laufzeiten und AVX lesen aus diesem
  einen Wert. Solange nichts Neues gelernt ist, ändert sich kein Start. Test: Das Rezept in der Evidenz ist das, was
  im Prefix landet. (`LibraryModel`, `Engine.gameDllOverrides`/`applyGameSettings`, `Launcher`. Der Schalter am
  Launcher-Fenster vorbei steht dann nur noch an einer Stelle, heute doppelt in `argumentsPastLauncher` und
  `StartRecipe.of`.)
- **E2 – eine Entscheidung statt sieben Zweige, gleiches Verhalten.** `NextStart.after` ersetzt die Zweige von
  „Engine-Rückfall“ bis „Aufgeben“. Es wirken nur die Regeln, die heute schon wirken. Für ein Spiel mit Anti-Cheat
  kommt der Befund wie bisher aus Wines Protokoll allein. Sichtbar anders: mehrere Abhilfen in einem Start, der
  Deckel von drei. Live: ein Spiel mit fehlender Laufzeit, Hogwarts ohne Profil. (`LibraryModel`)
- **E3 – DLL-Abhilfen wirken.** `physx-update-loader` und `nvidia-interface` ändern das Rezept. Live: It Takes Two
  mit einem Testprofil, das den Loader zurückholt – ein Fehlstart, dann Bild, `steps` in der Evidenz.
  (`LibraryModel`: Der Filter aus E2 fällt weg.)
- **E4 – Beweise je Rezept wirken.** `LaunchHealth` hält zum bestätigten Weg fest, womit er lief. Ein Start mit
  anderem Rezept gilt nicht als bewährt und wird wieder bis zum Bild beobachtet. Preis: Ändert ein Profil den Start
  eines Spiels, kostet das einen beobachteten Start. (`LaunchHealth`, `LibraryModel`)
- **E5 – Fehlerfenster.** Jeder Start trägt `+pid,+loaddll,+msgbox`, und das Ende an einer eigenen Frage fragt
  zusätzlich `LaunchHealth.ownQuestionWasAChoice`. Unabhängig von E1 bis E4. (`GameLog`/`Engine` für den Grundwert,
  `LibraryModel`)
- **E6 – nach Entscheidung des Nutzers.** Frage zur Wurzel, genauerer Blick für den bewährten Weg, Text auf dem
  Vorhang (Board zuerst).

E1 vor E2 vor E3; E4 braucht E1; E5 steht für sich.

#### Teil 2: Was verdrahtet ist

| Schritt | Stand | Was sich am Start ändert |
|---|---|---|
| E1 | gebaut | Nichts. Die Schleife liest das Gelernte einmal je Start und baut daraus mit Weg und Profil das Rezept; DLL-Schalter und Windows-Version im Prefix, die Argumente und AVX kommen aus diesem Wert, die Evidenz schreibt ihn. |
| E2 | gebaut | Zwei Dinge, wie geplant: alles, was auf demselben Weg zu ändern ist, in einem Start; höchstens drei Starts „derselbe Weg noch einmal“ je „Spielen“. Sonst entscheidet `NextStart.after` wie die Zweige vorher. |
| E3 | gebaut | Jede Abhilfe der Tabelle wirkt, für Spiele ohne Anti-Cheat: DLLs aus und derselbe Weg noch einmal; der Weg, auf den ein Befund zeigt. |
| E4 | gebaut | Ein Weg ist für das Rezept bewährt, mit dem er lief. Ein Start mit anderem Rezept wird wieder bis zum Bild beobachtet. |
| E5 | gebaut | Jeder Start trägt `+pid,+loaddll,+msgbox`; ein Steam von vorher startet dafür einmal neu. Ein Fehlerfenster zählt als Fehlstart, nicht als Wahl des Spielers. |
| E6 | Logik gebaut, Oberflächen offen | Ein bewährter Weg, der ohne Erklärung wieder endet, startet einmal still mit den Kanälen und behält seinen Platz. Die Frage zur Wurzel und die Vorhangzeile gibt es noch nicht: sichtbar ist alles beim heutigen Text. |

**E1 im Einzelnen.** `Engine.applyGameSettings` und `Launcher.launch`/`launchDirect` bekommen das Rezept; der Launcher
nimmt die Argumente nur noch von dort. Eine Falle dabei: Das Spiel bekam schon immer Profil, dann Weg, dann den
Schalter am Launcher-Fenster vorbei; das Rezept in der Evidenz stand als Weg, Schalter, Profil. Das Rezept hat jetzt
die Reihenfolge des Starts, und `startsLike` vergleicht die Argumente ohne Reihenfolge, damit die Beweise von vor dem
14.11. gelten. Die Argumente gegen ein Anti-Cheat (`SteamCatalog.antiCheatOffArguments`) und die eigenen des Spielers
stehen weiter außerhalb des Rezepts. Der Schalter am Launcher-Fenster vorbei steht nur noch in
`StartRecipe.pastLauncher`.

**E2 im Einzelnen.** Die Schleife sammelt die Tatsachen (Engine davor, Dateikorrektur, die Worte des Spiels, Wines
Protokoll, den genaueren Blick), fragt einmal und tut, was die Antwort sagt. Ein Test hält die Entscheidung gegen
die alten Zweige, als Funktion ausgeschrieben, auf 4.000 erfundenen Fehlstarts (`StartRecipeTest`, „Step E2“); mit
dem Filter `NextStart.asBefore` wirkten in E2 nur die Abhilfen von vorher. Genauer als geplant: Ein Start, der AVX gar
nicht angeboten hat (Profil), wird wegen „illegal instruction“ nicht wiederholt, wie vorher
(`NextStart.Failed.recipe`).

**E3 im Einzelnen.**

- Für ein Spiel ohne Anti-Cheat entscheidet die ganze Diagnose. Neu wirken damit: `nvidia-interface` und
  `physx-update-loader` (DLLs aus, derselbe Weg), `graphics-crash` und `graphics-failed` (ein Weg auf einem anderen
  Layer statt einfach der nächste), `loads-direct3d9` (Wines eigenes Direct3D). Ein Fenstertext zählt als Wort des
  Spiels, sobald ein Start `+msgbox` trägt.
- Was der Fehlstart schon hatte, ist keine Änderung: Eine DLL, die im Rezept schon aus war (der PhysX-Update-Loader
  für alle, eine aus dem Profil), löst keinen Start aus.
- Zeigen mehrere Befunde auf einen Weg, gilt zuerst der, der den Weg benennt (Layer, ohne Schalter), dann „anderer
  Layer“, dann „der nächste“ (`NextStart.pointer`). Sonst schickte ein Absturz in `d3d9.dll` Alan Wake von D3DMetal
  zu DXMT, wo Direct3D 9 genauso DXVKs ist.
- Für ein Spiel mit Anti-Cheat bleibt alles wie vor E: Der Befund kommt aus Wines Protokoll und den Absturzberichten
  wie bisher, und es wirken nur die Abhilfen von vorher (`NextStart.asBefore` bleibt dafür stehen). Keine DLL aus.
- Evidenz: Ändert ein Fehlstart das Rezept, steht er jetzt als `failed` in der Aufzeichnung, mit Diagnose. Vorher
  schrieben die Zweige „Laufzeit“ und „AVX“ dafür nichts. So kennt `failedWith` das Rezept, das scheiterte.
- Die Erststart-Zählung (`StartEvidence.summary`) zählt Wege, nicht Starts: Ein Spiel, das auf seinem ersten Weg beim
  zweiten Start kommt, kam auf dem ersten Weg. **Das ändert die Zahl auch rückwirkend** für Spiele, die auf
  demselben Weg zwei „Spielen“ brauchten; vorher zählten sie als „späterer Weg“.
- `StartDiagnosis.finding` liest „illegal instruction“ jetzt auch aus den Absturzberichten (Unreal fängt es selbst),
  wie der alte Zweig es tat.

**E4 im Einzelnen.** `LaunchHealth` hält zum bestätigten Weg das Rezept des Starts fest, der ihn bestätigt hat
(`confirm(…recipe:)`, `holds`). Baut die Schleife für einen bewährten Weg ein anderes Rezept, nimmt sie die
Bestätigung für diesen Start zurück: Er wird wie ein erster beobachtet und mit dem neuen Rezept neu bestätigt, die
Evidenz bekommt ein `worked` dazu. Ein Weg ohne Rezept im Zustand gilt für jedes: alles, was vor dem 14.11.
bestätigt wurde, und was `review` allein aus Steams Protokoll bestätigt. Der nächste gute Start trägt das Rezept
ein. Der Preis steht oben und ist echt: Nach einem Update, das die DLL-Schalter eines Layers oder ein Profil ändert,
wird der nächste Start jedes betroffenen Spiels beobachtet, mit `waitForPicture` und dessen „hung“ nach 90 s ohne
Arbeit oder 270 s ohne Bild.

**E5 im Einzelnen.**

- Der Grundwert ist `CloserLook.usualWineDebug` (`GameLog.wineDebug` und die drei Kanäle), in
  `Engine.gameEnvironment` und als Vorgabe von `Engine.wineDebug`. `steamConfigVersion` steht auf 11, das ist der
  eine Steam-Neustart. `GameLog.swift` ist nicht angefasst; der Schalter `wineDebug` wirkt obendrauf wie bisher.
- Kosten, gemessen am Messlauf vom 14.11. (20 Spiele in 81 Minuten, `+pid,+loaddll` an): 6.888 Ladezeilen, 866 KB
  von 2,9 MB Protokoll. Im Schnitt 43 KB je Spielstart.
- Die Schleife fragt beim Ende an einer eigenen Frage zusätzlich `LaunchHealth.ownQuestionWasAChoice`. **Anders als
  in Teil 1 vorgeschlagen** heißt „erklärt“ dort: Die Tabelle hat einen Fehler gesehen
  (`StartDiagnosis.sawFailure`: die Worte des Spiels, ein Dump an bekannter Stelle, Wines oder des Layers eigener
  Fehler). „Irgendeine Zeile außer den Auffangzeilen“ wäre mit E5 falsch geworden: Seit jeder Start `+loaddll`
  trägt, findet `loads-direct3d9` jedes Direct3D-9-Spiel auf DXMT oder D3DMetal, auch eines, das der Spieler an
  seinem Launcher-Fenster beendet hat. Was einen Start nur beschreibt (was er lud, eine Signaturprüfung), lässt das
  Ende die Wahl des Spielers.
- Die Leser in `GameLog` sind mit Zeilen geprüft, die mit der Prozessnummer beginnen (`CloserLookTest`, „Step E5“).
  Der FPS-Leser des Spieletests liest über `CloserLook.Line` und kennt die Form schon.
- Die Zeile der Vorhangwache („ended right at a question of its own, answered by the player: no other way“) steht
  weiter im Protokoll; entscheidet der Start anders, schreibt er „the window it ended at was no question … a failed
  start“ dahinter.

**E6 im Einzelnen.**

- *Genauerer Blick für den bewährten Weg (verdrahtet, still):* `CloserLook.step(…proven:)` antwortet für einen
  bewährten Weg mit „derselbe Weg noch einmal“, weil kein kommender Weg die Kanäle tragen könnte. Danach behält der
  Weg seinen Platz, was immer der zweite Start zeigt (`lookedAtProven` in der Schleife); in der Evidenz steht dann
  die Diagnose mit den Kanälen. Einmal je Spiel und Engine-Stand, nie bei Anti-Cheat, nur wo der Start die Kanäle
  tragen kann. Das gilt für den Zweig „bewährt, aber Absturz oder zu viele kurze Enden“. **ABZUs Zweig – das stille
  zweite Mal nach einem Ende ohne Fehler – bleibt, wie er ist:** Der zweite Start gelingt dort fast immer und wäre
  mit den Kanälen die Spielsitzung selbst, mit der Debugger-Ausgabe des Spiels im Protokoll. Im Messlauf vom 14.11.
  hätte der Blick an ABZU auch nichts gesehen: Der erste Anlauf lud dieselben 85 Bibliotheken wie der zweite und
  endete nach 3,7 s ohne Zeile, Fenster oder Dump.
- *Wurzel (entschieden, nicht verdrahtet):* `NextStart.rootToAskAbout` sagt, nach welcher Wurzel gefragt werden
  kann (der Befund nennt sie, sie ist bekannt und noch nicht im Prefix, in diesem „Spielen“ noch nicht gefragt).
  `NextStart.after(rootTrusted:againSoFar:)` sagt, was folgt: Ja – derselbe Weg noch einmal; Nein – der Start
  endet, die übrigen Wege werden nicht durchgegangen, die Leiter bleibt, wo sie ist.
- **Was der Wurzel-Frage noch fehlt, außer dem Board:** `WindowsRoots.all` trägt jede bekannte Wurzel für alle in
  jeden Prefix. Damit gibt es heute keine Wurzel, die auf ein Ja wartet. Die Frage braucht eine zweite Liste
  (bekannt, aber nur auf Ja), einen Ort für das Ja des Spielers und den Eintrag in `registrySection`. Jede Wurzel in
  dieser Liste braucht wie bisher das OK des Nutzers.

**Live zu prüfen** (die Anleitung liegt im Notizordner, `closer-look/live-pruefung-schritt-e.md`): E2 mit einem
Spiel, dem eine Laufzeit fehlt, und Hogwarts Legacy ohne Profil; E3 mit It Takes Two und einem Testprofil, das den
Loader zurückholt; E4 mit einem bewährten Spiel, dessen Profil sich ändert; E5 mit Alan Wake auf D3DMetal und The
Forest; E6 mit einem bewährten Spiel, das abstürzt.

#### Beweise gelten für ein Rezept

`StartEvidence.proofs` liest zu jedem `worked` und `failed` das Rezept des Starts, zu dem es gehört:

- `workedWith[Weg]`: das Rezept des Starts, der zählte. `failedWith[Weg]`: die Rezepte, mit denen der Weg ohne Bild
  endete, auch wenn er mit einem anderen später lief. It Takes Two im Test: D3DMetal lief mit dem Loader aus und
  scheiterte mit ihm – ein Weg, zwei Rezepte.
- `holds(for:on:)`: Der eigene Beweis eines Spiels gilt für das Rezept, das lief (`StartRecipe.startsLike`: alles, was
  Wine bekommt; welche Regel es verlangt hat, zählt nicht).
- **Alte Zeilen behalten ihren Wert:** Ein `worked` aus der Zeit vor den Rezepten (vor dem 10.11.) hat kein Rezept und
  gilt weiter für seinen Weg, mit welchem Rezept auch immer. Probe an der echten Aufzeichnung dieses Macs (14.11., 74
  Zeilen, 18 Spiele): acht Wege mit `worked`, fünf tragen ein Rezept, drei stammen von davor; kein `failed` trägt
  bisher eines.
- **Für die Sorte ändert sich nichts:** `worked`, `picture`, `failed` und `sortScores` rechnen wie vorher. Ein Weg, der
  erst mit geändertem Rezept lief, zählt für die Sorte als der Weg, der er ist – weiter nur als Reihenfolge.
  `steps(on:)` sagt, welche Regeln das Rezept trug. Ob ein Spiel gleicher Sorte diese Änderungen gleich mitbekommt,
  ist Stufe 4 in ihrer nächsten Form und nicht Teil von E.
- Auch der Start eines Profils wird gelesen: Sein Rezept ist genau das, was er beweist. Für die Sorte beweist er
  weiter nichts.

#### Fehlerfenster oder Frage

Der Fund vom 14.11.: Alan Wakes Fehlerfenster stand unter dem Vorhang als Frage, der Spieler drückte OK, und der
Vorhang schrieb „ended right at a question of its own, answered by the player: no other way“. Genauer hingesehen
(Code und Protokoll gelesen, nicht nachgestellt): Die Zeile stammt von der Vorhangwache. Der Start selbst hat das
Ende in diesem Fall **nicht** als Wahl des Spielers genommen, weil `direct3D9Failed` dagegen sprach (fe1b8fa); im
Protokoll fehlt die Zeile „Start of Alan Wake: it ended at a question of its own“. Die Lücke ist trotzdem echt: Metal Gear Solid V steht am 11.11. mit „closed at a
question of its own“ in der Evidenz, weil außer dem Fenster nichts gegen den Start sprach.

**Die Regel** (`LaunchHealth.ownQuestionWasAChoice`, zusätzlich zu dem, was der Start heute schon fragt):

1. Erklärt die Tabelle das Ende (irgendeine Zeile außer den Auffangzeilen), war es keine Wahl. Das kostet nichts
   und braucht keinen Kanal.
2. Endete das Spiel an einem Windows-Meldungsfenster und dessen Text ist eine Mitteilung, war es keine Wahl. Der
   Text ist dann das Wort des Spiels.
3. Sonst bleibt es die Wahl des Spielers wie heute. Unitys Fenster vor dem Spiel und die Fenster eigener Launcher
   sind keine Meldungsfenster, `+msgbox` druckt für sie nichts.

**Mitteilung oder Frage** (`CloserLook.box`): Wine druckt nur den Text, nicht die Knöpfe. Ein Fenster, das nichts
fragt, hat nur OK. Also entscheidet der Text: ohne Fragezeichen eine Mitteilung; mit Fragezeichen eine Frage, außer
der Text meldet einen Fehler („… has crashed. Send a report?“, Wörter auf Englisch und Deutsch). An welchem Fenster
das Spiel endete, sagt `Reading.endedAtBox`: das letzte Fenster, nach dem sein Prozess nichts mehr geladen hat.
Grenzen: Die Wortliste kennt zwei Sprachen; ein echtes Ja/Nein ohne Fragezeichen gälte als Mitteilung.

**Was es braucht:** den Kanal `+msgbox` bei jedem Start, und damit der Leser das Fenster dem Spiel zuordnet, auch
`+pid` und `+loaddll` (`CloserLook.everyStart`). Die Ausgabe für den Debugger und die Zertifikatsketten bleiben
dem genaueren Blick: Ein Spiel kann die erste mit jedem Frame schreiben, und Steams Browser baut Ketten, solange
er läuft.

**Was es kostet:**

- Protokoll: Alan Wakes Direktstart am 14.11. kam auf 88 Zeilen, 10 KB. Batmans Start über Steam samt
  Steam-Neustart hatte mit allen Kanälen 4.423 Zeilen, davon 3.204 Ketten; für die drei Kanäle bleiben höchstens
  rund 1.200 Zeilen, die meisten einmal je Steam-Start. `wine.log` wechselt bei 8 MB in `wine.previous.log`.
- Laufzeit: eine Zeile je geladener Bibliothek beim Prozessstart, eine je Meldungsfenster, nichts während des Spiels.
- Steam: ein Neustart beim ersten Start nach der Umstellung, danach keiner mehr für diese Kanäle. Der genauere
  Blick braucht seinen Neustart weiter.
- Risiko: `+pid` setzt vor jede Wine-Zeile die Prozessnummer. Die Leser in `GameLog` suchen in der Zeile, nicht am
  Anfang (nachgesehen bei fehlenden Laufzeiten, Absturz, illegal instruction und Grafikfehler); in E5 mit Zeilen
  dieser Form zu testen.

**Nebenbei gewonnen:** `loads-direct3d9` und der Fenstertext wirken dann schon beim ersten Fehlstart, ohne
zweiten Start. Der offene Punkt „`+loaddll` beim ersten Start“ wäre erledigt.

#### Was sich für den Spieler ändert – und was nicht

Es ändert sich:

- Ein Fehlstart mit bekannter Ursache heilt im selben „Spielen“. Der Vorhang bleibt oben, das Spiel startet auf
  demselben Weg noch einmal, statt alle Wege durchzugehen und aufzugeben.
- Mehrere Abhilfen kommen in einem Start, und es gibt höchstens drei solche Starts je „Spielen“.
- Ein Spiel verlässt seinen Grafikweg seltener wegen einer Ursache, die nicht am Weg liegt.
- Mit E5 zählt ein Fehlerfenster als Fehlstart: Der nächste Weg oder die Abhilfe kommt, wo Nightforge heute still
  in die Bibliothek zurückgeht.

Es ändert sich nicht:

- Keine neue Oberfläche und kein neuer Text, bis ein Board entschieden ist.
- Die erste Wahl: Profil, eigener Beweis, Beweise der Sorte, Berichte, Dateien.
- Ein bewährter Weg behält seinen Platz. Ein von Hand gewählter Weg wird nie gewechselt.
- Anti-Cheat: keine Diagnose aus Spieldateien, kein genauerer Blick, keine DLL aus.
- Wurzeln nur im Prefix und jede weitere nur mit OK. Lizenzen und Anmeldungen bleiben beim Spieler.
- Die Evidenz bleibt auf dem Mac.

#### Entscheidungen für den Nutzer

**Entschieden am 14.11.2026, alle vier „Ja, wie empfohlen“.** Gebaut sind 1 (E6) und 3 (E5); 2 und 4 warten auf
ihr Board, die Vorlagen dafür stehen unter der Liste.

1. **Bekommt ein bewährter Weg, der wieder scheitert, den genaueren Blick?** Empfehlung: ja – ein stiller Start
   mehr im selben „Spielen“, einmal je Spiel und Engine-Stand; sonst verlässt das nächste „Spielen“ den bewährten
   Weg, ohne dass jemand weiß, warum er scheiterte. `NextStart.after` kann es schon.
2. **Wird `untrusted-root` eine Frage an den Spieler?** Empfehlung: ja, aber nur für eine Wurzel, die `WindowsRoots`
   mit festen Fingerabdrücken kennt – bei Ja kommt sie in den Prefix und derselbe Weg startet noch einmal, bei Nein
   endet der Start, ohne die übrigen Wege durchzugehen; eine unbekannte Wurzel wird weiter nur gesagt. Die Frage
   braucht ein Board.
3. **Tragen alle Starts `+pid,+loaddll,+msgbox`?** Empfehlung: ja – die Kosten stehen oben, und nur so lässt sich
   ein Fehlerfenster schon beim ersten Fehlstart lesen.
4. **Was sagt der Vorhang, während Nightforge ein Rezept ändert?** Oberfläche, also Board zuerst. Heute steht beim
   Wegwechsel „Starting again with %@ …“ mit dem Hinweis „It closed right away – Nightforge starts it the next way and
   remembers what works.“ Drei Vorlagen für Zeile und Hinweis beim Start auf demselben Weg:
   - A, ruhig, ohne Technik: „Noch ein Versuch …“ / darunter „Das Spiel ist gleich wieder zugegangen. Nightforge
     hat die Ursache gefunden und startet es noch einmal.“
   - B, sagt, was geändert wird: „Startet noch einmal, ohne %@ …“ (z. B. „ohne NVIDIAs Zusatz“, „mit einer
     fehlenden Laufzeit“) / darunter wie A.
   - C, gar kein eigener Text: Der Vorhang bleibt bei „Startet …“, der Spieler merkt nur die längere Wartezeit.
   Empfehlung: A – es erklärt die Wartezeit, ohne Mechanik zu zeigen.

**Das Board steht seit 15.11.2026:** https://claude.ai/artifact/DFFsf6UN2SqAEubqUCWWy3 (Design-Leinwand im
Nightforge-Designsystem, privat; die Quellen der fünf Artboards liegen in `docs/entwuerfe/fehlstart/`). Es zeigt
drei Vorlagen für den Vorhang bei einem Fehlstart (A ruhig, B mit Lebenszeichen – empfohlen, C erzählt mit), drei
Wege für das Fehlerfenster des Spiels (einordnen – empfohlen als erster Schritt, selbst sagen, selbst OK drücken)
und die Frage zur Wurzel (auf dem Vorhang – empfohlen, oder auf der Seite des Spiels), alles deutsch und englisch.
Der Nutzer wählt; gebaut ist davon nichts. Die Tabelle unten war der erste Stand der Texte.

**Vorlage für das Board, zwei Oberflächen, deutsch und englisch.** Nichts davon ist gebaut.

*Vorhang beim Start auf demselben Weg (Vorlage A).* Es gibt drei Anlässe, und der Satz darunter stimmt nicht für
alle drei:

| Anlass | Zeile | Darunter |
|---|---|---|
| Die Tabelle hat das Rezept geändert | „Noch ein Versuch …“ / “One more try …” | „Das Spiel ist gleich wieder zugegangen. Nightforge hat die Ursache gefunden und startet es noch einmal.“ / “The game closed right away. Nightforge found the cause and starts it once more.” |
| Genauerer Blick (nichts erklärt das Ende) | wie oben | „Das Spiel ist gleich wieder zugegangen. Nightforge sieht genauer hin und startet es noch einmal.“ / “The game closed right away. Nightforge takes a closer look and starts it once more.” |
| Engine davor | heute schon eigener Text (`.rollingBack`) | bleibt |

Das Board muss entscheiden, ob der zweite Anlass einen eigenen Satz bekommt oder beide einen gemeinsamen, der
nichts verspricht („… Nightforge startet es noch einmal.“). „Die Ursache gefunden“ wäre beim genaueren Blick
unwahr.

*Frage zur Wurzel.*

- Titel: „%@ braucht ein älteres Zertifikat“ / “%@ needs an older certificate”
- Text: „Das Spiel prüft beim Start eine Datei, die mit dem Zertifikat „%@“ signiert ist. macOS führt es nicht
  mehr, Windows schon. Nightforge kann es für seine Windows-Spiele eintragen – nur dort, nicht im Mac.“ / “At its
  start the game checks a file signed with the certificate ‘%@’. macOS no longer carries it, Windows does.
  Nightforge can add it for its Windows games – only there, not on the Mac.”
- Knöpfe: „Eintragen und starten“ / „Nicht eintragen“ – “Add and start” / “Don’t add”
- Nach Nein: „%@ startet ohne dieses Zertifikat nicht.“ / “%@ doesn’t start without this certificate.”
- Für das Board offen: ob ein Nein gemerkt wird (sonst fragt jedes „Spielen“ wieder) und wo der Spieler es später
  ändert; ob die Frage mit dem Controller zu beantworten ist, solange der Vorhang oben ist.

#### Offen und Risiken

- Eine gelernte Änderung bleibt beim Spiel, für alle Wege, auch wenn sie nicht geholfen hat (wie Laufzeiten und AVX
  heute). Zurücknehmen, wenn derselbe Befund danach wieder kommt, wäre genauer; noch nicht gebaut.
- Gelerntes geht über das Profil. Begründung: Es antwortet auf einen Fehler, der auf diesem Mac in diesem Spiel
  gesehen wurde, und Profile aus umu sind auf dem Mac nicht geprüft. Für die erste Wahl behält das Profil den Vorrang.
- `nvapi64` und `nvngx` aus nimmt einem Spiel auf D3DMetal DLSS über MetalFX. Das ist der Preis dafür, dass es startet.
- Der gemeinsame Prefix: Eine Laufzeit für Spiel A wirkt auf Spiel B (Abschnitt 4).
- `physx-update-loader` ist seit 0df3c58 für alle aus und greift nur noch, wenn ein Profil den Loader zurückholt.
  Als echte neue Wirkung bleibt zunächst `nvidia-interface`.

## 4. Offene Fragen

- **Probelauf nach dem Download:** Fenster unterdrücken? Denuvo-Aktivierungen? Spielzeit bei Steam? Erst prüfen.
- **Steckbrief-Wissen und Engine-Stand:** Ein Beweis gilt für einen winecx-Stand. Verfällt er beim Engine-Wechsel
  oder wird er nur abgewertet?
- **Wie viel Beweis verallgemeinert?** Vorschlag: ab zwei Spielen gleicher feiner Sorte, grob erst ab drei.
- **Gemeinsamer Prefix:** Laufzeiten für Spiel A wirken auf Spiel B (PhysX). Soll das Rezept festhalten, was es im
  Prefix voraussetzt, damit der Nachttest nach jeder neuen Laufzeit gezielt die betroffenen Spiele prüft?
- **Anzeige:** Was sagt der Vorhang, während Nightforge ein Rezept ändert? Design zuerst (Board). Drei Vorlagen
  stehen in 3.3 › Entscheidungen.

## 5. Grenzen, die bleiben

- Kein Umgehen von Anti-Cheat: keine Spieldateien ändern, nichts verstecken, keine Hardware vortäuschen. Der
  Kreislauf diagnostiziert Anti-Cheat-Spiele nicht (kein Minidump, kein zweiter Start).
- Lizenzen und Anmeldungen bleiben beim Spieler.
- Gemeinschaftsdaten ordnen nur erlaubte Wege. Argumente, Registry und Laufzeiten kommen aus geprüften Profilen, den
  Dateien des Spiels oder der Diagnose-Tabelle.
- Keine KI beim Start, kein Punktesystem: erst läuft es, dann wird verglichen.
