# BashTwoWindows

Kleine native macOS-App in Swift/AppKit ohne Xcode-Projektdatei.

Die App startet zwei Fenster:

1. Input: mehrzeiliges Textfeld fuer Bash-Befehle.
2. Output: zeigt stdout und stderr der Bash-Ausfuehrung.

Im Eingabefenster fuehrt Command+E den Befehlsabschnitt an der Cursorposition mit /bin/bash aus.

## Voraussetzungen

Du brauchst macOS mit Apples Swift-Toolchain und dem macOS SDK. Bei dir sah das bereits passend aus, wenn diese Befehle funktionieren:

```bash
swift --version
xcrun --show-sdk-path
```

Die Apple-Toolchain und das SDK sind nicht im ZIP enthalten. Sie kommen von Xcode oder Apples Command Line Tools.

## Schnellstart

ZIP entpacken, dann im Projektordner:

```bash
./run.sh
```

Das baut die App und startet sie direkt.

## Nur bauen

```bash
./build.sh
```

Das erzeugt:

```text
dist/BashTwoWindows.app
```

Starten:

```bash
open dist/BashTwoWindows.app
```

## Clean

```bash
./clean.sh
```

oder:

```bash
make clean
```

## IntelliJ

1. ZIP entpacken.
2. Den Ordner NativeBashTwoWindows in IntelliJ oeffnen.
3. Im integrierten Terminal ausfuehren:

```bash
./run.sh
```

Optional kannst du eine Shell-Script-Run-Configuration verwenden:

- Script path: build.sh
- Script options: run
- Working directory: project root
- Interpreter: /bin/bash

Eine Beispiel-Run-Configuration liegt in .run/BashTwoWindows.run.xml. Je nach IntelliJ-Installation wird sie automatisch erkannt.

## Dateien

```text
NativeBashTwoWindows/
  Sources/BashTwoWindows/main.swift   Swift/AppKit-Quellcode
  build.sh                           baut dist/BashTwoWindows.app
  run.sh                             baut und startet die App
  clean.sh                           loescht Build-Artefakte
  Makefile                           make build / make run / make clean
  Package.swift                      optional fuer Editor-/SPM-Erkennung
  .run/BashTwoWindows.run.xml         IntelliJ Shell-Script-Konfiguration
```

## Deployment Target

Standard ist macOS 13.0. Du kannst es beim Bauen ueberschreiben:

```bash
MACOSX_DEPLOYMENT_TARGET=14.0 ./build.sh
```

## Verhalten der Bash

- Bash wird als /bin/bash -s gestartet.
- stdin, stdout und stderr laufen ueber Pipes.
- Das Arbeitsverzeichnis der Bash wird beim App-Start aus der Umgebung uebernommen.
- Ueber File > Choose Working Directory... kannst du per Finder-Auswahldialog ein anderes Arbeitsverzeichnis fuer neue Bash-Ausfuehrungen waehlen.
- Das Eingabefenster laedt beim Start und beim Wechsel des Arbeitsverzeichnisses .worksheet.shw aus dem Arbeitsverzeichnis, falls die Datei existiert.
- Sobald der Inhalt des Eingabefensters geaendert wurde, wird er beim Beenden oder vor einem Arbeitsverzeichniswechsel als .worksheet.shw im aktuellen Arbeitsverzeichnis gespeichert.
- .worksheet.shw enthaelt zuerst einen einfachen Header mit den Geometrien beider Fenster; nach einer Leerzeile folgt der Textpuffer des Eingabefensters.
- PATH wird gesetzt auf:

```text
/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

Innerhalb des Textfelds kannst du natuerlich selbst mit cd wechseln, zum Beispiel:

```bash
cd ~/Desktop
pwd
ls -la
```

## Sicherheitshinweis

Die App fuehrt den Text im Eingabefenster als Bash-Code aus. Verwende sie nur mit eigenen, vertrauenswuerdigen Befehlen.

Programme, die ein echtes Terminal/TTY brauchen, zum Beispiel manche interaktiven Vollbildprogramme oder sudo-Passwortabfragen, koennen in dieser Pipe-basierten Variante unzuverlaessig funktionieren.
