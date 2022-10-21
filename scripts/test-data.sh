#! /bin/bash

owner='0x2ed9c59209456b2064f62ed5e14093bf19cddc52f4c855e1efce406446ec7155'
user=''
launcher='0x913cc40d9cd60207fc004c59176f577c9e4e0fdde1fe0cfcfa55b4d3852477a0'

cmd_param_local_owner='--profile default --estimate-max-gas'
cmd_param_local_user='--profile buyer --estimate-max-gas'
cmd_param_local_launcher='--profile projecter --estimate-max-gas'

cmd_param_remote_owner='--profile remote'
cmd_param_remote_user='--profile remoteb'
cmd_param_remote_launcher='--profile remotep'

cmd_param_owner=${cmd_param_local_owner}
cmd_param_user=${cmd_param_local_user}
cmd_param_launcher=${cmd_param_local_launcher}

if [ x"remote" == $1 ]; then
    cmd_param_owner=${cmd_param_remote_owner}
    cmd_param_user=${cmd_param_remote_user}
    cmd_param_launcher=${cmd_param_remote_launcher}
fi


function start_project() {
    prj_id=$1
    prj_owner=$2
    wl_start=$3
    message=$4
    auto_buy=$5

    (( wl_end = wl_start + 86400 ))
    (( pv_end = wl_end + 86400 ))
    (( pb_end = pv_end + 86400 ))

    # 启动一个系统
    aptos move run --function-id ${owner}::ThundindCoin::launch_project ${cmd_param_owner} \
    --args u64:${prj_id} \
    address:${prj_owner} \
    string:${message} \
    string:ThisIsTestProject \
    string:TokenDistribution \
    string:InittialMarketCap \
    u64:1200 \
    u64:500 \
    u64:400 u64:10 u64:${wl_start} u64:${wl_end} u64:10 \
    u64:400 u64:15 u64:${wl_end} u64:${pv_end} u64:10 \
    u64:400 u64:20 u64:${pv_end} u64:${pb_end} u64:10 \
    --type-args ${owner}::moon_coin::MoonCoin

    if [ $auto_buy -eq 1]; then
        # 质押代币
        aptos move run --function-id ${owner}::ThundindCoin::stake_coin --args u64:${prj_id} --type-args ${owner}::moon_coin::MoonCoin ${cmd_param_launcher}

        # 购买
        aptos move run --function-id ${owner}::ThundindCoin::buy_coin --args u64:${prj_id} u64:10 --type-args ${owner}::moon_coin::MoonCoin ${cmd_param_user}
    fi
}

# step register projecter to accept moon coin
aptos move run --function-id 0x1::managed_coin::register --type-args ${owner}::moon_coin::MoonCoin ${cmd_param_launcher}

# mint MOON to projecter
aptos move run --function-id 0x1::managed_coin::mint --args address:${launcher} u64:150000 --type-args ${owner}::moon_coin::MoonCoin ${cmd_param_owner}

# 初始化合约系统
aptos move run --function-id default::ThundindCoin::init_system ${cmd_param_owner}

now=$(date +%s)

(( not_start = now + 86400 * 4 ))
start_project 100 ${launcher} ${not_start} 'this is a not a start project'

start_project 101 ${launcher} ${now} 'this is a white list stage project'

(( pv_start = now - 86400 ))
start_project 102 ${launcher} ${pv_start} 'this is a private sell stage project'

(( pb_start = now - 86400 * 2 ))
start_project 103 ${launcher} ${pb_start} 'this is a public sell stage project'

(( finished_prj = now - 86400 * 3 ))
start_project 104 ${launcher} ${finished_prj} 'this is a finished project'