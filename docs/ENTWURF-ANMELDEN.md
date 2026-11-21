# Entwurf: Anmelden am Sofa ohne Tastatur

Stand 8.11.2026, gelesen auf `origin/main` 2276ccb. Ein Bericht, nichts ist gebaut. Das Board dazu heißt
`Anmelden.dc.html` und liegt im Notizordner.

**Entschieden am 8.11. und auf diesem Zweig gebaut:** GOG mit Variante A, Epic mit Variante C, die Texte für Steam und
Battle.net, Punkt G1 ohne zweiten Schritt. Abweichend vom Entwurf unten:
- Die Verbindung zwischen Handy und Mac bleibt einfaches HTTP, ohne Verschlüsselung im Browser. Wer im selben WLAN mitliest,
  könnte den Einmal-Code sehen. Er gilt einmal, und Nightforge löst ihn sofort ein.
- GOG startet nur dann mit dem QR-Code, wenn ein Controller verbunden ist. Sonst kommt wie bisher die Seite, und ein Knopf
  wechselt zum Handy. So öffnet am Schreibtisch niemand ohne Grund einen Port.
- Der Einmal-Token gilt 10 Minuten. Danach bietet die Bühne einen neuen Code an.

**Wie die Aussagen belegt sind:**
- **[Code]** Datei und Zeile im Stand oben. **[SDK]** Header aus `MacOSX26.5.sdk`.
- **[Quelle]** siehe Quellenliste am Ende, mit Nummer.
- **[Vermutung]** nicht belegt. **Live:** nur am Gerät zu beurteilen, siehe „Live prüfen“.
- **„Nicht gefunden“** heißt: Die Suche und die erreichbaren Seiten des Stores nennen es nicht. Es heißt nicht, dass es
  das sicher nicht gibt.

## Ergebnis in Kürze

| Store | Ohne Tastatur möglich? | Was dafür zu tun ist |
|---|---|---|
| Steam | Ja, heute schon, mit der Steam-App | Nur die Bühne muss es sagen |
| Epic Games | Nur mit einem Umweg: anmelden auf dem Handy, Code zurücktragen | Variante A oder B |
| GOG | Ebenso | Variante A oder B |
| Battle.net | Nicht belegt. Passkey ist der einzige Kandidat | Live prüfen, sonst einmal Tastatur |

Einen offiziellen Code- oder QR-Ablauf, den Nightforge für Epic oder GOG nutzen dürfte, habe ich nicht gefunden. Der
Umweg ist deshalb immer derselbe: Die echte Seite des Stores öffnet sich auf dem Handy, der Spieler meldet sich dort
an, und nur der Einmal-Code kommt zu Nightforge.

**Empfehlung:** Variante A für Epic und GOG, die Worte aus Variante C für alle Stores. Vorher muss der Nutzer eine
Frage beantworten: Epics Seite warnt ausdrücklich davor, diesen Code weiterzugeben (siehe „Entscheidungen“).

## Die feste Grenze und was sie bedeutet

Passwörter laufen nie durch Nightforge. Es geht nur um Codes und die echten Seiten der Stores.

Daraus folgt eine Korrektur an `docs/ENTWURF-KONSOLE.md` (Zweig `claude/touchpad-tastatur-033`, Punkt G1): Der zweite
Schritt dort will die Pad-Tastatur auch auf Epics und GOGs Anmeldeseite bringen. Das geht unter dieser Grenze nicht.
Jeder getippte Buchstabe des Passworts liefe durch Nightforge. Die Pad-Tastatur bleibt bei Suche und anderen Feldern
ohne Geheimnis.

Noch etwas gehört offen gesagt: Nightforge meldet sich schon heute bei Epic mit der Client-ID des Epic-Launchers an
(so arbeitet legendary) und bei GOG mit der von GOG Galaxy (so arbeitet gogdl) **[Code]** `EpicSignIn.swift:12`,
`GOGSignIn.swift:11`. Die Anmeldeseiten sind echt, ein von den Stores vorgesehener Zugang für fremde Launcher ist das
aber nicht. Der Handy-Weg ändert daran nichts und weitet es nicht aus. Er nutzt dieselbe Seite und denselben Code.

## Heute im Code

- **Epic und GOG:** Die Seite des Stores liegt in der Bühne in einem `WKWebView` **[Code]** `SignInStage.swift:81`. Das
  Pad hat dort nichts zu tun **[Code]** `InputRouter.swift:924`. Der Code wird schon ausgelesen: bei Epic aus der
  JSON-Antwort **[Code]** `EpicSignIn.swift:19`, bei GOG aus der Adresse **[Code]** `GOGSignIn.swift:25`. Beide Prüfungen
  lassen sich für einen vom Handy gebrachten Code wiederverwenden.
