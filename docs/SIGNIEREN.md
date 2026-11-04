# Signieren: Schritt für Schritt (ab 0.3.1)

Ab 0.3.1 nimmt Nightforge vier Dinge aus dem Netz nur noch mit deiner Signatur an:

- das Update-ZIP,
- `components/manifest.json`,
- `profiles/profiles.json`,
- `profiles/agw.json`.

`install.sh` prüft das ZIP genauso. Signiert wird nur auf deinem Mac, mit einem Ed25519-Schlüssel, den außer dir
niemand hat. Die Gründe und die Einzelheiten stehen in `docs/SICHERHEIT-0.3.md` › „Signierte Releases“.

**Es gibt kein GitHub-Secret, und das ist Absicht**, auch nicht für das Codesignatur-Zertifikat
(`docs/CODESIGNATUR.md`). Läge der Schlüssel als Secret auf GitHub, könnte jeder
signieren, der einen Workflow ändert oder ein Token stiehlt, und die Signatur wäre wertlos. Unter Settings › Secrets
legst du deshalb nichts an.

## Vorher

- Auf dem MacBook arbeiten, nicht auf dem Mac mini.
- Terminal im Nightforge-Ordner, auf einem Stand, der die Skripte schon hat (nach dem Merge von signed-updates).
- Die Command Line Tools sind da (die Skripte bauen sich ein kleines Prüfwerkzeug mit `swiftc`).
- `gh auth status` zeigt dich als angemeldet (für die Releases).
- Ein Passwort-Manager oder ein USB-Stick für den Ersatzschlüssel.

## 1. Schlüssel erzeugen (einmal)

```bash
scripts/make-signing-keys.sh
```

Das Skript macht zwei Schlüssel. Keiner erscheint auf dem Bildschirm, in einer Befehlszeile oder im Repo.

1. **Hauptschlüssel → Anmelde-Schlüsselbund.** Er heißt dort „Nightforge signing key“. Zur Kontrolle liest das Skript
   ihn gleich zurück, und macOS fragt nach deinem Passwort. Klick auf **Erlauben**, nicht auf „Immer erlauben“. So
   fragt macOS bei jedem Signieren nach, und kein Programm liest den Schlüssel unbemerkt. Exportier ihn nie.
2. **Ersatzschlüssel → nur offline, nie auf dem Mac.** Das Skript legt ihn in die Zwischenablage.
   - Füg ihn in deinem Passwort-Manager als neuen Eintrag „Nightforge spare key“ ein, speicher und drück Return.
   - Das Skript bittet dich, ihn einmal zurückzukopieren, und prüft, ob alle 44 Zeichen angekommen sind. Danach ist
     die Zwischenablage leer.
   - Lieber auf einen USB-Stick:
     `scripts/make-signing-keys.sh --spare-file /Volumes/<Stick>/nightforge-spare.txt`.
     Die Datei bekommt die Rechte 600 (nur du). Einen Pfad im Repo lehnt das Skript ab. Den Stick danach abziehen und
     weglegen.

Bricht das Skript ab, bleibt `SigningKeys.swift` unverändert, und du startest es einfach noch einmal. Einen
Schlüsselbund-Eintrag vom abgebrochenen Lauf ersetzt es dabei.

## 2. Öffentliche Schlüssel in die App

Das hat das Skript schon erledigt: Es schreibt beide öffentlichen Schlüssel in `Sources/Nightforge/SigningKeys.swift`.
Diese Datei enthält nichts Geheimes und wird committet, mit dem Befehl, den das Skript am Ende ausgibt:

```bash
git add Sources/Nightforge/SigningKeys.swift && git commit -m "Signing keys"
```

Auf `main` ist das die einzige Stelle mit den Schlüsseln. Die App, die Skripte, der Check „Signatures“ und
`install.sh` lesen sie alle von dort.

## 3. Die Listen auf `main` signieren (einmal, vor dem ersten Release)

Sobald der Code und `SigningKeys.swift` auf `main` sind:

```bash
scripts/sign-lists.sh main
```

Das Skript fragt einmal nach deinem Passwort (Erlauben) und pusht die `.sig`-Dateien auf `main`. Prüfen: Unter
Actions ist der Lauf „Signatures“ grün. Ohne diesen Schritt nimmt jede 0.3.1 nur ihre mitgelieferten Listen. Hast du
`main` schon per Ruleset geschützt (`docs/TODO.md`), brauchst du für diesen Push die Ausnahme für dich.

