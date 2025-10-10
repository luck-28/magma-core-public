#[allow(unused_const)]

module magma_clmm::clmm_math;

use integer_mate::{i32::{Self, I32}, math_u128, full_math_u64, full_math_u128, math_u256};

use magma_clmm::tick_math;

const ErrTokenAmountMaxExceed: u64 = 0;
const ErrTokenAmountMinSubceeded: u64 = 1;
const ErrMultiplicationOverflow: u64 = 2;
const ErrIntegerDowncastOverflow: u64 = 3;
const ErrInvalidSqrtPriceInput: u64 = 4;
const ErrInvalidFixedTokenType: u64 = 5;
const ErrInvalidTickIndex: u64 = 3018;

const Q64: u256 = 18446744073709551615;

// return: (amount_in, amount_out, sqrt_price, fee)
// the amount_in returned is the total amount involved in the swap, it has non info about fee or anything else.
public fun compute_swap_step(
    from_price: u128,
    to_price: u128,
    current_liquidity: u128,
    amount: u64,
    fee_rate: u64,
    a2b: bool,
    by_amount_in: bool
): (u64, u64, u128, u64) {
    if (current_liquidity == 0) {
        return (0, 0, to_price, 0)
    };
    if (a2b) {
        assert!(from_price >= to_price, ErrInvalidSqrtPriceInput);
    } else {
        assert!(from_price < to_price, ErrInvalidSqrtPriceInput);
    };
    let (amount_in, amount_out, fee_amount, end_price) = if (by_amount_in) {
        let mut amount_in_neat = full_math_u64::mul_div_floor(amount, 1000000 - fee_rate, 1000000);
        if (fee_rate > 0 && amount_in_neat == amount) {
            amount_in_neat = amount_in_neat - 1; // at least we charge 1 for fee
        };
        let max_input_amount = get_delta_up_from_input(from_price, to_price, current_liquidity, a2b);
        let (amount_in, fee_amount, end_price) = if (max_input_amount > (amount_in_neat as u256)) {
            (amount_in_neat, amount - amount_in_neat, get_next_sqrt_price_from_input(from_price, current_liquidity, amount_in_neat, a2b))
        } else {
            (max_input_amount as u64, full_math_u64::mul_div_ceil(max_input_amount as u64, fee_rate, 1000000 - fee_rate), to_price)
        };
        (amount_in, get_delta_down_from_output(from_price, end_price, current_liquidity, a2b) as u64, fee_amount, end_price)
    } else {
        let max_output_amount = get_delta_down_from_output(from_price, to_price, current_liquidity, a2b);
        let (amount_out, end_price) = if (max_output_amount > (amount as u256)) {
            (amount, get_next_sqrt_price_from_output(from_price, current_liquidity, amount, a2b))
        } else {
            (max_output_amount as u64, to_price)
        };
        let amount_in = get_delta_up_from_input(from_price, end_price, current_liquidity, a2b) as u64;
        let mut fee_amount = full_math_u64::mul_div_ceil(amount_in, fee_rate, 1000000 - fee_rate);
        if (fee_rate > 0 && fee_amount == 0) {
            fee_amount = 1; // at least we charge 1 for fee
        };
        (amount_in, amount_out, fee_amount, end_price)
    };
    (amount_in, amount_out, end_price, fee_amount)
}

public fun fee_rate_denominator() : u64 {
    1000000
}

public fun get_amount_by_liquidity(
    tick_lower_index: I32,
    tick_upper_index: I32,
    current_tick_index: I32,
    current_sqrt_price: u128,
    liquidity: u128,
    round_up: bool
): (u64, u64) {
    if (liquidity == 0) {
        return (0, 0)
    };
    if (i32::lt(current_tick_index, tick_lower_index)) {
        (get_delta_a(
            tick_math::get_sqrt_price_at_tick(tick_lower_index),
            tick_math::get_sqrt_price_at_tick(tick_upper_index),
            liquidity,
            round_up),
        0)
    } else {
        if (i32::lt(current_tick_index, tick_upper_index)) {
            (get_delta_a(
                current_sqrt_price,
                tick_math::get_sqrt_price_at_tick(tick_upper_index),
                liquidity,
                round_up
            ), get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower_index),
                current_sqrt_price,
                liquidity,
                round_up
            ))
        } else {
            (0, get_delta_b(
                tick_math::get_sqrt_price_at_tick(tick_lower_index),
                tick_math::get_sqrt_price_at_tick(tick_upper_index),
                liquidity,
                round_up
            ))
        }
    }
}

