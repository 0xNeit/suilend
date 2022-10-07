/// This module keeps track of token prices. I'm not sure what the oracle landscape will look like,
/// but until then, we'll have a client binary that updates the PriceCache object with valid prices.
module suilend::oracle {
    use suilend::decimal::{Self, Decimal, div, mul, pow};
    use sui::object::{Self, ID, UID};
    use suilend::time::{Self, Time};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct PriceCache has key {
        id: UID,
        owner: address,
        time_id: ID,
    }
    
    // USD price of 1 whole token.
    // eg say the price of SUI was $20.05. Then: 
    // PriceInfo.base = 2005
    // PriceInfo.exp = 2
    // => 2005 / 10^2 = 20.05
    struct PriceInfo<phantom T> has key, store {
        id: UID,
        price_cache_id: ID,

        base: u64,
        exp: u64,
        
        // eg SOL has 9 decimals
        decimals: u64,

        last_update_s: u64,
    }

    const EUnauthorized: u64 = 0;
    const EInvalidTime: u64 = 1;
    const EInvalidPriceInfo: u64 = 2;

    public entry fun new_price_cache(time: &Time, ctx: &mut TxContext) {
        let price_cache = PriceCache {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            time_id: object::id(time),
        };
        
        transfer::share_object(price_cache);
    }

    public entry fun add_price_info<T>(
        price_cache: &mut PriceCache,
        time: &Time, 
        base: u64, 
        exp: u64, 
        decimals: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == price_cache.owner, EUnauthorized);
        assert!(price_cache.time_id == object::id(time), EInvalidTime);

        let price_info = PriceInfo<T> {
            id: object::new(ctx),
            price_cache_id: object::id(price_cache),
            base,
            exp,
            decimals,
            last_update_s: time::get_epoch_s(time),
        };
        
        transfer::transfer_to_object(price_info, price_cache);
    }
    
    public entry fun update_price_info<T>(
        price_cache: &PriceCache,
        price_info: &mut PriceInfo<T>,
        time: &Time, 
        base: u64, 
        exp: u64, 
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == price_cache.owner, EUnauthorized);
        assert!(price_cache.time_id == object::id(time), EInvalidTime);
        assert!(price_info.price_cache_id == object::id(price_cache), EInvalidPriceInfo);

        price_info.base = base;
        price_info.exp = exp;
        price_info.last_update_s = time::get_epoch_s(time);
    }

    public fun last_update_s<T>(price_info: &PriceInfo<T>): u64 {
        price_info.last_update_s
    }
    
    public fun price_cache_id<T>(price_info: &PriceInfo<T>): ID {
        price_info.price_cache_id
    }

    public fun price<T>(price_info: &PriceInfo<T>): Decimal {
        decimal::div(
            decimal::from(price_info.base),
            decimal::pow(decimal::from(10), price_info.exp)
        )
    }
    
    /// find the market value of a specified quantity of tokens.
    public fun market_value<T>(price_info: &PriceInfo<T>, quantity: u64): Decimal {
        mul(
            price(price_info),
            div(
                decimal::from(quantity), 
                pow(decimal::from(10), price_info.decimals)
            )
        )
    }
}