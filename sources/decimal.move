/// Defines a fixed-point decimal type with up to 18 digits of decimal precision.
/// This type will overflow at about 10^20.
/// FIXME: I should use a u192 or only keep 15 digits of precision. This is fine for a prototype
/// but will definitely have to be fixed before production.

module suilend::decimal {
    struct Decimal has copy, store, drop {
        value: u128
    }
    
    // 10^18
    const WAD: u128 = 1000000000000000000;
    
    public fun zero(): Decimal {
        from(0)
    }

    public fun one(): Decimal {
        from(1)
    }

    public fun from(v: u64): Decimal {
        Decimal {
            value: (v as u128) * WAD
        }
    }
    
    // FIXME: this is wrong. need a floor, ceil function instead of this.
    public fun to_u64(d: Decimal): u64 {
        let Decimal { value } = d;
        value = value / WAD;

        (value as u64)
    }

    public fun add(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value + b.value
        }
    }

    public fun sub(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value - b.value
        }
    }

    public fun mul(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value * b.value / WAD
        }
    }

    public fun div(a: Decimal, b: Decimal): Decimal {
        Decimal {
            value: a.value * WAD / b.value
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
    }
    
}