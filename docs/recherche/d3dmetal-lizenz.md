<!-- Cloud-Recherche, Quelle: https://claude.ai/code/session_01Qz8nHT4RHomEFLP25pCxGK (1.11.2026) -->

## D3DMetal-Lizenz für Nightforge 0.3.0: Recherche, Stand 1.11.2026

Das ist keine Rechtsberatung. Es sind Fakten mit Quellen, eine Risikoeinschätzung und Optionen. Kennzeichnung: **[geprüft]** heißt, ich habe die Quelle selbst geöffnet. **[Snippet]** heißt, ich habe nur den Ausschnitt einer Suchmaschine gesehen. **[offen]** heißt unsicher oder nicht prüfbar. Am Repo habe ich nichts geändert.

---

### Kurzfassung

- Die Lizenz ist seit drei Jahren dieselbe: Apple-Dokument EA18380 vom 17.08.2023. Die License.rtf ist byte-identisch in Kopien aus GPTK 1.1, 2.0, 3.0, 4.0 beta 2 und 4.0 beta 3 (SHA-256 5abb2d05…8c8) [geprüft].
- Weitergabe ist ausdrücklich erlaubt, unter diesen Bedingungen:
  - nur nicht-kommerziell,
  - unverändert,
  - D3DMetal.framework nur als Ganzes, Teile aus /redist einzeln,
  - mit allen Hinweisen, nur auf Apple-Hardware.

- Die Nutzung ist nur „for the sole purpose of developing, testing, or evaluating video games“ erlaubt. Weitergabe und Nutzung sind getrennte Rechte:
  - Die Weitergabe hat keine Zweckbindung.
  - Jeder, der D3DMetal benutzt, ist an den Zweck gebunden, also auch jeder Nightforge-Spieler.
  - Ob „ein eigenes Windows-Spiel auf dem Mac spielen“ unter „evaluating video games“ fällt, ist ungeklärt. Kein Projekt und keine Apple-Aussage löst das.

- Viele kostenlose Projekte liefern D3DMetal seit August 2023 mit: Whisky, Wineskin, Gcenx, Sikarugir, Mythic, Heroic (über Gcenx), Bridgeplay. Apple nennt Gcenx, Whisky und CrossOver in seiner eigenen Read-Me sogar als Weg.
  - Abmahnungen, DMCA-Meldungen oder Apple-Reaktionen habe ich nicht gefunden.
  - Neuere Projekte lassen den Nutzer eher selbst laden: frankea/Whisky, Switchyard, Pufflet, MacPorts. Das gilt auch für die Engine, die Nightforge nutzt: dappermint schreibt „apple’s gptk is not redistributable“ und liefert D3DMetal bewusst nicht mit.
  - Kommerzielle Anbieter (Apara, UTM) bitten Apple seit August 2026 öffentlich um eine Klarstellung. Apple hat nicht geantwortet.

- Eigenes Risiko von Nightforge: Ihr verteilt 4.0 beta 3, also eine Vorabversion.
  - Apples Developer Agreement behandelt Vorabversionen als vertraulich und verbietet, sie zu „transmit“. Ob die GPTK-Lizenz das aufhebt, ist unklar.
  - Das Release d3dmetal-4.0b3 ist seit 26.10. öffentlich auf GitHub, obwohl main noch alt ist.

- Ohne D3DMetal fällt DirectX 12 heute praktisch weg. Es bleibt nur Wines vkd3d auf MoltenVK mit Feature Level 11_0 und Shader Model ≤ 6.0. vkd3d-proton startet weder auf MoltenVK noch auf unverändertem KosmicKrisp. DXMTs D3D12-Teil ist in Arbeit, aber als „DO NOT USE“ markiert.

### Empfehlung für 0.3.0

1. (c) mit (b) als Hauptweg. D3DMetal wird nicht mehr still beim ersten Start geladen, sondern erst beim ersten DX12-Spiel oder per Schalter. Ein Dialog zeigt Apples Lizenz und die Zweckbindung und bietet zwei Wege:
  - „Bei Apple laden und importieren“ (empfohlen),
  - „Von Nightforge laden“.

2. Keine Beta weiterverteilen. Entweder liefert ihr das finale D3DMetal 3.0 aus (Dez. 2025). Vorher prüfen, ob winecx 4.7.3 damit läuft. Oder 4.0-Betas gibt es nur über den Import (b), bis Apple 4.0 final veröffentlicht. Ob es das schon gibt, konnte ich nicht prüfen.
3. Das D3DMetal-Paket in ein eigenes Repo legen statt in die Releases von LordHayne/Nightforge. Eine Beschwerde trifft dann nicht das ganze Projekt. Abschalten geht weiter über `components/manifest.json`.
4. „Kostenlos, keine Werbung, keine Spenden“ dauerhaft halten. Das steht schon im README. Es ist die Grundlage von §2A(iii).
5. Wer null Restrisiko will: nur (b). Dafür muss im Dialog nur der zweite Knopf wegfallen. Wirkliche Sicherheit gäbe nur eine schriftliche Bestätigung von Apple, z. B. per Feedback Assistant mit Verweis auf FB24262864. Das müsstet ihr selbst anstoßen.

