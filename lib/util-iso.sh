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

import ${LIBDIR}/util-iso-image.sh
import ${LIBDIR}/util-iso-boot.sh
import ${LIBDIR}/util-yaml.sh

error_function() {
    if [[ -p $logpipe ]]; then
        rm "$logpipe"
    fi
    # first exit all subshells, then print the error
    if (( ! BASH_SUBSHELL )); then
        error "A failure occurred in %s()." "$1"
        plain "Aborting..."
    fi
    umount_fs
    umount_img
    exit 2
}

# $1: function
run_log(){
    local func="$1"
    local tmpfile=${tmp_dir}/$func.ansi.log logfile=${log_dir}/$(gen_iso_fn).$func.log
    logpipe=$(mktemp -u "${tmp_dir}/$func.pipe.XXXXXXXX")
    mkfifo "$logpipe"
    tee "$tmpfile" < "$logpipe" &
    local teepid=$!
    $func &> "$logpipe"
    wait $teepid
    rm "$logpipe"
    cat $tmpfile | perl -pe 's/\e\[?.*?[\@-~]//g' > $logfile
    rm "$tmpfile"
}

run_safe() {
    local restoretrap func="$1"
    set -e
    set -E
    restoretrap=$(trap -p ERR)
    trap 'error_function $func' ERR

    if ${verbose};then
        run_log "$func"
    else
        "$func"
    fi

    eval $restoretrap
    set +E
    set +e
}

trap_exit() {
    local sig=$1; shift
    error "$@"
    umount_fs
    trap -- "$sig"
    kill "-$sig" "$$"
}

make_sig () {
    msg2 "Creating signature file..."
    cd "$1"
    user_own "$1"
    su ${OWNER} -c "gpg --detach-sign --default-key ${gpgkey} $2.sfs"
    chown -R root "$1"
    cd ${OLDPWD}
}

# $1: file
make_checksum(){
    msg2 "Creating md5sum ..."
    cd $1
    md5sum $2.sfs > $2.md5
    cd ${OLDPWD}
}

