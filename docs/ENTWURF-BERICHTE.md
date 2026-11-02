# Entwurf: Mac-Wissen aus Quellen und eigenen Berichten

Stand 2.11.2026, Zweig `claude/compat-db-bce7dc`. Gebaut sind die Teile 1–3, Teil 4 ist ein Entwurf.

Wunsch des Nutzers (2.11.): „Wir sind noch immer an einem Punkt, an dem wir ein neues Spiel laden und wieder auf
neue Fehler stoßen …“ Ziel: Ein neues Spiel startet beim ersten Mal auf dem richtigen Weg, statt live kaputt
gefunden zu werden. Beispiel Control: DX11 stürzt auf DXMT und DXVK ab, alle Mac-Quellen sagen DX12 mit D3DMetal.

## 1. AppleGamingWiki → `profiles/agw.json` (gebaut)

- `scripts/fetch-agw.py` liest jede Nacht die Tabelle „macOS Compatibility“ aller AGW-Seiten (rund 1.900).
  MediaWiki-API, eigener User-Agent mit Repo-Adresse, höchstens 1 Anfrage pro Sekunde, `maxlag`, etwa 45 Anfragen.
  robots.txt erlaubt alles (`Allow: /`, Content-Signal `search=yes, ai-train=no`); eine API-Regel hat das Wiki nicht.
- Je Spiel und Weg (nativ, Rosetta, CrossOver, Wine/GPTK): Bewertung, gekürzte Notiz, und was die Notiz und ihre
  `{{Refdevice}}`-Berichte nennen: CrossOver-/GPTK-Version, Grafikweg, DirectX-Version, Chip, Datum. Nie die
  Namen der Berichtenden.
- IDs: aus der Infobox (`steam appid`, `gogcom id`). Über die Hälfte der Seiten hat keine Infobox; deren Titel sind
  PCGamingWiki-Titel, und Wikidata (CC0) kennt dazu die Steam-ID (eine SPARQL-Abfrage). „…side“-Felder werden
  ignoriert: Viele Seiten tragen dort noch das `10` (Counter-Strike) aus der Musterseite.
- Ergebnis 2.11.: 1.888 Seiten, 1.389 Spiele (800 über Wikidata, 74 davon über einen lockeren Titelvergleich, in
  der App als „vielleicht eine andere Ausgabe“ markiert), 154 Grafik-Hinweise.
- Lizenz: CC BY-NC-SA 3.0, eigene Datei neben dem GPL-Code, `profiles/LICENSE-applegamingwiki`, Hinweis in
  `THIRD_PARTY_NOTICES.txt`. **Nicht** in `profiles.json` (dort nur BSD/MIT/eigene Daten), **nicht** in der App
  oder im DMG: Die App lädt die Datei von `main` (`NightforgeAGWURL`) und merkt sich die letzte.
- Workflow: eigener Schritt „Fetch AppleGamingWiki“ in `profiles.yml` (nicht bei Pull Requests,
  `continue-on-error`); schlägt das Skript fehl (Quelle weg, Format geändert, weniger als 1.000 Spiele), bleibt die
  alte Datei. Der Commit-Schritt nimmt `agw.json` mit.

### Wann es einen Hinweis gibt (`hint`)

Nur wenn er klar ist:

1. Genau ein Grafikweg wird in den Wegen CrossOver/Wine genannt, die „perfect“ oder „playable“ sind.
2. Kein Satz nennt ihn negativ: kein „crash“, „black screen“, „off“, „glitch“ … innerhalb von 5 Wörtern, und nicht im
   selben Satz wie ein zweiter Grafikweg (Vergleich).
3. Kein schlecht bewerteter Weg nennt ihn.
4. DXVK zählt nur aus CrossOver 25 oder neuer: Vorher gab es kein DXMT, „DXVK an“ hieß dort nur „besser als WineD3D“.
5. `profiles/mac.json` gewinnt immer: Hat unser Profil einen Grafikweg, gibt es keinen Hinweis.

### Was die App damit macht

- **Startweg** (`LaunchHealth.hinted`): Der Hinweis kommt nur an die erste Stelle, wo er zum Spiel passt.
  - D3DMetal: bei DX11-Spielen (mit oder ohne DX12-Build) und Spielen ohne erkannte API, wenn D3DMetal eingerichtet
    ist und Nightforge keinen DX11-Schalter für die Engine kennt (Unreal und Unity bleiben bei gemessenem `-dx11` auf
    DXMT). Seit de1f146 ist D3DMetal für DX11 ohnehin der letzte Weg; der Hinweis holt ihn nach vorn:
    D3DMetal → DXMT → DXVK. Das ist der Fall Control (DX11-Build läuft nur auf D3DMetal, live 2.11.).
  - DXMT oder DXVK: bei DX11-Spielen an die erste Stelle.
  - Ein Profil mit Grafikweg gewinnt. Ein Spiel, das auf einem **bestätigten** Weg der Liste ohne Hinweis läuft,
    behält sie. Eins, das noch sucht (z. B. vor dem Hinweis gestartet), nimmt die Liste mit Hinweis.
    „Am kompatibelsten“ setzt den Hinweis an die erste Stelle wie ein Profil.
  - Beim allerersten Start nach der Einrichtung wartet der Start auf den laufenden Download von `agw.json`, damit
    schon dieser Start den Hinweis hat.
