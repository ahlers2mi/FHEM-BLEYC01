##############################################################################
# 98_BLEYC01.pm
#
# FHEM-Modul zur Dekodierung von Messwerten des BLE-YC01 Pool-Sensors.
#
# Der Sensor überträgt seine Messdaten als verschlüsselten HEX-String via
# Bluetooth Low Energy. Dieses Modul empfängt den Rohwert als FHEM-Reading
# (z. B. von einem MQTT2_DEVICE via Tasmota BLE-Gateway), dekodiert ihn mit
# einem Bit-Swap-Algorithmus und schreibt die berechneten Messwerte als
# FHEM-Readings.
#
# Unterstützte Messwerte:
#   Temperatur (°C), pH, ORP (mV), EC (µS/cm), TDS (ppm),
#   Chlor (mg/l), Batterie (%)
#
# Autor:    ahlers2mi
# Version:  v1.4.1
# Lizenz:   GPL v2 oder höher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use Data::Dumper;

use vars qw($init_done);

# ----------------------------------------------------------------------------
# BLEYC01_Initialize
#   Wird von FHEM beim Laden des Moduls aufgerufen.
#   Registriert alle Callback-Funktionen und die Attributliste.
# ----------------------------------------------------------------------------
sub BLEYC01_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}      = \&BLEYC01_Define;
    $hash->{UndefFn}    = \&BLEYC01_Undef;
    $hash->{SetFn}      = \&BLEYC01_Set;
    $hash->{GetFn}      = \&BLEYC01_Get;
    $hash->{AttrFn}     = \&BLEYC01_Attr;
    $hash->{ReadFn}     = \&BLEYC01_Read;
    $hash->{NotifyFn}   = \&BLEYC01_Notify;

    $hash->{AttrList} =
          "disable:1,0 " .
          "updateCmd " .
          "ChlorMin " .
          "ChlorMax " .
          "PHMin " .
          "PHMax " .
          "TDSMin " .
          "TDSMax " .
          "ORPMin " .
          "ORPMax " .
          "ECMin " .
          "ECMax " .
          $readingFnAttributes;

    $hash->{DbLog_splitFn} = \&BLEYC01_DbLog_splitFn;
}

# ----------------------------------------------------------------------------
# BLEYC01_setNotifyDev
#   Setzt NOTIFYDEV auf das konfigurierte Quellgerät und registriert den
#   Notify-Regexp bei FHEM. Wird als InternalTimer-Callback aufgerufen,
#   damit $defs sicher befüllt ist.
# ----------------------------------------------------------------------------
sub BLEYC01_setNotifyDev($) {
  my ($hash) = @_;

  if( $hash->{DEVICE} ) {
    $hash->{NOTIFYDEV} = $hash->{DEVICE};
    notifyRegexpChanged($hash, $hash->{DEVICE});
  } else {
    $hash->{NOTIFYDEV} = "";
    notifyRegexpChanged($hash, '');
  }
}

