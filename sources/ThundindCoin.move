// Copyright (c) Thundind
// SPDX-License-Identifier: Apache-2.0

module Thundind::ThundindCoin {
    use std::string::String;
    use std::coin::{Self, Coin};
    use std::signer;
    use std::error;
    use std::vector;
    use std::type_info;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::managed_coin;
    use aptos_framework::account;

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
    const ETHUNDIND_NOT_CLAIMABLE: u64              = 12;
    const ETHUNDIND_NOT_BOUGHT: u64                 = 13;
    const ETHUNDIND_PROJECT_HAS_STARTED: u64        = 14;
    const ETHUNDIND_OVER_BUYABLE_AMOUNT: u64        = 15;

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

    struct Stage has store, drop {
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

    struct Project has store {
        id: u64,                  // project id
        owner: address,     // project launched by
        name: String,             // project name
        description: String,      // details of project
        token_distribution: String, // a brief introduction for token distribution
        initial_market_cap_at_tge: String, // Initial Market cap intro
        coin_info: String,
        total_presell_amount: u64, // total amount for launch
        claimable_time: u64, // buyer can claim token after this time

        white_list_stage: Stage,     // starting, published.....
        private_sell_stage: Stage,     // starting, published.....
        public_sell_stage: Stage,     // starting, published.....

        white_list: vector<address>,        // white list
        buyer_list: Table<address, BoughtRecord>,        // all buyers

        buy_events: EventHandle<PrjBuyEvent>,
    }

    struct AllProjects has key {
        projects: Table<u64, Project>,
        launch_events: EventHandle<PrjLaunchEvent>,
    }

    struct ProjectEscrowedCoin<phantom CoinType> has key {
       coin: Coin<CoinType>,
       apt_coin: Coin<AptosCoin>,
       last_withdraw_time: u64,
    }

    struct BuyerEscrowedCoin<phantom CoinType> has key {
        coin: Coin<CoinType>,
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
            limit_per_account: limit
        }
    }

    public entry fun init_system(sender: &signer) {
        // only_owner(sender);

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
    */
    public entry fun launch_project<CoinType>(
            sender: &signer,
            prj_id: u64,
            owner: address,
            name: String,
            description: String,
            token_distribution: String, // a brief introduction for token distribution
            initial_market_cap_at_tge: String,
            total_presell_amount: u64,
            claimable_time: u64,
            wl_amount: u64, wl_price: u64, wl_start: u64, wl_end: u64, wl_limit: u64, // white list params
            pv_amount: u64, pv_price: u64, pv_start: u64, pv_end: u64, pv_limit: u64, // private sell params
            pb_amount: u64, pb_price: u64, pb_start: u64, pb_end: u64, pb_limit: u64, // public sell params
    ) acquires AllProjects {

        only_owner(sender);

        assert!(
            total_presell_amount == wl_amount + pv_amount + pb_amount,
            error::invalid_argument(ETHUNDIND_PROJECT_AMOUNT_OVER_BOUND)
        );

        let coin_info = type_info::type_name<CoinType>();

        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);

        if (table::contains(&allPrjs.projects, prj_id)) {
            let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
            let now = timestamp::now_seconds();
            assert!(
                now < prj.white_list_stage.start_time ||
                now < prj.private_sell_stage.start_time ||
                now < prj.public_sell_stage.start_time,
                error::invalid_argument(ETHUNDIND_PROJECT_HAS_STARTED)
            );

            prj.id = prj_id;
            prj.owner = owner;
            prj.name = name;
            prj.description = description;
            prj.token_distribution = token_distribution;
            prj.initial_market_cap_at_tge = initial_market_cap_at_tge;
            prj.coin_info = coin_info;
            prj.total_presell_amount = total_presell_amount;
            prj.claimable_time = claimable_time;
            prj.white_list_stage = make_stage(wl_amount, wl_price, wl_start, wl_end, wl_limit);
            prj.private_sell_stage = make_stage(pv_amount, pv_price, pv_start, pv_end, pv_limit);
            prj.public_sell_stage = make_stage(pb_amount, pb_price, pb_start, pb_end, pb_limit);
        } else {
            let new_prj = Project {
                id: prj_id,
                owner,
                name,
                description,
                token_distribution,
                initial_market_cap_at_tge,
                coin_info,
                total_presell_amount,
                claimable_time,

                white_list_stage:   make_stage(wl_amount, wl_price, wl_start, wl_end, wl_limit),     // white list progress
                private_sell_stage: make_stage(pv_amount, pv_price, pv_start, pv_end, pv_limit),     // private sell progress
                public_sell_stage:  make_stage(pb_amount, pb_price, pb_start, pb_end, pb_limit),     // public sell progress

                white_list: vector::empty(),        // white list
                buyer_list: table::new(),        // all buyers

                buy_events: account::new_event_handle<PrjBuyEvent>(sender),
            };

            table::add(&mut allPrjs.projects, prj_id, new_prj);
        };

        event::emit_event<PrjLaunchEvent>(
            &mut allPrjs.launch_events,
            PrjLaunchEvent { prj_id },
        );
    }

