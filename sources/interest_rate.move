module suilend::interest_rate {
    use suilend::decimal::{Self, Decimal};

    struct InterestRate has store, copy, drop {
        slope: Decimal,
    }
    
    // errors
    const EInvalidBorrowUtilPercentage: u64 = 0;
    
    
    public fun create_interest_rate(slope: Decimal): InterestRate {
        InterestRate {
            slope
        }
    }

    public fun calculate_apr(interest_rate: InterestRate, borrow_util_pct: Decimal): Decimal {
       decimal::mul(interest_rate.slope, borrow_util_pct)
    }
    
}