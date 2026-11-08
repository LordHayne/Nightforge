# Entscheidung: DXMT-Build unter LGPL (0.3.3)

**Entschieden: Ja, 8.11.2026, der Nutzer** („ja auf jeden fall machen“).

**Frage war:** Darf `engine/patches/dxmt-0.80-prepare-shaders.patch` in unseren DXMT-Build? Gemergt wird nach einem lokalen Test. Die Messung ist kein Tor mehr, sie bleibt als späterer Beleg im Plan (`docs/ENTWURF-SHADER.md`).

**Mit dem Ja:** Der DXMT-Teil des Graphics-Pakets steht danach als Ganzes unter LGPL-2.1-or-later statt MIT, denn der Patch enthält Teile aus Recalls DXMT-Patches, die unter dieser Lizenz stehen.
**Wäre es ein Nein gewesen:** Alles bliebe MIT, die erste Runde bliebe, wie sie ist.

**Was uns das verpflichtet (LGPL-2.1)**

| Pflicht | Wo sie erfüllt ist | Noch zu tun |
|---|---|---|
| Quelltext zu jeder ausgelieferten Datei, am selben Ort (§ 4) | Zweites Asset jedes Graphics-Release: `nightforge-graphics-<version>-source.tar.xz` mit unverändertem DXMT, allen Patches und `graphics.yml` | Nichts, läuft automatisch. Dieses Asset nicht löschen, solange das Release steht |
| Lizenztext und Urheberhinweise mitgeben (§ 1) | `licenses/` im Paket: `NOTICE.txt`, `COPYING-Wine.txt` (derselbe Lizenztext) und die bisherigen Lizenzen. Dazu `THIRD_PARTY_NOTICES.txt` | Nichts, auf dem Zweig angepasst |
| Geänderte Dateien kennzeichnen, mit Datum (§ 2 b) | Vermerk in jeder Datei des Patches, Herkunft im Patch-Kopf | Nichts |
| Für alle kostenlos unter derselben Lizenz (§ 2 c) | Nightforge und das Paket sind kostenlos | Nichts |

**Was öffentlich würde:** nur die Patch-Datei im Repository und der Quelltext-Asset am Graphics-Release, beides wie bei den bisherigen Patches.
**Nie:** Shader-Code und Metal-Bibliotheken von Spielen, Caches, Spieldaten. Die Patches laden nichts hoch und täuschen keine Hardware vor.

**Was unberührt bleibt**

- Nightforge selbst bleibt GPL-3. Die App bindet DXMT nicht ein, es bleibt eine getrennt geladene Komponente (§ 2, letzter Absatz).
- Spieler merken nichts und müssen nichts tun. Spiele und ihre Dateien sind nicht betroffen.
- DXVK, MoltenVK, D3DMetal und Wine behalten ihre Lizenzen.
- Recalls Apache-Teile (`pipeline_warm.m`) sind nicht übernommen, sein `NOTICE` muss deshalb nicht mit.
- `components/manifest.json` führt das Graphics-Paket schon als LGPL-2.1-or-later.

**Einordnung:** Upstream-DXMT steht inzwischen selbst unter LGPL-2.1-or-later, jedes spätere DXMT-Update brächte das also ohnehin. Ein Ja gilt nur für die Lizenz: Der Merge nach `main` löst sofort ein neues Graphics-Release aus und bleibt eine eigene Freigabe. Zurück geht es mit einem Build ohne den Patch; schon verteilte Builds bleiben LGPL.

Keine Rechtsberatung.
