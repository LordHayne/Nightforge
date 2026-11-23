# Entwurf: Nightforges eigene Bildschirme nur mit dem Controller (0.4.0)

Stand 23.11.2026, Zweig `claude/pad-only-04` (von `claude/staging-035`, e0f84b9). Gelesen: alle Ansichten unter
`Sources/Nightforge`, dazu `InputRouter`, `PadRules`, `PadFocus`. Nichts live geprüft. Steams eigene Fenster stehen in
`docs/ENTWURF-STEAM-PAD.md`.

Entscheidung 1 des Nutzers (22.11.): „Controller-only ist hart: alles muss einwandfrei mit dem Pad gehen.“

## Kurzfassung

- **Fast alles geht schon.** Jede Taste, jeder Schalter und jede Auswahl in Nightforges Ansichten trägt `.padFocus`
  (Prüfung per Skript über alle `Button`, `Toggle`, `Picker`; die Treffer ohne liegen in Bausteinen, deren Aufrufer den Fokus
  setzen, oder haben einen Pad-Weg daneben). Jedes der 21 Blätter hat das × mit Esc (`GlassDialog`, `GlassQuestion`,
  `GlassDialogHeader`), Ⓑ schickt Esc (`InputRouter.press`), also schließt Ⓑ jedes Blatt.
- **Gebaut:** die zwei Textfelder unter Einstellungen › Stores (eigener Wine, Bottles-Ordner) hatten keinen Pad-Fokus; jetzt
  setzt Ⓐ den Cursor hinein wie bei jedem `GlassTextField`. Dazu `tests/test_pad_reach.py`: jedes Textfeld braucht
  `.padFocus`, jedes Blatt etwas, das Esc nimmt. Ein später hinzugefügtes Feld oder Blatt ohne das fällt in der Kette auf.
- **Die echten Lücken brauchen Oberfläche oder liegen außerhalb von Nightforge:** Tippen außerhalb der Suche, Ordnerwahl
  über macOS' Dateifenster, Berichte im Browser, die Anmeldung bei Epic, und macOS' eigene Fragen. Liste zur Wahl unten.

## 1. Bestand

✅ geht mit dem Pad · ⚠️ geht, mit Einschränkung · ❌ braucht Maus oder Tastatur

| Bildschirm | Erreichen | Aktionen | Textfelder | Nur Maus/System | Beleg |
|---|---|---|---|---|---|
| Startseite, Bibliothek, Filter, Sortierung | ✅ | ✅ Ⓐ, ☰, L1/R1, Ⓑ eine Ebene | Suche ✅ (Ⓨ, Pad-Tastatur) | Pfeile der Bühne, Punkte der Tipps: Maus, Pad hat Steuerkreuz bzw. Wechsel von selbst | `HomeStage.swift:269`, `SetupTips.swift:107` |
| Spielkarte: Rechtsklick-Menü, „…“ beim Überfahren | ✅ über das Schnellmenü (☰ halten), gleiche Einträge (`menuActions`) | ✅ | – | Rechtsklick und Überfahren sind nur der Mausweg | `GameMenuViews.swift:20`, `:67`, `GameMenu.swift:147` |
| Spielseite, „Dieses Spiel“, Versionen, Bilder | ✅ | ✅ | – | – | `ThisGameCard.swift`, `GameAbout.swift` |
| Spieloptionen | ✅ | ✅ | ⚠️ Startoptionen: Ⓐ setzt den Cursor, tippen nur mit Tastatur | – | `SettingsViews.swift:315` |
| Einstellungen, alle Reiter | ✅ (Reiter mit L1/R1) | ✅ | ⚠️ Bottles-Ordner, Wine-Pfad: **jetzt** Cursor per Ⓐ, tippen nur mit Tastatur | ❌ „Auswählen …“ öffnet macOS' Ordnerwahl; ❌ „In den Systemeinstellungen bestätigen“ (Anmeldeobjekt), Bluetooth, Bedienungshilfen öffnen Systemeinstellungen | `SettingsView.swift:150`, `:159`, `LibraryModel.swift:6668`, `SettingsView.swift:279`, `:637`, `PadPointer.swift:214` |
| Ersteinrichtung | ✅ | ✅ | – | ❌ Rosetta: macOS fragt das Passwort; Steam-Anmeldung siehe Steam-Entwurf (S1) | `LibraryView.swift:176`, `LibraryModel.swift:422` |
| Anmelden: Epic | ✅ | ⚠️ Ⓐ „Später anmelden“ | ❌ Epics Seite braucht eine Tastatur | – | `SignInStage.swift:133`, `:177` |
| Anmelden: GOG | ✅ | ✅ Handy-Anmeldung (QR), Ⓐ neuer Code | – | – | `PhoneSignInView.swift:47`, `Launchers.swift:500` |
| Anmelden: Battle.net | ✅ | ⚠️ Ⓐ holt das Fenster des Clients | ❌ im Fenster des Clients | – | `Launchers.swift:496` |
| Download-Panel | ✅ | ✅ | – | – | `Downloads.swift` |
| Platz schaffen, Ziel wählen, Verschieben, Laufwerk übernehmen | ✅ | ✅ | – | – | `LibraryView.swift:142`, `DriveViews.swift`, `DriveTakeover.swift:108` |
| Nightforge-Update (Leiste oben) | ✅ | ✅ | – | – | `LibraryView.swift:1178` |
| „Startet nicht?“, Rückblick nach dem Spiel | ✅ | ✅ | – | ❌ „Problem melden“ und „Bericht teilen“ öffnen GitHub im Browser | `ProblemReport.swift:39`, `LibraryModel.swift:6398` |
| Schnellmenü, Später spielen, Ein/Aus | ✅ | ✅ | – | – | `PadRules.swift`, `LibraryView.swift:224` |
| Löschen, Deinstallieren, Windows-Rest entfernen | ✅ | ✅ sichere Antwort vorbelegt | – | – | `LibraryView.swift:253`, `:270` |
| Fehlermeldungen, Rosetta-, GeForce-Now-, Konsolenmodus-Frage | ✅ | ✅ | – | GeForce Now öffnet NVIDIAs Seite | `LibraryView.swift:167`–`:238`, `LibraryModel.swift:3313` |
| D3DMetal holen | ✅ | ✅ in Nightforges Blatt | – | ❌ Apples Seite im Browser (Apple-Konto), ❌ Dateiwahl | `D3DMetalFlow.swift:149`, `:171` |
| Meldungen mit Knopf (Rückgängig, Spielen, Zeigen) | ⚠️ **unbelegt**, ob die Hervorhebung von der Bibliothek dorthin kommt | Knopf trägt `.padFocus` | – | – | `Toast.swift:133`, `LibraryModel.swift:2838`, `:4721` |
| Overlay im Spiel | ✅ L3+R3 | ✅ | – | – | `GameOverlay.swift` |
| Alerts, Kontext von macOS | keine `NSAlert` im Code | – | – | – | – |

