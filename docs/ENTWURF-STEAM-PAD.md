# Entwurf: Steams Abfragen mit dem Controller (0.4.0)

Stand 23.11.2026, Zweig `claude/steam-dialoge-pad-04` (von `claude/staging-035`). Nur gelesen: Code, Doku, die Steam-Protokolle
dieses Macs (nur Schrittnamen gezählt). Kein Spielstart, kein Steam-Fenster geöffnet.

Entscheidung 1 des Nutzers (22.11.): „Controller-only ist hart: alles muss einwandfrei mit dem Pad gehen, auch Steams Abfragen.“

## Kurzfassung

- Heute geht jede Steam-Abfrage mit dem Pad nur über den **Pad-Zeiger**: Touchpad (DualSense, DualShock 4) oder rechter
  Stick, R2 klickt. Das Klicken in Steams Fenster braucht macOS' Erlaubnis „Bedienungshilfen“, und die lässt sich nur mit
  Maus oder Trackpad erteilen. Ohne sie sagt der Vorhang „Antworten mit Maus oder Trackpad“.
- **Ⓐ und Ⓑ tun bei Steams Fragen nichts.** `pad-answer.exe` (G4) drückt nur in Fenstern des Spiels (Klasse `#32770`) und
  lässt Steams Prozesse ausdrücklich aus. Auf dem Vorhang ist Ⓑ nur der Ausweg „Hängt es?“ (`PadRules.back`, `curtain`).
- **Tippen geht nirgends mit dem Pad in Steams Fenstern** (Passwort, Steam-Guard-Code). Die Pad-Tastatur (G1) schreibt nur
  in Nightforges eigene Felder. Bei der Anmeldung bleibt der QR-Code mit dem Handy der Weg ohne Tastatur.
- Gebaut wurde in diesem Schritt **nichts**: Der einzige Weg ohne neue Oberfläche (Tasten in Steams Fenster, Weg B) hängt an
  einer Frage, die nur eine Probe mit echtem Steam-Dialog beantwortet. Alles andere braucht neue Oberfläche oder eine
  neue Erlaubnis-Frage. Siehe „Zur Wahl“ unten.

## 1. Welche Steam-Fenster vor dem Spieler auftauchen können

Belegt heißt: im Code behandelt, in einem Protokoll gesehen oder in einer Live-Runde notiert. Die Schrittnamen stammen aus
Steams `console_log.txt` („waiting for user response to …“). Gezählt auf diesem Mac: Windows-Steam `ShowInterstitials` 10,
`CreatingProcess` 10 (beide Routine, ohne Fenster); Steam für Mac zusätzlich `ShowGameArgs` 1. In der Doku: `ShowEula` 8,
`CloudSync` 2, `SynchronizingCloud` 1.

| # | Fenster | Steam | Wann | Beleg | Vorhang heute |
|---|---|---|---|---|---|
| S1 | Anmelden (Passwort und QR-Code) | beide | erster Start, abgelaufene Anmeldung | `LaunchPhase.signInInSteamWindow`, `.signInAgain`; `SteamQuestion.signIn` | „In Steams Fenster anmelden“, Hinweis auf den QR-Code |
| S2 | Steam Guard (Code aus Mail oder App) | beide | Anmeldung ohne Handy-Bestätigung | `docs/recherche/updates.md`, `docs/ENTWURF-ANMELDEN.md` | wie S1 |
| S3 | Lizenz (EULA) | beide | erster Start, bei 12 von 24 Spielen | `ShowEula`, `SteamLicence` (9.11.) | „Die Lizenz, nur einmal“, Zeiger-Leiste |
| S4 | Startoption wählen | beide | Spiele mit mehreren Startwegen (Drawful 2) | `ShowGameArgs`, Steam für Mac 22.11. | „Wie das Spiel starten soll“ |
| S5 | Cloud: Abgleich fehlgeschlagen („Unable to Sync“) | beide | Netz weg, Steam-Server | `CloudSync`; Valheim 22.11. 14:55 (`docs/AUDIT-LADESCREEN.md` C3) | „Welcher Spielstand zählt“ |
| S6 | Cloud: Spielstände widersprechen sich | beide | zwei Macs, Spiel lief woanders | `SynchronizingCloud`; `MacSteam.waitsInDialog` | wie S5 |
| S7 | Spiel läuft auf einem anderen Gerät (Sitzung übernehmen) | beide | zweites Gerät | `MacSteam.waitsInDialog` („another session to kick“); Schrittname nicht belegt | „Steam fragt etwas“ |
| S8 | Installieren (Ort und Laufwerk wählen) | beide | Demo ohne Lizenz, `steam://install/<id>` | `MacSteam.ask`, `docs/TODO.md` (Demo, nicht live geprüft) | kein Vorhang, Glas-Dialog davor |
| S9 | DLC- oder Store-Fenster über dem Spiel | Windows-Steam | Spielmenü öffnet Steam (Tomb Raider, 8.11.) | `reachWindowOverGame`, `PadPointerRules.handsFront` | kein Vorhang, das Fenster bekommt die Front |
| S10 | Offline-Hinweis (Steam braucht Verbindung) | beide | ohne Netz | `docs/ROADMAP.md` (Offline-Modus), nicht im Protokoll | „Steam fragt etwas“ |