## 4. Test-Release

Vor dem echten Release einmal durchspielen, ob die App lädt, prüft und sich ersetzt. Die Schritte mit rc.1 bis rc.4
stehen in `docs/SICHERHEIT-0.3.md` › „Test-Release“. Prereleases bietet weder die App noch `install.sh` an, kein
Spieler sieht sie.

## 5. Das erste signierte Release

Erst müssen die Schlüssel auf `main` sein, dann kommt der Tag. `release.yml` bricht ohne Schlüssel ab. Solange
`SigningKeys.swift` auf `main` leer ist, installiert `install.sh` nur 0.3.0 (über dessen Prüfsumme), jedes andere
Release scheitert mit „isn't signed by its maintainer“.

1. Auf dem aktuellen `main` den Tag setzen und pushen (die Version kommt aus dem Tag, `release.yml` baut nur Commits
   von `main`):

   ```bash
   git tag v0.3.1 && git push origin v0.3.1
   ```

2. `release.yml` baut die App und legt einen **Entwurf** mit ZIP und DMG an. Hat `SigningKeys.swift` keine zwei
   Schlüssel, bricht der Workflow ab.
3. Auf deinem Mac:

   ```bash
   scripts/sign-release.sh v0.3.1 --publish
   ```

   Das Skript prüft, ob die App im Entwurf v0.3.1 ist und beide Schlüssel kennt. Dann signiert es die App mit dem
   Codesignatur-Zertifikat, das nur auf deinem Mac liegt (`docs/CODESIGNATUR.md` › 4), und packt das ZIP neu. macOS
   fragt dabei, ob `codesign` den Schlüssel verwenden darf (Immer erlauben ist hier in Ordnung).
   Vor dem Signieren zeigt es:
   - beide SHA-256: die des ZIPs aus dem Workflow und die des neu signierten, das auf das Release kommt,
   - die Codesignatur,
   - den Commit, auf den der Tag zeigt,
   - die Prüfsumme des Steam-Browser-Wrappers neben der aus dem Repo.

   Stimmt der Commit, und steht beim Wrapper „the same as …“, tippst du `yes`. Dann signiert es mit Ed25519
   (Passwortabfrage: Erlauben), lädt das neue ZIP und `Nightforge-0.3.1.zip.sig` hoch und veröffentlicht. Ohne
   `--publish` bleibt es beim Entwurf, und das Skript zeigt den Befehl zum Veröffentlichen.
4. Prüfen: Auf der Release-Seite liegen `Nightforge-0.3.1.zip`, `.zip.sig` und `.dmg`. Die DMG bleibt ad hoc, wie
   der Workflow sie baut (Begründung in `docs/CODESIGNATUR.md` › 4).

Ein veröffentlichtes Release lässt sich nicht mehr ändern („Immutable Releases“). Fehlt die Signatur, braucht es einen
neuen Tag.

## 6. Laufend: die Nacht-Listen

Die Bots schlagen neue Listen als Pull Request vor: `bot/profiles` für Profile und AppleGamingWiki, `bot/components`
für Komponenten. Sie pushen nie auf `main`.

1. Den Diff im Pull Request lesen.
2. Signieren:

   ```bash
   scripts/sign-lists.sh bot/profiles
   ```

   bzw. `bot/components`. Das Skript signiert auf dem Zweig des Pull Requests, deine Arbeitskopie bleibt unberührt.
   Ändert der Zweig mehr als die Listen (etwa ein Skript), bricht es ab. So einen Pull Request liest du wie jeden
   anderen und signierst erst danach, auf `main`. Halte deinen Checkout aktuell (`git pull`): Das Werkzeug kommt aus
   ihm.
3. Mergen, wenn „Signatures“ grün ist, mit dem `gh pr merge … --match-head-commit …`, das das Skript ausgibt.

Dazu kommt `bot/wrapper`, wenn sich `wrapper/steamwebhelper-wrapper.c` auf `main` geändert hat: die neu gebaute
`steamwebhelper.exe`. Die braucht keine eigene Signatur, sie steckt in der App und wird mit dem Release signiert.
Merge sie nur zu einer Änderung am Quelltext, die du kennst.

