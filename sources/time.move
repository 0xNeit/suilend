/// Sui has no granular timestamp yet which we really need for interest rate calculations.
///  so for now, update this Time object with the latest epoch time in seconds. 
/// This will be done with an off-chain binary.
module suilend::time {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;

    struct Time has key, store {
        id: UID,
        owner: address,
        epoch_time_s: u64
    }
    
    const EUnauthorized: u64 = 0;
    
    public entry fun new(cur_epoch_time_s: u64, ctx: &mut TxContext) {
        let time = Time {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            epoch_time_s: cur_epoch_time_s
        };
        
        transfer::share_object(time);
    }

    public fun create(cur_epoch_time_s: u64, ctx: &mut TxContext): Time {
        Time {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            epoch_time_s: cur_epoch_time_s
        }
    }
    
    public entry fun update_time(
        time: &mut Time, 
        cur_epoch_time_s: u64, 
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == time.owner, EUnauthorized);
        time.epoch_time_s = cur_epoch_time_s;
    }
    
    public fun get_epoch_s(time: &Time): u64 {
        time.epoch_time_s
    }
}