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
        sed -e 's/miso_pxe_common miso_pxe_http miso_pxe_nbd miso_pxe_nfs //' \
        -e 's/memdisk //' -i $1
    fi
    if ! ${plymouth_boot};then
        msg2 "Removing plymouth hook"
        sed -e 's/plymouth //' -i $1
    fi
    if ! ${use_overlayfs};then
        msg2 "Setting aufs hook"
        sed -e 's/miso /miso_aufs /' -i $1
    fi
}

gen_boot_args(){
#     local args=(quiet)
    local args=()
    if ${plymouth_boot};then
        args+=(splash)
    fi
    echo ${args[@]}
}

prepare_initcpio(){
    msg2 "Copying initcpio ..."
    cp /etc/initcpio/hooks/miso* $1/etc/initcpio/hooks
    cp /etc/initcpio/install/miso* $1/etc/initcpio/install
    cp /etc/initcpio/miso_shutdown $1/etc/initcpio
#     sed -e "s|/usr/lib/initcpio/|/etc/initcpio/|" -i $1/etc/initcpio/install/miso_shutdown
}

prepare_initramfs(){
    cp $1/mkinitcpio.conf $2/etc/mkinitcpio-${iso_name}.conf
    set_mkinicpio_hooks "$2/etc/mkinitcpio-${iso_name}.conf"
    local _kernver=$(cat $2/usr/lib/modules/*/version)
    chroot-run $2 \
        /usr/bin/mkinitcpio -k ${_kernver} \
        -c /etc/mkinitcpio-${iso_name}.conf \
        -g /boot/initramfs.img
}

prepare_boot_extras(){
    cp $1/boot/intel-ucode.img $2/intel_ucode.img
    cp $1/usr/share/licenses/intel-ucode/LICENSE $2/intel_ucode.LICENSE
    cp $1/boot/memtest86+/memtest.bin $2/memtest
    cp $1/usr/share/licenses/common/GPL2/license.txt $2/memtest.COPYING
}

prepare_efiboot_image(){
    local efi=$1/EFI/miso boot=$2/${iso_name}/boot
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
    local efi_data=$1/usr/share/efi-utils efi=$2/EFI/boot
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

prepare_isolinux(){
    local syslinux=$1/usr/lib/syslinux/bios
    msg2 "Copying isolinux binaries ..."
    cp ${syslinux}/{{isolinux,isohdpfx}.bin,ldlinux.c32} $2
    msg2 "Copying isolinux.cfg ..."
    cp $1/usr/share/syslinux/isolinux/isolinux.cfg $2
    vars_to_boot_conf "$2/isolinux.cfg"
}

prepare_syslinux(){
    local syslinux=$1/usr/lib/syslinux/bios
    msg2 "Copying syslinux binaries ..."
    cp ${syslinux}/{*.c32,lpxelinux.0,memdisk} $2
    msg2 "Copying syslinux theme ..."
    syslinux=$1/usr/share/syslinux/theme
    cp ${syslinux}/* $2
    for conf in $2/*.cfg; do
        vars_to_boot_conf "${conf}"
    done
    if ! ${nonfree_mhwd};then
        check_syslinux_optional "$2"
    fi
}
