#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

copy_overlay(){
    if [[ -e $1 ]];then
        msg2 "Copying [%s] ..." "${1##*/}"
        if [[ -L $1 ]];then
            cp -a --no-preserve=ownership $1/* $2
        else
            cp -LR $1/* $2
        fi
    fi
}

add_svc_rc(){
    if [[ -f $1/etc/init.d/$2 ]];then
        msg2 "Setting %s ..." "$2"
        chroot $1 rc-update add $2 default &>/dev/null
    fi
}

add_svc_sd(){
    if [[ -f $1/etc/systemd/system/$2.service ]] || \
    [[ -f $1/usr/lib/systemd/system/$2.service ]];then
        msg2 "Setting %s ..." "$2"
        chroot $1 systemctl enable $2 &>/dev/null
    fi
}

set_xdm(){
    if [[ -f $1/etc/conf.d/xdm ]];then
        local conf='DISPLAYMANAGER="'${displaymanager}'"'
        sed -i -e "s|^.*DISPLAYMANAGER=.*|${conf}|" $1/etc/conf.d/xdm
    fi
}

configure_mhwd_drivers(){
    local path=$1${mhwd_repo}/ \
        drv_path=$1/var/lib/mhwd/db/pci/graphic_drivers
    info "Configuring mwwd db ..."
    if  [ -z "$(ls $path | grep catalyst-utils 2> /dev/null)" ]; then
        msg2 "Disabling Catalyst driver"
        mkdir -p $drv_path/catalyst/
        touch $drv_path/catalyst/MHWDCONFIG
    fi
    if  [ -z "$(ls $path | grep nvidia-utils 2> /dev/null)" ]; then
        msg2 "Disabling Nvidia driver"
        mkdir -p $drv_path/nvidia/
        touch $drv_path/nvidia/MHWDCONFIG
        msg2 "Disabling Nvidia Bumblebee driver"
        mkdir -p $drv_path/hybrid-intel-nvidia-bumblebee/
        touch $drv_path/hybrid-intel-nvidia-bumblebee/MHWDCONFIG
    fi
    if  [ -z "$(ls $path | grep nvidia-304xx-utils 2> /dev/null)" ]; then
        msg2 "Disabling Nvidia 304xx driver"
        mkdir -p $drv_path/nvidia-304xx/
        touch $drv_path/nvidia-304xx/MHWDCONFIG
    fi
    if  [ -z "$(ls $path | grep nvidia-340xx-utils 2> /dev/null)" ]; then
        msg2 "Disabling Nvidia 340xx driver"
        mkdir -p $drv_path/nvidia-340xx/
        touch $drv_path/nvidia-340xx/MHWDCONFIG
    fi
    if  [ -z "$(ls $path | grep xf86-video-amdgpu 2> /dev/null)" ]; then
        msg2 "Disabling AMD gpu driver"
        mkdir -p $drv_path/xf86-video-amdgpu/
        touch $drv_path/xf86-video-amdgpu/MHWDCONFIG
    fi
}

configure_hosts(){
    sed -e "s|localhost.localdomain|localhost.localdomain ${hostname}|" -i $1/etc/hosts
}

configure_lsb(){
    if [ -e $1/etc/lsb-release ] ; then
        msg2 "Configuring lsb-release"
        sed -i -e "s/^.*DISTRIB_RELEASE.*/DISTRIB_RELEASE=${dist_release}/" $1/etc/lsb-release
        sed -i -e "s/^.*DISTRIB_CODENAME.*/DISTRIB_CODENAME=${dist_codename}/" $1/etc/lsb-release
    fi
}

configure_logind(){
    msg2 "Configuring logind ..."
    local conf=$1/etc/$2/logind.conf
    sed -i 's/#\(HandleSuspendKey=\)suspend/\1ignore/' "$conf"
    sed -i 's/#\(HandleLidSwitch=\)suspend/\1ignore/' "$conf"
    sed -i 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' "$conf"
}

configure_journald(){
    msg2 "Configuring journald ..."
    local conf=$1/etc/systemd/journald.conf
    sed -i 's/#\(Storage=\)auto/\1volatile/' "$conf"
}

configure_services(){
    info "Configuring [%s]" "${initsys}"
    case ${initsys} in
        'openrc')
            for svc in ${enable_openrc[@]}; do
                [[ $svc == "xdm" ]] && set_xdm "$1"
                add_svc_rc "$1" "$svc"
            done
            for svc in ${enable_openrc_live[@]}; do
                add_svc_rc "$1" "$svc"
            done
        ;;
        'systemd')
            for svc in ${enable_systemd[@]}; do
                add_svc_sd "$1" "$svc"
            done
            for svc in ${enable_systemd_live[@]}; do
                add_svc_sd "$1" "$svc"
            done
        ;;
    esac
    info "Done configuring [%s]" "${initsys}"
}

