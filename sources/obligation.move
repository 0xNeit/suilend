/// An obligation tracks a user's deposits and borrows in a given lending market.
/// A user can own more than 1 obligation for a given lending market.
/// The structure of this module will change significantly once Sui supports
/// dynamic access of child objects.

module suilend::obligation {
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use suilend::decimal::{
        Decimal, 
        Self, 
        add, 
        sub, 
        mul, 
        div, 
        le, 
        from_percent, 
        from, 
        floor, 
        ge, 
        one
    };
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{TxContext};
    use suilend::oracle::{Self, PriceCache};
    use suilend::reserve::{Self, Reserve, CToken};
    use suilend::time::{Self, Time};
    use sui::object_bag::{Self, ObjectBag};

    // errors
    const EInvalidDeposit: u64 = 0;
    const ESeqnumStillValid: u64 = 1;
    const EBorrowAlreadyHandled: u64 = 2;
    const EPriceTooStale: u64 = 3;
    const ESeqnumIsStale: u64 = 4;
    const EDepositAlreadyHandled: u64 = 5;
    const EInvalidStats: u64 = 6;
    const EReserveIsStale: u64 = 7;
    const EBorrowIsTooLarge: u64 = 8;
    const EUnauthorized: u64 = 9;
    const EWithdrawIsTooLarge: u64 = 10;
    const ERepayIsTooLarge: u64 = 11;
    const EHealthy: u64 = 12;
    
    const PRICE_STALENESS_THRESHOLD_S: u64 = 30;

    const MAX_LOAN_TO_VALUE_PCT: u64 = 80;
    const LIQUIDATION_THRESHOLD_PCT: u64 = 90;
    
    // percentage of an obligation that can be liquidated at once.
    const CLOSE_FACTOR_PCT: u64 = 20;
    const LIQUIDATOR_BONUS_PCT: u64 = 5;
    
    struct Obligation<phantom P> has key, store {
        id: UID,
        owner: address,
        deposits: ObjectBag,
        borrows: ObjectBag,
        
        // gets incremented on every deposit or borrow call.
        // used to verify validity of Stats object during borrows,
        // withdraws, and liquidations.
        seqnum: u64,
    }
    
    // dynamic fields owned by obligation
    struct Deposit<phantom T> has key, store {
        id: UID,
        balance: Balance<T>,
        usd_value: Decimal,
    }

    struct Borrow<phantom T> has key, store {
        id: UID,
        borrowed_amount: Decimal, // needs to be a decimal bc we compound debt
        cumulative_borrow_rate_snapshot: Decimal,
        
        usd_value: Decimal,
    }
    
    // used as Name field in deposit and borrow bags
    struct Name<phantom T> has copy, drop, store {}
    
    // hot potato struct that tracks obligation stats
    struct Stats {
        seqnum: u64,
        obligation_id: ID,

        created: u64,
        
        usd_borrow_value: Decimal,
        usd_deposit_value: Decimal,
        
        handled_positions: VecSet<ID>,
    }
    
    /* getter functions */
    public fun usd_borrow_value(stats: &Stats): Decimal {
        stats.usd_borrow_value
    }

    public fun usd_deposit_value(stats: &Stats): Decimal {
        stats.usd_deposit_value
    }
    
    /* entry functions */
    public fun create_obligation<P>(owner: address, ctx: &mut TxContext): Obligation<P> {
        Obligation<P> {
            id: object::new(ctx),
            owner,
            deposits: object_bag::new(ctx),
            borrows: object_bag::new(ctx),
            seqnum: 0,
        }
    }
    
