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
#     cp $1/usr/share/efitools/efi/Loader.efi $2/loader.efi
}

copy_loader_efi(){
    cp $1/usr/lib/systemd/boot/efi/systemd-bootx64.efi $2/loader.efi
}

copy_boot_images(){
    msg2 "Copying boot images ..."
    cp $1/x86_64/${iso_name} $2/${iso_name}.efi
    cp $1/x86_64/${iso_name}.img $2/${iso_name}.img
    if [[ -f $1/intel_ucode.img ]] ; then
        msg2 "Using intel_ucode.img ..."
        cp $1/intel_ucode.img $2/intel_ucode.img
    fi
}

copy_ucode(){
    cp $1/boot/intel-ucode.img $2/intel_ucode.img
    cp $1/usr/share/licenses/intel-ucode/LICENSE $2/intel_ucode.LICENSE
}

write_loader_conf(){
    local fn=loader.conf
    local conf=$1/${fn}
    msg2 "Writing %s ..." "${fn}"
    echo 'timeout 3' > ${conf}
    echo "default ${iso_name}-${target_arch}-free" >> ${conf}
}

gen_boot_args(){
    local args=(quiet)
    if ${plymouth_boot};then
        args+=(splash)
    fi
    echo ${args[@]}
}

write_usb_efi_loader_conf(){
    local drv='free' switch="$2"
    [[ ${switch} == 'yes' ]] && drv='nonfree'
    local fn=${iso_name}-${target_arch}-${drv}.conf
    local conf=$1/iso/loader/entries/${fn} path="$1/iso"
    msg2 "Writing %s ..." "${fn}"
    echo "title   ${dist_name} Linux ${target_arch} UEFI USB (${drv})" > ${conf}
    echo "linux   /${iso_name}/boot/${target_arch}/${iso_name}" >> ${conf}
    if [[ -f ${path}/${iso_name}/boot/intel_ucode.img ]] ; then
        msg2 "Using intel_ucode.img ..."
        echo "initrd  /${iso_name}/boot/intel_ucode.img" >> ${conf}
    fi
    echo "initrd  /${iso_name}/boot/${target_arch}/${iso_name}.img" >> ${conf}
    echo "options misobasedir=${iso_name} misolabel=${iso_label} nouveau.modeset=1 i915.modeset=1 radeon.modeset=1 logo.nologo overlay=${drv} nonfree=${switch} $(gen_boot_args)" >> ${conf}
}

write_dvd_efi_loader_conf(){
    local drv='free' switch="$2"
    [[ ${switch} == 'yes' ]] && drv='nonfree'
    local fn=${iso_name}-${target_arch}-${drv}.conf
    local conf=$1/efiboot/loader/entries/${fn} path="$1/iso"
    msg2 "Writing %s ..." "${fn}"
    echo "title   ${dist_name} Linux ${target_arch} UEFI DVD (${drv})" > ${conf}
    echo "linux   /EFI/miso/${iso_name}.efi" >> ${conf}
    if [[ -f ${path}/${iso_name}/boot/intel_ucode.img ]] ; then
        msg2 "Using intel_ucode.img ..."
        echo "initrd  /EFI/miso/intel_ucode.img" >> ${conf}
    fi
    echo "initrd  /EFI/miso/${iso_name}.img" >> ${conf}
    echo "options misobasedir=${iso_name} misolabel=${iso_label} nouveau.modeset=1 i915.modeset=1 radeon.modeset=1 logo.nologo overlay=${drv} nonfree=${switch} $(gen_boot_args)" >> ${conf}
}

copy_isolinux_bin(){
    msg2 "Copying isolinux bios binaries ..." 
    cp $1/usr/lib/syslinux/bios/{{isolinux,isohdpfx}.bin,{ldlinux,gfxboot,whichsys,mboot,hdt,chain,libcom32,libmenu,libutil,libgpl}.c32} $2
}

copy_syslinux_efi(){
    msg2 "Copying syslinux efi binaries ..."
    cp $1/usr/lib/syslinux/efi64/{syslinux.efi,ldlinux.e64,{menu,libcom32,libutil}.c32} $2
}

