# Entwurf: Ladebildschirm wie eine Konsole (0.3.5, Teilschritt zu 0.4)

Stand 22.11.2026, gelesen auf `claude/staging-035` (a60728a). Ein Entwurf, nichts ist gebaut. Bilder dazu:
Canvas `docs/entwuerfe/ladescreen-konsole/` (Vorher/Nachher, drei Animationen, Vorhang beim Beenden, Pad-Karte).

**Thomas' Entscheidung (22.11., 18:34 und 18:42):**
1. Im Spielmodus ist das Dock nie zu sehen.
2. Keine Technik- oder Fehlertexte in normalen Phasen.
3. Die Ladeanzeige ist **eine schöne Animation, kein Fortschrittsbalken** mit Technikschritten: „Bei einer Konsole will
   niemand wissen, was technisch passiert.“ Immer in Bewegung, auch beim Vorhang beim Beenden.
4. Alles geht mit dem Pad, auch Steams Fragen. Keine Zielzahlen: Wartezeiten so weit verkürzen, wie es geht; die
   Animation muss bis 2 min tragen, ohne zu wirken, als hinge sie.
5. Klänge kommen später (0.4.x), das Overlay in 0.4.0. Beides ist nicht Teil dieses Entwurfs.

Damit ändert sich die Regel vom 15.11. („eine Zeile, was gerade passiert“) zu: **keine Zeile, solange nichts zu tun ist.**
Was passiert, steht im Protokoll (`wine.log`), wie heute schon mit `kind` und den Uhrzeiten.

## 1. Was heute auf dem Schirm steht

Quellen: `LaunchPhase.curtainTitle`/`curtainSentence`, `LibraryModel.curtainStatus`/`curtainDetail` (~2157–2277),
`CurtainEscape.tip` (83), `GameBackdrop.BackdropView` (545–640), `BrandMark` (770–833).

- **Bewegung:** nur ein Lichtpunkt, der alle 2,6 s die Naht des N entlangläuft (`BrandMark`, Deckkraft der Naht 0,8).
  Er ist klein und läuft auf dunkler Naht, auf einem Fernseher oder aus 3 m kaum zu sehen. Auf der Seite hinter dem
  Spiel (`stage == .behind`, „Nightforge wartet hier, bis du fertig bist.“) steht **gar nichts** still: `moving` ist dort
  aus. Das war die Seite, die am 22.11. 1–2 min nach dem Wukong-Benchmark stand.
- **Text:** eine Statuszeile (bis zu 20 verschiedene, von „Steam wird gestartet …“ bis „Shader werden beim ersten Start
  vorbereitet …“), ab 3 s ein Satz darunter, ab 30 s „Hängt es? Zurück zu Nightforge“.
- **Balken:** nur bei Updates (`UpdateBar`, 420 × 4 pt, Nahtblau).
- **Dock:** Nightforge blendet es nur aus, solange Nightforge vorne ist (`FullScreen.swift:127`, Präsentationsoptionen
  gelten nur für die aktive App). Unter dem Vorhang ist es verdeckt (der Vorhang liegt über der Dock-Ebene). Zu sehen ist
  es, wenn ein Spiel im Fenster läuft und die Seite dahinter liegt (Valheim 21.11., „Menüleiste und Dock sind zu sehen“,
  `docs/TODO.md:408`), und auf der stehenden Seite nach Spielende, solange Steam oder ein Hilfsprozess vorne ist.

## 2. Vorher/Nachher je Phase

„Nachher“ gilt für alle drei Animations-Varianten. Unter der Animation stehen immer NIGHTFORGE und der Spielname,
sonst nichts, bis der Spieler etwas tun muss. Ins Protokoll gehen Zeilen wie heute, keine neuen nötig.

