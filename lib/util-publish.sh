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

#get_project(){
#    local project
#    case "$1" in
#        'community') project='manjarolinux-community' ;;
#        'manjaro') project='manjarolinux' ;;
#        'sonar') project='sonargnulinux' ;;
#        # manjarotest
#        # manjarotest-community
#    esac
#    echo ${project}
#}

create_release(){
    msg "Create release (%s) ..." "${target_dir}"
    rsync ${rsync_args[*]} /dev/null ${url}/${profile}/
    rsync ${rsync_args[*]} /dev/null ${url}/${target_dir}/
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
    msg "Done (%s)" "${target_dir}"
}

get_edition(){
    local result=$(find ${run_dir} -maxdepth 2 -name "${profile}") path
    [[ -z $result ]] && die "%s is not a valid profile or build list!" "${profile}"
    path=${result%/*}
    echo ${path##*/}
}

connect(){
    local home="/home/frs/project"
    echo "${account},${project}@frs.${host}:${home}/${project}"
}

gen_webseed(){
    local webseed seed="$1"
    for mirror in ${iso_mirrors[@]};do
        webseed=${webseed:-}${webseed:+,}"http://${mirror}.dl.${seed}"
    done
    echo ${webseed}
}

make_torrent(){
    rm ${src_dir}/*.iso.torrent

    for iso in $(ls ${src_dir}/*.iso);do

        local seed=${host}/project/${project}/${target_dir}/${iso##*/}
        local mktorrent_args=(-c "${torrent_meta}" -v -p -l ${piece_size} -a ${tracker_url} -w $(gen_webseed ${seed}))

        msg2 "Creating (%s) ..." "${iso##*/}.torrent"
        mktorrent ${mktorrent_args[*]} -o ${iso}.torrent ${iso}
    done
}

prepare_transfer(){
    profile="$1"
    edition=$(get_edition)
    url=$(connect)

    target_dir="${profile}/${dist_release}"
    src_dir="${run_dir}/${edition}/${target_dir}"
    ${torrent} && make_torrent
}

sync_dir(){
    prepare_transfer "$1"
    if ${release} && ! ${exists};then
        create_release
        exists=true
    fi
    msg "Start upload [%s] --> [${project}] ..." "${profile}"
    rsync ${rsync_args[*]} ${src_dir}/ ${url}/${target_dir}/
    msg "Done upload [%s]" "$1"
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}
