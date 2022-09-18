/// This will be deprecated once Sui has more granular timestamps.

module suilend::time {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::transfer;

    struct TimeInfo has key, store {
        id: UID,
        owner: address,
        epoch_time_s: u64
    }
    
    struct Time has store, copy, drop {
        id: ID,
        owner: address,
        epoch_time_s: u64
    }
    
    const EUnauthorized: u64 = 0;
    
    public entry fun new(cur_epoch_time_s: u64, ctx: &mut TxContext) {
        let time_info = TimeInfo {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            epoch_time_s: cur_epoch_time_s
        };
        
        transfer::share_object(time_info);
    }
    
    public entry fun update_time(
        time_info: &mut TimeInfo, 
        cur_epoch_time_s: u64, 
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == time_info.owner, EUnauthorized);
        time_info.epoch_time_s = cur_epoch_time_s;
    }
    
    public fun get(time_info: &TimeInfo): Time {
        Time {
            id: object::id(time_info),
            owner: time_info.owner,
            epoch_time_s: time_info.epoch_time_s,
        }
    }
    
    public fun get_epoch_s(time: Time): u64 {
        time.epoch_time_s
    }
}