public fun get_delta_a(price1: u128, price2: u128, liquidity: u128, round_up: bool): u64 {
    let price_delta = if (price1 > price2) {
        price1 - price2
    } else {
        price2 - price1
    };
    if (price_delta == 0 || liquidity == 0) {
        return 0
    };
    let (num, overflowed) = math_u256::checked_shlw(full_math_u128::full_mul(liquidity, price_delta));
    if (overflowed) {
        abort ErrMultiplicationOverflow
    };
    math_u256::div_round(num, full_math_u128::full_mul(price1, price2), round_up) as u64
}

public fun get_delta_b(price1: u128, price2: u128, liquidity: u128, round_up: bool): u64 {
    let price_delta = if (price1 > price2) {
        price1 - price2
    } else {
        price2 - price1
    };
    if (price_delta == 0 || liquidity == 0) {
        return 0
    };
    let num = full_math_u128::full_mul(liquidity, price_delta);
    if (round_up && num & Q64 > 0) {
        return ((num >> 64) + 1) as u64
    };
    (num >> 64) as u64
}

// given price1&price2&current liquidity, calculate the max amount of token the pool can output
public fun get_delta_down_from_output(from_price: u128, to_price: u128, liquidity: u128, a2b: bool): u256 {
    let price_delta = if (from_price > to_price) {
        from_price - to_price
    } else {
        to_price - from_price
    };
    if (price_delta == 0 || liquidity == 0) {
        return 0
    };
    if (a2b) {
        full_math_u128::full_mul(liquidity, price_delta) >> 64
    } else {
        let (num, overflowed) = math_u256::checked_shlw(full_math_u128::full_mul(liquidity, price_delta));
        if (overflowed) {
            abort ErrMultiplicationOverflow
        };
        math_u256::div_round(num, full_math_u128::full_mul(from_price, to_price), false)
    }
}

// given price1&price2&current liquidity, calculate the max amount of token the trading input can be
public fun get_delta_up_from_input(from_price: u128, to_price: u128, liquidity: u128, a2b: bool): u256 {
    let price_delta = if (from_price > to_price) {
        from_price - to_price
    } else {
        to_price - from_price
    };
    if (price_delta == 0 || liquidity == 0) {
        return 0
    };
    if (a2b) {
        let (num, overflowed) = math_u256::checked_shlw(full_math_u128::full_mul(liquidity, price_delta));
        if (overflowed) {
            abort ErrMultiplicationOverflow
        };
        math_u256::div_round(num, full_math_u128::full_mul(from_price, to_price), true)
    } else {
        let num = full_math_u128::full_mul(liquidity, price_delta);
        if (num & Q64 > 0) {
            (num >> 64) + 1
        } else {
            num >> 64
        }
    }
}

