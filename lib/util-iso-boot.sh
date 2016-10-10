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

set_mkinicpio_hooks(){
    if ! ${pxe_boot};then
        msg2 "Removing pxe hooks"
        sed -e 's/miso_pxe_common miso_pxe_http //' \
        -e 's/memdisk //' -i $1
    fi
    if ! ${plymouth_boot};then
        msg2 "Removing plymouth hook"
        sed -e 's/plymouth //' -i $1
    fi
    if ${use_overlayfs};then
        sed -e 's/miso /miso_overlayfs /' -i $1
    fi
}

gen_boot_args(){
    local args=(quiet)
    if ${plymouth_boot};then
        args+=(splash)
    fi
    echo ${args[@]}
}

set_silent_switch_root(){
    sed -e 's|"$@"|"$@" >/dev/null 2>&1|' -i $1/usr/lib/initcpio/init
}

copy_initcpio(){
    msg2 "Copying initcpio ..."
    cp /usr/lib/initcpio/hooks/miso* $2/usr/lib/initcpio/hooks
    cp /usr/lib/initcpio/install/miso* $2/usr/lib/initcpio/install
    cp $1/mkinitcpio.conf $2/etc/mkinitcpio-${iso_name}.conf
    set_mkinicpio_hooks "$2/etc/mkinitcpio-${iso_name}.conf"
    set_silent_switch_root "$2"
}

# $1: work_dir
gen_boot_image(){
    local _kernver=$(cat $1/usr/lib/modules/*/version)
    chroot-run $1 \
        /usr/bin/mkinitcpio -k ${_kernver} \
        -c /etc/mkinitcpio-${iso_name}.conf \
        -g /boot/initramfs.img
}

copy_ucode(){
    cp $1/boot/intel-ucode.img $2/intel_ucode.img
    cp $1/usr/share/licenses/intel-ucode/LICENSE $2/intel_ucode.LICENSE
}

prepare_efiboot_image(){
    local efi=$1/efiboot/EFI/miso boot=$2/${iso_name}/boot
    prepare_dir "${efi}"
    cp ${boot}/x86_64/vmlinuz ${efi}/vmlinuz.efi
    cp ${boot}/x86_64/initramfs.img ${efi}/initramfs.img
    if [[ -f ${boot}/intel_ucode.img ]] ; then
        cp ${boot}/intel_ucode.img ${efi}/intel_ucode.img
    fi
}

vars_to_boot_conf(){
    sed -e "s|@ISO_NAME@|${iso_name}|g" \
        -e "s|@ISO_LABEL@|${iso_label}|g" \
        -e "s|@DIST_NAME@|${dist_name}|g" \
        -e "s|@ARCH@|${target_arch}|g" \
        -e "s|@DRV@|$2|g" \
        -e "s|@SWITCH@|$3|g" \
        -e "s|@BOOT_ARGS@|$(gen_boot_args)|g" \
        -i $1
}

prepare_efi_loader(){
    local efi_data=$1${DATADIR}/efiboot efi=$2/EFI/boot
    msg2 "Preparing efi loaders ..."
    prepare_dir "${efi}"
    cp $1/usr/share/efitools/efi/PreLoader.efi ${efi}/bootx64.efi
    cp $1/usr/share/efitools/efi/HashTool.efi ${efi}
    cp ${efi_data}/gummibootx64.efi ${efi}/loader.efi
    cp ${efi_data}/shellx64_v{1,2}.efi $2/EFI

    local entries=$2/loader/entries
    msg2 "Preparing efi loader config ..."
    prepare_dir "${entries}"

    cp ${efi_data}/loader.conf $2/loader/loader.conf
    vars_to_boot_conf $2/loader/loader.conf
    cp ${efi_data}/uefi-shell-v{1,2}-x86_64.conf ${entries}

    local drv='free' switch="no"
    cp ${efi_data}/entry-x86_64-$3.conf ${entries}/${iso_name}-x86_64.conf
    vars_to_boot_conf "${entries}/${iso_name}-x86_64.conf" "$drv" "$switch"
    if ${nonfree_mhwd};then
        drv='nonfree' switch="yes"
        cp ${efi_data}/entry-x86_64-$3.conf ${entries}/${iso_name}-x86_64-nonfree.conf
        vars_to_boot_conf "${entries}/${iso_name}-x86_64-nonfree.conf" "$drv" "$switch"
    fi
}

check_syslinux_optional(){
    msg2 "Configuring syslinux menu ..."
    sed -e "/LABEL optional/,/^$/d" -i "$1/miso_sys_i686.cfg"
    sed -e "/LABEL optional/,/^$/d" -i "$1/miso_sys_x86_64.cfg"
    sed -e "/nonfree/ d" -i $1/syslinux.msg
}

prepare_syslinux(){
    local syslinux=/usr/lib/syslinux/bios
    msg2 "Copying syslinux binaries ..."
    cp ${syslinux}/{*.c32,lpxelinux.0,memdisk,{isolinux,isohdpfx}.bin} $1
    msg2 "Copying syslinux theme ..."
    cp ${DATADIR}/syslinux-theme/* $1
    for conf in $1/*.cfg; do
        vars_to_boot_conf "${conf}"
    done
    if ! ${nonfree_mhwd};then
        check_syslinux_optional "$1"
    fi
}

write_isomounts(){
    local file=$1/isomounts
    echo '# syntax: <img> <arch> <mount point> <type> <kernel argument>' > ${file}
    echo '' >> ${file}
    msg2 "Writing live entry ..."
    echo "${target_arch}/live-image.sqfs ${target_arch} / squashfs" >> ${file}
    if [[ -f ${packages_mhwd} ]] ; then
        msg2 "Writing mhwd entry ..."
        echo "${target_arch}/mhwd-image.sqfs ${target_arch} / squashfs" >> ${file}
    fi
    if [[ -f "${packages_custom}" ]] ; then
        msg2 "Writing %s entry ..." "${profile}"
        echo "${target_arch}/${profile}-image.sqfs ${target_arch} / squashfs" >> ${file}
    fi
    msg2 "Writing root entry ..."
    echo "${target_arch}/root-image.sqfs ${target_arch} / squashfs" >> ${file}
}
