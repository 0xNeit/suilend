// Strongly typed oracle module. 
// TODO maybe the authorities should be a dynamic check

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
        
        transfer::share_object(price_info);
    }

    public fun last_update_s<T>(price_info: &PriceInfo<T>): u64 {
        price_info.last_update_s
    }

    public fun price<T>(price_info: &PriceInfo<T>): Decimal {
        decimal::div(
            decimal::from(price_info.base),
            decimal::pow(decimal::from(10), price_info.exp)
        )
    }
    
    /// find the market value of a specified quantity of tokens.
    public fun market_value<T>(price_info: &PriceInfo<T>, quantity: u64): Decimal {
        div(
            mul(decimal::from(quantity), price(price_info)),
            pow(decimal::from(10), price_info.decimals)
        )
    }
}