// Copyright (c) Thundind
// SPDX-License-Identifier: Apache-2.0

module Thundind::ThundindNft {
    use std::string::String;
    use std::coin;
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_framework::account;
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
    const ETHUNDIND_OVER_BUYABLE_AMOUNT: u64        = 12;

    const STAGE_WHITE_LIST: u8 = 1;
    const STAGE_PRIVATE_SELL: u8 = 2;
    const STAGE_PUBLIC_SELL: u8 = 3;

    struct PrjLaunchEvent has drop, store {
        prj_id: u64,
    }

    struct PrjBuyEvent has drop, store {
        buyer: address,
        buy_amount: u64,
        price: u64,
    }

    struct Stage has store {
        selling_amount: u64,     // want sell amount
        sold_amount: u64,     // real sold amount
        price: u64,           // 1 Token for xx Aptos
        start_time: u64,      // progress start time
        end_time: u64,        // progress end time
        limit_per_account: u64, // limitation for each account
    }

    struct BoughtRecord has store {
        wl_amount: u64, // how many a user bought during white list stage.
        pv_amount: u64, //
        pb_amount: u64,
    }

    struct NftProject has store {
        prj_id: u64,                  // project id
        prj_owner: address,     // project launched by
        prj_name: String,             // project name
        prj_description: String,      // details of project
        total_presell_amount: u64, // total amount for launch

        white_list_stage: Stage,     // starting, published.....
        private_sell_stage: Stage,     // starting, published.....
        public_sell_stage: Stage,     // starting, published.....

        white_list: vector<address>,        // white list
        buyer_list: Table<address, BoughtRecord>,        // all buyers

        buy_events: EventHandle<PrjBuyEvent>,
    }

    struct AllProjects has key {
        projects: Table<u64, NftProject>,
        launch_events: EventHandle<PrjLaunchEvent>,
    }

    fun only_owner(sender: &signer): address {
        let owner = signer::address_of(sender);

        assert!(
            @Thundind == owner,
            error::invalid_argument(ETHUNDIND_ONLY_OWNER),
        );

        owner
    }

    fun make_stage(amount: u64, price: u64, start: u64, end: u64, limit: u64): Stage {
        Stage {
            selling_amount: amount,
            sold_amount: 0,
            price,
            start_time: start,
            end_time: end,
            limit_per_account: limit,
        }
    }

