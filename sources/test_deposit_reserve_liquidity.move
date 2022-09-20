#[test_only]
module suilend::test_deposit_reserve_liquidity {
    use sui::coin::{Self, Coin};
    use suilend::time::{Self, Time};
    use sui::sui::SUI;
    use suilend::reserve::CToken;
    use suilend::lending_market::{
        Self,
        LendingMarket, 
        AdminCap, 
        ReserveInfo,
        create_lending_market,
        add_reserve,
        deposit_reserve_liquidity,
        create_obligation,
    };
    use suilend::obligation::{
        Obligation,
        DepositInfo
    };
    use sui::test_scenario::{Self, Scenario};
    use suilend::oracle::{Self, PriceCache, PriceInfo};

    struct POOLEY has drop {}
    
    
    fun update_time(scenario: &mut Scenario, owner: address, new_time: u64) {
        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);
            time::update_time(time, new_time, test_scenario::ctx(scenario));
            
            test_scenario::return_shared(scenario, time_wrapper);
        }
    }
    
    fun add_price_info<T>(
        scenario: &mut Scenario,
        owner: address,
        price_base: u64,
        price_exp: u64,
    ) {
        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);
            
            oracle::add_price_info<T>(
                price_cache, 
                time,
                price_base,
                price_exp,
                9,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, price_cache_wrapper);
        }
    }

    fun update_price<T>(
        scenario: &mut Scenario, 
        owner: address,
        price_base: u64,
        price_exp: u64
    ) {
        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);

            let price_info = test_scenario::take_child_object<
                PriceCache, 
                PriceInfo<T>>(scenario, price_cache);

            
            oracle::update_price_info(
                price_cache,
                &mut price_info,
                time,
                price_base,
                price_exp,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_owned(scenario, price_info);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, price_cache_wrapper);
        }
    }

    #[test]
    fun lending_market_create_reserve() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        time::new(start_time, test_scenario::ctx(scenario));
        
        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            oracle::new_price_cache(time, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, time_wrapper);
        };

        add_price_info<SUI>(scenario, owner, 10, 0);

        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);

            create_lending_market(POOLEY {}, time, price_cache, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, price_cache_wrapper);
        };
        
        test_scenario::next_tx(scenario, &owner);
        {
            let admin_cap = test_scenario::take_owned<AdminCap<POOLEY>>(scenario);

            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            add_reserve<POOLEY, SUI>(&admin_cap, lending_market, time, test_scenario::ctx(scenario));
            
            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_owned(scenario, admin_cap);
        };

        test_scenario::next_tx(scenario, &rando_1);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let reserve_info = test_scenario::take_child_object<LendingMarket<POOLEY>, ReserveInfo<POOLEY, SUI>>(
                scenario, lending_market);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);
            
            let money = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));

            deposit_reserve_liquidity<POOLEY, SUI>(
                lending_market, 
                &mut reserve_info, 
                money, 
                time,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_owned(scenario, reserve_info);
        };
        

        // verify that 100 ctokens were minted
        test_scenario::next_tx(scenario, &rando_1);
        let ctokens = test_scenario::take_owned<Coin<CToken<POOLEY, SUI>>>(scenario);
        assert!(coin::value(&ctokens) == 100, coin::value(&ctokens));
        
        test_scenario::next_tx(scenario, &rando_1);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);
            
            create_obligation<POOLEY>(lending_market, time, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
        };
        
        test_scenario::next_tx(scenario, &rando_1); 
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<POOLEY>, Obligation<POOLEY>>(
                scenario, lending_market);
            
            lending_market::add_deposit_info_to_obligation<POOLEY, CToken<POOLEY, SUI>>(
                lending_market,
                &mut obligation,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_owned(scenario, obligation);
        }; 
        
        test_scenario::next_tx(scenario, &rando_1);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<POOLEY>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<POOLEY>, Obligation<POOLEY>>(
                scenario, lending_market);

            let deposit_info = test_scenario::take_child_object<
                Obligation<POOLEY>, 
                DepositInfo<CToken<POOLEY, SUI>>>(scenario, &mut obligation);
                
            lending_market::deposit_ctokens(
                lending_market,
                &mut obligation,
                &mut deposit_info,
                time,
                ctokens,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_owned(scenario, obligation);
            test_scenario::return_owned(scenario, deposit_info);
        };
        
        // update price of SUI
        update_price<SUI>(scenario, owner, 20, 0);
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