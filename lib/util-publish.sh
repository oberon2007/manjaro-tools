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
    local result=$(find ${run_dir} -maxdepth 3 -name "${profile}") path
    [[ -z $result ]] && die "%s is not a valid profile or build list!" "${profile}"
    path=${result%/*}
    path=${path%/*}
    echo ${path##*/}
}

connect(){
    local home="/home/frs/project"
    echo "${account},${project}@frs.${host}:${home}/${profile}"
}

gen_webseed(){
    local webseed seed="$1"
    local mirrors=('heanet' 'jaist' 'netcologne' 'iweb' 'kent')
    for m in ${mirrors[@]};do
        webseed=${webseed:-}${webseed:+,}"http://${m}.dl.${seed}"
    done
    echo ${webseed}
}

make_torrent(){
    rm ${src_dir}/*.iso.torrent
    for iso in $(ls ${src_dir}/*.iso);do

        local seed=${host}/project/${project}/${target_dir}/${iso}
        local mktorrent_args=(-v -p -l ${piece_size} -a ${tracker_url} -w $(gen_webseed ${seed}))

        msg2 "Creating (%s) ..." "${iso}.torrent"
        mktorrent ${mktorrent_args[*]} -o ${src_dir}/${iso}.torrent ${src_dir}/${iso}
    done
}

prepare_transfer(){
    edition=$(get_edition)
    url=$(connect)

    target_dir="${profile}/${dist_release}"
    src_dir="${run_dir}/${edition}/${target_dir}"
    ${torrent} && make_torrent
}

sync_dir(){
    profile="$1"
    prepare_transfer "${profile}"
    if ${release} && ! ${exists};then
        create_release
        exists=true
    fi
    msg "Start upload [%s] --> [${project}] ..." "${profile}"
    rsync ${rsync_args[*]} ${src_dir}/ ${url}/${target_dir}/
    msg "Done upload [%s]" "${profile}"
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}
