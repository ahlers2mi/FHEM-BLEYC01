package main;

use strict;
use warnings;

use Data::Dumper;

use vars qw($init_done);

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
#    $hash->{NOTIFYDEV}  = AttrVal($hash->{name}, "notifyDev", "forwardRemote");

}

sub BLEYC01_setNotifyDev($) {
  my ($hash) = @_;

  if( $hash->{DEVICE} ) {
    $hash->{NOTIFYDEV} = $hash->{DEVICE};
    notifyRegexpChanged($hash,$hash->{DEVICE});
  } else {
    $hash->{NOTIFYDEV} = "";
    notifyRegexpChanged($hash,'');
  }
}

sub BLEYC01_update($$){

  my ($hash,$value) = @_;
  my $name = $hash->{NAME};

  my $DEVICE = $hash->{DEVICE};
  return if( !$DEVICE );
  my $READING = $hash->{READING};
	

  if( !$value ){
    Log3 $name, 4, "$name: ($READING) empty value";
    return;
  }

  if( length($value) < 5 ){
    Log3 $name, 2, "$name: ($READING) reading is to short";
    return;
  }

  # 1. HEX-String in Byte-Array wandeln
my @message = map { hex($_) } ($value =~ /../g);

# 2. DEKODIERUNG wie im C++-Snippet
for (my $i = scalar(@message) - 1; $i > 0; $i--) {
    my $tmp = $message[$i];
    my $hibit1 = ($tmp & 0x55) << 1;
    my $lobit1 = ($tmp & 0xAA) >> 1;

    my $tmp_prev = $message[$i-1];
    my $hibit = ($tmp_prev & 0x55) << 1;
    my $lobit = ($tmp_prev & 0xAA) >> 1;

    $message[$i] = ~( $hibit1 | $lobit ) & 0xFF;
    $message[$i-1] = ~( $hibit | $lobit1 ) & 0xFF;
}

# 3. Extrahieren der Werte (entsprechend C++-Mapping)
my $temp    = (($message[13]<<8) + $message[14]) / 10.0;     # °C
my $ph      = (($message[3] <<8) + $message[4]) / 100.0;
my $orp     = (($message[20]<<8) + $message[21]);
my $battery = (($message[15]<<8) + $message[16]) / 31.9;
my $ec      = (($message[5] <<8) + $message[6]);
my $tds     = (($message[7] <<8) + $message[8]);
my $chlor   = (($message[11]<<8) + $message[12]) / 10.0;

$battery = sprintf("%.2f", $battery);

  readingsBeginUpdate($hash);

  # 4. Readings setzen und ausgeben
  #print "Temperatur: $temp °C\n";
readingsBulkUpdate($hash, "Temperatur", $temp );

#print "PH: $ph\n";
readingsBulkUpdate($hash, "PH", $ph );
if ($ph >= AttrVal($name,"PHMin",7.0) && ($ph <= AttrVal($name,"PHMax",7.4))){
  readingsBulkUpdate($hash, "PH_OK", "true" );
}else{
  readingsBulkUpdate($hash, "PH_OK", "false" );
}

#print "ORP: $orp\n";
readingsBulkUpdate($hash, "ORP", $orp );
if ($orp >= AttrVal($name,"ORPMin",650) && ($orp <= AttrVal($name,"ORPMax",750))){
  readingsBulkUpdate($hash, "ORP_OK", "true" );
}else{
  readingsBulkUpdate($hash, "ORP_OK", "false" );
}

#print "Batterie: $battery %\n";
readingsBulkUpdate($hash, "Batterie", $battery );

#print "Leitfähigkeit: $ec µs/cm\n";
readingsBulkUpdate($hash, "EC", $ec );
if ($ec >= AttrVal($name,"ECMin",250) && ($ec <= AttrVal($name,"ECMax",2000))){
  readingsBulkUpdate($hash, "EC_OK", "true" );
}else{
  readingsBulkUpdate($hash, "EC_OK", "false" );
}


#print "TDS: $tds ppm\n";
readingsBulkUpdate($hash, "TDS", $tds );
if ($tds >= AttrVal($name,"TDSMin",250) && ($tds <= AttrVal($name,"TDSMax",2000))){
  readingsBulkUpdate($hash, "TDS_OK", "true" );
}else{
  readingsBulkUpdate($hash, "TDS_OK", "false" );
}


#print "Chlor: $chlor mg\l";

  if ($chlor == 6553.5){
    readingsBulkUpdate($hash, "Chlor", "NAN" );
    readingsBulkUpdate($hash, "Chlor_OK", "NAN" );
  }else{
    readingsBulkUpdate($hash, "Chlor", $chlor );
    if ($temp > 30){
      if ($chlor >= AttrVal($name,"ChlorMin", 1.2) && ($chlor <= AttrVal($name,"ChlorMax",2.0))){
        readingsBulkUpdate($hash, "Chlor_OK", "true" );
      }else{
        readingsBulkUpdate($hash, "Chlor_OK", "false" );
      }
    }else{
      if ($chlor >= AttrVal($name,"ChlorMin", 0.5) && ($chlor <= AttrVal($name,"ChlorMax",1.0))){
        readingsBulkUpdate($hash, "Chlor_OK", "true" );
      }else{
        readingsBulkUpdate($hash, "Chlor_OK", "false" );
      }
    }
  }

  readingsEndUpdate($hash, 1);

}

