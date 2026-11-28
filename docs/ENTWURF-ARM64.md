# Entwurf: Nightforge ohne Rosetta (ARM64-Wine mit FEX)

Studie vom 8.11.2026. Nur gelesen und recherchiert: nichts geladen, gebaut oder gestartet.

**Nachtrag vom 21.11.2026: Abschnitt 9.** Dort stehen der Stand von heute, ein halber Prototyp, der Plan bis zur
macOS-28-Beta und die Entscheidungen. Wo er den Abschnitten 1 bis 7 widerspricht, gilt Abschnitt 9.

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

Stand 8.11. Fortgeschrieben und neu geordnet in Abschnitt 9.7.

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

| Was | Wo | Worauf es ankommt | Stand (21.11.2026) |
|---|---|---|---|
| Wine: Merge-Requests zu macOS/ARM64 | https://gitlab.winehq.org/wine/wine/-/merge_requests/12716 | Ist der Merge-Request gemergt, ab welcher Version? Bleibt macOS 27 die Untergrenze? | Eingereicht am 18.11., offen, verlangt macOS 27 [16] |
| CrossOver 27 und seine Quellen | https://www.codeweavers.com/crossover/source | Ist 27 erschienen? Liegen die ARM64-Quellen samt FEX offen? Bleiben 32-Bit-Flaschen? | Nicht erschienen, Quellen nur für 26.3.0, ohne FEX [18] |
| FEX für macOS | https://github.com/FEX-Emu/FEX/releases | Gibt es upstream einen macOS-Bau? Vergleich mit Rosetta aus einem Spiel? | Upstream nur Linux (FEX-2611.1), offen bei athei/FEX, keine Spielzahlen [20][23] |
| DXMT mit arm64-Paket | https://github.com/3Shain/dxmt/releases | Liefert ein Release ARM64X? Kommt Direct3D 12 (DXIL)? | Release 0.80 nur x86_64, ARM64X bei mach9, DXIL in Arbeit [19][21] |
| Toolkit und D3DMetal für arm64 | https://developer.apple.com/games/game-porting-toolkit/ | Nennt Apple eine arm64-Fassung? | Toolkit 4 in der Beta, keine arm64-Fassung genannt [24]; hier 3.0, x86_64 [Mac] |
| Apples Definition der Altspiele | https://support.apple.com/en-us/102527 | Liste, API oder Schlüssel? Wird Wine genannt? | Laut Apple-Ingenieur Mac-Spiele für Intel [14]; keine Liste, Wine nicht genannt |
| mach9, die fertige ARM64-Engine | https://github.com/athei/mach9/releases | Erscheint es weiter? Bleibt der Loader notarisiert und das Profil gültig? Was ändert sich für einbettende Launcher? | 0.4.0 vom 17.11., fünf Releases seit 7.11. [19] |
| Berechtigung für kostenlose Konten | https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-Building/ARM64-Provisioning-Profiles | Fällt die Pflicht zum bezahlten Konto? Dokumentiert Apple die Berechtigung? | Bezahltes Konto nötig, bei Apple als Fehler geführt, keine Doku [15][17] |

## 9. Stand November 2026

Nachtrag vom 21.11.2026, auf diesem Mac (macOS 27.2.1, Apple M5, nur die Command Line Tools). Anders als bei der Studie
wurde geladen, gebaut und gestartet; was genau, steht in 9.3. Die Quellen [13] bis [24] sind vom 21.11.
**[Helfer]** heißt: Die Seite hat ein Hilfsprogramm gelesen und berichtet, nicht ich selbst.

> **Nachtrag 23.11.2026 (nach staging geholt, Zweig `claude/arm64-plan-04`).** Der Abschnitt stammt vom Zweig
> `claude/vibrant-meninsky-0f7097` (26756f3f) und steht hier unverändert. Was seitdem überholt ist, trägt den Vermerk
> **[überholt 23.11.]**. Grundlage ist die Engine-Bestandsaufnahme vom 23.11. (`ROADMAP-0.4.md`, „Engines zuerst“).
> Neu nachgesehen im Netz wurde dafür nichts. Die Stände von mach9, MetalSharp, Wines Merge-Request und FEX sind die
> vom 21.11.
>
> | Am 21.11. | Stand 23.11. |
> |---|---|
> | Plan ab „Dezember 2026, nach 0.3.3“ | 0.3.4 ist erschienen, 0.3.5 im Release. Rosetta ist Punkt 5 der Roadmap 0.4, nach D3DMetal 4, Startzeit, Kompatibilitätsliste und Klassikern. M0 rückt damit hinter diese Punkte. |
> | Direct3D 12 über „vkd3d“ (CrossOvers Bausteinliste) | Wines eigenes vkd3d 2.x reicht für die Spiele nicht. Gemeint ist durchweg **vkd3d-proton 3.1**, und dem fehlt auf KosmicKrisp Transform Feedback (Caretaker-Demo, `TODO.md`). |
> | DXMT „Release 0.80 vom April“ | Weiterhin kein neuer Release seit April. Nightforge fährt 0.80 mit eigenen Patches. ARM64X gibt es nur aus fremdem Bau (mach9). |
> | GPTK 4: „eine arm64-Fassung … nirgends angekündigt“ | Bestätigt: GPTK 4 (4.0b3) hat kein arm64. Auf ARM64 bleibt D3DMetal also ganz weg, auch die neue Wahl „D3DMetal 4 zulassen“ (Zweig `claude/d3dmetal4-messen-04`). |
> | Prototyp unter `tests/arm64/` | Die Quellen und `fex-proto.sh` liegen weiter nur auf `claude/vibrant-meninsky-0f7097` (357137e5), nicht in staging. Für den FEX-Lauf aus 9.3 b) diesen Zweig auschecken oder die fünf Dateien von dort holen. |

