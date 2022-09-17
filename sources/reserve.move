module suilend::reserve {
    use sui::balance::{Self, Balance, Supply};
    use suilend::decimal::{Decimal, Self, add, mul, div};
    use suilend::interest_rate::{InterestRate, Self};

    friend suilend::obligation;

    // TODO use lending market type here as well. ctokens need to be unique per lending_market, reserve pair
    struct CToken<phantom P, phantom T> has drop {}

    struct Reserve<phantom P, phantom T> has store {
        last_update: u64,
        
        available_liquidity: Balance<T>,
        
        // this is a decimal bc we need to compound this value wrt interest rate
        borrowed_liquidity: Decimal,
        cumulative_borrow_rate: Decimal,

        ctoken_supply: Supply<CToken<P, T>>,
        
        interest_rate: InterestRate,
    }
    
    spec Reserve {
        invariant decimal::raw_val(cumulative_borrow_rate) >= decimal::WAD;
    }
    
    // errors
    const EInvalidTime: u64 = 0;
    
    // constants
    const SECONDS_IN_YEAR: u64 = 60 * 60 * 24 * 365;
    
    public fun create_reserve<P, T>(cur_time: u64): Reserve<P, T> {
        // TODO make this a function argument somehow
        let interest_rate = interest_rate::create_interest_rate(decimal::one());

        Reserve {
            last_update: cur_time,
            available_liquidity: balance::zero(),
            borrowed_liquidity: decimal::zero(),
            cumulative_borrow_rate: decimal::one(),
            ctoken_supply: balance::create_supply(CToken<P, T> {}),
            interest_rate: interest_rate,
        }
    }
    
    // computes ctoken / token
    public fun ctoken_exchange_rate<P, T>(reserve: &Reserve<P, T>): Decimal {
        let available_liquidity = decimal::from(balance::value(&reserve.available_liquidity));
        let ctoken_total_supply = decimal::from(balance::supply_value(&reserve.ctoken_supply));
        
        if (available_liquidity == decimal::zero() && ctoken_total_supply == decimal::zero()) {
            return decimal::one()
        };
        
        div(
            add(available_liquidity, reserve.borrowed_liquidity),
            ctoken_total_supply
        )
    }
    
    public fun borrow_utilization<P, T>(reserve: &Reserve<P, T>): Decimal {
        let available_liquidity = decimal::from(balance::value(&reserve.available_liquidity));
        let denom = add(reserve.borrowed_liquidity, available_liquidity);

        if (denom == decimal::zero()) {
            return decimal::zero()
        };

        div(
            reserve.borrowed_liquidity,
            denom
        )
    }
    
    public fun cumulative_borrow_rate<P, T>(reserve: &Reserve<P, T>): Decimal {
        reserve.cumulative_borrow_rate
    }
    
    spec borrow_utilization {
        // <= 100%
        ensures decimal::raw_val(result) <= decimal::WAD;
    }

    public fun compound_debt_and_interest<P, T>(reserve: &mut Reserve<P, T>, cur_time: u64) {
        assert!(reserve.last_update <= cur_time, EInvalidTime);
        
        let diff = cur_time - reserve.last_update;
        if (diff == 0) {
            return
        };

        let apr = interest_rate::calculate_apr(reserve.interest_rate, borrow_utilization(reserve));
        
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
        let additional_interest = add(
            decimal::one(),
            mul(
                apr,
                div(decimal::from(diff), decimal::from(SECONDS_IN_YEAR))
            )
        );

        // update variables
        reserve.borrowed_liquidity = mul(reserve.borrowed_liquidity, additional_interest);
        reserve.cumulative_borrow_rate = mul(reserve.cumulative_borrow_rate, additional_interest);
        reserve.last_update = cur_time;
    }
    
    spec compound_debt_and_interest {
        ensures reserve.last_update >= old(reserve.last_update);
        ensures decimal::ge(reserve.borrowed_liquidity, old(reserve.borrowed_liquidity));
        ensures decimal::ge(reserve.cumulative_borrow_rate, old(reserve.cumulative_borrow_rate));

        ensures decimal::raw_val(reserve.cumulative_borrow_rate) >= decimal::WAD;
    }
    
    // adds liquidity to reserve's supply and creates new ctokens. returns a balance.
    public fun deposit_liquidity_and_mint_ctokens<P, T>(reserve: &mut Reserve<P, T>, cur_time: u64, liquidity: Balance<T>): Balance<CToken<P, T>> {
        compound_debt_and_interest(reserve, cur_time);

        let exchange_rate = ctoken_exchange_rate(reserve);

        // mint ctokens at the exchange rate
        let ctoken_mint_amount = decimal::to_u64(div(
            decimal::from(balance::value(&liquidity)),
            exchange_rate
        ));

        balance::join(&mut reserve.available_liquidity, liquidity);
        balance::increase_supply(&mut reserve.ctoken_supply, ctoken_mint_amount)
    }
    
    spec deposit_liquidity_and_mint_ctokens {
        ensures reserve.last_update >= old(reserve.last_update);
        
        // TODO invariant: ctoken ratio is >= 1
        // TODO assert that the ctoken ratio doesn't change by much
        // TODO assert that ctokens * ctoken_ratio <= liquidity amount
    }
    
    // TODO make sure only obligation can use this function
    public(friend) fun borrow_liquidity<P, T>(reserve: &mut Reserve<P, T>, cur_time: u64, amount: u64): Balance<T> {
        compound_debt_and_interest(reserve, cur_time);
        
        reserve.borrowed_liquidity = add(reserve.borrowed_liquidity, decimal::from(amount));
        balance::split(&mut reserve.available_liquidity, amount)
    }
    
    public fun redeem_ctokens_for_liquidity<P, T>(reserve: &mut Reserve<P, T>, cur_time: u64, ctokens: Balance<CToken<P, T>>): Balance<T> {
        compound_debt_and_interest(reserve, cur_time);
        
        let exchange_rate = ctoken_exchange_rate(reserve);

        // redeem ctokens at the exchange rate
        let liquidity_amount = decimal::to_u64(mul(
            decimal::from(balance::value(&ctokens)),
            exchange_rate
        ));

        balance::decrease_supply(&mut reserve.ctoken_supply, ctokens);
        balance::split(&mut reserve.available_liquidity, liquidity_amount)
    }
    
    #[test_only]
    struct POOLEY has drop {}
    
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_create_reserve(): Reserve<POOLEY, SUI> {

        let start_time = 1;
        
        // create reserve
        let reserve = create_reserve<POOLEY, SUI>(start_time);
        assert!(reserve.last_update == 1, 0);
        assert!(ctoken_exchange_rate(&reserve) == decimal::one(), 1);
        assert!(borrow_utilization(&reserve) == decimal::zero(), 2);
        
        // deposit liquidity
        {
            let sui = balance::create_for_testing<SUI>(100);
            let ctoken_balance = deposit_liquidity_and_mint_ctokens(&mut reserve, start_time, sui);

            // there's no debt to compound yet, so the ctoken exchange rate should be 1
            assert!(balance::value(&ctoken_balance) == 100, 3);
            assert!(balance::supply_value(&reserve.ctoken_supply) == 100, 3);
            balance::destroy_for_testing(ctoken_balance);
        };
        
        // borrow
        {
            let borrowed_sui = borrow_liquidity(&mut reserve, start_time, 10);

            assert!(balance::value(&borrowed_sui) == 10, 4);
            assert!(reserve.borrowed_liquidity == decimal::from(10), 5);
            assert!(balance::value(&reserve.available_liquidity) == 90, 6);
            
            let expected_util = div(decimal::from(10), decimal::from(100));
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

            assert!(balance::value(&ctoken_balance) == 99, balance::value(&ctoken_balance));

            let exchange_rate = ctoken_exchange_rate(&reserve);
            assert!(decimal::is_close(exchange_rate, decimal::from_percent(101)), 0);

            // 11 / 200 = 5.5% => 550bps
            let borrow_util = borrow_utilization(&reserve);
            assert!(decimal::is_close(borrow_util, decimal::from_bps(550)), decimal::rounded(borrow_util));
            assert!(decimal::is_close(reserve.borrowed_liquidity, decimal::from(11)), 0);

            balance::destroy_for_testing(ctoken_balance);
        };
        
        // withdraw again 1 year after the deposit
        {
            let ctoken_balance = balance::create_for_testing<CToken<POOLEY, SUI>>(100);
            let liquidity_amount = redeem_ctokens_for_liquidity(&mut reserve, start_time + 2 * SECONDS_IN_YEAR, ctoken_balance);
            
            // borrowed liquidity should be 10 * 1.1 * (1 + 0.055/ seconds_per_year) * seconds_per_year ~= 116.
            assert!(
                decimal::is_close(reserve.borrowed_liquidity, decimal::from_percent(1160)), 
                decimal::rounded(reserve.borrowed_liquidity));

            // => ctoken ratio should be (12.1 + 190) / (100 + 99) => 1.015578
            // => redeemed liquidity amount should be 100 * 1.015578 ~= 101.5578 = 101 bc we floor
            assert!(balance::value(&liquidity_amount) == 101, 0);

            balance::destroy_for_testing(liquidity_amount);
        };
        
        reserve
    }
}