| Phase | Vorher (Zeile · Satz) | Nachher auf dem Schirm | Protokoll |
|---|---|---|---|
| Start, Steam läuft | „Wird gestartet …“ | Animation, Spielname | wie heute |
| Steam startet | „Steam wird gestartet …“ | Animation | `phase startingSteam` |
| Steam meldet sich an | „Anmeldung bei Steam …“ · „Steam meldet sich neu an, damit deine Cloud-Spielstände mitkommen.“ (auch ohne Wechsel) | Animation | `signingIn` / neu `signingInAgain` nur bei `sessionReplaced` (Vorlage) |
| Steam-Neustart für das Spiel (F5) | „Steam wird neu gestartet …“ | Animation | neu `restartingSteamForGame` (Vorlage) |
| Steam hing wirklich | „Steam wird neu gestartet …“ · „Steam ist beim Starten hängen geblieben – ein Neustart behebt das.“ | Animation | `restartingSteam`, Ursache |
| Steam Cloud, erster Abgleich | „Anmeldung bei Steam …“ | Animation | neu `steamCloudSync` (Vorlage) |
| Spielstand hoch (Wechsel) | „Spielstand wird gesichert …“ | Animation | `savingToCloud` |
| Einrichten (erster Start) | „Wird eingerichtet …“ · „Nur beim ersten Mal.“ | Animation; nach 60 s ein leiser Satz „Beim ersten Mal dauert es etwas länger.“ (Frage 3) | `settingUp…` |
| Shader beim ersten Start | „Shader werden … vorbereitet …“ · „Nur beim ersten Mal.“ | wie Einrichten | `shaders` |
| Noch ein Versuch / vorige Engine | „Noch ein Versuch …“ | Animation | `retrying`, `rollingBack` |
| Warte auf das Bild | „Wird gestartet …“ | Animation | `look` |
| Update (Steam, Epic, GOG) | „Wird aktualisiert … 42 %“ · Geschwindigkeit · Balken | **bleibt**: Balken mit Prozent, eine Zeile „Update“ – das ist echter Fortschritt, wie eine Konsole ihn zeigt | wie heute |
| Nach 30 s ohne Spielprozess | „Hängt es? Zurück zu Nightforge“ (Ⓑ) | nichts; erst ab 90 s leise unten „Ⓑ Zurück zu Nightforge“ | `storeQuiet` |
| Steam fragt etwas | Steams Fenster auf dem Vorhang, Leiste „Antworten mit Maus oder Trackpad“ | Steams Fenster mit Naht, Leiste mit Pad-Zeiger (§5) | wie heute |
| Anmeldung nötig | „Melde dich im Steam-Fenster an“ · „Sein Fenster ist offen.“ | bleibt (Spieler muss handeln), Pad-Tastatur (§5) | wie heute |
| Spiel meldet Fehler / fragt | Zeile + Ⓐ/Ⓑ | bleibt | wie heute |
| Vollbild verdeckt das Spiel | Zeile + Satz + Ⓐ Neu starten | bleibt | wie heute |
| Spiel läuft, Seite dahinter | „Nightforge wartet hier, bis du fertig bist.“, **keine Bewegung** | nur sichtbar, wenn das Bild weg ist; dann wie „Zurück“ (§4) | `Stage` |
| Spielende | „Zurück zu Nightforge …“ | Animation läuft weiter, kein Text | wie heute |

**Fehltexte raus:** „Steam ist beim Starten hängen geblieben …“ (`LaunchPhase.swift:79`) und „Hängt es? …“
(`CurtainEscape.swift:83`) erscheinen nie mehr auf dem Vorhang; der erste bleibt als `hint` am Spielen-Knopf nur für den
echten Hänger, der zweite wird „Zurück zu Nightforge“. Aus der Vorlage (`.claude/worktrees/f5-steam-ohne-neustart`)
werden die drei neuen Phasen übernommen, weil sie das Protokoll und den Knopf richtig machen; ihre neuen Texte
(„Steam wird für das Spiel vorbereitet …“ u. a.) erscheinen nur am Spielen-Knopf, nicht auf dem Vorhang.

## 3. Drei Animationen

Alle drei: gecachte Bilder, nur billige Transformationen (Drehung, Verschiebung, Deckkraft), nichts, was den ganzen
Schirm neu zeichnet ([[feedback-ui-power]]); bei „Bewegung reduzieren“ nur ein langsames Atmen der Naht. Sie laufen
gleichmäßig weiter, egal ob der Start 5 s oder 2 min dauert – kein Ende, das sie ansteuern, also nichts, was „fast fertig“
verspricht und dann steht. Was eine lange Wartezeit trägt: eine Bewegung, die nie anhält und sich nie gleich anfühlt.

