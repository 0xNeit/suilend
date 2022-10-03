/// An obligation tracks a user's deposits and borrows in a given lending market.
/// A user can own more than 1 obligation for a given lending market.
/// The structure of this module will change significantly once Sui supports
/// dynamic access of child objects.

module suilend::obligation {
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use suilend::decimal::{Decimal, Self, add, sub, mul, div, le, from_percent, from, to_u64_floor};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{Self, TxContext};
    use suilend::oracle::{Self, PriceInfo};
    use suilend::reserve::{Self, Reserve, CToken};
    use suilend::time::{Self, Time};

    use sui::transfer;

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
    
    const PRICE_STALENESS_THRESHOLD_S: u64 = 30;

    const MAX_LOAN_TO_VALUE_PCT: u64 = 80;
    const LIQUIDATION_THRESHOLD_PCT: u64 = 90;
    
    struct Obligation<phantom P> has key, store {
        id: UID,
        owner: address,
        deposits: VecSet<ID>,
        borrows: VecSet<ID>,
        
        // gets incremented on every deposit or borrow call.
        // used to verify validity of Stats object during borrows,
        // withdraws, and liquidations.
        seqnum: u64,
        
        stats: Stats,
    }
    
    // Child object owned by an Obligation
    struct DepositInfo<phantom T> has key {
        id: UID,
        obligation_id: ID,
        balance: Balance<T>,
        
        usd_value: Decimal,
    }
    
    // Child object owned by an Obligation
    struct BorrowInfo<phantom T> has key {
        id: UID,
        obligation_id: ID,
        borrowed_amount: Decimal, // needs to be a decimal bc we compound debt
        cumulative_borrow_rate_snapshot: Decimal,
        
        usd_value: Decimal,
    }
    
    struct Stats has store {
        seqnum: u64,
        last_refreshed: u64,
        
        usd_borrow_value: Decimal,
        usd_deposit_value: Decimal,
        
        handled_deposits: VecSet<ID>,
        handled_borrows: VecSet<ID>,
        
        unhandled_deposits: VecSet<ID>,
        unhandled_borrows: VecSet<ID>,
    }
    
    /* entry functions */
    public fun create_obligation<P>(owner: address, cur_time: u64, ctx: &mut TxContext): Obligation<P> {
        Obligation<P> {
            id: object::new(ctx),
            owner,
            deposits: vec_set::empty(),
            borrows: vec_set::empty(),
            seqnum: 0,
            stats: Stats {
                seqnum: 0,
                last_refreshed: cur_time,
                usd_borrow_value: decimal::zero(),
                usd_deposit_value: decimal::zero(),
                
                handled_deposits: vec_set::empty(),
                handled_borrows: vec_set::empty(),
                unhandled_deposits: vec_set::empty(),
                unhandled_borrows: vec_set::empty(),
            }
        }
    }
    
    // deposit ctokens into obligation. it's not difficult to extend this to deposit non-ctokens as well,
    // if users want that functionality. similar to "protected collateral" in euler finance.
    public fun deposit<P, T>(
        obligation: &mut Obligation<P>, 
        // this is here to make sure the user doesn't deposit any unsupported tokens
        _reserve: &Reserve<P, T>,
        liquidity: Balance<CToken<P, T>>, 
        deposit: &mut DepositInfo<CToken<P, T>>,
        ctx: &mut TxContext
    ) {
        assert!(obligation.owner == tx_context::sender(ctx), EUnauthorized);
        assert!(deposit.obligation_id == object::id(obligation), EInvalidDeposit);
        assert!(vec_set::contains(&obligation.deposits, &object::id(deposit)), EInvalidDeposit);
        
        balance::join(&mut deposit.balance, liquidity);
        obligation.seqnum = obligation.seqnum + 1;
    }
    