# ----------------------------------------------------------------------------
# BLEYC01_update
#   Dekodiert den HEX-Rohwert des Sensors und schreibt alle Readings.
#
#   Dekodierungs-Algorithmus (Bit-Swap, analog zum C++-Original):
#     Für jedes Byte-Paar (rückwärts iteriert):
#       1. Bits 0,2,4,6 (Maske 0x55) um 1 nach links  schieben  → hibit
#       2. Bits 1,3,5,7 (Maske 0xAA) um 1 nach rechts schieben → lobit
#       3. Ergebnis = ~(hibit_aktuell | lobit_vorgänger) & 0xFF (und umgekehrt)
#
#   Byte-Mapping nach Dekodierung:
#     [3..4]   → pH       (/100)
#     [5..6]   → EC
#     [7..8]   → TDS
#     [11..12] → Chlor    (/10)
#     [13..14] → Temp     (/10)
#     [15..16] → Batterie (/31.9)
#     [20..21] → ORP
# ----------------------------------------------------------------------------
sub BLEYC01_update($$) {
  my ($hash, $value) = @_;
  my $name = $hash->{NAME};

  my $DEVICE  = $hash->{DEVICE};
  return if( !$DEVICE );
  my $READING = $hash->{READING};

  # Leerwert abfangen
  if( !$value ) {
    Log3 $name, 4, "$name: ($READING) empty value";
    return;
  }

  # Mindestlänge prüfen (5 Zeichen = 2,5 Bytes – Plausibilitätscheck)
  if( length($value) < 5 ) {
    Log3 $name, 2, "$name: ($READING) reading is to short";
    return;
  }

  # 1. HEX-String in Byte-Array wandeln
  my @message = map { hex($_) } ($value =~ /../g);

  # 2. Bit-Swap-Dekodierung (rückwärts über alle Byte-Paare)
  for (my $i = scalar(@message) - 1; $i > 0; $i--) {
    my $tmp    = $message[$i];
    my $hibit1 = ($tmp & 0x55) << 1;
    my $lobit1 = ($tmp & 0xAA) >> 1;

    my $tmp_prev = $message[$i-1];
    my $hibit    = ($tmp_prev & 0x55) << 1;
    my $lobit    = ($tmp_prev & 0xAA) >> 1;

    $message[$i]   = ~($hibit1 | $lobit)  & 0xFF;
    $message[$i-1] = ~($hibit  | $lobit1) & 0xFF;
  }

  # 3. Messwerte aus dekodierten Bytes berechnen
  my $temp    = (($message[13] << 8) + $message[14]) / 10.0;
  my $ph      = (($message[3]  << 8) + $message[4])  / 100.0;
  my $orp     =  ($message[20] << 8) + $message[21];
  my $battery = (($message[15] << 8) + $message[16]) / 31.9;
  my $ec      =  ($message[5]  << 8) + $message[6];
  my $tds     =  ($message[7]  << 8) + $message[8];
  my $chlor   = (($message[11] << 8) + $message[12]) / 10.0;

  $battery = sprintf("%.2f", $battery);

  # 4. Readings schreiben und OK-Status anhand der Attributgrenzen berechnen
  readingsBeginUpdate($hash);

  readingsBulkUpdate($hash, "Temperatur", $temp);

  readingsBulkUpdate($hash, "PH", $ph);
  readingsBulkUpdate($hash, "PH_OK",
    ($ph >= AttrVal($name,"PHMin",7.0) && $ph <= AttrVal($name,"PHMax",7.4))
    ? "true" : "false");

  readingsBulkUpdate($hash, "ORP", $orp);
  readingsBulkUpdate($hash, "ORP_OK",
    ($orp >= AttrVal($name,"ORPMin",650) && $orp <= AttrVal($name,"ORPMax",750))
    ? "true" : "false");

  readingsBulkUpdate($hash, "Batterie", $battery);

  readingsBulkUpdate($hash, "EC", $ec);
  readingsBulkUpdate($hash, "EC_OK",
    ($ec >= AttrVal($name,"ECMin",250) && $ec <= AttrVal($name,"ECMax",2000))
    ? "true" : "false");

  readingsBulkUpdate($hash, "TDS", $tds);
  readingsBulkUpdate($hash, "TDS_OK",
    ($tds >= AttrVal($name,"TDSMin",250) && $tds <= AttrVal($name,"TDSMax",2000))
    ? "true" : "false");

  # Chlor: 6553.5 = Sentinel-Wert des Sensors für "kein Messwert"
  if ($chlor == 6553.5) {
    readingsBulkUpdate($hash, "Chlor",    "NAN");
    readingsBulkUpdate($hash, "Chlor_OK", "NAN");
  } else {
    readingsBulkUpdate($hash, "Chlor", $chlor);
    # Grenzwerte sind temperaturabhängig (>30°C verschärfte Obergrenzen)
    my ($chlorMin, $chlorMax) = $temp > 30
      ? (AttrVal($name,"ChlorMin",1.2), AttrVal($name,"ChlorMax",2.0))
      : (AttrVal($name,"ChlorMin",0.5), AttrVal($name,"ChlorMax",1.0));
    readingsBulkUpdate($hash, "Chlor_OK",
      ($chlor >= $chlorMin && $chlor <= $chlorMax) ? "true" : "false");
  }

  readingsEndUpdate($hash, 1);
}