- **Spielseite**: Abschnitt „Was andere berichten“ unter „Über das Spiel“: „Laut AppleGamingWiki:“, je Weg die
  Bewertung (farbig, mit Wort), Version · Grafikweg · DX · Chip · Jahr, die englische Notiz (2 Zeilen, voll beim
  Darüberfahren), Herkunft mit Lizenz, Knöpfe zu AppleGamingWiki, CodeWeavers und MacGamingDB. Die Karte „Dieses
  Spiel“ sagt „Noch kein Profil – zuerst D3DMetal, wie im AppleGamingWiki berichtet“.
- **Plakette, auch vor dem Download**: Ein Spiel, das sonst nichts bewertet, bleibt „Noch nicht getestet“, die
  Erklärung sagt aber „Laut AppleGamingWiki: CrossOver: perfekt, …“ – oder ehrlich „Laut AppleGamingWiki läuft es über
  CrossOver und Wine schlecht (…) – hier vielleicht auch nicht.“
- **Problembericht**: Die Grafik-Zeile nennt den Hinweis („D3DMetal first from AppleGamingWiki“).
- Negatives sperrt nie. Eine fremde Bewertung ändert nie Registry, Startoptionen oder Dateien.

Offen: Signatur. `agw.json` kann nur die Reihenfolge bekannter Wege und Text ändern, deshalb prüft die App heute
keine Signatur. Sobald `claude/signed-updates` gemergt ist, kann `sign-lists.sh` die Datei mitsignieren und
`AGWStore.refresh` dieselbe `Signature.fetch` nutzen (zwei Zeilen).

## 2. „Wie lief es?“ nach dem Spiel (gebaut)

- „Willkommen zurück“ hat drei Knöpfe: **Lief gut**, **Mit Problemen** (dann die Chips wie bisher), **Startet
  nicht**. Gespeichert wird lokal (`rating.<Spiel>` in den Einstellungen), jetzt mit dem Weg, auf dem es lief
  (`LaunchAttempt.id`, z. B. `dxmt -dx11`, `d3dmetal`, oder `mac`).
- „Startet nicht“: Plakette „Läuft nicht auf dem Mac“ mit „Du hast gesagt, es startet nicht.“; bei „Automatisch“
  nimmt der nächste Start den nächsten Weg (`LaunchHealth.advance`), wie nach einem Start, der sofort endete.
- Danach erscheint **Bericht teilen …**. Es öffnet im Browser das GitHub-Formular
  `.github/ISSUE_TEMPLATE/compat-report.yml`, vorausgefüllt mit festen Werten: Spiel, Store und ID, Ergebnis
  (`good`/`problems`/`no-start`), Weg, Chips, Nightforge-Version, Voreinstellung, Engine-Bauteile, Chip, macOS.
  Keine Pfade, Kontonamen, Startoptionen oder Logs; jeder Wert geht trotzdem durch `GameLog.redacted`. Abschicken
  muss der Nutzer dort selbst; sein GitHub-Name steht dann am Bericht (steht im Tooltip).
- Das Formular verlangt das Kästchen „unter CC0“, damit wir die Berichte auch an AGW/MacGamingDB weitergeben dürfen.
- Vor dem ersten echten Bericht im Repo: Label `report` anlegen (sonst setzt GitHub es nicht). Prüfen, dass der
  alte Problembericht-Link (`issues/new?title=…&body=…`) mit einem Vorlagen-Ordner weiter ein leeres Issue öffnet.

## 3. Abdeckung (gebaut)

`scripts/mac-coverage.py` schreibt `docs/recherche/mac-abdeckung.md`: die 200 meistgespielten Steam-Spiele mit
Mac-Version, Anti-Cheat, eigenem Test und AGW. Stand 2.11.: 51 Spiele ohne jede Mac-Angabe, 26 davon in den Top 100 –
dort lohnt sich Testen am meisten.

### Testkorb für den nächtlichen Spieletest

„Ich hab ja nicht alle Games gekauft“ (Nutzer, 2.11.): `scripts/test-basket.py` ordnet die Spiele ohne verlässliche
Mac-Daten in vier Körbe – **im Besitz** (Steam über `tests/CatalogProbe/run.sh <Steam> --json`, Epic und GOG aus dem
Support-Ordner, mit Größe und „installiert“), **kostenlos** (Free-to-play ohne Anti-Cheat-Sperre, Steam-Demos der
Top 200, die Benchmarks von Wukong und Monster Hunter Wilds), **Stellvertreter** (je Engine laut Wikidata und
DirectX laut Steam-Anforderungen das am leichtesten testbare Spiel; `standsFor` listet die gedeckten Top-Spiele)
und **nicht testbar** (nur Quellen und Berichte, `coveredBy` nennt einen Stellvertreter). Sortiert nach
Beliebtheit × fehlenden Daten × Download. Die Ausgabe enthält die eigene Bibliothek und liegt deshalb nur lokal im
Notizordner der Sessions (`testkorb.json`, `testkorb.md`), nie im Repo; das Skript verweigert einen Pfad im Repo.