# $1: image path
make_sfs() {
    local src="$1"
    if [[ ! -e "${src}" ]]; then
        error "The path %s does not exist" "${src}"
        retrun 1
    fi
    local timer=$(get_timer) dest=${iso_root}/${iso_name}/${target_arch}
    local name=${1##*/}
    local sfs="${dest}/${name}.sfs"
    mkdir -p ${dest}
    msg "Generating SquashFS image for %s" "${src}"
    if [[ -f "${sfs}" ]]; then
        local has_changed_dir=$(find ${src} -newer ${sfs})
        msg2 "Possible changes for %s ..." "${src}"  >> ${tmp_dir}/buildiso.debug
        msg2 "%s" "${has_changed_dir}" >> ${tmp_dir}/buildiso.debug
        if [[ -n "${has_changed_dir}" ]]; then
            msg2 "SquashFS image %s is not up to date, rebuilding..." "${sfs}"
            rm "${sfs}"
        else
            msg2 "SquashFS image %s is up to date, skipping." "${sfs}"
            return
        fi
    fi

    if ${persist};then
        local size=32G
        local mnt="${mnt_dir}/${name}"
        msg2 "Creating ext4 image of %s ..." "${size}"
        truncate -s ${size} "${src}.img"
        local ext4_args=()
        ${verbose} && ext4_args+=(-q)
        ext4_args+=(-O ^has_journal,^resize_inode -E lazy_itable_init=0 -m 0)
        mkfs.ext4 ${ext4_args[@]} -F "${src}.img" &>/dev/null
        tune2fs -c 0 -i 0 "${src}.img" &> /dev/null
        mount_img "${work_dir}/${name}.img" "${mnt}"
        msg2 "Copying %s ..." "${src}/"
        cp -aT "${src}/" "${mnt}/"
        umount_img "${mnt}"

    fi

    msg2 "Creating SquashFS image, this may take some time..."
    local used_kernel=${kernel:5:1} mksfs_args=()
    if ${persist};then
        mksfs_args+=(${work_dir}/${name}.img)
    else
        mksfs_args+=(${src})
    fi

    mksfs_args+=(${sfs} -noappend)

    local highcomp="-b 256K -Xbcj x86" comp='xz'

    if [[ "${name}" == "mhwdfs" && ${used_kernel} < "4" ]]; then
        mksfs_args+=(-comp lz4)
    else
        mksfs_args+=(-comp ${comp} ${highcomp})
    fi
    if ${verbose};then
        mksquashfs "${mksfs_args[@]}" >/dev/null
    else
        mksquashfs "${mksfs_args[@]}"
    fi
    make_checksum "${dest}" "${name}"
    ${persist} && rm "${src}.img"

    if [[ -n ${gpgkey} ]];then
        make_sig "${dest}" "${name}"
    fi

    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}

assemble_iso(){
    msg "Creating ISO image..."
    local iso_publisher="$(get_osname) <$(get_disturl)>" \
        iso_app_id="$(get_osname) Live/Rescue CD" \
        mod_date=$(date -u +%Y-%m-%d-%H-%M-%S-00  | sed -e s/-//g)

    xorriso -as mkisofs \
        --modification-date=${mod_date} \
        --protective-msdos-label \
        -volid "${iso_label}" \
        -appid "${iso_app_id}" \
        -publisher "${iso_publisher}" \
        -preparer "Prepared by manjaro-tools/${0##*/}" \
        -r -graft-points -no-pad \
        --sort-weight 0 / \
        --sort-weight 1 /boot \
        --grub2-mbr ${iso_root}/boot/grub/i386-pc/boot_hybrid.img \
        -partition_offset 16 \
        -b boot/grub/i386-pc/eltorito.img \
        -c boot.catalog \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
        -eltorito-alt-boot \
        -append_partition 2 0xef ${iso_root}/efi.img \
        -e --interval:appended_partition_2:all:: \
        -no-emul-boot \
        -iso-level 3 \
        -o ${iso_dir}/${iso_file} \
        ${iso_root}/

#         arg to add with xorriso-1.4.7
#         -iso_mbr_part_type 0x00
}

# Build ISO
make_iso() {
    msg "Start [Build ISO]"
    touch "${iso_root}/.miso"
    for sfs_dir in $(find "${work_dir}" -maxdepth 1 -type d); do
        if [[ "${sfs_dir}" != "${work_dir}" ]]; then
            make_sfs "${sfs_dir}"
        fi
    done

    msg "Making bootable image"
    # Sanity checks
    [[ ! -d "${iso_root}" ]] && return 1
    if [[ -f "${iso_dir}/${iso_file}" ]]; then
        msg2 "Removing existing bootable image..."
        rm -rf "${iso_dir}/${iso_file}"
    fi
    assemble_iso
    msg "Done [Build ISO]"
}

gen_iso_fn(){
    local vars=() name
    vars+=("${iso_name}")
    if ! ${chrootcfg};then
        [[ -n ${profile} ]] && vars+=("${profile}")
    fi
    [[ ${initsys} == 'openrc' ]] && vars+=("${initsys}")
    vars+=("${dist_release}")
    vars+=("${target_branch}")

    ! [[ ${full_iso} ]] && vars+=("minimal")

    vars+=("${target_arch}")
    for n in ${vars[@]};do
        name=${name:-}${name:+-}${n}
    done
    echo $name
}

reset_pac_conf(){
    info "Restoring [%s/etc/pacman.conf] ..." "$1"
    sed -e 's|^.*HoldPkg.*|HoldPkg      = pacman glibc manjaro-system|' \
        -e "s|^.*#CheckSpace|CheckSpace|" \
        -i "$1/etc/pacman.conf"
}

# Base installation (rootfs)
make_image_root() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [Base installation] (rootfs)"
        local path="${work_dir}/rootfs"
        mkdir -p ${path}

        chroot_create "${path}" "${packages}" || die

        pacman -Qr "${path}" > "${path}/rootfs-pkgs.txt"
        copy_overlay "${profile_dir}/root-overlay" "${path}"

        reset_pac_conf "${path}"

        configure_lsb "${path}"

        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [Base installation] (rootfs)"
    fi
}

make_image_desktop() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [Desktop installation] (desktopfs)"
        local path="${work_dir}/desktopfs"
        mkdir -p ${path}

        mount_fs_root "${path}"

        chroot_create "${path}" "${packages}"

        pacman -Qr "${path}" > "${path}/desktopfs-pkgs.txt"
        cp "${path}/desktopfs-pkgs.txt" ${iso_dir}/$(gen_iso_fn)-pkgs.txt
        [[ -e ${profile_dir}/desktop-overlay ]] && copy_overlay "${profile_dir}/desktop-overlay" "${path}"

        reset_pac_conf "${path}"

        umount_fs
        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [Desktop installation] (desktopfs)"
    fi
}

