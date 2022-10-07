/// A LendingMarket owns many reserves and obligations.
module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use suilend::reserve::{Self, Reserve, CToken};
    use suilend::time::{Self, Time};
    use std::vector;
    use suilend::obligation::{Self, Obligation, BorrowInfo, DepositInfo};
    use suilend::oracle::{Self, PriceCache, PriceInfo};
    use sui::types;
    
    // errors
    const EInvalidTime: u64 = 0;
    const EInvalidReserve: u64 = 1;
    const EUnauthorized: u64 = 2;
    const EInvalidPrice: u64 = 3;
    const ENotAOneTimeWitness: u64 = 4;

    // this is a shared object that contains references to ReserveInfos. This object 
    // also owns the ReserveInfos.
    struct LendingMarket<phantom P> has key {
        id: UID,
        reserve_info_ids: vector<ID>,
        time_id: ID,
        price_cache_id: ID,
    }
    
    struct AdminCap<phantom P> has key {
        id: UID
    }
    
    struct ReserveInfo<phantom P, phantom T> has key {
        id: UID,
        lending_market: ID,
        reserve: Reserve<P, T>
    } 
    
    struct ObligationCap<phantom P> has key {
        id: UID,
        obligation_id: ID
    }
    
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
            reserve_info_ids: vector::empty(),
            time_id: object::id(time),
            price_cache_id: object::id(price_cache)
        };
        
        transfer::share_object(lending_market);
        transfer::transfer(AdminCap<P> { id: object::new(ctx) }, tx_context::sender(ctx));
    }
    
    /// Add a reserve to a LendingMarket.
    /// TODO once we can dynamically check child objects, make sure there aren't any
    /// duplicate reserves
    public entry fun add_reserve<P, T>(
        _: &AdminCap<P>, 
        lending_market: &mut LendingMarket<P>, 
        time: &Time,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let reserve = reserve::create_reserve<P, T>(time::get_epoch_s(time));
        let id = object::new(ctx);

        let reserve_info = ReserveInfo<P, T> {
            id,
            lending_market: object::id(lending_market),
            reserve
        };
        
        vector::push_back(
            &mut lending_market.reserve_info_ids, 
            object::id<ReserveInfo<P, T>>(&reserve_info));

        transfer::transfer_to_object(reserve_info, lending_market);
    }
    
    // Deposits Coin<T> into the lending market and returns Coin<CToken<T>>. 
    // The ctoken entitles the user to their original principal + any accumulated
    // interest.
    public entry fun deposit_reserve_liquidity<P, T>(
        lending_market: &mut LendingMarket<P>, 
        reserve_info: &mut ReserveInfo<P, T>, 
        deposit: Coin<T>,
        time: &Time,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);

        let balance = coin::into_balance(deposit);
        let ctoken_balance = reserve::deposit_liquidity_and_mint_ctokens(
            &mut reserve_info.reserve, 
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
            time::get_epoch_s(time),
            ctx
        );
        
        transfer::transfer(
            ObligationCap<P> { 
                id: object::new(ctx), 
                obligation_id: object::id(&obligation) 
            }, 
            tx_context::sender(ctx)
        );
        transfer::transfer_to_object(obligation, lending_market);
    }
    
    /// This function will be removed once dynamic child access is available
    public entry fun add_deposit_info_to_obligation<P, T>(
        _lending_market: &mut LendingMarket<P>,
        obligation: &mut Obligation<P>,
        ctx: &mut TxContext
    ) {
        obligation::add_deposit_info<P, T>(obligation, ctx);
    }

    /// This function will be removed once dynamic child access is available
    public entry fun add_borrow_info_to_obligation<P, T>(
        _lending_market: &mut LendingMarket<P>,
        obligation: &mut Obligation<P>,
        ctx: &mut TxContext
    ) {
        obligation::add_borrow_info<P, T>(obligation, ctx);
    }
    
    /// Deposit CTokens into an obligation
    public entry fun deposit_ctokens<P, T>(
        lending_market: &mut LendingMarket<P>,
        reserve_info: &ReserveInfo<P, T>,
        obligation: &mut Obligation<P>,
        deposit_info: &mut DepositInfo<CToken<P, T>>,
        time: &Time,
        deposit: Coin<CToken<P, T>>,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        obligation::deposit(
            obligation,
            &reserve_info.reserve,
            coin::into_balance(deposit),
            deposit_info,
            ctx
        );
    }

    /// Borrow coins from a reserve.
    public entry fun borrow<P, T>(
        lending_market: &mut LendingMarket<P>,
        reserve_info: &mut ReserveInfo<P, T>,
        obligation: &mut Obligation<P>,
        borrow_info: &mut BorrowInfo<T>,
        time: &Time,
        price_info: &PriceInfo<T>,
        borrow_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(oracle::price_cache_id(price_info) == lending_market.price_cache_id, EInvalidPrice);

        let borrowed_balance = obligation::borrow(
            obligation,
            borrow_info,
            &mut reserve_info.reserve,
            time,
            price_info,
            borrow_amount,
            ctx
        );
        
        transfer::transfer(
            coin::from_balance(borrowed_balance, ctx),
            tx_context::sender(ctx)
        );
    }

    /// Withdraw funds from an obligation
    public entry fun withdraw<P, T>(
        lending_market: &mut LendingMarket<P>,
        reserve_info: &mut ReserveInfo<P, T>,
        obligation: &mut Obligation<P>,
        deposit_info: &mut DepositInfo<CToken<P, T>>,
        time: &Time,
        price_info: &PriceInfo<T>,
        borrow_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(oracle::price_cache_id(price_info) == lending_market.price_cache_id, EInvalidPrice);

        let withdraw_balance = obligation::withdraw(
            obligation,
            deposit_info,
            &mut reserve_info.reserve,
            time::get_epoch_s(time),
            price_info,
            borrow_amount,
            ctx
        );
        
        transfer::transfer(
            coin::from_balance(withdraw_balance, ctx),
            tx_context::sender(ctx)
        );
    }

    /// Repay obligation debt.
    public entry fun repay<P, T>(
        lending_market: &mut LendingMarket<P>,
        reserve_info: &mut ReserveInfo<P, T>,
        obligation: &mut Obligation<P>,
        borrow_info: &mut BorrowInfo<T>,
        time: &Time,
        price_info: &PriceInfo<T>,
        repay_amount: Coin<T>,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(oracle::price_cache_id(price_info) == lending_market.price_cache_id, EInvalidPrice);

        obligation::repay(
            obligation,
            borrow_info,
            &mut reserve_info.reserve,
            time,
            coin::into_balance(repay_amount),
            price_info,
            ctx
        );
    }
    
    /// Liquidate an unhealthy obligation
    public entry fun liquidate<P, T1, T2>(
        lending_market: &mut LendingMarket<P>,
        violator: &mut Obligation<P>,
        violator_loan: &mut BorrowInfo<T1>,
        violator_collateral: &mut DepositInfo<CToken<P, T2>>,
        liquidator: &mut Obligation<P>,
        liquidator_loan: &mut BorrowInfo<T1>,
        liquidator_collateral: &mut DepositInfo<CToken<P, T2>>,
        time: &Time,
        ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        
        obligation::liquidate(
            violator,
            violator_loan,
            violator_collateral,
            liquidator,
            liquidator_loan,
            liquidator_collateral,
            time,
            ctx
        );

    }
    
    /// This will be removed once dynamic child access is enabled.
    public entry fun reset_stats<P>(
        _lending_market: &mut LendingMarket<P>,
        obligation: &mut Obligation<P>,
        time: &Time,
        _ctx: &mut TxContext
    ) {
        obligation::reset_stats(obligation, time);
    }
    
    /// This will be removed once dynamic child access is enabled.
    public entry fun update_stats_deposit<P, T>(
        lending_market: &mut LendingMarket<P>,
        reserve_info: &mut ReserveInfo<P, T>,
        obligation: &mut Obligation<P>,
        deposit_info: &mut DepositInfo<CToken<P, T>>,
        time: &Time,
        price_info: &PriceInfo<T>,
        _ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(oracle::price_cache_id(price_info) == lending_market.price_cache_id, EInvalidPrice);
        
        obligation::update_stats_deposit(
            obligation,
            deposit_info,
            time, 
            &mut reserve_info.reserve,
            price_info
        );
    }

    /// This will be removed once dynamic child access is enabled.
    public entry fun update_stats_borrow<P, T>(
        lending_market: &mut LendingMarket<P>,
        reserve_info: &mut ReserveInfo<P, T>,
        obligation: &mut Obligation<P>,
        borrow_info: &mut BorrowInfo<T>,
        time: &Time,
        price_info: &PriceInfo<T>,
        _ctx: &mut TxContext
    ) {
        assert!(object::id(time) == lending_market.time_id, EInvalidTime);
        assert!(oracle::price_cache_id(price_info) == lending_market.price_cache_id, EInvalidPrice);
        
        obligation::update_stats_borrow(
            obligation,
            borrow_info,
            time, 
            &mut reserve_info.reserve,
            price_info
        );
    }
    
}