gen_initrd_arg(){
    local path="/${iso_name}/boot/${target_arch}/${iso_name}.img"
    local arg="initrd=${path}"
    if [[ -f $1/${iso_name}/boot/intel_ucode.img ]] ; then
        arg="initrd=/${iso_name}/boot/intel_ucode.img,${path}"
    fi
    echo $arg
}

write_isolinux_cfg(){
    local fn=isolinux.cfg
    local conf=$1/${fn} path=$2
    msg2 "Writing %s ..." "${fn}"
    echo "default start" > ${conf}
    echo "implicit 1" >> ${conf}
    echo "display isolinux.msg" >> ${conf}
    echo "ui gfxboot bootlogo isolinux.msg" >> ${conf}
    echo "prompt   1" >> ${conf}
    echo "timeout  200" >> ${conf}
    echo '' >> ${conf}
    echo "label start" >> ${conf}
    echo "  kernel /${iso_name}/boot/${target_arch}/${iso_name}" >> ${conf}

    local initrd_arg=$(gen_initrd_arg $path)

    echo "  append ${initrd_arg} misobasedir=${iso_name} misolabel=${iso_label} nouveau.modeset=1 i915.modeset=1 radeon.modeset=1 logo.nologo overlay=free $(gen_boot_args) showopts" >> ${conf}

    echo '' >> ${conf}
    if ${nonfree_mhwd};then
        echo "label nonfree" >> ${conf}
        echo "  kernel /${iso_name}/boot/${target_arch}/${iso_name}" >> ${conf}
        echo "  append ${initrd_arg} misobasedir=${iso_name} misolabel=${iso_label} nouveau.modeset=0 i915.modeset=1 radeon.modeset=0 nonfree=yes logo.nologo overlay=nonfree $(gen_boot_args) showopts" >> ${conf}
        echo '' >> ${conf}
    fi
    echo "label harddisk" >> ${conf}
    echo "  com32 whichsys.c32" >> ${conf}
    echo "  append -iso- chain.c32 hd0" >> ${conf}
    echo '' >> ${conf}
    echo "label hdt" >> ${conf}
    echo "  kernel hdt.c32" >> ${conf}
    echo '' >> ${conf}
    echo "label memtest" >> ${conf}
    echo "  kernel memtest" >> ${conf}
}

write_isolinux_msg(){
    local fn=isolinux.msg
    local conf=$1/${fn}
    msg2 "Writing %s ..." "${fn}"
    echo "Welcome to ${dist_name} Linux!" > ${conf}
    echo '' >> ${conf}
    echo "To start the system enter 'start' and press <return>" >> ${conf}
    echo '' >> ${conf}
    echo '' >> ${conf}
    echo "Available boot options:" >> ${conf}
    echo "start                    - Start ${dist_name} Live System" >> ${conf}
    if ${nonfree_mhwd};then
        echo "nonfree                  - Start with proprietary drivers" >> ${conf}
    fi
    echo "harddisk                 - Boot from local hard disk" >> ${conf}
    echo "hdt                      - Run Hardware Detection Tool" >> ${conf}
    echo "memtest                  - Run Memory Test" >> ${conf}
}

update_isolinux_cfg(){
    local fn=isolinux.cfg
    msg2 "Updating %s ..." "${fn}"
    sed -i "s|%ISO_LABEL%|${iso_label}|g;
            s|%ISO_NAME%|${iso_name}|g;
            s|%ARCH%|${target_arch}|g" $2/${fn}
}

update_isolinux_msg(){
    local fn=isolinux.msg
    msg2 "Updating %s ..." "${fn}"
    sed -i "s|%DIST_NAME%|${dist_name}|g" $2/${fn}
}

write_isomounts(){
    local file=$1/isomounts
    echo '# syntax: <img> <arch> <mount point> <type> <kernel argument>' > ${file}
    echo '# Sample kernel argument in syslinux: overlay=extra,extra2' >> ${file}
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
