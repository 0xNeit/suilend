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
        add_deposit_info_to_obligation,
        deposit_ctokens_into_obligation,
        update_price,
        reset_stats,
        update_stats_deposit,
        update_stats_borrow,
        add_borrow_info_to_obligation,
        borrow,
        withdraw,
        repay,
        get_obligation,
        liquidate
    };
    use suilend::lending_market::{destroy_obligation_cap_for_testing};
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
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 10, 0, 9);

        create_lending_market(scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);
        assert!(coin::value(&ctokens) == 100 * MIST_TO_SUI, coin::value(&ctokens));

        let obligation_cap = create_obligation<TEST_LM>(scenario, rando_1);
        add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, ctokens);

        // update price of SUI
        update_price<SUI>(scenario, owner, 20, 0);

        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        // try to borrow some coins
        add_borrow_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        let coins = borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 80 * MIST_TO_SUI);
        assert!(coin::value(&coins) == 80 * MIST_TO_SUI, coin::value(&coins) / MIST_TO_SUI);
        coin::destroy_for_testing(coins);
        
        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
    }

    #[test]
    #[expected_failure(abort_code=8)] // borrow is too large
    fun lending_market_borrow_more_than_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 10, 0, 9);

        create_lending_market(scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);
        assert!(coin::value(&ctokens) == 100 * MIST_TO_SUI, coin::value(&ctokens));

        let obligation_cap = create_obligation<TEST_LM>(scenario, rando_1);
        add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, ctokens);

        // update price of SUI
        update_price<SUI>(scenario, owner, 20, 0);

        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        // try to borrow some coins
        add_borrow_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        let coins = borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 81 * MIST_TO_SUI);
        
        coin::destroy_for_testing(coins);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
    }

   #[test]
    fun lending_market_withdraw_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 10, 0, 9);

        create_lending_market(scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);

        let obligation_cap = create_obligation<TEST_LM>(scenario, rando_1);
        add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, ctokens);

        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        // try to borrow some coins
        add_borrow_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        let coins = borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 60 * MIST_TO_SUI);
        
        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        // try to withdraw. with a 80% LTV I should be able to withdraw 25 SUI. 
        // new ltv is 60/75 = 0.8
        // the ctoken ratio is 1:1 (bc time hasn't passed yet).
        let withdrawn_ctokens = withdraw<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 25 * MIST_TO_SUI);
        
        coin::destroy_for_testing(withdrawn_ctokens);
        coin::destroy_for_testing(coins);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
    }

    #[test]
    #[expected_failure(abort_code=10)] // Withdraw is too large
    fun lending_market_withdraw_over_max_ltv() {
        let owner = @0x26;
        let rando_1 = @0x27;
        /* let rando_2 = @0x28; */
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 10, 0, 9);

        create_lending_market(scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);

        let obligation_cap = create_obligation<TEST_LM>(scenario, rando_1);
        add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, ctokens);

        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        // try to borrow some coins
        add_borrow_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        let coins = borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 60 * MIST_TO_SUI);
        
        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        let withdrawn_ctokens = withdraw<TEST_LM, SUI>(
            scenario, 
            rando_1, 
            &obligation_cap, 
            25 * MIST_TO_SUI + 1
        );
        
        coin::destroy_for_testing(withdrawn_ctokens);
        coin::destroy_for_testing(coins);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
    }

    #[test]
    fun lending_market_repay() {
        let owner = @0x26;
        let rando_1 = @0x27;
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 10, 0, 9);

        create_lending_market(scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(scenario, owner);

        let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, rando_1, 100 * MIST_TO_SUI);

        let obligation_cap = create_obligation<TEST_LM>(scenario, rando_1);
        add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, ctokens);

        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        // try to borrow some coins
        add_borrow_info_to_obligation<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        let coins = borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 60 * MIST_TO_SUI);
        
        // refresh obligation
        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        repay<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, coins);

        reset_stats<TEST_LM>(scenario, rando_1, &obligation_cap);
        update_stats_borrow<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, rando_1, &obligation_cap);
        
        let coins = withdraw<TEST_LM, SUI>(scenario, rando_1, &obligation_cap, 100 * MIST_TO_SUI);
        coin::destroy_for_testing(coins);
        destroy_obligation_cap_for_testing<TEST_LM>(obligation_cap);
    }

    #[test]
    fun lending_market_liquidate() {
        let owner = @0x26;
        let violator = @0x27;
        let liquidator = @0x28;
        let start_time = 1;
        
        let scenario = &mut test_scenario::begin(&owner);
        
        create_time(scenario, owner, start_time);
        create_price_cache(scenario, owner);

        // SUI is $10
        add_price_info<SUI>(scenario, owner, 20, 0, 9);
        add_price_info<USDC>(scenario, owner, 1, 0, 6);

        create_lending_market(scenario, TEST_LM {}, owner);
        add_reserve<TEST_LM, SUI>(scenario, owner);
        add_reserve<TEST_LM, USDC>(scenario, owner);
        
        // deposit 900 USDC
        let ctokens = deposit_reserve_liquidity<TEST_LM, USDC>(scenario, violator, 900 * USDC_DECIMAL);
        coin::destroy_for_testing(ctokens);

        // violator deposits 100 SUI and borrow 900 USDC
        let violator_obligation_cap = {
            let obligation_cap = create_obligation<TEST_LM>(scenario, violator);
            add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, violator, &obligation_cap);
        
            let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, violator, 100 * MIST_TO_SUI);
            deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, violator, &obligation_cap, ctokens);

            // refresh obligation
            reset_stats<TEST_LM>(scenario, violator, &obligation_cap);
            update_stats_deposit<TEST_LM, SUI>(scenario, violator, &obligation_cap);
        
            // try to borrow some coins
            add_borrow_info_to_obligation<TEST_LM, USDC>(scenario, violator, &obligation_cap);
            let coins = borrow<TEST_LM, USDC>(scenario, violator, &obligation_cap, 900 * USDC_DECIMAL);
            coin::destroy_for_testing(coins);
        
            obligation_cap
        };
        
        // liquidator deposits 1000 USDC
        let liquidator_obligation_cap = {
            let obligation_cap = create_obligation<TEST_LM>(scenario, liquidator);
            add_deposit_info_to_obligation<TEST_LM, SUI>(scenario, liquidator, &obligation_cap);
            add_borrow_info_to_obligation<TEST_LM, USDC>(scenario, liquidator, &obligation_cap);
        
            let ctokens = deposit_reserve_liquidity<TEST_LM, SUI>(scenario, liquidator, 100 * MIST_TO_SUI);
            deposit_ctokens_into_obligation<TEST_LM, SUI>(scenario, liquidator, &obligation_cap, ctokens);

            obligation_cap
        };
        
        // SUI is $100
        update_price<SUI>(scenario, owner, 10, 0);

        // refresh obligation
        reset_stats<TEST_LM>(scenario, violator, &violator_obligation_cap);
        update_stats_borrow<TEST_LM, USDC>(scenario, violator, &violator_obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, violator, &violator_obligation_cap);

        reset_stats<TEST_LM>(scenario, liquidator, &liquidator_obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, liquidator, &liquidator_obligation_cap);
        update_stats_borrow<TEST_LM, USDC>(scenario, liquidator, &liquidator_obligation_cap);
            
        liquidate<TEST_LM, USDC, SUI>(
            scenario, 
            liquidator, 
            &violator_obligation_cap, 
            &liquidator_obligation_cap
        );

        // refresh everything again for clarity
        reset_stats<TEST_LM>(scenario, violator, &violator_obligation_cap);
        update_stats_borrow<TEST_LM, USDC>(scenario, violator, &violator_obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, violator, &violator_obligation_cap);

        reset_stats<TEST_LM>(scenario, liquidator, &liquidator_obligation_cap);
        update_stats_deposit<TEST_LM, SUI>(scenario, liquidator, &liquidator_obligation_cap);
        update_stats_borrow<TEST_LM, USDC>(scenario, liquidator, &liquidator_obligation_cap);
        
        // check stuff
        {
            let violator_obligation = get_obligation(scenario, violator, &violator_obligation_cap);
            assert!(obligation::usd_borrow_value(&violator_obligation) == decimal::from(900 * 4 / 5), 0);
            // 1000 - 900 * 0.2 * 1.05 = 811
            assert!(obligation::usd_deposit_value(&violator_obligation) == decimal::from(811), 0);
            test_scenario::return_owned(scenario, violator_obligation);
        };

        {
            let liquidator_obligation = get_obligation(scenario, liquidator, &liquidator_obligation_cap);
            // 900 * 0.2 = 180
            assert!(obligation::usd_borrow_value(&liquidator_obligation) == decimal::from(180), 0);
            // 100 * $10 (existing collateral) + 900 * 0.2 * 10.5 = 1189
            assert!(obligation::usd_deposit_value(&liquidator_obligation) == decimal::from(1189), 0);
            test_scenario::return_owned(scenario, liquidator_obligation);
        };

        destroy_obligation_cap_for_testing<TEST_LM>(violator_obligation_cap);
        destroy_obligation_cap_for_testing<TEST_LM>(liquidator_obligation_cap);
    }
}