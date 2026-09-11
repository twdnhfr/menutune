# Prüfung der ersten Version

Stand: 10. September 2026, lokal auf Apple Silicon mit macOS 26.6.2. Mindestziel ist macOS 14; ältere macOS-Versionen wurden nicht separat praktisch geprüft.

## Automatisierte Tests

`swift test`: **26 Tests, 0 Fehler** (einschließlich Pop-out-Erweiterung vom 11.09.2026 und Review-Korrekturen vom 11.09.2026).

Geprüft werden URL- und Zeitparameter, erlaubte Hosts, Clipboard-URL-Erkennung, Queue-Navigation und Wiederholung, Entfernen/Verschieben, atomare Speicherung und Umgang mit beschädigten Dateien. Ein zusätzlicher Test verwendet das echte AppModel mit einem privaten, benannten Pasteboard und einer temporären Bibliothek: Lesen allein verändert keine Wiedergabe/Queue, Bestätigung fügt genau einmal hinzu, Verwerfen bleibt für denselben Clipboard-Stand wirksam, neuer Clipboard-Inhalt wird neu geprüft. Die allgemeine Zwischenablage wird im Test nicht verändert.

Ein Test hängt die Oberfläche in ein echtes Fenster und prüft, dass die gemessene Inhaltshöhe dem Layout folgt und beim Aufklappen der Warteschlange wächst. Damit ist die Popover-Höhe nicht länger eine handgepflegte Kopie des Layouts.

Aus dem Review vom 11.09.2026 kamen weitere Tests hinzu. Eine Bibliothek mit unbekanntem Wiederholungsmodus und fehlendem Titel bleibt lesbar, statt den ganzen Ladevorgang scheitern zu lassen. Ein zweites Exemplar desselben Links über das Eingabefeld übernimmt den bereits geladenen Titel. Die in der README zugesagte Garantie bei beschädigter Datei wird nun auf AppModel-Ebene geprüft: Warnung gesetzt, Weiterarbeit im Speicher möglich, Datei auf der Platte byteidentisch unverändert. Beim Verschieben ist erstmals der Zweig mit positivem Versatz abgedeckt, ebenso das Entfernen eines nicht ausgewählten Titels, das Entfernen des laufenden letzten Titels, "Zurück" auf dem ersten Titel ohne Wiederholung und die leere Warteschlange. Beim Längenlimit der Zwischenablage prüft ein Fall jetzt genau die Grenze statt einer ohnehin ungültigen Zeichenkette.

Zwei Tests decken erstmals die Bewegungsvorhersage der Ausweichlogik ab, einmal als alleiniger Auslöser eines Wechsels und einmal als alleiniger Grund, ein Ziel zu verwerfen. Gegenprobe: wird die Vorhersage im Quelltext neutralisiert, fallen genau diese beiden Tests um, alle übrigen bleiben grün. Der frühere Test `testStationaryPointerDoesNotCycleAfterMove` hieß irreführend, er prüfte nicht den Cooldown, sondern den Abstandswächter, und heißt jetzt danach.

Die Unit-Tests erreichen youtube.com nicht mehr. Bisher lud jede AppModel-Instanz die IFrame-API in eine echte WebView, und das Bestätigen aus der Zwischenablage löste einen oEmbed-Abruf aus. Beide Pfade hängen jetzt an einem Schalter im Initialisierer, den ausschließlich die Tests auf aus stellen.

Neun Tests prüfen die Ausweichlogik insgesamt: Annäherung, Reihenfolge sicherer Ziele, Bewegungsvorhersage in beide Richtungen, entfernter Zeiger nach einem Wechsel, Cooldown, fehlende sichere Ziele und negative Bildschirmkoordinaten. Ein Regressionstest prüft das Pendeln über die Mitte in beiden Richtungen (unten → Mitte → oben → Mitte → unten). Ein Host-Test stellt sicher, dass ein verspätetes Entfernen aus dem alten SwiftUI-Container die bereits ins schwebende Fenster verschobene WebView nicht entfernt. Der Speichertest deckt alle drei Größen sowie ältere Bibliotheken ohne Größenangabe ab.

## Test am echten YouTube-Player

Video: `https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s`

Erfolgreicher Durchlauf vom 10.09.2026, 14:03–14:04 UTC, im lokal gebauten App-Bundle:

