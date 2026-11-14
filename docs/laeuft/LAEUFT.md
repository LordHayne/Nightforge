# Läuft unter Nightforge

Erzeugt von `scripts/laeuft-liste.py` aus Nightforges eigenen Aufzeichnungen (Start-Evidenz und Spieletest) – nicht von Hand ändern. Was die Stufen bedeuten, unter welchen Bedingungen gemessen wird und was die Zahlen nicht aussagen: [LAEUFT-LISTE.md](../LAEUFT-LISTE.md). Maschinenlesbar: [laeuft.json](laeuft.json).

Stand der Daten: 14.11.2026 (Tage in UTC). Quellen: 71 Einträge der Start-Evidenz, 29 Spieletest-Läufe.

## Apple M5 · macOS 27.0

Aktueller Build: Nightforge 0.3.2 (gebaut 14.11.2026 17:41 UTC) · winecx@4.7.3 · d3dmetal@apple-3.0 · dxvk-macos@1.10.3-20230507 · enginefix@4.7.3-4 · gamepad@4.7.3-15 · graphics@11.18-dxmt0.80-17 · moltenvk@1.4.2, gesehen seit dem 14.11.2026. Messwerte stehen mit dem Build, auf dem sie gemessen sind, und bleiben, wenn ein neuerer läuft; die Spalte „Aktueller Build“ sagt, was der jüngste von dem Spiel gesehen hat.

### Läuft (15)

Der Weg ist bestätigt: Das Spiel hat gemessene Frames gezeichnet oder lief 180 s mit Bild.

