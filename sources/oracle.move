/// This module keeps track of token prices. I'm not sure what the oracle landscape will look like,
/// but until then, we'll have a client binary that updates the PriceCache object with valid prices.
module suilend::oracle {
    use suilend::decimal::{Self, Decimal, div, mul, pow};
    use sui::object::{Self, ID, UID};
    use suilend::time::{Self, Time};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::object_bag::{ObjectBag, Self};

    struct PriceCache has key {
        id: UID,
        owner: address,
        time_id: ID,
        prices: ObjectBag
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
            prices: object_bag::new(ctx),
        };
        
        transfer::share_object(price_cache);
    }

    // used as key to object bag
    struct Name<phantom T> has copy, drop, store {}

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
        
        object_bag::add(&mut price_cache.prices, Name<T> {}, price_info);
    }
    
    public entry fun update_price<T>(
        price_cache: &mut PriceCache,
        time: &Time, 
        base: u64, 
        exp: u64, 
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == price_cache.owner, EUnauthorized);
        assert!(price_cache.time_id == object::id(time), EInvalidTime);
        
        let price_info: &mut PriceInfo<T> = object_bag::borrow_mut(&mut price_cache.prices, Name<T>{ });

        price_info.base = base;
        price_info.exp = exp;
        price_info.last_update_s = time::get_epoch_s(time);
    }

    public fun last_update_s<T>(price_cache: &PriceCache): u64 {
        object_bag::borrow<Name<T>, PriceInfo<T>>(&price_cache.prices, Name<T> {}).last_update_s
    }
    
    public fun price<T>(price_cache: &PriceCache): Decimal {
        let price_info = object_bag::borrow<Name<T>, PriceInfo<T>>(&price_cache.prices, Name<T> {});
        decimal::div(
            decimal::from(price_info.base),
            decimal::pow(decimal::from(10), price_info.exp)
        )
    }
    
    public fun decimals<T>(price_cache: &PriceCache): u64 {
        let price_info = object_bag::borrow<Name<T>, PriceInfo<T>>(&price_cache.prices, Name<T> {});
        price_info.decimals
    }
    
    /// find the market value of a specified quantity of tokens.
    public fun market_value<T>(price_cache: &PriceCache, quantity: u64): Decimal {
        let price_info = object_bag::borrow<Name<T>, PriceInfo<T>>(&price_cache.prices, Name<T> {});

        mul(
            price<T>(price_cache),
            div(
                decimal::from(quantity), 
                pow(decimal::from(10), price_info.decimals)
            )
        )
    }
    
    public fun usd_to_quantity<T>(price_cache: &PriceCache, usd: Decimal): Decimal {
        mul(
            div(usd, price<T>(price_cache)),
            pow(decimal::from(10), decimals<T>(price_cache))
        )
    }
}