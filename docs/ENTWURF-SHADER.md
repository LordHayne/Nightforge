# Entwurf: Shader und Pipelines auf dem DXMT-Weg vorbereiten

Stand: 7.11.2026, `main` 97a8056. Nur Plan; Bauen braucht das OK des Nutzers. Zahlen von Recall (v1.6.3) sind seine Angaben,
von uns nicht nachgemessen.

**Ergebnis:** Erst messen, ob die Haken im Graphen überhaupt Shader sind. Dann ein DXMT-Build mit zwei Teilen aus Recall: früh
übersetzen für die erste Runde, lernen und vorab anlegen für die zweite. Den Shader-Pack nur, wenn die Messung ihn verlangt,
denn er kostet auf einem 16-GB-Mac Gigabytes Arbeitsspeicher.

## Was Nightforge heute hat

| Schicht | Ort | Inhalt | Hier |
|---|---|---|---|
| Übersetzung | `Engine.shaderCache`, `~/Library/Caches/Nightforge/dxmt/shaders_320.db`, alle Spiele in einer Datei | AIR aus airconv, Schlüssel Shader + Variante. Metal muss es noch kompilieren | 20 MB |
| Metals Cache | `$DARWIN_USER_CACHE_DIR/dxmt/<exe>/com.apple.metal`, je Programm, von DXMT selbst gesetzt (`dxgi.cpp`) | fertige GPU-Funktionen | Overwatch 25 MB |

Die zweite Runde ist also schon warm. Recalls Test unter Rosetta, eine kleine Pipeline: 17,7 ms kalt, 1,5 ms aus Metals Cache,
1,1 ms aus einem Archiv. Metals Cache hat hier den Neustart vom 3.11. überlebt. Es fehlt dreierlei: Die erste Runde ist kalt,
niemand legt Pipelines an, bevor ein Frame sie braucht, und nach einem macOS-Update baut nichts den Cache nach.

**Nebenbefund:** `ShaderCaches.folders` kennt `C/dxmt/<exe>` nicht. „Shader löschen“ lässt Metals Cache für DXMT-Spiele stehen,
die angezeigte Größe ist zu klein.

## Was von Recall taugt

Recalls Patches gelten für den Fork `NerRobDog/dxmt` c5dc3a0, 201 Commits nach unserem Pin plus 15 eigene. Probe auf unserem
Stand: Neue Dateien, `cache.c`, `dxmt_tasks.hpp` und `d3d11_shader.hpp` gehen auf; `winemetal_unix.c`, `d3d11_shader.cpp` und
`d3d11_pipeline_cache.cpp` gehen von Hand.

| Teil | Wofür | Urteil |
|---|---|---|
| `pipeline_recipe.*`, `pipeline_cache.*`, `dxmt-shader-pack.patch` (gut 1.800 Zeilen, nur Unix-Seite) | Lernt je Render-Pipeline ein Rezept mit gemessener Bauzeit und die AIR-Bytes; legt beim Start bis zu 128 teure in 10 s vorab an | **Nehmen.** Keine Overwatch-Namen im Code |
| `DXMT_PREPARE_SHADERS` (rund 220 Zeilen D3D11-Schicht) | Übersetzt schon beim Anlegen der Shader, zwei Threads, niedrigste Priorität. Recall: Shader-Warten −69 %, schlimmster Frame 470 → 148 ms (M1 Pro, leere Caches) | **Nehmen, von Hand**, ohne Recalls IR-Freigabe. Nur bis AIR, Metals Schritt bleibt. Braucht Deckel: Es paart jeden Vertex-Shader mit jedem passenden Layout (auf Overwatch zugeschnitten), und seine Listen leeren sich nie |
| `pipeline_warm.m` (Apache-2.0) | Baut aus den Rezepten Metals Cache auf, ohne Wine und ohne Spiel | **Nehmen**, für macOS-Updates. Kostet im Spiel keinen Speicher |
| Echter `hash<ShaderVariant>`, asynchroner sqlite-Schreiber (`cache.c`), `PipelineReady`, `DXMT_SHADER_LOG` | Pin hat `return v.index(); // FIXME`; Schreiben bremst die Compiler nicht mehr; Logbuch für Shader-Wartezeit | **Nehmen** |
| `pipeline_prepare.m`, Archive, `load.json` (der Pack) | Fertige Pipelines im Speicher. Recall: 5,7 GB, bei Maximum 9,6 GB auf 16-GB-Mac. Eine Nutzenzahl gegenüber Metals Cache nennt Recall nicht | **Später**, nur nach Messung, mit festem Budget |
| Canvas, Pacing, Kompression, MetalFX/DLSS, GPU-Fehler, Replay | Kein Shader-Thema | Nicht hier |

Lücke für andere Spiele: Gelernt werden nur Render-Pipelines. Compute und Geometrie/Tessellation bleiben bei Metals Cache.

**Basis bleibt Pin 589adb7**, kein DXMT-Update (384 Commits, vor allem D3D12). **Lizenz:** Recalls DXMT-Patches sind LGPL-2.1+,
ein damit gebautes DXMT also auch auf dem MIT-Pin. `Resources/THIRD_PARTY_NOTICES.txt` und der Lizenzschritt in `graphics.yml`
ändern sich, Recalls `NOTICE` kommt für die Apache-Helfer dazu. Quellen und Patches liegen dem Release schon bei.

## Ablauf in Nightforge