    // deposit ctokens into obligation. it's not difficult to extend this to deposit non-ctokens as well,
    // if users want that functionality. similar to "protected collateral" in euler finance.
    public fun deposit<P, T>(
        obligation: &mut Obligation<P>, 
        deposit_balance: Balance<CToken<P, T>>, 
        ctx: &mut TxContext
    ) {
        // find or add deposit to obligation
        let deposit: &mut Deposit<CToken<P, T>> = {
            if (!object_bag::contains(&mut obligation.deposits, Name<T> {})) {
                let deposit = Deposit<CToken<P, T>> {
                    id: object::new(ctx),
                    balance: balance::zero(),
                    usd_value: decimal::zero()
                };

                object_bag::add(&mut obligation.deposits, Name<CToken<P, T>> {}, deposit);
            };

            object_bag::borrow_mut(&mut obligation.deposits, Name<CToken<P, T>>{})
        };

        balance::join(&mut deposit.balance, deposit_balance);
        obligation.seqnum = obligation.seqnum + 1;
    }
    
    public fun borrow<P, T>(
        obligation: &mut Obligation<P>, 
        stats: Stats,
        reserve: &mut Reserve<P, T>, 
        time: &Time, 
        price_cache: &PriceCache, 
        borrow_amount: u64,
        ctx: &mut TxContext
    ): Balance<T> {
        assert!(is_stats_valid(obligation, &stats, time::get_epoch_s(time)), EInvalidStats);

        // find or add borrow to obligation
        let borrow: &mut Borrow<T> = {
            if (!object_bag::contains(&mut obligation.borrows, Name<T> {})) {
                let borrow = Borrow<T> {
                    id: object::new(ctx),
                    borrowed_amount: decimal::zero(),
                    cumulative_borrow_rate_snapshot: decimal::one(),
                    usd_value: decimal::zero()
                };

                object_bag::add(&mut obligation.borrows, Name<T> {}, borrow);
            };

            object_bag::borrow_mut(&mut obligation.borrows, Name<T>{})
        };
        
        let borrowed_liquidity = reserve::borrow_liquidity(reserve, time::get_epoch_s(time), borrow_amount);

        // check that we don't exceed our borrow limits
        let borrow_usd_value = oracle::market_value<T>(price_cache, borrow_amount);

        // safety: the stats object is guaranteed to be created in the same tx as the borrow call.
        // therefore the cumulative borrow rate snapshot is up to date, and the total borrow value
        // is borrow_usd_value + stats.usd_borrow_value
        let new_borrow_usd_value = add(borrow_usd_value, stats.usd_borrow_value);

        assert!(
            le(
                new_borrow_usd_value, 
                mul(stats.usd_deposit_value, from_percent(MAX_LOAN_TO_VALUE_PCT))
            ),
            EBorrowIsTooLarge
        );
        
        // update state 
        borrow.borrowed_amount = add(borrow.borrowed_amount, decimal::from(borrow_amount));
        borrow.usd_value = new_borrow_usd_value;
        obligation.seqnum = obligation.seqnum + 1;
        
        // delete stats object bc it's no longer valid
        destroy_stats(stats);

        borrowed_liquidity
    }
    
    public fun destroy_stats(stats: Stats) {
        let Stats { 
            seqnum: _, 
            obligation_id: _, 
            created: _, 
            usd_borrow_value: _, 
            usd_deposit_value: _, 
            handled_positions: _, 
        } = stats;
    }

    /// Withdraw ctokens from obligation
    public fun withdraw<P, T>(
        obligation: &mut Obligation<P>, 
        stats: Stats,
        reserve: &Reserve<P, T>, 
        time: &Time, 
        price_cache: &PriceCache, 
        withdraw_ctoken_amount: u64
    ): Balance<CToken<P, T>> {
        assert!(is_stats_valid(obligation, &stats, time::get_epoch_s(time)), EInvalidStats);
        
        let deposit: &mut Deposit<CToken<P, T>> = object_bag::borrow_mut(
            &mut obligation.deposits, Name<CToken<P, T>>{});

        // check that we don't exceed our borrow limits
        let withdraw_liquidity_amount = floor(mul(
            reserve::ctoken_exchange_rate(reserve),
            from(withdraw_ctoken_amount)
        ));

        let withdraw_usd_value = oracle::market_value<T>(price_cache, withdraw_liquidity_amount);
        let new_usd_deposit_value = sub(stats.usd_deposit_value, withdraw_usd_value);

        assert!(
            le(
                stats.usd_borrow_value,
                mul(new_usd_deposit_value, from_percent(MAX_LOAN_TO_VALUE_PCT))
            ),
            EWithdrawIsTooLarge
        );
        
        // update state
        deposit.usd_value = new_usd_deposit_value;
        obligation.seqnum = obligation.seqnum + 1;
        destroy_stats(stats);

        balance::split(&mut deposit.balance, withdraw_ctoken_amount)
    }

