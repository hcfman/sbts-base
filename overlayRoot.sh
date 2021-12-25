#!/bin/sh

# Copyright (c) 2021 Kim Hendrikse
# Inspired by and based in part on this work http://wiki.psuter.ch/doku.php?id=solve_raspbian_sd_card_corruption_issues_with_read-only_mounted_root_partition

#
# Jetson Xavier AGX version
#

fail(){
	echo -e "$1"
	exec /bin/bash
}
 
found_root=$(perl -n -e 'print $1, "\n" if m%^\s*APPEND .*\broot=(\S+)%' /boot/extlinux/extlinux.conf)
found_init=$(perl -n -e 'print $1, "\n" if m%^\s*APPEND .*\binit=(\S+)%' /boot/extlinux/extlinux.conf)
found_sbtsroot=$(perl -n -e 'print $1, "\n" if m%^\s*APPEND .*\bsbtsroot=(\S+)%' /boot/extlinux/extlinux.conf)

if [ "$found_init" != "/sbin/overlayRoot.sh" -a -z "$found_sbtsroot" ] ; then
    exec /lib/systemd/systemd
fi

# Mount useful device directories
[ ! -d /proc ] && mkdir /proc
if [ ! -e /proc/cpuinfo ] ; then
    mount -t proc proc /proc
fi

[ ! -d /sys ] && mkdir /sys
if [ ! -e /sys/fs ] ; then
    mount -t sysfs sysfs /sysfs
fi

if [ "$found_init" != "/sbin/overlayRoot.sh" -a ! -z "$found_sbtsroot" ] ; then
    mkdir /mnt/newroot || fail "Can't create /mnt/newroot"

    mount $found_sbtsroot /mnt/newroot || fail "Can't mount $found_sbtsroot on /mnt"

    cd /mnt/newroot || fail "Can't change to /mnt/newroot"
    pivot_root . mnt
    exec chroot . sh -c "$(cat <<END
    mount --move /mnt/proc /proc
    mount --move /mnt/sys /sys
    mount --move /mnt/dev /dev

    rmdir /mnt/mnt/newroot
    umount /mnt/proc
    umount /mnt

    # Should be the same as what /sbin/init used to link to
    exec /lib/systemd/systemd
END
    )"

fi

if [ -z "$found_sbtsroot" ] ; then
    found_sbtsroot=$found_root
fi

# Wait up to 30 seconds for boot device to appear otherwise just fail badly
count=0
while [ "$count" -lt 30 ] ; do
    if [ -e "$found_sbtsroot" ] ; then
        echo "$found_sbtsroot found in $count seconds"
        break
    fi

    echo "$found_sbtsroot not ready, waiting 1s"

    sleep 1
    count=`expr "$count" + 1`
done

# load module
modprobe overlay || fail "ERROR: missing overlay kernel module"

# create a writable fs to then create our mountpoints 
mount -t tmpfs inittemp /mnt || fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"

mkdir /mnt/lower || fail "ERROR: Can't create /mnt/lower"
mkdir /mnt/rw || fail "ERROR: Can't create /mnt/rw"
mount -t tmpfs root-rw /mnt/rw || fail "ERROR: could not create tempfs for upper filesystem"

mkdir /mnt/rw/upper
mkdir /mnt/rw/work
mkdir /mnt/newroot

# mount root filesystem readonly 
rootDev=$found_sbtsroot
rootMountOpt=defaults
rootFsType=ext4

mount -t ${rootFsType} -o ${rootMountOpt},ro ${rootDev} /mnt/lower || fail "ERROR: could not ro-mount original root partition"
mount -t overlay -o lowerdir=/mnt/lower,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work overlayfs-root /mnt/newroot
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount overlayFS"
fi

# create mountpoints inside the new root filesystem-overlay
mkdir /mnt/newroot/ro
mkdir /mnt/newroot/rw

# remove root mount from fstab (this is already a non-permanent modification)
awk '{if ($0 ~ /^#/ || $2 != "/") print}' /mnt/lower/etc/fstab > /mnt/newroot/etc/fstab

# HACK #  > /mnt/newroot/etc/fstab
echo "#the original root mount has been removed by overlayRoot.sh" >> /mnt/newroot/etc/fstab
echo "#this is only a temporary modification, the original fstab" >> /mnt/newroot/etc/fstab
echo "#stored on the disk can be found in /ro/etc/fstab" >> /mnt/newroot/etc/fstab

# change to the new overlay root
cd /mnt/newroot
pivot_root . mnt
exec chroot . sh -c "$(cat <<END
# move ro and rw mounts to the new root
mount --move /mnt/mnt/lower/ /ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move ro-root into newroot"
    /bin/bash
fi
mount --move /mnt/mnt/rw /rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move tempfs rw mount into newroot"
    /bin/bash
fi

# Move mounts needed so we can unmount the old root mount
mount --move /mnt/proc /proc
mount --move /mnt/sys /sys
mount --move /mnt/dev /dev

umount /mnt/mnt
findmnt -n /mnt/proc > /dev/null && umount /mnt/proc
findmnt -n /mnt/sys > /dev/null && umount /mnt/sys
umount /mnt

# continue with regular init
# Should be the same as what /sbin/init used to link to
exec /lib/systemd/systemd
END
)"