- **Steam und Battle.net:** Der eigene Client meldet sich in seinem eigenen Fenster an, Nightforge zeigt nur den Hinweis
  dazu **[Code]** `SignInStage.swift:83`. Beim ersten Start sagt Nightforge, dass der QR-Code reicht
  **[Code]** `Setup.swift:231`. Die Bühne im Launcher-Menü sagt das nicht, dort steht nur „dort anmelden“
  **[Code]** `SignInStage.swift:185`.

## Was je Store belegt ist

### Steam: geht

- Valve beschreibt den Ablauf selbst: In der Steam-App unter Steam Guard den QR-Code im Anmeldefeld scannen, in der App
  bestätigen **[Quelle 1]**. Voraussetzung ist der Mobile Authenticator in der App.
- Der Weg liegt komplett in Steams Fenster, Nightforge ist nicht beteiligt.
- Ohne Steam-App bleibt nur das Passwort in Steams Fenster, also eine Tastatur.
- **Offen, Live:** Ist der Code auf dem Fernseher vom Sofa aus lesbar?

### Battle.net: kein belegter Weg

- **QR oder Code für die Mac-App: nicht gefunden.** Ein Forum-Wunsch danach von Oktober 2024 blieb ohne Antwort von
  Blizzard **[Quelle 4]**. QR-Code und Code auf einer Battle.net-Seite gibt es für das Verknüpfen von Konsolen-Konten
  **[Quelle 5]**, die Mac-App meldet sich damit nicht an.
- **Passkeys gibt es**, laut Blizzard auch für die Battle.net-App **[Quelle 2]**. Eine Hilfeseite nannte sie zeitweise
  nur für die Beta der Desktop-App **[Quelle 3]**; sie war für mich nicht direkt lesbar, der Stand ist also offen.
  Blizzard nennt keine Anmeldung mit dem Handy als zweitem Gerät. Ob die Mac-App sie anbietet, ist **Live** zu prüfen.
- **Einmal-Code per Mail** gibt es für fremde Geräte **[Quelle 2]**, er muss aber in Blizzards Fenster getippt werden.
- Nightforge kann in Blizzards Fenster nicht tippen und soll es auch nicht. Bis der Passkey-Test etwas anderes zeigt,
  braucht Battle.net einmal eine Tastatur.

### Epic Games: nur über das Handy mit Code

- **Code für Konsolen:** Epic hat so einen Ablauf, er ist aber nicht für Nightforge da. Im offiziellen SDK ist der
  Anmeldetyp `DeviceCode` als veraltet markiert, sein Nachfolger gilt für Konsolen **[Quelle 6]**. Ein eigener
  EOS-Zugang gäbe vermutlich auch keinen Zugriff auf Bibliothek und Downloads **[Vermutung]**.
- **QR-Anmeldung oder Passkey:** nicht gefunden; die offiziellen Hilfeseiten nennen sie nicht **[Quelle 7]**, und zu
  Passkeys fanden sich nur unzuverlässige Seiten.
- **Epic Authenticator:** Das Handy bestätigt die Anmeldung, das Passwort muss vorher trotzdem eingegeben sein
  **[Quelle 7]**.
- **Was geht:** Dieselbe Seite wie heute auf dem Handy öffnen. legendary beschreibt genau das: Anmelden im Browser,
  dann den `authorizationCode` aus der JSON-Antwort übernehmen **[Quelle 8]**.
- **Die Hürde:** Dieselbe Antwort sagt wörtlich „Do not share this code with any 3rd party service“ **[Quelle 9]**. Heute
  sieht der Spieler das nie, weil Nightforge den Code still abholt. Auf dem Handy steht es vor ihm.

### GOG: ebenso, nur ohne Warnung

- **QR, Code-Ablauf oder Passkey: nicht gefunden.** QR-Codes gibt es bei GOG nur zum Einrichten einer Authenticator-App
  **[Quelle 10]**. Die Anmeldung läuft als Browser-Ablauf mit Code in der Adresse **[Quelle 11]**.
- **Was geht:** Die Seite auf dem Handy öffnen und die Adresse kopieren, auf der GOG landet. Sie enthält den Code. Die
  Adresse, an die GOG zurückschickt, ist fest vorgegeben, deshalb kann Nightforge den Code nicht selbst abfangen.

## Was ausscheidet

