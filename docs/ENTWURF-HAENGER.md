# Entwurf: Ein hängendes Spiel von selbst erkennen (0.4.0), Stufe 1: nur messen

Stand 23.11.2026, Zweig `claude/haenger-erkennen-04` (von `claude/staging-035`, 6004b62). Gelesen: die laufende Spielschleife
(`LibraryModel.watchRunningGames`), `GameOverlay`, `GameTest`/`GameTestMeasure`, `CloserLook`, `docs/TODO.md`. Kein Spielstart.

Ziel: Lebt ein Spiel, zeichnet aber nicht mehr oder antwortet nicht, bietet Nightforge später im Overlay „Spiel beenden“ an,
ohne zu raten, wenn ein Ladebildschirm nur lange dauert.

## Kurzfassung

- **Stufe 1 ist gebaut, nur hinter dem Testschalter `gameTest.hangWatch`** (im Release-Bau nicht vorhanden, `release.yml` prüft
  es). Nightforge schreibt dann eine Zeile ins Protokoll, wenn ein Spiel nach der Regel hängt, und eine, wenn es sich wieder
  bewegt. Keine Oberfläche, nichts im Spielprozess.
- **Alle Zeichen kommen von außen**, wie sie jedes Programm sehen darf: CPU-Zeit und gelesene Bytes aus der Abrechnung des
  Kernels, Ton aus Core Audios Prozessliste, Fenster aus der Fensterliste, die App vorn. Für Anti-Cheat-Spiele gilt dasselbe.
- **Die Regel ist vorsichtig:** „hängt“ heißt vorn, Fenster sichtbar, nicht vom Overlay angehalten, und mindestens 30 s
  (beim ersten Start 90 s) fast keine CPU, kein Lesen von der Platte, kein Ton. Ein Spiel, das einen Kern voll dreht, ohne zu
  zeichnen, fängt sie nicht; dafür bräuchte es Bilder (Stufe 2).

## 1. Welche Zeichen es heute gibt

| Zeichen | Woher | Ohne Neues im Spielprozess? | Taugt es? |
|---|---|---|---|
| Bilder (DXMT-Zähler, Metal-HUD-Zeilen, D3DMetal-HUD) | stehen nur bei einem Spieletest oder `gameTest.measurePlay` im Protokoll (HUD-Protokoll bzw. Wine-Kanal) | **nein**: der HUD ist eine Einstellung im Spielprozess, im normalen Spielen aus | Stufe 2, nur wo ohnehin an |
| Vulkan-Layer (`VK_LAYER_NIGHTFORGE_compat`) | nur Vulkan-Spiele | nein, liegt im Prozess | nein |
| „Programm reagiert nicht“ (Kreisel) | macOS sagt es Programmen nicht öffentlich; AX bräuchte „Bedienungshilfen“ und fragt den Prozess selbst | nein (AX fragt die App) | nein. Zudem bedient Wines Hauptthread die Mac-Ereignisse weiter, wenn das Spiel selbst steht: der Kreisel kommt bei Wine-Spielen selten |
| **CPU-Zeit** | `proc_pid_rusage` (Kernel) | **ja** | ja: ein stehendes Spiel rechnet nichts |
| **Gelesene Bytes** | `proc_pid_rusage`, `ri_diskio_bytesread` | **ja** | ja: ein Ladebildschirm liest |
| **Ton** | Core Audio, `kAudioHardwarePropertyTranslatePIDToProcessObject` + `kAudioProcessPropertyIsRunningOutput` (macOS 14) | **ja** | ja: Musik im Ladebildschirm zählt als lebendig |
| **Fenster sichtbar** | `CGWindowListCopyWindowInfo` | **ja** | ja; Ebene 0 **und** Abschirmungsebene (Overwatch zeichnet dort, L2147483628) |
| **Vorn** | `NSWorkspace.frontmostApplication` | **ja** | ja: ein Spiel im Hintergrund darf ruhen |
| **Overlay hält das Spiel** (SIGSTOP) | `GameOverlay.mayHoldGame` | ja (Nightforges eigener Zustand) | ja: dann nie „hängt“ |

