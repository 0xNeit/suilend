//// arbitrary precision little endian integer composed of u64s.

module suilend::big_number {
    use std::vector::{empty, push_back, borrow, length, pop_back, borrow_mut};

    struct BN has copy, drop {
        vals: vector<u64>
    }
    
    // errors
    const EOverflow: u64 = 0;
    const EUnderflow: u64 = 1;
    
    // constants
    const MAX_U64: u64 = 18446744073709551615;
    
    public fun zero(): BN {
        BN {
            vals: empty()
        }
    }
    
    fun reduce(a: BN): BN {
        while (length(&a.vals) > 0 && *borrow(&a.vals, length(&a.vals) - 1) == 0) {
            pop_back(&mut a.vals);
        };
        
        a
    }
    
    public fun from_u64(v: u64): BN {
        let vals = empty<u64>();
        push_back(&mut vals, v);
        
        reduce(BN {
            vals
        })
    }
    
    fun max(a: u64, b: u64): u64 {
        if (a > b) { a } else { b }
    }
    
    public fun add(a: BN, b: BN): BN {
        let sum = empty<u64>();
        let len = max(length(&a.vals), length(&b.vals));
        
        let i = 0;
        let carry: u64 = 0;

        while (i < len) {
            let a_i = if (i < length(&a.vals)) { *borrow(&a.vals, i) } else { 0 };
            let b_i = if (i < length(&b.vals)) { *borrow(&b.vals, i) } else { 0 };
            let sum_i = (a_i as u128) + (b_i as u128) + (carry as u128);

            carry = ((sum_i >> 64) as u64);
            sum_i = (sum_i & 0xffffffffffffffff);

            push_back(
                &mut sum,
                (sum_i as u64)
            );

            i = i + 1;
        };
        
        if (carry > 0) {
            push_back(&mut sum, carry);
        };
        
        BN {
            vals: sum
        }
    }

    /// subtract a by b.
    public fun sub(a: BN, b: BN): BN {
        let diff = empty<u64>();

        // there are never any leading zeros in BNs
        assert!(length(&a.vals) >= length(&b.vals), EUnderflow);
        
        let i = 0;
        let borrow = 0; // going to be either 0 or 1

        while (i < length(&a.vals)) {
            let a_i = *borrow(&a.vals, i);
            let b_i = if (i < length(&b.vals)) { *borrow(&b.vals, i) } else { 0 };
            
            if (a_i < b_i + borrow) {
                push_back(&mut diff, MAX_U64 - b_i - borrow + a_i + 1);
                borrow = 1;
            }
            else {
                push_back(&mut diff, a_i - b_i - borrow);
                borrow = 0;
            };
            
            i = i + 1;
        };
        
        assert!(borrow == 0, EUnderflow);
        
        reduce(BN {
            vals: diff
        })
    }
    
    public fun mul(a: BN, b: BN): BN {
        if (a == zero() || b == zero()) {
            return zero()
        };

        let product = empty();
        {
            let i = 0;
            while (i < length(&a.vals) + length(&b.vals)) {
                push_back(&mut product, 0);
                i = i + 1;
            };
        };
        
        let i = 0;
        while (i < length(&b.vals)) {
            let j = 0;
            let carry = 0;
            while (j < length(&a.vals)) {
                // multiply the i'th digit of b with the j'th digit of a, 
                // and store it in product[i + j]
                let b_i = *borrow(&b.vals, i);
                let a_j = *borrow(&a.vals, j);
                let product_ij = *borrow(&product, i + j);

                let sum = (b_i as u128) * (a_j as u128) + (product_ij as u128) + (carry as u128);
                *borrow_mut(&mut product, i + j) = ((sum & 0xffffffffffffffff) as u64);

                carry = ((sum >> 64) as u64);
                
               j = j + 1; 
            };
            
            if (carry > 0) {
                *borrow_mut(&mut product, i + j) = carry;
            };

            i = i + 1; 
        };
        
        reduce(
            BN {
                vals: product
            }
        )
    }
    