## 4. Berichte → `profiles/reports.json` (Entwurf, nicht gebaut)

### Ablauf

1. **Prüfen** – Workflow `reports.yml`, bei `issues: [opened, edited]` mit Label `report`, nur `issues: write`:
   - liest die `### Feld`-Abschnitte des Formulars;
   - prüft feste Werte: `store` ∈ steam/epic/gog, `store-id` (Steam: Ziffern; GOG: Ziffern; Epic: `[A-Za-z0-9]{1,64}`),
     `result` ∈ good/problems/no-start, `way` gegen `^(dxmt|dxvk|wined3d|d3dmetal)( -[a-z0-9-]+)*$|^mac$`, Chips aus
     der festen Liste, das CC0-Kästchen;
   - Konto mindestens 30 Tage alt (`GET /users/{login}`), höchstens 10 Berichte je Konto und Tag;
   - gültig: Label `report:valid`, Kommentar „Danke“, schließen (die Issue-Liste bleibt sauber);
     ungültig: Kommentar mit dem Grund, Label `report:invalid`, schließen.
   - Auffälliges an den Maintainer statt automatisch: „good“ bei einem Spiel mit Anti-Cheat-Sperre, „no-start“
     bei einem Spiel in `mac.json`.
2. **Zählen** – nachts `scripts/build-reports.py` (im `profiles.yml`-Lauf, eigener Schritt wie AGW):
   - liest alle geschlossenen Issues mit `report:valid` über die REST-API (eingebautes Token);
   - zählt je Spiel und Weg: gut / Probleme / startet nicht, Chips, neueste Nightforge-Version, neuestes Datum;
   - nur der letzte Bericht je Konto, Spiel und Nightforge-Version zählt (wie ProtonDB); Freitext nie;
   - schreibt `profiles/reports.json` (CC0) – keine Konto-Namen, nur Zahlen.
3. **Übernehmen** – über denselben PR-Weg wie die Profile (`bot/profiles`, Signatur, Merge durch den Maintainer).
4. **Eigene Tests** – der nächtliche Spieletest (Zweig `claude/angry-heisenberg-1f2283`) liest `testkorb.json`
   (`defaults write io.github.lordhayne.nightforge gameTest.basket -string <Pfad>`) und schreibt `report.json` mit
   denselben Feldern wie das Formular (`game`, `store`, `storeID`, `result`, `way`, `issues`) plus `hint` und
   `standsFor`. `build-reports.py` kann diese Ergebnisse als „von Nightforge getestet“ zählen (mehr Gewicht als
   ein einzelner Bericht) und über `standsFor` vorsichtig auf Spiele gleicher Engine und API übertragen – als
   Hinweis, nie als Profil.

### Format (Vorschlag)

```json
{
 "formatVersion": 1,
 "license": "CC0-1.0",
 "games": {
  "870780": {"ways": {"d3dmetal": {"good": 4, "problems": 1, "noStart": 0, "chips": ["M1 Pro", "M5"],
                                   "nightforge": "0.3.2", "last": "2026-11-20"},
                      "dxmt": {"good": 0, "problems": 0, "noStart": 3, "nightforge": "0.3.1", "last": "2026-11-02"}}}
 }
}
```

### Regeln in der App

- „1 Bericht“ steht nur als Text auf der Spielseite.
- Eine Stufe gibt es erst ab 3 verschiedenen Konten mit mindestens ⅔ Übereinstimmung aus den letzten beiden
  Engine-Ständen; Berichte älter als 12 Monate oder vor einem Engine-Wechsel gelten als alt.
- Ein Weg rückt erst nach vorn, wenn mindestens 3 übereinstimmende „good“ ihn nennen – dann als `SourceHint` mit
  `source: "reports"`, vor AGW (unsere eigene Version), nach `mac.json`.
- „no-start“ auf einem Weg schiebt ihn nach hinten, sperrt aber nie.
- Eigene Tests gewinnen immer; Berichte ändern nie Registry, Startoptionen oder Dateien.

### Warum noch nicht gebaut

`reports.yml` kommentiert und schließt Issues fremder Leute automatisch, und das öffentlich. Das sollte der Nutzer
erst sehen und freigeben, wenn die ersten echten Berichte da sind. `build-reports.py` lohnt sich erst mit Berichten.

## 5. MacGamingDB

Die genaueste Quelle (jeder Bericht nennt DXMT/D3DMetal/DXVK), aber die Daten sind nicht freigegeben. Entwurf für
die Anfrage an den Betreiber (neo773): `docs/recherche/macgamingdb-anfrage.md`. Bis zur Antwort nur verlinken.