| Idee | Warum nicht |
|---|---|
| Pad-Tastatur auf der Anmeldeseite | Das Passwort liefe durch Nightforge |
| Handy als Tastatur oder Fernbedienung für die Seite | Ebenso |
| Eigene Anmeldeseite von Nightforge, die weiterleitet | Ebenso, und sie gäbe sich als Store aus |
| Code-Ablauf mit der Kennung eines Fortnite-Clients (so beschrieben in **[Quelle 12]**) | Nightforge gäbe sich als ein anderes Programm aus |
| Steams QR aus dem Fenster abgreifen und groß zeigen | Braucht Bildschirmaufnahme, und das Fenster ist Steams Sache |
| Synthetisches ⌘V, damit macOS nicht nach der Ablage fragt | Umgeht eine Schutzabfrage |
| Den Code mit der Pad-Tastatur eintippen | Zu lang: GOGs Prüfung erlaubt bis 2048 Zeichen **[Code]** `GOGSignIn.swift:27` |

Als Notlösung bleibt die Bedienungshilfen-Tastatur von macOS. Sie tippt am System vorbei, zeigt das Passwort aber
Buchstabe für Buchstabe auf dem Fernseher und muss erst in den Systemeinstellungen an. Keine Variante.

## Die drei Varianten

Das Board zeigt sie nebeneinander, jeweils am Beispiel von Epic.

| | A: Handy-Seite im WLAN | B: Direkt zum Store, Code über die Ablage | C: Nur ehrlich sagen |
|---|---|---|---|
| Der QR führt zu | einer kleinen Seite von Nightforge | der echten Seite des Stores | kein QR für Epic und GOG |
| Telefone | alle | nur iPhone mit demselben Apple Account | keine |
| Rückweg des Codes | von Hand in die Seite einfügen | geteilte Ablage, dann Ⓐ | entfällt |
| Neues in Nightforge | kleiner Webserver während der Anmeldung | Lesen der Ablage auf Knopfdruck | nur Texte |
| Systemdialog | keiner belegt | **macOS fragt bei jedem Lesen** | keiner |
| Aufwand | groß | mittel | klein |

**A: Handy-Seite im WLAN.** Nightforge öffnet nur während der Anmeldung einen Port und zeigt einen QR-Code mit seiner
IP-Adresse und einem Einmal-Schlüssel. Die Seite auf dem Handy hat zwei Schritte: „Bei Epic anmelden“ öffnet die echte
Seite in einem neuen Tab, darunter ist das Feld für den Code. Die Eingabe läuft durch dieselbe Prüfung wie heute.
- Für eingehende TCP-Verbindungen braucht es keine Freigabe „Lokales Netzwerk“, für Bonjour teilweise schon. Der QR
  trägt also die IP-Adresse **[Quelle 13]**. Ob die macOS-Firewall nachfragt, ist **Live** zu prüfen.
- Die Verbindung ist einfaches HTTP. Damit im WLAN niemand den Code mitliest, sollte die Seite ihn verschlüsseln, mit
  einem Schlüssel im Teil der QR-Adresse hinter dem `#`, der nie übertragen wird.
- Handy und Mac müssen im selben Netz sein, Gast-WLANs trennen das oft.

**B: Direkt zum Store, Code über die Ablage.** Der QR enthält nur die Adresse des Stores, Nightforge lauscht auf nichts.
Der Spieler kopiert Epics Antwort oder GOGs Adresse, die geteilte Ablage von Apple bringt sie auf den Mac **[Quelle 14]**,
und Ⓐ holt sie ab.
- Der Knackpunkt steht im SDK: Beim Lesen der allgemeinen Ablage fragt macOS nach, außer die Aktion geht vom Nutzer aus
  und ist ein Einfügen **[SDK]** `NSPasteboard.h:55`. Ein Pad-Knopf gehört wohl nicht dazu **[Vermutung]**. Dann kommt am
  Sofa jedes Mal ein Systemdialog, bis der Nutzer in den Systemeinstellungen „Immer erlauben“ setzt.
- Apple sagt, dass der Inhalt nur kurz bleibt **[Quelle 14]**. Bei zügigem Ablauf reicht das **[Vermutung]**.

**C: Nur ehrlich sagen.** Kein neuer Weg für Epic und GOG. Die Bühne sagt vorher, dass eine Tastatur nötig ist, und bietet
„Später anmelden“. Steam nennt den QR-Code. Sofort machbar, aber das Sofa-Problem bleibt für zwei Stores.

