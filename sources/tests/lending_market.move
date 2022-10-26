#[test_only]
module suilend::test_lm {
    use suilend::test_helpers::{
        create_time,
        create_price_cache,
        add_price_info,
        create_lending_market,
        add_reserve,
        deposit_reserve_liquidity,
        create_obligation,
        deposit_ctokens_into_obligation,
        update_price,
        create_stats,
        update_stats,
        borrow,
        withdraw,
        repay,
        liquidate
    };
    use suilend::lending_market::{obligation_id, destroy_obligation_cap_for_testing};
    use suilend::obligation::{Self};
    use sui::test_scenario::{Self};
    use sui::sui::SUI;
    use sui::coin::Self;
    use suilend::decimal::{Self};
    /* use std::debug; */

    struct TEST_LM has drop {}
    struct USDC has drop {}
    
    // 10^9
    const MIST_TO_SUI: u64 = 1000000000;
    const USDC_DECIMAL: u64 = 1000000;

    #[test]
    fun lending_market_borrow_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = test_scenario::begin(owner);
        
        create_time(&mut scenario, owner, start_time);
        create_price_cache(&mut scenario, owner);

        // SUI is $10
        add_price_info<SUI>(&mut scenario, owner, 10, 0, 9);

        create_lending_market(&mut scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(&mut scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(&mut scenario, rando_1, 100 * MIST_TO_SUI);
        assert!(coin::value(&ctokens) == 100 * MIST_TO_SUI, coin::value(&ctokens));

        let obligation_cap = create_obligation<TEST_LM>(&mut scenario, rando_1);
        deposit_ctokens_into_obligation<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, ctokens);

        // update price of SUI
        update_price<SUI>(&mut scenario, owner, 20, 0);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to borrow some coins
        let coins = borrow<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, stats, 80 * MIST_TO_SUI);
        assert!(coin::value(&coins) == 80 * MIST_TO_SUI, coin::value(&coins) / MIST_TO_SUI);
        coin::destroy_for_testing(coins);
        
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=8)] // borrow is too large
    fun lending_market_borrow_over_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = test_scenario::begin(owner);
        
        create_time(&mut scenario, owner, start_time);
        create_price_cache(&mut scenario, owner);

        // SUI is $10
        add_price_info<SUI>(&mut scenario, owner, 10, 0, 9);

        create_lending_market(&mut scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(&mut scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(&mut scenario, rando_1, 100 * MIST_TO_SUI);
        assert!(coin::value(&ctokens) == 100 * MIST_TO_SUI, coin::value(&ctokens));

        let obligation_cap = create_obligation<TEST_LM>(&mut scenario, rando_1);
        deposit_ctokens_into_obligation<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, ctokens);

        // update price of SUI
        update_price<SUI>(&mut scenario, owner, 20, 0);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to borrow some coins
        let coins = borrow<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, stats, 81 * MIST_TO_SUI);
        assert!(coin::value(&coins) == 80 * MIST_TO_SUI, coin::value(&coins) / MIST_TO_SUI);
        coin::destroy_for_testing(coins);
        
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
        test_scenario::end(scenario);
    }

   #[test]
    fun lending_market_withdraw_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        let start_time = 1;
        
        let scenario = test_scenario::begin(owner);
        
        create_time(&mut scenario, owner, start_time);
        create_price_cache(&mut scenario, owner);

        // SUI is $10
        add_price_info<SUI>(&mut scenario, owner, 10, 0, 9);

        create_lending_market(&mut scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(&mut scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(&mut scenario, rando_1, 100 * MIST_TO_SUI);

        let obligation_cap = create_obligation<TEST_LM>(&mut scenario, rando_1);
        deposit_ctokens_into_obligation<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, ctokens);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to borrow some coins
        let coins = borrow<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, stats, 60 * MIST_TO_SUI);
        
        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to withdraw. with a 80% LTV I should be able to withdraw 25 SUI. 
        // new ltv is 60/75 = 0.8
        // the ctoken ratio is 1:1 (bc time hasn't passed yet).
        let withdrawn_ctokens = withdraw<TEST_LM, SUI>(
            &mut scenario, 
            rando_1, 
            &obligation_cap, 
            stats,
            25 * MIST_TO_SUI
        );
        
        coin::destroy_for_testing(withdrawn_ctokens);
        coin::destroy_for_testing(coins);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=10)] // Withdraw is too large
    fun lending_market_withdraw_over_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        let start_time = 1;
        
        let scenario = test_scenario::begin(owner);
        
        create_time(&mut scenario, owner, start_time);
        create_price_cache(&mut scenario, owner);

        // SUI is $10
        add_price_info<SUI>(&mut scenario, owner, 10, 0, 9);

        create_lending_market(&mut scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(&mut scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(&mut scenario, rando_1, 100 * MIST_TO_SUI);

        let obligation_cap = create_obligation<TEST_LM>(&mut scenario, rando_1);
        deposit_ctokens_into_obligation<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, ctokens);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to borrow some coins
        let coins = borrow<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, stats, 60 * MIST_TO_SUI);
        
        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to withdraw. with a 80% LTV I should be able to withdraw 25 SUI. 
        // new ltv is 60/75 = 0.8
        // the ctoken ratio is 1:1 (bc time hasn't passed yet).
        let withdrawn_ctokens = withdraw<TEST_LM, SUI>(
            &mut scenario, 
            rando_1, 
            &obligation_cap, 
            stats,
            25 * MIST_TO_SUI + 1
        );
        
        coin::destroy_for_testing(withdrawn_ctokens);
        coin::destroy_for_testing(coins);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun lending_market_repay() {
        let owner = @0x26;
        let rando_1 = @0x27;
        let start_time = 1;
        
        let scenario = test_scenario::begin(owner);
        
        create_time(&mut scenario, owner, start_time);
        create_price_cache(&mut scenario, owner);

        // SUI is $10
        add_price_info<SUI>(&mut scenario, owner, 10, 0, 9);

        create_lending_market(&mut scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(&mut scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(&mut scenario, rando_1, 100 * MIST_TO_SUI);

        let obligation_cap = create_obligation<TEST_LM>(&mut scenario, rando_1);
        deposit_ctokens_into_obligation<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, ctokens);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        // try to borrow some coins
        let coins = borrow<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, stats, 60 * MIST_TO_SUI);
        
        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);
        
        repay<TEST_LM, SUI>(&mut scenario, rando_1, &obligation_cap, stats, coins);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, rando_1, &obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, rando_1, &obligation_cap);

        // withdraw everything
        let withdrawn_ctokens = withdraw<TEST_LM, SUI>(
            &mut scenario, 
            rando_1, 
            &obligation_cap, 
            stats,
            100 * MIST_TO_SUI
        );
        
        coin::destroy_for_testing(withdrawn_ctokens);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun lending_market_liquidate() {
        let owner = @0x26;
        let violator = @0x27;
        let liquidator = @0x28;
        let start_time = 1;
        
        let scenario = test_scenario::begin(owner);
        
        create_time(&mut scenario, owner, start_time);
        create_price_cache(&mut scenario, owner);

        // SUI is $20
        add_price_info<SUI>(&mut scenario, owner, 20, 0, 9);
        add_price_info<USDC>(&mut scenario, owner, 1, 0, 6);

        create_lending_market(&mut scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(&mut scenario, owner);
        add_reserve<TEST_LM, USDC>(&mut scenario, owner);
        
        // deposit 900 USDC
        let ctokens = deposit_reserve_liquidity<TEST_LM, USDC>(&mut scenario, violator, 900 * USDC_DECIMAL);
        coin::destroy_for_testing(ctokens);

        // violator deposits 100 SUI and borrow 900 USDC
        let violator_obligation_cap = {
            let obligation_cap = create_obligation<TEST_LM>(&mut scenario, violator);
        
            let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(&mut scenario, violator, 100 * MIST_TO_SUI);
            deposit_ctokens_into_obligation<TEST_LM, SUI>(&mut scenario, violator, &obligation_cap, ctokens);

            // refresh obligation
            let stats = create_stats<TEST_LM>(&mut scenario, violator, &obligation_cap);
            update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, violator, &obligation_cap);
        
            // try to borrow some coins
            let coins = borrow<TEST_LM, USDC>(&mut scenario, violator, &obligation_cap, stats, 900 * USDC_DECIMAL);
            coin::destroy_for_testing(coins);
        
            obligation_cap
        };
        
        // SUI is $100
        update_price<SUI>(&mut scenario, owner, 10, 0);

        // refresh obligation
        let stats = create_stats<TEST_LM>(&mut scenario, violator, &violator_obligation_cap);
        update_stats<TEST_LM, USDC>(&mut scenario, &mut stats, violator, &violator_obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, violator, &violator_obligation_cap);

        let coins = coin::mint_for_testing<USDC>(180 * USDC_DECIMAL, test_scenario::ctx(&mut scenario));
        let ctokens = liquidate<TEST_LM, USDC, SUI>(
            &mut scenario, 
            liquidator, 
            obligation_id(&violator_obligation_cap), 
            stats,
            coins
        );

        // refresh everything again for clarity
        let stats = create_stats<TEST_LM>(&mut scenario, violator, &violator_obligation_cap);
        update_stats<TEST_LM, USDC>(&mut scenario, &mut stats, violator, &violator_obligation_cap);
        update_stats<TEST_LM, SUI>(&mut scenario, &mut stats, violator, &violator_obligation_cap);

        // check stuff
        {
            assert!(obligation::usd_borrow_value(&stats) == decimal::from(900 * 4 / 5), 0);

            // 1000 - 900 * 0.2 * 1.05 = 811
            assert!(obligation::usd_deposit_value(&stats) == decimal::from(811), 0);
        };
        
        coin::destroy_for_testing(ctokens);
        obligation::destroy_stats(stats);
        destroy_obligation_cap_for_testing(violator_obligation_cap);
        test_scenario::end(scenario);
    }
}