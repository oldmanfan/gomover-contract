#! /bin/bash

module='0x119127901a5e5ce36fda205ed6df306117e067043efeda80ac423e8e8b816388'
prj_owner='0x119127901a5e5ce36fda205ed6df306117e067043efeda80ac423e8e8b816388'

# module='0x2ed9c59209456b2064f62ed5e14093bf19cddc52f4c855e1efce406446ec7155'
# prj_owner='0x5d0a5135955a3d8e364f62420bf0c5fb52326a53b00f5e67b62817d648b2559b'

# prj_id=115
# message='string:this is user claimable project'

function launch_project() {
    prj_id=$1
    start=$2
    message=$3

    (( wl_start = start ))
    (( wl_end = wl_start + 86400*3 ))
    (( pv_end = wl_end + 86400*3 ))
    (( pb_end = pv_end + 86400*3 ))
    (( claimable_time = pb_end + 86400*3 ))

    aptos move run --function-id ${module}::ThundindNft::launch_project --profile default --assume-yes \
    --args u64:${prj_id} \
    address:${prj_owner} \
    'string:INO Test Project' \
    "${message}" \
    u64:1200 \
    u64:400 u64:10 u64:${wl_start} u64:${wl_end} u64:20 \
    u64:400 u64:15 u64:${wl_end} u64:${pv_end} u64:20 \
    u64:400 u64:20 u64:${pv_end} u64:${pb_end} u64:20
}

now=$(date +%s)

(( notstart = now + 86400 * 3 ))
launch_project 111 ${notstart} 'string:this project is not started'

(( inwl = now ))
launch_project 112 ${inwl} 'string:this project is in white list stage'

(( inpv = now - 86400 * 3 ))
launch_project 113 ${inpv} 'string:this project is in private sell stage'

(( inpb = now - 86400 * 2 * 3))
launch_project 114 ${inpb} 'string:this project is in public sell stage'

(( finished = now - 86400 * 3 * 3))
launch_project 115 ${finished} 'string:this project is finished and in claimable stage'
