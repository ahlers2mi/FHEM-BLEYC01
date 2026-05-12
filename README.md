# FHEM-BLEYC01

FHEM-Modul zur Dekodierung von BLE-YC01 Pool-Sensor-Daten über Tasmota/MQTT2.

---

## Inhaltsverzeichnis

- [Übersicht](#übersicht)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Define](#define)
- [Set](#set)
- [Get](#get)
- [Attribute](#attribute)
- [Readings](#readings)
- [Beispiel-Setup](#beispiel-setup)
- [Bekannte Probleme](#bekannte-probleme)

---

## Übersicht

Der **BLE-YC01** ist ein Bluetooth-Low-Energy-Poolsensor, der folgende Messwerte überträgt:

| Messwert      | Einheit  |
|---------------|----------|
| Temperatur    | °C       |
| PH-Wert       | pH       |
| ORP           | mV       |
| Leitfähigkeit | µS/cm    |
| TDS           | ppm      |
| Chlor         | mg/l     |
| Batterie      | %        |

Das Modul empfängt die Rohdaten als HEX-String (z. B. über Tasmota BLE + MQTT2), dekodiert sie und schreibt die Werte als FHEM-Readings. Zusätzlich wird für jeden Messwert ein `*_OK`-Reading gesetzt, das angibt ob der Wert im konfigurierten Sollbereich liegt.

---

## Voraussetzungen

- FHEM (aktuelle Version)
- Tasmota-Gerät mit BLE-Unterstützung (z. B. ESP32), das den BLE-YC01 ausliest
- MQTT2_SERVER und MQTT2_DEVICE in FHEM konfiguriert

---

## Installation

### Manuell

```bash
cp 98_BLEYC01.pm /opt/fhem/FHEM/
```

Danach in der FHEM-Konsole:

```
reload 98_BLEYC01
```

### Über FHEM Update

```
update add https://raw.githubusercontent.com/ahlers2mi/FHEM-BLEYC01/main/controls_BLEYC01.txt
update
```

---

## Konfiguration

### Define

```
define <name> BLEYC01 <device>:<reading>
```

| Parameter  | Beschreibung                                                  |
|------------|---------------------------------------------------------------|
| `name`     | Gerätename in FHEM                                            |
| `device`   | Name des MQTT2_DEVICE, das die Rohdaten liefert               |
| `reading`  | Reading-Name des MQTT2_DEVICE, das den HEX-String enthält     |

**Beispiel:**

```
define myBLEYC01 BLEYC01 MQTT2_tasmota8:BLEOperation_read
```

---

### Set

| Befehl          | Beschreibung                                                                 |
|-----------------|------------------------------------------------------------------------------|
| `test <hex>`    | Testet die Dekodierung mit einem manuell eingegebenen HEX-String             |
| `update`        | Führt den unter Attribut `updateCmd` hinterlegten Befehl aus (z. B. BLE-Scan) |

---

### Get

| Befehl    | Beschreibung                                          |
|-----------|-------------------------------------------------------|
| `devices` | Zeigt das aktuell registrierte Notify-Gerät an        |

---

### Attribute

| Attribut    | Standard | Beschreibung                                      |
|-------------|----------|---------------------------------------------------|
| `disable`   | 0        | 1 = Modul deaktivieren (keine Events verarbeiten) |
| `updateCmd` | –        | FHEM-Befehl, der per `set update` ausgeführt wird |
| `ChlorMin`  | 0.5      | Unterer Sollwert für Chlor (mg/l)                 |
| `ChlorMax`  | 1.0      | Oberer Sollwert für Chlor (mg/l)                  |
| `PHMin`     | 7.0      | Unterer Sollwert für pH                           |
| `PHMax`     | 7.4      | Oberer Sollwert für pH                            |
| `TDSMin`    | 250      | Unterer Sollwert für TDS (ppm)                    |
| `TDSMax`    | 2000     | Oberer Sollwert für TDS (ppm)                     |
| `ORPMin`    | 650      | Unterer Sollwert für ORP (mV)                     |
| `ORPMax`    | 750      | Oberer Sollwert für ORP (mV)                      |
| `ECMin`     | 250      | Unterer Sollwert für Leitfähigkeit (µS/cm)        |
| `ECMax`     | 2000     | Oberer Sollwert für Leitfähigkeit (µS/cm)         |

> **Hinweis Chlor:** Bei Wassertemperatur > 30 °C gelten automatisch höhere Standardgrenzwerte (1.2–2.0 mg/l).

---

### Readings

| Reading      | Einheit  | Beschreibung                                |
|--------------|----------|---------------------------------------------|
| `Temperatur` | °C       | Wassertemperatur                            |
| `PH`         | pH       | pH-Wert                                     |
| `PH_OK`      | true/false | pH im Sollbereich                         |
| `ORP`        | mV       | Redoxpotential                              |
| `ORP_OK`     | true/false | ORP im Sollbereich                        |
| `EC`         | µS/cm    | Elektrische Leitfähigkeit                   |
| `EC_OK`      | true/false | EC im Sollbereich                         |
| `TDS`        | ppm      | Gelöste Feststoffe                          |
| `TDS_OK`     | true/false | TDS im Sollbereich                        |
| `Chlor`      | mg/l     | Chlorgehalt (NAN wenn Sensor kein Signal)   |
| `Chlor_OK`   | true/false/NAN | Chlor im Sollbereich                  |
| `Batterie`   | %        | Batteriestand                               |

---

## Beispiel-Setup

### Tasmota-Seite (Berry-Script)

Tasmota liest den BLE-YC01 per BLE aus und veröffentlicht die Rohdaten über MQTT:

```
Topic: tele/tasmota8/SENSOR
Payload: {"BLEOperation":{"read":"<HEX-String>"}}
```

### FHEM-Seite

```
# MQTT2_SERVER (falls noch nicht vorhanden)
define mqtt_server MQTT2_SERVER 1883 global

# MQTT2_DEVICE für Tasmota
define MQTT2_tasmota8 MQTT2_DEVICE
attr MQTT2_tasmota8 readingList tele/tasmota8/SENSOR:.* BLEOperation_read:$events

# BLEYC01-Dekoder
define myBLEYC01 BLEYC01 MQTT2_tasmota8:BLEOperation_read

# Optionale Grenzwerte
attr myBLEYC01 PHMin 7.2
attr myBLEYC01 PHMax 7.6
attr myBLEYC01 ChlorMin 0.5
attr myBLEYC01 ChlorMax 1.5
```

---

## Bekannte Probleme

### Gerät reagiert nach FHEM-Neustart nicht auf Events

**Ursache:** Beim FHEM-Start ist `$init_done = 0`. Das Quellgerät (z. B. `MQTT2_tasmota8`) existiert zu diesem Zeitpunkt noch nicht in `%defs`, daher wird `NOTIFYDEV` nicht korrekt gesetzt.

**Lösung ab v1.4.1:** Das Modul registriert sich beim Start auf das globale `INITIALIZED`-Event und holt die Geräteregistrierung automatisch nach. Ein manueller Workaround ist nicht mehr notwendig.

**Workaround für ältere Versionen (< v1.4.1):** Nach dem FHEM-Start einmalig neu definieren:
```
defmod myBLEYC01 BLEYC01 MQTT2_tasmota8:BLEOperation_read
```
