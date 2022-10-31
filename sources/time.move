/// Sui has no granular timestamp yet which we really need for interest rate calculations.
///  so for now, update this Time object with the latest epoch time in seconds. 
/// This will be done with an off-chain binary.
module suilend::time {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::transfer;

    struct Time has key, store {
        id: UID,
        epoch_time_s: u64
    }
    
    struct TimeCap has key, store {
        id: UID,
        time_id: ID
    }
    
    const EUnauthorized: u64 = 0;
    
    public entry fun new(cur_epoch_time_s: u64, ctx: &mut TxContext) {
        let (time, time_cap) = create(cur_epoch_time_s, ctx); 

        transfer::share_object(time);
        transfer::transfer(time_cap, tx_context::sender(ctx));
    }

    public fun create(cur_epoch_time_s: u64, ctx: &mut TxContext): (Time, TimeCap) {
        let time = Time {
            id: object::new(ctx),
            epoch_time_s: cur_epoch_time_s
        };
        
        let time_cap = TimeCap {
            id: object::new(ctx),
            time_id: object::id(&time)
        };
        
        (time, time_cap)
    }
    
    public entry fun update_time(
        time_cap: &TimeCap,
        time: &mut Time, 
        cur_epoch_time_s: u64, 
        _ctx: &mut TxContext
    ) {
        assert!(time_cap.time_id == object::id(time), EUnauthorized);
        time.epoch_time_s = cur_epoch_time_s;
    }
    
    public fun get_epoch_s(time: &Time): u64 {
        time.epoch_time_s
    }
}