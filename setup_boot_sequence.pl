#!/usr/bin/perl


if ( $#ARGV != 1 ) {
    die "Usage: setup_boot_sequence.pl path to boot partition of new disk";
}

my $BOOT_PARTITION = $ARGV[0];
my $PLATFORM_BRANCH = $ARGV[1];

my $SD_BLOCK_DEVICE = "";

sub check_for_sd {
    if ( -e "/dev/mmcblk0" ) {
        $SD_BLOCK_DEVICE = "/dev/mmcblk0"
    } elsif (-e "/dev/mmcblk1" ) {
        $SD_BLOCK_DEVICE = "/dev/mmcblk1"
    } else {
        exit 1;
    }
}

sub trim {
    my ( $l ) = @_;

    $l =~ s/^\s*//;
    $l =~ s/\s*$//;

    return $l;
}

#
# Switch to the new disk, but with a readonly-memory overlay, the root pivot also happens in new
# init script
#
sub readonly_boot_line {
    my ( $part1, $part2 ) = @_;

    my @a = split(/\s+/, trim( $part2) );
    @a = grep {$_ ne "quiet" && $_ !~ "^root=" && $_ !~ "^init="} @a;
    push( @a, "root=${SD_BLOCK_DEVICE}p1" );
    push( @a, "init=/sbin/overlayRoot.sh" );
    push( @a, "sbtsroot=$BOOT_PARTITION" );

    my $b = join( ',', @a );
    return $part1 ."APPEND " . join( " ", @a);
}

#
# Simply change the boot device to the SSD, gets mounted normally, i.e. read-write
#
sub readwrite_boot_line {
    my ( $part1, $part2 ) = @_;

    my @a = split(/\s+/, trim( $part2) );
    @a = grep {$_ ne "quiet" && $_ !~ "^init="} @a;
    push( @a, "sbtsroot=$BOOT_PARTITION" );

    my $b = join( ',', @a );
    return $part1 ."APPEND " . join( " ", @a);
}

sub create_readonly_conf {
    my ( $l ) = @_;

    open( my $out, ">", "/boot/extlinux/readonly_extlinux.conf" ) || die "Can't create file /boot/extlinux/readonly_extlinux.conf: $!\n";

    #if ( $PLATFORM_BRANCH ne "sbts-jetson-nano" ) {
    if ( 0 ) {
        $l =~ s%^(\s*)(INITRD.*)$%$1#$2\n$1INITRD /boot/initrd-xusb.img%gm;
    }
    my $readonly = $l;

    $readonly =~ s%^(\s*)APPEND(.*)$%readonly_boot_line($1, $2)%gem;

    print $out $readonly;

    close $out;

    system("cat /boot/extlinux/readonly_extlinux.conf");
}

sub create_readwrite_conf {
    my ( $l ) = @_;

    open( my $out, ">", "/boot/extlinux/readwrite_extlinux.conf" ) || die "Can't create file /boot/extlinux/readonly_extlinux.conf: $!\n";

    #if ( $PLATFORM_BRANCH ne "sbts-jetson-nano" ) {
    if ( 0 ) {
        $l =~ s%^(\s*)(INITRD.*)$%$1#$2\n$1INITRD /boot/initrd-xusb.img%gm;
    }
    my $readonly = $l;

    $readonly =~ s%^(\s*)APPEND(.*)$%readwrite_boot_line($1, $2)%gem;

    print $out $readonly;

    close $out;

    system("cat /boot/extlinux/readwrite_extlinux.conf");
}

my $CONF_FILE = "/boot/extlinux/orig_extlinux.conf";

system( "cp /boot/extlinux/extlinux.conf /boot/extlinux/orig_extlinux.conf" );

open( my $in, "<", $CONF_FILE ) || die "Can't open $CONF_FILE: $!\n";
$l = do { local $/;<$in> };
#if ( $PLATFORM_BRANCH ne "sbts-jetson-nano" ) {
if ( 0 ) {
    $l =~ s%^(\s*)(INITRD.*)$%$1#$2\n$1INITRD /boot/initrd-xusb.img%gm;
}
close( $in );

create_readonly_conf( $l );
create_readwrite_conf( $l );
