# Entwurf: Nightforge ohne Rosetta (ARM64-Wine mit FEX)

Studie vom 8.11.2026. Nur gelesen und recherchiert: nichts geladen, gebaut oder gestartet.

Kennzeichnung:
- **[Mac]** am 8.11. auf diesem Mac nachgesehen (macOS 27.0.1).
- **[Beleg]** aus der genannten Quelle gelesen.
- **[gemeldet]** nur eine Projektseite oder Mailingliste sagt es, ungeprüft.
- **[Vermutung]** meine Schlussfolgerung.

Die Nummern in eckigen Klammern verweisen auf die Quellen am Ende.

## Kurzfassung

1. **Der Windows-Weg hängt an Rosetta.** Wine, DXMT, D3DMetal und Nightforges eigene Wine-Teile sind x86_64 [Mac]. Ab
   macOS 28 ist Intel-Software nicht mehr kompatibel, außer alten Spielen [1][3]. Ob Wine darunter fällt, sagt Apple nicht.
2. **Der Weg heraus ist technisch offen, aber noch nicht fertig.** ARM64-Wine mit FEX läuft in einer CrossOver-Vorschau
   und in einem freien Projekt [5][7][8]. Die Wine-Patches waren am 7.11. noch nicht eingereicht [5].
3. **Drei Hürden entscheiden:**
   - **Das Entitlement.** Ohne es gibt es keine 32-Bit-Spiele und wohl auch kein Windows-Steam. Ein kostenloses Konto
     scheiterte daran [5].
   - **D3DMetal gibt es nicht für ARM64** [Mac][8]. Für DirectX 12 braucht es einen anderen Weg.
   - **Die Leistung ist unbekannt.** Ein Vergleich FEX gegen Rosetta in einem Spiel ist nirgends veröffentlicht [8][9].
4. **Empfehlung:** jetzt nur das Risikolose vorbereiten (Abschnitt 6), die Kontofrage entscheiden und bis etwa Mai 2027
   beobachten. Eine eigene ARM64-Engine lohnt erst, wenn Wines Patches oder CrossOvers Quellen vorliegen. Bis dahin
   bliebe nur ein Fremdzweig.

## 1. Ausgangslage auf dem Mac

| Teil | Architektur [Mac] | Ohne Rosetta |
|---|---|---|
| Nightforge, Nightforge Helper | arm64 | läuft |
| legendary (Epic), gogdl (GOG) | arm64 | läuft |
| Steam für Mac | x86_64 + arm64 | läuft |
| MoltenVK | x86_64 + arm64 | läuft |
| winecx 4.7.3 (`wine`, `ntdll.so`) | x86_64 | braucht Ersatz |
| DXMT `winemetal.so` | x86_64 | braucht Ersatz |
| D3DMetal 3.0 (`D3DMetal`, `libd3dshared`) | x86_64 | **kein Ersatz bekannt** |
| `winebus.so` (gamepad), `ntdll.so` (enginefix) | x86_64 | neu gegen die neue Engine bauen |
| `hide-steam-dock.dylib`, Vulkan-Layer, Sandbox-Helfer | x86_64 (`clang -arch x86_64`, `build.sh`) | neu bauen |
| KosmicKrisp (eigener Bau) | x86_64 | neu bauen, arm64 wäre einfacher |

Der Code nimmt x86_64 an mehreren Stellen fest an, vor allem `Engine.swift` (35 Treffer, darunter die Pfade
`lib/wine/x86_64-unix` und `x86_64-windows`), `Setup.swift` und `D3DMetalSupply.swift`. Die Einrichtung installiert Rosetta
schon, wenn es fehlt. Für macOS 28 gibt es noch keine Prüfung und keinen Hinweis.

Am 7.11. warnte macOS 27 schon beim Nightforge Helper, dass eine Komponente in macOS 28 nicht mehr öffnet
(`nightforge-rosetta-macos28`).

## 2. Was Apple sagt

- macOS 27 ist die letzte Version mit Rosetta für Intel-Apps. Für ältere, nicht mehr gepflegte Spiele, die Intel-Frameworks
  brauchen, bleibt ein Teil bestehen [1][2][3] **[Beleg]**.