- **A · Lichtnaht (kleinste Änderung).** Die vorhandene Naht wird zum Taktgeber: Das Licht läuft heller und breiter
  (Kern weiß, Hof 3× so groß), alle 2,2 s, ohne Pause, dazu atmet die ganze Naht zwischen 60 und 100 %. Unter dem N ein
  kurzer Lichtstrich (80 pt), der auf einer 300-pt-Linie hin- und hergleitet. Aufwand klein, bleibt ganz im heutigen Bild.
- **B · Orbit (Empfehlung).** Um das N kreist langsam ein Lichtbogen in Nahtblau (ein Viertelkreis mit weichem Ende,
  eine Umdrehung in 3,2 s), dahinter ein kaum sichtbarer Ring. Das bekannte Konsolenmuster für „es lädt“, auf einen Blick
  aus 3 m lesbar, und die Naht-Animation läuft weiter. Aufwand klein: ein Bild, `rotationEffect`.
- **C · Nachtglut.** Hinter dem N ziehen drei unscharfe blaue Lichtwolken sehr langsam (20–40 s je Bahn) über die Nacht,
  die Naht atmet. Am ruhigsten und am stimmungsvollsten, aber am wenigsten eindeutig als „lädt“; braucht drei große
  Bilder in Bewegung, kostet am meisten Fensterserver-Arbeit (zu messen, bevor es gebaut wird).

Mischformen gehen (B + der Strich aus A).

## 4. Vorhang beim Beenden

**Heute:** Endet das Bild, aber ein Prozess des Spiels läuft weiter (Wukong-Benchmark: ein Hilfsprozess 1–2 min), liegt
die Seite hinter dem Spiel sichtbar da: stehendes N, „Nightforge wartet hier, bis du fertig bist.“, Dock und Menüleiste,
wenn ein anderer Prozess vorne ist. Erst mit dem letzten Prozess kommt „Zurück zu Nightforge …“.

**Nachher:**
1. Ist das Bild des Spiels 3 s weg und kein Fenster des Spiels mehr da, gilt das als Ende fürs Auge: Der Vorhang kommt
   mit derselben Animation wie beim Start, ohne Text.
2. Läuft danach nur noch ein Prozess ohne Fenster, kehrt Nightforge nach 10 s zur Spielseite zurück und folgt dem Rest im
   Hintergrund (wie heute `watchForGameEnd`, nur ohne Vorhang). Die Spielseite zeigt dann am Knopf „Wird beendet …“, bis er
   weg ist. Ein erneuter Druck auf Spielen in der Zeit wartet, wie heute.
3. Kommt in dieser Zeit doch ein Fenster zurück (Spiel lädt nur um), geht der Vorhang wieder weg wie heute.
4. Die Seite hinter einem laufenden Spiel ist nie ohne Bewegung zu sehen: Wird sie sichtbar, ist sie Vorhang.

Offen ist, ob Schritt 2 Spiele trifft, die zwischen zwei Teilen kein Fenster haben (Launcher → Spiel); dafür hält Schritt 3,
und die Frist ist im Protokoll zu prüfen (Frage 4).

## 5. Pad: wo Ladebildschirm und Vorhang Eingaben brauchen

| Wo | Heute | Nachher |
|---|---|---|
| Vorhang, Start läuft | Ⓑ wirkt erst nach 30 s („Hängt es?“) | Ⓑ wirkt ab 30 s still, der Hinweis erscheint erst ab 90 s; ab 90 s fragt Nightforge wie heute („%@ antwortet gerade nicht“, Ⓐ Weiter warten, Ⓑ Zurück) |
| Update | Ⓑ „Anhalten, das Update läuft beim nächsten Mal weiter“ | bleibt |
| Steams Frage (EULA, Startoption, Cloud-Konflikt, andere Sitzung) | nur Maus/Trackpad, außer bei der Lizenz | **überall der Pad-Zeiger der Lizenz** (Touchpad oder rechter Stick, R2 klickt), Leiste unten wie bei der Lizenz; Ⓑ zurück. Lücke heute: `SteamQuestionFrame.answers` fällt ohne Lizenz auf `.mouse` |
| Steam-Anmeldung | Fenster offen, Tastatur nötig | Pad-Zeiger + Pad-Tastatur (`PadKeyboard`), oder „Mit dem Handy anmelden“ (`PhoneSignIn`) als erster Vorschlag |
| Frage des Spiels | Ⓐ/Ⓑ, wo `PadAnswerRun` drücken kann | bleibt; wo nicht: Pad-Zeiger |
| macOS fragt (Erlaubnis) | nur Maus/Trackpad | **bleibt eine Lücke**: macOS-Dialoge nimmt kein Programm an. Abhilfe nur vorher: alle Erlaubnisse bei der Einrichtung einholen, nie mitten im Start |
| Vollbild verdeckt das Spiel | Ⓐ Neu starten | bleibt |
| Vorhang beim Beenden | Ⓑ, wenn niemand den Vorhang hält | bleibt; mit §4 steht er höchstens 10 s |

