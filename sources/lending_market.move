/// A lending market holds many reserves. Assume base currency is USD. 

module suilend::lending_market {
    use sui::object::{Self, ID, UID};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    struct LendingMarket<phantom P> has key {
        id: UID,
        owner: address,

        // TODO maybe use the bag collection here instead.
        reserves: VecSet<ID>
    }
    
    public entry fun create_lending_market<P: drop>(_witness: P, ctx: &mut TxContext) {
        let id = object::new(ctx);
        let lending_market = LendingMarket<P> {
            id,
            owner: tx_context::sender(ctx),
            reserves: vec_set::empty()
        };
        
        transfer::share_object(lending_market);
    }
    
}