### 9.1 Kurzfassung

1. **Es geht, und es gibt es fertig.** Das Projekt mach9 hat seit dem 7.11. fünfmal ein ARM64-Wine mit FEX, DXMT,
   vkd3d-proton und Windows-Steam veröffentlicht, nach eigenen Worten „made to be embedded in a launcher“ [19]. Der
   Loader ist mit Developer ID signiert, von Apple notarisiert und trägt die Berechtigung in einem Profil, das für
   alle Macs gilt **[Mac]**.
2. **Wine zieht nach.** CodeWeavers hat die Patches am 18.11. bei Wine eingereicht (Merge-Request 12716, offen). Sie
   verlangen macOS 27 [16].
3. **Die Berechtigung braucht ein bezahltes Apple-Entwicklerkonto**, 99 US-Dollar im Jahr. Das sagen Apple und Wine
   übereinstimmend [15][17]. Ohne sie startet ein selbst gebautes ARM64-Wine hier nicht; die Probe in 9.3 zeigt, woran.
   Wer mach9s signierten Loader einbettet, braucht kein eigenes Konto.
4. **Der Prototyp ist halb fertig.** Die Rosetta-Seite ist gemessen. Die FEX-Seite ist vorbereitet, aber nicht gelaufen:
   Diese Sitzung darf kein Programm starten, das sie aus dem Netz geladen hat. Ein Befehl des Nutzers holt das nach (9.3).
5. **Direct3D 12 verliert D3DMetal**, und mit ihm dessen Lizenzfrage. An seine Stelle tritt vkd3d-proton auf KosmicKrisp.
   Für Wukong, Control und Overwatch ist das ungeprüft. **[überholt 23.11.]** Gemeint ist vkd3d-proton 3.1, nicht Wines
   vkd3d 2.x. Dem fehlt auf KosmicKrisp heute Transform Feedback.

Die drei offenen Punkte der Studie:

| Offen am 8.11. | Antwort am 21.11. |
|---|---|
| Bekommt ein kostenloses Konto die Berechtigung? | Nein. Apple: „only available to paid teams“ [15]. Die Variante für kostenlose Konten gibt es, sie lässt sich aber nicht beantragen; Apple führt das als Fehler. |
| FEX gegen Rosetta in Zahlen | Weiter nirgends veröffentlicht. Die eigene Messung hat erst die Rosetta-Hälfte (9.3). |
| CodeWeavers' Blog | Sperrt automatische Abrufe weiter (403). Bekannt ist nur, was Suchauszüge zeigen. |

### 9.2 Was heute gilt

**Apple**

| Punkt | Stand | Quelle | Art |
|---|---|---|---|
| Rosetta | macOS 27 ist die letzte Version mit Rosetta für Intel-Apps. Bestehen bleibt ein Teil für „older, unmaintained gaming titles that rely on Intel-based frameworks“. Ab macOS 28 gilt das laut Supportseite nur für „certain“ solche Spiele. | [1] vom 1.9., [3] vom 21.9. | [Beleg], im Wortlaut gelesen |
| Release Notes zu macOS 27 | Jetzt ganz gelesen. Intel-Software ist mit macOS 28.0 nicht mehr kompatibel, „excluding legacy games“. In Betas schaltet `sudo game-test-tool enable` die Altspiel-Unterstützung ein. Das schaltet Rosetta ab, andere Prozesse können abstürzen, und außerhalb von Betas gibt es das Werkzeug nicht. Rosetta kommt beim Upgrade auf 27.0 nicht von selbst zurück. Die Systemeinstellungen listen Intel-Apps, die mit 28 enden; Spiele sollen dort nicht stehen (ein behobener Fehler zeigte „Steam Game“). | [4] | [Beleg] |
| Dieser Mac | Unter 27.2.1 ist Rosetta installiert und läuft. `game-test-tool` gibt es nicht. `/usr/bin/true` hat noch einen x86_64-Teil. | | [Mac] |
| Welche Spiele | Ein Apple-Ingenieur im Entwicklerforum, Juni 2026: „x86_64 macOS games should continue to work as they do on macOS 26.“ Gemeint sind Mac-Spiele für Intel. Wine, CrossOver und Windows-Spiele nennt Apple weiter nirgends. | [14] | [Beleg], [Helfer] |
| Schnittstellen | Apple hat gebaut, was ein ARM64-Wine braucht: den Start mit 4K-Seiten (`posix_spawnattr_set_4k_page_size_np`, ab 26.0) und die freie Nutzung des Registers x18 (`os_set_custom_x18_abi_enabled`, ab 26.4). Der Kommentar im SDK nennt als Zweck „compatibility layers for other ABIs“. | [13] | [Mac] |
| Berechtigung | Xcode 27 kennt die Fähigkeit „Cross-architecture Compatibility Framework“. Sie ergibt `com.apple.developer.cross-architecture-support`. Eine Dokumentation gibt es noch nicht. Für kostenlose Konten siehe 9.1. | [15], Sept. und Okt. 2026 | [Beleg], [Helfer] |
| Game Porting Toolkit | Version 4 ist seit der WWDC 2026 in der Beta. Eine arm64-Fassung von D3DMetal oder der Testumgebung habe ich nirgends angekündigt gefunden. Das hier installierte D3DMetal 3.0 ist x86_64. **[überholt 23.11.]** Bestätigt: Auch GPTK 4 (4.0b3) hat kein arm64. | [24]; [Mac] | nur gesucht, nicht bei Apple gelesen |

