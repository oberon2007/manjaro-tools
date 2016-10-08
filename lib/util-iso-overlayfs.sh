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
    info "%s mount: [%s]" "${iso_fs}" "$5"
    mount "$@" && IMAGE_ACTIVE_MOUNTS=("$5" "${IMAGE_ACTIVE_MOUNTS[@]}")
}

# $1: new branch
mount_image(){
    IMAGE_ACTIVE_MOUNTS=()
    mkdir -p "${work_dir}/work"
    track_image -t overlay overlay -olowerdir="${work_dir}/root-image",upperdir="$1",workdir="${work_dir}/work" "$1"
}

mount_image_custom(){
    IMAGE_ACTIVE_MOUNTS=()
    mkdir -p "${work_dir}/work"
    track_image -t overlay overlay -olowerdir="${work_dir}/${profile}-image":"${work_dir}/root-image",upperdir="$1",workdir="${work_dir}/work" "$1"
}

mount_image_live(){
    IMAGE_ACTIVE_MOUNTS=()
    mkdir -p "${work_dir}/work"
    track_image -t overlay overlay -olowerdir="${work_dir}/live-image":"${work_dir}/root-image",upperdir="$1",workdir="${work_dir}/work" "$1"
}

umount_image(){
    if [[ -n ${IMAGE_ACTIVE_MOUNTS[@]} ]];then
        info "%s umount: [%s]" "${iso_fs}" "${IMAGE_ACTIVE_MOUNTS[@]}"
        umount "${IMAGE_ACTIVE_MOUNTS[@]}"
        unset IMAGE_ACTIVE_MOUNTS
        rm -rf "${work_dir}/work"
    fi
}