    public entry fun init_system(sender: &signer) {
        only_owner(sender);

        assert!(
            !exists<AllProjects>(@Thundind),
            error::already_exists(ETHUNDIND_ALREADY_INITED),
        );

        move_to(
            sender,
            AllProjects {
                projects: table::new(),
                launch_events: account::new_event_handle<PrjLaunchEvent>(sender),
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
            wl_amount: u64, wl_price: u64, wl_start: u64, wl_end: u64, wl_limit: u64,// white list params
            pv_amount: u64, pv_price: u64, pv_start: u64, pv_end: u64, pv_limit: u64,// private sell params
            pb_amount: u64, pb_price: u64, pb_start: u64, pb_end: u64, pb_limit: u64,// public sell params
    ) acquires AllProjects {
        only_owner(sender);

        assert!(
            total_presell_amount == wl_amount + pv_amount + pb_amount,
            error::invalid_argument(ETHUNDIND_PROJECT_AMOUNT_OVER_BOUND)
        );

        let prj = NftProject {
            prj_id: id,
            prj_owner: owner,
            prj_name: name,
            prj_description: description,
            total_presell_amount,

            white_list_stage:   make_stage(wl_amount, wl_price, wl_start, wl_end, wl_limit),     // white list progress
            private_sell_stage: make_stage(pv_amount, pv_price, pv_start, pv_end, pv_limit),     // private sell progress
            public_sell_stage:  make_stage(pb_amount, pb_price, pb_start, pb_end, pb_limit),     // public sell progress

            white_list: vector::empty(),        // white list
            buyer_list: table::new(),        // all buyers

            buy_events: account::new_event_handle<PrjBuyEvent>(sender),
        };

        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);

        table::add(&mut allPrjs.projects, id, prj);

        event::emit_event<PrjLaunchEvent>(
            &mut allPrjs.launch_events,
            PrjLaunchEvent { prj_id: id },
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
        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
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
    ): (u8, u64)
    {
        let now = timestamp::now_seconds();
        let in_stage: u8 = 0;
        let stage: &mut Stage;

        if (prj.private_sell_stage.start_time <= now && now < prj.private_sell_stage.end_time) {
            stage = &mut prj.private_sell_stage;
            in_stage = STAGE_PRIVATE_SELL;
        } else if (prj.public_sell_stage.start_time <= now && now < prj.public_sell_stage.end_time) {
            stage = &mut prj.public_sell_stage;
            in_stage = STAGE_PUBLIC_SELL;
        } else if (prj.white_list_stage.start_time <= now && now < prj.white_list_stage.end_time) {
            stage = &mut prj.white_list_stage;
            in_stage = STAGE_WHITE_LIST;
        } else {
            assert!(
                false,
                error::invalid_argument(ETHUNDIND_PROJECT_PROGRESS_UNKNOWN)
            );
            // FIXME: how to avoid "may be uninitialized" compiling error??
            stage = &mut prj.white_list_stage;
        };

        assert!(
            stage.sold_amount + amount <= stage.selling_amount,
            error::invalid_argument(ETHUNDIND_PROJECT_AMOUNT_OVER_BOUND)
        );

        stage.sold_amount = stage.sold_amount + amount;

        let totalAptos = stage.price * amount;
        coin::transfer<AptosCoin>(sender, prj.prj_owner, totalAptos);

        event::emit_event<PrjBuyEvent>(
            &mut prj.buy_events,
            PrjBuyEvent {
                buyer: signer::address_of(sender),
                price: stage.price,
                buy_amount: amount
            }
        );

        (in_stage, stage.limit_per_account)
    }

    // user buy with white list
    public entry fun buy_nft(
        sender: &signer,
        prj_id: u64,
        amount: u64
    )
        acquires AllProjects
    {

        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
        assert!(
            table::contains(&allPrjs.projects, prj_id),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
        let (in_stage, limit) = do_exchange_nft_aptos(sender, prj, amount);
        let buyer = signer::address_of(sender);
        if (in_stage == STAGE_WHITE_LIST) {
            assert!(
                vector::contains(&prj.white_list, &buyer),
                error::invalid_argument(ETHUNDIND_PROJECT_NOT_WHITE_LIST)
            );
        };

        assert!(
                amount <= limit,
                error::invalid_argument(ETHUNDIND_OVER_BUYABLE_AMOUNT)
        );

        if (table::contains(&prj.buyer_list, buyer)) {
            let record = table::borrow_mut(&mut prj.buyer_list, buyer);
            let total_bought: u64;
            if (in_stage == STAGE_PRIVATE_SELL) {
                record.pv_amount = record.pv_amount + amount;
                total_bought = record.pv_amount;
            } else if (in_stage == STAGE_PUBLIC_SELL) {
                record.pb_amount = record.pb_amount + amount;
                total_bought = record.pb_amount;
            } else {
                record.wl_amount = record.wl_amount + amount;
                total_bought = record.wl_amount;
            };

            assert!(
                total_bought <= limit,
                error::invalid_argument(ETHUNDIND_OVER_BUYABLE_AMOUNT)
            );
        } else {
            let record = BoughtRecord {
                pv_amount:  if (in_stage == STAGE_PRIVATE_SELL) amount else 0,
                pb_amount:  if (in_stage == STAGE_PUBLIC_SELL) amount else 0,
                wl_amount:  if (in_stage == STAGE_WHITE_LIST) amount else 0,
            };

            table::add(&mut prj.buyer_list, buyer, record);
        }
    }

    // ------------ unit test starts -------------------
    #[test_only]
    use aptos_framework::aptos_account;

    #[test_only]
    use std::string;

    #[test_only]
    use aptos_framework::aptos_coin;

    #[test(m_owner = @Thundind)]
    public fun t_init_system(m_owner: &signer) {
        aptos_account::create_account(signer::address_of(m_owner));
        init_system(m_owner);
    }

    #[test(m_owner = @Thundind, prj_owner = @0xAABB1)]
    public fun t_launch_project(m_owner: &signer, prj_owner: &signer) acquires AllProjects{
        t_init_system(m_owner);

        let p_owner = signer::address_of(prj_owner);
        aptos_account::create_account(p_owner);

        launch_project(
            m_owner,
            1001,
            p_owner,
            string::utf8(b"Fake NFT Stake"),
            string::utf8(b"this is a test case of launch project"),
            3000,
            1000, 10, 100, 200, 30,// white list params
            1000, 20, 300, 400, 30,// private sell params
            1000, 30, 500, 600, 30,// public sell params
        )
    }

    #[test(prj_owner=@0xAABB1, m_owner = @Thundind)]
    public fun t_add_white_list(prj_owner: &signer, m_owner: &signer)
        acquires AllProjects
    {
        t_launch_project(m_owner, prj_owner);
        let whiter = vector::empty<address>();
        vector::push_back(&mut whiter, @0xBBCC0);
        add_white_list(prj_owner, 1001, whiter);
    }


    #[test_only]
    fun mint_aptos_coin(aptos_framework: &signer, receiver: &signer, amount: u64) {
        if (!account::exists_at(signer::address_of(receiver))) {
            aptos_account::create_account(signer::address_of(receiver));
        };

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        aptos_coin::mint(aptos_framework, signer::address_of(receiver), amount);
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    public fun t_buy_coin_success(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        let prj_owner_addr = signer::address_of(prj_owner);

        let apt_before = coin::balance<AptosCoin>(prj_owner_addr);

        buy_nft(player, 1001, 10);

        let apt_after = coin::balance<AptosCoin>(prj_owner_addr);
        assert!(apt_after - apt_before == 10 * 10, 100);

        // to private sell stage
        timestamp::fast_forward_seconds(200);
        apt_before = coin::balance<AptosCoin>(prj_owner_addr);

        buy_nft(player, 1001, 10);

        apt_after = coin::balance<AptosCoin>(prj_owner_addr);

        assert!(apt_after - apt_before == 10 * 20, 100);

        // to public sell stage
        timestamp::fast_forward_seconds(200);
        apt_before = coin::balance<AptosCoin>(prj_owner_addr);

        buy_nft(player, 1001, 10);

        apt_after = coin::balance<AptosCoin>(prj_owner_addr);

        assert!(apt_after - apt_before == 10 * 30, 100);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC2)]
    #[expected_failure]
    public fun t_buy_coin_not_white_list(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        buy_nft(player, 1001, 10);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    #[expected_failure]
    public fun t_buy_coin_not_sell_stage(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(1000);

       buy_nft(player, 1001, 10);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    #[expected_failure]
    public fun t_buy_coin_over_limit(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        buy_nft(player, 1001, 35);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    #[expected_failure]
    public fun t_buy_coin_over_limit_accu(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        buy_nft(player, 1001, 25);
        buy_nft(player, 1001, 15);
    }
}