**[Vermutung]** Zusammen genommen: Apple lässt Rosetta für Windows-Spiele auslaufen und öffnet zugleich den Weg für ein
natives Wine. Auf die Spiele-Ausnahme zu bauen wäre falsch, sie meint Mac-Spiele.

**Wine und CodeWeavers**

| Punkt | Stand | Quelle | Art |
|---|---|---|---|
| Wine | Merge-Request 12716 „Add support for ARM64 on macOS“ von Brendan Shanks: eingereicht am 18.11.2026, 12 Commits, offen, 26 Kommentare (ohne Anmeldung nicht lesbar), zurzeit mit Konflikten. Er verlangt macOS 27: Die Schnittstellen gibt es ab 26.5, aber erst 27 hält die unteren 8 GB des Adressraums frei. Neu sind `--enable-codesign-identity` und `--enable-provisioning-profile`. Ohne Profil warnt `configure`, Wine stürze beim Start ab. | [16] | [Beleg] |
| Wines Wiki | „a paid Apple Developer membership ($99/year) is required“; an kostenlosen Konten werde gearbeitet. Beschrieben ist ein Entwicklungsprofil, das an registrierte Macs gebunden ist. | [17] | [Beleg] |
| CrossOver 27 | Nicht erschienen, soweit erkennbar: Die Quellseite bietet nur 26.3.0, das Blog-Verzeichnis zeigt bis zum 16.9. keinen Release. Aus Suchauszügen: Vorschau seit 31.7. mit ARM64-Wine und eigenem FEX ab macOS 26.5, nach eigenen Worten „still very unpolished“; CrossOver 27 Anfang 2027, nur noch für Apple silicon, ohne 32-Bit-Flaschen. | [6][18] | [gemeldet] |
| „27.0 braucht kein Rosetta“ | Das ist eine Forenmeinung, keine Aussage von CodeWeavers. Ein anderer Forennutzer berichtet, die Beta starte 32-Bit-Programme über FEX. | [6][15] | [gemeldet] |
| Quelltext | Offen liegt nur CrossOver 26.3.0. Die Liste der Bausteine nennt Wine, vkd3d, DXVK, MoltenVK und LLVM; FEX, DXMT und D3DMetal fehlen. **[überholt 23.11.]** Das vkd3d dort ist Wines vkd3d 2.x. Für Direct3D-12-Spiele reicht es nicht, der Plan meint vkd3d-proton. CodeWeavers legt GPL- und LGPL-Teile je Release offen, für 27 also erst mit dem Release. | [18] | [Beleg], [Helfer] |

**FEX, DXMT, DXVK, Direct3D 12**

| Punkt | Stand | Quelle | Art |
|---|---|---|---|
| FEX | Lizenz MIT. Upstream nennt sich weiter einen Emulator „for Arm64 Linux“, letzter Release FEX-2611.1 vom 11.11.2026. Einen macOS-Bau gibt es dort nicht, aber Mac-Nutzer melden dort Fehler (Overwatch hängt nach zwei Minuten, 19.11.). macOS-Fassungen: CodeWeavers (nicht offen), athei/FEX (offen, MIT), MetalSharp. | [20][23] | [Beleg] |
| DXMT | Lizenz LGPL 2.1 oder neuer, „Feifan He for CodeWeavers“. Release 0.80 vom April enthält nur x86_64. **[überholt 23.11.]** Seit April weiterhin kein Release. Im Repository liegt `build-arm64ec.txt` mit `-marm64x`. mach9 liefert DXMT als ARM64X: Ein x64-Spiel lädt die native Hälfte, nur der Code des Spiels läuft durch FEX. | [21][19] | [Beleg] |
| DXVK | Keines der beiden freien Projekte nimmt es als Standard. MetalSharp bietet es als Schalter, mach9 nimmt für Direct3D 9 das eigene mtld3d (zlib). | [19][22] | [Beleg] |
| Direct3D 12 | D3DMetal gibt es für arm64 nicht. mach9 nimmt vkd3d-proton auf KosmicKrisp; laut Notiz zu 0.4.0 stürzen Unreal-5-Spiele mit `-dx12` im Menü nicht mehr ab. MetalSharp nimmt Mullion, wahlweise VKD3D-Proton. Zu Wukong oder Control berichtet niemand. DXMT bekommt seit November Befehle für DXIL, die Shader-Form von Direct3D 12. **[Vermutung]** Das deutet auf Direct3D 12 in DXMT. | [19][21][22] | [Beleg] |

**Die zwei fertigen ARM64-Engines**