sub BLEYC01_updateDevices($) {
  my ($hash) = @_;

  my %list;

  delete $hash->{DEVICE};
  delete  $hash->{READING};

  my @params = split(" ", $hash->{DEF});
  while (@params) {
    my $param = shift(@params);

    my @device = split(":", $param);

    if( defined($defs{$device[0]}) ) {
      $list{$device[0]} = 1;
      $hash->{DEVICE} = $device[0];
      $hash->{READING} = $device[1];

      $hash->{READING} = "state" if( !$hash->{READING} );
    }
  }

  InternalTimer(gettimeofday(), "BLEYC01_setNotifyDev", $hash);
  $hash->{CONTENT} = \%list;

  BLEYC01_update($hash, undef);
}


sub BLEYC01_Define {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    $hash->{FVERSION} = "98_BLEYC01.pm:v1.4.0";

    if(int(@param) != 3) {
        return "too few parameters: define <name> BLEYC01 <device>:<reading>";
    }

    $hash->{name}  = $param[0];

    $hash->{STATE} = "Initialized";

    if( $init_done ) {
      BLEYC01_updateDevices($hash);
    } else {
      # Während Startup: auf INITIALIZED warten
      $hash->{NOTIFYDEV} = "global";
    }

    return undef;
}

sub BLEYC01_Undef {
    my ($hash, $arg) = @_;
    # nothing to do
    return ;
}

sub BLEYC01_Get {
        my ( $hash, $name, $opt, @args ) = @_;

        if($opt eq "devices") {
          my @devices = devspec2array($hash->{NOTIFYDEV});
          return join("\n", @devices);
        } else {
          return "Unknown argument $opt, choose one of devices:noArg";
        }

}

sub BLEYC01_Set {
        my ( $hash, $name, $cmd, @args ) = @_;
        return "\"test $name\" needs at least one argument" unless(defined($cmd));

        if($cmd eq "test")
        {
          return "\"test $name $cmd\" needs at least one argument" unless(defined($args[0]));

          BLEYC01_update($hash, $args[0]);

          return undef;

        }elsif($cmd eq "update"){
          Log3 $name, 5, "$name: updateCmd -> " . $attr{$name}{updateCmd};
	  if($attr{$name}{updateCmd} eq ""){
            return "attr updateCmd is not set, please set attribute";
          }
          my $updateCommand = $attr{$name}{updateCmd};
          my $error = AnalyzeCommand(undef, $updateCommand); 
          if ($error ne ""){              
	    return "Command error: \"$error\" for $name";
          }
          return undef;
        }else{
          return "Unknown argument $cmd, choose one of test update";
        }
}


