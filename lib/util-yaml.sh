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

load_desktop_map(){
    local _space="s| ||g" _clean=':a;N;$!ba;s/\n/ /g' _com_rm="s|#.*||g" \
        file=${DATADIR}/desktop.map
    local desktop_map=$(sed "$_com_rm" "$file" \
            | sed "$_space" \
            | sed "$_clean")
    echo ${desktop_map}
}

detect_desktop_env(){
    local xs=$1/usr/share/xsessions ex=$1/usr/bin key val map=( $(load_desktop_map) )
    default_desktop_file="none"
    default_desktop_executable="none"
    for item in "${map[@]}";do
        key=${item%:*}
        val=${item#*:}
        if [[ -f $xs/$key.desktop ]] && [[ -f $ex/$val ]];then
            default_desktop_file="$key"
            default_desktop_executable="$val"
        fi
    done
}

is_valid_de(){
    if [[ ${default_desktop_executable} != "none" ]] && \
    [[ ${default_desktop_file} != "none" ]]; then
        return 0
    else
        return 1
    fi
}

write_machineid_conf(){
    local conf="${modules_dir}/machineid.conf" switch='false'
    msg2 "Writing %s ..." "${conf##*/}"
    echo '---' > "$conf"
    [[ ${initsys} == 'systemd' ]] && switch='true'
    echo "systemd: ${switch}" >> $conf
    echo "dbus: true" >> $conf
    echo "symlink: true" >> $conf
}

write_finished_conf(){
    msg2 "Writing %s ..." "finished.conf"
    local conf="${modules_dir}/finished.conf" cmd="shutdown -r now"
    echo '---' > "$conf"
    echo 'restartNowEnabled: true' >> "$conf"
    echo 'restartNowChecked: false' >> "$conf"
    [[ ${initsys} == 'systemd' ]] && cmd="systemctl -i reboot"
    echo "restartNowCommand: \"${cmd}\"" >> "$conf"
}

get_preset(){
    local p=${tmp_dir}/${kernel}.preset kvmaj kvmin digit
    cp ${DATADIR}/linux.preset $p
    digit=${kernel##linux}
    kvmaj=${digit:0:1}
    kvmin=${digit:1}

    sed -e "s|@kvmaj@|$kvmaj|g" \
        -e "s|@kvmin@|$kvmin|g" \
        -e "s|@arch@|${target_arch}|g"\
        -i $p
    echo $p
}

write_bootloader_conf(){
    local conf="${modules_dir}/bootloader.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    source "$(get_preset)"
    echo '---' > "$conf"
    echo "efiBootLoader: \"${efi_boot_loader}\"" >> "$conf"
    echo "kernel: \"${ALL_kver#*/boot}\"" >> "$conf"
    echo "img: \"${default_image#*/boot}\"" >> "$conf"
    echo "fallback: \"${fallback_image#*/boot}\"" >> "$conf"
    echo 'timeout: "10"' >> "$conf"
    echo "kernelLine: \", with ${kernel}\"" >> "$conf"
    echo "fallbackKernelLine: \", with ${kernel} (fallback initramfs)\"" >> "$conf"
    echo 'grubInstall: "grub-install"' >> "$conf"
    echo 'grubMkconfig: "grub-mkconfig"' >> "$conf"
    echo 'grubCfg: "/boot/grub/grub.cfg"' >> "$conf"
    echo '#efiBootloaderId: "dirname"' >> "$conf"
}

write_servicescfg_conf(){
    local conf="${modules_dir}/servicescfg.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo '---' >  "$conf"
    echo '' >> "$conf"
    echo 'services:' >> "$conf"
    echo '    enabled:' >> "$conf"
    for s in ${enable_openrc[@]};do
        echo "      - name: $s" >> "$conf"
        echo '        runlevel: default' >> "$conf"
    done
    if [[ -n ${disable_openrc[@]} ]];then
        echo '    disabled:' >> "$conf"
        for s in ${disable_openrc[@]};do
            echo "      - name: $s" >> "$conf"
            echo '        runlevel: default' >> "$conf"
            echo '' >> "$conf"
        done
    fi
}

write_services_conf(){
    local conf="${modules_dir}/services.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo '---' >  "$conf"
    echo '' >> "$conf"
    echo 'services:' > "$conf"
    for s in ${enable_systemd[@]};do
        echo "    - name: $s" >> "$conf"
        echo '      mandatory: false' >> "$conf"
        echo '' >> "$conf"
    done
    echo 'targets:' >> "$conf"
    echo '    - name: "graphical"' >> "$conf"
    echo '      mandatory: true' >> "$conf"
    echo '' >> "$conf"
    echo 'disable:' >> "$conf"
    for s in ${disable_systemd[@]};do
        echo "    - name: $s" >> "$conf"
        echo '      mandatory: false' >> "$conf"
        echo '' >> "$conf"
    done
}

write_displaymanager_conf(){
    local conf="${modules_dir}/displaymanager.conf"
    if ${unpackfs} && ! ${netinstall};then
        msg2 "Writing %s ..." "${conf##*/}"
        echo "---" > "$conf"
        echo "displaymanagers:" >> "$conf"
        echo "  - ${displaymanager}" >> "$conf"
        echo '' >> "$conf"
        if $(is_valid_de); then
            echo "defaultDesktopEnvironment:" >> "$conf"
            echo "    executable: \"${default_desktop_executable}\"" >> "$conf"
            echo "    desktopFile: \"${default_desktop_file}\"" >> "$conf"
        fi
        echo '' >> "$conf"
        echo "basicSetup: false" >> "$conf"
    fi
}

write_initcpio_conf(){
    local conf="${modules_dir}/initcpio.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "kernel: ${kernel}" >> "$conf"
}

write_unpack_conf(){
    local conf="${modules_dir}/unpackfs.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "unpack:" >> "$conf"
    echo "    - source: \"/bootmnt/${iso_name}/${target_arch}/root-image.sqfs\"" >> "$conf"
    echo "      sourcefs: \"squashfs\"" >> "$conf"
    echo "      destination: \"\"" >> "$conf"
    if [[ -f "${packages_custom}" ]] ; then
        echo "    - source: \"/bootmnt/${iso_name}/${target_arch}/${profile}-image.sqfs\"" >> "$conf"
        echo "      sourcefs: \"squashfs\"" >> "$conf"
        echo "      destination: \"\"" >> "$conf"
    fi
}

write_users_conf(){
    local conf="${modules_dir}/users.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "defaultGroups:" >> "$conf"
    local IFS=','
    for g in ${addgroups[@]};do
        echo "    - $g" >> "$conf"
    done
    unset IFS
    echo "autologinGroup: autologin" >> "$conf"
    echo "sudoersGroup:   wheel" >> "$conf"
    echo "setRootPassword: true" >> "$conf"
}

write_packages_conf(){
    local conf="${modules_dir}/packages.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "backend: pacman" >> "$conf"
}

write_welcome_conf(){
    local conf="${modules_dir}/welcome.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf" >> "$conf"
    echo "showSupportUrl:         true" >> "$conf"
    echo "showKnownIssuesUrl:     true" >> "$conf"
    echo "showReleaseNotesUrl:    true" >> "$conf"
    echo '' >> "$conf"
    echo "requirements:" >> "$conf"
    echo "    requiredStorage:    5.5" >> "$conf"
    echo "    requiredRam:        1.0" >> "$conf"
    echo "    check:" >> "$conf"
    echo "      - storage" >> "$conf"
    echo "      - ram" >> "$conf"
    echo "      - power" >> "$conf"
    echo "      - internet" >> "$conf"
    echo "      - root" >> "$conf"
    echo "    required:" >> "$conf"
    echo "      - storage" >> "$conf"
    echo "      - ram" >> "$conf"
    echo "      - root" >> "$conf"
    if ${netinstall};then
        echo "      - internet" >> "$conf"
    fi
}

write_mhwdcfg_conf(){
    local conf="${modules_dir}/mhwdcfg.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "bus:" >> "$conf"
    echo "    - pci" >> "$conf"
    echo '' >> "$conf"
    echo "identifier:" >> "$conf"
    echo "    net:" >> "$conf"
    echo "      - 200" >> "$conf"
    echo "      - 280" >> "$conf"
    echo "    video:" >> "$conf"
    echo "      - 300" >> "$conf"
    echo "      - 302" >> "$conf"
    echo "      - 380" >> "$conf"
    echo '' >> "$conf"
    if ${nonfree_mhwd};then
        echo "driver: nonfree" >> "$conf"
    else
        echo "driver: free" >> "$conf"
    fi
    echo '' >> "$conf"
    if ${netinstall};then
        if ${unpackfs};then
            echo "local: true" >> "$conf"
        else
            echo "local: false" >> "$conf"
        fi
    else
        echo "local: true" >> "$conf"
    fi
    echo '' >> "$conf"
    echo 'repo: /opt/pacman-mhwd.conf' >> "$conf"
}

write_postcfg_conf(){
    local conf="${modules_dir}/postcfg.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "keyrings:" >> "$conf"
    echo "    - archlinux" >> "$conf"
    echo "    - manjaro" >> "$conf"
    if [[ -n ${smb_workgroup} ]];then
        echo "" >> "$conf"
        echo "samba:" >> "$conf"
        echo "    - workgroup:  ${smb_workgroup}" >> "$conf"
    fi
}

get_yaml(){
    local args=() ext="yaml" yaml
    if ${unpackfs};then
        args+=("hybrid")
    else
        args+=('netinstall')
    fi
    args+=("${initsys}")
    [[ ${edition} == 'sonar' ]] && args+=("${edition}")
    for arg in ${args[@]};do
        yaml=${yaml:-}${yaml:+-}${arg}
    done
    echo "${yaml}.${ext}"
}

write_netinstall_conf(){
    local conf="${modules_dir}/netinstall.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "groupsUrl: ${netgroups}/$(get_yaml)" >> "$conf"
}

write_plymouthcfg_conf(){
    local conf="${modules_dir}/plymouthcfg.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "plymouth_theme: ${plymouth_theme}" >> "$conf"
}

write_locale_conf(){
    local conf="${modules_dir}/locale.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "localeGenPath: /etc/locale.gen" >> "$conf"
    if ${geoip};then
        echo "geoipUrl: freegeoip.net" >> "$conf"
    else
        echo "region: Europe" >> "$conf"
        echo "zone: London" >> "$conf"
    fi
}

write_settings_conf(){
    local conf="$1/etc/calamares/settings.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "modules-search: [ local ]" >> "$conf"
    echo '' >> "$conf"
    echo "instances:" >> "$conf"
    echo '#    - id: owncloud' >> "$conf"
    echo '#      module: webview' >> "$conf"
    echo '#      config: owncloud.conf' >> "$conf"
    echo '' >> "$conf"
    echo "sequence:" >> "$conf"
    echo "    - show:" >> "$conf"
    echo "        - welcome" >> "$conf"
    echo "        - locale" >> "$conf"
    echo "        - keyboard" >> "$conf"
    echo "        - partition" >> "$conf"
    echo "        - users" >> "$conf"
    ${netinstall} && echo "        - netinstall" >> "$conf"
    echo "        - summary" >> "$conf"
    echo "    - exec:" >> "$conf"
    echo "        - partition" >> "$conf"
    echo "        - mount" >> "$conf"
    if ${netinstall};then
        if ${unpackfs};then
            echo "        - unpackfs" >> "$conf"
            echo "        - networkcfg" >> "$conf"
            echo "        - packages" >> "$conf"
        else
            echo "        - chrootcfg" >> "$conf"
            echo "        - networkcfg" >> "$conf"
        fi
    else
        echo "        - unpackfs" >> "$conf"
        echo "        - networkcfg" >> "$conf"
    fi
    echo "        - machineid" >> "$conf"
    echo "        - fstab" >> "$conf"
    echo "        - locale" >> "$conf"
    echo "        - keyboard" >> "$conf"
    echo "        - localecfg" >> "$conf"
    echo "        - luksopenswaphookcfg" >> "$conf"
    echo "        - luksbootkeyfile" >> "$conf"
    echo "        - plymouthcfg" >> "$conf"
    echo "        - initcpiocfg" >> "$conf"
    echo "        - initcpio" >> "$conf"
    echo "        - users" >> "$conf"
    echo "        - displaymanager" >> "$conf"
    echo "        - mhwdcfg" >> "$conf"
    echo "        - hwclock" >> "$conf"
    case ${initsys} in
        'systemd') echo "        - services" >> "$conf" ;;
        'openrc')  echo "        - servicescfg" >> "$conf" ;;
    esac
    echo "        - grubcfg" >> "$conf"
    echo "        - bootloader" >> "$conf"
    echo "        - postcfg" >> "$conf"
    echo "        - umount" >> "$conf"
    echo "    - show:" >> "$conf"
    echo "        - finished" >> "$conf"
    echo '' >> "$conf"
    echo "branding: ${iso_name}" >> "$conf"
    echo '' >> "$conf"
    echo "prompt-install: false" >> "$conf"
    echo '' >> "$conf"
    echo "dont-chroot: false" >> "$conf"
}

