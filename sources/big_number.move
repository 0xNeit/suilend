//// arbitrary precision little endian integer composed of u64s. This is fairly unoptimized.

module suilend::big_number {
    use std::vector::{empty, push_back, borrow, borrow_mut};

    struct BN has drop {
        vals: vector<u64>
    }
    
    // errors
    const EOverflow: u64 = 0;
    const EUnderflow: u64 = 0;
    
    // constants
    const MAX_U64: u64 = 18446744073709551615;
    
    public fun zero(): BN {
        let vals = empty<u64>();
        push_back(&mut vals, 0);
        push_back(&mut vals, 0);
        push_back(&mut vals, 0);
        push_back(&mut vals, 0);
        
        BN {
            vals
        }
    }
    
    public fun from_index(a: u64, b: u64, c: u64, d: u64): BN {
        let num = zero();

        *borrow_mut(&mut num.vals, 0) = a;
        *borrow_mut(&mut num.vals, 1) = b;
        *borrow_mut(&mut num.vals, 2) = c;
        *borrow_mut(&mut num.vals, 3) = d;
        
        num
    }
    
    public fun from_u64(v: u64): BN {
        let num = zero();
        *borrow_mut(&mut num.vals, 3) = v;
        num 
    }
    
    public fun add(a: BN, b: BN): BN {
        let sum = zero();
        
        let i = 3;
        let carry: u64 = 0;

        loop {
            let a_i = *borrow(&a.vals, i);
            let b_i = *borrow(&b.vals, i);
            
            let sum_i = (a_i as u128) + (b_i as u128) + (carry as u128);
            *borrow_mut(&mut sum.vals, i) = ((sum_i & 0xffffffffffffffff) as u64);

            carry = ((sum_i >> 64) as u64);

            if (i == 0) {
                break
            };

            i = i - 1;
        };
        
        assert!(carry == 0, EOverflow);
        
        sum
    }

    /// subtract a by b.
    public fun sub(a: BN, b: BN): BN {
        let diff = zero();
        
        let i = 3;
        loop {
            let a_i = *borrow(&a.vals, i);
            let b_i = *borrow(&b.vals, i);

            if (a_i < b_i) {
                // loop until we find a non-zero digit to the left of a_i
                let j = 1;
                loop {
                    assert!(i >= j, EUnderflow);
                    let digit = borrow_mut(&mut a.vals, i - j);
                    if (*digit > 0) {
                        *borrow_mut(&mut diff.vals, i) = MAX_U64 - b_i + a_i + 1;
                        *digit = *digit - 1;
                        break
                    };
                    
                    *digit = MAX_U64;
                    j = j + 1;
                };
            } 
            else {
                *borrow_mut(&mut diff.vals, i) = a_i - b_i;
            };

            if (i == 0) {
                break
            };

            i = i - 1;
        };
        
        diff 
    }
    
    public fun gt(a: BN, b: BN): bool {
        let i = 3;
        loop {
            let a_i = *borrow(&a.vals, i);
            let b_i = *borrow(&b.vals, i);

            if (a_i > b_i) {
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
    

    #[test]
    fun test_from_u64() {
        use std::vector; 

        let a = from_u64(1);
        assert!(*vector::borrow(&a.vals, 3) == 1, 0);
    }
    
    #[test]
    fun test_sum() {
        use std::vector; 

        let a = from_u64(18446744073709551615u64);
        let b = from_u64(1);

        let sum = add(a, b);
        assert!(*vector::borrow(&sum.vals, 3) == 0, 0);
        assert!(*vector::borrow(&sum.vals, 2) == 1, 0);
    }
    
    #[test]
    fun test_sub_ez() {
        let a = from_index(0,0,3,1);
        let b = from_index(0,0,2,0);

        let diff = sub(a, b);
        assert!(diff == from_index(0,0,1,1), 0);
    }

    #[test]
    fun test_sub_borrow() {
        let a = from_index(0,0,1,0);
        let b = from_index(0,0,0, MAX_U64);

        let diff = sub(a, b);
        assert!(diff == from_index(0,0,0,1), 0);
    }

    #[test]
    fun test_sub_borrow_2() {
        let a = from_index(1,0,0,0);
        let b = from_index(0,0,0,1);

        let diff = sub(a, b);
        assert!(diff == from_index(0,MAX_U64,MAX_U64,MAX_U64), 0);
    }

    
}