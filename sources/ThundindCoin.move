// Copyright (c) Thundind
// SPDX-License-Identifier: Apache-2.0

module ThundindCoin::ThundindCoin {
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
        id: u64,
        buyer: address,
        progress_index: u8,
        buy_amount: u64,
        price: u64,
    }

    struct Progress has store {
        typ: u8,
        sell_amount: u64,     // want sell amount
        sold_amount: u64,     // real sold amount
        price: u64,           // 1 Token for xx Aptos
        start_time: u64,      // progress start time
        end_time: u64,        // progress end time
    }

    struct Project has store {
        id: u64,                  // project id
        launched_by: address,     // project launched by
        name: String,             // project name
        description: String,      // details of project
        coin_info: String,
        total_presell_amount: u64, // total amount for launch
        current_progress: u8,     // starting, published.....
        progresses: vector<Progress>, // all progresses
        white_list: vector<address>,
    }

    struct AllProjects has key {
        projects: Table<u64, Project>,
        launch_events: EventHandle<PrjLaunchEvent>,
        confirm_events: EventHandle<PrjConfirmEvent>,
        publish_events: EventHandle<PrjPublishEvent>,
        buy_events: EventHandle<PrjBuyEvent>,
    }

    struct CoinEscrowed<phantom CoinType> has key {
       coin: Coin<CoinType>,
    }

    struct SystemParameters has key {
        total_projects: u64,
        approved_publisher: vector<address>,
    }

    fun only_owner(sender: &signer): address {
        let owner = signer::address_of(sender);

        assert!(
            @ThundindCoin == owner,
            error::invalid_argument(ETHUNDIND_ONLY_OWNER),
        );

        owner
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
                confirm_events: event::new_event_handle<PrjConfirmEvent>(sender),
                publish_events: event::new_event_handle<PrjPublishEvent>(sender),
                buy_events: event::new_event_handle<PrjBuyEvent>(sender),
            }
        );

        assert!(
            !exists<SystemParameters>(owner),
            error::already_exists(ETHUNDIND_ALREADY_INITED),
        );

        move_to(
            sender,
            SystemParameters {
                total_projects: 0,
                approved_publisher: vector::empty<address>()
            }
        );
    }

    /**
    * launch_project
    *   start a request for launching, invoked by team member of the project
    */
    public entry fun launch_project(
            sender: &signer,
            name: String,
            description: String,
            coin_info: String,  // to describe the coin info, as: `0x1::FakeCoin::Coin`
            total_presell_amount: u64
    ) acquires SystemParameters, AllProjects {
        let prjId = &mut borrow_global_mut<SystemParameters>(@ThundindCoin).total_projects;
        *prjId = *prjId + 1;

        let prj = Project {
            id: *prjId,
            launched_by: signer::address_of(sender),
            name,
            description,
            coin_info,
            total_presell_amount,
            current_progress: PRJ_STATUS_STARTING,
            progresses: vector::empty(),
            white_list: vector::empty()
        };

        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);

        table::add(&mut allPrjs.projects, *prjId, prj);

        event::emit_event<PrjLaunchEvent>(
            &mut allPrjs.launch_events,
            PrjLaunchEvent { id: *prjId, amount: total_presell_amount },
        );
    }
    /**
    * comfirm_project
    *   the launch pad platform should confirm the project launched by `launch_project`
    */
    public entry fun confirm_project<CoinType>(
        sender: &signer,
        prjId: u64
    )
        acquires AllProjects
    {
        only_owner(sender);

        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );

        assert!(
            prj.current_progress == PRJ_STATUS_STARTING,
            error::invalid_argument(ETHUNDIND_PROJECT_STATUS_ERROR),
        );

        prj.current_progress = PRJ_STATUS_CONFIRMED;

        move_to(
            sender,
            CoinEscrowed<CoinType> { coin: coin::zero() }
        );

        event::emit_event<PrjConfirmEvent>(
            &mut allPrjs.confirm_events,
            PrjConfirmEvent { id: prjId },
        );
    }

    fun add_progress(prj: &mut Project, typ: u8, amount: u64, price: u64, start: u64, end: u64) {
        assert!(
            typ == 1 || typ == 2 || typ == 3,
            error::invalid_argument(ETHUNDIND_PROJECT_PROGRESS_UNKNOWN)
        );

        assert!(
            start < end,
            error::invalid_argument(ETHUNDIND_PROJECT_PROGRESS_UNKNOWN)
        );

        let p = Progress {
            typ,
            sell_amount: amount,
            sold_amount: 0,
            price,
            start_time: start,
            end_time: end,
        };

        vector::push_back(&mut prj.progresses, p);
    }

    /**
    * white_list_project
    *   add white list to project by launcher
    */
    public entry fun white_list_project(
        sender: &signer,
        prjId: u64,
        white_list: vector<address>
    )
        acquires AllProjects
    {
        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        let account = signer::address_of(sender);
        assert!(
            prj.launched_by == account,
            error::invalid_argument(ETHUNDIND_PROJECT_OWNER_MISMATCH)
        );

        vector::append(&mut prj.white_list, white_list);
    }

    /**
    * publish_project
    *   publish this project by launcher
    */
    public entry fun publish_project<CoinType>(
        sender: &signer,
        prjId: u64,
        progress_type: vector<u8>,
        progress_amount: vector<u64>,
        progress_price: vector<u64>,
        progress_start: vector<u64>,
        progress_end:   vector<u64>
    )
        acquires AllProjects, CoinEscrowed
    {
        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        let account = signer::address_of(sender);
        assert!(
            prj.launched_by == account,
            error::invalid_argument(ETHUNDIND_PROJECT_OWNER_MISMATCH)
        );

        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );

        assert!(
            prj.current_progress == PRJ_STATUS_CONFIRMED,
            error::invalid_argument(ETHUNDIND_PROJECT_STATUS_ERROR),
        );

        let len = vector::length(&progress_amount);
        let i = 0;
        let total_amount = 0;
        while ( i < len) {
            total_amount = total_amount + *vector::borrow(&progress_amount, i);
            i = i + 1;
        };

        assert!(
            prj.total_presell_amount == total_amount,
            error::invalid_argument(ETHUNDIND_PROJECT_STATUS_ERROR),
        );

        i = 0;
        while (i < len) {
            add_progress(
                prj,
                *vector::borrow(&progress_type, i),
                *vector::borrow(&progress_amount, i),
                *vector::borrow(&progress_price, i),
                *vector::borrow(&progress_start, i),
                *vector::borrow(&progress_end, i),
            );
            i = i + 1;
        };

        prj.current_progress = PRJ_STATUS_PUBLISHED;

        // to stake coin to this project
        let coin = coin::withdraw<CoinType>(sender, prj.total_presell_amount);
        let staked_coin = &mut borrow_global_mut<CoinEscrowed<CoinType>>(@ThundindCoin).coin;
        coin::merge<CoinType>(staked_coin, coin);

        event::emit_event<PrjPublishEvent>(
            &mut allPrjs.publish_events,
            PrjPublishEvent { id: prjId },
        );
    }

    fun pow(base: u64, exp: u64): u64 {
        let i = 0;
        let v = 1;
        while ( i < exp) {
            v = v * base;
        };

        v
    }

    public fun register_coin_if_need<CoinType>(sender: &signer) {
        if (coin::is_account_registered<CoinType>(signer::address_of(sender))) return;

        managed_coin::register<CoinType>(sender);
    }

    public fun exchange_coins<CoinType>(
        sender: &signer,
        amount: u64,
        price: u64,
        receiver: address
    )
        acquires CoinEscrowed
    {
        let decimal = coin::decimals<CoinType>();
        let aptos_amount = amount * price / pow(10, (decimal as u64));

        register_coin_if_need<CoinType>(sender);

        coin::transfer<AptosCoin>(sender, receiver, aptos_amount);

        let coin = &mut borrow_global_mut<CoinEscrowed<CoinType>>(@ThundindCoin).coin;

        let t = coin::extract<CoinType>(coin, amount);
        coin::deposit(signer::address_of(sender), t);
    }

    public fun update_progress_status(
        prj: &mut Project,
        progress_index: u8,
        amount: u64
    ): u64
    {
        let now = timestamp::now_seconds();
        let len = vector::length(&prj.progresses);

        let i = 0;
        let price = 0;
        while (i < len) {
            let progress = vector::borrow_mut(&mut prj.progresses, i);
            if (progress.typ == progress_index) {
               assert!(
                 progress.sold_amount + amount <= progress.sell_amount,
                 error::invalid_argument(ETHUNDIND_PROJECT_AMOUNT_OVER_BOUND)
               );

               assert!(
                 progress.start_time <= now && now < progress.end_time,
                 error::invalid_argument(ETHUNDIND_PROJECT_PROGRESS_TIME_OVER)
               );

               progress.sold_amount = progress.sold_amount + amount;
               price = progress.price;
            };
            i = i + 1;
        };

        assert!(
            i < len,
            error::invalid_argument(ETHUNDIND_PROJECT_PROGRESS_NOT_EXIST)
        );

        price
    }

    // user buy with white list
    public entry fun white_list_buy_project<CoinType>(
        sender: &signer,
        prjId: u64,
        amount: u64
    )
        acquires AllProjects, CoinEscrowed
    {
        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );

        let buyer = signer::address_of(sender);
        assert!(
            vector::contains(&prj.white_list, &buyer),
            error::invalid_argument(ETHUNDIND_PROJECT_NOT_WHITE_LIST)
        );

        let price = update_progress_status(prj, PRJ_PROGRESS_WHITE_LIST, amount);

        exchange_coins<CoinType>(sender, amount, price, prj.launched_by);

        event::emit_event<PrjBuyEvent>(
            &mut allPrjs.buy_events,
            PrjBuyEvent {
                id: prjId,
                buyer,
                progress_index: PRJ_PROGRESS_WHITE_LIST,
                buy_amount: amount,
                price,
            },
        );
    }

    // user buy with private sell
    public entry fun private_sell_buy_project<CoinType>(
        sender: &signer,
        prjId: u64,
        amount: u64
    )
        acquires AllProjects, CoinEscrowed
    {
        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );

        let buyer = signer::address_of(sender);
        let price = update_progress_status(prj, PRJ_PROGRESS_PRIVATE_SELL, amount);

        exchange_coins<CoinType>(sender, amount, price, prj.launched_by);

        event::emit_event<PrjBuyEvent>(
            &mut allPrjs.buy_events,
            PrjBuyEvent {
                id: prjId,
                buyer,
                progress_index: PRJ_PROGRESS_PRIVATE_SELL,
                buy_amount: amount,
                price,
            },
        );
    }

    // user buy with public sell
    public entry fun public_sell_buy_project<CoinType>(
        sender: &signer,
        prjId: u64,
        amount: u64
    )
        acquires AllProjects, CoinEscrowed
    {
        let allPrjs = borrow_global_mut<AllProjects>(@ThundindCoin);
        assert!(
            table::contains(&allPrjs.projects, prjId),
            error::not_found(ETHUNDIND_PROJECT_NOT_EXIST),
        );

        let prj = table::borrow_mut(&mut allPrjs.projects, prjId);
        assert!(
            type_info::type_name<CoinType>() == prj.coin_info,
            error::invalid_argument(ETHUNDIND_PROJECT_COINTYPE_MISMATCH),
        );

        let buyer = signer::address_of(sender);
        let price = update_progress_status(prj, PRJ_PROGRESS_PUBLIC_SELL, amount);

        exchange_coins<CoinType>(sender, amount, price, prj.launched_by);

        event::emit_event<PrjBuyEvent>(
            &mut allPrjs.buy_events,
            PrjBuyEvent {
                id: prjId,
                buyer,
                progress_index: PRJ_PROGRESS_PUBLIC_SELL,
                buy_amount: amount,
                price,
            },
        );
    }
}