## 2. Gebaut (technisch, ohne neue Oberfläche)

- `SettingsView.swift:150`, `:159`: `.padFocus("settings.bottlesRoot")` und `.padFocus("settings.runnerPath")` mit
  `@FocusState`, wie `GlassTextField`.
- `tests/test_pad_reach.py`: jedes `TextField` mit `.padFocus` (Ausnahme: die Suche, dort öffnet Ⓨ die Pad-Tastatur), jedes
  `.sheet` mit etwas, das Esc nimmt. Ohne den Bau oben schlägt der Test an beiden Feldern an (geprüft).

Sonst fand sich nichts der Art „fehlender Fokus, Taste ohne Aktion, Blatt schließt nicht mit Ⓑ“.

## 3. Zur Wahl (neue Oberfläche, erst Board, dann Bau)

1. **Pad-Tastatur für jedes Textfeld**, nicht nur die Suche: Startoptionen, Bottles-Ordner, Wine-Pfad. Die Tastatur gibt es
   (`PadKeyboardView`); offen ist, wie sie über einem Blatt aussieht. Vorschlag: dieselbe Tastatur, unten über dem Blatt, das Feld
   bleibt sichtbar.
2. **Ordnerwahl ohne macOS' Dateifenster** (Bottles-Ordner, D3DMetal-Datei): eine kurze Liste der Orte, an denen Nightforge
   sucht (Laufwerke, Downloads), mit dem Pad wählbar. Das Dateifenster bleibt für die Maus.
3. **Berichte ohne Browser am Sofa:** „Problem melden“ und „Bericht teilen“ zeigen einen QR-Code, der das ausgefüllte GitHub-Formular
   aufs Handy bringt. Der Link enthält schon heute nur die festen Angaben (`ProblemReportText`).
4. **Meldungen mit Knopf:** Erst live prüfen (unten). Kommt die Hervorhebung nicht hin: ein Pad-Weg wie „Ⓧ Rückgängig“ auf der
   Meldung selbst.
5. **Epic-Anmeldung mit dem Pad:** gehört zu `docs/ENTWURF-ANMELDEN.md` (Tastatur auf Epics Seite oder ein Handy-Weg).

Nicht lösbar, nur vorher ansagen: macOS' eigene Fragen (Rosetta-Passwort, Bedienungshilfen, Anmeldeobjekt, Bluetooth-Kopplung,
Mitteilungen). Vorschlag wie im Steam-Entwurf: alle in die Ersteinrichtung bzw. die Konsolenmodus-Anfrage, nie mitten im Spielen.

## 4. Live prüfen (über den Koordinator, vor 16:30)

- Meldung mit Knopf (ein Spiel ausblenden, „Rückgängig“ erscheint): Kommt die Hervorhebung mit dem Steuerkreuz hin, und
  drückt Ⓐ sie, bevor die Meldung geht?
- Einstellungen › Stores › eigener Wine: Ⓐ auf das Feld setzt den Cursor, eine Tastatur tippt hinein, Ⓑ schließt danach das Blatt.
