package utils;
use strict;
use warnings;
use Net::Telnet;
use Net::Ping;
use Readonly;

# TODO config file?
Readonly my $IFACE => 'wlp58s0';
Readonly my $PING_TIMEOUT => 5;
Readonly my $ROUTER => '10.0.0.138';
Readonly my $GOOGLEDNS => '8.8.8.8';

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

sub net_iface_up {
    my $if_file = "/sys/class/net/$IFACE/operstate";
    return unless -f $if_file;     

    my @state = read_file($if_file);
    return unless $state[0] eq 'up';
    return 1;
}
sub net_lan_up {
    return unless net_iface_up();

    my $ping = Net::Ping->new('icmp');
    return unless $ping->ping($ROUTER, $PING_TIMEOUT);
    return 1;
}
sub net_wan_up {
    return unless net_lan_up();

    my $ping = Net::Ping->new('icmp');
    return unless $ping->ping($GOOGLEDNS, $PING_TIMEOUT);
    return 1;
}


1;