    /// repay part of a loan
    public fun repay<P, T>(
        obligation: &mut Obligation<P>, 
        stats: Stats,
        reserve: &mut Reserve<P, T>, 
        time: &Time, 
        repay_balance: Balance<T>,
    ) {
        assert!(is_stats_valid(obligation, &stats, time::get_epoch_s(time)), EInvalidStats);

        let borrow: &mut Borrow<T> = object_bag::borrow_mut(&mut obligation.borrows, Name<T>{});
        borrow.borrowed_amount = sub(
            borrow.borrowed_amount,
            decimal::from(balance::value(&repay_balance))
        );

        reserve::repay_liquidity(reserve, time::get_epoch_s(time), repay_balance);
        obligation.seqnum = obligation.seqnum + 1;
        destroy_stats(stats);
    }
    
    /// Liquidate an obligation. The caller of this function pays off part of the violator's debt.
    /// In return, the caller receives collateral that is worth more than the paid debt.
    public fun liquidate<P, Debt, Collateral>(
        obligation: &mut Obligation<P>,
        stats: Stats,
        reserve: &mut Reserve<P, Debt>,
        time: &Time,
        price_cache: &PriceCache,
        repay_amount: Balance<Debt>,
    ): Balance<CToken<P, Collateral>> {
        assert!(is_stats_valid(obligation, &mut stats, time::get_epoch_s(time)), EInvalidStats);
        assert!(is_liquidatable(&stats), EHealthy);
        
        let deposit: &mut Deposit<CToken<P, Collateral>> = object_bag::borrow_mut(
            &mut obligation.deposits, Name<CToken<P, Collateral>>{});
        
        let max_allowed_repay_value_usd = mul(stats.usd_borrow_value, from_percent(CLOSE_FACTOR_PCT));
        let repay_value_usd = oracle::market_value<Debt>(
            price_cache,
            balance::value(&repay_amount)
        );
        assert!(le(repay_value_usd, max_allowed_repay_value_usd), ERepayIsTooLarge);
        
        // (1 + LIQUIDATION_BONUS) * repay_value_usd is eligible to be taken
        let liquidatable_value_usd = mul(
            repay_value_usd,
            add(one(), from_percent(LIQUIDATOR_BONUS_PCT))
        );
        let liquidity_amount = oracle::usd_to_quantity<Collateral>(price_cache, liquidatable_value_usd);
        let collateral_amount = floor(div(liquidity_amount, reserve::ctoken_exchange_rate(reserve)));
        let collateral = balance::split(&mut deposit.balance, collateral_amount);
        
        // repay increments seqnum so we don't have to do it here
        repay(obligation, stats, reserve, time, repay_amount);

        collateral
    }
    
    public fun is_liquidatable(stats: &Stats): bool {
        ge(
            stats.usd_borrow_value, 
            mul(stats.usd_deposit_value, from_percent(LIQUIDATION_THRESHOLD_PCT))
        )
    }
    
    /* 
        All functions below here are related to updating the obligation's Stat object. The 
        Stat object is used to track obligation health (ie assets.usd_value - liabilities.usd_value) 
    */
    public fun create_stats<P>(obligation: &Obligation<P>, time: &Time): Stats {
        Stats {
            seqnum: obligation.seqnum,
            obligation_id: object::id(obligation),
            created: time::get_epoch_s(time),
            
            usd_borrow_value: decimal::zero(),
            usd_deposit_value: decimal::zero(),
            
            handled_positions: vec_set::empty(),
        }
    }
    
