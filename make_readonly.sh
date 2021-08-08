#!/bin/bash

# Copyright (c) 2021 Kim Hendrikse

HERE=$(dirname $0)
cd $HERE || abort "Can't change to script directory"
HERE=`/bin/pwd`

abort() {
    echo $* >&2
    exit 1
}

determine_type() {
    COMMAND=$(basename $0)
    if [ "$COMMAND" == "make_readonly.sh" ] ; then
	CONF_FILE="readonly_extlinux.conf"
    elif [ "$COMMAND" == "make_readwrite.sh" ] ; then
	CONF_FILE="readwrite_extlinux.conf"
    elif [ "$COMMAND" == "make_orig.sh" ] ; then
	CONF_FILE="orig_extlinux.conf"
    else
	abort "Can't find the extlinux conf file for this state"
    fi
}

check_need_to_mount() {
    if [ "$(findmnt -n / | awk '{print $2}')" == "/dev/mmcblk0p1" ] ; then
	NEED_TO_MOUNT=
    else
	NEED_TO_MOUNT=1
    fi
}

sanity_check() {
    if [ "$(id -n -u)" != "root" ] ; then
	abort "You need to execute this script as root"
    fi

    if [ "$NEED_TO_MOUNT" -a -e /tmp/mnt ] ; then
	abort "/tmp/mnt already exists, please unmount and delete before running this script"
    fi
}

check_need_to_mount

sanity_check

determine_type

if [ ! "$NEED_TO_MOUNT" ] ; then
    cp "/boot/extlinux/$CONF_FILE" /boot/extlinux/extlinux.conf
else
    mkdir -p /tmp/mnt
    mount /dev/mmcblk0p1 /tmp/mnt || exit 1

    cp "/tmp/mnt/boot/extlinux/$CONF_FILE" /tmp/mnt/boot/extlinux/extlinux.conf

    umount /tmp/mnt
    rmdir /tmp/mnt
fi

exit 0
