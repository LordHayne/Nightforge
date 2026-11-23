# 0.4 „Wie eine Konsole“: was offen ist und was du wählst

Stand 23.11.2026, nach den Merges in `claude/staging-035` (1b563a4d). Zum Durchgehen in fünf Minuten: je Punkt, wo er steht,
was du wählst oder live prüfst und was danach gebaut wird.

## Deine Entscheidungen vom 22.11.

1. Controller-only ist hart: alles muss mit dem Pad gehen, auch Steams Abfragen.
2. Keine Zielzeiten: so viel verbessern, wie geht.
3. Konsolenmodus: eine Anfrage, sobald ein Controller erkannt wird, statt der heutigen Vollbild-Anfrage.
4. Ladeanzeige: eine ruhige Animation statt eines Fortschrittsbalkens mit Technikschritten.
5. Overlay in 0.4.0, Klänge später in 0.4.x.

## Übersicht

| Punkt | Stand | Entwurf | Du wählst / prüfst | Danach gebaut |
|---|---|---|---|---|
| **Konsolenmodus** | gebaut (Variante A, deine Wahl 22.11.) | `ENTWURF-KONSOLENMODUS.md` | live heute Abend: Anfrage kommt einmal, Dock bleibt weg | Feinschliff aus der Abnahme |
| **Lichtnaht** (Ladeanzeige) | gebaut (Variante A, deine Wahl) | `ENTWURF-LADESCREEN-KONSOLE.md` | live heute Abend: die fünf Vorschau-Varianten | Feinschliff aus der Abnahme |
| **Overlay** | Stufe 1 gebaut (Seitenleiste A, deine Wahl 8.11.), stille Eingabe gebaut | `ENTWURF-OVERLAY.md`, Board `entwuerfe/Overlay.dc.html` | welche Funktionen in 0.4.0 (Lautstärke, Downloads, Bildschirmfoto …); B (Streifen) für den Konsolenmodus ja/nein | die gewählten Funktionen der Stufe 2 |
| **Steams Fragen mit dem Pad** | Befund + Probe vorbereitet | `ENTWURF-STEAM-PAD.md`, Seite `entwurf-steam-pad-04/index.html`, Probe `probes/steam-pad-keys/` | (1) Erlaubnis „Bedienungshilfen“ in die Konsolenmodus-Anfrage? (3) Leistentext ohne Erlaubnis (Vorher/Nachher) (4) Startoption in Nightforge fragen? · Probe B an einer Frage des **Windows**-Steam | je nach Probe: Weg B (Ⓑ = Esc, Steuerkreuz = Tab), sonst Zeiger (A) und Weg E; C (Steam für Mac) erst nach eigener Probe |
| **Pad-only, Nightforges Bildschirme** | geprüft; fehlender Fokus gebaut; Wächter-Test | `ENTWURF-PAD-ONLY.md` | (1) Pad-Tastatur für jedes Textfeld (2) Ordnerwahl ohne Dateifenster (3) Berichte per QR aufs Handy (4) Meldungen mit Knopf erreichbar? (erst live prüfen) (5) Epic-Anmeldung | die gewählten Punkte, je mit Board zuerst |
| **Spielwechsel ohne Steam-Neustart** | Befund + Probe (Rosetta folgt der Umgebung beim Start) | `ENTWURF-SPIELWECHSEL.md` | Weg 1 (Abfangen in steam.exe, berührt Anti-Cheat-Prozesse) · Weg 2 (Steam vorab passend, nur im Konsolenmodus) · Weg 3 (so lassen; Empfehlung des Koordinators für 0.3.5) | Weg 2 als Regel, falls gewählt |
| **Hängendes Spiel erkennen** | Stufe 1 gebaut: nur eine Protokollzeile hinter dem Testschalter | `ENTWURF-HAENGER.md` | messen: Schalter an, spielen, „Hang watch:“ suchen (Fehlalarme?) · danach das Angebot: A Hinweis, B Overlay öffnet sich, C nur im Overlay (Vorschlag C, dann A) | Stufe 2: Bilder, wo vorhanden; das gewählte Angebot |
| **AVX-Meldung unter Wine** | Befund + Probe; Protokollzeile, wer die Sitzung beginnt (gebaut) | `ENTWURF-AVX.md` | Weg A (AVX als Sitzungseinstellung) oder D (nichts; Empfehlung für 0.3.5, A erst bei einem belegten Spiel) | A, falls gewählt |
| **Startzeit** | gebaut: kein Warten auf einen Cloud-Abgleich, den Steam nie macht; kürzerer Vorhang bei bewährten Spielen; Zeitmarken hinter Testschalter | `ENTWURF-STARTZEIT.md` | die Messliste heute Abend (drei Starts mit Zeitmarken) | was die Messung als Lücke zeigt |
| **Zwei Pads** (Spieler 1/2, Reihenfolge) | bei Worker 1, später | `ENTWURF-KONSOLE.md` (K4, G6) | live mit zwei Pads (Nummern, Licht, Abstecken) | Spielerreihenfolge wählen (G6) |
| **Klänge** | 0.4.x, noch nicht begonnen | `ENTWURF-KONSOLE.md` §5 (G3) | einen von zwei, drei eigenen Klangsätzen | Klänge und Haptik nach der Wahl |

## Nicht wählbar, nur ansagen

macOS' eigene Fragen (Rosetta-Passwort, „Bedienungshilfen“, Anmeldeobjekt, Bluetooth-Kopplung, Mitteilungen) gehen nicht mit dem Pad.
Vorschlag aus mehreren Entwürfen: alle in die Ersteinrichtung bzw. die Konsolenmodus-Anfrage legen, nie mitten im Spielen.
