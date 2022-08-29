// Copyright (c) Thundind
// SPDX-License-Identifier: Apache-2.0

module ThundindNft::ThundindNft {
    use std::string::String;
    use std::coin;
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::aptos_coin::AptosCoin;

    const ETHUNDIND_ONLY_OWNER: u64                 = 0;
    const ETHUNDIND_ALREADY_INITED: u64             = 1;
    const ETHUNDIND_PROJECT_STARTED: u64            = 2;
    const ETHUNDIND_PROJECT_NOT_EXIST: u64          = 3;
    const ETHUNDIND_PROJECT_COINTYPE_MISMATCH: u64  = 4;
    const ETHUNDIND_PROJECT_STATUS_ERROR: u64       = 5;
    const ETHUNDIND_PROJECT_OWNER_MISMATCH: u64     = 6;
    const ETHUNDIND_PROJECT_PROGRESS_UNKNOWN: u64   = 7;
    const ETHUNDIND_PROJECT_AMOUNT_OVER_BOUND: u64  = 8;
    const ETHUNDIND_PROJECT_PROGRESS_TIME_OVER: u64 = 9;
    const ETHUNDIND_PROJECT_PROGRESS_NOT_EXIST: u64 = 10;
    const ETHUNDIND_PROJECT_NOT_WHITE_LIST: u64     = 11;

    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    // life of project
    const PRJ_STATUS_STARTING: u8     = 0;
    const PRJ_STATUS_CONFIRMED: u8    = 1;
    const PRJ_STATUS_PUBLISHED: u8    = 2;
    const PRJ_STATUS_CLOSED: u8       = 3;
    // selling progress of project
    const PRJ_PROGRESS_WHITE_LIST: u8   = 1;
    const PRJ_PROGRESS_PRIVATE_SELL: u8 = 2;
    const PRJ_PROGRESS_PUBLIC_SELL: u8  = 3;

    struct PrjLaunchEvent has drop, store {
        id: u64,
        amount: u64,
    }

    struct PrjConfirmEvent has drop, store {
        id: u64,
    }

    struct PrjPublishEvent has drop, store {
        id: u64,
    }

    struct PrjBuyEvent has drop, store {
        buyer: address,
        buy_amount: u64,
        price: u64,
    }

    struct Progress has store {
        sell_amount: u64,     // want sell amount
        sold_amount: u64,     // real sold amount
        price: u64,           // 1 Token for xx Aptos
        start_time: u64,      // progress start time
        end_time: u64,        // progress end time
    }

    struct NftProject has store {
        prj_id: u64,                  // project id
        prj_owner: address,     // project launched by
        prj_name: String,             // project name
        prj_description: String,      // details of project
        total_presell_amount: u64, // total amount for launch

        white_list_progress: Progress,     // starting, published.....
        private_sell_progress: Progress,     // starting, published.....
        public_sell_progress: Progress,     // starting, published.....

        white_list: vector<address>,        // white list
        buyer_list: vector<address>,        // all buyers

        buy_events: EventHandle<PrjBuyEvent>,
    }

    struct AllProjects has key {
        projects: Table<u64, NftProject>,
        launch_events: EventHandle<PrjLaunchEvent>,
    }

    fun only_owner(sender: &signer): address {
        let owner = signer::address_of(sender);

        assert!(
            @ThundindNft == owner,
            error::invalid_argument(ETHUNDIND_ONLY_OWNER),
        );

        owner
    }

    fun empty_progress(amount: u64, price: u64, start: u64, end: u64): Progress {
        Progress {
            sell_amount: amount,
            sold_amount: 0,
            price,
            start_time: start,
            end_time: end,
        }
    }

    public entry fun init_system(sender: &signer) {
        let owner = only_owner(sender);

        assert!(
            !exists<AllProjects>(owner),
            error::already_exists(ETHUNDIND_ALREADY_INITED),
        );

        move_to(
            sender,
            AllProjects {
                projects: table::new(),
                launch_events: event::new_event_handle<PrjLaunchEvent>(sender),
            }
        );
    }

