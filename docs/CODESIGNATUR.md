# Feste Codesignatur: einmal fragen statt nach jedem Update

Bisher signiert `build.sh` Nightforge **ad hoc**. Dabei ist das „Designated Requirement“ der App, also ihre
Kennung für macOS, der Hash genau dieses Builds (`cdhash`). Jeder neue Build ist für macOS damit ein neues
Programm. Die Freigaben des Spielers (Zugriff auf ein externes Laufwerk, Bedienungshilfen, Automation) gelten nicht
mehr, und macOS fragt nach jedem Update erneut. Apple beschreibt das in TN3127: Ad hoc signierter Code hat zwar
ein Designated Requirement, aber eines, das nur für genau diese Version gilt.

Mit einem eigenen, selbst erstellten Zertifikat lautet das Requirement bei jedem Build gleich:
`identifier "io.github.lordhayne.nightforge" and certificate leaf = H"<SHA-1 des Zertifikats>"`. macOS erkennt
jedes Update als dieselbe App und behält die Antworten.

- **Gatekeeper ändert sich nicht.** Das Zertifikat ist nicht von Apple. `install.sh` und der Updater bringen die
  App ohne Quarantäne-Flag, sie startet wie bisher. Wer das DMG von Hand lädt, klickt einmal „Dennoch öffnen“, wie
  bisher.
- **Die Update-Prüfung ändert sich nicht.** Ob ein Update von dir stammt, entscheidet weiter die Ed25519-Signatur
  (`docs/SIGNIEREN.md`). Das Zertifikat sorgt nur dafür, dass macOS die App wiedererkennt.
- **Ohne Zertifikat bleibt alles beim Alten:** `build.sh` signiert dann ad hoc, und `release.yml` warnt im Log.

## 1. Zertifikat erzeugen (einmal, auf dem MacBook)

1. Schlüsselbundverwaltung öffnen, dann im Menü **Schlüsselbundverwaltung › Zertifikatsassistent › Zertifikat
   erstellen …**
2. Ausfüllen:
   - **Name:** `Nightforge Code Signing` (genau so, die Skripte suchen diesen Namen)
   - **Identitätstyp:** Selbstsigniertes Stammzertifikat
   - **Zertifikattyp:** Codesignatur
   - Häkchen bei **Standardeinstellungen überschreiben**
3. Weiter. **Gültigkeitsdauer: 7300 Tage** (20 Jahre). Nimmt der Assistent das nicht, die größte Zahl, die er
   erlaubt. Das ist wichtig: Die Vorgabe ist ein Jahr. `codesign`
   signiert mit einem abgelaufenen Zertifikat nicht mehr, und ein neues Zertifikat lässt jeden Mac noch einmal
   fragen.
4. Die übrigen Seiten mit den Vorgaben bestätigen (RSA 2048, Schlüsselverwendung „Signieren“, erweiterte
   Verwendung „Codesignatur“). Ablegen im Schlüsselbund **Anmeldung**.
5. Am Vertrauen nichts ändern. „Immer vertrauen“ ist nicht nötig, `codesign` braucht nur den privaten Schlüssel.

Lieber im Terminal? Das geht mit `openssl` und `security import`. Alles passiert in einem leeren Ordner, den du
danach löschst, weil der private Schlüssel dort kurz offen liegt:

```bash
cd "$(mktemp -d)"
printf '%s\n' '[req]' 'distinguished_name = dn' 'prompt = no' 'x509_extensions = ext' \
  '[dn]' 'CN = Nightforge Code Signing' \
  '[ext]' 'basicConstraints = critical, CA:false' 'keyUsage = critical, digitalSignature' \
  'extendedKeyUsage = critical, codeSigning' > cert.cnf
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config cert.cnf -keyout key.pem -out cert.pem
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Nightforge Code Signing" -out Nightforge.p12
security import Nightforge.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
rm key.pem
```

`openssl pkcs12` fragt nach einem Passwort für die `.p12`. Dasselbe Passwort braucht `security import` und
später GitHub.

## 2. Prüfen und festhalten

```bash
security find-identity -p codesigning
```