write_live_session_conf(){
    local path=$1${SYSCONFDIR}
    [[ ! -d $path ]] && mkdir -p $path
    local conf=$path/live.conf
    msg2 "Writing %s" "${conf##*/}"
    echo '# live session configuration' > ${conf}
    echo '' >> ${conf}
    echo '# autologin' >> ${conf}
    echo "autologin=${autologin}" >> ${conf}
    echo '' >> ${conf}
    echo '# login shell' >> ${conf}
    echo "login_shell=${login_shell}" >> ${conf}
    echo '' >> ${conf}
    echo '# live username' >> ${conf}
    echo "username=${username}" >> ${conf}
    echo '' >> ${conf}
    echo '# live password' >> ${conf}
    echo "password=${password}" >> ${conf}
    echo '' >> ${conf}
    echo '# live group membership' >> ${conf}
    echo "addgroups='${addgroups}'" >> ${conf}
    if [[ -n ${smb_workgroup} ]];then
        echo '' >> ${conf}
        echo '# samba workgroup' >> ${conf}
        echo "smb_workgroup=${smb_workgroup}" >> ${conf}
    fi
}

configure_system(){
    case ${initsys} in
        'systemd')
            configure_logind "$1" "systemd"
            configure_journald "$1"

            # Prevent some services to be started in the livecd
            echo 'File created by manjaro-tools. See systemd-update-done.service(8).' \
            | tee "${path}/etc/.updated" >"${path}/var/.updated"

            msg2 "Disable systemd-gpt-auto-generator"
            ln -sf /dev/null "${path}/usr/lib/systemd/system-generators/systemd-gpt-auto-generator"
        ;;
        'openrc')
            configure_logind "$1" "elogind"
#             local hn='hostname="'${hostname}'"'
#             sed -i -e "s|^.*hostname=.*|${hn}|" $1/etc/conf.d/hostname
        ;;
    esac
    echo ${hostname} > $1/etc/hostname
}

make_repo(){
    repo-add $1${mhwd_repo}/mhwd.db.tar.gz $1${mhwd_repo}/*pkg*z
}

clean_iso_root(){
    msg2 "Deleting isoroot [%s] ..." "${1##*/}"
    rm -rf --one-file-system "$1"
}