- In den Release Notes zu macOS 27 steht laut Auszug: Intel-Software ist mit macOS 28.0 nicht mehr kompatibel, Altspiele
  ausgenommen. In Betaversionen schaltet `sudo game-test-tool enable` die Altspiel-Unterstützung ein, deaktiviert dabei
  aber Rosetta. Rosetta wird beim Upgrade auf 27 nicht wiederhergestellt [4] **[Beleg, nur über einen Auszug gelesen]**.
- Welche Spiele dazugehören, sagt Apple nirgends. Es gibt keine Liste, keine API, keinen Plist-Schlüssel und kein
  Entitlement dafür. Wine, CrossOver und das Game Porting Toolkit werden nicht erwähnt [1][2][3][4] **[Beleg]**.
- **[Vermutung]** Wine ist kein altes Spiel, sondern ein laufendes Programm. Darauf sollte Nightforge nicht bauen. Ein
  Projekt meldet, dass die Ausnahme seinen Spiel-Wrapper unter 27.0.1 nicht abdeckt [9] **[gemeldet]**.
- Ein Projekt meldet auch, dass 27.0.1 Rosetta entfernt habe [9] **[gemeldet]**. Auf diesem Mac ist es unter 27.0.1
  installiert **[Mac]**.

## 3. Was ARM64-Wine bräuchte

Das Grundmodell: Wine läuft nativ auf arm64. x86_64-Windows-Programme laufen über FEX als ARM64EC, 32-Bit-Programme über
FEX in WoW64. Die Unix-Seite von Wine und Grafik ist nativ arm64 [5][7][8][11].

| Baustein | Stand | Art |
|---|---|---|
| **Wine für macOS/ARM64** | Vorhanden, aber außerhalb von Wine. CodeWeavers wollte Patches einreichen und sagte das am 9.9. erneut. Am 7.11. fragte jemand nach dem Stand bis zum Wine-12-Freeze, ohne Antwort [5]. Bis Wine 11.18 fand ein Projekt keinen Merge [9]. | [Beleg] / [gemeldet] |
| **macOS-Voraussetzungen** | macOS 26.5 für x18-Modus, 4K-Seiten beim Prozessstart und TSO pro Thread (`thread_set_x86_64_compat`, Threads erben es nicht). Dazu 26.4/Xcode für den Linker-Schalter gegen PAGEZERO [5]. Ein Projekt liest im SDK andere Mindestversionen [9]. | [gemeldet] (Wine-Entwickler) |
| **FEX** | Upstream ist Linux. CodeWeavers baut eine eigene macOS-Fassung. MetalSharp nutzt FEX-2610 mit 34 eigenen Commits, nicht upstream. FEX muss eigens für ARM64EC/WoW64 gebaut sein [7][8][12]. Lizenz MIT [8]. | [Beleg] für MetalSharp, [gemeldet] für CodeWeavers |
| **DXMT (DX10/11)** | Die Doku beschreibt x86_64-PE plus Unix-Teil, nativ arm64 nur für den Bau ohne Wine. Im Repo liegt `build-arm64ec.txt`, ungeprüft [10]. Die CI baut laut einem Projekt eine arm64-Unix-Seite, liefert sie aber nicht aus [9]. CodeWeavers liefert ARM64-DXMT in der Vorschau [6]. MetalSharp nutzt den Fork Mullion mit ARM64X [8]. | [Beleg] / [gemeldet] |
| **DXMT-Haken in winemac** | Sie sind nicht in Wine, sondern Fremdpatches. Bei einem Projekt nur für `__x86_64__` gebaut, und Wine benannte in 11.18 Typen um [9]. Nightforges `graphics`-Komponente baut `winemac.so` genau so und wäre betroffen. | [gemeldet], [Vermutung] |
| **DirectX 9 (DXVK)** | Läuft als opt-in-Weg bei MetalSharp (DXVK-macOS) [8]. Ein arm64-KosmicKrisp wäre hier leichter als heute. MoltenVK ist schon universal [Mac]. | [Beleg], [Vermutung] |
| **D3DMetal (DX12, Teile von DX11)** | Nicht auf arm64 nutzbar [8], fehlt in CrossOvers Vorschau [6]. Das Toolkit 3.0 hier ist x86_64 [Mac]. Eine Aussage von Apple zu einer arm64-Fassung habe ich nicht gefunden. | [Beleg] |
| **Eigene Teile** | `hide-steam-dock`, Vulkan-Layer, Sandbox-Helfer, „Nightforge Game.app“, winebus, enginefix müssen neu gebaut werden. Die Windows-Helfer (`steamwebhelper`-Wrapper, `unity-play.exe`) bleiben x86_64-PE und liefen über FEX. | [Mac], [Vermutung] |