# ----------------------------------------------------------------------------
# BLEYC01_updateDevices
#   Wertet die DEF-Parameter aus, setzt DEVICE und READING und plant
#   die Notify-Registrierung via InternalTimer.
#   Wird bei define (wenn $init_done=1) und nach INITIALIZED aufgerufen.
# ----------------------------------------------------------------------------
sub BLEYC01_updateDevices($) {
  my ($hash) = @_;

  my %list;
  delete $hash->{DEVICE};
  delete $hash->{READING};

  my @params = split(" ", $hash->{DEF});
  while (@params) {
    my $param  = shift(@params);
    my @device = split(":", $param);

    if( defined($defs{$device[0]}) ) {
      $list{$device[0]}  = 1;
      $hash->{DEVICE}    = $device[0];
      $hash->{READING}   = $device[1] // "state";
    }
  }

  # Notify-Registrierung via Timer (sicherstellt, dass $defs vollständig ist)
  InternalTimer(gettimeofday(), "BLEYC01_setNotifyDev", $hash);
  $hash->{CONTENT} = \%list;

  BLEYC01_update($hash, undef);
}

# ----------------------------------------------------------------------------
# BLEYC01_Define
#   Wird bei "define <name> BLEYC01 <device>:<reading>" aufgerufen.
#   Bei laufendem FHEM ($init_done=1): sofort initialisieren.
#   Beim Start ($init_done=0): NOTIFYDEV="global" setzen, damit
#   BLEYC01_Notify das INITIALIZED-Event empfängt und nachholt.
# ----------------------------------------------------------------------------
sub BLEYC01_Define {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    $hash->{FVERSION} = "98_BLEYC01.pm:v1.4.1";

    if(int(@param) != 3) {
        return "too few parameters: define <name> BLEYC01 <device>:<reading>";
    }

    $hash->{name}  = $param[0];
    $hash->{STATE} = "Initialized";

    if( $init_done ) {
      # FHEM läuft bereits: sofort Gerät und Notify registrieren
      BLEYC01_updateDevices($hash);
    } else {
      # FHEM-Start: globale Events abhören, bis INITIALIZED kommt
      $hash->{NOTIFYDEV} = "global";
    }

    return undef;
}

# ----------------------------------------------------------------------------
# BLEYC01_Undef
#   Wird beim Löschen des Geräts aufgerufen. Keine Ressourcen zu bereinigen.
# ----------------------------------------------------------------------------
sub BLEYC01_Undef {
    my ($hash, $arg) = @_;
    return;
}

# ----------------------------------------------------------------------------
# BLEYC01_Get
#   get <name> devices   → zeigt das registrierte Quellgerät (NOTIFYDEV)
# ----------------------------------------------------------------------------
sub BLEYC01_Get {
    my ($hash, $name, $opt, @args) = @_;

    if($opt eq "devices") {
      my @devices = devspec2array($hash->{NOTIFYDEV});
      return join("\n", @devices);
    } else {
      return "Unknown argument $opt, choose one of devices:noArg";
    }
}

# ----------------------------------------------------------------------------
# BLEYC01_Set
#   set <name> test <hex>   → Dekodierung mit Testwert
#   set <name> update       → Führt updateCmd-Attribut aus
# ----------------------------------------------------------------------------
sub BLEYC01_Set {
    my ($hash, $name, $cmd, @args) = @_;
    return "\"test $name\" needs at least one argument" unless(defined($cmd));

    if($cmd eq "test") {
      return "\"test $name $cmd\" needs at least one argument" unless(defined($args[0]));
      BLEYC01_update($hash, $args[0]);
      return undef;

    } elsif($cmd eq "update") {
      Log3 $name, 5, "$name: updateCmd -> " . $attr{$name}{updateCmd};
      if(!$attr{$name}{updateCmd} || $attr{$name}{updateCmd} eq "") {
        return "attr updateCmd is not set, please set attribute";
      }
      my $updateCommand = $attr{$name}{updateCmd};
      my $error = AnalyzeCommand(undef, $updateCommand);
      if($error ne "") {
        return "Command error: \"$error\" for $name";
      }
      return undef;

    } else {
      return "Unknown argument $cmd, choose one of test update";
    }
}

