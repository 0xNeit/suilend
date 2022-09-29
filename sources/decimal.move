/// Defines a fixed-point decimal type with up to 15 digits of decimal precision.
/// This type will overflow at about 10^20.
/// FIXME: I should use a u192. This is fine for a prototype
/// but will definitely have to be fixed before production.

module suilend::decimal {
    use suilend::big_number::{Self, BN};

    struct Decimal has copy, store, drop {
        value: BN
    }
    
    // 10^18
    const WAD: u64 = 1000000000000000000;
    
    public fun zero(): Decimal {
        from(0)
    }

    public fun one(): Decimal {
        from(1)
    }
    
    public fun from(v: u64): Decimal {
        Decimal {
            value: big_number::mul(big_number::from_u64(v), big_number::from_u64(WAD))
        }
    }
    
    public fun from_percent(pct: u64): Decimal {
        div(
            from(pct),
            from(100)
        )
    }

    public fun from_bps(pct: u64): Decimal {
        div(
            from(pct),
            from(10000)
        )
    }
    
    // FIXME: this is wrong. need a floor, ceil function instead of this.
    public fun to_u64(d: Decimal): u64 {
        let Decimal { value } = d;
        value = big_number::div(value, big_number::from_u64(WAD));

        big_number::to_u64(value)
    }
    
    public fun to_bps(d: Decimal): u64 {
        let Decimal { value } = d;
        value = big_number::div(value, big_number::from_u64(WAD / 10000));

        big_number::to_u64(value)
        
    }

    public fun add(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: big_number::add(a.value, b.value)
        }
    }

    public fun sub(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: big_number::sub(a.value, b.value)
        }
    }

    public fun mul(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: big_number::div(big_number::mul(a.value, b.value), big_number::from_u64(WAD))
        }
    }

    public fun div(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: big_number::div(big_number::mul(a.value, big_number::from_u64(WAD)), b.value)
        }
    }
    
    // FIXME: use more efficient power function
    public fun pow(base: Decimal, exp: u64): Decimal {
        let i = 0;
        let product = one();

        while (i < exp) {
            product = mul(product, base);
            i = i + 1;
        };
        
        product
    }
    
    public fun gt(a: Decimal, b: Decimal): bool {
        big_number::gt(a.value, b.value)
    }

    public fun ge(a: Decimal, b: Decimal): bool {
        big_number::ge(a.value, b.value)
    }

    public fun lt(a: Decimal, b: Decimal): bool {
        big_number::lt(a.value, b.value)
    }

    public fun le(a: Decimal, b: Decimal): bool {
        big_number::le(a.value, b.value)
    }
    
    // round to 6 decimal places
    // eg rounded(decimal::from_pct(5)) == 50
    public fun rounded(d: Decimal): u64 {
        let d = big_number::div(d.value, big_number::from_u64(1000000000000));
        big_number::to_u64(d)
    }
    
    // 10^16
    const CLOSENESS_THRESHOLD: u64 = 10000000000000000;

    // checks if the actual value is within 0.01 of expected
    // FIXME: jank. probably should support a mix of absolute and relative errors
    public fun is_close(actual: Decimal, expected: Decimal): bool {
        if (gt(expected, actual)) {
            big_number::le(
                big_number::sub(expected.value, expected.value), 
                big_number::from_u64(CLOSENESS_THRESHOLD)
            )
        }
        else {
            big_number::le(
                big_number::sub(actual.value, expected.value), 
                big_number::from_u64(CLOSENESS_THRESHOLD)
            )
        }
    }
}

#[test_only]
module suilend::decimal_tests {
    use suilend::decimal::{Self};
    
    #[test]
    fun test_golden() {
        let a = decimal::from(12);
        let b = decimal::from(3);
        
        {
            let sum_decimal = decimal::add(a, b);
            let sum = decimal::to_u64(sum_decimal);
            assert!(sum == 15, 0);
        };

        {
            let sub_decimal = decimal::sub(a, b);
            let sub = decimal::to_u64(sub_decimal);
            assert!(sub == 9, 0);
        };

        {
            let product_decimal = decimal::mul(a, b);
            let product = decimal::to_u64(product_decimal);
            assert!(product == 36, 0);
        };

        {
            let quotient_decimal = decimal::div(a, b);
            let quotient = decimal::to_u64(quotient_decimal);
            assert!(quotient == 4, 0);
        };
        
        {
            let res = decimal::pow(a, 3);
            assert!(decimal::to_u64(res) == 1728, decimal::to_u64(res));
        };

        {
            let res = decimal::pow(a, 0);
            assert!(decimal::to_u64(res) == 1, decimal::to_u64(res));
        };
        
        {
            let res = decimal::pow(decimal::from(10), 9);
            assert!(decimal::to_u64(res) == 1000000000, decimal::to_u64(res));
        };
        
        {
            assert!(decimal::rounded(decimal::from_percent(5)) == 50000, 0);
        }
    }
    
}