| | mach9 [19] | MetalSharp-Wine [22] |
|---|---|---|
| Stand | 0.4.0 vom 17.11.2026, fünf Releases seit 7.11. | 8.0 vom 18.11.2026 |
| Wine | 11.21 mit CrossOvers Patches (msync) und eigenen | 11.20 |
| Grafik | DXMT (10/11), vkd3d-proton (12), mtld3d (9), Zink (OpenGL) | Mullion (9 bis 12), VKD3D-Proton, DXVK |
| Windows-Steam | läuft laut README | Anleitung im README |
| 32 Bit | ja, über FEX | ja, ab macOS 26.4 |
| macOS | ab 26.4 | ab 15 |
| Download | 132 MB, entpackt 1,1 GB [Mac] | 994 MB |
| Eigene Teile | zlib | AGPL 3.0 |
| Für fremde Launcher | ja: den Ordner `wine/` einbetten, `wine.app` nicht anfassen, Regeln je Spiel über `WINE_COMPATDB` | als App für den eigenen Launcher |
| Sterne auf GitHub | 38 | 37 |

Beide enthalten Wine (LGPL 2.1 oder neuer). mach9 enthält dazu FEX (MIT), DXMT und vkd3d-proton (LGPL 2.1), Mesa (MIT),
GStreamer mit FFmpeg (in der Regel LGPL, nicht nachgeprüft) und mtld3d (zlib) [19][23]. Unter `share/licenses` liegen
im Paket nur vier Texte, die LGPL ist nicht dabei **[Mac]**.

**Was mach9s Signatur zeigt [Mac]** (mit `codesign`, `spctl` und `security cms` gelesen, nichts gestartet):

- Signiert von „Developer ID Application: Alexander Theissen (WLKUUJD25W)“, gehärteter Lauf. Gatekeeper: „accepted,
  source=Notarized Developer ID“.
- Berechtigungen: `com.apple.developer.cross-architecture-support`, `com.apple.security.custom-x18-abi-toggle`,
  `cs.allow-jit`, `cs.disable-executable-page-protection`, `cs.disable-library-validation`, `device.audio-input`.
- Das eingebettete Profil „Mach9 Loader“ gilt für alle Geräte (`ProvisionsAllDevices`), erstellt am 15.10.2026, gültig
  bis 10.10.2044. **Der Weg mit Developer ID reicht also für den Vertrieb an alle**, anders als das Entwicklungsprofil
  aus Wines Wiki. Das beantwortet die Frage aus 4.1.
- Der Loader heißt „Mach9“ (`app.mach9.loader`), Kategorie Spiele, mit Game Mode. So hieße jeder Spielprozess.
- `cs.allow-dyld-environment-variables` fehlt: `DYLD_INSERT_LIBRARIES` wirkt im Loader nicht. So lädt Nightforge heute
  `hide-steam-dock` in Wines Prozesse. `disable-library-validation` erlaubt dagegen eigene, anders signierte
  Unix-Bibliotheken wie Nightforges `winebus.so`.
- Laut mach9s Doku startet Wine ohne die Berechtigung gar nicht, einen Rückfall auf 16K-Seiten gibt es nicht. Wer das
  Paket einbettet, darf `wine.app` weder neu signieren noch ändern [19].

### 9.3 Prototyp

Alles liegt in `build/arm64` (von git ignoriert), die Quellen und das Skript in `tests/arm64/`. Nightforges Prefix und
sein laufendes Wine blieben unberührt; während der Läufe lief auf dem Mac die Live-Runde zu 0.3.3.

**a) Laden und prüfen: lief.**

```
$ curl -L -o wine-v0.4.0-macos-arm64.tar.xz https://github.com/athei/mach9/releases/download/v0.4.0/wine-v0.4.0-macos-arm64.tar.xz
http 200 bytes 131698496
$ shasum -a 256 wine-v0.4.0-macos-arm64.tar.xz
3b81aac9b93d5652872673b400769ec525f3bc2f1f7e2ec82c9f851d0a0db05d
$ spctl -a -t exec -vvv wine/lib/wine/aarch64-unix/wine.app
accepted
source=Notarized Developer ID
origin=Developer ID Application: Alexander Theissen (WLKUUJD25W)
$ lipo -archs wine/lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine
arm64
```

**b) Das ARM64-Wine starten: nicht gelaufen.** Schon `wine --version` hat die Sicherheitsprüfung dieser Sitzung
abgelehnt. Sie startet kein Programm, das sie selbst aus dem Netz geladen hat, auch kein notarisiertes. Das ist eine
Grenze der Sitzung, nicht von macOS. Nachholen kann es der Nutzer mit zwei Befehlen, etwa fünf Minuten:

```
tests/arm64/fex-proto.sh fex build/arm64/mach9-0.4.0/wine
tests/arm64/fex-proto.sh table
```

Der Lauf nimmt einen eigenen Prefix in `build/arm64`, öffnet kein Fenster und startet keinen Loader, den macOS nicht als
notarisiert annimmt. Diese Hälfte des Skripts ist ungetestet. Scheitert der Direct3D-Teil ohne Fenster, lässt
`PROTO_WINDOWS=1` Wines Mac-Treiber an.

**c) Was macOS ohne die Berechtigung erlaubt: lief.** Ein eigenes arm64-Programm versucht, was Wines Loader braucht
(`tests/arm64/proto/entitlement-probe.c`), ad hoc signiert, ohne Schlüssel und ohne Profil:

```
$ tests/arm64/fex-proto.sh probe
macOS 27.2.1, ad hoc signed, no entitlement:
probe: page size 16384
pages: posix_spawn: Malformed Mach-o file
low: memory at 0x1000000: (os/kern) invalid address
x18: custom use switched on and off again
ad hoc signed, claiming com.apple.developer.cross-architecture-support without a profile:
... Killed: 9
exit code 137 (137: macOS killed it at the start)
```

- **4K-Seiten:** Der Start wird verweigert. mach9 und Wines Merge-Request sehen keinen Rückfall auf 16K-Seiten vor.
  Dass es an der Berechtigung liegt, sagen mach9s Doku und die Warnung in Wines `configure` [16][19]; die Probe
  selbst zeigt nur die Weigerung.
- **Speicher unter 4 GB:** verweigert. Den brauchen 32-Bit-Programme und 64-Bit-Programme mit fester Ladeadresse.
- **x18:** geht auch ohne Berechtigung.
- **Berechtigung nur behaupten:** macOS beendet das Programm beim Start.
- Mit Wines Linker-Schaltern (`-pagezero_size,0x200000000`, `-x86_64_layout_emulation`, `-no_fixup_chains`) ist das
  Ergebnis dasselbe. Der Linker der Command Line Tools nimmt sie an.

Ein selbst gebautes ARM64-Wine scheitert hier also nicht am Bauen, sondern am Start. Es fehlt genau ein Profil mit der
Berechtigung, und das gibt es nur mit dem bezahlten Konto. Für DXMT fehlt diesem Mac zusätzlich Xcodes Metal-Compiler.

**d) Die Rosetta-Seite: lief.** Dieselben Programme, die später unter FEX laufen sollen, in einer Kopie der heutigen
Engine (winecx 4.7.3, Wine 11.17, DXMT 0.80) mit eigenem Prefix:

```
$ tests/arm64/fex-proto.sh rosetta 3
side: rosetta
wine: wine-11.17
loader: x86_64
macOS: 27.2.1, Apple M5, load 4.87 3.81 3.07
hello from a 64-bit x86 Windows program
process machine: none (not WoW64), native machine: x86_64
cpuid vendor: GenuineIntel, hypervisor leaf: , brand: VirtualApple @ 2.50GHz
hello from a 32-bit x86 Windows program
process machine: i386, native machine: x86_64
d3d11off 64-bit
device: feature level 0xb000, created in 34 ms
d3d11.dll: Z:\...\build\arm64\proto\rosetta64\d3d11.dll
winemetal.dll (DXMT): loaded
adapter: Apple M5 (vendor 0x106b)
picture: corner ff007fff, centre ff00ff00: PASS
```

Der Direct3D-Test zeichnet ohne Fenster in eine Textur und liest einen Bildpunkt zurück. Gemessen, je der beste von
drei Läufen, in Millisekunden:

| Test | Was er belastet | Rosetta, 64 Bit | Rosetta, 32 Bit | FEX |
|---|---|---:|---:|---|
| `int_hash` | Rechnen in Registern | 338 | 827 | offen |
| `sieve` | Schreiben in Speicher | 336 | 285 | offen |
| `sort` | `qsort` der C-Laufzeit mit Rückruf ins Programm | 348 | 577 | offen |
| `mandel` | Gleitkomma: SSE2 in 64 Bit, x87 in 32 Bit | 65 | 6836 | offen |
| `fib` | Aufrufe und Rücksprünge | 91 | 89 | offen |
| `api_calls` | 23 Mio. Windows-Aufrufe im Prozess | 698 | 742 | offen |
| `heap` | 4 Mio. `HeapAlloc`/`HeapFree` | 209 | 272 | offen |
| `events` | 600 000 Aufrufe an ein Ereignis (msync) | 128 | 140 | offen |
| `threads` | acht Threads, gesperrte Befehle | 122 | 136 | offen |
| Direct3D 11, 20 000 kleine Zeichenaufrufe je Bild | Prozessorseite von DXMT | 6,5 | 17,7 | offen |
| Direct3D 11, schwerer Pixel-Shader auf 2048 × 2048 | Grafikchip | 2,2 | 2,1 | offen |
| Start von `hello64.exe` bei laufendem Wine-Server | Prozessstart | 35 | | offen |

Was die Zahlen sagen und was nicht:

- Es sind Kleinstprogramme. Sie zeigen, wo sich die beiden Wege unterscheiden werden, nicht wie ein Spiel läuft.
- Der Mac war nicht ruhig. Für den Vergleich beide Seiten direkt nacheinander messen.
- x87-Gleitkomma ist unter Rosetta rund hundertmal langsamer als SSE2 (6836 gegen 65 ms). Das trifft alte
  32-Bit-Spiele. mach9 schaltet für x87 eine verringerte Genauigkeit ein [19]. **[Vermutung]** Dort dürfte FEX klar
  vorn liegen, mit anderer Prüfsumme in dieser Zeile.
- 32-Bit-Zeichenaufrufe kosten unter Rosetta das 2,7-Fache der 64-Bit-Aufrufe.
- Auf der FEX-Seite läuft ein anderes Wine (11.21) und ein anderes DXMT. Der Vergleich misst die beiden Engines, wie
  Nightforge sie ausliefern würde, nicht FEX und Rosetta allein.