clean_up_image(){
    msg2 "Cleaning [%s]" "${1##*/}"

    local path
    if [[ ${1##*/} == 'mhwdfs' ]];then
        path=$1/var
        if [[ -d $path ]];then
            find "$path" -mindepth 0 -delete &> /dev/null
        fi
        path=$1/etc
        if [[ -d $path ]];then
            find "$path" -mindepth 0 -delete &> /dev/null
        fi
    else
        [[ -f "$1/etc/locale.gen.bak" ]] && mv "$1/etc/locale.gen.bak" "$1/etc/locale.gen"
        [[ -f "$1/etc/locale.conf.bak" ]] && mv "$1/etc/locale.conf.bak" "$1/etc/locale.conf"
        path=$1/boot
        if [[ -d "$path" ]]; then
            find "$path" -name 'initramfs*.img' -delete &> /dev/null
        fi
        path=$1/var/lib/pacman/sync
        if [[ -d $path ]];then
            find "$path" -type f -delete &> /dev/null
        fi
        path=$1/var/cache/pacman/pkg
        if [[ -d $path ]]; then
            find "$path" -type f -delete &> /dev/null
        fi
        path=$1/var/log
        if [[ -d $path ]]; then
            find "$path" -type f -delete &> /dev/null
        fi
        path=$1/var/tmp
        if [[ -d $path ]];then
            find "$path" -mindepth 1 -delete &> /dev/null
        fi
        path=$1/tmp
        if [[ -d $path ]];then
            find "$path" -mindepth 1 -delete &> /dev/null
        fi
    fi
	find "$1" -name *.pacnew -name *.pacsave -name *.pacorig -delete
	file=$1/boot/grub/grub.cfg
        if [[ -f "$file" ]]; then
            rm $file
        fi
}

copy_from_cache(){
    local list="${tmp_dir}"/mhwd-cache.list
    chroot-run \
        -r "${bindmounts_ro[*]}" \
        -w "${bindmounts_rw[*]}" \
        -B "${build_mirror}/${target_branch}" \
        "$1" \
        pacman -v -Syw $2 --noconfirm || return 1
    chroot-run \
        -r "${bindmounts_ro[*]}" \
        -w "${bindmounts_rw[*]}" \
        -B "${build_mirror}/${target_branch}" \
        "$1" \
        pacman -v -Sp $2 --noconfirm > "$list"
    sed -ni '/.pkg.tar.xz/p' "$list"
    sed -i "s/.*\///" "$list"

    msg2 "Copying mhwd package cache ..."
    rsync -v --files-from="$list" /var/cache/pacman/pkg "$1${mhwd_repo}"
}

chroot_create(){
    [[ "${1##*/}" == "rootfs" ]] && local flag="-L"
    setarch "${target_arch}" \
        mkchroot ${mkchroot_args[*]} ${flag} $@
}

chroot_clean(){
    msg "Cleaning up ..."
    for image in "$1"/*fs; do
        [[ -d ${image} ]] || continue
        local name=${image##*/}
        if [[ $name != "mhwdfs" ]];then
            msg2 "Deleting chroot [%s] (%s) ..." "$name" "${1##*/}"
            lock 9 "${image}.lock" "Locking chroot '${image}'"
            if [[ "$(stat -f -c %T "${image}")" == btrfs ]]; then
                { type -P btrfs && btrfs subvolume delete "${image}"; } #&> /dev/null
            fi
        rm -rf --one-file-system "${image}"
        fi
    done
    exec 9>&-
    rm -rf --one-file-system "$1"
}

prepare_initcpio(){
    msg2 "Copying initcpio ..."
    cp /etc/initcpio/hooks/miso* $1/etc/initcpio/hooks
    cp /etc/initcpio/install/miso* $1/etc/initcpio/install
    cp /etc/initcpio/miso_shutdown $1/etc/initcpio
}

prepare_initramfs(){
    cp ${DATADIR}/mkinitcpio.conf $1/etc/mkinitcpio-${iso_name}.conf
    local _kernver=$(cat $1/usr/lib/modules/*/version)
    if [[ -n ${gpgkey} ]]; then
        su ${OWNER} -c "gpg --export ${gpgkey} >${MT_USERCONFDIR}/gpgkey"
        exec 17<>${MT_USERCONFDIR}/gpgkey
    fi
    MISO_GNUPG_FD=${gpgkey:+17} chroot-run $1 \
        /usr/bin/mkinitcpio -k ${_kernver} \
        -c /etc/mkinitcpio-${iso_name}.conf \
        -g /boot/initramfs.img

    if [[ -n ${gpgkey} ]]; then
        exec 17<&-
    fi
    if [[ -f ${MT_USERCONFDIR}/gpgkey ]]; then
        rm ${MT_USERCONFDIR}/gpgkey
    fi
}

prepare_boot_extras(){
    cp $1/boot/intel-ucode.img $2/intel_ucode.img
    cp $1/usr/share/licenses/intel-ucode/LICENSE $2/intel_ucode.LICENSE
    cp $1/boot/memtest86+/memtest.bin $2/memtest
    cp $1/usr/share/licenses/common/GPL2/license.txt $2/memtest.COPYING
}

prepare_grub(){
    local platform=i386-pc img='core.img' grub=$3/boot/grub efi=$3/efi/boot \
        lib=$1/usr/lib/grub prefix=/boot/grub theme=$2/usr/share/grub data=$1/usr/share/grub

    prepare_dir ${grub}/${platform}

    cp ${theme}/cfg/*.cfg ${grub}

    cp ${lib}/${platform}/* ${grub}/${platform}

    msg2 "Building %s ..." "${img}"

    grub-mkimage -d ${grub}/${platform} -o ${grub}/${platform}/${img} -O ${platform} -p ${prefix} biosdisk iso9660

    cat ${grub}/${platform}/cdboot.img ${grub}/${platform}/${img} > ${grub}/${platform}/eltorito.img

    case ${target_arch} in
        'i686')
            platform=i386-efi
            img=bootia32.efi
        ;;
        'x86_64')
            platform=x86_64-efi
            img=bootx64.efi
        ;;
    esac

    prepare_dir ${efi}
    prepare_dir ${grub}/${platform}

    cp ${lib}/${platform}/* ${grub}/${platform}

    msg2 "Building %s ..." "${img}"

    grub-mkimage -d ${grub}/${platform} -o ${efi}/${img} -O ${platform} -p ${prefix} iso9660

    prepare_dir ${grub}/themes
    cp -r ${theme}/themes/${iso_name}-live ${grub}/themes/
    cp ${data}/unicode.pf2 ${grub}
    cp -r ${theme}/{locales,tz} ${grub}

    local size=4M mnt="${mnt_dir}/efiboot" efi_img="$3/efi.img"
    msg2 "Creating fat image of %s ..." "${size}"
    truncate -s ${size} "${efi_img}"
    mkfs.fat -n MISO_EFI "${efi_img}" &>/dev/null
    prepare_dir "${mnt}"
    mount_img "${efi_img}" "${mnt}"
    prepare_dir ${mnt}/efi/boot
    msg2 "Building %s ..." "${img}"
    grub-mkimage -d ${grub}/${platform} -o ${mnt}/efi/boot/${img} -O ${platform} -p ${prefix} iso9660
    umount_img "${mnt}"
}
