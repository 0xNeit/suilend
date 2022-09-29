//// arbitrary precision little endian integer composed of u64s.

module suilend::big_number {
    use std::vector::{empty, push_back, borrow, length, pop_back, borrow_mut};

    struct BN has copy, drop {
        vals: vector<u64>
    }
    
    // errors
    const EOverflow: u64 = 0;
    const EUnderflow: u64 = 1;
    const EDivideByZero: u64 = 2;
    
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

    public fun from_u128(v: u128): BN {
        let vals = empty<u64>();
        push_back(&mut vals, ((v & 0xffffffffffffffff) as u64));
        push_back(&mut vals, ((v >> 64) as u64));
        
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
            
            if ((a_i as u128) < (b_i as u128) + (borrow as u128)) {
                let d = (MAX_U64 as u128) + (a_i as u128) + 1 - (b_i as u128) - (borrow as u128);
                assert!(d <= (MAX_U64 as u128), 0);
                push_back(&mut diff, (d as u64));
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
    
    // left shift.
    public fun shl(a: BN, shift: u64): BN {
        let word_shifts = shift / 64;
        let bit_shifts = ((shift % 64) as u8);

        let shifted = empty();
        {
            let i = 0;
            while (i < length(&a.vals) + word_shifts + 1) {
                push_back(&mut shifted, 0);
                i = i + 1;
            };
        };
        
        {
            let i = 0;
            while (i < length(&a.vals)) {
                let a_i = *borrow(&a.vals, i);
                *borrow_mut(&mut shifted, i + word_shifts) = (a_i << bit_shifts);

                i = i + 1;
            };
            
        };
        
        if (bit_shifts > 0) {
            let i = 1;
            while (i <= length(&a.vals)) {
                let a_i1 = *borrow(&a.vals, i-1);
                let shifted_wi = *borrow(&shifted, i + word_shifts);
                
                *borrow_mut(&mut shifted, i + word_shifts) = shifted_wi + (a_i1 >> (64 - bit_shifts));

                i = i + 1;
            };
        };

        reduce(
            BN {
                vals: shifted
            }
        )
    }
    
    public fun div(a: BN, b: BN): BN {
        assert!(b != zero(), EDivideByZero);

        if (a == zero() || lt(a,b)) {
            return zero()
        };

        if (length(&b.vals) == 1) {
            return div_small(a, *borrow(&b.vals, 0))
        };
        
        div_knuth(a, b)
    }

    fun div_small(a: BN, b: u64): BN {
        let quotient = empty();
        {
            let i = 0;
            while (i < length(&a.vals)) {
                push_back(&mut quotient, 0);
                i = i + 1;
            };
        };

        let i = length(&a.vals);
        let remainder = 0u64;

        while (i > 0) {
            i = i - 1;
            let a_i = *borrow(&a.vals, i);

            let dividend = (remainder as u128);
            dividend = dividend << 64;
            dividend = dividend + (a_i as u128);

            let q = ((dividend / (b as u128)) as u64);
            *borrow_mut(&mut quotient, i) = q;

            remainder = (dividend % (b as u128) as u64);
        };

        reduce(BN {
            vals: quotient
        })
    }

    /// knuth's long division algorithm. this doesn't _exactly_ follow his steps,
    /// i can optimize this function later.
    fun div_knuth(u: BN, v: BN): BN {
        /* use std::debug; */

        let n = length(&v.vals);
        let m = length(&u.vals) - n;

        // D1: normalize
        let shift = leading_zeros(v);
        v = shl(v, shift);
        u = shl(u, shift);
        
        if (length(&u.vals) == n + m) {
            push_back(&mut u.vals, 0);
        };

        let quotient = empty();
        {
            let i = 0;
            while (i <= m) {
                push_back(&mut quotient, 0);
                i = i + 1;
            };
        };

        assert!(length(&u.vals) == m + n + 1, 0);
        assert!(length(&v.vals) == n, 0);
        assert!(length(&quotient) == m + 1, 0);
        
        /* debug::print(&0); */
        /* debug::print(&u); */
        /* debug::print(&v); */
        
        // D2
        let j = m;
        loop {
            let u_slice = slice(u, j, j+n);
            /* debug::print(&1); */
            /* debug::print(&u_slice); */

            // D3: calculate qhat, rhat
            // we are trying to divide u_(j+n)...u_j by b.
            let qhat = (
                ((*borrow(&u.vals, j + n) as u128) << 64) 
                + (*borrow(&u.vals, j + n - 1) as u128)
                ) / (*borrow(&v.vals, n - 1) as u128);

            if (qhat > (MAX_U64 as u128)) {
                qhat = (MAX_U64 as u128);
            };
            
            let qhatv = mul(v, from_u64((qhat as u64)));

            // inefficient, can optimize later with knuths magic conditions
            while (gt(qhatv, u_slice)) {
                qhatv = sub(qhatv, v);
                qhat = qhat - 1;
            };
            
            // get remainder
            let r = sub(u_slice, qhatv);
            
            // set u_(j+n)...u_j = r
            {
                let i = 0;
                while (i <= n) {
                    let r_i = if (i < length(&r.vals)) { *borrow(&r.vals, i) } else { 0 };
                    *borrow_mut(&mut u.vals, j + i) = r_i;
                    
                    i = i + 1;
                }
            };
            
            *borrow_mut(&mut quotient, j) = (qhat as u64);
            
            /* debug::print(&2); */
            /* debug::print(&qhat); */
            /* debug::print(&u); */
            /* debug::print(&quotient); */

            if (j == 0) {
                break
            };
            
            j = j - 1;
        };

        reduce(BN {
            vals: quotient
        })
    }
    
    // inclusive slice of a BN
    fun slice(a: BN, from: u64, to: u64): BN {
        let vals = empty();
        let i = from;
        while (i <= to) {
            push_back(&mut vals, *borrow(&a.vals, i));
            i = i + 1;
        };
        
        BN {
            vals
        }
    }


    fun leading_zeros(a: BN): u64 {
        if (a == zero()) { 
            return 64
        };

        let i = length(&a.vals) - 1;
        let num_zeros = 0;
        loop {
            let a_i = *borrow(&a.vals, i);
            if (a_i == 0) {
                num_zeros = num_zeros + 64;
            }
            else {
                let j = 0;
                let msb = 1 << 63;
                while (j < 63) { // can't go to 64 bc then a_i == 0
                    if ((a_i << j) & msb == 0) {
                        num_zeros = num_zeros + 1;
                    }
                    else {
                        return num_zeros
                    };
                    
                    j = j + 1;
                };
            };
            
            if (i == 0) {
                return num_zeros
            };

            i = i - 1;
        }
    }
    
    fun gt_helper(a: BN, b: BN, equal: bool): bool {
        a = reduce(a);
        b = reduce(b);

        let a_len = length(&a.vals);
        let b_len = length(&b.vals);
        
        if (a_len > b_len) {
            return true
        };
        
        if (b_len > a_len) {
            return false
        };
        
        if (a_len == 0) {
            return equal
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
    fun from_le_2_unreduced(a: u64, b: u64): BN {
        let vals = empty();
        push_back(&mut vals, a);
        push_back(&mut vals, b);
        
        BN {
            vals
        }
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
        let a = from_le_3(MAX_U64, 0, 1);
        let b = from_le_3(1, MAX_U64, MAX_U64);

        let sum = add(a, b);
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

    #[test]
    fun test_mul_complex_2() {
        let a = from_le_2(MAX_U64, MAX_U64);
        let b = from_le_2(MAX_U64, MAX_U64);
        
        let product = mul(a, b);
        assert!(product == from_le_4(1, 0, 18446744073709551614, 18446744073709551615), 0);
    }
    
    #[test]
    fun test_shl_basic() {
        let a = from_u64(1);
        let shifted = shl(a, 5);
        assert!(shifted == from_u64(32), 0)
    }

    #[test]
    fun test_shl_basic_2() {
        let a = from_u64(1);
        let shifted = shl(a, 0);
        assert!(shifted == from_u64(1), 0)
    }
    
    #[test]
    fun test_shl_overflow() {
        let a = from_u64(MAX_U64);
        let shifted = shl(a, 32);
        assert!(shifted == from_le_2(18446744069414584320, 4294967295), 0)
    }
    
    #[test]
    fun test_shl_overflow_word_shift() {
        let a = from_u64(MAX_U64);
        let shifted = shl(a, 32 + 64*2);
        assert!(shifted == from_le_4(0, 0, 18446744069414584320, 4294967295), 0)
    }
    
    #[test]
    fun test_leading_zeros() {
        {
            let a = zero();
            assert!(leading_zeros(a) == 64, (leading_zeros(a) as u64));
        };
        {
            let a = from_u64(1);
            assert!(leading_zeros(a) == 63, (leading_zeros(a) as u64));
        };
        {
            let a = from_u64(MAX_U64);
            assert!(leading_zeros(a) == 0, (leading_zeros(a) as u64));
        };
        {
            let a = from_le_2_unreduced(1, 0);
            assert!(leading_zeros(a) == 63 + 64, (leading_zeros(a) as u64));
        };
        {
            let a = from_le_2_unreduced(2, 0);
            assert!(leading_zeros(a) == 62 + 64, (leading_zeros(a) as u64));
        };
    }

    #[test]
    fun test_div_small() {
        {
            let a = from_le_2(6, 4);
            assert!(div_small(a, 2) == from_le_2(3, 2), 0);
        };
        {
            let a = from_le_2(3, 4);
            assert!(div_small(a, 45) == from_u64(1639710584329737921), 0);
        };
    }
    
    #[test]
    fun test_div_knuth() {
        {
            let a = from_le_3(0, 0, 1);
            let b = from_u64(MAX_U64);
            let quotient = div_knuth(a, b);
            assert!(quotient == from_le_2(1, 1), 0);
        };
        {
            let a = from_le_4(0, 0, 0, MAX_U64);
            let b = from_le_2(0, MAX_U64);
            let quotient = div_knuth(a, b);
            assert!(quotient == from_le_3(0, 0, 1), 0);
        };
        {
            let a = from_le_4(1, 2, 3, MAX_U64);
            let b = from_le_2(MAX_U64, MAX_U64);
            let quotient = div_knuth(a, b);
            assert!(quotient == from_le_3(4, 18446744073709551615, 0), 0);
        };
        {
            let a = from_le_4(0, 0, 0, 1 << 32);
            let b = from_le_2(45, MAX_U64);
            let quotient = div_knuth(a, b);
            assert!(quotient == from_le_2(4294967295, 4294967296), 0);
        };
    }


}