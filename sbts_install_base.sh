#!/bin/bash

UPDATED=

disk_list=()

abort() {
    echo $* >&2
    echo "Aborting..."
    exit 1
}

HERE=$(dirname $0)
cd $HERE || abort "Can't change to script directory"
HERE=`/bin/pwd`

sanity_check() {
    if [ -e "/tmp/mnt" ] ; then
        abort "Please remove /tmp/mnt and re-run this script"
    fi

    if [ -e /boot/extlinux/orig_extlinux.conf ] ; then
        cat <<EOF
There already exists an orig_extlinux.conf file in /boot/extlinux. Please makesure that /boot/extlinux/extlinux.conf contains
the original distribution file and remove the one called /boot/extlinux/orig_extlinux.conf and re-run this script
EOF

    exit 1
    fi
}

update_pkg_registry() {
    if [ ! "$UPDATED" ] ; then
        echo Updating the package registry
        apt update
        UPDATED=1
    fi
}

ensure_pyparted_is_present() {
    if ! python3 -c 'import parted' ; then
        update_pkg_registry

        echo Installing python3-parted
        apt install -y python3-parted
    fi
}

choose_disk() {
    for disk in /dev/nvme0n1 /dev/sda ; do
        if [ -e "$disk" ] ; then
            disk_list+=( "$disk" )
        fi
    done
    disk_list+=( "Quit" )

    PS3='Choose the SSD disk device: '
    options=("Option 1" "Option 2" "Option 3" "Quit")
    select opt in "${disk_list[@]}"
    do
        if [ -n "$opt" ] ; then
            if [ "$REPLY" == "${#disk_list[@]}" ] ; then
                echo "Aborting..."
                exit 1
            fi

            disk_device_path="$opt"
            return
        fi
    done
}