### 9.4 Plan bis zur macOS-28-Beta

Reihenfolge wie in Abschnitt 5, jetzt mit Monaten. Die Beta im Juni 2027 ist eine Erwartung, keine Zusage von Apple.

| Monat | Meilenstein | Fertig, wenn |
|---|---|---|
| **Dezember 2026**, nach 0.3.3 **[überholt 23.11.: nach den Engine-Punkten 1–4 der Roadmap 0.4]** | **M0 Zahlen und Weg.** Der Nutzer startet den FEX-Lauf aus 9.3. Entscheidungen 1 bis 3 aus 9.7. | Die Spalte „FEX“ ist gefüllt, und es steht fest, ob der erste Versuch mit mach9s Loader läuft. |
| **Januar 2027** | **M1 Ein Spiel.** Hinter einem versteckten Testschalter: Baustein `winecx-arm64` (Arbeitstitel) mit `arch: arm64`, eigener Prefix `Prefix-arm64`, ABZU (64 Bit, Direct3D 11, GOG oder Epic) startet aus Nightforge über DXMT. Dazu nachsehen, ob Wine 12 den Merge-Request enthält. | ABZU startet und endet aus Nightforge, die Bildrate steht neben der der x86_64-Engine vom selben Tag. |
| **Februar 2027** | **M2 Eigene Teile** (9.5): Ordner und Loader je Engine, Grafikweg ohne D3DMetal, Regeln je Spiel, Controller, Overlay, Vorhang, Diagnose. | Der Testkorb der 64-Bit-Spiele mit Direct3D 9 bis 11 von Epic und GOG läuft mit Controller. |
| **März 2027** | **M3 Steam und 32 Bit.** Windows-Steam im ARM64-Prefix: anmelden, laden, starten. Left 4 Dead 2 und Mafia II. Startzeit des Steam-Clients messen. Spätestens jetzt Entscheidung 2 (eigenes Konto). | Ein 64-Bit- und ein 32-Bit-Steam-Spiel starten aus Nightforge; entschieden ist: Windows-Steam unter FEX oder Steam für Mac als Brücke. |
| **April 2027** | **M4 Direct3D 12 und die übrigen Launcher.** Wukong, Control und die Caretaker-Demo über vkd3d-proton. Overwatch und Battle.net, die heute an `libd3dshared` hängen. | Für jedes Spiel im Testkorb steht fest: läuft, läuft schlechter, oder läuft nur bis macOS 27. |
| **Mai 2027** | **M5 Entscheidung.** Schwelle aus Abschnitt 5 prüfen (80 % der Bildrate, keine neuen Stopps). Die ARM64-Engine als Wahl im Testbuild für macOS 27. Texte für Spieler. | Ein Testbuild mit beiden Engines ist auf dem Mac, die Liste der Spiele ohne Weg ist geschrieben. |
| **Juni 2027** | **M6 macOS-28-Beta.** Eigenes Testvolumen, `tests/arm64/macos28-probe.sh`, der Testkorb auf der Beta. `RosettaSupport` wählt ab macOS 28 die ARM64-Engine, statt nur zu warnen. | Ein Windows-Spiel startet aus Nightforge auf der Beta ohne Rosetta. |
| **Herbst 2027** | Release zu macOS 28: x86_64-Engine bis macOS 27, ARM64-Engine ab 28. | |

Jeder Meilenstein ist eine eigene Session auf einem eigenen Zweig. Vor M1 braucht es nichts außer den Entscheidungen 1
bis 3.

### 9.5 Was Nightforge umbauen muss

