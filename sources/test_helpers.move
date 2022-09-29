#[test_only]
module suilend::test_helpers {
    use sui::coin::{Self, Coin};
    use suilend::time::{Self, Time};
    use sui::sui::SUI;
    use suilend::reserve::CToken;
    use suilend::lending_market::{
        Self,
        LendingMarket, 
        AdminCap, 
        ReserveInfo
    };
    use suilend::obligation::{
        Obligation,
        DepositInfo,
        BorrowInfo
    };
    use sui::test_scenario::{Self, Scenario};
    use suilend::oracle::{Self, PriceCache, PriceInfo};

    struct POOLEY has drop {}
    
    // 10^9
    const MIST_TO_SUI: u64 = 1000000000;
    
    // various helper functions to abstract away all the object taking and returning
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

   fun reset_stats<P>(
        scenario: &mut Scenario,
        obligation_owner: address
    ) {
        test_scenario::next_tx(scenario, &obligation_owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);

            lending_market::reset_stats(
                lending_market,
                &mut obligation,
                time,
                test_scenario::ctx(scenario)
            );


            test_scenario::return_owned(scenario, obligation);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, lending_market_wrapper);
        };
    }
     
    fun update_stats_deposit<P, T>(
        scenario: &mut Scenario,
        obligation_owner: address
    ) {
        test_scenario::next_tx(scenario, &obligation_owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);

            let price_info = test_scenario::take_child_object<
                PriceCache, 
                PriceInfo<T>>(scenario, price_cache);

            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let reserve_info = test_scenario::take_child_object<LendingMarket<P>, ReserveInfo<P, T>>(
                scenario, lending_market);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);

            let deposit_info = test_scenario::take_child_object<
                Obligation<P>, 
                DepositInfo<CToken<P, T>>>(scenario, &mut obligation);
            
            lending_market::update_stats_deposit(
                lending_market,
                &mut reserve_info,
                &mut obligation,
                &mut deposit_info,
                time,
                &price_info,
                test_scenario::ctx(scenario)
            );


            test_scenario::return_owned(scenario, deposit_info);
            test_scenario::return_owned(scenario, obligation);

            test_scenario::return_owned(scenario, price_info);
            test_scenario::return_shared(scenario, price_cache_wrapper);

            test_scenario::return_owned(scenario, reserve_info);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, lending_market_wrapper);
        };
    }

    fun update_stats_borrow<P, T>(
        scenario: &mut Scenario,
        obligation_owner: address
    ) {
        test_scenario::next_tx(scenario, &obligation_owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);

            let price_info = test_scenario::take_child_object<
                PriceCache, 
                PriceInfo<T>>(scenario, price_cache);

            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let reserve_info = test_scenario::take_child_object<LendingMarket<P>, ReserveInfo<P, T>>(
                scenario, lending_market);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);

            let borrow_info = test_scenario::take_child_object<
                Obligation<P>, 
                BorrowInfo<T>>(scenario, &mut obligation);
            
            lending_market::update_stats_borrow(
                lending_market,
                &mut reserve_info,
                &mut obligation,
                &mut borrow_info,
                time,
                &price_info,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_owned(scenario, borrow_info);
            test_scenario::return_owned(scenario, obligation);

            test_scenario::return_owned(scenario, price_info);
            test_scenario::return_shared(scenario, price_cache_wrapper);

            test_scenario::return_owned(scenario, reserve_info);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, lending_market_wrapper);
        };
    }
    
    fun create_price_cache(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            oracle::new_price_cache(time, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, time_wrapper);
        };
    }
    
    fun create_lending_market<P: drop>(scenario: &mut Scenario, witness: P, owner: address) {
        test_scenario::next_tx(scenario, &owner);
        {
            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);

            lending_market::create_lending_market<P>(
                witness, 
                time, 
                price_cache, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, price_cache_wrapper);
        }
    }
    
    fun create_time(scenario: &mut Scenario, owner: address, start_time: u64) {
        test_scenario::next_tx(scenario, &owner);
        {
            time::new(start_time, test_scenario::ctx(scenario));
        }
    }
    
    fun add_reserve<P, T>(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, &owner);
        {
            let admin_cap = test_scenario::take_owned<AdminCap<P>>(scenario);

            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            lending_market::add_reserve<P, T>(&admin_cap, lending_market, time, test_scenario::ctx(scenario));
            
            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_owned(scenario, admin_cap);
        }
    }

    fun deposit_reserve_liquidity<P, T>(scenario: &mut Scenario, owner: address, amount: u64): Coin<CToken<P, T>> {
        test_scenario::next_tx(scenario, &owner);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let reserve_info = test_scenario::take_child_object<LendingMarket<P>, ReserveInfo<P, T>>(
                scenario, lending_market);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);
            
            let money = coin::mint_for_testing<T>(amount, test_scenario::ctx(scenario));

            lending_market::deposit_reserve_liquidity<P, T>(
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
        test_scenario::next_tx(scenario, &owner);
        test_scenario::take_owned<Coin<CToken<P, T>>>(scenario)
    }
    
    fun create_obligation<P>(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, &owner);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);
            
            lending_market::create_obligation<P>(lending_market, time, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
        };
    }

    fun add_deposit_info_to_obligation<P, T>(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, &owner); 
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);
            
            lending_market::add_deposit_info_to_obligation<P, CToken<P, T>>(
                lending_market,
                &mut obligation,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_owned(scenario, obligation);
        };
    }

    fun add_borrow_info_to_obligation<P, T>(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, &owner); 
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);
            
            lending_market::add_borrow_info_to_obligation<P, T>(
                lending_market,
                &mut obligation,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_owned(scenario, obligation);
        };
    }
    
    fun deposit_ctokens_into_obligation<P, T>(
        scenario: &mut Scenario, 
        owner: address, 
        ctokens: Coin<CToken<P, T>>
    ) {
        test_scenario::next_tx(scenario, &owner);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);

            let deposit_info = test_scenario::take_child_object<
                Obligation<P>, 
                DepositInfo<CToken<P, T>>>(scenario, &mut obligation);
                
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
        }
    }

    fun borrow<P, T>(
        scenario: &mut Scenario, 
        owner: address, 
        borrow_amount: u64
    ): Coin<T> {
        test_scenario::next_tx(scenario, &owner);
        {
            let lending_market_wrapper = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let lending_market = test_scenario::borrow_mut(&mut lending_market_wrapper);

            let time_wrapper = test_scenario::take_shared<Time>(scenario);
            let time = test_scenario::borrow_mut(&mut time_wrapper);

            let obligation = test_scenario::take_child_object<LendingMarket<P>, Obligation<P>>(
                scenario, lending_market);

            let reserve_info = test_scenario::take_child_object<LendingMarket<P>, ReserveInfo<P, T>>(
                scenario, lending_market);

            let borrow_info = test_scenario::take_child_object<
                Obligation<P>, 
                BorrowInfo<T>>(scenario, &mut obligation);

            let price_cache_wrapper = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache = test_scenario::borrow_mut(&mut price_cache_wrapper);

            let price_info = test_scenario::take_child_object<
                PriceCache, 
                PriceInfo<T>>(scenario, price_cache);
                
            lending_market::borrow(
                lending_market,
                &mut reserve_info,
                &mut obligation,
                &mut borrow_info,
                time,
                &price_info,
                borrow_amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(scenario, lending_market_wrapper);
            test_scenario::return_shared(scenario, time_wrapper);
            test_scenario::return_shared(scenario, price_cache_wrapper);

            test_scenario::return_owned(scenario, price_info);
            test_scenario::return_owned(scenario, obligation);
            test_scenario::return_owned(scenario, borrow_info);
            test_scenario::return_owned(scenario, reserve_info);
        };

        test_scenario::next_tx(scenario, &owner);
        test_scenario::take_last_created_owned<Coin<T>>(scenario)
    }
    
    #[test]
    fun lending_market_create_reserve() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 10, 0);

        create_lending_market(scenario, POOLEY {}, owner);
        add_reserve<POOLEY, SUI>(scenario, owner);

        let ctokens = deposit_reserve_liquidity<POOLEY, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);
        assert!(coin::value(&ctokens) == 100 * MIST_TO_SUI, coin::value(&ctokens));

        create_obligation<POOLEY>(scenario, rando_1);
        add_deposit_info_to_obligation<POOLEY, SUI>(scenario, rando_1);
        
        deposit_ctokens_into_obligation<POOLEY, SUI>(scenario, rando_1, ctokens);

        // update price of SUI
        update_price<SUI>(scenario, owner, 20, 0);

        // refresh obligation
        reset_stats<POOLEY>(scenario, rando_1);
        update_stats_deposit<POOLEY, SUI>(scenario, rando_1);
        
        // try to borrow some coins
        add_borrow_info_to_obligation<POOLEY, SUI>(scenario, rando_1);
        let coins = borrow<POOLEY, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);
        assert!(coin::value(&coins) == 100 * MIST_TO_SUI, coin::value(&coins));
        coin::destroy_for_testing(coins);
        
        // refresh obligation
        reset_stats<POOLEY>(scenario, rando_1);
        update_stats_borrow<POOLEY, SUI>(scenario, rando_1);
        update_stats_deposit<POOLEY, SUI>(scenario, rando_1);
    }
}