---

### 1. Der Lizenztext

**Welche Version gilt:** „APPLE INC. SOFTWARE LICENSE AGREEMENT FOR GAME PORTING TOOLKIT – For use on Apple-branded Systems“, Fußzeile **EA18380 8/17/2023**.

- Diese Fassung kam mit GPTK 1.0 beta 4 (21.08.2023). Die Einordnung stützt sich auf Commit-Daten in apple/homebrew-apple laut Teilrecherche.
- Seitdem ist sie unverändert bis 4.0 beta 3 [geprüft]. Belegt ist das durch dieselbe SHA-256 in Kopien für 1.1, 2.0, 3.0 (Switchyard, aus Apples DMG), 4.0b2 (Pufflet, aus Apples DMG) und 4.0b3 (holt-d3dmetal). Sikarugir hält PDFs für 1.1 bis 4.0 mit identischem Text.
- Die erste Fassung vom Juni 2023 erlaubte laut zeitgenössischen Berichten keine Weitergabe [Snippet]. Ihren Text habe ich nicht gesehen.

So prüft ihr eure eigene Kopie im Verzeichnis mit der `License.rtf`. Erwartet wird `5abb2d059be217663b00e8fd37e14411d374e11d17e3b744eebd49b8d17118c8`:

#### Wortlaut der entscheidenden Stellen

> PLEASE READ THIS SOFTWARE LICENSE AGREEMENT (“AGREEMENT”) CAREFULLY BEFORE USING THIS APPLE SOFTWARE (DEFINED BELOW). BY USING THE APPLE SOFTWARE, YOU ARE AGREEING TO BE BOUND BY THE TERMS OF THIS AGREEMENT. […]

> IMPORTANT NOTE: You may only use this Apple Software in connection with non-copyrighted materials, materials in which you own the copyright, or materials you are authorized or legally permitted to use. […]

> “Apple Software” means the Apple Game Porting Toolkit software, including the Redistributables and Framework, and documentation, updates, interfaces, content, fonts, and any data or other materials.
> “Framework” means the “D3DMetal.framework” within the Apple Game Porting Toolkit. “Redistributables” means components within the “/redist” directory of the Apple Game Porting Toolkit.

> **2. A. License.** Subject to the terms and conditions of this License, you are granted a limited, non-exclusive, non-transferable, personal copyright license to **(i) install, internally use, and test the Apple Software for the sole purpose of developing, testing, or evaluating video games for use on Apple-branded products**; (ii) sublicense the Apple Software to your third-party service providers (“Third-Party Service Providers”) solely for the purpose of exercising the foregoing Section 2A(i) rights on your behalf; and **(iii) distribute the Apple Software solely for non-commercial purposes and in accordance with this Agreement, including Section 2C.** You may make only as many internal use copies of the Apple Software as reasonably necessary to use the Apple Software as permitted under this License; provided that you reproduce on each copy of the Apple Software or portion thereof, all copyright or other proprietary notices contained on the original. […]

> **C. Other Use Restrictions; Backup Copy.** The grants set forth in this Agreement do not permit you to, and you agree not to, install, use or run the Apple Software on any non-Apple-branded devices, or to enable others to do so. You may not rent, lease, lend, host, sell, or sublicense (except as expressly set forth in Section 2A) the Apple Software or any services, in whole or in part. The Apple Software is provided as part of a bundle and its components may not be separated from the Apple Software for distribution. **Notwithstanding the foregoing, the Framework in its entirety or any part of the Redistributables may be distributed separately from the Apple Software. For clarity, all distribution of the Apple Software, including the Framework in its entirety and any individual Redistributables, are subject to the non-commercial restriction in Section 2(A)(iii).** […] You agree not to use the Apple Software in connection with service bureau, time-sharing, terminal sharing or other similar types of services. […]

> **D. No Reverse Engineering.** You may not, and you agree not to or to enable others to, copy (except to the extent expressly permitted by this Agreement), decompile, reverse engineer, disassemble, attempt to derive the source code of, decrypt, modify, or create derivative works of the Apple Software […]

> **3. Transfer.** Any copy of the Apple Software that may be provided by Apple for promotional, evaluation, diagnostic or restorative purposes may only be used for such purposes and may not be resold or transferred.

> **5. Termination.** This Agreement is effective until terminated. Your rights under this Agreement will terminate automatically or otherwise cease to be effective (i) with notice from Apple, or (ii) without notice from Apple if you fail to comply with any term(s) of this Agreement. Upon the termination of this Agreement, you shall cease all use of the Apple Software and destroy all copies, full or partial, of the Apple Software. […]

> **6. Indemnification.** […] you agree to indemnify, defend and hold harmless Apple […] from any and all claims […] related to or arising from your use of the Apple Software, […] or your loading of applications and limited distribution as permitted hereunder. […]

Weitere Punkte: Recht von Delaware (§11). Exportkontrolle (§9): keine Weitergabe in US-Embargoländer und an gelistete Personen.

#### Was erlaubt ist, was verboten ist