Zum Vergleich, **keine Steam-Fenster**, aber auf demselben Weg zum Spiel:

| # | Fenster | Heute mit dem Pad |
|---|---|---|
| W1 | Frage des Spiels selbst (Treiberwarnung, Wukong) | Ⓐ Standardtaste, Ⓑ Abbrechen (`pad-answer.exe`, G4); sonst Hinweis auf den Zeiger |
| W2 | Unitys „Play!“-Fenster | drückt Nightforge selbst (`UnityDialog`) |
| W3 | macOS' eigene Fragen (Bedienungshilfen, Mitteilungen) | **gar nicht**: macOS nimmt keine erzeugten Eingaben an |

## 2. Was heute mit dem Pad geht

Gelesen in `InputRouter` (Ⓐ/Ⓑ), `PadRules.back`, `SteamLicence.answering`, `GameBackdrop.SteamQuestionFrame`, `PadPointer`, `pad-answer.c`.

| | Ⓐ | Ⓑ | Pad-Zeiger | Tippen |
|---|---|---|---|---|
| S1, S2 Anmelden | nichts | nichts | ja, mit Erlaubnis | **nein** (QR mit dem Handy geht) |
| S3 Lizenz | nichts | Ausweg „Hängt es?“, nicht „Ablehnen“ | ja, mit Erlaubnis; Leiste zeigt Touchpad bzw. Stick + R2 | – |
| S4–S7, S10 | nichts | wie S3 | ja, mit Erlaubnis; dieselbe Leiste | – |
| S8 Installieren | nichts | nichts | ja, mit Erlaubnis; Auswahllisten in Steam sind klein | – |
| S9 Fenster über dem Spiel | nichts | nichts | ja: das Fenster bekommt die Front, sobald ein Finger aufsetzt | – |

Die Leiste unten auf dem Vorhang gilt seit 0.3.5 für alle Fragen, nicht nur für die Lizenz (`LibraryModel.questionLook`). Die Lücke
aus `docs/ENTWURF-LADESCREEN-KONSOLE.md` §5 ist damit zu.

**Die eine harte Grenze:** Ohne „Bedienungshilfen“ kommt kein Klick des Zeigers in Steams Fenster an (`PadPointerAccess`). Die
Erlaubnis selbst ist eine macOS-Frage (W3) und nur mit Maus oder Trackpad zu erteilen. Für „Controller-only“ muss sie also
vorher eingeholt werden, sonst bleibt jede Steam-Frage eine Mausfrage.

## 3. Wege

**A · Pad-Zeiger überall (heute), Erlaubnis bei der Einrichtung.**
Funktioniert für jedes Fenster beider Steams, ohne Steam-Wissen. Fehlt: die Erlaubnis muss vorher da sein; Ⓐ/Ⓑ fühlen sich
nicht nach Konsole an; kleine Knöpfe am TV. Aufwand für den Erlaubnis-Schritt: S, braucht Oberfläche (Einrichtung, Konsolenmodus-Anfrage).