# ----------------------------------------------------------------------------
# BLEYC01_Attr
#   Validiert Attributwerte beim Setzen.
# ----------------------------------------------------------------------------
sub BLEYC01_Attr {
    my ($cmd, $name, $attr_name, $attr_value) = @_;
    if($cmd eq "set") {
      if($attr_name eq "disable") {
        if($attr_value !~ /^1|0$/) {
          my $err = "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
          Log3 $name, 3, "$name: " . $err;
          return $err;
        }
      } elsif($attr_name eq "updateCmd") {
        my $error = AnalyzeCommand(undef, $attr_value);
        if($error ne "") {
          return "Command error: \"$error\" for $name";
        }
      }
    }
    return;
}

# ----------------------------------------------------------------------------
# BLEYC01_Notify
#   Empfängt Events von:
#     a) "global" → INITIALIZED/REREADCFG: Initialisierung nach FHEM-Start
#     b) dem konfigurierten Quellgerät: Dekodierung des Sensor-Payloads
# ----------------------------------------------------------------------------
sub BLEYC01_Notify($$) {
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME};

  Log3 $ownName, 4, "$ownName: Event for $dev_hash->{NAME}";

  # --- Globale Events: INITIALIZED / REREADCFG ---
  # Nach dem FHEM-Start wird hier die verzögerte Initialisierung nachgeholt.
  if( $dev_hash->{NAME} eq "global" ) {
    my $events = deviceEvents($dev_hash, 1);
    if( grep { /^INITIALIZED$|^REREADCFG$/ } @{$events} ) {
      Log3 $ownName, 4, "$ownName: global INITIALIZED – registriere Notify";
      BLEYC01_updateDevices($own_hash);
    }
    return undef;
  }

  return if( !$init_done );
  return "" if( IsDisabled($ownName) );
  return if( $dev_hash->{TYPE} =~ /^BLEYC01/ );

  my $devName = $dev_hash->{NAME};
  my $events  = deviceEvents($dev_hash, 1);
  return if( !$events );

  Log3 $ownName, 5, "$ownName: EventObjekt -> " . Dumper($events);

  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));

    my @parts   = split(/: /, $event);
    my $reading = shift @parts;
    my $value   = join(": ", @parts);

    $reading = "" if(!defined($reading));
    $value   = "" if(!defined($value));

    # Wenn kein Reading-Name vorhanden, ist es ein state-Event
    if( $value eq "" ) {
      $reading = "state";
      $value   = $event;
    }

    # Nur das konfigurierte Reading verarbeiten
    next if( $reading ne $own_hash->{READING} );

    BLEYC01_update($own_hash, $value);
  }

  return undef;
}

# ----------------------------------------------------------------------------
# BLEYC01_DbLog_splitFn
#   Zerlegt FHEM-Events für DbLog in (Reading, Wert, Einheit).
# ----------------------------------------------------------------------------
sub BLEYC01_DbLog_splitFn($$) {
  my ($event, $device) = @_;
  my ($reading, $value, $unit);

  my @splited = split(/ /, $event);
  $reading = $splited[0];
  $reading =~ tr/://d;
  $value = $splited[1];
  $unit  = '';

  my %units = (
    Batterie  => '%',
    Chlor     => 'mg/l',
    EC        => 'µS/cm',
    ORP       => 'mV',
    PH        => 'pH',
    TDS       => 'ppm',
    Temperatur => '°C',
  );
  $unit = $units{$reading} // '';

  return ($reading, $value, $unit);
}


