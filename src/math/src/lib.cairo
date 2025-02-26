use option::OptionTrait;
use traits::Into;
use integer::{
    u8_wide_mul, u16_wide_mul, u32_wide_mul, u64_wide_mul, u128_wide_mul, u256_overflow_mul,
    BoundedInt
};
use debug::PrintTrait;

/// Raise a number to a power.
/// O(log n) time complexity.
/// * `base` - The number to raise.
/// * `exp` - The exponent.
/// # Returns
/// * `u128` - The result of base raised to the power of exp.
fn pow(base: u128, exp: u128) -> u128 {
    if exp == 0 {
        1
    } else if exp == 1 {
        base
    } else if exp % 2 == 0 {
        pow(base * base, exp / 2)
    } else {
        base * pow(base * base, (exp - 1) / 2)
    }
}

/// Function to count the number of digits in a number.
/// # Arguments
/// * `num` - The number to count the digits of.
/// * `base` - Base in which to count the digits.
/// # Returns
/// * `felt252` - The number of digits in num of base
fn count_digits_of_base(mut num: u128, base: u128) -> u128 {
    let mut res = 0;
    loop {
        if num == 0 {
            break res;
        } else {
            num = num / base;
        }
        res += 1;
    }
}

trait BitShift<T> {
    fn fpow(x: T, n: T) -> T;
    fn shl(x: T, n: T) -> T;
    fn shr(x: T, n: T) -> T;
}

impl U8BitShift of BitShift<u8> {
    fn fpow(x: u8, n: u8) -> u8 {
        if n == 0 {
            1
        } else if n == 1 {
            x
        } else if (n & 1) == 1 {
            x * BitShift::fpow(x * x, n / 2)
        } else {
            BitShift::fpow(x * x, n / 2)
        }
    }
    fn shl(x: u8, n: u8) -> u8 {
        (u8_wide_mul(x, BitShift::fpow(2, n)) & BoundedInt::<u8>::max().into()).try_into().unwrap()
    }

    fn shr(x: u8, n: u8) -> u8 {
        x / BitShift::fpow(2, n)
    }
}

impl U16BitShift of BitShift<u16> {
    fn fpow(x: u16, n: u16) -> u16 {
        if n == 0 {
            1
        } else if n == 1 {
            x
        } else if (n & 1) == 1 {
            x * BitShift::fpow(x * x, n / 2)
        } else {
            BitShift::fpow(x * x, n / 2)
        }
    }
    fn shl(x: u16, n: u16) -> u16 {
        (u16_wide_mul(x, BitShift::fpow(2, n)) & BoundedInt::<u16>::max().into())
            .try_into()
            .unwrap()
    }

    fn shr(x: u16, n: u16) -> u16 {
        x / BitShift::fpow(2, n)
    }
}

impl U32BitShift of BitShift<u32> {
    fn fpow(x: u32, n: u32) -> u32 {
        if n == 0 {
            1
        } else if n == 1 {
            x
        } else if (n & 1) == 1 {
            x * BitShift::fpow(x * x, n / 2)
        } else {
            BitShift::fpow(x * x, n / 2)
        }
    }
    fn shl(x: u32, n: u32) -> u32 {
        (u32_wide_mul(x, BitShift::fpow(2, n)) & BoundedInt::<u32>::max().into())
            .try_into()
            .unwrap()
    }

    fn shr(x: u32, n: u32) -> u32 {
        x / BitShift::fpow(2, n)
    }
}

impl U64BitShift of BitShift<u64> {
    fn fpow(x: u64, n: u64) -> u64 {
        if n == 0 {
            1
        } else if n == 1 {
            x
        } else if (n & 1) == 1 {
            x * BitShift::fpow(x * x, n / 2)
        } else {
            BitShift::fpow(x * x, n / 2)
        }
    }
    fn shl(x: u64, n: u64) -> u64 {
        (u64_wide_mul(x, BitShift::fpow(2, n)) & BoundedInt::<u64>::max().into())
            .try_into()
            .unwrap()
    }

    fn shr(x: u64, n: u64) -> u64 {
        x / BitShift::fpow(2, n)
    }
}

impl U128BitShift of BitShift<u128> {
    fn fpow(x: u128, n: u128) -> u128 {
        if n == 0 {
            1
        } else if n == 1 {
            x
        } else if (n & 1) == 1 {
            x * BitShift::fpow(x * x, n / 2)
        } else {
            BitShift::fpow(x * x, n / 2)
        }
    }
    fn shl(x: u128, n: u128) -> u128 {
        let (_, bottom_word) = u128_wide_mul(x, BitShift::fpow(2, n));
        bottom_word
    }

    fn shr(x: u128, n: u128) -> u128 {
        x / BitShift::fpow(2, n)
    }
}

impl U256BitShift of BitShift<u256> {
    fn fpow(x: u256, n: u256) -> u256 {
        if n == 0 {
            1
        } else if n == 1 {
            x
        } else if (n & 1) == 1 {
            x * BitShift::fpow(x * x, n / 2)
        } else {
            BitShift::fpow(x * x, n / 2)
        }
    }
    fn shl(x: u256, n: u256) -> u256 {
        let (r, _) = u256_overflow_mul(x, BitShift::fpow(2, n));
        r
    }

    fn shr(x: u256, n: u256) -> u256 {
        x / BitShift::fpow(2, n)
    }
}

mod aliquot_sum;
mod armstrong_number;
mod collatz_sequence;
mod ed25519;
mod extended_euclidean_algorithm;
mod fast_power;
mod fibonacci;
mod gcd_of_n_numbers;
mod karatsuba;
mod mod_arithmetics;
mod perfect_number;
mod sha256;
mod sha512;
mod zellers_congruence;
mod keccak256;

#[cfg(test)]
mod tests;
