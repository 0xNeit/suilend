/// A lending market holds many reserves. Assume base currency is USD. 

// notes: as of now there's no granular time module in the move VM. so the lending market owner
// will have to update the time via a function call. if the owner doesn't do this, the contract
// can be exploited.

module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use suilend::reserve::{Self, Reserve};
    use std::vector;
    

    // errors
    const EInvalidTime: u64 = 0;
    const EInvalidReserve: u64 = 1;
    const EUnauthorized: u64 = 2;

    // this is a shared object that contains references to ReserveInfos. This object 
    // also owns the ReserveInfos.
    struct LendingMarket<phantom P> has key {
        id: UID,
        cur_time: u64,
        reserve_info_ids: vector<ID>,
    }
    
    struct AdminCap<phantom P> has key {
        id: UID
    }
    
    struct ReserveInfo<phantom P, phantom T> has key {
        id: UID,
        lending_market: ID,
        reserve: Reserve<P, T>
    } 
    
    public entry fun create_lending_market<P: drop>(_witness: P, cur_time: u64, ctx: &mut TxContext) {
        // TODO add one-time witness check here

        let id = object::new(ctx);
        let lending_market = LendingMarket<P> {
            id,
            cur_time,
            reserve_info_ids: vector::empty()
        };
        
        transfer::share_object(lending_market);
        transfer::transfer(AdminCap<P> { id: object::new(ctx) }, tx_context::sender(ctx));
    }
    
    // add reserve
    public entry fun add_reserve<P, T>(_: &AdminCap<P>, lending_market: &mut LendingMarket<P>, ctx: &mut TxContext) {
        let reserve = reserve::create_reserve<P, T>(lending_market.cur_time);
        let id = object::new(ctx);

        let reserve_info = ReserveInfo<P, T> {
            id,
            lending_market: object::id(lending_market),
            reserve
        };
        
        vector::push_back(
            &mut lending_market.reserve_info_ids, 
            object::id<ReserveInfo<P, T>>(&reserve_info));

        transfer::share_object(reserve_info);
    }
    
    public entry fun update_time<P>(_: &AdminCap<P>, lending_market: &mut LendingMarket<P>, cur_time: u64, _ctx: &mut TxContext) {
        assert!(lending_market.cur_time <= cur_time, EInvalidTime);

        lending_market.cur_time = cur_time;
    }

    // deposit reserve liquidity
    public entry fun deposit_reserve_liquidity<P, T>(lending_market: &mut LendingMarket<P>, reserve_info: &mut ReserveInfo<P, T>, deposit: Coin<T>, ctx: &mut TxContext) {
        // TODO. do i even need this check? the reserve and lending market have to be related bc 
        // of the type constraints.
        assert!(reserve_info.lending_market == object::id(lending_market), EInvalidReserve);

        let balance = coin::into_balance(deposit);

        let ctoken_balance = reserve::deposit_liquidity_and_mint_ctokens(
            &mut reserve_info.reserve, 
            lending_market.cur_time, 
            balance
        );

        let ctokens = coin::from_balance(ctoken_balance, ctx);

        transfer::transfer(ctokens, tx_context::sender(ctx));
    }
    
    public fun time<P>(lending_market: &LendingMarket<P>): u64 {
        lending_market.cur_time
    }
    
    #[test_only]
    use sui::test_scenario::{Self};
    
    #[test_only]
    use sui::sui::SUI;
    
    #[test_only]
    use suilend::reserve::CToken;

    #[test_only]
    struct POOLEY has drop {}
    
    #[test]
    fun lending_market_success() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_lending_market(POOLEY {}, start_time, test_scenario::ctx(scenario));
        
        test_scenario::next_tx(scenario, &owner);
        {
            let admin_cap = test_scenario::take_owned<AdminCap<POOLEY>>(scenario);
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);
            add_reserve<POOLEY, SUI>(&admin_cap, lending_market, test_scenario::ctx(scenario));
            
            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_owned(scenario, admin_cap);
        };

        test_scenario::next_tx(scenario, &rando_1);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let reserve_info_wrapper = test_scenario::take_shared<ReserveInfo<POOLEY, SUI>>(scenario);
            let reserve_info = test_scenario::borrow_mut(&mut reserve_info_wrapper);
            
            let money = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));

            deposit_reserve_liquidity<POOLEY, SUI>(lending_market, reserve_info, money, test_scenario::ctx(scenario));
            
            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, reserve_info_wrapper);
        };
        

        // verify that 100 ctokens were minted
        test_scenario::next_tx(scenario, &rando_1);
        {
            let ctokens = test_scenario::take_owned<Coin<CToken<POOLEY, SUI>>>(scenario);
            assert!(coin::value(&ctokens) == 100, coin::value(&ctokens));
            
            coin::destroy_for_testing(ctokens);
        }
    }


    // redeem reserve collateral

    // create obligation
    // deposit collateral into obligation
    // withdraw obligation collateral
    // borrow obligation liquidity
    // repay obligation liquidity
    // liquidate obligation
    

    // tests
    // can you create multiple lending markets with the same type P?
    
    
}