    public fun borrow<P, T>(
        obligation: &mut Obligation<P>, 
        borrow_info: &mut BorrowInfo<T>, 
        reserve: &mut Reserve<P, T>, 
        time: &Time, 
        price_info: &PriceInfo<T>, 
        borrow_amount: u64,
        ctx: &mut TxContext
    ): Balance<T> {
        assert!(obligation.owner == tx_context::sender(ctx), EUnauthorized);
        assert!(is_stats_valid(obligation, time::get_epoch_s(time)), EInvalidStats);
        
        let borrowed_liquidity = reserve::borrow_liquidity(reserve, time::get_epoch_s(time), borrow_amount);
        let new_cumulative_borrow_rate = reserve::cumulative_borrow_rate(reserve);

        // refresh interest
        borrow_info.borrowed_amount = mul(
            div(borrow_info.borrowed_amount, borrow_info.cumulative_borrow_rate_snapshot),
            new_cumulative_borrow_rate
        );
        borrow_info.cumulative_borrow_rate_snapshot = new_cumulative_borrow_rate;
        
        // check that we don't exceed our borrow limits
        let borrow_usd_value = oracle::market_value(price_info, borrow_amount);
        let new_borrow_usd_value = add(borrow_usd_value, obligation.stats.usd_borrow_value);
        assert!(
            le(
                new_borrow_usd_value, 
                mul(obligation.stats.usd_deposit_value, from_percent(MAX_LOAN_TO_VALUE_PCT))
            ),
            EBorrowIsTooLarge
        );
        
        // update state 
        borrow_info.borrowed_amount = add(borrow_info.borrowed_amount, decimal::from(borrow_amount));
        obligation.seqnum = obligation.seqnum + 1;
        borrowed_liquidity
    }

    public fun withdraw<P, T>(
        obligation: &mut Obligation<P>, 
        deposit_info: &mut DepositInfo<CToken<P, T>>, 
        reserve: &mut Reserve<P, T>,
        cur_time: u64, 
        price_info: &PriceInfo<T>, 
        withdraw_ctoken_amount: u64,
        ctx: &mut TxContext
    ): Balance<CToken<P, T>> {
        assert!(obligation.owner == tx_context::sender(ctx), EUnauthorized);
        assert!(is_stats_valid(obligation, cur_time), EInvalidStats);
        reserve::compound_debt_and_interest(reserve, cur_time);
        
        // FIXME: stats valid can be slightly stale which can cause issues. can be fixed
        // after "dynamic access to child objects lands"

        // check that we don't exceed our borrow limits
        let withdraw_liquidity_amount = to_u64_floor(mul(
            reserve::ctoken_exchange_rate(reserve),
            from(withdraw_ctoken_amount)
        ));

        let withdraw_usd_value = oracle::market_value(price_info, withdraw_liquidity_amount);
        let new_usd_deposit_value = sub(obligation.stats.usd_deposit_value, withdraw_usd_value);

        assert!(
            le(
                obligation.stats.usd_borrow_value,
                mul(new_usd_deposit_value, from_percent(MAX_LOAN_TO_VALUE_PCT))
            ),
            EWithdrawIsTooLarge
        );
        
        obligation.seqnum = obligation.seqnum + 1;

        balance::split(&mut deposit_info.balance, withdraw_ctoken_amount)
    }

    public fun repay<P, T>(
        obligation: &mut Obligation<P>, 
        borrow_info: &mut BorrowInfo<T>, 
        reserve: &mut Reserve<P, T>, 
        time: &Time,
        repay_balance: Balance<T>,
        _price_info: &PriceInfo<T>,
        ctx: &mut TxContext
    ) {
        assert!(obligation.owner == tx_context::sender(ctx), EUnauthorized);
        assert!(is_stats_valid(obligation, time::get_epoch_s(time)), EInvalidStats);

        // FIXME this is slightly incorrect bc the stats object can be a little bit stale
        // i should be refreshing all interest stuff here. which can be done soon.
        borrow_info.borrowed_amount = sub(
            borrow_info.borrowed_amount,
            decimal::from(balance::value(&repay_balance))
        );

        reserve::repay_liquidity(reserve, time::get_epoch_s(time), repay_balance);
        obligation.seqnum = obligation.seqnum + 1;
    }
    
    /* 
        All functions below here are related to updating obligation internal state. This will be heavily
        refactored once we can dynamically access child objects.
    */
    public fun add_deposit_info<P, T>(obligation: &mut Obligation<P>, ctx: &mut TxContext) {
        assert!(obligation.owner == tx_context::sender(ctx), EUnauthorized);

        let deposit = DepositInfo<T> {
            id: object::new(ctx),
            obligation_id: object::id(obligation),
            balance: balance::zero(),
            usd_value: decimal::zero(),
        };
        
        vec_set::insert(&mut obligation.deposits, object::id(&deposit));
        transfer::transfer_to_object(deposit, obligation);
    }

    public fun add_borrow_info<P, T>(obligation: &mut Obligation<P>, ctx: &mut TxContext) {
        assert!(obligation.owner == tx_context::sender(ctx), EUnauthorized);

        let borrow = BorrowInfo<T> {
            id: object::new(ctx),
            obligation_id: object::id(obligation),
            borrowed_amount: decimal::zero(),
            cumulative_borrow_rate_snapshot: decimal::one(),
            usd_value: decimal::zero(),
        };
        
        vec_set::insert(&mut obligation.borrows, object::id(&borrow));
        transfer::transfer_to_object(borrow, obligation);
    }