## 4. Die Hürden

### 4.1 Entitlement und Signatur (die erste Entscheidung)

- ARM64-Wine braucht für 4K-Seiten und x86-Kompatibilität eingeschränkte Entitlements:
  `com.apple.developer.cross-architecture-support` für bezahlte Konten, `…-unmanaged` für kostenlose. Dazu ein
  Provisioning-Profil, das im `.app`-Bündel beim Wine-Loader liegt [5] **[gemeldet, Wine-Entwickler]**.
- In der Praxis scheiterte ein kostenloses Konto: Die Seite ist nicht sichtbar, die Fähigkeit wird abgelehnt. Der Betroffene
  arbeitet nun mit abgeschaltetem SIP und AMFI [5] **[gemeldet]**. Das ist für Spieler keine Lösung. CodeWeavers' Entwickler
  hat selbst kein kostenloses Konto und konnte nicht helfen [5].
- In Apples Entitlement-Doku fand ich den Schlüssel nicht (die erwartete Adresse ergibt 404) [4]. Das beweist nichts, passt
  aber zu dem, was der Betroffene berichtet.
- MetalSharp signiert mit Developer ID, bettet ein Profil in ein eigenes Bündel für den Loader ein, nutzt zusätzlich
  `disable-executable-page-protection` und notarisiert [7] **[Beleg]**.
- **Was ohne Entitlement geht** [7] **[Beleg]**: x86_64 und ARM64 mit 16K-Seiten, **kein 32-Bit**.
- **Folgen für Nightforge [Vermutung]:**
  - Nightforge hat ein selbst signiertes Zertifikat und ist nicht notarisiert (`docs/CODESIGNATUR.md`). Für den Vertrieb
    an alle reicht das wohl nicht. Ein kostenloses Profil wäre an registrierte Macs gebunden. Nötig wäre also ein
    bezahltes Apple-Developer-Konto mit Developer ID.
  - Ein neuer Signaturweg ändert die Identität der App. macOS würde die Rechte wieder einmal abfragen.
  - Der gehärtete Lauf verträgt sich womöglich nicht mit `DYLD_INSERT_LIBRARIES` (`hide-steam-dock`). Das müsste man
    ersetzen oder mit einer Ausnahme erlauben.

### 4.2 32-Bit-Spiele

32-Bit läuft nur über FEX-WoW64 und braucht das Entitlement für den unteren 4-GB-Adressraum [7] **[Beleg]**. Das betrifft
Mafia II und Left 4 Dead 2. CrossOver 27 soll laut einer ungeprüften Notiz 32-Bit-Flaschen aufgeben (Blog nicht lesbar).

### 4.3 Launcher

- **Epic und GOG sind der leichte Fall.** legendary und gogdl sind schon arm64 [Mac], die Spiele startet Nightforge direkt.
- **Windows-Steam ist der schwere Fall:**
  - Es enthält laut einem Projekt 31 i386-Programme, braucht also 32-Bit und damit das Entitlement [9] **[gemeldet]**.
  - Sein Browser ist Chromium unter FEX. In MetalSharps Messung ist kalter JIT-Code etwa 380-mal langsamer als nativ [8].
    **[Vermutung]** Das trifft Steams Oberfläche und den Start.
  - CEF läuft dort als Testprogramm, die Steam-Seite lädt, mit Darstellungsfehlern [8]. Einen vollständigen
    Windows-Steam-Client unter FEX bestätigt keine Quelle.
- **Alternative: Steam für Mac als Brücke.** Es ist schon universal [Mac]. MetalSharp und `neutron` lassen Windows-Spiele
  so an Mac-Steam hängen [8][9] **[gemeldet, `neutron` nicht mehr erreichbar]**. Das wäre eine größere Änderung an
  Nightforges Steam-Weg, aber der Weg, der keine 32-Bit-Teile braucht.