sub BLEYC01_Attr {
        my ($cmd,$name,$attr_name,$attr_value) = @_;
        if($cmd eq "set") {
          if($attr_name eq "disable") {
            if($attr_value !~ /^1|0$/) {
              my $err = "Invalid argument $attr_value to $attr_name. Must be 0 or 1.";
              Log3 $name, 3, "$name: ".$err;
              return $err;
            }
          }elsif($attr_name eq "updateCmd") {
            my $error = AnalyzeCommand(undef, $attr_value); 
	    if ($error ne ""){              
	      return "Command error: \"$error\" for $name";
	    }

	  #          }elsif($attr_name eq "verbose") {
	  #          } else {
	  #            return "Unknown attr $attr_name for $name";
          }
        }
      return ;
}

sub BLEYC01_Notify($$) {
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME};

  # Globale INITIALIZED / REREADCFG Events abfangen
  if( $dev_hash->{NAME} eq "global" ) {
    my $events = deviceEvents($dev_hash, 1);
    if( grep { /^INITIALIZED$|^REREADCFG$/ } @{$events} ) {
      BLEYC01_updateDevices($own_hash);
    }
    return undef;
  }

  Log3 $ownName, 4, "$ownName: Event for $dev_hash->{NAME}";

  return if( !$init_done );

  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
#  Log 3, $ownName . ": Test1";

  return if( $dev_hash->{TYPE} =~ /^BLEYC01/ );
#  Log 3, $ownName . ": Test2";

  my $devName = $dev_hash->{NAME}; # Device that created the events

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  Log3 $ownName, 5, "$ownName: EventObjekt -> " . Dumper($events);

  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));

    my @parts = split(/: /,$event);
    my $reading = shift @parts;
    my $value   = join(": ", @parts);

    $reading = "" if( !defined($reading) );
    $value = "" if( !defined($value) );
    if( $value eq "" ) {
      $reading = "state";
      $value = $event;
    }
         next if( $reading ne $own_hash->{READING} );

    BLEYC01_update($own_hash, $value);
  }
  
  return undef;
}

#####################################
#
#      DbLog event interpretation
#
sub BLEYC01_DbLog_splitFn($$)
{
	my ($event, $device) = @_;
	my ($reading, $value, $unit);

        my @splited = split(/ /,$event);

        $reading = $splited[0];;
        $reading =~ tr/://d;

	$value = $splited[1];
       	$unit = '';

        if ($reading eq "Batterie"){
	   $unit = '%';
	}elsif ($reading eq "Chlor"){
	   $unit = 'mg/l';
	}elsif ($reading eq "EC"){
	   $unit = 'mV';
	}elsif ($reading eq "ORP"){
	   $unit = 'mV';
	}elsif ($reading eq "PH"){
	   $unit = 'pH';
	}elsif ($reading eq "TDS"){
	   $unit = 'ppm';
	}elsif ($reading eq "Temperatur"){
	   $unit = '°C';
        }
        
        return ($reading, $value, $unit);
}


1;

=pod
=begin html

<a name="BLEYC01"></a>
<h3>BLEYC01</h3>
<ul>
    <i>BLEYC01</i> implements a decoding Device of Readings from a BLE-YC01 Pool Sensor
    <br><br>
    <a name="BLEYC01define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; BLEYC01 &lt;device&gt;:&lt;reading&gt;</code><br>
        <br><br>
        Example: <code>define myBLEYC01 BLEYC01 MQTT2_BLEYC01:BLEOperation_read</code>
        <br><br>
    </ul>
    <br>

    <a name="BLEYC01_Set"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i> any value to any of the following options. They're just there to
        <i>get</i> them. See <a href="http://fhem.de/commandref.html#set">commandref#set</a>
        for more info about the set command.
        <br><br>
        Options:
        <ul>
              <li><i>test</i><br>
                  try a Test value</li>
        </ul>
    </ul>
    <br>

    <a name="BLEYC01_Get"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>devices</i><br>
                  test your definition, it lists the device of notification</li>
        </ul>
    </ul>
    <br>

    <a name="BLEYC01_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>disable<br>
        1 -> disable notify processing. Notice: this also disables rename and delete handling.</li>
      <li>verbose<br></li>
    </ul><br>

</ul>

=end html

=cut
