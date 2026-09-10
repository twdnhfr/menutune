# MenuTune

Ein privater YouTube-Mini-Player für die macOS-Menüleiste. Öffne den Player per Klick, starte deine Musik und klappe das Menü wieder zu. Dieselbe WebView bleibt dabei bestehen.

## Starten

Voraussetzungen: macOS 14 oder neuer und eine installierte Swift-6-Toolchain (Xcode). Keine zusätzlichen Pakete, kein API-Schlüssel und kein eigener Server.

```sh
bash scripts/build-app.sh
open build/MenuTune.app
```

MenuTune erscheint dauerhaft als Wellenform in der Menüleiste. Ein kleiner Punkt unten rechts zeigt den Status: grün beim Abspielen, gelb bei Pause, kein Punkt bei inaktiver Wiedergabe. Die App hat keinen Dock-Eintrag. Über Rechtsklick erreichst du Play/Pause, den nächsten Titel und Beenden.

## Bedienung

- YouTube-Link einfügen und mit **+** zur Warteschlange hinzufügen. Enter fügt den Titel hinzu und startet ihn direkt.
- Beim Öffnen wird die Zwischenablage einmalig auf einen YouTube-Link geprüft. Das Häkchen übernimmt ihn in die Warteschlange, das X verwirft den Vorschlag bis zum nächsten Kopieren. Ohne Bestätigung wird nichts hinzugefügt oder gestartet. Es gibt keine Hintergrundüberwachung der Zwischenablage.
- Die üblichen Mac-Tastenkürzel wie `⌘V`, `⌘C`, `⌘X`, `⌘A` und `⌘Z` funktionieren im Linkfeld.
- Links von `youtube.com`, `youtu.be`, YouTube Music, Shorts, Live und Embed werden unterstützt; beim direkten Start wird ein Zeitparameter wie `t=3s` berücksichtigt.
- Auf einen Titel klicken, um ihn abzuspielen. Über sein Aktionsmenü kannst du ihn verschieben oder entfernen.
- Play/Pause, Lautstärke und Position werden direkt im YouTube-Player bedient. Es gibt keine doppelte Steuerungsleiste. Der Statuspunkt folgt auch diesen Player-Aktionen.
- Über das Menü neben **Warteschlange** lässt sich ein Titel oder die ganze Liste wiederholen. Nächster Titel und Play/Pause sind zusätzlich über Rechtsklick auf das Menüleisten-Symbol erreichbar.
- Ein Klick außerhalb oder auf den Pfeil oben schließt das Menü. Bei Titelwechseln öffnet es sich nicht automatisch.
- Fehler erscheinen innerhalb des Players. Sie öffnen kein zusätzliches Fenster.
- Die Warteschlange und Lautstärke werden lokal gespeichert. Beim nächsten App-Start beginnt keine automatische Wiedergabe.

Die lokale Datei liegt unter `~/Library/Application Support/MenuTune/library.json`. Ist sie beschädigt, bleibt sie unverändert; eine Meldung weist darauf hin, dass Änderungen vorerst nicht gespeichert werden. Nach Sicherung bzw. Wiederherstellung der Datei die App neu starten.

## Aktueller Umfang

Version 0.1 ist ein Machbarkeitsprototyp mit einer gespeicherten Warteschlange. Mehrere benannte Playlists, automatische Empfehlungen, Hover-Vorschau, Google-Anmeldung, Medientasten und Autostart sind noch nicht enthalten. Nicht jedes YouTube-Video erlaubt die Wiedergabe in eingebetteten Playern. In diesem Fall gibt es den Link **Auf YouTube öffnen**.

Die Wiedergabe nutzt den normalen YouTube-IFrame-Player in einer persistenten `WKWebView`. Es werden keine Videos heruntergeladen, Tonspuren extrahiert oder Werbeblocker eingebaut. Metadaten werden über YouTubes oEmbed-Endpunkt geladen. YouTube erhält beim Laden/Abspielen die üblichen Web-Anfragen und kann Cookies in der eigenen WebView speichern; die App importiert keine Browser-Cookies.

YouTubes Entwicklerbedingungen untersagen Hintergrundplayer. Private Nutzung stellt keine zugesicherte Ausnahme dar. Das Ein-/Ausblenden ist hier ausdrücklich ein persönlicher technischer Prototyp; dauerhaftes Funktionieren bei zukünftigen Änderungen durch YouTube oder WebKit wird nicht vorausgesetzt.

## Entwicklung und Tests

```sh
swift test
bash scripts/build-app.sh
```

Ein optionaler Test am echten Player protokolliert die Wiedergabe bei sichtbarem/geschlossenem Menü, Pause/Fortsetzen, einen automatischen Titelwechsel, Replay direkt im Embed und Wiederherstellung nach simulierten Lade-/Prozessfehlern. Er verwendet die übergebene Testbibliothek und lädt das Video zweimal in die Warteschlange; er startet ausschließlich mit diesen Argumenten:

```sh
build/MenuTune.app/Contents/MacOS/MenuTune \
  --library "$PWD/build/smoke-library.json" \
  --play-url 'https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s' \
  --smoke-test 2>build/playback-smoke.log
```

Der Test prüft die Player-Zeit und WebKit-Medienzustände. Er ist kein Nachweis dafür, dass Lautsprecher oder Kopfhörer hörbar Ton ausgeben. Während des Tests öffnet und schließt sich das Menü gezielt. Im normalen Betrieb geschieht das nicht.

Der Test beginnt erst, wenn der Player sichtbar geöffnet ist; bei Bedarf das Menüleisten-Symbol anklicken. Die geprüften Abläufe und Grenzen sind in [docs/VERIFICATION.md](docs/VERIFICATION.md) dokumentiert.

## Aufbau

- `MenuTuneCore`: URL-Prüfung, Warteschlange und atomare lokale Speicherung.
- `MenuTune`: AppKit-Menüleiste, SwiftUI-Oberfläche und WebKit-Player.
- `Resources/player.html`: kleine Brücke zur YouTube-IFrame-API.
- `scripts/build-app.sh`: baut ein lokal ad-hoc signiertes App-Bundle für die aktuelle Mac-Architektur.

Referenzen: [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference), [Native Embed-Identifikation](https://developers.google.com/youtube/terms/required-minimum-functionality#Set_the_Referer), [YouTube-Entwicklerbedingungen](https://developers.google.com/youtube/terms/developer-policies).
