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

track_image() {
    info "%s mount: [%s]" "${iso_fs}" "$6"
    mount "$@" && IMAGE_ACTIVE_MOUNTS=("$6" "${IMAGE_ACTIVE_MOUNTS[@]}")
}

# $1: new branch
mount_image(){
    IMAGE_ACTIVE_MOUNTS=()
    track_image -t aufs -o br="$1":${work_dir}/root-image=ro none "$1"
}

mount_image_custom(){
    IMAGE_ACTIVE_MOUNTS=()
    track_image -t aufs -o br="$1":${work_dir}/${profile}-image=ro:${work_dir}/root-image=ro none "$1"
}

mount_image_live(){
    IMAGE_ACTIVE_MOUNTS=()
    track_image -t aufs -o br="$1":${work_dir}/live-image=ro:${work_dir}/root-image=ro none "$1"
}

# $1: image path
umount_image(){
    if [[ -n ${IMAGE_ACTIVE_MOUNTS[@]} ]];then
        umount "${IMAGE_ACTIVE_MOUNTS[@]}"
        unset IMAGE_ACTIVE_MOUNTS
        find $1 -name '.wh.*' -delete &> /dev/null
    fi
}