    public fun reset_stats<P>(obligation: &mut Obligation<P>, time: &Time) {
        assert!(obligation.seqnum != obligation.stats.seqnum, ESeqnumStillValid);
        
        obligation.stats.seqnum = obligation.seqnum;
        obligation.stats.last_refreshed = time::get_epoch_s(time);

        obligation.stats.usd_borrow_value = decimal::zero();
        obligation.stats.usd_deposit_value = decimal::zero();

        obligation.stats.handled_deposits = vec_set::empty();
        obligation.stats.handled_borrows = vec_set::empty();
        obligation.stats.unhandled_deposits = obligation.deposits;
        obligation.stats.unhandled_borrows = obligation.borrows;
    }
    
    public fun update_stats_borrow<P, T>(
        obligation: &mut Obligation<P>, 
        borrow_info: &mut BorrowInfo<T>, 
        time: &Time,
        reserve: &mut Reserve<P, T>,
        price_info: &PriceInfo<T>
    ) {
        assert!(
            vec_set::contains(&obligation.stats.unhandled_borrows, &object::id(borrow_info)),
            EBorrowAlreadyHandled
        );
        assert!(
            oracle::last_update_s(price_info) + PRICE_STALENESS_THRESHOLD_S >= time::get_epoch_s(time),
            EPriceTooStale
        ); 
        assert!(obligation.stats.seqnum == obligation.seqnum, ESeqnumIsStale);

        reserve::compound_debt_and_interest(reserve, time::get_epoch_s(time));
        let new_cumulative_borrow_rate = reserve::cumulative_borrow_rate(reserve);

        // refresh interest
        borrow_info.borrowed_amount = mul(
            div(borrow_info.borrowed_amount, borrow_info.cumulative_borrow_rate_snapshot),
            new_cumulative_borrow_rate
        );
        borrow_info.cumulative_borrow_rate_snapshot = new_cumulative_borrow_rate;
        
        // refresh usd value
        // TODO make sure to ceil here
        borrow_info.usd_value  = oracle::market_value(
            price_info, 
            decimal::to_u64(borrow_info.borrowed_amount)
        );
        obligation.stats.usd_borrow_value = add(
            obligation.stats.usd_borrow_value, 
            borrow_info.usd_value
        );
        
        // update vec sets
        vec_set::remove(
            &mut obligation.stats.unhandled_borrows,
            &object::id(borrow_info)
        );

        vec_set::insert(
            &mut obligation.stats.handled_borrows,
            object::id(borrow_info)
        );
    }
    
    public fun update_stats_deposit<P, T>(
        obligation: &mut Obligation<P>, 
        deposit_info: &mut DepositInfo<CToken<P, T>>, 
        time: &Time,
        reserve: &mut Reserve<P, T>,
        price_info: &PriceInfo<T>
    ) {
        assert!(
            vec_set::contains(&obligation.stats.unhandled_deposits, &object::id(deposit_info)),
            EDepositAlreadyHandled
        );
        assert!(
            oracle::last_update_s(price_info) + PRICE_STALENESS_THRESHOLD_S >= time::get_epoch_s(time),
            EPriceTooStale
        ); 
        assert!(obligation.stats.seqnum == obligation.seqnum, ESeqnumIsStale);
        
        reserve::compound_debt_and_interest(reserve, time::get_epoch_s(time));

        let ctoken_ratio = reserve::ctoken_exchange_rate<P, T>(reserve);
        let ctokens = decimal::from(balance::value(&deposit_info.balance));

        // FIXME: make sure this floors
        let liquidity = decimal::to_u64(mul(ctokens, ctoken_ratio));
        
        deposit_info.usd_value = oracle::market_value(price_info, liquidity);

        obligation.stats.usd_deposit_value = add(
            obligation.stats.usd_deposit_value,
            deposit_info.usd_value
        );

        vec_set::remove(
            &mut obligation.stats.unhandled_deposits,
            &object::id(deposit_info)
        );

        vec_set::insert(
            &mut obligation.stats.handled_deposits,
            object::id(deposit_info)
        );
        
    }
    
    public fun is_stats_valid<P>(obligation: &Obligation<P>, cur_time: u64): bool {
        obligation.stats.seqnum == obligation.seqnum 
        && (obligation.stats.last_refreshed + PRICE_STALENESS_THRESHOLD_S >= cur_time)
        && vec_set::is_empty(&obligation.stats.unhandled_borrows)
        && vec_set::is_empty(&obligation.stats.unhandled_deposits)
    }
}