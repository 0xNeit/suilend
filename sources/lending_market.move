/// A lending market holds many reserves. Assume base currency is USD. 

// notes: as of now there's no granular time module in the move VM. so the lending market owner
// will have to update the time via a function call. if the owner doesn't do this, the contract
// can be exploited.

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
    /* use sui::types; */
    

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
    
    public entry fun create_lending_market<P: drop>(
        _witness: P, 
        time: &Time,
        price_cache: &PriceCache,
        ctx: &mut TxContext
    ) {
        /* assert!(types::is_one_time_witness(&witness), ENotAOneTimeWitness); */

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
    
    // add reserve
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
        
        transfer::transfer_to_object(obligation, lending_market);
    }
    
    public entry fun add_deposit_info_to_obligation<P, T>(
        _lending_market: &mut LendingMarket<P>,
        obligation: &mut Obligation<P>,
        ctx: &mut TxContext
    ) {
        obligation::add_deposit_info<P, T>(obligation, ctx);
    }

    public entry fun add_borrow_info_to_obligation<P, T>(
        _lending_market: &mut LendingMarket<P>,
        obligation: &mut Obligation<P>,
        ctx: &mut TxContext
    ) {
        obligation::add_borrow_info<P, T>(obligation, ctx);
    }
    
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
    
    public entry fun reset_stats<P>(
        _lending_market: &mut LendingMarket<P>,
        obligation: &mut Obligation<P>,
        time: &Time,
        _ctx: &mut TxContext
    ) {
        obligation::reset_stats(obligation, time);
    }
    
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