| Erlaubt | Verboten oder eingeschränkt |
|---|---|
| D3DMetal.framework **als Ganzes** und einzelne `/redist`-Teile weitergeben, **nur nicht-kommerziell** (§2A(iii), §2C) | Jede kommerzielle Weitergabe. „Nicht-kommerziell“ ist **nicht definiert** [offen]. |
| Installieren, intern nutzen, testen **nur zum Entwickeln, Testen oder Evaluieren von Spielen** (§2A(i)) | Ändern, Disassemblieren, abgeleitete Werke (§2D). Nightforge prüft schon die Apple-Signatur. |
| Kopien mit allen Copyright- und Lizenzhinweisen | Nutzung auf Nicht-Apple-Geräten oder anderen das ermöglichen (§2C) |
|  | Vermieten, Verleihen, „host“, Verkaufen, Service-Bureau-, Time-Sharing- oder Streaming-artige Dienste (§2C). „host“ meint im Kontext vermutlich Betrieb als Dienst, nicht einen Download [offen]. |
|  | „Evaluation“-Kopien weder weiterverkaufen noch „transfer“ (§3). Reibt sich mit §2A(iii) [offen]. |
|  | Apple kann jederzeit **mit Mitteilung kündigen**. Dann alle Kopien vernichten (§5). |

#### Gilt die Zweckbindung für den Verteiler, den Endnutzer oder beide?

- Weitergabe (§2A(iii)): Hier gibt es keine Zweckbindung. Bedingung ist nur „non-commercial“ und „in accordance with this Agreement, including Section 2C“. Das trifft den Verteiler.
- Nutzung (§2A(i)): Das ist das einzige Nutzungsrecht. Es ist auf Entwickeln, Testen oder Evaluieren von Spielen beschränkt. Es bindet jeden, der die Software benutzt: den Verteiler bei eigenen Tests und den Endnutzer. Der Vertrag soll durch Benutzung gelten („BY USING …“), und die Lizenzdatei muss jede Kopie begleiten. Also gilt die Zweckbindung für beide.
- Ungeklärt [offen]:Bridgeplay bezeichnet das als „Unresolved“, wyn als „not settled“, Switchyard verlangt dafür eine Anwaltsfreigabe.
  1. Fällt „Windows-Spiel auf dem Mac spielen“ unter „evaluating video games for use on Apple-branded products“? Der Wortlaut beschränkt das nicht ausdrücklich auf Entwickler. Apple richtet die Read-Me aber an „game developers“ und nennt das Ganze „evaluation environment“.
  2. Handelt ein Verteiler noch „in accordance with this Agreement“, wenn er D3DMetal als Spiele-Laufzeit anbietet?

#### Was Apple zur Weitergabe in Drittprodukten sagt

- Die Lizenz selbst erlaubt die Weitergabe des Frameworks und der Redistributables „separately“, ausdrücklich, aber nur nicht-kommerziell (§2C).
- Die GPTK-Seite [geprüft]: „there are even more ways to get started with this evaluation environment when you use community projects (like Homebrew) and products (like CrossOver from CodeWeavers).“
- Apples Read-Me „Evaluation environment for Windows games 2.0“ [geprüft, Kopie aus Drittrepos, nicht aus Apples DMG]:
  - „Using community projects that bundle the evaluation environment …“
  - „The following free and commercial products incorporate the supplemental evaluation layers from this distribution within a pre-built WINE environment.“ Darauf folgen Gcenx’ Casks, Whisky und CrossOver.
  - Laut Pufflet nennt die 4.0-beta-2-Read-Me weiter Gcenx und CrossOver [offen, Zweitquelle].

- Developer-Forum, Thread 841547 „Update license of D3DMetal for redistribution“ (Aug. 2026) [geprüft]:
  - UTM: „CrossOvers and Whisky both redistribute D3DMetal in their app. We would like to do so as well but the included license does not make it clear.“
  - Apara (kommerziell): „today every customer has to download the Game Porting Toolkit from Apple themselves“.
  - Keine Antwort von Apple.

#### Apple Developer Agreement, wichtig wegen der Beta

Das gilt für alles, was man über ein Apple-Developer-Konto lädt [geprüft]:

- §4: „all pre-release versions of Apple software […] provided to you as an Apple Developer (“Pre-Release Materials“) […] will be considered […] “Apple Confidential Information”“.
- §6A: Bei einer eigenen Lizenz gilt diese „in addition to Sections 4 and 5“. Nur bei Widersprüchen zu den Vertraulichkeits-Regeln geht die eigene Lizenz vor. Außerdem: „you will not modify, network, rent, lease, transmit, sell, or loan the Pre-Release Materials in whole or in part.“
- §6B: Zugriff auf Vorabversionen nur für Volljährige.

**Folge [offen]:** Bei finalen Versionen ist die GPTK-Lizenz klar die maßgebliche Erlaubnis. Bei **Betas wie 4.0b3** kommt die Vertraulichkeits- und Weitergabe-Sperre des Developer Agreement mindestens als Argument hinzu. Gcenx hat 3.0-Betas verteilt, Bridgeplay, holt-d3dmetal und dbc-hbin verteilen 4.0-Betas. Reaktionen sind keine bekannt. Vermeiden lässt sich das Risiko trotzdem leicht.