public fun get_liquidity_by_amount(tick_lower_index: I32, tick_upper_index: I32, current_tick_index: I32, current_sqrt_price: u128, amount: u64, fix_amount_a: bool): (u128, u64, u64) {
    if (fix_amount_a) {
        if (i32::lt(current_tick_index, tick_lower_index)) {
            (get_liquidity_from_a(tick_math::get_sqrt_price_at_tick(tick_lower_index), tick_math::get_sqrt_price_at_tick(tick_upper_index), amount, false), amount, 0)
        } else {
            assert!(i32::lt(current_tick_index, tick_upper_index), ErrInvalidTickIndex);
            let liquidity = get_liquidity_from_a(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_upper_index), amount, false);
            let amount_b = get_delta_b(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_lower_index), liquidity, true);
            (liquidity, amount, amount_b)
        }
    } else {
        if (i32::gte(current_tick_index, tick_upper_index)) {
            (get_liquidity_from_b(tick_math::get_sqrt_price_at_tick(tick_lower_index), tick_math::get_sqrt_price_at_tick(tick_upper_index), amount, false), 0, amount)
        } else {
            assert!(i32::gte(current_tick_index, tick_lower_index), ErrInvalidTickIndex);
            let liquidity = get_liquidity_from_b(tick_math::get_sqrt_price_at_tick(tick_lower_index), current_sqrt_price, amount, false);
            let amount_a = get_delta_a(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_upper_index), liquidity, true);
            (liquidity, amount_a, amount)
        }
    }
}

public fun get_liquidity_from_a(from_sqrt_price: u128, to_sqrt_price: u128, amount: u64, round_up: bool): u128 {
    let price_delta = if (from_sqrt_price > to_sqrt_price) {
        from_sqrt_price - to_sqrt_price
    } else {
        to_sqrt_price - from_sqrt_price
    };
    math_u256::div_round((full_math_u128::full_mul(from_sqrt_price, to_sqrt_price) >> 64) * (amount as u256), price_delta as u256, round_up) as u128
}

public fun get_liquidity_from_b(from_sqrt_price: u128, to_sqrt_price: u128, amount: u64, round_up: bool): u128 {
    let price_delta = if (from_sqrt_price > to_sqrt_price) {
        from_sqrt_price - to_sqrt_price
    } else {
        to_sqrt_price - from_sqrt_price
    };
    math_u256::div_round((amount as u256) << 64, price_delta as u256, round_up) as u128
}

public fun get_next_sqrt_price_a_up(from_price: u128, liquidity: u128, amount: u64, round_up: bool): u128 {
    if (amount == 0) {
        return from_price
    };
    let (num, overflowed) = math_u256::checked_shlw(full_math_u128::full_mul(from_price, liquidity));
    if (overflowed) {
        abort ErrMultiplicationOverflow
    };
    let price = if (round_up) {
        math_u256::div_round(num, ((liquidity as u256) << 64) + full_math_u128::full_mul(from_price, amount as u128), true) as u128
    } else {
        math_u256::div_round(num, ((liquidity as u256) << 64) - full_math_u128::full_mul(from_price, amount as u128), true) as u128
    };
    if (price > tick_math::max_sqrt_price()) {
        abort ErrTokenAmountMaxExceed
    };
    if (price < tick_math::min_sqrt_price()) {
        abort ErrTokenAmountMinSubceeded
    };
    price
}

public fun get_next_sqrt_price_b_down(from_price: u128, liquidity: u128, amount: u64, round_up: bool): u128 {
    let price = if (round_up) {
        from_price + math_u128::checked_div_round((amount as u128) << 64, liquidity, !round_up)
    } else {
        from_price - math_u128::checked_div_round((amount as u128) << 64, liquidity, !round_up)
    };
    if (price > tick_math::max_sqrt_price()) {
        abort ErrTokenAmountMaxExceed
    };
    if (price < tick_math::min_sqrt_price()) {
        abort ErrTokenAmountMinSubceeded
    };
    price
}

public fun get_next_sqrt_price_from_input(from_price: u128, liquidity: u128, amount_in: u64, a2b: bool): u128 {
    if (a2b) {
        get_next_sqrt_price_a_up(from_price, liquidity, amount_in, true)
    } else {
        get_next_sqrt_price_b_down(from_price, liquidity, amount_in, true)
    }
}

public fun get_next_sqrt_price_from_output(from_price: u128, liquidity: u128, amount_out: u64, a2b: bool): u128 {
    if (a2b) {
        get_next_sqrt_price_b_down(from_price, liquidity, amount_out, false)
    } else {
        get_next_sqrt_price_a_up(from_price, liquidity, amount_out, false)
    }
}
