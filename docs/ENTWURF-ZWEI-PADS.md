# Zwei Controller, lokaler Koop (Entwurf, 23.11.2026)

Auftrag 0.4 „Controller einwandfrei“, Eintrag „Zwei Controller, lokaler Koop mit Split-Screen“ in docs/TODO.md. Grundlage:
der Code auf `claude/staging-035` (a4475e01), dazu der Befund zu den Spielernummern vom 8.11. (`claude/spielernummern-033`)
und die winebus-Patches unter `engine/patches/`. Kein Live-Test; was nur am Gerät zu sehen ist, steht in der Liste am Ende.

## Kurzfassung

- **Nightforge selbst:** Beide Pads steuern die Oberfläche, jeder mit allen Tasten. Ein Fehler ist behoben: Gehaltene
  Richtungen und das Scrollen gab es nur einmal für alle Pads, nicht je Pad. Bewegte der zweite Pad seinen Stick zurück in
  die Mitte, endete das Halten oder Scrollen des ersten. Sonst ist nichts klar falsch.
- **Windows-Spiele:** Jeder Pad kommt als eigener Xbox-360-Pad an (winebus über SDL), XInput vergibt die Plätze 1–4
  selbst. Welcher Pad Spieler 1 ist, bestimmt Wine, nicht Nightforges Nummer. Die stille Eingabe beim Overlay hält
  alle Pads an.
- **Alte Mac-Ports:** macOS bildet die Pads im Spiel als Xbox-360-Pads nach (`GCSyntheticDevice`). Ob es für zwei Pads
  zwei nachbildet, steht nicht im Code; das zeigt erst ein Spiel.

## 1. In Nightforge

| Was | Mit zwei Pads | Stelle |
|---|---|---|
| Auswahl, A, B, X, Y, L1/R1 | jeder Pad; die Handler hängen an jedem (`attach`) | `InputRouter.attach` |
| Gehaltene Richtung (Steuerkreuz, linker Stick) | **war gemeinsam, jetzt je Pad**: die zuletzt bewegte führt, Loslassen gibt an die jüngste noch gehaltene ab, auch am anderen Pad | `HeldDirections`, `InputRouter.steer` |
| Scrollen mit dem rechten Stick | **war gemeinsam, jetzt je Pad**; unter der Totzone gilt ein Stick als in Ruhe, sein Zittern übernimmt nicht | `InputRouter`, `scrolls` |
| Bildschirmtastatur | gehört dem Pad, der sie öffnete; das A der anderen tut solange nichts; geht dieser Pad, schließt sie | `keyboardPad`, `PadRules.keyboardStays` |
| PS- oder Xbox-Taste, ⧉ | Nightforge nimmt sie jedem Pad, auch einem, der später kommt (`attach` ruft `takeHomeButton` und `takeViewButton`) | `InputRouter.takeHomeButton` |
| Overlay | jeder Pad öffnet es; „Weiterspielen“ wartet, bis an **keinem** Pad mehr etwas gedrückt ist | `GameOverlay.padIdle` |
| Konsolenmodus | die Frage kommt einmal, beim ersten verbundenen Pad; ein zweiter fragt nicht noch einmal | `ConsoleMode.offers` |
| Akku | eine Kapsel je Pad, nach Spielernummer („1 · DualSense · 80 %“); live gesehen am 8.11. mit zwei DualSense | `InputRouter.refreshBattery`, `ControllerPlayers` |
| Spielernummer und Lichtleiste | 1–4; der Platz eines ausgeschalteten Pads bleibt frei; geschrieben nur bei einer Änderung und nicht unter einem Spiel | `PlayerSlots` |
| Tastensymbole | vom zuletzt benutzten Pad (DualSense ✕○□△, Xbox ABXY) | `refreshConnected`, `GCController.current` |
| Rumpeln, Touchpad als Zeiger | je Pad | `PadHaptics`, `PadPointer.attach` |
| Hinweis „Controller verbunden“, Akku schwach | je Pad, einmal, auch über einem Spiel | `ControllerNotices` |

Kleine Reste, nicht gebaut, weil selten und ohne Schaden:
- Der Druck auf die PS- oder Xbox-Taste und das Halten von ☰ werden einmal für alle Pads gemessen (`homeDown`,
  `menuHold`). Drücken zwei Spieler sie gleichzeitig, kann ein kurzer Druck des einen als Teil des langen des anderen
  zählen.
- Der Controller-Test der Ersteinrichtung zeigt einen Pad (schon in docs/TODO.md).

## 2. In Windows-Spielen

- **Weg:** winebus über SDL (SDL 2.32.8, HIDAPI). Jeder Pad ist ein eigenes Gerät und meldet sich mit den Kennungen eines
  Xbox-360-Pads (045E:028E, `winebus-winecx-xbox360-ids.patch`). `DisableHidraw`=1 (`Engine.controllerRegistry`), also
  kein zweiter Weg über rohes HID, kein Pad doppelt.
