// TODO mark all this stuff as friend so only the lending market can access.
module suilend::price {
    use sui::tx_context::{TxContext};
    use sui::object::{Self, UID};
    use suilend::decimal::{Decimal};

    // USD price of 1 whole token.
    // Whole token: 1 SOL (1e9 lamports)
    // Fractional token: 1 lamport
    struct PriceInfo<phantom T> has key, store {
        id: UID,
        price: Decimal,
        decimals: u64,
        last_update: u64,
    }

    public fun new<T>(cur_time: u64, value: Decimal, decimals: u64, ctx: &mut TxContext): PriceInfo<T> {
        PriceInfo<T> {
            id: object::new(ctx),
            price: value,
            decimals,
            last_update: cur_time,
        }
    }

    public fun last_update<T>(p: &PriceInfo<T>): u64 {
        p.last_update
    }

    public fun price<T>(p: &PriceInfo<T>): Decimal {
        p.price
    }
    
    public fun decimals<T>(p: &PriceInfo<T>): u64 {
        p.decimals
    }
    

}