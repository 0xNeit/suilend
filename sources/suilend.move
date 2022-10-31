/// holds OTW for the main pool and initializes the lending market
/// with a SUI reserve and some fake tokens
module suilend::suilend_main {
    use suilend::lending_market::{Self};
    use sui::tx_context::{TxContext};
    use suilend::time::{Self};
    use suilend::oracle::{Self};
    use sui::transfer::{Self};

    struct SUILEND_MAIN has drop {}
    
    fun init(witness: SUILEND_MAIN, ctx: &mut TxContext) {
        let time = time::create(0, ctx);
        let price_cache = oracle::create(&time, ctx);

        lending_market::create_lending_market<SUILEND_MAIN>(
            witness,
            &time,
            &price_cache,
            ctx
        );
        
        transfer::share_object(time);
        transfer::share_object(price_cache);
    }

}