    public entry fun stake_coin<CoinType>(
        sender: &signer,
        prj_id: u64
    )
        acquires AllProjects, ProjectEscrowedCoin
    {
        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
        assert!(
            table::contains(&allPrjs.projects, prj_id),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );
        let owner = signer::address_of(sender);
        assert!(
            prj.owner == owner,
            error::invalid_argument(ETHUNDIND_PROJECT_OWNER_MISMATCH)
        );

        if (!exists<ProjectEscrowedCoin<CoinType>>(owner)) {
            move_to(
                sender,
                ProjectEscrowedCoin {
                    coin: coin::zero<CoinType>(),
                    apt_coin: coin::zero<AptosCoin>(),
                    last_withdraw_time: 0
                }
            );
        };

        let staked_coin = &mut borrow_global_mut<ProjectEscrowedCoin<CoinType>>(owner).coin;
        let staked_amount = coin::withdraw<CoinType>(sender, prj.total_presell_amount);
        coin::merge<CoinType>(staked_coin, staked_amount);
    }

    /**
    * white_list_project
    *   add white list to project by launcher
    */
    public entry fun add_white_list(
        sender: &signer,
        prjId: u64,
        white_list: vector<address>
    )
        acquires AllProjects
    {
        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        let account = signer::address_of(sender);
        assert!(
            prj.owner == account,
            error::invalid_argument(ETHUNDIND_PROJECT_OWNER_MISMATCH)
        );

        vector::append(&mut prj.white_list, white_list);
    }

    fun pow(base: u64, exp: u64): u64 {
        let i = 0;
        let v = 1;
        while ( i < exp) {
            v = v * base;
            i = i + 1;
        };

        v
    }

    public fun exchange_coins<CoinType>(
        buyer: &signer,
        prj_owner: address,
        amount: u64,
        price: u64
    )
        acquires ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        let decimal = coin::decimals<CoinType>();
        let aptos_amount = amount * price / pow(10, (decimal as u64));
        //
        if (!coin::is_account_registered<CoinType>(signer::address_of(buyer))) {
            managed_coin::register<CoinType>(buyer);
        };
        let coin_escrowed = borrow_global_mut<ProjectEscrowedCoin<CoinType>>(prj_owner);
        let t = coin::extract<CoinType>(&mut coin_escrowed.coin, amount);