    /**
    * launch_project
    *   start a request for launching, invoked by team member of the project
    * for white-list, private-sell, public-sell progress, if no need, set all params to 0
    */
    public entry fun launch_project(
            sender: &signer,
            id: u64,
            owner: address,
            name: String,
            description: String,
            total_presell_amount: u64,
            wl_amount: u64, wl_price: u64, wl_start: u64, wl_end: u64, // white list params
            pv_amount: u64, pv_price: u64, pv_start: u64, pv_end: u64, // private sell params
            pb_amount: u64, pb_price: u64, pb_start: u64, pb_end: u64, // public sell params
    ) acquires AllProjects {
        only_owner(sender);

        let prj = NftProject {
            prj_id: id,
            prj_owner: owner,
            prj_name: name,
            prj_description: description,
            total_presell_amount,

            white_list_progress:   empty_progress(wl_amount, wl_price, wl_start, wl_end),     // white list progress
            private_sell_progress: empty_progress(pv_amount, pv_price, pv_start, pv_end),     // private sell progress
            public_sell_progress:  empty_progress(pb_amount, pb_price, pb_start, pb_end),     // public sell progress

            white_list: vector::empty(),        // white list
            buyer_list: vector::empty(),        // all buyers

            buy_events: event::new_event_handle<PrjBuyEvent>(sender),
        };

        let allPrjs = borrow_global_mut<AllProjects>(@ThundindNft);

        table::add(&mut allPrjs.projects, id, prj);

        event::emit_event<PrjLaunchEvent>(
            &mut allPrjs.launch_events,
            PrjLaunchEvent { id, amount: total_presell_amount },
        );
    }

    /**
    * white_list_project
    *   add white list to project by launcher
    */
    public entry fun add_white_list(
        sender: &signer,
        prj_id: u64,
        white_list: vector<address>
    )
        acquires AllProjects
    {
        let allPrjs = borrow_global_mut<AllProjects>(@ThundindNft);
        assert!(
            table::contains(&allPrjs.projects, prj_id),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
        let account = signer::address_of(sender);
        assert!(
            prj.prj_owner == account,
            error::invalid_argument(ETHUNDIND_PROJECT_OWNER_MISMATCH)
        );

        vector::append(&mut prj.white_list, white_list);
    }

    public fun do_exchange_nft_aptos(
        sender: &signer,
        prj: &mut NftProject,
        amount: u64
    ): bool
    {
        let now = timestamp::now_seconds();
        let is_wl_progress: bool = false;
        let progress: &mut Progress;

        if (prj.private_sell_progress.start_time <= now && now < prj.private_sell_progress.end_time) {
            progress = &mut prj.private_sell_progress;
        } else if (prj.public_sell_progress.start_time <= now && now < prj.public_sell_progress.end_time) {
            progress = &mut prj.public_sell_progress;
        } else if (prj.white_list_progress.start_time <= now && now < prj.white_list_progress.end_time) {
            progress = &mut prj.white_list_progress;
            is_wl_progress = true;
        } else {
            assert!(
                false,
                error::invalid_argument(ETHUNDIND_PROJECT_PROGRESS_UNKNOWN)
            );
            // FIXME: how to avoid "may be uninitialized" compiling error??
            progress = &mut prj.white_list_progress;
        };

        assert!(
            progress.sold_amount + amount <= progress.sell_amount,
            error::invalid_argument(ETHUNDIND_PROJECT_AMOUNT_OVER_BOUND)
        );

        progress.sold_amount = progress.sold_amount + amount;

        let totalAptos = progress.price * amount;
        coin::transfer<AptosCoin>(sender, prj.prj_owner, totalAptos);

        event::emit_event<PrjBuyEvent>(
            &mut prj.buy_events,
            PrjBuyEvent {
                buyer: signer::address_of(sender),
                price: progress.price,
                buy_amount: amount
            }
        );

        is_wl_progress
    }

    // user buy with white list
    public entry fun white_list_buy_project<CoinType>(
        sender: &signer,
        prj_id: u64,
        amount: u64
    )
        acquires AllProjects
    {

        let allPrjs = borrow_global_mut<AllProjects>(@ThundindNft);
        assert!(
            table::contains(&allPrjs.projects, prj_id),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
        let is_wl = do_exchange_nft_aptos(sender, prj, amount);
        if (is_wl) {
            let buyer = signer::address_of(sender);
            assert!(
                vector::contains(&prj.white_list, &buyer),
                error::invalid_argument(ETHUNDIND_PROJECT_NOT_WHITE_LIST)
            );
        };
    }

}
