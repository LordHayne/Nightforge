# Was das große Overlay technisch kann (0.4.0, unabhängig von der Variante)

Stand 23.11.2026, Zweig `claude/overlay-technik-04` (von `claude/staging-035`, a8e75b9c). Gelesen: `OverlayTiles.swift`,
`GameOverlay.swift`, `Engine.writeGameConfigs`, `Engine.prepareLaunchEnvironment`, `D3DMetalPace.swift`,
`wrapper/d3dmetal-pace*.c/.m`, `Downloads.swift`, `docs/ENTWURF-OVERLAY.md`. Eine Probe, die nur liest (Core Audio, unten).
Kein Spielstart, nichts an Nightforges Prefix.

Heute im Overlay, ausgeliefert: Uhr, Spielzeit, Akku je Controller (`OverlayTiles.swift:107`), dazu Weiterspielen, Spiel
beenden, Zu Nightforge, und die Pause per SIGSTOP bzw. die stille Eingabe (`PadSilence`).

## Die Funktionen

**Bildratengrenze ändern.**
- *DXVK* (DirectX 9–11 über Vulkan): `dxgi.maxFrameRate`/`d3d9.maxFrameRate` in `dxvk.conf` im Spielordner
  (`Engine.swift`, `writeGameConfigs`). DXVK liest die Datei beim Anlegen des Geräts: **erst beim nächsten Start**.
- *DXMT* (DirectX 10/11 über Metal): `d3d11.preferredMaxFrameRate` in `dxmt.conf`, ebenfalls beim Anlegen des Geräts gelesen:
  **nächster Start**. Live ginge es nur mit einem Patch an DXMT, der die Datei neu liest. Das wäre ein Eingriff in eine
  LGPL-Komponente (braucht dein OK) und neuer Code im Spielprozess.
- *D3DMetal* (DirectX 12): Die Bremse ist Nightforges eigene (`d3dmetal-pace.m`). Sie liest Grenze und Erlaubnis **einmal**,
  wenn D3DMetal geladen wird (`takeHold`), und hält sie danach in `paceLimit`. **Live möglich mit kleinem Umbau:**
  `pacedPresent` müsste die Erlaubnisdatei (`~/Library/Application Support/Nightforge/d3dmetal-pace`) alle paar Sekunden neu lesen
  und `paceLimit` anpassen. Das ist neuer Code im Spielprozess, aber nur in einer Bibliothek, die dort schon läuft. In Spielen mit
  Anti-Cheat ist sie gar nicht aktiv (keine Variable, keine Erlaubnis). Risiko: eine Dateilese-Schleife im Present-Pfad, also
  nur mit Zeitabstand und ohne Sperren. Nach dem Revert der Dock-Bibliothek gilt: erst Probe, dann Bau.
- *Mac-Versionen:* Die Bildrate gehört dem Spiel. Nightforge setzt sie nicht. **Geht nicht.**

**Lautstärke.**
- *Die des Macs:* Core Audio, Standardausgabe, `kAudioDevicePropertyVolumeScalar` (Element „main“) und `kAudioDevicePropertyMute`.
  Probe 23.11. (nur gelesen): beides vorhanden, setzbar, **ohne Erlaubnis**. **Geht live.** Hängt am Ausgang: HDMI zum
  Fernseher oder zu einem Verstärker hat oft keine Software-Lautstärke. Dann ist die Kachel ausgeblendet (`hidden`), wie in
  ENTWURF-OVERLAY §3 vorgesehen. Den Ausgang kennt `GameAudio`.
- *Nur die des Spiels:* Core Audios Prozessobjekte (`kAudioHardwarePropertyTranslatePIDToProcessObject`) haben **keine**
  Lautstärke (Probe: kein `VolumeScalar` am Prozessobjekt). Ein eigener Pegel je Spiel ginge nur über einen Process Tap
  (`CATapDescription`, macOS 14.2+). Der braucht die Erlaubnis „Audioaufnahme“, eine macOS-Frage, also nichts fürs Sofa.
  Über Wine (`ISimpleAudioVolume` eines anderen Prozesses) ist es unbelegt; Wines Audio-Sitzungen gelten je Prozess.
  **Geht nicht ohne Erlaubnis.**

