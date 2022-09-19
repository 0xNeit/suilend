/// A lending market holds many reserves. Assume base currency is USD. 

// notes: as of now there's no granular time module in the move VM. so the lending market owner
// will have to update the time via a function call. if the owner doesn't do this, the contract
// can be exploited.

module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use suilend::reserve::{Self, Reserve};
    use suilend::time::{Self, Time};
    use std::vector;
    

    // errors
    const EInvalidTime: u64 = 0;
    const EInvalidReserve: u64 = 1;
    const EUnauthorized: u64 = 2;

    // this is a shared object that contains references to ReserveInfos. This object 
    // also owns the ReserveInfos.
    struct LendingMarket<phantom P> has key {
        id: UID,
        reserve_info_ids: vector<ID>,
        time_id: ID
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
        ctx: &mut TxContext
    ) {
        // TODO add one-time witness check here

        let id = object::new(ctx);
        let lending_market = LendingMarket<P> {
            id,
            reserve_info_ids: vector::empty(),
            time_id: object::id(time),
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
    
    // deposit reserve liquidity
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
}