| Spiel | Laden | Fassung | Weg | Beleg | Spieletest | Bild nach | Frame-Limit | FPS | Langsamster Frame | Größe | Messung | Aktueller Build | Hinweis |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Alan Wake | Epic Games | Windows | wined3d | bestätigt 11.11.2026, 2. Start, 2 Wege · winecx@4.7.3 | Bild in 1 von 3 | 11 s | nicht gemessen | nicht gemessen (WineD3D meldet keine) | nicht gemessen | nicht gemessen | 11.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 200 s | noch nichts | endete im Spielfenster von selbst |
| Batman: Arkham Asylum GOTY Edition | Steam | Windows | wined3d | bestätigt 14.11.2026, 1. Start · winecx@4.7.3 | Bild in 1 von 1 | 141 s | 60 FPS | nicht gemessen (WineD3D meldet keine) | nicht gemessen | Fenster 1800×1125 Punkte | 14.11.2026 · Nightforge 0.3.2 (gebaut 14.11.2026 14:40 UTC) · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 190 s | noch nichts | – |
| Black Myth: Wukong Benchmark Tool | Steam | Windows | d3dmetal | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 2 von 5 | 89 s | nicht gemessen | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | – |
| Control | Epic Games | Windows | d3dmetal | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 4 von 4 | 10 s | nicht gemessen | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | – |
| Dishonored - Definitive Edition | Epic Games | Windows | wined3d | bestätigt 11.11.2026, 3. Start · winecx@4.7.3 | Bild in 3 von 3 | 18 s | nicht gemessen | nicht gemessen (WineD3D meldet keine) | nicht gemessen | nicht gemessen | 11.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 200 s | noch nichts | – |
| Hogwarts Legacy | Epic Games | Windows | d3dmetal | bestätigt 9.11.2026, 1. Start · winecx@4.7.3 | Bild in 1 von 2 | 81 s | nicht gemessen | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | – |
| It Takes Two | Steam | Windows | d3dmetal | bestätigt 10.11.2026, 6. Start, 3 Wege · winecx@4.7.3 | Bild in 3 von 5 | 80 s | nicht gemessen | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17 · 30 s | noch nichts | mit Profil |
| Just Cause 4 | Epic Games | Windows | dxmt | bestätigt 9.11.2026, 1. Start · winecx@4.7.3 | Bild in 2 von 2 | 8 s | nicht gemessen | Ø 47, tiefste Periode 12 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |
| Left 4 Dead 2 | Steam | Windows | wined3d | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 3 von 3 | 14 s | nicht gemessen | nicht gemessen (WineD3D meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | – |
| Mafia II (Classic) | GOG | Windows | wined3d | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 6 von 6 | 19 s | nicht gemessen | nicht gemessen (WineD3D meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 200 s | noch nichts | – |
| METAL GEAR SOLID V: THE PHANTOM PAIN | Steam | Windows | dxmt | bestätigt 11.11.2026, 7. Start, 2 Wege · winecx@4.7.3 | Bild in 1 von 7 | 57 s | nicht gemessen | Ø 59, tiefste Periode 57 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen | 11.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 200 s | noch nichts | endete im Spielfenster von selbst; FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |
| Overwatch® | Steam | Windows | dxmt | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 1 von 5 | 10 s | nicht gemessen | Ø 28, tiefste Periode 22 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |
| OxyRail | Steam | Windows | dxvk | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 4 von 4 | 8 s | nicht gemessen | nicht gemessen (keine im Log) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | – |
| REANIMAL | Steam | Windows | dxmt -dx11 | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 2 von 2 | 13 s | nicht gemessen | Ø 57, tiefste Periode 43 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |
| The Forest | Steam | Windows | dxvk | bestätigt vor dem 9.11.2026 (vor der Aufzeichnung) · winecx@4.7.3 | Bild in 3 von 5 | 32 s | nicht gemessen | Ø 58, tiefste Periode 50 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | kein Bild 14.11.2026 (Evidenz) | FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |

### Startet (6)

Ein Bild kam, der Weg ist aber nicht (oder nicht mehr) bestätigt. Für Mac-Fassungen zeichnet Nightforge keine Bestätigung auf: Sie stehen höchstens hier.

| Spiel | Laden | Fassung | Weg | Beleg | Spieletest | Bild nach | Frame-Limit | FPS | Langsamster Frame | Größe | Messung | Aktueller Build | Hinweis |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ABZU | Epic Games | Windows | dxmt -dx11 | Bild im Spieletest 10.11.2026 | Bild in 7 von 10 | 12 s | nicht gemessen | Ø 55, tiefste Periode 42 (Limit nicht aufgezeichnet) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | dxmt -dx11 war bestätigt, seit 10.11.2026 nicht mehr; FPS nicht für die öffentliche Liste: Limit nicht aufgezeichnet, Größe nicht aufgezeichnet, Messdauer nicht aufgezeichnet |
| Asphalt Legends | Steam | Mac | mac | Bild im Spieletest 10.11.2026 | Bild in 4 von 4 | 31 s | nicht gemessen | nicht gemessen (Mac-Fassung meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · 60 s | noch nichts | – |
| Drawful 2 | Steam | Mac | mac | Bild im Spieletest 10.11.2026 | Bild in 1 von 1 | 32 s | nicht gemessen | nicht gemessen (Mac-Fassung meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · 60 s | noch nichts | Last beim Messen hoch |
| Marvel's Guardians of the Galaxy | Epic Games | Windows | d3dmetal | Bild im Spieletest 9.11.2026 | Bild in 1 von 2 | 31 s | nicht gemessen | nicht gemessen (D3DMetal meldet keine) | nicht gemessen | nicht gemessen | 9.11.2026 · Nightforge 0.3.2 · winecx@4.7.3 · d3dmetal@apple-3.0 · graphics@11.18-dxmt0.80-17 · 60 s | noch nichts | – |
| Tomb Raider | Steam | Mac | mac | Bild im Spieletest 10.11.2026 | Bild in 1 von 3 | 32 s | nicht gemessen | nicht gemessen (Mac-Fassung meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · 60 s | noch nichts | – |
| Valheim | Steam | Mac | mac | Bild im Spieletest 10.11.2026 | Bild in 1 von 1 | 31 s | nicht gemessen | nicht gemessen (Mac-Fassung meldet keine) | nicht gemessen | nicht gemessen | 10.11.2026 · Nightforge 0.3.2 · 60 s | noch nichts | – |

### Versucht, bisher ohne Bild (1)

Gehört nicht zur Liste, steht hier der Ehrlichkeit halber: gestartet, aber kein Bild aufgezeichnet.

| Spiel | Laden | Fassung | Letzter Weg | Stand |
|---|---|---|---|---|
| Grand Theft Auto V Enhanced | Steam | Windows | d3dmetal | Spieletest 9.11.2026: wartet auf einen Klick in seinem eigenen Fenster; 2 Starts aufgezeichnet, kein Bild bestätigt |
