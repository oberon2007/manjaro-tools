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


get_rel_dir(){
    [[ ${project} == 'manjarotest' ]] && rel_dir="${dist_release}" || rel_dir="${dev_cycle}/${dist_release}"
    echo "${rel_dir}"
}

create_release(){
    rel_dir=$(get_rel_dir)
    msg "Create release (%s) ..." "${rel_dir}"
    rsync ${rsync_args[*]} /dev/null ${url}/${rel_dir}/
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
    msg "Done (%s)" "${rel_dir}"
}

get_edition(){
    local result=$(find ${run_dir} -maxdepth 3 -name "$1") path
    [[ -z $result ]] && die "%s is not a valid profile or build list!" "$1"
    path=${result%/*}
    path=${path%/*}
    echo ${path##*/}
}

check_dev_cycle(){
    if ! $(is_valid_dev_cycle ${dev_cycle}); then
        die "%s is not a valid development cycle!" "${dev_cycle}"
    fi
}

connect(){
    local home="/home/frs/project"
    echo "${account},$1@frs.${host}:${home}/$1"
}

prepare_transfer(){
    local edition=$(get_edition $1)
    project=$(get_project "${edition}")
    url=$(connect "${project}")
    src_dir="${run_dir}/${edition}/${dist_release}/$1"
    target_dir=$(get_rel_dir)/$1
}

sync_dir(){
    prepare_transfer "$1"
    if ${release} && ! ${exists};then
        create_release
        exists=true
    fi
    msg "Start upload [%s] --> [${project}] ..." "$1"
    rsync ${rsync_args[*]} ${src_dir}/ ${url}/${target_dir}/
    msg "Done upload [%s]" "$1"
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}