**B · Tasten statt Zeiger im Windows-Steam, innerhalb von Wine.**
`pad-answer.exe` bekommt einen zweiten Teil: Steht ein Steam-Fenster (steamwebhelper) vorn in der Wine-Sitzung, schickt es
per `SendInput` Enter (Ⓐ), Esc (Ⓑ) oder Tab/Umschalt-Tab (Steuerkreuz). Das läuft in Wine, also **ohne macOS-Erlaubnis**, wie G4 heute.
- Offen, nur mit einer Probe zu klären: Nehmen Steams Dialoge (CEF, React-Oberfläche) Enter, Esc und Tab an, und ist der Fokus
  sichtbar? **[Vermutung]**: ja, die Desktop-Oberfläche hat Tastatur-Navigation, belegt ist es hier nicht.
- Ⓑ = Esc schließt bei der Lizenz mit „Ablehnen“; der Start endet dann. Das ist die Antwort des Spielers, Nightforge antwortet nie
  selbst (Regel aus `SteamQuestion`).
- Nur Windows-Steam. Steam für Mac bräuchte dafür `CGEventPost` in ein fremdes Programm, also wieder die Erlaubnis (Weg C).
- Aufwand M; mingw-w64 ist auf diesem Mac da (`build.sh` baut `pad-answer.exe` selbst).

**C · Steam für Mac: Weg B geht dort grundsätzlich nicht.** Steam für Mac ist kein Wine-Programm. Seine Fenster gehören
„Steam Helper“ (`com.valvesoftware.steam.helper`, Chromium), einem gewöhnlichen Mac-Prozess (`MacSteam.helperBundleID`). Es gibt
keine Wine-Sitzung, in der ein Programm wie `pad-answer.exe` mit `SendInput` stehen könnte; Win32-Nachrichten erreichen es nicht.
Jeder Tastendruck von außen ist ein macOS-Ereignis, und macOS lässt ein Programm in fremde Apps nur mit der Erlaubnis
„Bedienungshilfen“ schreiben (dieselbe Prüfung wie für die Zeiger-Klicks: `CGPreflightPostEventAccess`, `PadPointerAccess`).
Was in Frage kommt, alles nur **mit** dieser Erlaubnis:

| Weg | Wie | Dafür | Dagegen |
|---|---|---|---|
| C1 · Taste an die App vorn | `CGEvent(keyboardEventSource:…)` mit Esc, Tab, Enter, `.post(tap: .cghidEventTap)`, wie heute die Klicks (`PadPointer.swift:282`). Vorher bekommt Steam Helper die Front (`MacSteam.comeForward`). | kleinster Bau, dasselbe Muster wie der Zeiger | geht an die App vorn: hat in dem Moment etwas anderes die Front, landet die Taste dort. Vor jedem Druck prüfen, dass Steam Helper vorn ist |
| C2 · Taste an einen Prozess | `CGEvent.postToPid(_:)` an Steam Helper | trifft nur Steam, auch wenn die Front kurz wechselt | Chromium nimmt Tasten oft nur im aktiven Fenster an **[Vermutung]**; Probe nötig |
| C3 · Knopf über die Bedienungshilfen-Schnittstelle | `AXUIElement`: Knopf im Fenster suchen und mit `AXPress` drücken | Ⓐ träfe den richtigen Knopf, nicht nur „Enter“ | Chromium gibt seinen Baum erst auf Anfrage frei (`AXManualAccessibility`); Knöpfe nur am Text erkennbar, und der ändert sich mit Sprache und Steam-Version. Viel Steam-Wissen, zerbrechlich |
| C4 · AppleScript „System Events“ | `keystroke` | – | braucht zusätzlich „Automation“, also eine zweite macOS-Frage. Nicht empfohlen |

Dazu der Weg ohne Fenster, wo es ihn schon gibt: Steam für Mac startet mit `-applaunch` die erste Startoption, ohne zu fragen
(`MacSteam.applaunch`). Die Lizenz geht dort nach dem Ja in derselben Sekunde weiter (`SteamLicence`, 5 von 5).

**Folgerung:** Für Steam für Mac ist die Erlaubnis aus Punkt 1 (Abschnitt 4) die Voraussetzung für alles. Mit ihr klickt der
Zeiger schon heute. C1 bringt zusätzlich Ⓑ = Esc und das Steuerkreuz = Tab, ohne Zeiger. Sinnvoll erst, wenn Probe B im
Windows-Steam zeigt, dass Steams Dialoge Esc und Tab überhaupt annehmen: Beide Steams nutzen dieselbe Oberfläche (Chromium,
React), das Ergebnis gilt also wohl für beide **[Vermutung]**. Ohne die Erlaubnis bleibt bei Steam für Mac nur die Maus.

