#!/bin/bash
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

copy_mirrorlist(){
    cp -a /etc/pacman.d/mirrorlist "$1/etc/pacman.d/"
}

copy_keyring(){
    if [[ -d /etc/pacman.d/gnupg ]] && [[ ! -d $1/etc/pacman.d/gnupg ]]; then
        cp -a /etc/pacman.d/gnupg "$1/etc/pacman.d/"
    fi
}

create_min_fs(){
    msg "Creating install root at %s" "$1"
    mkdir -m 0755 -p $1/var/{cache/pacman/pkg,lib/pacman,log} $1/{dev,run,etc}
    mkdir -m 1777 -p $1/tmp
    mkdir -m 0555 -p $1/{sys,proc}
}

is_btrfs() {
	[[ -e "$1" && "$(stat -f -c %T "$1")" == btrfs ]]
}

subvolume_delete_recursive() {
    local subvol

    is_btrfs "$1" || return 0

    while IFS= read -d $'\0' -r subvol; do
        if ! btrfs subvolume delete "$subvol" &>/dev/null; then
            error "Unable to delete subvolume %s" "$subvol"
            return 1
        fi
    done < <(find "$1" -xdev -depth -inum 256 -print0)

    return 0
}

# $1: chroot
# kill_chroot_process(){
#     # enable to have more debug info
#     #msg "machine-id (etc): $(cat $1/etc/machine-id)"
#     #[[ -e $1/var/lib/dbus/machine-id ]] && msg "machine-id (lib): $(cat $1/var/lib/dbus/machine-id)"
#     #msg "running processes: "
#     #lsof | grep $1
#
#     local prefix="$1" flink pid name
#     for root_dir in /proc/*/root; do
#         flink=$(readlink $root_dir)
#         if [ "x$flink" != "x" ]; then
#             if [ "x${flink:0:${#prefix}}" = "x$prefix" ]; then
#                 # this process is in the chroot...
#                 pid=$(basename $(dirname "$root_dir"))
#                 name=$(ps -p $pid -o comm=)
#                 info "Killing chroot process: %s (%s)" "$name" "$pid"
#                 kill -9 "$pid"
#             fi
#         fi
#     done
# }
