#! /bin/bash

prj_id=$1

module='0xb5f4a19c3e48a48779309c0df7a9d7671d88c3b2b1721ddd1505317bd5b7e64f'

# step register projecter to accept moon coin
aptos move run --function-id ${module}::ThundindCoin::buy_coin --args u64:${prj_id} u64:10 --type-args ${module}::moon_coin::MoonCoin --profile remoteb