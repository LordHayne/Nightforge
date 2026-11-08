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

- **Im Spiel:** `DXMT_PIPELINE_CACHE_PATH` zeigt app-weit auf `pipelines` in DXMTs Ordner (`Engine.shaderCache`) und gilt so auch über
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
bekommt `C/dxmt`; `Engine.shaderCache` steht dort schon.

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

**Stufe 0 läuft ohne Build und zunächst ohne Recall:** nur Nightforge, kalt und warm. Sie klärt Overwatchs Spitzen und ist zugleich der
Vorher-Wert für erste Runden, möglichst mit einem zweiten Spiel (ABZU); der Nutzen für DXMT-Spiele hängt nicht an Overwatchs Spitzen. `MTL_HUD_LOG_ENABLED=1` schreibt die Frames über
stderr ins `wine.log`. Die Compile-Einträge von `MTL_HUD_LOG_SHADER_ENABLED` waren hier nicht zu sehen (macOS 27, kleines Testprogramm).
Kompilieren misst deshalb ein Beobachter von außen: Rechenzeit von `MTLCompilerService`, Wachstum der Übersetzungs-Datei, dazu die
Zeitstempel der `.reg`-Dateien. Am Testprogramm trennt das sauber: kalt 98 s Compiler und Spitzen um 725 ms, warm 0 s und fast keine.
Aus dem Metal-Cache bediente Pipelines sieht der Beobachter nicht. Werkzeug: Notizen unter `shader-messung/`.

**Ergebnis Stufe 0 (7.11., nur Overwatch, Übungsbereich, ganze Runden):** Kalt 175 s, 27 Frames über 50 ms je Minute, schlimmster 500 ms, 62
von 69 Haken bei Compiler oder Übersetzung, 33 s Compiler. Warm 238 s, 2,3 je Minute, schlimmster 117 ms, 0,7 s Compiler; 10 der 12 Haken
lagen in den ersten 15 s, ohne Compiler. Ein Takt von 20 bis 30 s trat nicht auf, in einem Match ist das aber nicht gemessen. Für Stufe 1
heißt das: Die erste Runde ist die Lücke, die zweite Runde auf derselben Karte schaffen die vorhandenen Caches schon. Früh übersetzen
kommt zuerst. Lernen und Vorab-Anlegen brauchen erst einen Grund aus einer weiteren Messung. Wie viel früh übersetzen bringt, sagt die
Messung nicht, denn Übersetzen und Metals Kompilieren fielen fast immer zusammen.

**Entscheidung:** Liegt in Lauf B weniger als die Hälfte der Haken über 50 ms bei einem Shader-Eintrag, hilft dieser Plan dort
wenig. Dann sind Recalls Wine-Patches dran, die wir nicht haben: `wine-server-registry-save` (0,1 s Pause alle 30 s) und
`wine-ntdll-syscall-log` (Freezes von 150–400 ms). Recalls „95 % weniger Stotterer“ nennt Shader und Wine-Fixes zusammen.

## Grenzen und Anti-Cheat

**Rein lokal:** Nichts wird hochgeladen. Nightforge liefert keine Shader oder Metal-Bibliotheken eines Spiels aus. Nichts hängt sich
ins Spiel oder ändert Spieldateien. Alle Daten liegen in DXMTs Cache-Ordnern.

