/// A LendingMarket owns many reserves and obligations.
module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use suilend::reserve::{Self, Reserve, CToken};
    use suilend::time::{Self, Time};
    use suilend::obligation::{Self, Obligation, Stats};
    use suilend::oracle::{PriceCache};
    use sui::types;
    use sui::object_bag::{Self, ObjectBag};
    use sui::bag::{Self, Bag};
    /* use suilend::decimal::{Self}; */
    
    // errors
    const EInvalidTime: u64 = 0;
    const EInvalidReserve: u64 = 1;
    const EUnauthorized: u64 = 2;
    const EInvalidPriceCache: u64 = 3;
    const ENotAOneTimeWitness: u64 = 4;

    struct LendingMarket<phantom P> has key {
        id: UID,

        time_id: ID,
        price_cache_id: ID,
        
        reserves: Bag,
        obligations: ObjectBag,
    }
    
    struct AdminCap<phantom P> has key {
        id: UID
    }
    
    struct ObligationCap<phantom P> has key {
        id: UID,
        obligation_id: ID
    }
    
    // used to store reserves in a bag
    struct Name<phantom T> has copy, drop, store {}
    
    public fun obligation_id<P>(o: &ObligationCap<P>): ID {
        o.obligation_id
    }
    
    #[test_only]
    public fun destroy_obligation_cap_for_testing<P>(o: ObligationCap<P>) {
        let ObligationCap { id, obligation_id: _obligation_id } = o;
        object::delete(id);
    }
    
    /// Create a new LendingMarket object.
    public entry fun create_lending_market<P: drop>(
        witness: P, 
        time: &Time,
        price_cache: &PriceCache,
        ctx: &mut TxContext
    ) {
        assert!(types::is_one_time_witness(&witness), ENotAOneTimeWitness);

        let id = object::new(ctx);
        let lending_market = LendingMarket<P> {
            id,
            time_id: object::id(time),
            price_cache_id: object::id(price_cache),
            reserves: bag::new(ctx),
            obligations: object_bag::new(ctx),
        };
        
        transfer::share_object(lending_market);
        transfer::transfer(AdminCap<P> { id: object::new(ctx) }, tx_context::sender(ctx));
    }
    
    /// Add a reserve to a LendingMarket.
    public entry fun add_reserve<P, T>(
        _: &AdminCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        time: &Time,
        _ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let reserve = reserve::create_reserve<P, T>(time::get_epoch_s(time));
        bag::add(&mut lending_market.reserves, Name<T> {}, reserve);
    }
    
    // Deposits Coin<T> into the lending market and returns Coin<CToken<T>>. 
    // The ctoken entitles the user to their original principal + any accumulated
    // interest.
    public entry fun deposit_reserve_liquidity<P, T>(
        lending_market: &mut LendingMarket<P>, 
        deposit: Coin<T>,
        time: &Time,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let balance = coin::into_balance(deposit);
        let reserve: &mut Reserve<P, T> = bag::borrow_mut(&mut lending_market.reserves, Name<T> {});

        let ctoken_balance = reserve::deposit_liquidity_and_mint_ctokens(
            reserve,
            time::get_epoch_s(time),
            balance
        );

        let ctokens = coin::from_balance(ctoken_balance, ctx);

        transfer::transfer(ctokens, tx_context::sender(ctx));
    }
    
    /// Create an obligation.
    public entry fun create_obligation<P>(
        lending_market: &mut LendingMarket<P>,
        time: &Time,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        
        let obligation = obligation::create_obligation<P>(
            tx_context::sender(ctx),
            /* time::get_epoch_s(time), */
            ctx
        );
        
        transfer::transfer(
            ObligationCap<P> { 
                id: object::new(ctx), 
                obligation_id: object::id(&obligation) 
            }, 
            tx_context::sender(ctx)
        );
        
        object_bag::add(
            &mut lending_market.obligations, 
            object::id(&obligation),
            obligation
        );
    }
    
    public fun get_obligation<P>(
       lending_market: &LendingMarket<P>, 
       obligation_cap: &ObligationCap<P>,
    ): &Obligation<P> {
        object_bag::borrow(&lending_market.obligations, obligation_cap.obligation_id)
    }
    
    /// Deposit CTokens into an obligation
    public entry fun deposit_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_cap: &ObligationCap<P>,
        time: &Time,
        deposit: Coin<CToken<P, T>>,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        
        // make sure coin type is supported
        let _reserve: &Reserve<P, T> = bag::borrow(&lending_market.reserves, Name<T> {});

        let obligation = object_bag::borrow_mut(
            &mut lending_market.obligations,
            obligation_cap.obligation_id
        );

        obligation::deposit(
            obligation,
            coin::into_balance(deposit),
            ctx
        );
    }

    /// Borrow coins from a reserve.
    public fun borrow<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_cap: &ObligationCap<P>,
        stats: Stats,
        time: &Time,
        price_cache: &PriceCache,
        borrow_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(object::id(price_cache) == lending_market.price_cache_id, EInvalidPriceCache);

        let reserve: &mut Reserve<P, T> = bag::borrow_mut(&mut lending_market.reserves, Name<T> {});
        let obligation: &mut Obligation<P> = object_bag::borrow_mut(
            &mut lending_market.obligations,
            obligation_cap.obligation_id
        );

        let borrowed_balance = obligation::borrow(
            obligation,
            stats,
            reserve,
            time,
            price_cache,
            borrow_amount,
            ctx
        );
        
        transfer::transfer(
            coin::from_balance(borrowed_balance, ctx),
            tx_context::sender(ctx)
        );
    }

    /// Withdraw funds from an obligation
    public fun withdraw<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_cap: &ObligationCap<P>,
        stats: Stats,
        time: &Time,
        price_cache: &PriceCache,
        withdraw_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(object::id(price_cache) == lending_market.price_cache_id, EInvalidPriceCache);

        let reserve: &Reserve<P, T> = bag::borrow(&mut lending_market.reserves, Name<T> {});
        let obligation: &mut Obligation<P> = object_bag::borrow_mut(
            &mut lending_market.obligations,
            obligation_cap.obligation_id
        );

        let withdraw_balance = obligation::withdraw(
            obligation,
            stats,
            reserve,
            time,
            price_cache,
            withdraw_amount,
        );
        
        transfer::transfer(
            coin::from_balance(withdraw_balance, ctx),
            tx_context::sender(ctx)
        );
    }

    /// Repay obligation debt.
    public fun repay<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_cap: &ObligationCap<P>,
        stats: Stats,
        time: &Time,
        repay_amount: Coin<T>,
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let reserve: &mut Reserve<P, T> = bag::borrow_mut(&mut lending_market.reserves, Name<T> {});
        let obligation: &mut Obligation<P> = object_bag::borrow_mut(
            &mut lending_market.obligations,
            obligation_cap.obligation_id
        );

        obligation::repay(
            obligation,
            stats,
            reserve,
            time,
            coin::into_balance(repay_amount)
        );
    }
    
    /// Liquidate an unhealthy obligation
    public fun liquidate<P, Debt, Collateral>(
        lending_market: &mut LendingMarket<P>,
        obligation_id: ID,
        stats: Stats,
        repay_amount: Coin<Debt>,
        time: &Time,
        price_cache: &PriceCache,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let obligation: &mut Obligation<P> = object_bag::borrow_mut(
            &mut lending_market.obligations,
            obligation_id
        );
        let reserve: &mut Reserve<P, Debt> = bag::borrow_mut(&mut lending_market.reserves, Name<Debt> {});

        let ctokens = obligation::liquidate<P, Debt, Collateral>(
            obligation,
            stats,
            reserve,
            time,
            price_cache,
            coin::into_balance(repay_amount)
        );
        
        transfer::transfer(
            coin::from_balance(ctokens, ctx),
            tx_context::sender(ctx)
        );
    }
    
    public fun create_stats<P>(
        lending_market: &LendingMarket<P>,
        obligation_cap: &ObligationCap<P>,
        time: &Time
    ): Stats {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let obligation: &Obligation<P> = object_bag::borrow(
            &lending_market.obligations,
            obligation_cap.obligation_id
        );

        obligation::create_stats(obligation, time)
    }
    
    public fun update_stats<P, T>(
        lending_market: &mut LendingMarket<P>,
        obligation_cap: &ObligationCap<P>,
        stats: &mut Stats,
        time: &Time,
        price_cache: &PriceCache,
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let reserve: &mut Reserve<P, T> = bag::borrow_mut(&mut lending_market.reserves, Name<T> {});
        let obligation: &mut Obligation<P> = object_bag::borrow_mut(
            &mut lending_market.obligations,
            obligation_cap.obligation_id
        );
        
        obligation::update_stats_deposit(
            obligation,
            stats,
            time, 
            reserve,
            price_cache
        );

        obligation::update_stats_borrow(
            obligation,
            stats,
            time, 
            reserve,
            price_cache
        );
    }
}