        let buyer_address = signer::address_of(buyer);
        if (exists<BuyerEscrowedCoin<CoinType>>(buyer_address)) {
            let c = &mut borrow_global_mut<BuyerEscrowedCoin<CoinType>>(buyer_address).coin;
            coin::merge<CoinType>(c, t);
        } else {
            move_to(buyer, BuyerEscrowedCoin { coin: t });
        };
        // escrow AptosCoin to owner storage
        let paied_apt = coin::withdraw<AptosCoin>(buyer, aptos_amount);
        coin::merge<AptosCoin>(&mut coin_escrowed.apt_coin, paied_apt);
    }

    public fun do_buy_coin_with_aptos<CoinType>(
        sender: &signer,
        prj: &mut Project,
        amount: u64
    ): (u8, u64)
        acquires ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        let now = timestamp::now_seconds();
        let in_stage: u8 = 0;
        let stage: &mut Stage;

        if (prj.white_list_stage.start_time <= now && now < prj.white_list_stage.end_time) {
            stage = &mut prj.white_list_stage;
            in_stage = STAGE_WHITE_LIST;
        } else if (prj.private_sell_stage.start_time <= now && now < prj.private_sell_stage.end_time) {
            stage = &mut prj.private_sell_stage;
            in_stage = STAGE_PRIVATE_SELL;
        } else if (prj.public_sell_stage.start_time <= now && now < prj.public_sell_stage.end_time) {
            stage = &mut prj.public_sell_stage;
            in_stage = STAGE_PUBLIC_SELL;
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

        exchange_coins<CoinType>(sender, prj.owner, amount, stage.price);

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

    // user buy coin
    public entry fun buy_coin<CoinType>(
        sender: &signer,
        prjId: u64,
        amount: u64
    )
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );

        let (in_stage, limit) = do_buy_coin_with_aptos<CoinType>(sender, prj, amount);

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

    // project owner withdraw AptosCoin
    public entry fun withdraw_apt_coin<CoinType>(
        sender: &signer,
        prj_id: u64,
        amount: u64
    )
        acquires ProjectEscrowedCoin, AllProjects
    {
        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
        assert!(
            table::contains(&allPrjs.projects, prj_id),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
        let owner = signer::address_of(sender);
        assert!(
            prj.owner == owner,
            error::invalid_argument(ETHUNDIND_PROJECT_OWNER_MISMATCH)
        );

        let apt_escrowed = borrow_global_mut<ProjectEscrowedCoin<CoinType>>(owner);
        let withdraw_amount = coin::extract<AptosCoin>(&mut apt_escrowed.apt_coin, amount);
        // TODO: to impl withdraw logic
        coin::deposit<AptosCoin>(owner, withdraw_amount);
        apt_escrowed.last_withdraw_time = timestamp::now_seconds();
    }

    /// buyer request to claim the token who bought at project
    public entry fun buyer_claim_token<CoinType>(
        sender: &signer,
        prj_id: u64
    )
        acquires BuyerEscrowedCoin, AllProjects
    {
        let allPrjs = borrow_global_mut<AllProjects>(@Thundind);
        assert!(
            table::contains(&allPrjs.projects, prj_id),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prj_id);
        let now = timestamp::now_seconds();
        assert!(
            now >= prj.claimable_time,
            error::invalid_argument(ETHUNDIND_NOT_CLAIMABLE)
        );

        let buyer_address = signer::address_of(sender);
        assert!(
            exists<BuyerEscrowedCoin<CoinType>>(buyer_address),
            error::invalid_argument(ETHUNDIND_NOT_BOUGHT)
        );

        let c = &mut borrow_global_mut<BuyerEscrowedCoin<CoinType>>(buyer_address).coin;
        let claim_amount = coin::extract_all<CoinType>(c);
        coin::deposit<CoinType>(buyer_address, claim_amount);
    }

// ------------ unit test starts -------------------
    #[test_only]
    struct FakeMoney { }

    #[test_only]
    use aptos_framework::aptos_account;

    #[test_only]
    use std::string;

    #[test_only]
    use aptos_framework::aptos_coin;

    #[test_only]
    const FM_DECIMALS: u64 = 1;

    #[test_only(m_owner = @Thundind, prj_owner=@0xAABB1)]
    public fun issue_fake_money(m_owner: &signer, prj_owner: &signer) {

        managed_coin::initialize<FakeMoney>(
            m_owner,
            b"Fake Money",
            b"FM",
            0,
            false,
        );

        let p = signer::address_of(prj_owner);
        aptos_account::create_account(p);

        coin::register<FakeMoney>(prj_owner);

        managed_coin::mint<FakeMoney>(
            m_owner,
            p,
            10000 * FM_DECIMALS // 10000FM
        );
    }

    #[test(m_owner = @Thundind)]
    public fun t_init_system(m_owner: &signer) {
        aptos_account::create_account(signer::address_of(m_owner));
        init_system(m_owner);
    }

    #[test(m_owner = @Thundind, prj_owner = @0xAABB1)]
    public fun t_launch_project(m_owner: &signer, prj_owner: &signer) acquires AllProjects{
        t_init_system(m_owner);

        let p_owner = signer::address_of(prj_owner);
        launch_project<FakeMoney>(
            m_owner,
            1001,
            p_owner,
            string::utf8(b"Fake Coin Stake"),
            string::utf8(b"this is a test case of launch project"),
            string::utf8(b"20% for sell, 80% for dev"),
            string::utf8(b"45% TGE for 2 weeks"),
            1200,
            700, // claimable time
            400, 10, 100, 200, 20,// white list params
            400, 20, 300, 400, 20,// private sell params
            400, 30, 500, 600, 20,// public sell params
        )
    }

    #[test(prj_owner=@0xAABB1, m_owner = @Thundind)]
    public fun t_stake_coin(prj_owner: &signer, m_owner: &signer)
        acquires AllProjects, ProjectEscrowedCoin
    {
        t_launch_project(m_owner, prj_owner);
        issue_fake_money(m_owner, prj_owner);

        stake_coin<FakeMoney>(prj_owner, 1001);
    }

    #[test(prj_owner=@0xAABB1, m_owner = @Thundind)]
    public fun t_add_white_list(prj_owner: &signer, m_owner: &signer)
        acquires AllProjects, ProjectEscrowedCoin
    {
        t_stake_coin(prj_owner, m_owner);

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
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        let player_addr = signer::address_of(player);

        let apt_before = coin::balance<AptosCoin>(player_addr);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 10);  // 10 FM

        let apt_after = coin::balance<AptosCoin>(player_addr);

        assert!(apt_before - apt_after == 10 * 10, 100);

        // to private sell stage
        timestamp::fast_forward_seconds(200);
        apt_before = coin::balance<AptosCoin>(player_addr);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 10);  // 10 FM

        apt_after = coin::balance<AptosCoin>(player_addr);

        assert!(apt_before - apt_after == 10 * 20, 100);

        // to public sell stage
        timestamp::fast_forward_seconds(200);
        apt_before = coin::balance<AptosCoin>(player_addr);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 10);  // 10 FM

        apt_after = coin::balance<AptosCoin>(player_addr);

        assert!(apt_before - apt_after == 10 * 30, 100);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    public fun t_buyer_claim_success(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        t_buy_coin_success(prj_owner, m_owner, aptos_framework, player);

        timestamp::fast_forward_seconds(200);

        buyer_claim_token<FakeMoney>(player, 1001);

        assert!(coin::balance<FakeMoney>(signer::address_of(player)) == FM_DECIMALS * 10 * 3, 109);
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC2)]
    #[expected_failure]
    public fun t_buy_coin_not_white_list(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 10);  // 10 FM
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    #[expected_failure]
    public fun t_buy_coin_not_sell_stage(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(1000);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 10);  // 10 FM
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    #[expected_failure]
    public fun t_buy_coin_over_limit(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 21);  // 21 FM
    }

    #[test(aptos_framework = @0x1, prj_owner=@0xAABB1, m_owner = @Thundind, player = @0xBBCC0)]
    #[expected_failure]
    public fun t_buy_coin_over_limit_by_accumulative(prj_owner: &signer, m_owner: &signer, aptos_framework: &signer, player: &signer)
        acquires AllProjects, ProjectEscrowedCoin, BuyerEscrowedCoin
    {
        t_add_white_list(prj_owner, m_owner);
        mint_aptos_coin(aptos_framework, player, 1000000000000); // 10000 APT

        timestamp::set_time_has_started_for_testing(aptos_framework);
        // to white list stage
        timestamp::fast_forward_seconds(150);

        buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 10);  // 21 FM

        timestamp::fast_forward_seconds(10);

         buy_coin<FakeMoney>(player, 1001, FM_DECIMALS * 15);
    }
}