1;

=pod
=item device
=item summary Dekodiert Messwerte des BLE-YC01 Pool-Sensors aus einem MQTT-Reading
=item summary_DE Dekodiert Messwerte des BLE-YC01 Pool-Sensors aus einem MQTT-Reading
=begin html

<a name="BLEYC01"></a>
<h3>BLEYC01</h3>
<ul>
  <p>
    <b>BLEYC01</b> dekodiert die verschlüsselten Messwerte eines BLE-YC01 Pool-Sensors,
    der seinen HEX-Payload via Bluetooth/Tasmota an ein MQTT2-Gerät in FHEM liefert.
  </p>

  <a name="BLEYC01define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; BLEYC01 &lt;device&gt;:&lt;reading&gt;</code>
    <br><br>
    <ul>
      <li><b>device</b> &ndash; Name des FHEM-Geräts, das den HEX-Rohwert liefert</li>
      <li><b>reading</b> &ndash; Reading-Name des HEX-Payloads</li>
    </ul>
    <br>
    Beispiel:<br>
    <code>define myBLEYC01 BLEYC01 MQTT2_tasmota8:BLEOperation_read</code>
    <br><br>
    Nach dem FHEM-Start wird die Notify-Registrierung automatisch beim
    globalen <code>INITIALIZED</code>-Event nachgeholt.
  </ul>
  <br>

  <a name="BLEYC01set"></a>
  <b>Set</b>
  <ul>
    <li><b>test &lt;hex-string&gt;</b> &ndash; Testet die Dekodierung mit einem manuellen HEX-Wert</li>
    <li><b>update</b> &ndash; Führt den in Attribut <code>updateCmd</code> hinterlegten FHEM-Befehl aus</li>
  </ul>
  <br>

  <a name="BLEYC01get"></a>
  <b>Get</b>
  <ul>
    <li><b>devices</b> &ndash; Zeigt das aktuell registrierte Notify-Quellgerät</li>
  </ul>
  <br>

  <a name="BLEYC01attr"></a>
  <b>Attributes</b>
  <ul>
    <li><b>disable</b> 1|0 &ndash; Deaktiviert die Event-Verarbeitung</li>
    <li><b>updateCmd</b> &ndash; FHEM-Befehl für <code>set update</code></li>
    <li><b>PHMin / PHMax</b> &ndash; Grenzen pH-Wert (Standard: 7.0 / 7.4)</li>
    <li><b>ORPMin / ORPMax</b> &ndash; Grenzen ORP in mV (Standard: 650 / 750)</li>
    <li><b>ECMin / ECMax</b> &ndash; Grenzen EC in µS/cm (Standard: 250 / 2000)</li>
    <li><b>TDSMin / TDSMax</b> &ndash; Grenzen TDS in ppm (Standard: 250 / 2000)</li>
    <li><b>ChlorMin / ChlorMax</b> &ndash; Grenzen Chlor in mg/l (temperaturabhängig)</li>
  </ul>
  <br>

  <a name="BLEYC01readings"></a>
  <b>Readings</b>
  <ul>
    <li><b>Temperatur</b> &ndash; Wassertemperatur in °C</li>
    <li><b>PH / PH_OK</b> &ndash; pH-Wert und Normbereich-Status</li>
    <li><b>ORP / ORP_OK</b> &ndash; Redox-Potential in mV und Normbereich-Status</li>
    <li><b>EC / EC_OK</b> &ndash; Leitfähigkeit in µS/cm und Normbereich-Status</li>
    <li><b>TDS / TDS_OK</b> &ndash; Gelöste Feststoffe in ppm und Normbereich-Status</li>
    <li><b>Chlor / Chlor_OK</b> &ndash; Chlorgehalt in mg/l (NAN wenn kein Messwert)</li>
    <li><b>Batterie</b> &ndash; Batterieladung in %</li>
  </ul>
</ul>

=end html

=cut
