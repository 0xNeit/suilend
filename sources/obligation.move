/// An obligation tracks a user's deposits and borrows in a given lending market.
/// A user can own more than 1 obligation for a given lending market.
/// The structure of this module will change significantly once Sui supports
/// dynamic access of child objects.

module suilend::obligation {
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use suilend::decimal::{Decimal, Self, add, mul, div, pow, le};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{TxContext};
    use suilend::price::{Self, PriceInfo};
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
    
    const PRICE_STALENESS_THRESHOLD_S: u64 = 30;
    
    struct Obligation<phantom P> has key {
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
    
    public fun add_deposit_info<P, T>(obligation: &mut Obligation<P>, ctx: &mut TxContext) {
        let deposit = DepositInfo<T> {
            id: object::new(ctx),
            obligation_id: object::id(obligation),
            balance: balance::zero(),
            usd_value: decimal::zero(),
        };
        
        transfer::transfer_to_object(deposit, obligation);
    }
    
    public fun deposit<P, T>(obligation: &mut Obligation<P>, liquidity: Balance<T>, deposit: &mut DepositInfo<T>) {
        assert!(deposit.obligation_id == object::id(obligation), EInvalidDeposit);
        assert!(vec_set::contains(&obligation.deposits, &object::id(deposit)), EInvalidDeposit);
        
        balance::join(&mut deposit.balance, liquidity);
        obligation.seqnum = obligation.seqnum + 1;
    }
    
    public fun add_borrow_info<P, T>(obligation: &mut Obligation<P>, ctx: &mut TxContext) {
        let borrow = BorrowInfo<T> {
            id: object::new(ctx),
            obligation_id: object::id(obligation),
            borrowed_amount: decimal::zero(),
            cumulative_borrow_rate_snapshot: decimal::zero(),
            usd_value: decimal::zero(),
        };
        
        transfer::transfer_to_object(borrow, obligation);
    }
    
    public fun borrow<P, T>(
        obligation: &mut Obligation<P>, 
        borrow_info: &mut BorrowInfo<T>, 
        reserve: &mut Reserve<P, T>, 
        cur_time: u64, 
        price_info: &PriceInfo<T>, 
        borrow_amount: u64
    ): Balance<T> {
        assert!(is_stats_valid(obligation, cur_time), EInvalidStats);
        // TODO check that reserve is refreshed. or refresh it ourself. idk.
        
        // check that we don't exceed our borrow limits
        let borrow_usd_value = div(
            mul(decimal::from(borrow_amount), price::price(price_info)),
            pow(decimal::from(10), price::decimals(price_info))
        );
        
        let new_borrow_usd_value = add(borrow_usd_value, obligation.stats.usd_borrow_value);
        assert!(le(new_borrow_usd_value, obligation.stats.usd_deposit_value), EBorrowIsTooLarge);
        
        // update state 
        borrow_info.borrowed_amount = add(borrow_info.borrowed_amount, decimal::from(borrow_amount));
        borrow_info.cumulative_borrow_rate_snapshot = reserve::cumulative_borrow_rate(reserve);
        obligation.seqnum = obligation.seqnum + 1;

        reserve::borrow_liquidity(reserve, cur_time, borrow_amount)
    }
    
    public fun reset_stats<P>(obligation: &mut Obligation<P>) {
        assert!(obligation.seqnum != obligation.stats.seqnum, ESeqnumStillValid);
        
        obligation.stats.seqnum = obligation.seqnum;
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
        reserve: &Reserve<P, T>,
        price_info: &PriceInfo<T>
    ) {
        assert!(
            vec_set::contains(&obligation.stats.unhandled_borrows, &object::id(borrow_info)),
            EBorrowAlreadyHandled
        );
        assert!(
            price::last_update(price_info) >= time::get_epoch_s(time) - PRICE_STALENESS_THRESHOLD_S, 
            EPriceTooStale
        ); 
        assert!(obligation.stats.seqnum == obligation.seqnum, ESeqnumIsStale);
        // TODO refresh reserve
        
        let new_cumulative_borrow_rate = reserve::cumulative_borrow_rate(reserve);

        // refresh interest
        borrow_info.borrowed_amount = mul(
            div(borrow_info.borrowed_amount, borrow_info.cumulative_borrow_rate_snapshot),
            new_cumulative_borrow_rate
        );
        borrow_info.cumulative_borrow_rate_snapshot = new_cumulative_borrow_rate;
        
        // refresh usd value
        borrow_info.usd_value = div(
            mul(borrow_info.borrowed_amount, price::price(price_info)),
            pow(decimal::from(10), price::decimals(price_info))
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
        reserve: &Reserve<P, T>,
        price_info: &PriceInfo<T>
    ) {
        assert!(
            vec_set::contains(&obligation.stats.unhandled_deposits, &object::id(deposit_info)),
            EDepositAlreadyHandled
        );
        assert!(
            price::last_update(price_info) >= time::get_epoch_s(time) - PRICE_STALENESS_THRESHOLD_S, 
            EPriceTooStale
        ); 
        assert!(obligation.stats.seqnum == obligation.seqnum, ESeqnumIsStale);
        // TODO refresh reserve
        
        let ctoken_ratio = reserve::ctoken_exchange_rate<P, T>(reserve);
        let ctokens = decimal::from(balance::value(&deposit_info.balance));
        let liquidity = mul(ctokens, ctoken_ratio);
        
        deposit_info.usd_value = div(
            mul(liquidity, price::price(price_info)),
            pow(decimal::from(10), price::decimals(price_info))
        );
        
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
        && (obligation.stats.last_refreshed >= cur_time - PRICE_STALENESS_THRESHOLD_S)
        && vec_set::is_empty(&obligation.stats.unhandled_borrows)
        && vec_set::is_empty(&obligation.stats.unhandled_deposits)
    }
}