| Prüfung | Ergebnis |
| --- | --- |
| Start mit Zeitparameter | Wiedergabe ab ca. Sekunde 3 |
| 30 Sekunden geschlossenes Popover | Zeit läuft weiter, alle sechs Stichproben unsichtbar und spielend |
| Wieder öffnen | Wiedergabe bleibt erhalten |
| Pause und Fortsetzen | Zeit bleibt bei Pause stehen; Status wechselt gelb/grün |
| Automatischer Titelwechsel bei geschlossenem Popover | Nächster Queue-Eintrag startet |
| Replay über den eingebetteten Player nach Queue-Ende | Status und Zeit bleiben synchron |
| Simulierter Netzwerkfehler, danach Queue-Auswahl | Player lädt neu und spielt |
| Simulierter Prozessfehler, Meldung schließen, Play | Player lädt neu und spielt |
| Lautstärkeänderung im Webplayer | Wird ins AppModel übernommen |

Die Abschlusszeile aus `build/playback-final-smoke.log`:

```text
SMOKE PASS: hidden=true pause=true resume=true automaticNext=true embeddedReplay=true recovery=true dismissedRecovery=true nativeVolume=true
```

Der Test wertet YouTubes Zustandsmeldungen und Fortschritt aus. WebKits Medienstatus wird zusätzlich protokolliert. Eine akustische Messung der Lautsprecher-/Kopfhörerausgabe ist nicht Teil des Tests.

## Ausgeliefertes App-Bundle

Am 11.09.2026 geprüft: mit verstecktem `.build`-Verzeichnis gestartet das Bundle sauber durch und der Player meldet `ready`. Vor der Korrektur brach derselbe Versuch sofort mit `Fatal error: could not load resource bundle` ab, weil SwiftPMs `Bundle.module` nur neben der ausführbaren Datei und danach an einem fest einkompilierten Build-Pfad sucht. `codesign --verify --strict` besteht weiterhin.

Die Korrekturen aus dem Review vom 11.09.2026 sind **nicht** erneut gegen den echten Player geprüft worden. Der Test unten braucht eine interaktive Desktop-Sitzung; ohne sie erscheint das Popover nicht und die Testsequenz startet nicht. Betroffen sind vor allem das Überspringen gesperrter Videos, die Übernahme von im Embed gestarteten Empfehlungen und die Pause während des Ladens.

## Bedienprüfung

- Laufende native Oberfläche visuell geprüft.
- Video nutzt die gesamte Breite am oberen Rand; separate Wiedergaberegler entfernt.
- Titelaktionen sind allein über den nativen Menüpfeil erreichbar; Öffnen des Menüs praktisch geprüft.
- Normaler Neustart erhält beide gespeicherten Titel, zeigt das ausgewählte Video ohne Autoplay und erlaubt den direkten Start über den eingebetteten Player.
- Globaler Hotkey `⌘⇧Y` zum Öffnen/Schließen ergänzt. Der Nutzer hat die Funktion am 10.09.2026 mit seiner Tastatur ausdrücklich bestätigt. Hotkey-Verhalten wird nicht separat automatisiert abgedeckt.
- Standard- und Mini-Ansicht visuell geprüft; Hin- und Rückwechsel am laufenden Video geprüft. Die Mini-Auswahl steht anschließend tatsächlich in der lokalen Bibliothek. Ein zusätzlicher Test prüft Größenpersistenz und Migration bestehender Bibliotheken mit Erhalt von Queue und Lautstärke.
- Mini auf Wunsch auf 192 × 108 Punkte für das Video vergrößert; ganzzahlige Abmessungen ersetzen die ursprüngliche Drittelbreite. Die aktualisierte Ansicht wurde erneut visuell geprüft.
- YouTube-Link über das native Clipboard-Paste eingefügt: Eingabefeld enthält anschließend den vollständigen Link, Plus-Schaltfläche wird aktiv.
- `⌘A` und Löschen im Eingabefeld praktisch geprüft.
- Pop-out am 11.09.2026 visuell geprüft: rahmenloses Video im schwebenden Fenster. Die neue mittlere Größe (320 × 180 Punkte) wurde in der laufenden App bestätigt; `medium` steht anschließend in der lokalen Bibliothek. Vollbild-Spaces und ein Wechsel zwischen mehreren Monitoren wurden nicht praktisch geprüft.
- Der Build erstellt ein ad-hoc signiertes Bundle; `codesign --verify --strict` besteht.

Die Erkennung/Bestätigung aus der Zwischenablage wurde nach dem Wiedergabetest ergänzt und durch den vollständigen Testlauf geprüft. Ein Langzeittest über mehrere Stunden, sämtliche YouTube-Videoarten und ältere macOS-Versionen sind nicht abgedeckt.