mount_fs_select(){
    if [[ -f "${packages_desktop}" ]]; then
        mount_fs_desktop "$1"
    else
        mount_fs_root "$1"
    fi
}

make_image_live() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [Live installation] (livefs)"
        local path="${work_dir}/livefs"
        mkdir -p ${path}

        mount_fs_select "${path}"

        chroot_create "${path}" "${packages}"

        pacman -Qr "${path}" > "${path}/livefs-pkgs.txt"
        copy_overlay "${profile_dir}/live-overlay" "${path}"
        configure_live_image "${path}"

        reset_pac_conf "${path}"

        umount_fs

        # Clean up GnuPG keys
        rm -rf "${path}/etc/pacman.d/gnupg"
        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [Live installation] (livefs)"
    fi
}

make_image_mhwd() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [drivers repository] (mhwdfs)"
        local path="${work_dir}/mhwdfs"
        mkdir -p ${path}${mhwd_repo}

        mount_fs_select "${path}"

        reset_pac_conf "${path}"

        copy_from_cache "${path}" "${packages}"

        if [[ -n "${packages_cleanup}" ]]; then
            for mhwd_clean in ${packages_cleanup}; do
                rm ${path}${mhwd_repo}/${mhwd_clean}
            done
        fi
        cp ${DATADIR}/pacman-mhwd.conf ${path}/opt
        make_repo "${path}"
        configure_mhwd_drivers "${path}"

        umount_fs
        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [drivers repository] (mhwdfs)"
    fi
}

make_image_boot() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [/iso/boot]"
        local boot="${iso_root}/boot"

        mkdir -p ${boot}

        cp ${work_dir}/rootfs/boot/vmlinuz* ${boot}/vmlinuz-${target_arch}

        local path="${work_dir}/bootfs"
        mkdir -p ${path}

        if [[ -f "${packages_desktop}" ]]; then
            mount_fs_live "${path}"
        else
            mount_fs_net "${path}"
        fi

        prepare_initcpio "${path}"
        prepare_initramfs "${path}"

        cp ${path}/boot/initramfs.img ${boot}/initramfs-${target_arch}.img
        prepare_boot_extras "${path}" "${boot}"

        umount_fs

        rm -R ${path}
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [/iso/boot]"
    fi
}

configure_grub(){
    local default_args="misobasedir=${iso_name} misolabel=${iso_label}" \
        boot_args=('quiet')
    [[ ${initsys} == 'systemd' ]] && boot_args+=('systemd.show_status=1')

    sed -e "s|@DIST_NAME@|${dist_name}|g" \
        -e "s|@ARCH@|${target_arch}|g" \
        -e "s|@DEFAULT_ARGS@|${default_args}|g" \
        -e "s|@BOOT_ARGS@|${boot_args[*]}|g" \
        -e "s|@PROFILE@|${profile}|g" \
        -i $1
}

configure_grub_theme(){
    sed -e "s|@ISO_NAME@|${iso_name}|" -i "$1"
}

make_grub(){
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [/iso/boot/grub]"

        local path="${work_dir}/livefs"

        prepare_grub "${path}" "${iso_root}"

        configure_grub "${iso_root}/boot/grub/kernels.cfg"
        configure_grub_theme "${iso_root}/boot/grub/variable.cfg"

        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [/iso/boot/grub]"
    fi
}

check_requirements(){
    [[ -f ${run_dir}/repo_info ]] || die "%s is not a valid iso profiles directory!" "${run_dir}"
    if ! $(is_valid_arch_iso ${target_arch});then
        die "%s is not a valid arch!" "${target_arch}"
    fi
    if ! $(is_valid_branch ${target_branch});then
        die "%s is not a valid branch!" "${target_branch}"
    fi

    if ! is_valid_init "${initsys}";then
        die "%s is not a valid init system!" "${initsys}"
    fi

    local host_kernel=$(uname -r)
    if [[ ${host_kernel%%*.} < "4" ]];then
        die "The host kernel must be version>=4.0!"
    fi
}