- CrossOvers Vorschau hat laut Sekundärquellen Einschränkungen bei Launchern [6]. Die Originalseite war nicht lesbar.

### 4.4 DirectX 12

Ohne D3DMetal bleiben Mullions noch frühes D3D12 und VKD3D-Proton als Option [8]. Wukong, Control und andere
DX12-Spiele hätten damit keinen geprüften Weg. Overwatch hängt zudem an `libd3dshared` (`nightforge-engine-04`).

### 4.5 Leistung

- MetalSharp misst auf einem M4 nur Kleinstprogramme: x86_64 etwa wie nativ bei Integer- und Gleitkomma-Last, 1,67-fach
  bei CPython, 32-Bit 2,42-fach, kalter JIT 380-fach [8] **[Beleg]**.
- Einen Vergleich mit Rosetta und Zahlen aus Spielen gibt es nicht [8][9]. Ein Projekt setzt sich 70 % als Schwelle, mit dem
  Hinweis, das sei eine Einschätzung [9].
- TSO läuft bei MetalSharp per Emulation, nicht in Hardware. Red Dead Redemption 2 hängt ohne [7] **[Beleg]**.

### 4.6 Anti-Cheat

Keine Quelle sagt etwas zu Anti-Cheat unter FEX auf dem Mac. Nightforges Regeln bleiben: keine Umgehung, Hinweis vor dem Download.

## 5. Reihenfolge

Daten: CrossOver 27 wird für Anfang 2027 erwartet [6]. Die Betas von macOS 28 etwa ab Juni 2027 sind eine Erwartung, keine
Aussage von Apple [9]. Der Release wäre nach bisherigem Muster im Herbst 2027 **[Vermutung]**.

| Schritt | Inhalt | Voraussetzung |
|---|---|---|
| **0. Jetzt** | Abschnitt 6, Kontofrage klären, Beobachtung | keine |
| **1. Engine wählen** (bis ~Mai 2027) | Upstream-Wine mit Shanks' Patches, CodeWeavers' Quellen, oder ein Community-Zweig. Sonst: Nutzer bleiben auf macOS 27 | Patches oder Quellen öffentlich |
| **2. Prototyp** | Eigener Prefix, ein 64-Bit-Spiel über Epic/GOG mit DXMT (ABZU), gleicher Tag gegen die x86_64-Engine | Schritt 1, Fremdcode mit dem OK des Nutzers |
| **3. Entscheidung Leistung** | Eigene Schwelle vorher festlegen, etwa 80 % der Bildrate und keine neuen Stopps | Schritt 2 |
| **4. Eigene Teile** | Helfer, Layer, Pfade je Architektur, `winemac`-Haken, Komponenten je Architektur | Schritt 3 |
| **5. 32-Bit und Steam** | Mit Entitlement: WoW64 und Windows-Steam. Ohne: Steam für Mac als Brücke prüfen | Kontofrage |
| **6. DX12** | Beobachten, ob Apple D3DMetal für arm64 bringt. Sonst D3D12 über Mullion oder VKD3D prüfen | offen |
| **7. Parallel ausliefern** | x86_64-Engine bis macOS 27, ARM64-Engine ab 28. Spiele ohne Weg klar benennen | Schritte 4–6 |

Der realistische Fall für Herbst 2027 **[Vermutung]**: 64-Bit-Spiele mit DirectX 10/11 über Epic und GOG zuerst, Steam danach,
DirectX 12 und 32-Bit je nach Apple und Konto später.

## 6. Was jetzt ohne Risiko geht

Nichts davon lädt Fremdcode oder ändert das Verhalten für Spieler auf macOS 27. Gebaut am 8.11. auf `claude/arm64-vorbereitung`:

1. **Hinweis für macOS 28** (gebaut, `RosettaSupport.swift`). Ab macOS 28, wenn `arch -x86_64` nicht läuft: bei der Einrichtung
   und beim Start eines Windows-Spiels ein klarer Satz, ohne Install-Knopf und ohne Versprechen. Bis macOS 27 wird nichts
   zusätzlich geprüft und nichts anders angezeigt. Auf macOS 28 kann noch niemand testen: siehe Punkt 8.
