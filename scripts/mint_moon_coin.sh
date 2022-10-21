#! /bin/bash

prj_id=$1

module='0xb5f4a19c3e48a48779309c0df7a9d7671d88c3b2b1721ddd1505317bd5b7e64f'
prj_owner='0x5d0a5135955a3d8e364f62420bf0c5fb52326a53b00f5e67b62817d648b2559b'
# step register projecter to accept moon coin
aptos move run --function-id 0x1::managed_coin::register --type-args ${module}::moon_coin::MoonCoin --profile remotep --assume-yes --estimate-max-gas
# aptos move run --function-id 0x1::managed_coin::register --type-args ${module}::moon_coin::MoonCoin --profile remotep --assume-yes

# mint MOON to projecter
aptos move run --function-id 0x1::managed_coin::mint --args address:${prj_owner} u64:150000 --type-args ${module}::moon_coin::MoonCoin --profile remote --assume-yes --estimate-max-gas

# stake coin
aptos move run --function-id ${module}::ThundindCoin::stake_coin --args u64:${prj_id} --type-args ${module}::moon_coin::MoonCoin --profile remotep --assume-yes --estimate-max-gas