---

### 2. Wie machen es andere?

| Projekt | Preis, Status | Woher kommt D3DMetal | Lizenzhinweis oder Zustimmung |
|---|---|---|---|
| **CrossOver** (CodeWeavers) | kostenpflichtig, aktiv | Liefert D3DMetal seit 23.5.0 (Sept. 2023) mit, CrossOver 26 mit D3DMetal 3.0 [Snippet]. Die native ARM-Vorschau von CrossOver 27 kommt ohne D3DMetal [Snippet]. | **Kein öffentlicher Vertrag mit Apple gefunden** [offen]. Apple nennt CrossOver auf der GPTK-Seite und in der Read-Me. CodeWeavers sagte im Juni 2023, man habe nicht mit Apple am GPTK gearbeitet [Snippet]. |
| **Whisky** | kostenlos (GPL-3.0), **archiviert 11.05.2025** | 6/2023: Nutzer zieht Apples DMG ins Fenster. Ab 29.08.2023 eigenes Paket von `data.getwhisky.app` (Apple-redist im Repo `Whisky-App/wine`). [geprüft] | Kein Hinweis, kein Dialog. Einstellung aus eigenem Entschluss („I lost interest“, „Whisky harms Wine on Mac“), **nicht wegen Apple**. |
| **frankea/Whisky** (Fork) | kostenlos, aktiv | Nutzer importiert Apples DMG, „nothing of apple’s is redistributed“ (PR [#164](https://github.com/LordHayne/Nightforge/pull/164), Aug. 2026) [geprüft] | – |
| **Heroic Games Launcher** | kostenlos (GPL-3.0), aktiv | Lädt auf Apple Silicon beim Start automatisch **Gcenx’ GPTK 3.0-3** [geprüft] | Kein Lizenzhinweis, kein Dialog |
| **Kegworks → Sikarugir** | kostenlos (LGPL, Ko-fi), aktiv, Umbenennung ca. Aug. 2025 | Liefert D3DMetal im „Template“ auf GitHub-Releases mit, inklusive License, Read-Me und Acknowledgements [geprüft] | README: „restrictive license / it can not be used for commerial ports“ plus Link zur 4.0-Lizenz. Ein Dialog ist nicht bekannt. |
| **Wineskin** | kostenlos, **archiviert 14.08.2025** | Bis 8/2023 die GPTK-Installation des Nutzers. Ab 24.08.2023 mitgeliefert: „as now Apple allows bundling for non commercial use“ [geprüft] | README: „Since “Game porting toolkit“ 1.0 beta 4 Apple now allows redistribution for none commercial uses.“ |
| **Porting Kit** | kostenlos (Spenden), aktiv | 6.2.2 (22.03.2024): „D3DMetal should be downloaded without the need of a Developer Account“. Quelle unklar. [Snippet] | [offen] |
| **Mythic** | kostenlos (GPL-3.0), aktiv | D3DMetal 3.0 in der eigenen „Mythic Engine“ (Repo `MythicApp/wine`, Download vom eigenen Server) [geprüft] | Kein Apple-Hinweis im Dialog |
| **dappermint/winecx-gptk** (eure Engine) | kostenlos, keine LICENSE-Datei | **Liefert bewusst ohne D3DMetal**: „not shipped in this artifact: apple’s gptk is not redistributable.“ Den Import erledigt frankea/Whisky. [geprüft] | – |
| **Gcenx** | kostenlos | `game-porting-toolkit` Releases 1.1 bis **3.0-3** (03.03.2026, auch 3.0-Betas), Homebrew-Cask. **Kein 4.0.** [geprüft] | „please ensure you comply with Apple’s License.pdf for D3DMetal“. Die Lizenz liegt nicht im Archiv. Kein Dialog. |
| **MacPorts `d3dmetal`** (von Gcenx gepflegt) | – | **Lädt nicht automatisch**: „Please log in to your Apple Developer account …“, Lizenz „Restrictive“ [geprüft] | – |
| **Apara** | kommerziell, unveröffentlicht | **Nutzer lädt selbst bei Apple** [geprüft, Forum] | Bittet Apple um eine Erlaubnis |
| **UTM** (`d3dmetal-native`) | – | „Apple-licensed and NOT bundled“ [geprüft] | Bittet Apple um eine Lizenz-Klarstellung |
| Switchyard, Pufflet, wyn | kostenlos | Import aus Apples Download. Switchyards eigener Download ist abgeschaltet, bis ein Anwalt zustimmt. GPTK 4 ist dort gesperrt. [geprüft] | Switchyard: Zustimmungsdialog mit Apples Lizenz (Entwurf) |
| Bridgeplay | kostenlos (GPL-3.0) | Liefert **4.0 beta 3** mit [geprüft] | Tabelle Lizenz → Umsetzung, §2A(i) „Unresolved“ |

**Apples Reaktionen** [geprüft, soweit GitHub]:

- Im Repo `github/dmca` gibt es keine Meldung zu D3DMetal, GPTK, Whisky, Gcenx, Wineskin, Kegworks, Porting Kit oder Mythic.
- Apples Meldungen von 2023 bis 2026 betreffen andere Dinge (iBoot, App-Store-Quelltext, Doku).
- CodeWeavers’ Meldungen richten sich nur gegen Werkzeuge, die die Testphase zurücksetzen.
- Abmahnungen oder öffentliche Apple-Aussagen gegen Verteiler habe ich nicht gefunden [Snippet-Suche].
- Die Lumen-Datenbank habe ich nicht geprüft.

**Einzige Lizenzänderung:** 17.08.2023, Weitergabe nicht-kommerziell erlaubt. Wineskin (24.08.) und Whisky (29.08.) reagierten innerhalb von Tagen [geprüft]. Den Grund nennt Apple nicht. Ein Hacker-News-Kommentar vermutet Druck aus der Community oder CodeWeavers [Snippet].

---

### 3. Optionen für Nightforge

Aufwand grob: **S** ≈ ein Tag, **M** ≈ einige Tage, **L** ≈ Wochen plus laufende Pflege.

#### (a) Weiter mitliefern, wie heute

Heute wird D3DMetal automatisch aus dem eigenen GitHub-Release geladen.

- Aufwand: keiner. Zur Absicherung S: finale statt Beta-Version, eigenes Repo für das Paket.
- Risiko:
  - Die Weitergabe selbst ist durch §2A(iii) und §2C gut gedeckt, solange Nightforge kostenlos bleibt (gering bis mittel). Viele Projekte machen es seit 2023 ohne bekannte Folgen.
  - Offen bleiben die Zweckbindung (Nightforge bewirbt D3DMetal als den DX12-Weg, das ist mittel und ungeklärt), §3 „evaluation copy“ (gering bis mittel), die Beta-Frage (mittel, vermeidbar) und §6, die persönliche Freistellung Apples durch den Maintainer.
  - Bei einer Kündigung (§5) oder einer DMCA-Meldung wäre heute das Haupt-Repo betroffen.
  - Nightforge darf dauerhaft kein Geld nehmen, keine Spenden, keine Sponsoren, keine Bezahlstufe.

#### (b) Der Spieler lädt das GPTK selbst, Nightforge erkennt und nutzt es

- So geht es für den Spieler:
  1. Apple-Account, einmal kostenlos als Apple Developer registrieren und das Developer Agreement annehmen. Bei Betas nur ab 18.
  2. Bei https://developer.apple.com/download/all/?q=game%20porting%20toolkit „Evaluation environment for Windows games …“ laden.
    - Bei 3.0 gibt es die direkte Datei Evaluation_environment_for_Windows_games_3.0.dmg (25 MB, so lädt MacPorts).
    - Oder die GPTK-DMG, in der die Evaluation-DMG verschachtelt liegt (3.0 und 4.0b2).

  3. Im Image liegen License.rtf, Read Me.rtf, Acknowledgements.rtf und redist/lib/{external,wine}.

- Bezahlte Mitgliedschaft (99 $): nach allen Quellen nicht nötig. Apple: „To access additional resources, such as beta versions … register for free with your Apple Account.“ Die GPTK-Liste selbst konnte ich nicht sehen, sie liegt hinter dem Login [offen].
- Kann Nightforge selbst laden? Nein. Das Konto darf nicht geteilt werden (Developer Agreement §1), und Login-Automatik mit Zwei-Faktor-Anmeldung ist fragil. Möglich ist: Apples Seite im Browser öffnen, ~/Downloads beobachten, Drag-and-drop oder „Toolkit hinzufügen …“ anbieten.
- Aufwand: M. Der Kern existiert schon:
  - Engine.installD3DMetal nimmt einen beliebigen Ordner und prüft die Apple-Signatur (`Sources/Nightforge/Engine.swift:672`).
  - `scripts/package-d3dmetal.sh` kann schon DMG oder Ordner einlesen.
  - Neu wären: Oberfläche, hdiutil attach auch für die verschachtelte DMG (das Skript sucht nur 4 Ebenen tief in einem Image), Version aus Info.plist, Stempel nach lokaler statt Manifest-Version, Tests.

- Risiko: das geringste. Nightforge verteilt nichts von Apple, der Spieler stimmt Apples Bedingungen selbst zu. Die Zweckbindung bleibt dann seine Sache, ein Satz im Dialog genügt.
- Preis: Hürde für Spieler (Konto, rund 5 Schritte). DX12 gibt es nur für die, die das machen.
- Vorbilder: frankea/Whisky, Switchyard, Pufflet, wyn, MacPorts, Apara, Whisky und Wineskin vor 8/2023.

#### (c) D3DMetal nur auf ausdrücklichen Wunsch, mit Lizenzhinweis

- Ablauf: Kein Download beim ersten Start. Beim ersten DX12-Spiel oder per Schalter erscheint ein Dialog:
  - Apples License.rtf (oder die Kernsätze plus Datei),
  - Zweckbindung, „Nightforge ist kostenlos“, nur Apple-Hardware,
  - die Wahl „bei Apple laden (b)“ oder „von Nightforge laden“,
  - die Zustimmung wird nur lokal gespeichert, Nightforge nimmt sie nicht für den Nutzer vor. Switchyards Entwurf ist dafür ein gutes Muster.

- Aufwand: S allein, M zusammen mit (b).
- Risiko: Rechtlich gleich (a), Nightforge verteilt weiter. Besser sind Transparenz, Hinweispflicht und die bewusste Zustimmung des Spielers. Beta-Frage und Zweckfrage löst es nicht. Heroic, Mythic und Sikarugir zeigen gar keinen Hinweis, Nightforge wäre damit vorsichtiger als die meisten.

#### (d) Ohne D3DMetal: was für DirectX 12 bliebe

- Wines eigenes vkd3d (2.x) auf MoltenVK [geprüft]:
  - Läuft, aber nur Feature Level 11_0, Shader Model ≤ 6.0, keine Geometry Shader und kein Stream Output.
  - Das reicht für wenige ältere oder leichte DX12-Titel, oft mit Fehlern (Diablo II: Resurrected: schwarzer Boden).
  - Ob winecx-gptk Wines d3d12.dll mitbringt, ist ungeprüft [offen].

- vkd3d-proton (v3.1, 28.10.2026) auf MoltenVK 1.4.2: startet nicht.
  - Ihm fehlen robustness2 inklusive nullDescriptor, Transform Feedback, Sparse und Mutable Descriptors.
  - „won’t even run at all“ (Issue [HansKristian-Work/vkd3d-proton#2838](https://github.com/HansKristian-Work/vkd3d-proton/issues/2838)) [geprüft].

- KosmicKrisp (LunarG, Mesa ≥ 26.0, MIT, Metal 4, macOS 26+):
  - Laut Khronos und Phoronix Vulkan-1.4-konform [Snippet].
  - Geometry Shader gibt es erst auf main (29.10.2026).
  - Es fehlen weiter Transform Feedback, Single-Texel-Alignment, Sparse und SM-6.6-Atomics.
  - Unverändertes vkd3d-proton bricht deshalb beim Erzeugen des Device ab [geprüft im Code].

- Nur mit großen Patch-Stapeln (Highball, steamac: gepatchtes vkd3d-proton plus rund 55 Mesa-Patches, teils von KI geschrieben):
  - Forza Horizon 6 mit 30 FPS auf „Very Low“ (M4), GravityMark mit 6 FPS, ein Spiel kommt nicht übers Shader-Kompilieren hinaus.
  - Für die Rosetta-Wine braucht es außerdem einen x86_64-KosmicKrisp-Treiber.

- DXMT D3D12:
  - Rund 164 Commits seit Juli 2026, nur mit -Denable_d3d12=true, in keinem Release.
  - Der Maintainer schreibt „DO NOT USE“. Finanziert von CodeWeavers.
  - Der glaubwürdigste offene Weg mittelfristig, aber ohne Datum.

- Aufwand:
  - D3DMetal entfernen: S.
  - Eine eigene vkd3d-proton/KosmicKrisp-Spur: L plus Dauerpflege, nur macOS 26+.

- Risiko: rechtlich keines. Produktseitig hoch: DX12 fällt weitgehend weg (Wukong, UE5, die meisten AAA-Spiele seit etwa 2020), und das README-Versprechen „DirectX 12 runs through Apple’s D3DMetal“ fiele.

---

### 4. DXMT-Lizenzwechsel und eure Hinweisdatei

**Fakten [geprüft]:**

- Commit ec357fd vom 25.04.2026: „chore: add LGPL license“. Seitdem steht auf main LGPL-2.1-or-later (LICENSE, COPYING.LIB). Die alte MIT-Lizenz liegt in LICENSE.OLD.
- Die Release-Notiz zu v0.80 (23.04.2026): „v0.80 will be the last release distributed in MIT license.“
- Ein neueres Release gibt es noch nicht.

**Was das für Nightforge heißt:**

- Heute ändert sich nichts. Nightforge baut DXMT fest aus v0.80 (DXMT_VERSION: v0.80 in `.github/workflows/graphics.yml`). Die Zeile „DXMT 0.80 MIT (with DXVK code, zlib, and NVIDIA NVAPI headers, MIT)“ in `Resources/THIRD_PARTY_NOTICES.txt` stimmt.
- Unstimmig: `components/manifest.json` führt dxmt 0.80 als „LGPL-2.1-or-later“. Für 0.80 müsste dort MIT stehen. `components/sources.json` passt als Regel für künftige Versionen.
- Ab dem ersten Update über v0.80 hinaus (v0.81+ oder ein main-Commit nach ec357fd, z. B. für D3D12):
  - Die Zeile wird zu „DXMT ≥ 0.81: LGPL-2.1-or-later“.
  - COPYING.LIB und LICENSE müssen mit.
  - Der zugehörige Quelltext muss mit, inklusive eurer Patches, die damit auch LGPL werden. Das erfüllt ihr schon mit dem Quellarchiv als zweitem Asset.
  - „or later“ ist mit GPL-3.0 verträglich.
  - Die App linkt DXMT nicht, Wine lädt austauschbare DLLs. Damit gibt es keine weitere Relink-Pflicht. LGPL-2.1 hat keine Klausel zu Installationsinformationen, Signieren und Notarisieren sind also kein Problem.

- Nebenbefund, unabhängig vom Wechsel [prüfen]:
  - DXMTs winemetal.so linkt LLVM 15 statisch (Apache-2.0 WITH LLVM-exception, euer Workflow baut LLVM 15.0.7).
  - DXMT enthält Microsofts DXBCParser (MIT).
  - Beides fehlt in den Hinweisen. Die LLVM-Ausnahme deckt nur Compiler-Ausgabe ab, nicht das Linken der LLVM-Bibliotheken.

---

### Gesperrte Hosts und was deshalb ungeprüft blieb

Erreichbar waren nur `developer.apple.com`, GitHub und die Websuche (nur Ausschnitte).

**Gesperrt:**

- www.codeweavers.com, support.codeweavers.com
- getwhisky.app und data.getwhisky.app, portingkit.com, paulthetall.com, dl.getmythic.app, apara.dev, sikarugir.com, machow2.com
- www.apple.com und support.apple.com, also auch Apples allgemeine Website-Nutzungsbedingungen
- idmsa.apple.com, also Apples Login und damit die GPTK-Downloadliste
- reddit, Hacker News, Wikipedia, archive.org, Phoronix, MacRumors, AppleGamingWiki
- gitlab.winehq.org, gitlab.freedesktop.org, lunarg.com, khronos.org, mesa3d.org

Apples Forenthreads zeigen bei direktem Abruf eine Bot-Prüfung. Thread 841547 ließ sich über den Abrufdienst lesen.

**Dadurch ungeprüft:**

- ob CodeWeavers einen Vertrag mit Apple hat (nur Ausschnitte, keine offizielle Aussage),
- die Details zu Porting Kit (Quelle des D3DMetal-Downloads),
- ob es GPTK 4.0 final schon gibt (öffentlich gespiegelt ist zuletzt 4.0 beta 3 vom 21. und 26.10.),
- ob Apples Download-Liste das GPTK auch mit kostenlosem Konto zeigt (laut allen Quellen ja),
- der Wortlaut der ersten GPTK-Lizenz vom Juni 2023 und der Grund für die Änderung im August 2023,
- die Lumen-Datenbank für DMCA-Meldungen außerhalb von GitHub,
- KosmicKrisps Konformitäts- und SDK-Status (nur Ausschnitte).

---

### Quellen

**Apple**

- GPTK-Seite: https://developer.apple.com/games/game-porting-toolkit/
- GPTK-Downloads (Login): https://developer.apple.com/download/all/?q=game%20porting%20toolkit
- Apple Developer Agreement (20250318): https://developer.apple.com/support/downloads/terms/apple-developer-agreement/Apple-Developer-Agreement-20250318-English.pdf
- Kostenloses Developer-Konto: https://developer.apple.com/help/account/basics/about-your-developer-account
- Forum „Update license of D3DMetal for redistribution“: https://developer.apple.com/forums/thread/841547
- Apples öffentliches GPTK-Repo (ohne D3DMetal): https://github.com/apple/game-porting-toolkit

**Lizenzkopien und Lesarten**

- holt-d3dmetal (4.0b3, License.rtf): https://github.com/al0x99/holt-d3dmetal, Release: https://github.com/al0x99/holt-d3dmetal/releases/tag/4.0b3
- Sikarugir, Lizenz 4.0: https://github.com/Sikarugir-App/Sikarugir/blob/HEAD/D3DMetal/4.0/License.pdf
- Lizenz als Text: https://github.com/gauthierpiarrette/highball/blob/HEAD/spike/d3dmetal-license.txt
- Lizenz und Read-Me 1.1/2.0: https://github.com/HmWhyNot/macOS-SMW-Tools/tree/HEAD/common/Frameworks/renderer/d3dmetal
- Switchyard GPTK-3-Prüfung: https://github.com/jungwuk-ryu/Switchyard/blob/HEAD/docs/legal/gptk-3-redistribution-review.md
- Switchyard Kanal-Entwurf: https://github.com/jungwuk-ryu/Switchyard/blob/HEAD/docs/gptk-component-channel.md
- Bridgeplay: https://github.com/raymondchins/Bridgeplay/blob/HEAD/docs/GPTK-LICENSE.md
- Pufflet: https://github.com/talhabalaj/pufflet/blob/HEAD/docs/D3DMETAL.md
- wyn: https://github.com/JellyBean47/wyn/blob/HEAD/Documentation/user/gptk.md
- MacPorts-Port: https://github.com/macports/macports-ports/blob/master/devel/d3dmetal/Portfile

**Andere Projekte**

- Whisky: https://github.com/Whisky-App/Whisky
- Whisky Wartungshinweis: https://github.com/Whisky-App/whisky-book/blob/HEAD/src/maintenance-notice.md
- Whisky Wine-Build mit GPTK/redist: https://github.com/Whisky-App/wine/tree/a92f7f06c4cff7291578e58eb95284b00e322799/GPTK/redist
- frankea/Whisky: https://github.com/frankea/Whisky/blob/HEAD/docs/DEPENDENCIES.md, https://github.com/frankea/Whisky/releases/tag/app-v3.6.0
- Heroic: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/blob/HEAD/src/backend/wine/manager/downloader/constants.ts, [Heroic-Games-Launcher/HeroicGamesLauncher#4964](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/4964)
- dappermint/winecx-gptk: https://github.com/dappermint/winecx-gptk, Zeile „not redistributable“: https://github.com/dappermint/winecx-gptk/blob/0bf3eab/.github/workflows/build.yml#L855, KosmicKrisp-Notiz: https://github.com/dappermint/winecx-gptk/blob/HEAD/docs/kosmickrisp.md
- Gcenx: https://github.com/Gcenx/game-porting-toolkit/releases, https://github.com/Gcenx/homebrew-wine/blob/HEAD/Casks/game-porting-toolkit.rb
- Sikarugir: https://github.com/Sikarugir-App/Sikarugir, https://github.com/Sikarugir-App/Template/releases, [Sikarugir-App/Sikarugir#140](https://github.com/Sikarugir-App/Sikarugir/issues/140)
- Wineskin: https://github.com/The-Wineskin-Project/WineskinServer, https://github.com/The-Wineskin-Project/Engines/releases
- Porting Kit: Changelog (gesperrt, nur Snippet) https://www.portingkit.com/pub/portingkit_dev/download_latest.php?format=changelog, Cask: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/p/porting-kit.rb
- Mythic: https://github.com/MythicApp/Mythic, https://github.com/MythicApp/wine
- Apara: https://github.com/Apara-App
- UTM: https://github.com/utmapp/d3dmetal-native
- Switchyard: https://github.com/jungwuk-ryu/Switchyard
- CrossOver-Changelog (gesperrt, nur Snippets): https://www.codeweavers.com/crossover/changelog
- GitHub DMCA-Archiv: https://github.com/github/dmca
- Nightforge-Release: https://github.com/LordHayne/Nightforge/releases/tag/d3dmetal-4.0b3

**DirectX 12 ohne D3DMetal**

- vkd3d-proton: https://github.com/HansKristian-Work/vkd3d-proton (README, `libs/vkd3d/device.c`), [HansKristian-Work/vkd3d-proton#2838](https://github.com/HansKristian-Work/vkd3d-proton/issues/2838), [HansKristian-Work/vkd3d-proton#1889](https://github.com/HansKristian-Work/vkd3d-proton/issues/1889), https://github.com/HansKristian-Work/vkd3d-proton/commit/929b5da94dbe85e71b911476ac9c6922572a66b5
- MoltenVK: https://github.com/KhronosGroup/MoltenVK/blob/HEAD/Docs/Whats_New.md, [KhronosGroup/MoltenVK#2650](https://github.com/KhronosGroup/MoltenVK/issues/2650), [KhronosGroup/MoltenVK#1524](https://github.com/KhronosGroup/MoltenVK/issues/1524), [KhronosGroup/MoltenVK#1776](https://github.com/KhronosGroup/MoltenVK/issues/1776), [KhronosGroup/MoltenVK#2883](https://github.com/KhronosGroup/MoltenVK/issues/2883)
- Wines vkd3d: https://github.com/wine-mirror/wine/blob/HEAD/libs/vkd3d/libs/vkd3d/device.c
- KosmicKrisp (Mesa-Spiegel): https://github.com/chaotic-cx/mesa-mirror/blob/HEAD/docs/drivers/kosmickrisp.rst, https://github.com/chaotic-cx/mesa-mirror/commits/main/src/kosmickrisp
- Highball: https://github.com/gauthierpiarrette/highball, https://github.com/gauthierpiarrette/highball-engine/blob/HEAD/renderers-arm64/README.md
- steamac: https://github.com/fxgl/steamac/releases/tag/v1.8
- Cosmopolitan: [cyber-prinzesse/Cosmopolitan#20](https://github.com/cyber-prinzesse/Cosmopolitan/pull/20)
- hadron: [Broyojo/hadron#84](https://github.com/Broyojo/hadron/issues/84)
- DXMT D3D12: [3Shain/dxmt#249](https://github.com/3Shain/dxmt/pull/249), [3Shain/dxmt#194](https://github.com/3Shain/dxmt/issues/194), https://github.com/3Shain/dxmt/blob/HEAD/meson.options

**DXMT-Lizenz**

- Commit: https://github.com/3Shain/dxmt/commit/ec357fd582f0b7e0fee3803f6102ab786f1ba616
- LICENSE heute: https://github.com/3Shain/dxmt/blob/HEAD/LICENSE
- LICENSE.OLD: https://github.com/3Shain/dxmt/blob/HEAD/LICENSE.OLD
- LICENSE bei v0.80: https://github.com/3Shain/dxmt/blob/v0.80/LICENSE
- Release v0.80: https://github.com/3Shain/dxmt/releases/tag/v0.80