**D · Steams eigene Controller-Bedienung (Big Picture, Steam Input).** Dort sind alle Dialoge für das Pad gemacht. Dagegen:
Steam müsste das Pad sehen und reicht es dann doppelt an Spiele weiter; die PS-Taste wurde bewusst von Big Picture getrennt
(`docs/TODO.md`, SteamGuideButton); Big Picture übernimmt den Bildschirm. Nicht empfohlen.

**E · Fragen vermeiden oder in Nightforge stellen.**
- S4 Startoption: Nightforge fragt in seiner eigenen, pad-fähigen Auswahl und startet die gewählte Option direkt. Braucht
  Oberfläche (Board) und das Wissen, welche Optionen Steam kennt (appinfo `config/launch`).
- S5/S6 Cloud: Nightforge kann nie wählen, welcher Spielstand zählt (Regel). Es kann nur vorbeugen (Abgleich abwarten, wie
  `savingToCloud`) und die Frage gut sichtbar machen.
- S3 Lizenz: muss der Spieler in Steam beantworten. Nightforge sagt vorher an, dass sie kommt (`SteamLicence.stillOpen`).
- S1/S2 Anmelden: der QR-Code mit dem Handy als erster Vorschlag (`PhoneSignIn`), wie im Entwurf zum Ladebildschirm.

## 4. Zur Wahl (der Nutzer entscheidet, dann wird gebaut)

1. **Erlaubnis „Bedienungshilfen“ in die Konsolenmodus-Anfrage** (Entscheidung 3 des Nutzers): einmal mit Maus oder Trackpad,
   danach klickt der Pad-Zeiger überall. Ohne das bleibt „Controller-only“ bei Steams Fragen unerreichbar. *Braucht Oberfläche: Board.*
2. **Probe zu Weg B** (ohne Oberfläche, ohne Spielstart): ein Steam-Fenster mit Frage öffnen, z. B. `steam://install/<Demo>`
   oder die Startoption von Drawful 2, und von Hand `pad-answer.exe` mit Enter/Esc/Tab schicken. Wirkt es, wird B gebaut:
   Ⓐ/Ⓑ und Steuerkreuz bei Steams Fragen im Windows-Steam, die Leiste nennt dann Ⓐ und Ⓑ statt des Zeigers.
   *Braucht einen Neustart von Steam, also über den Koordinator.*
3. **Leiste ohne Erlaubnis:** statt „Mit Maus oder Trackpad antworten“ ein Satz, der sagt, was einmal nötig ist. *Text, als Vorher/Nachher zur Wahl:*
   - Vorher: „Antworten mit Maus oder Trackpad“
   - Nachher (Vorschlag): „Einmal mit der Maus erlauben, dann geht es mit dem Controller: Einstellungen › Controller“
4. **Startoption in Nightforge** (Weg E, S4): nur, wenn 2 nicht reicht. *Board.*
5. **Tippen in Steams Fenster** (S1/S2): die Pad-Tastatur könnte bei erteilter Erlaubnis in Steams Feld schreiben. Bis dahin der
   QR-Code. *Board, später.*

## 5. Live-Proben (über den Koordinator, nie ab 16:30)

- Probe B wie unter 4.2. Im Protokoll: Exit-Code von `pad-answer.exe`, ob der Fokus in Steams Fenster sichtbar wandert.
- Pad-Zeiger mit Erlaubnis bei S3 und S4: Trifft R2 auf dem TV die Knöpfe sicher? Wie groß sind sie aus 3 m?
- S7 (zweites Gerät): Schrittname im `console_log.txt` notieren, damit der Vorhang eine eigene Überschrift bekommen kann.
- S8: Erscheint Steams Installationsfenster vor Nightforge, und lässt sich die Laufwerksliste mit dem Zeiger öffnen?
- Steam für Mac, erst nach Probe B und nur mit erteilter Erlaubnis: dasselbe Installationsfenster (`steam://install/<Demo>`),
  Esc und Tab über C1. Schließt Esc es, ist C1 baubar.
