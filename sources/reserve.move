module suilend::reserve {
    use sui::balance::{Self, Balance, Supply};
    use suilend::decimal::{Decimal, Self};
    use suilend::interest_rate::{InterestRate, Self};

    #[test_only]
    use sui::sui::SUI;
    
    struct CToken<phantom T> has drop {}

    struct Reserve<phantom T> has store {
        last_update: u64,
        
        available_liquidity: Balance<T>,
        
        // this is a decimal bc we need to compound this value wrt interest rate
        borrowed_liquidity: Decimal,
        cumulative_borrow_rate: Decimal,

        ctoken_supply: Supply<CToken<T>>,
        
        interest_rate: InterestRate,
    }
    
    // errors
    const EInvalidTime: u64 = 0;
    
    // constants
    const SECONDS_IN_YEAR: u64 = 60 * 60 * 24 * 365;
    
    public fun create_reserve<T>(cur_time: u64): Reserve<T> {
        // TODO make this a function argument somehow
        let interest_rate = interest_rate::create_interest_rate(decimal::one());

        Reserve {
            last_update: cur_time,
            available_liquidity: balance::zero<T>(),
            borrowed_liquidity: decimal::zero(),
            cumulative_borrow_rate: decimal::one(),
            ctoken_supply: balance::create_supply<CToken<T>>(CToken<T> {}),
            interest_rate: interest_rate,
        }
    }
    
    // computes ctoken / token
    public fun ctoken_exchange_rate<T>(reserve: &Reserve<T>): Decimal {
        let available_liquidity = decimal::from(balance::value<T>(&reserve.available_liquidity));
        let ctoken_total_supply = decimal::from(balance::supply_value<CToken<T>>(&reserve.ctoken_supply));
        
        if (available_liquidity == decimal::zero() && ctoken_total_supply == decimal::zero()) {
            return decimal::one()
        };
        
        decimal::div(
            decimal::add(available_liquidity, reserve.borrowed_liquidity),
            ctoken_total_supply
        )
    }
    
    public fun borrow_utilization<T>(reserve: &Reserve<T>): Decimal {
        let available_liquidity = decimal::from(balance::value<T>(&reserve.available_liquidity));
        let denom = decimal::add(reserve.borrowed_liquidity, available_liquidity);

        if (denom == decimal::zero()) {
            return decimal::zero()
        };

        decimal::div(
            reserve.borrowed_liquidity,
            denom
        )
    }

    public fun compound_debt_and_interest<T>(reserve: &mut Reserve<T>, cur_time: u64) {
        assert!(reserve.last_update <= cur_time, EInvalidTime);
        
        let diff = cur_time - reserve.last_update;
        let apr = interest_rate::calculate_apr(reserve.interest_rate, borrow_utilization<T>(reserve));
        
        // we compound interest every second.
        // formula: I(t_n) = I(t_o) * (1 + apr / seconds_in_year) ^ (t_n - t_o)
        // where: 
        // - I(t) is the cumulative interest rate
        // - t_n is the new epoch time in seconds
        // - t_o is the old epoch time in seconds
        
        // instead of calculating (1 + apr / seconds_in_year) ^ (t_n - t_o), we approximate
        // by using (1 + apr * (t_n - t_o) / seconds_in_year). This should be good enough as long as 
        // interest is compounded at least once a day.
        // https://docs.youves.com/syntheticAssets/stableTokens/incentiveFeatures/interestRates/Interest-Rate-Calculation/#n-period-case
        let additional_interest = decimal::mul(
            decimal::add(
                decimal::one(),
                decimal::div(apr, decimal::from(SECONDS_IN_YEAR))
            ), 
            decimal::from(diff)
        );

        // update variables
        reserve.borrowed_liquidity = decimal::mul(reserve.borrowed_liquidity, additional_interest);
        reserve.cumulative_borrow_rate = decimal::mul(reserve.cumulative_borrow_rate, additional_interest);
    }
    
    // adds liquidity to reserve's supply and creates new ctokens. returns a balance.
    public fun deposit_liquidity_and_mint_ctokens<T>(reserve: &mut Reserve<T>, cur_time: u64, liquidity: Balance<T>): Balance<CToken<T>> {
        compound_debt_and_interest(reserve, cur_time);

        let exchange_rate = ctoken_exchange_rate<T>(reserve);

        // mint ctokens at the exchange rate
        let ctoken_mint_amount = decimal::to_u64(decimal::div(
            decimal::from(balance::value<T>(&liquidity)),
            exchange_rate
        ));
        

        // add liquidity
        balance::join<T>(&mut reserve.available_liquidity, liquidity);
        
        balance::increase_supply<CToken<T>>(&mut reserve.ctoken_supply, ctoken_mint_amount)
    }
    
    public fun borrow_liquidity<T>(reserve: &mut Reserve<T>, cur_time: u64, amount: u64): Balance<T> {
        compound_debt_and_interest(reserve, cur_time);
        
        reserve.borrowed_liquidity = decimal::add(reserve.borrowed_liquidity, decimal::from(amount));
        balance::split<T>(&mut reserve.available_liquidity, amount)
    }
    
    
    use std::debug::{Self};

    #[test]
    fun test_create_reserve(): Reserve<SUI> {

        let start_time = 1;
        
        // create reserve
        let reserve = create_reserve<SUI>(start_time);
        assert!(reserve.last_update == 1, 0);
        assert!(ctoken_exchange_rate(&reserve) == decimal::one(), 1);
        assert!(borrow_utilization(&reserve) == decimal::zero(), 2);
        

        // deposit liquidity
        {
            let sui = balance::create_for_testing<SUI>(100);
            let ctoken_balance = deposit_liquidity_and_mint_ctokens(&mut reserve, start_time, sui);

            // there's no debt to compound yet, so the ctoken exchange rate should be 1
            assert!(balance::value(&ctoken_balance) == 100, 3);
            balance::destroy_for_testing(ctoken_balance);
        };
        
        // borrow
        {
            let borrowed_sui = borrow_liquidity(&mut reserve, start_time, 10);

            assert!(balance::value(&borrowed_sui) == 10, 4);
            assert!(reserve.borrowed_liquidity == decimal::from(10), 5);
            assert!(balance::value(&reserve.available_liquidity) == 90, 6);
            
            let expected_util = decimal::div(decimal::from(10), decimal::from(100));
            assert!(borrow_utilization(&reserve) == expected_util, 7);
            assert!(ctoken_exchange_rate(&reserve) == decimal::one(), 8);

            balance::destroy_for_testing(borrowed_sui);
        };
        
        
        // deposit again 1 year later
        {
            let sui = balance::create_for_testing<SUI>(100);
            let ctoken_balance = deposit_liquidity_and_mint_ctokens(&mut reserve, start_time + SECONDS_IN_YEAR, sui);

            // additional interest: (1 + 0.1 / seconds_per_year) * seconds_per_year = 1.1
            // => borrowed_liquidity should be ~11
            // => cumulative_borrow_rate should be 1.1
            // => ctoken ratio should be (11 + 90) / (100) = 1.01

            debug::print<Balance<CToken<SUI>>>(&ctoken_balance);

            assert!(balance::value(&ctoken_balance) == 100, 3);
            balance::destroy_for_testing(ctoken_balance);
        };
        

        
        reserve
    }

    /* #[test] */
    /* fun test_c(): Reserve<SUI> { */
    /*     let start_time = 1; */
        
    /*     let reserve = create_reserve<SUI>(start_time); */
    /*     assert!(reserve.last_update == 1, 0); */
        
    /*     reserve */
    /* } */
    
    
}