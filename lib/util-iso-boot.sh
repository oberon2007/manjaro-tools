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
        -g /boot/${iso_name}.img
}

copy_preloader_efi(){
    msg2 "Copying efi loaders ..."
    cp $1/usr/share/efitools/efi/PreLoader.efi $2/bootx64.efi
    cp $1/usr/share/efitools/efi/HashTool.efi $2/
}

copy_loader_efi(){
    cp $1/usr/lib/systemd/boot/efi/systemd-bootx64.efi $2/loader.efi
}

is_intel_ucode(){
    if [[ -f $1/iso/${iso_name}/boot/intel_ucode.img ]] ; then
        return 0
    else
        return 1
    fi
}

copy_efi_shell(){
    msg2 "Copying efi shell ..."
    cp $1${DATADIR}/efi_shell/*.efi $2/
}

copy_efi_shell_conf(){
    msg2 "Copying efi shell loader entries ..."
    cp $1${DATADIR}/efi_shell/*.conf $2/
}

copy_ucode(){
    cp $1/boot/intel-ucode.img $2/intel_ucode.img
    cp $1/usr/share/licenses/intel-ucode/LICENSE $2/intel_ucode.LICENSE
}

copy_boot_images(){
    msg2 "Copying boot images ..."
    cp $1/iso/${iso_name}/boot/x86_64/${iso_name} $1/efiboot/EFI/miso/${iso_name}.efi
    cp $1/iso/${iso_name}/boot/x86_64/${iso_name}.img $1/efiboot/EFI/miso/${iso_name}.img
    if $(is_intel_ucode "$1"); then
        cp $1/iso/${iso_name}/boot/intel_ucode.img $1/efiboot/EFI/miso/intel_ucode.img
    fi
}

prepare_efi_loader_conf(){
    prepare_dir "$1"
    sed "s|%ISO_NAME%|${iso_name}|g" ${run_dir}/shared/efiboot/loader.conf > $1/loader.conf
}

gen_boot_args(){
    local args=(quiet)
    if ${plymouth_boot};then
        args+=(splash)
    fi
    echo ${args[@]}
}

set_efi_loader_entry_conf(){
    sed -e "s|@ISO_NAME@|${iso_name}|g" \
        -e "s|@ISO_LABEL@|${iso_label}|g" \
        -e "s|@DRV@|$2|g" \
        -e "s|@SWITCH@|$3|g" \
        -e "s|@BOOT_ARGS@|$(gen_boot_args)|g" \
        -i $1
}

prepare_loader_entry(){
    local drv='free' switch="no"
    prepare_dir "$1/loader/entries"
    cp ${run_dir}/shared/efiboot/miso-x86_64-$2.conf $1/loader/entries/${iso_name}-x86_64.conf
    set_efi_loader_entry_conf "$1/loader/entries/${iso_name}-x86_64.conf" "$drv" "$switch"
    if ${nonfree_mhwd};then
        drv='nonfree' switch="yes"
        cp ${run_dir}/shared/efiboot/miso-x86_64-$2.conf $1/loader/entries/${iso_name}-x86_64-nonfree.conf
        set_efi_loader_entry_conf "$1/loader/entries/${iso_name}-x86_64-nonfree.conf" "$drv" "$switch"
    fi
}

prepare_syslinux(){
    local syslinux=${run_dir}/shared/syslinux
    msg2 "Copying syslinux splash ..."
    cp ${syslinux}/splash.png $2
    for conf in ${syslinux}/*.cfg ${syslinux}/${target_arch}/*.cfg; do
        msg2 "Copying %s ..." "${conf##*/}"
        sed "s|@ISO_LABEL@|${iso_label}|g;
            s|@ISO_NAME@|${iso_name}|g;
            s|@BOOT_ARGS@|$(gen_boot_args)|g;
            s|@DIST_NAME@|${dist_name}|g" ${conf} > $2/${conf##*/}
    done
    msg2 "Copying syslinux binaries ..."
    cp $1/usr/lib/syslinux/bios/*.c32 $2
    cp $1/usr/lib/syslinux/bios/lpxelinux.0 $2
    cp $1/usr/lib/syslinux/bios/memdisk $2
}

prepare_isolinux(){
    msg2 "Copying isolinux.cfg ..."
    sed "s|@ISO_NAME@|${iso_name}|g" ${run_dir}/shared/isolinux/isolinux.cfg > $2/isolinux.cfg
    msg2 "Copying isolinux binaries ..."
    cp $1/usr/lib/syslinux/bios/isolinux.bin $2
    cp $1/usr/lib/syslinux/bios/isohdpfx.bin $2
    cp $1/usr/lib/syslinux/bios/ldlinux.c32 $2
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
