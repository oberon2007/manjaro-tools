#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

track_fs() {
    info "%s mount: [%s]" "${iso_fs}" "$6"
    mount "$@" && FS_ACTIVE_MOUNTS=("$6" "${FS_ACTIVE_MOUNTS[@]}")
}

# $1: new branch
mount_fs_root(){
    FS_ACTIVE_MOUNTS=()
    track_fs -t aufs -o br="$1":${work_dir}/rootfs=ro none "$1"
}

mount_fs_desktop(){
    FS_ACTIVE_MOUNTS=()
    track_fs -t aufs -o br="$1":${work_dir}/desktopfs=ro:${work_dir}/rootfs=ro none "$1"
}

mount_fs_live(){
    FS_ACTIVE_MOUNTS=()
    track_fs -t aufs -o br="$1":${work_dir}/livefs=ro:${work_dir}/desktopfs=ro:${work_dir}/rootfs=ro none "$1"
}

mount_fs_net(){
    FS_ACTIVE_MOUNTS=()
    track_fs -t aufs -o br="$1":${work_dir}/livefs=ro:${work_dir}/rootfs=ro none "$1"
}

# $1: image path
umount_fs(){
    if [[ -n ${FS_ACTIVE_MOUNTS[@]} ]];then
        umount "${FS_ACTIVE_MOUNTS[@]}"
        unset FS_ACTIVE_MOUNTS
        find $1 -name '.wh.*' -delete &> /dev/null
    fi
}