    public fun update_stats_borrow<P, T>(
        obligation: &mut Obligation<P>, 
        stats: &mut Stats,
        time: &Time,
        reserve: &mut Reserve<P, T>,
        price_cache: &PriceCache
    ) {
        assert!(object::id(obligation) == stats.obligation_id, EInvalidStats);

        if (!object_bag::contains(&obligation.borrows, Name<T> {})) {
            return
        };

        let borrow: &mut Borrow<T> = object_bag::borrow_mut(
            &mut obligation.borrows, 
            Name<T> {}
        );
        
        assert!(
            !vec_set::contains(&stats.handled_positions, &object::id(borrow)),
            EDepositAlreadyHandled
        );

        assert!(
            oracle::last_update_s<T>(price_cache) + PRICE_STALENESS_THRESHOLD_S >= time::get_epoch_s(time),
            EPriceTooStale
        ); 

        assert!(stats.seqnum == obligation.seqnum, ESeqnumIsStale);

        refresh_borrow(borrow, reserve, time, price_cache);

        stats.usd_borrow_value = add(
            stats.usd_borrow_value, 
            borrow.usd_value
        );
        
        vec_set::insert(
            &mut stats.handled_positions,
            object::id(borrow)
        );
    }
    
    public fun refresh_borrow<P, T>(
        borrow: &mut Borrow<T>,
        reserve: &mut Reserve<P, T>,
        time: &Time,
        price_cache: &PriceCache
    ) {
        reserve::compound_debt_and_interest(reserve, time::get_epoch_s(time));
        let new_cumulative_borrow_rate = reserve::cumulative_borrow_rate(reserve);

        // refresh interest
        borrow.borrowed_amount = mul(
            div(borrow.borrowed_amount, borrow.cumulative_borrow_rate_snapshot),
            new_cumulative_borrow_rate
        );
        borrow.cumulative_borrow_rate_snapshot = new_cumulative_borrow_rate;
        
        // refresh usd value
        borrow.usd_value  = oracle::market_value<T>(
            price_cache, 
            decimal::ceil(borrow.borrowed_amount)
        );
    }
    
    public fun update_stats_deposit<P, T>(
        obligation: &mut Obligation<P>, 
        stats: &mut Stats,
        time: &Time,
        reserve: &mut Reserve<P, T>,
        price_cache: &PriceCache
    ) {
        if (!object_bag::contains(&obligation.deposits, Name<CToken<P, T>> {})) {
            return
        };

        assert!(object::id(obligation) == stats.obligation_id, EInvalidStats);

        let deposit: &mut Deposit<CToken<P, T>> = object_bag::borrow_mut(
            &mut obligation.deposits, 
            Name<CToken<P, T>> {}
        );
        
        assert!(
            !vec_set::contains(&stats.handled_positions, &object::id(deposit)),
            EDepositAlreadyHandled
        );

        assert!(
            oracle::last_update_s<T>(price_cache) + PRICE_STALENESS_THRESHOLD_S >= time::get_epoch_s(time),
            EPriceTooStale
        ); 

        assert!(stats.seqnum == obligation.seqnum, ESeqnumIsStale);
        
        // update ctoken ratio
        reserve::compound_debt_and_interest(reserve, time::get_epoch_s(time));

        let ctoken_ratio = reserve::ctoken_exchange_rate<P, T>(reserve);
        let ctokens = decimal::from(balance::value(&deposit.balance));
        let liquidity = decimal::floor(mul(ctokens, ctoken_ratio));
        
        deposit.usd_value = oracle::market_value<T>(price_cache, liquidity);

        stats.usd_deposit_value = add(
            stats.usd_deposit_value,
            deposit.usd_value
        );

        vec_set::insert(
            &mut stats.handled_positions,
            object::id(deposit)
        );
    }
    
    public fun is_stats_valid<P>(obligation: &Obligation<P>, stats: &Stats, cur_time: u64): bool {
        object::id(obligation) == stats.obligation_id
        && obligation.seqnum == stats.seqnum 
        && (stats.created + PRICE_STALENESS_THRESHOLD_S >= cur_time)
        && (
            vec_set::size(&stats.handled_positions) == 
            (object_bag::length(&obligation.deposits) + object_bag::length(&obligation.borrows))
        )
    }
}