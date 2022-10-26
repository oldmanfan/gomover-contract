#! /bin/bash

# module='0x1ceca33cf2ffa0d5daf903c098711c98e3fd9a6690bc36c914c347ba1878adf2'
# prj_owner='0x1ceca33cf2ffa0d5daf903c098711c98e3fd9a6690bc36c914c347ba1878adf2'

module='0x5d0a5135955a3d8e364f62420bf0c5fb52326a53b00f5e67b62817d648b2559b'
prj_owner='0x5d0a5135955a3d8e364f62420bf0c5fb52326a53b00f5e67b62817d648b2559b'

# prj_id=115
# message='string:this is user claimable project'

function launch_project() {
    prj_id=$1
    start=$2
    message=$3
    symbol=$4

    (( wl_start = start ))
    (( wl_end = wl_start + 86400*3 ))
    (( pv_end = wl_end + 86400*3 ))
    (( pb_end = pv_end + 86400*3 ))
    (( claimable_time = pb_end + 86400*3 ))

    aptos move run --function-id ${module}::ThundindNft::launch_project --profile devnet --assume-yes \
    --args u64:${prj_id} \
    address:${prj_owner} \
    "${symbol}" \
    "${message}" \
    u64:1200 \
    u64:400 u64:10 u64:${wl_start} u64:${wl_end} u64:20 \
    u64:400 u64:15 u64:${wl_end} u64:${pv_end} u64:20 \
    u64:400 u64:20 u64:${pv_end} u64:${pb_end} u64:20
}

now=$(date +%s)

(( notstart = now + 86400 * 3 ))
launch_project 111 ${notstart} 'string:this project is not started' 'string:DODO'

(( inwl = now ))
launch_project 112 ${inwl} 'string:this project is in white list stage' 'string:APE'

(( inpv = now - 86400 * 3 ))
launch_project 113 ${inpv} 'string:this project is in private sell stage' 'string:PUNK'

(( inpb = now - 86400 * 2 * 3))
launch_project 114 ${inpb} 'string:this project is in public sell stage' 'string:MONKEY'

(( finished = now - 86400 * 3 * 3))
launch_project 115 ${finished} 'string:this project is finished and in claimable stage' 'string:TIGER'