    fun gt_helper(a: BN, b: BN, equal: bool): bool {
        let a_len = length(&a.vals);
        let b_len = length(&b.vals);
        
        if (a_len > b_len) {
            return true
        };
        
        if (b_len > a_len) {
            return false
        };

        let i = a_len - 1;
        loop {
            let a_i = *borrow(&a.vals, i);
            let b_i = *borrow(&b.vals, i);

            if ((!equal && a_i > b_i) || (equal && a_i >= b_i)) {
                return true
            };

            if (a_i < b_i) {
                return false
            };
            
            if (i == 0) {
                return false
            };

            i = i - 1;
        }
    }
    
    public fun gt(a: BN, b: BN): bool {
        gt_helper(a, b, false)
    }
    
    public fun ge(a: BN, b: BN): bool {
        gt_helper(a, b, true)
    }
    
    public fun lt(a: BN, b: BN): bool {
        gt(b, a)
    }
    
    public fun le(a: BN, b: BN): bool {
        ge(b, a)
    }
    
    #[test_only]
    fun from_le_2(a: u64, b: u64): BN {
        let vals = empty();
        push_back(&mut vals, a);
        push_back(&mut vals, b);
        
        reduce(BN {
            vals
        })
    }

    #[test_only]
    fun from_le_3(a: u64, b: u64, c: u64): BN {
        let vals = empty();
        push_back(&mut vals, a);
        push_back(&mut vals, b);
        push_back(&mut vals, c);
        
        reduce(BN {
            vals
        })
    }

    #[test_only]
    fun from_le_4(a: u64, b: u64, c: u64, d: u64): BN {
        let vals = empty();
        push_back(&mut vals, a);
        push_back(&mut vals, b);
        push_back(&mut vals, c);
        push_back(&mut vals, d);
        
        reduce(BN {
            vals
        })
    }
    
    #[test]
    fun test_from_u64() {
        use std::vector; 

        let a = from_u64(1);
        assert!(*vector::borrow(&a.vals, 0) == 1, 0);
    }
    
    #[test]
    fun test_gt() {
        assert!(gt(from_le_3(0, 0, 1), from_le_3(0, 1, 0)), 0);
        assert!(gt(from_le_3(0, 0, 2), from_le_3(0, 1, 1)), 0);
        assert!(gt(from_le_3(0, 2, 1), from_le_3(0, 1, 1)), 0);
        assert!(!gt(from_le_3(0, 0, 1), from_le_3(0, 0, 2)), 0);
        assert!(!gt(from_le_3(1, 1, 1), from_le_3(1, 1, 1)), 0);
        assert!(!gt(from_le_3(1, 1, 0), from_le_3(1, 1, 1)), 0);
    }
    
    #[test]
    fun test_sum() {
        use std::debug;

        let a = from_le_3(MAX_U64, 0, 1);
        let b = from_le_3(1, MAX_U64, MAX_U64);

        let sum = add(a, b);
        debug::print(&sum);

        assert!(sum == from_le_4(0, 0, 1, 1), 0);
    }
    
    #[test]
    fun test_sub_ez() {
        let a = from_le_3(1, 2, 3);
        let b = from_le_3(0, 1, 2);

        let diff = sub(a, b);
        assert!(diff == from_le_3(1,1,1), 0);
    }

    #[test]
    fun test_sub_borrow() {
        let a = from_le_3(0, 1, 0);
        let b = from_le_3(MAX_U64, 0, 0);

        let diff = sub(a, b);
        assert!(diff == from_u64(1), 0);
    }

    #[test]
    fun test_sub_borrow_2() {
        let a = from_le_3(0, 0, 1);
        let b = from_le_3(MAX_U64, 0, 0);

        let diff = sub(a, b);
        assert!(diff == from_le_2(1, MAX_U64), 0);
    }

    #[test]
    fun test_mul_zero() {
        let a = from_le_2(0, 0);
        let b = from_le_2(8, 9);
        
        assert!(mul(a, b) == zero(), 0);
        assert!(mul(b, a) == zero(), 0);
    }

    #[test]
    fun test_mul_basic() {
        let a = from_u64(8);
        let b = from_u64(9);
        
        let product = mul(a, b);
        assert!(product == from_u64(72), 0);
    }
    
    #[test]
    fun test_mul_complex() {
        let a = from_le_2(8, 7);
        let b = from_le_2(8, 9);
        
        let product = mul(a, b);
        assert!(product == from_le_3(64, 128, 63), 0);
    }


}