create_partitions() {
    echo "Creating disk partitions for $disk_device_path"

    echo ""

    [ ! -e /etc/udev/disabled ] && mkdir /etc/udev/disabled
    grep -l 'RUN.*/usr/bin/systemd-mount' /etc/udev/rules.d/* |xargs -n1 -i mv '{}' /etc/udev/disabled
    udevadm control --reload

    ls -1 ${disk_device_path}?* | xargs -n1 findmnt -n| awk '{print $1}' | xargs -n1 umount
    if ! $HERE/make_partitions.py "$disk_device_path" ; then
        abort "Failed to create partitions on $disk_device_path"
    fi


    echo ""
    echo "Created partitions are:"
    echo ""

    fdisk -l "$disk_device_path"
}

determine_partition_base() {
    if [ "$disk_device_path" == "/dev/nvme0n1" ] ; then
        partition_base_path="/dev/nvme0n1p"
    else
        partition_base_path="$disk_device_path"
    fi
}

create_file_systems() {
    echo "Creating file systems"
    echo ""

    echo partition_base_path = $partition_base_path
    for partition_path in ${partition_base_path}?* ; do
        echo "mkfs -t ext4 $partition_path"
        echo ""
        if ! mkfs -t ext4 "$partition_path" ; then
            echo "Failed to create file system on $partition_path, aborting..."
            exit 1
        fi
    done
}

label_partitions() {
    echo "Labelling the partitions"

    if [ "$disk_device_path" == "/dev/nvme0n1" ] ; then
        partition_base_path="/dev/nvme0n1p"
    else
        partition_base_path="/dev/sda"
    fi

    echo "Labeling the partitions"
    echo ""

    e2label "$partition_base_path"1 SbtsRoot
    e2label "$partition_base_path"2 SbtsConfig
    e2label "$partition_base_path"3 SbtsDisk
}


#
# This hook is needed to copy the firmware needed to mount a USB SSD during boot time
#
create_usb_firmware_hook() {
    #
    # USB disk driver in the boot image
    #
    echo "Create usb-firmware hook"
    echo ""

    cat > usb-firmware <<EOF
if [ "\$1" = "prereqs" ]; then exit 0; fi

. /usr/share/initramfs-tools/hook-functions

EOF
    for ware in /lib/firmware/tegra*_xusb_firmware ; do
        echo "copy_file firmware $ware"
    done >> usb-firmware

    cat >> usb-firmware <<EOF

exit 0
EOF

    chmod +x /usr/share/initramfs-tools/hooks/usb-firmware

    echo "Created usb-firmware hook as follows:"
    echo ""
    cat /usr/share/initramfs-tools/hooks/usb-firmware
    echo ""

}

create_fsck_binaries_copy_hook() {
    #
    # Copy the fsck binaries
    #
    echo "Create copy fsck binaries to the disk image hook"
    echo ""

    cat > fsck-binaries <<EOF
if [ "\$1" = "prereqs" ]; then exit 0; fi

. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/e2fsck /sbin

copy_file binary /sbin/fsck.ext4

exit 0
EOF

    chmod +x /usr/share/initramfs-tools/hooks/fsck-binaries

    echo "Created fsck copy hook as follows:"
    echo ""
    cat /usr/share/initramfs-tools/hooks/fsck-binaries
    echo ""

}

create_fsck_disk_repair_premount_hook() {
    #
    # Setup the fsck pre-mount
    #
    echo "Create the fsck pre-mount disk repair hook"
    echo ""

    cd /usr/share/initramfs-tools/scripts/local-premount || abort "Can't cd to /usr/share/initramfs-tools/scripts/local-premount"
    cat > fsck_repair_partitions <<EOF
#!/bin/sh
# initramfs local-premount script for repairing any broken partitions

PREREQ=""

# Output pre-requisites
prereqs()
{
        echo "\$PREREQ"
}

case "\$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Repair any damaged partitions with fsck -y

echo Repair any damaged partitions
fsck -y ${partition_base_path}1
fsck -y ${partition_base_path}2
fsck -y ${partition_base_path}3

# Don't let any failures stop the boot

exit 0
EOF

    chmod +x /usr/share/initramfs-tools/scripts/local-premount/fsck_repair_partitions

    echo "Created disk repair pre-mount hook as follows:"
    echo ""
    cat /usr/share/initramfs-tools/scripts/local-premount/fsck_repair_partitions
    echo ""

}

copy_overlay_init() {
    perl -pi -e "s%^rootDev=.*%rootDev=${partition_base_path}1%" "$HERE/overlayRoot.sh" || abort "Can't change the boot device in overlayRoot.sh"
    cp "$HERE/overlayRoot.sh" /sbin || abort "Can't copy $HERE/overlayRoot.sh to /sbin"
    chmod 755 /sbin/overlayRoot.sh || abort "Can't change permissions of /sbin/overlayRoot.sh"

    # Change /sbin/init link
    cd /sbin || abort "Can't change directory to /sbin"
    rm init || abort "Can't remove link /sbin/init"
    ln -s overlayRoot.sh init || abort "Can't link overlayRoot.sh to init"
    cd "$HERE" || abort "Can't change directory to $HERE"

}

setup_boot_sequence() {
    $HERE/setup_boot_sequence.pl "${partition_base_path}1" "$PLATFORM_BRANCH" || abort "Can't setup the boot sequence"
}

determine_platform_branch() {
    PLATFORM_LABEL=$(cat /proc/device-tree/model | tr '\0' '\n' ; echo '')
    PLATFORM_BRANCH=""
    case "$PLATFORM_LABEL" in
        "NVIDIA Jetson Nano Developer Kit")
            PLATFORM_BRANCH=sbts-jetson-nano
            nvpmodel -m 0
	    jetson_clocks
            ;;
        "NVIDIA Jetson Xavier NX Developer Kit")
            PLATFORM_BRANCH=sbts-jetson-xavier-nx
            nvpmodel -m 2
	    jetson_clocks --fan
            ;;
        "Jetson-AGX")
            PLATFORM_BRANCH=sbts-jetson-xavier-agx
            nvpmodel -m 0
	    jetson_clocks --fan
            ;;
        *)
            abort "Cannot determine the platform type to build darknet for"
            ;;
    esac
}

create_initramfs() {
    echo "Create initial ramfs"
    echo ""

    cd /usr/share/initramfs-tools/hooks || abort "Can't cd to /usr/share/initramfs-tools/hooks"

    create_usb_firmware_hook

    create_fsck_binaries_copy_hook

    create_fsck_disk_repair_premount_hook

    echo "Setup is finished, now create the initial ram disk"
    echo ""
    echo mkinitramfs -o /boot/initrd-xusb.img
    mkinitramfs -o /boot/initrd-xusb.img

    if [ ! -e /boot/initrd-xusb.img -o -z /boot/initrd-xusb.img ] ; then
        abort "Failed to create the initial ram disk properly"
    fi

    # Change back to starting place
    cd $HERE || abort "Can't change to script directory"
}

setup_sbts_bin() {
    # Change back to starting place
    cd $HERE || abort "Can't change to script directory"

    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    SBTS_BIN="$SUDO_USER_HOME/sbts-bin"
    SBTS_SBIN="/usr/local/sbts-sbin"

    [[ -d "$SBTS_BIN" ]] || mkdir "$SBTS_BIN" || abort "Can't create $SBTS_BIN directory"

    for b in make_readonly.sh make_readwrite.sh make_orig.sh ; do
        rm -f "$SBTS_BIN/$b" > /dev/null 2>&1
    done

    # Set boot mode scripts
    cp "$HERE/make_readonly.sh" "$SBTS_BIN/make_readonly.sh" || abort "Can't copy make_readonly.sh to $SBTS_BIN"
    ln "$SBTS_BIN/make_readonly.sh" "$SBTS_BIN/make_readwrite.sh" || abort "Can't link $SBTS_BIN/make_readonly.sh to $SBTS_BIN/make_readwrite.sh"
    ln "$SBTS_BIN/make_readonly.sh" "$SBTS_BIN/make_orig.sh" || abort "Can't link $SBTS_BIN/make_readonly.sh to $SBTS_BIN/make_orig.sh"

    # Create sbts sbin directory for setuid re-mount code
    [[ -d "$SBTS_SBIN" ]] || mkdir "$SBTS_SBIN" || abort "Can't create $SBTS_SBIN"
    chown root:root "$SBTS_SBIN" || abort "Can't chown root:root $SBTS_SBIN"
    chmod 755 "$SBTS_SBIN" || abort "Can't chmod 755 $SBTS_SBIN"

    # Re-mount scripts
    gcc mount_readonly.c -o mount_readonly
    gcc mount_readwrite.c -o mount_readwrite

    # Move to /usr/local
    mv mount_readonly "$SBTS_SBIN" || abort "Can't mv mount_readonly to $SBTS_SBIN"
    mv mount_readwrite "$SBTS_SBIN" || abort "Can't mv mount_readwrite to $SBTS_SBIN"

    # Set correct executable permissions
    chmod 755 "$SBTS_SBIN/mount_readonly" "$SBTS_SBIN/mount_readwrite" || abort "Can't change permissions on $SBTS_SBIN/mount_readonly and $SBTS_SBIN/mount_readwrite"

    # Set root setuid on re-mount commands
    chown root:root "$SBTS_SBIN/mount_readonly" "$SBTS_SBIN/mount_readwrite" || abort "Can't change owner on $SBTS_SBIN/mount_readonly and $SBTS_SBIN/mount_readwrite"
    chmod +s "$SBTS_SBIN/mount_readonly" "$SBTS_SBIN/mount_readwrite" || abort "Can't set +s on $SBTS_SBIN/mount_readonly and $SBTS_SBIN/mount_readwrite"

    # Link to the local location

    ln -s "$SBTS_SBIN/mount_readonly" "$SBTS_BIN/mount_readonly" || abort "Can't link $SBTS_SBIN/mount_readonly to $SBTS_BIN/mount_readonly"
    ln -s "$SBTS_SBIN/mount_readwrite" "$SBTS_BIN/mount_readwrite" || abort "Can't link $SBTS_SBIN/mount_readwrite to $SBTS_BIN/mount_readwrite"

    # Set correct permissions and ownership on make* scripts
    chmod 755 "$SBTS_BIN/make_readonly.sh" || abort "Can't change permissions on $SBTS_BIN/make_readonly.sh"
    chown "$SUDO_USER:$SUDO_USER" "$SBTS_BIN" "$SBTS_BIN/make_readonly.sh"


    # Now setup the configuration mounting
}

copy_system_disk_to_SSD() {
    if [ -e "/tmp/mnt" ] ; then
        echo "/tmp/mnt already exists, aborting"
    fi

    echo "Mount the new destination disk"
    echo ""

    mkdir /tmp/mnt || abort "Can't create /tmp/mnt"
    mount "$partition_base_path"1 /tmp/mnt || abort "Can't mount ${partition_base_path}1 on /tmp/mnt"

    cd / || abort "Can't change to /"

    echo "Copying original system disk to new SSD location"
    echo ""

    rsync -axHAWX --numeric-ids --info=progress2 --exclude=/proc --exclude=/tmp/mnt / /tmp/mnt || abort "Failed to copy original system to SSD"
}

update_fstab() {
    cat > /tmp/mnt/etc/fstab <<EOF
# <file system> <mount point>             <type>          <options>                               <dump> <pass>
LABEL=SbtsConfig     /home/sbts/config     ext4           noatime                                     0 2
LABEL=SbtsDisk       /home/sbts/disk       ext4           noatime                                     0 2
#the original root mount has been removed by overlayRoot.sh
#this is only a temporary modification, the original fstab
#stored on the disk can be found in /ro/etc/fstab
EOF
    if [ $? -ne 0 ] ; then
	abort "Could not create new fstab"
    fi

    perl -pi -e "s%/home/sbts/%$SUDO_USER_HOME/%" /tmp/mnt/etc/fstab || abort "Can't update fstab to the before sudo user"
}

unmount_system_disk() {
    echo "Umounting new system disk"
    echo ""

    umount /tmp/mnt || abort "Failed to unmount /tmp/mnt"
    rmdir /tmp/mnt || abort "Failed to remove mount point /tmp/mnt"
}

make_readonly() {
    "$SBTS_BIN/make_readonly.sh"

    echo ""
    echo "Please reboot"
}

disable_docker() {
    echo "Disable docker"
    echo ""

    systemctl stop docker
    systemctl disable docker
}

#
# Main
#

if [ "$(id -n -u)" != "root" ] ; then
    abort "You need to execute this script as root"
fi

if [ ! "$SUDO_USER" -o "$SUDO_USER" == "root" ] ; then
    abort "Please execute this script simply as sudo $(basename $0)"
fi

sanity_check

ensure_pyparted_is_present

choose_disk

create_partitions

determine_partition_base

create_file_systems

label_partitions

determine_platform_branch

#if [ "$PLATFORM_BRANCH" != "sbts-jetson-nano" ] ;then
if false ; then
    create_initramfs
fi

copy_overlay_init

setup_boot_sequence

setup_sbts_bin

copy_system_disk_to_SSD

update_fstab

disable_docker

unmount_system_disk

make_readonly