configure_calamares(){
    info "Configuring [Calamares]"

    modules_dir=$1/etc/calamares/modules

    mkdir -p ${modules_dir}

    write_settings_conf "$1"

    write_locale_conf

    write_welcome_conf

    if ${netinstall};then
        write_netinstall_conf
        write_packages_conf
    fi

    write_bootloader_conf

    write_mhwdcfg_conf

    write_unpack_conf

    write_displaymanager_conf

    write_initcpio_conf

    write_machineid_conf

    write_finished_conf

    write_plymouthcfg_conf

    write_postcfg_conf

    case ${initsys} in
        'systemd') write_services_conf ;;
        'openrc') write_servicescfg_conf ;;
    esac

    write_users_conf

    info "Done configuring [Calamares]"
}

check_yaml(){
    msg2 "Checking validity [%s] ..." "${1##*/}"
    local name=${1##*/} data=$1 schema
    case ${name##*.} in
        yaml)
            name=netgroups
#             data=$1
        ;;
        conf)
            name=${name%.conf}
#             data=${tmp_dir}/$name.yaml
#             cp $1 $data
        ;;
    esac
    schema=${DATADIR}/schemas/$name.schema.yaml
#     pykwalify -d $data -s $schema
    kwalify -lf $schema $data
}

write_calamares_yaml(){
    configure_calamares "${yaml_dir}"
    local yf
    if ${validate}; then
        for conf in "${yaml_dir}"/etc/calamares/modules/*.conf "${yaml_dir}"/etc/calamares/settings.conf; do
            check_yaml "$conf"
        done
	fi
}

write_netgroup_yaml(){
    msg2 "Writing %s ..." "${2##*/}"
    echo "---" > "$2"
    echo "- name: '$1'" >> "$2"
    echo "  description: '$1'" >> "$2"
    echo "  selected: false" >> "$2"
    echo "  hidden: false" >> "$2"
    echo "  packages:" >> "$2"
    for p in ${packages[@]};do
        echo "       - $p" >> "$2"
    done
	${validate} && check_yaml "$2"
}

