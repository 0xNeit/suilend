#[test_only]
module suilend::test_obligation_borrow {
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
    };
    use sui::test_scenario::{Self};
    use sui::sui::SUI;
    use sui::coin::Self;

    struct POOLEY has drop {}
    
    // 10^9
    const MIST_TO_SUI: u64 = 1000000000;

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
        let coins = borrow<POOLEY, SUI>(scenario, rando_1, 80 * MIST_TO_SUI);
        assert!(coin::value(&coins) == 80 * MIST_TO_SUI, coin::value(&coins) / MIST_TO_SUI);
        coin::destroy_for_testing(coins);
        
        // refresh obligation
        reset_stats<POOLEY>(scenario, rando_1);
        update_stats_borrow<POOLEY, SUI>(scenario, rando_1);
        update_stats_deposit<POOLEY, SUI>(scenario, rando_1);
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
        let coins = borrow<POOLEY, SUI>(scenario, rando_1, 81 * MIST_TO_SUI);
        
        coin::destroy_for_testing(coins);
    }

}