Belege aus dem Bestand: Der Spieletest sagte bei Overwatch „hängt ohne Bild“, obwohl DXMT 49 FPS zählte (`docs/TODO.md`): Ein Urteil
über Bilder und Fensterlagen allein irrt. Die Regel unten urteilt deshalb nur, wo das Spiel vorn und sichtbar ist, und nur über
Arbeit, die jeder lebende Prozess macht.

## 2. Die Regel (`Sources/Nightforge/HangRule.swift`)

Eine reine Funktion über die Blicke der laufenden Spielschleife (etwa alle 3 s):

- Beurteilt wird nur der letzte Abschnitt, in dem das Spiel ohne Unterbrechung **vorn**, **sichtbar** und **nicht angehalten**
  war, und erst ab 20 s nach dem Start.
- Zwischen zwei Blicken ist es **ruhig**, wenn: CPU unter 3 % eines Kerns, gelesen unter 256 KB/s, und kein Ton bei beiden.
  Zähler, die zurückgehen (neuer Prozess), zählen nie als Arbeit; ein neuer Prozess beginnt ohnehin von vorn.
- **hängt**, wenn der ruhige Abschnitt mindestens **30 s** dauert, beim **ersten Start** des Spiels (noch keine Spielzeit)
  **90 s**. Sonst „ruhig“, bei Arbeit „beschäftigt“, wo nicht beurteilbar „unbekannt“.
- Ins Protokoll kommt nur der Wechsel: „Hang watch: <Spiel> quiet in front for 30 s (CPU 0.4 %, reads 0 KB/s, sound no):
  would offer Quit Game“ und „Hang watch: <Spiel> moves again after 42 s“. Nur Namen und Zahlen, keine Pfade.

Was „lädt nur lange“ abfängt: Ladebildschirme lesen (Platte) oder übersetzen Shader (CPU), viele spielen Musik; ein erster Start
bekommt die dreifache Zeit; Spiele im Hintergrund, im Overlay angehalten oder ohne Fenster werden gar nicht beurteilt.

Was sie nicht fängt: Ein Spiel, das einen Kern voll dreht, aber nicht mehr zeichnet. Das zeigen nur Bilder (Stufe 2).

Tests: `tests/HangRuleTest` (Regel: ruhig, hängt, erster Start, Laden, Arbeit, Ton, unbekannter Ton, hinten, Pause, ohne Fenster,
zurück nach vorn, zurückgehende Zähler; die Protokollzeilen; die Blicke von außen auf den eigenen Prozess; die Fensterliste mit
Ebene 0 und Abschirmungsebene). Testschalter: `tests/test_release_switches.py` und `release.yml` kennen `gameTest.hangWatch`.

## 3. Messen (der Nutzer oder der Koordinator)

`defaults write io.github.lordhayne.nightforge gameTest.hangWatch -bool true`, Nightforge neu starten, spielen wie immer.
Danach in `wine.log` nach „Hang watch:“ suchen; ausschalten mit `defaults delete io.github.lordhayne.nightforge gameTest.hangWatch`.
Fragen an die Messung:
- Gibt es Zeilen bei Spielen, die nicht hingen (lange Ladebildschirme, Zwischensequenzen ohne Ton, Pausemenüs)? Dann Grenzen anpassen.
- Ein echter Hänger (falls einer vorkommt): kam die Zeile, und wann?
- Wie viel CPU zeigt ein Pausemenü unter Wine und Rosetta? (Die 3 % sind geschätzt.)

## 4. Später: das Angebot im Overlay (zur Wahl, erst Board, dann Bau)

Erst wenn die Messung keine Fehlalarme zeigt:

- **A · Hinweis über dem Spiel:** eine Zeile über `GameHint`, nimmt dem Spiel keine Tasten:
  „<Spiel> reagiert nicht. Ⓑ halten: beenden.“ Nichts geschieht von selbst.
- **B · Overlay öffnet sich von selbst** mit „Spiel beenden“ hervorgehoben, Ⓑ schließt es wieder. Deutlicher, aber es öffnet
  etwas über einem Spiel, das vielleicht doch nur lädt.
- **C · Nur im Overlay:** Öffnet der Spieler das Overlay (L3+R3), steht „Spiel beenden“ oben, mit dem Satz „Das Spiel reagiert
  seit 40 s nicht.“ Nichts erscheint ungefragt.

Vorschlag: C zuerst, A dazu, wenn die Messung sauber ist.
