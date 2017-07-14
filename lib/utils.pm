package utils;
use strict;
use warnings;
use Net::Telnet;
use Net::Ping;
use Readonly;
use FindBin;
use vars qw|$IFACE $PING_TIMEOUT $WAN_PING_TARGET|;

BEGIN {
    # parse config
    my $conf = $FindBin::Bin . '/conf/runchecks.conf';
    return unless -f $conf;

    open F, '<', $conf or die $!;
    my @cont = <F>;
    chomp @cont;
    close F;

    # add more config sections here,
    # and in XXX below
    my $global = 0;

    for my $line (@cont) {
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;

        # fix up line for easier processing
        $line =~ s/\s//g;
        $line = lc $line;

        if ($line eq '[global]') {
            $global++;
            next;
        }

        # XXX future use
        # if ($line eq '[conf_section]') {
        #   $global = 0;
        #   ...
        # }

        if ($global) {
            my ($key, $val) = split /=/, $line;
            $key eq 'interface'         and do { $IFACE = $val };
            $key eq 'ping_timeout'      and do { $PING_TIMEOUT = $val };
            $key eq 'wan_ping_target'   and do { $WAN_PING_TARGET = $val };
        }

        # XXX future use
        # if ($conf_section) {
        #   ...
        # }
    }
}

# DEFAULTS (see config file)
Readonly my %DEFAULTS => (
    iface => 'eth0',
    ping_timeout => 5,
    wan_ping_target => '8.8.8.8',
);

$IFACE           ||= $DEFAULTS{iface};
$PING_TIMEOUT    ||= $DEFAULTS{ping_timeout};
$WAN_PING_TARGET   = valid_ip($WAN_PING_TARGET) ? $WAN_PING_TARGET : $DEFAULTS{wan_ping_target};


#
# Subs

sub read_file {
    my $file = shift;

    open F, '<', $file or die "Could not open file '$file', $!";
    my @content = <F>;
    close F;

    chomp @content;
    return @content;
}

sub write_file {
    my ($file, @lines) = @_;

    open F, '>', $file or die "Could not open file '$file', $!";
    print F "$_\n" for @lines;
    close F;

    1;
}

sub create_file {
    my $file = shift;

    return if -f $file;

    open F, '>', $file or die "Could not create file '$file', $!";
    close F;

    1;
}

sub get_telnet {
    my $family = shift;

    # accept 4/ipv4, 6/ipv6
    if ($family and $family =~ /^\d$/) {
        $family = 'ipv4' if $family == 4;
        $family = 'ipv6' if $family == 6;
    }
    $family ||= 'ipv4';

    die "Invalid IP family input: '$family'"
        unless $family eq 'ipv4' or $family eq 'ipv6';

    my $t = Net::Telnet->new(Timeout=>10, Errmode=>'die', Family=>$family);

    return $t;
}

sub get_time_seconds {
    my $val = shift;

    # make sure we die if nothing is passed
    die "Impossible time given: 'null'"
        unless defined $val and length $val;

    return $val if $val =~ /^\d+$/; # only numbers, means seconds

    die "Impossible time given: '$val'"
        unless $val =~ /^\d+[s,m,h,d]{1}$/; # accept only seconds, minutes, hours, days

    my ($num, $unit) = $val =~ /^(\d+)([s,m,h,d]{1})$/;

    return $unit eq 's' ? $num
        :  $unit eq 'm' ? $num * 60
        :  $unit eq 'h' ? $num * 60 * 60
        :  $num * 24 * 60 * 60; # days
}

my %MONTHS = (
    Jan=>1, Feb=>2, Mar=>3, Apr=>4,  May=>5,  Jun=>6,
    Jul=>7, Aug=>8, Sep=>9, Oct=>10, Nov=>11, Dec=>12,
);

sub month_to_num {
    my $month = shift;

    defined $MONTHS{$month}
        or die "Invalid month '$month'";

    return sprintf '%02d', $MONTHS{$month};
}
sub num_to_month {
    my $num = shift;

    my %months;
    @months{values %MONTHS} = keys %MONTHS;

    defined $months{$num}
        or die "Invalid month number '$num'";

    return $months{$num};
}

sub valid_ip {
    my $ip = shift;
    return unless
        $ip and $ip =~ /^\d{1,3}(\.\d{1,3}){3}$/;

    return 1;
}

sub get_gw {
    my @gw_cmd_out = qx(ip route show default dev $IFACE scope global);
    # NIC is up by now, but routing may not be setup make sure to timeout ping if this is so.
    # We check gw on every run so this will rectify itself in due time..
    return '1.0.0.0' unless @gw_cmd_out;

    my ($gw_line) = @gw_cmd_out > 1
        ? grep /^default/, @gw_cmd_out : $gw_cmd_out[0];

    # default via 10.0.0.138  src 10.0.0.3  metric 322
    my ($gw) = $gw_line =~ /default\s+via\s+(\d+\.\d+\.\d+\.\d+)\s+/;

    return $gw;
}

sub net_iface_up {
    my $if_file = "/sys/class/net/$IFACE/operstate";
    return unless -f $if_file;     

    my @state = read_file($if_file);
    return unless $state[0] eq 'up';
    return 1;
}
sub net_lan_up {
    return unless net_iface_up();

    my $local_gw = get_gw();

    my $ping = Net::Ping->new('icmp');
    return unless $ping->ping($local_gw, $PING_TIMEOUT);
    return 1;
}
sub net_wan_up {
    return unless net_lan_up();

    my $ping = Net::Ping->new('icmp');
    return unless $ping->ping($WAN_PING_TARGET, $PING_TIMEOUT);
    return 1;
}


1;