write_pacman_group_yaml(){
    packages=$(pacman -Sgq "$1")
    prepare_dir "${cache_dir_netinstall}/pacman"
    write_netgroup_yaml "$1" "${cache_dir_netinstall}/pacman/$1.yaml"
    ${validate} && check_yaml "${cache_dir_netinstall}/pacman/$1.yaml"
    user_own "${cache_dir_netinstall}/pacman" "-R"
}

prepare_check(){
    profile=$1
    edition=$(get_edition ${profile})
    profile_dir=${run_dir}/${edition}/${profile}
    check_profile
    load_profile_config "${profile_dir}/profile.conf"

    yaml_dir=${cache_dir_netinstall}/${profile}/${target_arch}

    prepare_dir "${yaml_dir}"
    user_own "${yaml_dir}"
}

gen_fn(){
    echo "${yaml_dir}/$1-${target_arch}-${initsys}.yaml"
}

make_profile_yaml(){
    prepare_check "$1"
    load_pkgs "${profile_dir}/Packages-Root"
    write_netgroup_yaml "$1" "$(gen_fn "Packages-Root")"
    if [[ -f "${packages_custom}" ]]; then
        load_pkgs "${packages_custom}"
        write_netgroup_yaml "$1" "$(gen_fn "${packages_custom##*/}")"
    fi
    ${calamares} && write_calamares_yaml "$1"
    user_own "${cache_dir_netinstall}/$1" "-R"
    reset_profile
    unset yaml_dir
}