- **Im Spiel:** `DXMT_PIPELINE_CACHE_PATH` zeigt app-weit auf `~/Library/Caches/Nightforge/dxmt-pipelines` und gilt so auch über
  Steam. Zwei Änderungen an Recalls Code: Der Ordner bekommt `<exe>` aus `MTLGetShaderCachePath()`, damit Launcher und Spiel sich
  nicht `write.lock` wegnehmen. `registryID` und macOS-Text fliegen aus dem Ordnerschlüssel: Die ID wechselt bei jedem Neustart,
  und Rezepte hängen nicht von macOS ab.
- **Beim Start:** Bis zu 128 teure Pipelines, höchstens 10 s, im Hintergrund, kein neuer Warteschirm. Anfragen warten bis zur Frist;
  prüfen, dass das in den Ladebildschirm fällt.
- **Nach der Sitzung:** Normal nichts, das Spiel hat seinen Teil schon in Metals Cache gebaut. `pipeline-warm` läuft nur, wenn
  macOS-Build oder GPU nicht passen oder der Cache gelöscht wurde: am Netzteil, niedrige Priorität, über `DetachedProcess`. Es
  endet beim Spielstart und mit der App und macht später weiter.
- **Sicherheit:** Der Helfer läuft in der Wine-Sandbox ohne Netz, denn Rezepte und AIR stammen aus dem Spielprozess.
- **Bedienung:** Keine Einstellung; je Teil ein versteckter Ausweg per `defaults`, wie beim Unity-Helfer.

## Speicherplatz

Hier gemessen, Recalls Ordner `/Volumes/Games/Overwatch2Mac/cache`, Zeitstempel 00:54 bis 00:59: `shaders_320.db` knapp 1 GB,
1.740 Rezepte 6,8 MB, 2.072 AIR 36 MB, keine Archive. Unsere Datei für alle Spiele hat 20 MB. Das Fünfzigfache kommt vermutlich von
`DXMT_PREPARE_SHADERS`, das alles übersetzt, was das Spiel anlegt. Metals Cache: Recall nennt rund 120 KB je Pipeline.

Also: Übersetzungs-Datei je Programm, Deckel 2 GB je Programm für Rezepte und AIR (älteste zuerst), und `ShaderCaches.folders`
bekommt `dxmt-pipelines` und `C/dxmt`.

## Nach Updates

| Ereignis | Folge | Nightforge tut |
|---|---|---|
| Spiel-Update | Schlüssel hängen am Inhalt, Spielversion egal. Nur neue Shader sind einmal kalt | Deckel räumt alte Rezepte weg |
| macOS-Update | Metals Cache leer (Recalls Angabe, hier nicht gesehen), Rezepte gültig | `pipeline-warm` im Hintergrund |
| DXMT-/airconv-Update | Neue AIR, neue Schlüssel, einmal kalt. `kDXMTShaderCacheVersion` (18) hängt auf dem Pin nicht an airconv: von Hand hochzählen | `graphicsSignature` zeigt den Hinweis wie bisher |
| Anderer Mac oder GPU | Gerätename im Schlüssel, neuer Ordner | Nichts |

## Messen gegen Recall

Beide Seiten mit demselben Werkzeug: Metal HUD plus `MTL_HUD_LOG_ENABLED=1` (Werte je Frame) und `MTL_HUD_LOG_SHADER_ENABLED=1`
(Kompilieren), per `launchctl setenv` für die Messung. Vorher prüfen, ob Recall sie durchreicht und wo das Log landet.
Gleicher Mac, Netzteil, gleiche Auflösung und Stufe, gleiches Laufwerk. Übungsbereich, feste Runde, 3 Minuten. Je App drei Läufe:
**A** kalt (alle Caches leer, Recalls vorher sichern), **B** zweiter Lauf, **C** nach Neustart. Zahlen: Frames über 33/50/100 ms je
Minute, schlimmster Frame, 1-%-Low, Anteil der Haken mit Shader-Eintrag im selben Moment.

**Entscheidung:** Liegt in Lauf B weniger als die Hälfte der Haken über 50 ms bei einem Shader-Eintrag, hilft dieser Plan dort
wenig. Dann sind Recalls Wine-Patches dran, die wir nicht haben: `wine-server-registry-save` (0,1 s Pause alle 30 s) und
`wine-ntdll-syscall-log` (Freezes von 150–400 ms). Recalls „95 % weniger Stotterer“ nennt Shader und Wine-Fixes zusammen.

## Stufen

| Stufe | Inhalt | Braucht |
|---|---|---|
| 0 | Messung Nightforge heute gegen Recall | Keinen Build; der Nutzer spielt |
| 1 | `dxmt-0.80-shader-prep.patch` mit allem, was oben „Nehmen“ heißt, Helfer in `graphics.yml`, App-Seite, Recalls `tests/pipeline_cache`. Beide Teile einzeln schaltbar: A/B mit einem Build | graphics-Build und App-Release, Basis `claude/staging-032`, Spieletest mit Korb |
| 2 | Pack mit festem Budget, teuerste Pipelines zuerst (Vorschlag: 1 GB) | Nur wenn Lauf B nach Stufe 1 noch Shader-Haken zeigt. Helfer und App, kein neuer DXMT-Patch |

**Außerhalb:** D3DMetal ist geschlossen, Spiele darauf bleiben draußen. Eine geteilte Liste wie Fossilize bräuchte Server, Opt-in,
Zusammenführen je Spiel-Build und GPU sowie Signaturen. Rezepte wären teilbar; AIR stammt aber aus dem Shader-Code des Spiels und
müsste beim Spieler entstehen.
