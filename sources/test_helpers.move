#[test_only]
/// Various helper functions to abstract away all the object stuff
module suilend::test_helpers {
    use sui::coin::{Self, Coin};
    use suilend::time::{Self, Time, TimeCap};
    use suilend::reserve::CToken;
    use suilend::lending_market::{
        Self,
        LendingMarket, 
        AdminCap, 
        ObligationCap
    };
    use suilend::obligation::{
        Stats
    };
    use sui::test_scenario::{Self, Scenario};
    use suilend::oracle::{Self, PriceCache, PriceCacheCap};
    use sui::object::{ID};
    use std::option;

    // time helpers
    public fun create_time(scenario: &mut Scenario, owner: address, start_time: u64) {
        test_scenario::next_tx(scenario, owner);
        {
            time::new(start_time, test_scenario::ctx(scenario));
        }
    }

    public fun update_time(scenario: &mut Scenario, owner: address, new_time: u64) {
        test_scenario::next_tx(scenario, owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            let time_cap = test_scenario::take_from_sender<TimeCap>(scenario);
            time::update_time(&time_cap, &mut time, new_time, test_scenario::ctx(scenario));

            test_scenario::return_shared(time);
            test_scenario::return_to_sender(scenario, time_cap);
        }
    }
    
    public fun create_price_cache(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            oracle::new_price_cache(&mut time, test_scenario::ctx(scenario));
            test_scenario::return_shared(time);
        };
    }

    // price helpers
    public fun add_price_info<T>(
        scenario: &mut Scenario,
        owner: address,
        price_base: u64,
        price_exp: u64,
        decimals: u64
    ) {
        test_scenario::next_tx(scenario, owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache_cap = test_scenario::take_from_sender<PriceCacheCap>(scenario);
            
            oracle::add_price_info<T>(
                &price_cache_cap,
                &mut price_cache, 
                &time,
                price_base,
                price_exp,
                decimals,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(time);
            test_scenario::return_shared(price_cache);
            test_scenario::return_to_sender(scenario, price_cache_cap);
        }
    }

    public fun update_price<T>(
        scenario: &mut Scenario, 
        owner: address,
        price_base: u64,
        price_exp: u64
    ) {
        test_scenario::next_tx(scenario, owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);
            let price_cache_cap = test_scenario::take_from_sender<PriceCacheCap>(scenario);

            oracle::update_price<T>(
                &price_cache_cap,
                &mut price_cache,
                &time,
                price_base,
                price_exp,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(time);
            test_scenario::return_shared(price_cache);
            test_scenario::return_to_sender(scenario, price_cache_cap);
        }
    }

    public fun create_lending_market<P: drop>(scenario: &mut Scenario, witness: P, owner: address) {
        test_scenario::next_tx(scenario, owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);

            lending_market::create_lending_market<P>(
                witness,
                &time, 
                &price_cache, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(time);
            test_scenario::return_shared(price_cache);
        }
    }
    
    
    public fun add_reserve<P, T>(scenario: &mut Scenario, owner: address) {
        test_scenario::next_tx(scenario, owner);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap<P>>(scenario);
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);

            let time = test_scenario::take_shared<Time>(scenario);

            lending_market::add_reserve<P, T>(
                &admin_cap, 
                &mut lending_market, 
                &time, 
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
            test_scenario::return_to_sender(scenario, admin_cap);
        }
    }

    public fun deposit_reserve_liquidity<P, T>(scenario: &mut Scenario, owner: address, amount: u64): Coin<CToken<P, T>> {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);
            let money = coin::mint_for_testing<T>(amount, test_scenario::ctx(scenario));

            lending_market::deposit_reserve_liquidity<P, T>(
                &mut lending_market, 
                money, 
                &time,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
        };

        // verify that 100 ctokens were minted
        test_scenario::next_tx(scenario, owner);
        test_scenario::take_from_sender<Coin<CToken<P, T>>>(scenario)
    }


   public fun create_stats<P>(
        scenario: &mut Scenario,
        obligation_owner: address,
        obligation_cap: &ObligationCap<P>
    ): Stats {
        test_scenario::next_tx(scenario, obligation_owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let stats = lending_market::create_stats(
                &lending_market,
                obligation_cap,
                &time
            );


            test_scenario::return_shared(time);
            test_scenario::return_shared(lending_market);
            stats
        }
    }

    public fun update_stats<P, T>(
        scenario: &mut Scenario,
        stats: &mut Stats,
        obligation_owner: address,
        obligation_cap: &ObligationCap<P>
    ) {
        test_scenario::next_tx(scenario, obligation_owner);
        {
            let time = test_scenario::take_shared<Time>(scenario);
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);

            lending_market::update_stats<P, T>(
                &mut lending_market,
                obligation_cap,
                stats,
                &time,
                &price_cache
            );

            test_scenario::return_shared(time);
            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(price_cache);
        }
    }
     
    public fun create_obligation<P>(scenario: &mut Scenario, owner: address): ObligationCap<P> {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);
            
            lending_market::create_obligation<P>(
                &mut lending_market, 
                &time, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
        };
        
        test_scenario::next_tx(scenario, owner);
        {
            let obligation_cap_id = test_scenario::most_recent_id_for_sender<ObligationCap<P>>(scenario);
            test_scenario::take_from_sender_by_id<ObligationCap<P>>(
                scenario, 
                option::extract(&mut obligation_cap_id)
            )
        }
    }
    
    public fun deposit_ctokens_into_obligation<P, T>(
        scenario: &mut Scenario, 
        owner: address, 
        obligation_cap: &ObligationCap<P>,
        ctokens: Coin<CToken<P, T>>
    ) {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);

            lending_market::deposit_ctokens(
                &mut lending_market,
                obligation_cap,
                &time,
                ctokens,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
        }
    }

    public fun repay<P, T>(
        scenario: &mut Scenario, 
        owner: address, 
        obligation_cap: &ObligationCap<P>,
        stats: Stats,
        repay_amount: Coin<T>
    ) {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);

            lending_market::repay<P, T>(
                &mut lending_market,
                obligation_cap,
                stats,
                &time,
                repay_amount,
            );

            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
        };
    }

    public fun borrow<P, T>(
        scenario: &mut Scenario, 
        owner: address, 
        obligation_cap: &ObligationCap<P>,
        stats: Stats,
        borrow_amount: u64
    ): Coin<T> {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);

            lending_market::borrow<P, T>(
                &mut lending_market,
                obligation_cap,
                stats,
                &time,
                &price_cache,
                borrow_amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
            test_scenario::return_shared(price_cache);
        };

        test_scenario::next_tx(scenario, owner);
        let coins_id = test_scenario::most_recent_id_for_sender<Coin<T>>(scenario);
        test_scenario::take_from_sender_by_id<Coin<T>>(scenario, option::extract(&mut coins_id))
    }

    public fun withdraw<P, T>(
        scenario: &mut Scenario, 
        owner: address, 
        obligation_cap: &ObligationCap<P>,
        stats: Stats,
        withdraw_amount: u64
    ): Coin<CToken<P, T>> {
        test_scenario::next_tx(scenario, owner);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);

            lending_market::withdraw<P, T>(
                &mut lending_market,
                obligation_cap,
                stats,
                &time,
                &price_cache,
                withdraw_amount,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
            test_scenario::return_shared(price_cache);
        };

        test_scenario::next_tx(scenario, owner);
        let coins_id = test_scenario::most_recent_id_for_sender<Coin<CToken<P,T>>>(scenario);
        test_scenario::take_from_sender_by_id<Coin<CToken<P, T>>>(
            scenario, option::extract(&mut coins_id))
    }

    public fun liquidate<P, Debt, Collateral>(
        scenario: &mut Scenario, 
        liquidator: address, 
        obligation_id: ID,
        stats: Stats,
        repay_amount: Coin<Debt>
    ): Coin<CToken<P, Collateral>> {
        test_scenario::next_tx(scenario, liquidator);
        {
            let lending_market = test_scenario::take_shared<LendingMarket<P>>(scenario);
            let time = test_scenario::take_shared<Time>(scenario);
            let price_cache = test_scenario::take_shared<PriceCache>(scenario);

            lending_market::liquidate<P, Debt, Collateral>(
                &mut lending_market,
                obligation_id,
                stats,
                repay_amount,
                &time,
                &price_cache,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(lending_market);
            test_scenario::return_shared(time);
            test_scenario::return_shared(price_cache);
        };

        test_scenario::next_tx(scenario, liquidator);

        let coins_id = test_scenario::most_recent_id_for_sender<Coin<CToken<P,Collateral>>>(scenario);
        test_scenario::take_from_sender_by_id<Coin<CToken<P, Collateral>>>(
            scenario, option::extract(&mut coins_id))
    }
    
}