2. **Komponenten mit Architektur** (gebaut). Optionales Feld `arch`, fehlt es: x86_64. Nightforge lässt Einträge weg, die
   nicht unter Rosetta laufen. Alte Apps ignorieren das Feld und würden einen arm64-Bau für ihren halten, darum verlangt
   `validate-manifest.py` dafür eine eigene Kennung (`wine-arm64`). In der echten Liste steht es noch nirgends.
3. **Pfade bündeln** (gebaut, `WineFolders.swift`). Nur `Engine.swift`; `D3DMetalSupply.swift` beschreibt Apples eigenes
   Paket und bleibt.
4. **Eigene Helfer: anders als hier ursprünglich geplant.** Nur der Vulkan-Layer ist jetzt universal, ihn lädt allein der
   x86_64-Loader im Spielebündel. Dock-Hider und Sandbox-Helfer bleiben x86_64, sonst änderte sich das Verhalten:
   `DYLD_INSERT_LIBRARIES` geht an alles, was Steam startet. Heute überspringen arm64-Programme die Bibliothek, universal
   würden sie sie samt AppKit laden. Der Sandbox-Helfer liefe als arm64, weil Nightforge ihn aus einem arm64-Prozess startet.
   Dass beide für arm64 bauen, prüft `tests/test_helper_architectures.py`. Universal werden sie mit der ARM64-Engine.
5. **Keine neuen x86_64-Abhängigkeiten** (Prüfung gebaut, `tests/test_no_new_x86_only.py`, Regel in `CONTRIBUTING.md`).
6. **Vergleichswerte** (gebaut). Berichte sagen jetzt, wie Wine lief (`runsOn`). Die drei Spieletests vom 3.11. mit gemessenen
   Bildraten liegen in `docs/spieletest`. Das ist wenig: ABZU und The Forest, teils mit belastetem Mac. Ein Lauf auf
   ruhigem Mac wäre die bessere Basis.
7. **Beobachtungsliste, monatlich:** Abschnitt 8.
8. **Sobald eine macOS-28-Beta da ist:** `tests/arm64/macos28-probe.sh` auf einem Testvolumen, das nicht zum Spielen dient,
   vor und nach `game-test-tool enable` (der Schalter stellt Rosetta ab [4]). Das Skript zeigt auch, ob `/usr/bin/true` noch
   einen x86_64-Teil hat. **[Vermutung]** Fehlt er, schlüge die Prüfung aus Punkt 1 auch bei vorhandenem Rosetta an. Dann
   muss sie vor dem ersten Einsatz ein anderes Programm nehmen.

## 7. Entscheidungen für den Nutzer

1. **Apple-Developer-Konto?** Davon hängen 32-Bit-Spiele und wohl Windows-Steam ab, außerdem Notarisierung und Signaturweg.
2. **Fremdzweig oder warten?** Ein Community-Zweig wie MetalSharp wäre früher da, bindet aber an ein kleines Projekt (35 Sterne,
   eigene Skripte unter AGPL [7]). Empfehlung: warten bis Mai 2027, dann entscheiden.
3. **Was sagen wir den Spielern?** Empfehlung: nichts versprechen, ab der macOS-28-Beta klar benennen, was geht.
4. **Spieletest-Werte im Repository?** Die drei Berichte in `docs/spieletest` werden mit dem Merge öffentlich. Die Prüfung
   des Importers fand weder Namen noch Pfade. Sie enthalten Spielenamen, Bildraten und „Apple M5 · macOS 27.0“.
5. **Wer geht die Beobachtungsliste durch?** Von Hand, oder eine monatliche Aufgabe, die nur liest und berichtet.
6. **Testvolumen für die Beta?** Sobald es eine macOS-28-Beta gibt: ein eigenes APFS-Volumen dafür, oder bis zum Release warten.

## 8. Beobachtungsliste

Monatlich durchgehen und die Spalte „Stand“ fortschreiben. Solange nichts Neues kommt, bleibt alles wie heute.