| Teil | Heute | Mit der ARM64-Engine |
|---|---|---|
| Baustein | `winecx`, x86_64 | Zweiter Baustein mit `arch: arm64` und Kennung auf `-arm64` (Vorarbeit aus Abschnitt 6). Auf macOS 28 wählt Nightforge ihn, bis macOS 27 bleibt `winecx`. |
| Ordner | `WineFolders`: `x86_64-unix`, `x86_64-windows`, `i386-windows` (21 Stellen in `Engine.swift`) | Je Engine: `aarch64-unix`, `aarch64-windows`, `i386-windows`. `WineFolders` wird von festen Werten zu einer Eigenschaft der Engine. |
| Loader | Nightforge baut „Nightforge Game.app“ um Wines Loader (Game Mode, Name im Dock) | Der Loader ist das signierte `wine.app` und darf nicht verändert werden. Mit mach9s Loader heißt der Prozess „Mach9“, mit eigenem Konto „Nightforge“. |
| Direct3D 10/11 | DXMT als eigene Bausteine `dxmt` und `graphics`, als „native“ DLLs im Prefix | DXMT steckt in der Engine. `graphics` und `installDXMTNatives` entfallen für sie. |
| Direct3D 12 | D3DMetal (`D3DMetalSupply.swift`, Profilfelder, `needsRosettaLibrary`; **[23.11.]** dazu `d3dmetal4` und die Wahl „D3DMetal 4“ je Spiel) | Kein D3DMetal, auch nicht in Version 4: vkd3d-proton der Engine (3.1, ohne Transform Feedback auf KosmicKrisp). Profile, die D3DMetal verlangen, brauchen einen zweiten Weg oder den Vermerk „nur bis macOS 27“. |
| Direct3D 9 | DXVK auf KosmicKrisp oder MoltenVK | mtld3d oder WineD3D der Engine. Der eigene KosmicKrisp-Bau entfällt, die Engine bringt einen mit. |
| Regeln je Spiel | DLL-Tausch und Ladereihenfolgen im Prefix (`layerOverrides`) | mach9: Regeln in `WINE_COMPATDB`, je Prozess. Ein kleiner Übersetzer von Nightforges Profilen dorthin. |
| Prefix | einer, gemeinsam für alle Spiele | Zunächst ein zweiter (`Prefix-arm64`), damit der Rückweg bleibt. Spielstände und Steam-Anmeldung übernehmen ist ein eigener Schritt. |
| `winebus.so` (Baustein `gamepad`) | für winecx gebaut, DualSense mit Xbox-Kennung | Für die neue Wine-Fassung als arm64 neu bauen, oder prüfen, ob die Engine es schon richtig macht. Laden geht, siehe `disable-library-validation`. |
| `ntdll.so` (Baustein `enginefix`) | Patch an winecx | Entfällt wohl. Prüfen, ob der Fehler dort noch besteht. |
| Helfer am Mac | `hide-steam-dock` und `nightforge-sandbox` x86_64, Vulkan-Layer universal | Die beiden werden universal (Abschnitt 6, Punkt 4). `hide-steam-dock` kommt heute über `DYLD_INSERT_LIBRARIES` in Wines Prozesse; im signierten Loader wirkt das nicht. Steams Fenster aus dem Dock zu halten braucht dort einen anderen Weg. |
| Windows-Helfer | `steamwebhelper`-Wrapper, `unity-play.exe`, Controller-Antwort: x86_64-PE | Bleiben, laufen durch FEX. Testen. |
| Steam-Client | Windows-Steam im Prefix | In M3 entscheiden: Windows-Steam unter FEX (Chromium durch FEX, Startzeit messen) oder Steam für Mac als Brücke. |
| Rosetta | Einrichtung installiert Rosetta; `RosettaSupport` warnt jenseits von macOS 27 | Auf macOS 28 kein Rosetta verlangen und die ARM64-Engine wählen. |
| Berichte | `runsOn` sagt, wie Wine lief | Um „arm64 mit FEX“ ergänzen, damit Vergleichswerte getrennt bleiben. |
| Anti-Cheat | Hinweis vor dem Download, keine Umgehung, GeForce Now als Hauptknopf | Bleibt unverändert. Keine Quelle sagt etwas zu Anti-Cheat unter FEX; die Liste gilt für beide Engines. |
| CI | Wächter gegen neue x86_64-Teile | Bleibt. Dazu ein Lauf, der den arm64-Baustein prüft: Signatur des Loaders unverändert, Profil nicht abgelaufen. |

### 9.6 Risiken

1. **Ein Mann, ein Zertifikat.** mach9s erster Release ist zwei Wochen alt, das Projekt hat 38 Sterne. Hört es auf oder verliert der Loader
   seine Notarisierung, steht eine eingebettete Engine still. Dagegen hilft nur der eigene Loader (Entscheidung 2);
   die Quellen dafür liegen offen.
2. **Apple ändert die Regeln.** Die Berechtigung ist nicht dokumentiert. Sie kann strenger werden oder für kostenlose
   Konten aufgehen.
3. **Leistung unbekannt.** Bis zum FEX-Lauf gibt es keine Zahl, bis M1 keine aus einem Spiel. Kalter Code ist unter
   FEX langsam (Abschnitt 4.5); das trifft den Start von Steam.
4. **Direct3D 12.** vkd3d-proton auf KosmicKrisp ist jung (**[23.11.]** 3.1, ohne Transform Feedback). Wukong läuft heute mit D3DMetal bei 63 Bildern pro Sekunde;
   ob es dort startet, weiß niemand. Overwatch braucht heute `libd3dshared`.
5. **Zwei Engines bis Herbst 2027.** Jedes Profil und jeder Fix muss auf beiden gelten oder sagen, für welche er ist.
6. **macOS-Untergrenze.** Upstream-Wine verlangt macOS 27, mach9 26.4. Wer älter fährt, bleibt bei der x86_64-Engine.
7. **Der Termin.** Bis zur Beta sind es sieben Monate, daneben laufen 0.3.4 und Folgende. **[überholt 23.11.]** 0.3.4 ist
   erschienen. Vor Rosetta stehen in der Roadmap 0.4 die Engine-Punkte 1–4.

Weggefallen: die Sorge aus 4.1, Developer ID reiche nicht für alle Macs, und die Lizenz von D3DMetal, soweit es die
ARM64-Engine betrifft.

### 9.7 Entscheidungen für den Nutzer

1. **Den FEX-Lauf starten?** Zwei Befehle aus 9.3, fünf Minuten, am besten bei ruhigem Mac. Erst danach gibt es Zahlen.
2. **Fremder Loader oder eigenes Konto?**
   - **A: mach9s signierten Loader einbetten.** Kostet nichts, geht sofort. Nightforge hängt dann an einem fremden
     Zertifikat, und die Spielprozesse heißen „Mach9“.
   - **B: Apple Developer Program**, 99 US-Dollar im Jahr [17] (Apples Preis in Euro habe ich nicht nachgesehen).
     Eigener Loader aus offenen Quellen, eigener Name. Notarisierung löst nebenbei Gatekeeper für Nightforge selbst.
     Dafür ändert sich die Signatur der App, macOS fragt die Rechte einmal neu ab, und der Bau braucht Xcode
     (GitHubs Runner haben es).
   - Empfehlung: M1 mit A, weil es nichts kostet und nichts festlegt. B bis März entscheiden, mit den Zahlen aus M1.