**In jeder Variante gleich:** Der Steam-Hinweis auf der Bühne nennt QR-Code und Steam-App, Battle.net sagt offen, dass es
eine Tastatur braucht. Die Seite des Stores bleibt mit Tastatur immer erreichbar. Danach ist auch der Satz in README und
Release-Notizen anzupassen, dass Anmelden eine Tastatur braucht.

## Entscheidungen des Nutzers

1. **Welche Variante?** Empfehlung: A, mit den Worten aus C.
2. **Epics Warnung:** Darf Nightforge den Spieler bitten, einen Code weiterzugeben, vor dem Epic warnt? Technisch ist es
   derselbe Code, den Nightforge heute still abholt, und er geht an kein fremdes Netz. Für den Spieler sieht es trotzdem
   nach dem aus, wovor gewarnt wird, und es gewöhnt ihn an eine Geste, die anderswo gefährlich ist. Empfehlung: nur mit
   einem klaren Satz auf der Handy-Seite. Wer das nicht möchte, nimmt für Epic C und für GOG A.
3. **Punkt G1 im Konsolen-Entwurf:** Zweiter Schritt gestrichen, wie oben begründet? Empfehlung: ja.

## Live prüfen

Noch nicht geprüft, keine Anmeldung und keine GUI in dieser Runde.

1. **Epic auf dem iPhone und auf Android:** Landet die Anmeldung auf der JSON-Antwort, oder drängt sich die Epic-App dazwischen?
2. **GOG auf dem Handy:** Geht die Seite mit `layout=galaxy`, und bleibt die Adresse mit dem Code kopierbar?
3. **Steam:** Ist der QR-Code auf dem Fernseher vom Sofa aus lesbar, in beiden Steam-Fenstern?
4. **Battle.net für Mac:** Bietet das Fenster einen Passkey an, und lässt sich dabei das Handy nutzen?
5. **GOG mit dem Handy:** Erreicht das Handy den Port, auch bei eingeschalteter macOS-Firewall? Fragt macOS beim ersten
   Mal nach? Geht es durch, bis GOG verbunden ist, und ist die Seite danach weg?
6. **Warnungen im Browser:** Warnt Safari oder Chrome auf dem Handy vor der HTTP-Seite („Immer sichere Verbindungen“)?
7. **Controller auf der Bühne:** X wechselt zwischen Handy und Tastatur, bei Epic führt A zu „Später anmelden“.

## Quellen

1. Steam Support, Steam Guard Mobile Authenticator: https://help.steampowered.com/faqs/view/7EFD-3CAE-64D3-1C31
2. Blizzard, Passkeys und Einmal-Codes: https://news.blizzard.com/en-us/article/24240392/passkeys-and-one-time-passcodesfaster-and-safer-ways-to-log-in
3. Blizzard Support, Passkey mit Battle.net (nur als Suchauszug gelesen): https://eu.support.blizzard.com/en/article/000380924
4. Blizzard-Forum, Wunsch nach QR-Anmeldung, 31.10.2024: https://us.forums.blizzard.com/en/overwatch/t/add-login-using-qr-code/936179
5. Overwatch, Cross-Play und Verknüpfen auf Konsolen: https://overwatch.blizzard.com/en-us/news/23684155/il-cross-play-e-in-arrivo-su-overwatch/
6. Epic Online Services (Suchauszüge, die Seiten rendern nur im Browser): https://dev.epicgames.com/docs/services/en-US/API/Members/Enums/Auth/EOS_ELoginCredentialType/index.html und https://dev.epicgames.com/docs/services/en-US/API/Members/Structs/Auth/EOS_Auth_PinGrantInfo/index.html
7. Epic Hilfe, Methoden der Zwei-Faktor-Anmeldung: https://www.epicgames.com/help/c-45487929/c-38978022/what-two-factor-authentication-2fa-methods-are-available-to-use-with-my-epic-games-account-a11272697
8. legendary, Anmeldung und `--code`: https://github.com/legendary-gl/legendary
9. Epics Antwortseite, am 8.11. ohne Anmeldung abgerufen: https://www.epicgames.com/id/api/redirect
10. GOG Support, zweistufige Anmeldung (nur als Suchauszug gelesen): https://support.gog.com/hc/en-us/articles/115003660533
11. Inoffizielle GOG-API-Doku: https://readthedocs.org/projects/gogapidocs/downloads/pdf/latest/
12. EpicResearch, Device Code (Gemeinschaft, nur als Beleg für das Ausgeschlossene): https://github.com/MixV2/EpicResearch/blob/master/docs/auth/grant_types/device_code.md
13. Apple TN3179, Local Network Privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
14. Apple, Universal Clipboard: https://support.apple.com/en-us/102430