Der Merge bringt Liste und Signatur zusammen nach `main`. Wird einmal ohne Signatur gemergt, schadet das niemandem:
Die Apps behalten ihre letzte signierte Liste, und „Signatures“ auf `main` wird rot. Dann `scripts/sign-lists.sh main`.

## 7. Wie 0.3.0-Nutzer zum ersten signierten Update kommen

Sie müssen nichts tun. 0.3.0 kennt keine Schlüssel und prüft nicht. Es zeigt wie gewohnt „Update verfügbar“, lädt das
ZIP von 0.3.1 (nie die `.sig`) und installiert es. Ab 0.3.1 gilt die Prüfung. Neuinstallationen per `install.sh`
gehen in der Zwischenzeit weiter: Bis `v0.3.1` erscheint, nimmt `install.sh` das ZIP von 0.3.0 an seiner SHA-256
(sonst nichts Unsigniertes). Danach ist das neueste Release signiert.

Ist die Prüfung in 0.3.1 kaputt, kommen seine Spieler nur noch über den Einzeiler weiter. Deshalb zuerst der
Test-Release (Schritt 4).

## 8. Wenn ein Schlüssel verloren geht

- **Hauptschlüssel weg** (Mac kaputt, Schlüsselbund gelöscht) **oder verdächtig:**
  1. Neuen Hauptschlüssel machen:

     ```bash
     scripts/make-signing-keys.sh --replace main
     ```

     Dann `SigningKeys.swift` committen.
  2. Die installierten Apps kennen nur den alten Haupt- und den Ersatzschlüssel. Deshalb jedes Release und jede
     Liste zweimal signieren: zuerst normal, dann mit dem Ersatzschlüssel dazu. Beim Release erst beim zweiten Mal
     veröffentlichen, denn danach lässt sich nichts mehr anhängen:

     ```bash
     scripts/sign-release.sh v0.3.2
     scripts/sign-release.sh v0.3.2 --spare --add --publish
     ```

     Bei den Listen: `scripts/sign-lists.sh <zweig>`, dann `scripts/sign-lists.sh <zweig> --spare --add`.
  3. Für `--spare` den Ersatzschlüssel vorher aus dem Passwort-Manager in die Zwischenablage kopieren. Liegt er auf
     dem Stick: `pbcopy < /Volumes/<Stick>/nightforge-spare.txt`. Das Skript leert die Zwischenablage danach.
  4. Ist der alte Hauptschlüssel gestohlen, bald ein Release so herausbringen: Erst die Apps mit den neuen Schlüsseln
     trauen dem alten nicht mehr.
- **Ersatzschlüssel verdächtig:** `scripts/make-signing-keys.sh --replace spare`, committen und mit dem nächsten
  Release ausliefern. Den alten Eintrag im Passwort-Manager erst löschen, wenn das Release draußen ist.
- **Beide weg:** Kein Update erreicht die installierten Apps mehr.
  1. Neue Schlüssel machen, nacheinander `scripts/make-signing-keys.sh --replace main` und
     `scripts/make-signing-keys.sh --replace spare`, dann `SigningKeys.swift` committen.
  2. Ein neues Release herausbringen.
  3. Im README und auf der Landingpage um eine Neuinstallation per Einzeiler bitten. `install.sh` liest die neuen
     Schlüssel von `main`.

## Wenn etwas hakt

- **„This key isn't the main or the spare key“:** Im Schlüsselbund liegt ein anderer Schlüssel als in
  `SigningKeys.swift`. Mit `git log Sources/Nightforge/SigningKeys.swift` prüfen, ob dort ein anderer Stand steht.
- **„Signatures“ ist rot:** Eine Liste hat sich nach dem Signieren geändert. Dann `scripts/sign-lists.sh <zweig>`.
- **Die App zeigt in Einstellungen › Über „nicht signiert“:** Eine Online-Liste auf `main` hat keine passende
  Signatur. Dann `scripts/sign-lists.sh main`.
- **Einstellungen auf GitHub** (Rulesets für Tags und `main`, Release-Environment, PR-Recht für Actions) stehen in
  `docs/TODO.md` unter „Signierte Updates“. Die setzt du selbst.