- **Plätze:** XInput vergibt 1–4 selbst (`xinput1_3`, `update_controller_list`: Geräte in SetupDi-Reihenfolge, der
  kleinste freie Platz; ein Pad behält ihn, solange sein Gerät besteht). winebus ruft nie `SDL_JoystickSetPlayerIndex` auf.
  Nightforges Nummer und Lichtleiste kommen deshalb im Spiel nicht an: Spieler 1 im Spiel kann der andere Pad sein.
- **Ab- und Anstecken:** Ein Pad, der geht, gibt seinen Platz frei; kommt er wieder, bekommt er den kleinsten freien. Ein
  spät eingeschalteter Pad wird von SDL nachgemeldet (für einen Pad live gesehen am 26.10.). Ob ein Spiel einen zweiten
  Pad mitten im Spiel annimmt, entscheidet das Spiel.
- **Stille Eingabe beim Overlay** (`PadSilence`, `winebus-winecx-pad-silence.patch`): Der Treiber meldet für **jedes**
  Gerät einen Pad in Ruhe und hält dann alle Meldungen zurück, auch die eines Pads, der während der Stille dazukommt. Am
  Ende schickt er für jedes Gerät den echten Stand. Mit zwei Pads stimmt das.
- **Spiele, die nicht XInput nehmen** (DirectInput, Raw Input): sehen beide Geräte über winebus, die Reihenfolge ist auch
  hier die von Wine.

## 3. In alten Mac-Ports

- `ControllerCompatibility` setzt `GCSyntheticDevice` nur für Spiele, die GameController nicht linken (Feral-Ports wie
  Batman: Arkham City). Dann bildet macOS 27 im Prozess des Spiels Xbox-360-Pads nach
  (AppleSyntheticGameController.plugin). Nightforge gibt nur den Schalter; wie viele Pads macOS nachbildet, liegt bei
  macOS. Laut Apples Beschreibung erscheint „jeder Controller“ als Xbox-360-Pad; belegt ist das bisher nur für einen.
- Neuere Mac-Spiele mit GameController oder neuem SDL sehen mehrere Pads von selbst; für sie setzt Nightforge nichts.

## 4. Gebaut (`claude/zwei-pads-04`)

- `HeldDirections` (PadRules.swift): Was mehrere zugleich halten, führt das zuletzt bewegte; Loslassen gibt an das
  jüngste noch gehaltene ab. Schlüssel: Pad und Quelle (Steuerkreuz oder linker Stick), fürs Scrollen der Pad.
  Für einen Pad bleibt alles wie vorher (Steuerkreuz und Stick geben einander ab).
- `InputRouter`: `steer` und das Scrollen gehen darüber; `letGo` (Pad weg, Nightforge im Hintergrund) leert beides.
- Test: `PadRulesTest.twoPads`.

## 5. Vorschläge (neue Oberfläche, zur Wahl)

1. **Controller-Test der Ersteinrichtung mit allen Pads:** je Pad eine Kapsel mit seiner Nummer, die beim Drücken
   aufleuchtet. Klein, passt zu den Kapseln unten.
2. **Spieler 1 im Windows-Spiel = Nightforges 1:** ein weiterer winebus-Patch für beide Engines, der die Geräte in der
   Reihenfolge von `PlayerSlots` meldet. Erst, wenn ein Koop-Spiel zeigt, dass es stört; viele lassen per Tastendruck
   beitreten.
3. **Im Overlay die Pads mit Nummer und Akku zeigen** (wie die Kapseln unten), damit beide Spieler sehen, wer wer ist.

## 6. Live-Liste (DualSense und Xbox-Pad)

Einmal, wenn Zeit ist; je Punkt, was zu sehen sein soll.

1. **Nightforge mit beiden:** Beide verbinden. Unten zwei Kapseln, „1 · DualSense“ und „2 · Xbox“, je mit Akku. Mit dem
   einen den Stick nach rechts halten und den anderen kurz anstoßen und loslassen: Die Auswahl läuft weiter (der Fix).
   Mit beiden durch die Bibliothek scrollen.
2. **Symbole:** Den Xbox-Pad benutzen: Hinweise zeigen A/B; den DualSense: ✕/○.
3. **Overlay:** Im Spiel mit dem zweiten Pad die PS- bzw. Xbox-Taste halten: Das Overlay kommt. „Weiterspielen“ mit dem
   ersten: Das Spiel sieht keinen Tastendruck.
4. **Windows-Koop** (ein Spiel mit lokalem Koop aus der Bibliothek, etwa Overcooked 2): Bekommt jeder seinen Pad? Welcher
   ist Spieler 1, und ist es Nightforges 1? Den zweiten im Spiel ausschalten und wieder einschalten: Kommt er zurück, auf
   seinem Platz?
5. **Mac-Port** (Batman: Arkham City oder ein anderer Feral-Port mit Koop, falls vorhanden): Sieht das Spiel zwei Pads?
6. **Ein dritter Moment:** Den zweiten Pad erst einschalten, während ein Windows-Spiel schon läuft: Kommt er an?
7. **Ausschalten in Nightforge:** Einen Pad aus- und wieder einschalten: Er behält seine Nummer, die Kapsel ihren Platz.