**Der Fall von 2018:** Im September 2018 wurden Overwatch-Spieler auf Linux mit DXVK gesperrt, die Sperren wurden wieder aufgehoben
([AltChar](https://www.altchar.com/games-news/576591/blizzard-unbans-overwatch-players-who-used-linux-os)). DXVK entfernte seine
Option für asynchrones Kompilieren am 13.9.2018 mit dem Vermerk „Unsafe“ ([Commit](https://github.com/doitsujin/dxvk/commit/922f0382)).
Die Ursache ist nicht belegt: Ein gesperrter Spieler nannte die Option, Phoronix vermutete einen Fehlalarm
([Slashdot](https://tech.slashdot.org/story/18/09/14/2055209/some-linux-gamers-using-winedxvk-to-play-blizzards-overwatch-banned)),
eine Aussage von Blizzard zur Ursache fand ich nicht, und der Commit nennt Overwatch nicht. Geprüft an diesen Quellen; Phoronix selbst
und Rock Paper Shotgun ließen sich nicht lesen. Es bleibt: Eine Änderung an der Grafikschicht kann verdächtig wirken, und messen
können wir dieses Risiko nicht.

**Wo der Entwurf bleibt:** Auf DXMTs Ebene, hinter den D3D11-Aufrufen, die das Spiel selbst macht. Lernen und Vorab-Anlegen laufen auf
der Mac-Seite in `winemetal.so`. Der Helfer ist ein Mac-Prozess und läuft nie neben dem Spiel. Anders als DXVKs Option, die laut
Release 0.51 erst unoptimiert zeichnete und nachoptimierte, gibt es keine vorläufige Pipeline: `GetPipeline` wartet wie heute auf die
fertige, kein Zeichenaufruf fällt aus. Recalls Meldung als RTX 4090 übernehmen wir nicht.

**Was sich für Overwatch ändern kann:**
- **Bytes:** `d3d11.dll` ist ein neuer Build, wie bei jedem DXMT-Update.
- **Threads:** zwei zusätzliche Windows-Threads niedrigster Priorität (`DXMT_PREPARE_SHADERS`).
- **Zeiten:** Shader und Layouts anlegen dauert etwas länger, beim Start warten Pipeline-Anfragen bis zu 10 s, im Spiel weniger Haken.
- **Bild:** gleiche Shader aus dem eigenen Bytecode. Nur `canonical()` legt gleichwertige Varianten zusammen; ein Fehler dort wäre sichtbar.
- **Gleich bleiben:** Adapter, VRAM, Feature-Level, Spieldateien, Spielspeicher.

**Regel:** Erst der Spieletest ohne Overwatch, dann Overwatch nur nach ausdrücklichem OK des Nutzers, weil dabei das eigene Konto auf dem Spiel steht. Jeder
Teil ist je Spiel abschaltbar. Recall macht bei Overwatch dasselbe und erwähnt in seiner Doku keine Sperren; ein Beleg ist das nicht.
`DXVK_ASYNC=1` gilt in Nightforge app-weit. Overwatch steht per Profil auf `dxmt`; zu prüfen ist, dass es nie auf DXVK zurückfällt.

## Stufen

| Stufe | Inhalt | Braucht |
|---|---|---|
| 0 | Messung Nightforge heute gegen Recall | Keinen Build; der Nutzer spielt |
| 1 | `dxmt-0.80-prepare-shaders.patch`: nur früh übersetzen, Standard aus (Stand unten) | graphics-Build und App-Schalter für 0.3.3, Spieletest mit Korb, Overwatch zuletzt und nur mit OK |
| 1b | Lernen und Vorab-Anlegen (`pipeline_recipe.*`, `pipeline_cache.*`), `pipeline_warm`, asynchroner Schreiber (`cache.c`) | Einen Grund aus einer Messung. Laut Stufe 0 ist die zweite Runde schon fast sauber |
| 2 | Pack mit festem Budget, teuerste Pipelines zuerst (Vorschlag: 1 GB) | Nur wenn Lauf B nach Stufe 1 noch Shader-Haken zeigt. Helfer und App, kein neuer DXMT-Patch |

**Außerhalb:** D3DMetal ist geschlossen, Spiele darauf bleiben draußen. Eine geteilte Liste wie Fossilize gehört nicht zu diesem Plan.
Sie bräuchte Server, Opt-in, Zusammenführen je Spiel-Build und GPU, Signaturen und eine rechtliche Prüfung. AIR stammt aus dem
Shader-Code des Spiels und dürfte nicht mitreisen. Einstieg: Recherche `hermes/queue-032/shader-sharing.md`, Quellen großteils ungeprüft.

## Stufe 1: Stand 8.11.2026

**Ergebnis:** `engine/patches/dxmt-0.80-prepare-shaders.patch` übersetzt die Shader eines Spiels, sobald es sie anlegt, in zwei Hintergrund-Threads.
Der Patch ändert nur `d3d11.dll`. Ohne `d3d11.prepareShaders` in `dxmt.conf` oder `DXMT_PREPARE_SHADERS` (geht vor, `0` schaltet aus) läuft alles wie heute. Gebaut wurde er zur Probe lokal; in einem Spiel lief er noch nicht, und einen Workflow-Lauf gab es nicht.

**Was früh übersetzen kann und was nicht:** Es erzeugt AIR im vorhandenen Cache (`Engine.shaderCache`) und spart damit airconv in der Spielrunde. Metals eigenes Kompilieren beim ersten Zeichnen bleibt. In Stufe 0 maß der
Beobachter vor allem dieses Kompilieren. Wie viel die erste Runde gewinnt, zeigt erst die Messung unten.

### Recalls Patches einzeln

Stand Recall v1.6.3. Basis bleibt Pin 589adb7, die 201 Commits des Forks kommen nicht mit.

| Patch, Teil | Urteil |
|---|---|
| `dxmt-v1-performance.patch`: `DXMT_PREPARE_SHADERS`, Vorhersage der Varianten, `SetCacheOnly`, `canonical()` | Übernommen, mit den Änderungen unten |
| `dxmt-v1-private.patch`: `task_scheduler` mit Grenze und Priorität samt Reparatur beim Beenden, echter `hash<ShaderVariant>`, Scheduler nach den Objekten, die er braucht | Übernommen |
| `dxmt-v1-private.patch`: `PipelineReady`, `DXMT_SHADER_LOG`, IR-Freigabe | Nicht nötig für früh übersetzen; Pin hat keine IR-Freigabe, also ist `handle()` immer gültig |
| `dxmt-v1-private.patch`: asynchroner Schreiber (`cache.c`) | Vertagt: Unix-Seite, bräuchte Build mit Metal-Compiler. Ersatz im Patch: die Hintergrund-Threads halten die Cache-Sperre mit hoher Priorität. Erst nehmen, wenn die Messung Wartezeiten beim Schreiben zeigt |
| `dxmt-v1-private.patch`: Lernen und Vorab-Anlegen (`pipeline_recipe.*`, `pipeline_cache.*`) | Vertagt, siehe Stufe 1b |
| `dxmt-shader-pack.patch`, `pipeline_warm.m` | Vertagt, siehe Stufen 1b und 2 |
| `dxmt-metalfx-upscaling.patch` (DLSS meldet eine RTX 4090) | **Ausgeschlossen:** falsche Hardware |
| Rest von `dxmt-v1-*`, `dxmt-gpu-errors.patch`, `dxmt-portable-metal.patch`, alle `wine-*` | Kein Shader-Thema |

### Änderungen gegenüber Recall

- **Sample Mask bleibt in der Variante.** Recall setzt sie zurück, wenn der Shader kein `oMask` schreibt. In `SM50Compile` (`src/airconv/dxbc_converter.cpp:460`, gleicher Code auf dem Fork) bekommt aber auch so ein Shader die Maske als Coverage-Ausgabe. Metal hat keine eigene Sample Mask. Recalls Rücksetzen hätte Spiele mit eigener Maske also falsch gezeichnet.
- **Deckel je Lauf:** 65.536 Varianten und 1 GB AIR. Dazu höchstens 16 Layouts je Signatur und 1.024 Vertex-Shader je Layout, damit `CreateInputLayout` den Spiel-Thread nicht aufhält. Recall hat keine Deckel, sein Cache lag hier nach einer kurzen Sitzung bei knapp 1 GB.
- **Compute-Shader kommen dazu:** Sie haben genau eine Variante, also trifft die Vorhersage immer.
- **Wert 2 des Schalters:** `DXMT_PREPARE_SHADERS=2` bereitet Pixel-Shader zusätzlich für 8-Bit-Ziele vor. Recalls Vorhersage (Wert 1) nimmt immer „kein 8-Bit-Ziel“ an; das passt zu Unreal-G-Buffern schlecht.
- **Aus heißt aus:** Ohne Schalter gibt es keine Threads und keine `canonical()`-Zusammenlegung.
- **Log für die Messung:** Eine Zeile je 256 gezeichneter Varianten (`[nightforge-dxmt] prepare: …`): wie viele rechtzeitig fertig waren und wie viele noch in der Warteschlange lagen.

### Bauen

- **Offizieller Weg:** `graphics.yml` wendet `engine/patches/dxmt-*.patch` schon an, in Namensreihenfolge; der Patch geht auf einem frischen Pin mit den vorhandenen zusammen auf. Lauf auf einem Zweig (nur nach Push): `gh workflow run graphics.yml --ref <zweig>`, er baut und veröffentlicht nichts. Ein Merge nach `main` löst den Bau und ein neues Graphics-Release aus.
- **Lokal vollständig (seit 8.11., nur für Versuche):** `scripts/build-dxmt-local.sh <ref>` baut mit Xcode 27.2 über `DEVELOPER_DIR` wie `graphics.yml`, einschließlich `winemetal.so`. Was zu Spielern geht, kommt weiter aus dem GitHub-Bau.
- **Lokale Probe, nur `d3d11.dll`:** gebaut mit mingw 16.2 und meson, mit Stellvertretern für `xcrun`, `winebuild` und `winecrt0`. Die eingebettete Metal-Bibliothek (152.339 Byte) stammt aus der ausgelieferten DLL. Importe gleich der ausgelieferten, 32-Bit-Objekte übersetzen. Dieser Weg dient nur dem Prüfen und der Messung, nicht dem Release.

### Lizenz: vom Nutzer freigegeben (8.11.)

Siehe `docs/ENTSCHEIDUNG-DXMT-LGPL.md`: Pflichten, was öffentlich würde, was unberührt bleibt. Auf dem Zweig sind `graphics.yml` und `Resources/THIRD_PARTY_NOTICES.txt` schon angepasst.

### Messplan (späterer Beleg, kein Tor für den Merge)

Vor dem Merge reicht der Kurztest (`ablauf.sh test`, rund 6 Minuten): Startet ABZU, sieht es normal aus, läuft der Schalter. Ablauf und Werkzeug: Notizordner `shader-messung/SCHRITTE.md`, ein Befehl (`ablauf.sh`), rund 40 Minuten, der Nutzer spielt.

ABZU, dieselbe Probe-DLL, Schalter abwechselnd aus und an, je Block eine kalte und eine warme Runde von 4 Minuten. `vergleich.py` nennt je Runde Frames über 33/50/100 ms je Minute, schlimmsten Frame, 99. Perzentil, Compiler-Sekunden, Wachstum der Übersetzungs-Datei und die Trefferquote.

**Gewinn belegt**, wenn jede kalte Runde mit Schalter mindestens 25 % weniger Frames über 50 ms je Minute hat als das Mittel ohne, der schlimmste Frame höchstens 10 % steigt und die warme Runde nicht schlechter wird (Grenze: +20 % plus 1 je Minute). Overwatch folgt nur mit ausdrücklichem OK des Nutzers.

### Was noch fehlt

- Probe in einem Spiel, Workflow-Lauf, Spieletest mit Korb.
- Einschalten (Beschluss 8.11., erst nach dem Kurztest bei Spielern): `writeGameConfigs` schreibt `d3d11.prepareShaders = 1` für alle DXMT-Spiele außer Overwatch und außer Spielen mit Anti-Cheat (`ShaderCaches.hasAntiCheat`: `antiCheat` oder `antiCheatOnline` im Profil, auch leer, Sperrliste des Stores, oder EasyAntiCheat/BattlEye im Spielordner; Entscheidung des Nutzers 8.11.). Ausweg ohne Schalter in der App: `defaults write io.github.lordhayne.nightforge dxmtEarlyShaders -bool false`. Eine ältere `d3d11.dll` speichert die unbekannte Zeile nur und fragt sie nie ab.
- Die gemeinsame Übersetzungs-Datei geht vor einem Spielstart weg, wenn sie 4 GB überschreitet (`ShaderCaches.limitTranslations`). Ein Deckel je Programm fehlt.