Erwartet ist eine Zeile wie `1) 0123…CDEF "Nightforge Code Signing" (CSSMERR_TP_NOT_TRUSTED)`. Der Zusatz „not
trusted“ ist richtig so: Das Zertifikat ist sein eigener Aussteller. Die 40 Zeichen davor sind sein SHA-1. Trag sie
als eigene Zeile unter die Kommentare in `scripts/codesign-certificate.sha1` ein und committe die Datei, sie enthält
nichts Geheimes. `release.yml` signiert dann nur mit genau diesem Zertifikat. Ein anderes, aus Versehen neu
erzeugtes, ließe sonst alle Macs noch einmal fragen.

Lokal findet `build.sh` die Identität von selbst. Beim ersten Build fragt macOS, ob `codesign` den Schlüssel
verwenden darf. Mit „Immer erlauben“ fragt es nicht bei jedem Build. Das ist vertretbar: Dieser Schlüssel
entscheidet über keine Updates, das macht der Ed25519-Schlüssel.

## 3. Für GitHub exportieren

1. In der Schlüsselbundverwaltung unter **Meine Zertifikate** „Nightforge Code Signing“ wählen, dann Rechtsklick
   › **Exportieren …** › Format **Persönliche Informationen austauschen (.p12)**, ein starkes Passwort vergeben.
   Wer den Terminal-Weg gegangen ist, hat die `.p12` schon.
2. In die Zwischenablage:

   ```bash
   base64 -i Nightforge.p12 | pbcopy
   ```

3. Auf GitHub: Repository › **Settings › Secrets and variables › Actions › New repository secret**:
   - `NIGHTFORGE_CODESIGN_P12`: den Inhalt der Zwischenablage einfügen
   - `NIGHTFORGE_CODESIGN_PASSWORD`: das Passwort der `.p12`
4. Die `.p12` als Sicherung auf den USB-Stick zum Ersatzschlüssel legen, dann vom Mac löschen.

Ohne diese Sicherung gilt: Geht das Zertifikat verloren, hilft nur ein neues. Dann fragt jeder Mac einmal.

## 4. Erster Build damit

Ein Probelauf geht ohne Tag: Actions › **Release app** › **Run workflow**. Im Schritt „Code signing identity“ steht
`Signing with <SHA-1>`. Nach der Installation zeigt

```bash
codesign -d -r - /Applications/Nightforge.app
```

`designated => identifier "io.github.lordhayne.nightforge" and certificate leaf = H"…"` statt `cdhash H"…"`.

## Der Übergang

Die Freigaben von heute hängen am alten Hash. Nach dem ersten Update auf eine Version mit dem Zertifikat fragt
macOS deshalb **noch einmal**, danach nie wieder. Das steht in `docs/release-notes/v0.3.1.md`. Erscheint 0.3.1 doch
ohne Zertifikat, den Absatz dort streichen.

## Was es nicht abdeckt

- **„Nightforge Helper“**, die kleine App, über die Nightforge Steam, Wine und die Spiele startet, baut Nightforge
  auf dem Mac selbst und signiert sie dort ad hoc. Ihre Kennung bleibt gleich, solange sich ihr Programm
  (`wrapper/nightforge-helper.c`) nicht ändert. Ändert es sich, fragt macOS für den Helfer einmal neu. Abhilfe wäre,
  den Helfer fertig signiert mitzuliefern (`docs/TODO.md`).
- **Gerät die `.p12` in fremde Hände**, kann jemand eine App bauen, die macOS für Nightforge hält. Sie bekäme dann
  dessen Freigaben, etwa für das externe Laufwerk. Auf deinen Mac käme sie damit nicht, und ein Update ohne deine
  Ed25519-Signatur nimmt Nightforge nicht an. Dann ein neues Zertifikat erzeugen, Secret und
  `codesign-certificate.sha1` tauschen. Jeder Mac fragt einmal.

Quellen: Apple, [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements);
Quinn „The Eskimo!“ (Apple DTS) im [Developer Forum](https://developer.apple.com/forums/thread/795739): „Ad hoc
signed code does not include a stable DR“; ein Erfahrungsbericht mit Bedienungshilfen und selbst signiertem
Zertifikat: [tcc cdhash trap](https://nickboy-github-io.pages.dev/posts/tcc-cdhash-trap/).