compress_images(){
    local timer=$(get_timer)
    run_safe "make_iso"
    user_own "${cache_dir_iso}" "-R"
    show_elapsed_time "${FUNCNAME}" "${timer}"
}

prepare_images(){
    local timer=$(get_timer)
    load_pkgs "${profile_dir}/Packages-Root"
    run_safe "make_image_root"
    if [[ -f "${packages_desktop}" ]] ; then
        load_pkgs "${packages_desktop}"
        run_safe "make_image_desktop"
    fi
    if [[ -f ${profile_dir}/Packages-Live ]]; then
        load_pkgs "${profile_dir}/Packages-Live"
        run_safe "make_image_live"
    fi
    if [[ -f ${packages_mhwd} ]] ; then
        load_pkgs "${packages_mhwd}"
        run_safe "make_image_mhwd"
    fi
    run_safe "make_image_boot"
    run_safe "make_grub"

    show_elapsed_time "${FUNCNAME}" "${timer}"
}

archive_logs(){
    local name=$(gen_iso_fn) ext=log.tar.xz src=${tmp_dir}/archives.list
    find ${log_dir} -maxdepth 1 -name "$name*.log" -printf "%f\n" > $src
    msg2 "Archiving log files [%s] ..." "$name.$ext"
    tar -cJf ${log_dir}/$name.$ext -C ${log_dir} -T $src
    msg2 "Cleaning log files ..."
    find ${log_dir} -maxdepth 1 -name "$name*.log" -delete
}

make_profile(){
    msg "Start building [%s]" "${profile}"
    if ${clean_first};then
        chroot_clean "${chroots_iso}/${profile}/${target_arch}"

        local unused_arch=''
        case ${target_arch} in
            i686) unused_arch='x86_64' ;;
            x86_64) unused_arch='i686' ;;
        esac
        if [[ -d "${chroots_iso}/${profile}/${unused_arch}" ]];then
            chroot_clean "${chroots_iso}/${profile}/${unused_arch}"
        fi
        clean_iso_root "${iso_root}"
    fi

    if ${iso_only}; then
        [[ ! -d ${work_dir} ]] && die "Create images: buildiso -p %s -x" "${profile}"
        compress_images
        ${verbose} && archive_logs
        exit 1
    fi
    if ${images_only}; then
        prepare_images
        ${verbose} && archive_logs
        warning "Continue compress: buildiso -p %s -zc ..." "${profile}"
        exit 1
    else
        prepare_images
        compress_images
        ${verbose} && archive_logs
    fi
    reset_profile
    msg "Finished building [%s]" "${profile}"
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}

get_pacman_conf(){
    local user_conf=${profile_dir}/user-repos.conf pac_arch='default' conf
    [[ "${target_arch}" == 'x86_64' ]] && pac_arch='multilib'
    if [[ -f ${user_conf} ]];then
        info "detected: %s" "user-repos.conf"
        check_user_repos_conf "${user_conf}"
        conf=${tmp_dir}/custom-pacman.conf
        cat ${DATADIR}/pacman-$pac_arch.conf ${user_conf} > "$conf"
    else
        conf="${DATADIR}/pacman-$pac_arch.conf"
    fi
    echo "$conf"
}

load_profile(){
    conf="$1/profile.conf"

    info "Profile: [%s]" "${profile}"

    load_profile_config "$conf"

    pacman_conf=$(get_pacman_conf)

    mirrors_conf=$(get_pac_mirrors_conf "${target_branch}")

    iso_file=$(gen_iso_fn).iso

    mkchroot_args+=(-C ${pacman_conf} -S ${mirrors_conf} -B "${build_mirror}/${target_branch}" -K)
    work_dir=${chroots_iso}/${profile}/${target_arch}

    iso_dir="${cache_dir_iso}/${edition}/${profile}/${dist_release}"

    iso_root=${chroots_iso}/${profile}/iso
    mnt_dir=${chroots_iso}/${profile}/mnt
    prepare_dir "${mnt_dir}"

    prepare_dir "${iso_dir}"
    user_own "${cache_dir_iso}" "-R"
}

prepare_profile(){
    profile=$1
    edition=$(get_edition ${profile})
    profile_dir=${run_dir}/${edition}/${profile}
    check_profile "${profile_dir}"
    load_profile "${profile_dir}"
}

build(){
    prepare_profile "$1"
    make_profile
}