## 6. Dock im Spielmodus

Präsentationsoptionen wirken nur für die App vorne. Heute:
- **Nightforge vorne:** Dock aus, wenn Nightforge im Vollbild ist (`FullScreen`).
- **Vorhang oben:** verdeckt (Ebene über dem Dock).
- **Spiel im macOS- oder Wine-Vollbild vorne:** aus (macOS bzw. Wines Mac-Treiber blendet es aus; für Wine aus dem
  Verhalten geschlossen, im Quelltext nicht geprüft).
- **Spiel im Fenster vorne, oder Steam/Helper vorne über der Seite:** **zu sehen.** Daran ändert Nightforge von außen nichts.

**Vorschlag, in zwei Stufen:**
1. **Ohne Systemeinstellung:** Im Konsolenmodus läuft jedes Spiel im Vollbild (Mac-Unity wie F1, andere Mac-Spiele und
   Windows-Spiele über Profil und Wines Vollbild); die Seite hinter dem Spiel wird nie ohne Vorhang sichtbar (§4); Steam
   und Helper werden unter dem Vorhang versteckt wie heute. Damit bleibt als Lücke nur ein Spiel, das sich nicht ins
   Vollbild bringen lässt.
2. **Für diese Lücke**, nur mit Thomas' ausdrücklichem OK (es ist eine Systemeinstellung): Nightforge schaltet im
   Konsolenmodus „Dock automatisch ein- und ausblenden“ ein und stellt den alten Wert beim Verlassen wieder her, auch
   nach einem Absturz beim nächsten Start. Ganz unsichtbar ist es auch dann nicht: Am unteren Rand mit dem Zeiger kommt es.
   Private Dock-Schnittstellen bleiben draußen.

**Ladebildschirm im Konsolenmodus:** Vollbild über dem Dock, Animation, NIGHTFORGE und Spielname, keine Zeile,
Pad-Hinweise nur, wenn etwas zu tun ist. Ohne Konsolenmodus (Fenster am Schreibtisch) sieht der Vorhang gleich aus; das
Dock darf dort zu sehen sein. Die Konsolenmodus-Anfrage selbst (ersetzt „Vollbild für den Controller?“,
`LibraryView.swift:239`) ist ein eigener Punkt.

## 7. Wartezeiten kürzen

Nicht Teil der Oberfläche, aber was die Animation tragen muss, hängt daran: F5 (kein Steam-Neustart je Spielstart,
26–40 s statt 5–8 s), F4 (neues MacBook rund 20 s über diesem Mac), `stopSteam` wartet auf alle Prozesse, `librarySession`
nach Inhalt (Worker A). Wukong bis 2 min zum ersten Bild ist das Spiel selbst (Shader); da hilft nur die Animation.

## Offene Fragen an Thomas

1. **Welche Animation:** A Lichtnaht, B Orbit (Empfehlung) oder C Nachtglut?
2. **Update-Balken:** Bleibt beim Update ein Balken mit Prozent (echter Fortschritt wie bei einer Konsole), oder auch dort
   nur die Animation?
3. **Erster Start, sehr lang (Einrichten, Shader):** ab 60 s ein leiser Satz „Beim ersten Mal dauert es etwas länger.“,
   oder auch dann nichts?
4. **Beenden:** Darf Nightforge nach 10 s ohne Fenster zurückkehren, während ein Rest des Spiels im Hintergrund noch endet?
5. **Dock, Stufe 2:** Darf Nightforge im Konsolenmodus die Systemeinstellung „Dock automatisch ausblenden“ setzen und
   zurückstellen?
6. **Zurück-Hinweis:** Ⓑ wirkt ab 30 s, gezeigt erst ab 90 s – passt das, oder soll er nie stehen, nur die Frage ab 90 s?
