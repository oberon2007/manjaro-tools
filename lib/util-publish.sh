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
    find ${src_dir} -type f -name "*.torrent" -delete

    if [[ -n $(find ${src_dir} -type f -name "*.iso") ]]; then
        for iso in $(ls ${src_dir}/*.iso);do
            local seed=${host}/project/${project}/${target_dir}/${iso##*/}
            local mktorrent_args=(-c "${torrent_meta}" -p -l ${piece_size} -a ${tracker_url} -w $(gen_webseed ${seed}))
            ${verbose} && mktorrent_args+=(-v)
            msg2 "Creating (%s) ..." "${iso##*/}.torrent"
            mktorrent ${mktorrent_args[*]} -o ${iso}.torrent ${iso}
        done
    fi
}

prepare_transfer(){
    profile="$1"
    edition=$(get_edition "${profile}")
    url=$(connect)

    target_dir="${project}/${dist_release}"
    src_dir="${run_dir}/${edition}/${profile}"
    ${torrent} && make_torrent
}

sync_dir(){
	cont=1
	max_cont=10
    prepare_transfer "$1"
    msg "Start upload [%s] --> [${project}/${dist_release}] ..." "${profile}"
    while [[ $cont -le $max_cont  ]]; do 
    rsync ${rsync_args[*]} ${src_dir}/ ${url}/
    	if [[ $? != 0 ]]; then
    		cont=$(($cont + 1))
    		msg "Failed to upload [%s] now try again: try $cont of $max_cont" "$1"
    		sleep 2
    	else
    		cont=$(($max_cont + 1))
    		msg "Done upload [%s]" "$1"
    		show_elapsed_time "${FUNCNAME}" "${timer_start}"
    	fi
    done
}