**Bildschirmfoto.**
- Nur das Spielfenster: `ScreenCaptureKit` (`SCScreenshotManager.captureImage`, macOS 14) mit einem `SCContentFilter` auf das
  Fenster des Spiels, auch im eigenen Vollbild des Spiels.
- Braucht **„Bildschirmaufnahme“**, eine macOS-Erlaubnis, die nur mit Maus oder Trackpad zu erteilen ist. Wie beim Pad-Zeiger
  also vorher einholen (Ersteinrichtung oder Konsolenmodus-Anfrage). Ohne sie: `needsRight` mit einem Satz.
- Im Spielprozess nichts, also auch bei Anti-Cheat-Spielen unbedenklich: Das Bild kommt vom Fenstersystem.
- Wohin: dorthin, wo macOS Bildschirmfotos ablegt (`com.apple.screencapture location`, sonst Schreibtisch), Name
  „<Spiel> <Datum Uhrzeit>.png“. Mit dem Pad dann eine kurze Meldung, kein Fenster. **Geht live, mit Erlaubnis.**

**Downloads.**
- Was schon da ist: `model.downloads`, die Raten (`downloadRates`), der Stand je Download (`DownloadsPanel.status`), dazu
  `KeepAwake` hält den Mac wach, solange geladen wird.
- Fürs Overlay: **anzeigen geht live**, ohne Spielprozess. **Steuern** (anhalten, fortsetzen) nur dort, wo Nightforge den Download
  selbst führt (Epic über legendary, GOG über gogdl). Steams eigene Downloads steuert Steam; während eines Spiels hält Steam sie oft
  selbst an. Das sollte die Kachel sagen, statt einen Knopf zu zeigen, der nichts tut.

**Akku je Controller:** ausgeliefert (`OverlayPadsTile`).

**MetalFX an/aus.**
- D3DMetal liest `D3DM_ENABLE_METALFX` beim Start aus der Umgebung (`Engine.prepareLaunchEnvironment`); DXMT liest
  `d3d11.metalSpatialUpscale` aus `dxmt.conf` beim Anlegen des Geräts. **Erst beim nächsten Start**, bei Steam-Spielen dazu ein
  Steam-Neustart (die Umgebung kommt mit Steam, siehe `ENTWURF-SPIELWECHSEL.md`). Das Overlay kann es also nur **für den nächsten
  Start** umstellen (`nextStart` mit Satz).

**Leistungsanzeige (Metal-HUD).** Zur Vollständigkeit: Sie wird beim Start über die Umgebung eingeschaltet. Der Patch zum
Umschalten im Spiel (`claude/dxmt-hud-toggle-033`) wirkt nur, wenn der HUD beim Start an war. **Nächster Start**, mit Patch
teilweise live.

## Übersicht für die Variantenwahl

| Funktion | Geht live | Nur beim nächsten Start | Geht nicht | Braucht |
|---|---|---|---|---|
| Uhr, Spielzeit, Akku je Controller | ✅ (ausgeliefert) | | | – |
| Lautstärke des Macs | ✅ | | an Ausgängen ohne Software-Lautstärke (oft HDMI) | – |
| Lautstärke nur des Spiels | | | ✅ ohne Erlaubnis | „Audioaufnahme“ (Process Tap) |
| Bildschirmfoto des Spielfensters | ✅ | | ohne Erlaubnis | „Bildschirmaufnahme“, vorher eingeholt |
| Downloads anzeigen | ✅ | | | – |
| Downloads anhalten/fortsetzen | ✅ Epic, GOG | | Steam (steuert Steam selbst) | – |
| Bildratengrenze, D3DMetal | ✅ nach kleinem Umbau der Bibliothek (Probe zuerst) | ✅ heute | | nichts Neues in Anti-Cheat-Spielen (dort inaktiv) |
| Bildratengrenze, DXMT/DXVK | | ✅ | live nur mit Patch | DXMT-Patch: dein OK (LGPL) |
| Bildratengrenze, Mac-Versionen | | | ✅ | – |
| MetalFX an/aus | | ✅ (Steam-Spiele mit Steam-Neustart) | | – |
| Leistungsanzeige | teilweise (Patch, nur wenn beim Start an) | ✅ | | – |