| Was | Wo | Worauf es ankommt | Stand (8.11.2026) |
|---|---|---|---|
| Wine: Merge-Requests zu macOS/ARM64 | https://gitlab.winehq.org/wine/wine/-/merge_requests?scope=all&state=all&search=macOS+ARM64 | Sind Shanks' Patches eingereicht oder gemergt, ab welcher Version? | Am 7.11. nicht eingereicht [5] |
| CrossOver 27 und seine Quellen | https://www.codeweavers.com/crossover/source | Liegen die ARM64-Quellen offen? Bleiben 32-Bit-Flaschen? | Vorschau seit 31.7. [6], Seite nicht lesbar (403) |
| FEX für macOS | https://github.com/FEX-Emu/FEX/issues/5222 | Gibt es upstream einen macOS-Bau? Vergleich mit Rosetta aus einem Spiel? | Nur Fremdzweige [7][8][12], keine Spielzahlen |
| DXMT mit arm64-Paket | https://github.com/3Shain/dxmt/releases | Liefert ein Release die arm64-Unix-Seite? Gehen die winemac-Haken? | x86_64-Paket [10], arm64 nur in der CI gemeldet [9] |
| Toolkit und D3DMetal für arm64 | https://developer.apple.com/games/game-porting-toolkit/ | Nennt Apple eine arm64-Fassung? | Toolkit 3.0 ist x86_64 [Mac] |
| Apples Definition der Altspiele | https://support.apple.com/en-us/102527 | Liste, API oder Schlüssel? Wird Wine genannt? | Nichts davon [1][2][3][4] |

## Quellen

Gelesen am 8.11.2026, sofern nicht anders vermerkt.

1. Apple Developer News, „Upcoming changes to Rosetta support for Intel-based macOS apps“, 1.9.2026:
   https://developer.apple.com/news/?id=w5ngl9k2
2. Apple, „About the Rosetta translation environment“:
   https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
3. Apple Support 102527, 21.9.2026: https://support.apple.com/en-us/102527
4. macOS 27 Release Notes (nur als Auszug gelesen):
   https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes.
   Der Entitlement-Pfad unter `developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/` ergab 404.
5. wine-devel, „Wine on ARM64 macOS“ (Brendan Shanks, CodeWeavers, 7.8.2026, Antworten bis 7.11.2026):
   https://list.winehq.org/hyperkitty/list/wine-devel@list.winehq.org/thread/CKG5CEN2BE5VRXZ7O7NX4YUSBH3247WH/
6. CrossOver-Vorschau. Die Blogartikel von CodeWeavers antworten mit 403, ihre Aussagen stammen aus Suchauszügen und
   Sekundärquellen, die sich beim Zieltermin widersprechen:
   https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac,
   https://borncity.com/news/crossover-fuer-mac-arm64-version-ohne-rosetta-2-verfuegbar/,
   https://www.ithinkdiff.com/crossover-preview-native-arm64-support-rosetta-2/,
   https://appleinsider.com/articles/26/06/11/crossover-a-windows-to-mac-gaming-tool-goes-apple-silicon-only
7. MetalSharp-Wine, README: https://github.com/metalsharp/MetalSharp-Wine
8. MetalSharp-Wine, `docs/STATUS.md` (23.10.2026) und `docs/PERFORMANCE.md` (22.10.2026, M4):
   https://github.com/metalsharp/MetalSharp-Wine/tree/main/docs
9. Cities-Skylines-2-Portierung: Issue #16 und `docs/plans/arm64-migration.md`:
   https://github.com/macgameport/cities-skylines-2-macos/issues/16.
   Das dort genannte `lixsldotnet/neutron` ergab 404.
10. DXMT, README, `docs/DEVELOPMENT.md`, Releases: https://github.com/3Shain/dxmt
11. Wine auf ARM64 unter Linux mit FEX (GamingOnLinux, 6.11.2025):
    https://www.gamingonlinux.com/2025/11/codeweavers-launch-a-new-crossover-preview-adding-linux-arm64-support
12. FEX, Issue #5222 (ARM64EC/WoW64-Bau für Wine): https://github.com/FEX-Emu/FEX/issues/5222

Nicht lesbar: die Blogartikel von CodeWeavers (403), Phoronix (403). Die Notiz `hermes/queue-035/rosetta28.md` diente nur als
Wegweiser.