3. **Dürfen LGPL-Teile aus fremdem Bau in einen Baustein?** Wine, DXMT, vkd3d-proton und GStreamer, gebaut von mach9.
   Dieselbe Art Frage wie heute bei winecx und DXMT. Nightforge müsste Lizenztexte und den Weg zu den Quellen
   mitliefern; im Paket selbst fehlen die Texte. Bis zum Ja wird nichts eingebaut.
4. **Kontakt zu mach9s Autor?** Das Projekt sucht Launcher, die es einbetten. Eine Nachricht klärt, ob der Name des
   Loaders wählbar wird und wie lange das Profil trägt. Das ist ein Schritt nach außen, also Sache des Nutzers.
5. **Was fällt bei Direct3D 12 weg?** Annehmen, dass einzelne Spiele ab macOS 28 nicht mehr laufen, und sie klar
   benennen? Oder Direct3D 12 zur Bedingung für den Umstieg machen? Empfehlung: benennen, nicht warten.
6. **Ab welchem macOS bekommt man die ARM64-Engine?** Empfehlung: bis macOS 27 nur als Wahl, ab macOS 28 von selbst.
7. **Testvolumen für die Beta im Juni 2027** (aus Abschnitt 7, Punkt 6): weiter offen.
8. **Was sagen wir den Spielern?** Empfehlung wie am 8.11.: nichts versprechen, ab M5 sagen, was geht.

Nächster Schritt: Entscheidung 1.

## Quellen

Gelesen am 8.11.2026, sofern nicht anders vermerkt.

1. Apple Developer News, „Upcoming changes to Rosetta support for Intel-based macOS apps“, 1.9.2026:
   https://developer.apple.com/news/?id=w5ngl9k2
2. Apple, „About the Rosetta translation environment“:
   https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
3. Apple Support 102527, 21.9.2026: https://support.apple.com/en-us/102527
4. macOS 27 Release Notes (am 8.11. nur als Auszug gelesen, am 21.11. ganz):
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

Gelesen am 21.11.2026:

13. Apples SDK auf diesem Mac (`MacOSX27.2.sdk`): `usr/include/os/arch/arm64.h`, `usr/include/spawn.h`.
14. Apple Developer Forums, Thread 830692 (Juni 2026, Antwort eines Apple-Ingenieurs):
    https://developer.apple.com/forums/thread/830692
15. Apple Developer Forums, Thread 845976 (September und Oktober 2026, Antworten von Apples Entwickler-Support) und
    Thread 852591 (Oktober 2026): https://developer.apple.com/forums/thread/845976,
    https://developer.apple.com/forums/thread/852591
16. Wine, Merge-Request 12716 „Add support for ARM64 on macOS“ (Brendan Shanks, 18.11.2026), Beschreibung und Commits:
    https://gitlab.winehq.org/wine/wine/-/merge_requests/12716
17. Wine-Wiki, „ARM64 Provisioning Profiles“:
    https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-Building/ARM64-Provisioning-Profiles
18. CodeWeavers, Quellseite und Blog-Verzeichnis: https://www.codeweavers.com/crossover/source,
    https://www.codeweavers.com/blog. Die Artikel vom 11.6. („What's in and what's out for CrossOver 27“) und vom 31.7.
    blieben gesperrt; ein Umweg über ein Webarchiv wurde nicht genommen.
19. mach9 (Lizenz der eigenen Teile: zlib): README, `docs/internals.md`, `docs/maintenance.md`, `docs/building.md`,
    `bin/bundle-wine.sh`, Release 0.4.0 vom 17.11.2026: https://github.com/athei/mach9
20. FEX (MIT), Releases und Issues 5222 und 6141: https://github.com/FEX-Emu/FEX
21. DXMT (LGPL 2.1 oder neuer): `LICENSE`, `docs/DEVELOPMENT.md`, `build-arm64ec.txt`, Commits vom November 2026:
    https://github.com/3Shain/dxmt
22. MetalSharp-Wine (eigene Teile AGPL 3.0), README und Release 8.0 vom 18.11.2026:
    https://github.com/metalsharp/MetalSharp-Wine
23. mach9s Zweige: https://github.com/athei/wine (Wine mit CrossOvers Patches, LGPL), https://github.com/athei/FEX (MIT),
    https://github.com/athei/dxmt, https://github.com/athei/vkd3d-proton (LGPL 2.1), https://github.com/athei/mesa,
    https://github.com/athei/mtld3d (zlib).
24. Apple, Game Porting Toolkit (nur über die Suche gelesen): https://developer.apple.com/games/game-porting-toolkit/

Geladen am 21.11.2026 und nicht Teil des Repositorys: `wine-v0.4.0-macos-arm64.tar.xz` aus [19] nach `build/arm64`
(Lizenzen siehe 9.2). Geprüft, nicht gestartet, nichts daraus eingebaut.
