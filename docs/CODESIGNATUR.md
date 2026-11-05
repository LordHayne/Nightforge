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
- **Das Zertifikat bleibt auf deinem Mac**, nie auf GitHub (deine Entscheidung vom 3.11.). `release.yml` baut ad
  hoc und legt wie bisher den Entwurf an. `scripts/sign-release.sh` signiert die App dann auf deinem Mac mit dem
  Zertifikat, packt das ZIP neu und signiert erst dieses mit Ed25519.
- **Ohne Zertifikat bleibt alles beim Alten:** Steht in `scripts/codesign-certificate.sha1` keines, signiert
  `sign-release.sh` das ZIP aus dem Workflow, ad hoc wie bisher.

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
nichts Geheimes. `sign-release.sh` signiert dann nur mit genau diesem Zertifikat. Ein anderes, aus Versehen neu
erzeugtes, ließe sonst alle Macs noch einmal fragen.

Lokal findet `build.sh` die Identität von selbst. Beim ersten Build fragt macOS, ob `codesign` den Schlüssel
verwenden darf. Mit „Immer erlauben“ fragt es nicht bei jedem Build. Das ist vertretbar: Dieser Schlüssel
entscheidet über keine Updates, das macht der Ed25519-Schlüssel. Ein Build, bei dem niemand zuschaut (eine Claude-Session, ein
Testlauf), wartet sonst auf diese Frage: `NIGHTFORGE_AD_HOC=1 ./build.sh` signiert ad hoc, egal was im Schlüsselbund
liegt.

## 3. Sicherung auf den USB-Stick

Geht das Zertifikat verloren (Mac kaputt, Schlüsselbund gelöscht), hilft nur ein neues, und dann fragt jeder Mac
einmal. Darum eine `.p12` auf den Stick, zum Ersatzschlüssel. Auf macOS 27 öffnet die Schlüsselbundverwaltung nur
noch „Passwörter“, und `security export -t identities` nähme jede Identität im Schlüsselbund mit. Dieses Skript
exportiert nur das Zertifikat aus `scripts/codesign-certificate.sha1` mit seinem Schlüssel:

```bash
scripts/export-codesign-identity.sh /Volumes/<Stick>/Nightforge-Code-Signing.p12
```

1. macOS zeigt ein eigenes Fenster für das Passwort der `.p12`. Ein starkes Passwort zweimal eingeben und in den
   Passwort-Manager legen (Eintrag „Nightforge Code Signing p12“). Es läuft nicht durch das Skript.
2. macOS fragt, ob der Schlüssel „Nightforge Code Signing“ exportiert werden darf: Anmeldepasswort, **Erlauben**.
3. Erwartet: `✓ /Volumes/…/Nightforge-Code-Signing.p12: the certificate … with its key, readable only by you.` Den
   Stick abziehen und weglegen.

Das Skript läuft nur im Terminal und ändert nichts im Schlüsselbund. Zurück auf einen neuen Mac kommt die Sicherung
mit `security import <Datei>.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign`.

## 4. Ein Release damit

`scripts/sign-release.sh <tag>` erledigt es (`docs/SIGNIEREN.md` › 5):

1. Es lädt das ZIP aus dem Entwurf und prüft Version und Schlüssel wie bisher.
2. Dann signiert es die App mit dem Zertifikat. macOS fragt, ob `codesign` den Schlüssel verwenden darf: Mit
   „Immer erlauben“ fragt es nicht bei jedem Release. Das ist vertretbar, denn dieser Schlüssel entscheidet über
   keine Updates.
3. Es prüft, dass das Requirement Bundle-ID und Zertifikat nennt, und packt das ZIP neu.
4. Vor dem `yes` stehen beide Prüfsummen da: die des ZIPs aus dem Workflow und die des neu signierten. Dieses
   zweite kommt mit seiner Ed25519-Signatur in den Entwurf und ersetzt das erste.
5. Ein zweiter Lauf (`--spare --add` nach einem Schlüsselwechsel) findet die App schon signiert vor und lässt das
   ZIP, wie es ist. Sonst passte die erste Signatur nicht mehr.

**Die DMG kommt aus derselben App:** `sign-release.sh` baut sie aus der App mit dem Zertifikat neu, ersetzt die ad hoc
signierte des Workflows und schreibt ihre SHA-256 in die Release-Notes. `dmgbuild` kommt über die Prüfsummen in
`scripts/dmgbuild-requirements.txt` in eine eigene Umgebung und braucht Homebrews `python@3.13`. Wer die DMG von
Hand öffnet, bestätigt sie einmal unter „Dennoch öffnen“, weil Nightforge nicht notarisiert ist.

Prüfen nach dem Release:

```bash
codesign -d -r - /Applications/Nightforge.app
```

zeigt `designated => identifier "io.github.lordhayne.nightforge" and certificate leaf = H"…"` statt `cdhash H"…"`.

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
  Ed25519-Signatur nimmt Nightforge nicht an. Dann ein neues Zertifikat erzeugen und `codesign-certificate.sha1`
  tauschen. Jeder Mac fragt einmal. Weil die `.p12` nie auf GitHub liegt, kommt nur an sie, wer an deinen Mac oder
  den Stick kommt.

Quellen: Apple, [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements);
Quinn „The Eskimo!“ (Apple DTS) im [Developer Forum](https://developer.apple.com/forums/thread/795739): „Ad hoc
signed code does not include a stable DR“; ein Erfahrungsbericht mit Bedienungshilfen und selbst signiertem
Zertifikat: [tcc cdhash trap](https://nickboy-github-io.pages.dev/posts/tcc-cdhash-trap/).
