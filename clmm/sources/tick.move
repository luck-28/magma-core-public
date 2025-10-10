module magma_clmm::tick;

use move_stl::{option_u64, skip_list};

use integer_mate::{i32::{Self, I32}, math_u128, i128::{Self, I128}};

use magma_clmm::tick_math;

const ErrLiquidityOverflow: u64 = 0;
const ErrLiquidityUnderflow: u64 = 1;
const ErrInvalidTick: u64 = 2;
const ErrTickNotFound: u64 = 3;

public struct TickManager has store {
    tick_spacing: u32,
    ticks: skip_list::SkipList<Tick>,
}

public struct Tick has copy, drop, store {
    index: I32,
    sqrt_price: u128,
    liquidity_net: I128,
    liquidity_gross: u128,
    fee_growth_outside_a: u128,
    fee_growth_outside_b: u128,
    points_growth_outside: u128,
    rewards_growth_outside: vector<u128>,
    magma_distribution_staked_liquidity_net: I128,
    magma_distribution_growth_outside: u128,
}

public(package) fun new(tick_spacing: u32, seed: u64, ctx: &mut TxContext): TickManager {
    TickManager{
        tick_spacing,
        ticks: skip_list::new<Tick>(16, 2, seed, ctx),
    }
}

public fun borrow_tick(tick_manager: &TickManager, tick_index: I32): &Tick {
    tick_manager.ticks.borrow(tick_score(tick_index))
}

public fun borrow_tick_for_swap(tick_manager: &TickManager, score: u64, a2b: bool) : (&Tick, option_u64::OptionU64) {
    let node = tick_manager.ticks.borrow_node(score);
    let next_score = if (a2b) {
        node.prev_score()
    } else {
        node.next_score()
    };
    (node.borrow_value(), next_score)
}

// NOTE: "staked liquidity net" should follow the change of "liquidity net"
public(package) fun cross_by_swap(
    tick_manager: &mut TickManager,
    tick_index: I32,
    a2b: bool,
    current_liquidity: u128,
    current_magma_distribution_staked_liquidity: u128,
    fee_growth_outside_a: u128,
    fee_growth_outside_b: u128,
    points_growth_outside: u128,
    rewards_growth: vector<u128>,
    magma_distribution_growth: u128
): (u128, u128) {
    let tick = tick_manager.ticks.borrow_mut(tick_score(tick_index));
    let (liquidity_delta, magma_distribution_liquidity_delta) = if (a2b) {
        (i128::neg(tick.liquidity_net),
            i128::neg(tick.magma_distribution_staked_liquidity_net))
    } else {
        (tick.liquidity_net,
            tick.magma_distribution_staked_liquidity_net)
    };
    let (liquidity_after, magma_distribution_liquidity_after) = if (!i128::is_neg(liquidity_delta)) {
        let l = i128::abs_u128(liquidity_delta);
        assert!(math_u128::add_check(l, current_liquidity), ErrLiquidityUnderflow);
        let sl = i128::abs_u128(magma_distribution_liquidity_delta);
        assert!(math_u128::add_check(sl, current_magma_distribution_staked_liquidity), ErrLiquidityUnderflow);
        (current_liquidity + l, current_magma_distribution_staked_liquidity + sl)
    } else {
        let l = i128::abs_u128(liquidity_delta);
        assert!(current_liquidity >= l, ErrLiquidityUnderflow);
        let sl = i128::abs_u128(magma_distribution_liquidity_delta);
        assert!(current_magma_distribution_staked_liquidity >= sl);
        (current_liquidity - l, current_magma_distribution_staked_liquidity - sl)
    };
    tick.fee_growth_outside_a = math_u128::wrapping_sub(fee_growth_outside_a, tick.fee_growth_outside_a);
    tick.fee_growth_outside_b = math_u128::wrapping_sub(fee_growth_outside_b, tick.fee_growth_outside_b);
    let mut i = 0;
    while (i < rewards_growth.length()) {
        let reward_growth = *rewards_growth.borrow(i);
        if (tick.rewards_growth_outside.length() > i) {
            let tick_rewards_growth_outside = tick.rewards_growth_outside.borrow_mut(i);
            *tick_rewards_growth_outside = math_u128::wrapping_sub(reward_growth, *tick_rewards_growth_outside);
        } else {
            tick.rewards_growth_outside.push_back(reward_growth);
        };
        i = i + 1;
    };
    tick.points_growth_outside = math_u128::wrapping_sub(points_growth_outside, tick.points_growth_outside);
    tick.magma_distribution_growth_outside = math_u128::wrapping_sub(magma_distribution_growth, tick.magma_distribution_growth_outside);
    (liquidity_after, magma_distribution_liquidity_after)
}

public(package) fun decrease_liquidity(
    tick_manager: &mut TickManager,
    current_tick_index: I32,
    tick_lower_index: I32,
    tick_upper_index: I32,
    liquidity_delta: u128,
    fee_growth_a: u128,
    fee_growth_b: u128,
    points_growth: u128,
    rewards_growth: vector<u128>,
    magma_distribution_growth: u128,
) {
    if (liquidity_delta == 0) {
        return
    };
    let tick_lower_score = tick_score(tick_lower_index);
    let tick_upper_score = tick_score(tick_upper_index);
    assert!(tick_manager.ticks.contains(tick_lower_score), ErrTickNotFound);
    assert!(tick_manager.ticks.contains(tick_upper_score), ErrTickNotFound);
    if (tick_manager.ticks.borrow_mut(tick_lower_score).update_by_liquidity(current_tick_index, liquidity_delta, false, false, false, fee_growth_a, fee_growth_b, points_growth, rewards_growth, magma_distribution_growth) == 0) {
        tick_manager.ticks.remove(tick_lower_score);
    };
    if (tick_manager.ticks.borrow_mut(tick_upper_score).update_by_liquidity(current_tick_index, liquidity_delta, false, false, true, fee_growth_a, fee_growth_b, points_growth, rewards_growth, magma_distribution_growth) == 0) {
        tick_manager.ticks.remove(tick_upper_score);
    };
}

fun default(tick_index: I32): Tick {
    Tick{
        index: tick_index,
        sqrt_price: tick_math::get_sqrt_price_at_tick(tick_index),
        liquidity_net: i128::from(0),
        liquidity_gross: 0,
        fee_growth_outside_a: 0,
        fee_growth_outside_b: 0,
        points_growth_outside: 0,
        rewards_growth_outside: vector::empty<u128>(),
        magma_distribution_growth_outside: 0,
        magma_distribution_staked_liquidity_net: i128::from(0),
    }
}

fun default_rewards_growth_outside(size: u64): vector<u128> {
    if (size <= 0) {
        vector::empty<u128>()
    } else {
        let mut ret = vector::empty<u128>();
        let mut i = 0;
        while (i < size) {
            ret.push_back(0);
            i = i + 1;
        };
        ret
    }
}

public fun fee_growth_outside(tick: &Tick): (u128, u128) {
    (tick.fee_growth_outside_a, tick.fee_growth_outside_b)
}

public fun fetch_ticks(tick_manager: &TickManager, start: vector<u32>, limit: u64): vector<Tick> {
    let mut ret = vector::empty<Tick>();
    let mut maybe_score = if (start.is_empty()) {
        tick_manager.ticks.head()
    } else {
        tick_manager.ticks.find_next(tick_score(i32::from_u32(*start.borrow(0))), false)
    };
    let mut i = 0;
    while (maybe_score.is_some()) {
        let node = tick_manager.ticks.borrow_node(maybe_score.borrow());
        ret.push_back(*node.borrow_value());
        maybe_score = node.next_score();
        i = i + 1;
        if (i == limit) {
            break
        };
    };
    ret
}

public fun first_score_for_swap(tick_manager: &TickManager, tick_index: I32, a2b: bool): option_u64::OptionU64 {
    if (a2b) {
        tick_manager.ticks.find_prev(tick_score(tick_index), true)
    } else {
        if (i32::eq(tick_index, i32::neg_from(tick_math::tick_bound() + 1))) {
            tick_manager.ticks.find_next(tick_score(tick_math::min_tick()), true)
        } else {
            tick_manager.ticks.find_next(tick_score(tick_index), false)
        }
    }
}

public fun get_fee_in_range(current_tick_index: I32, fee_growth_outside_a: u128, fee_growth_outside_b: u128, maybe_tick_lower: option::Option<Tick>, maybe_tick_upper: option::Option<Tick>): (u128, u128) {
    let (fee_growth_a_lower, fee_growth_b_lower) = if (maybe_tick_lower.is_none()) {
        (fee_growth_outside_a, fee_growth_outside_b)
    } else {
        let tick_lower = maybe_tick_lower.borrow();
        if (i32::lt(current_tick_index, tick_lower.index)) {
            (math_u128::wrapping_sub(fee_growth_outside_a, tick_lower.fee_growth_outside_a), math_u128::wrapping_sub(fee_growth_outside_b, tick_lower.fee_growth_outside_b))
        } else {
            (tick_lower.fee_growth_outside_a, tick_lower.fee_growth_outside_b)
        }
    };
    let (fee_growth_a_upper, fee_growth_b_upper) = if (maybe_tick_upper.is_none()) {
        (0, 0)
    } else {
        let tick_upper = maybe_tick_upper.borrow();
        if (i32::lt(current_tick_index, tick_upper.index)) {
            (tick_upper.fee_growth_outside_a, tick_upper.fee_growth_outside_b)
        } else {
            (math_u128::wrapping_sub(fee_growth_outside_a, tick_upper.fee_growth_outside_a), math_u128::wrapping_sub(fee_growth_outside_b, tick_upper.fee_growth_outside_b))
        }
    };
    (math_u128::wrapping_sub(math_u128::wrapping_sub(fee_growth_outside_a, fee_growth_a_lower), fee_growth_a_upper), math_u128::wrapping_sub(math_u128::wrapping_sub(fee_growth_outside_b, fee_growth_b_lower), fee_growth_b_upper))
}

public fun get_magma_distribution_growth_in_range(tick_index: I32, growth: u128, maybe_tick_lower: option::Option<Tick>, maybe_tick_upper: option::Option<Tick>): u128 {
    let magma_distri_growth_lower_delta = if (maybe_tick_lower.is_none()) {
        growth
    } else {
        let tick_lower = maybe_tick_lower.borrow();
        if (i32::lt(tick_index, tick_lower.index)) {
            math_u128::wrapping_sub(growth, tick_lower.magma_distribution_growth_outside)
        } else {
            tick_lower.magma_distribution_growth_outside
        }
    };
    let magma_distri_growth_upper_delta = if (maybe_tick_upper.is_none()) {
        0
    } else {
        let tick_upper = maybe_tick_upper.borrow();
        if (i32::lt(tick_index, tick_upper.index)) {
            tick_upper.magma_distribution_growth_outside
        } else {
            math_u128::wrapping_sub(growth, tick_upper.magma_distribution_growth_outside)
        }
    };
    math_u128::wrapping_sub(math_u128::wrapping_sub(growth, magma_distri_growth_lower_delta), magma_distri_growth_upper_delta)
}

public fun get_points_in_range(tick_index: I32, points_growth: u128, maybe_tick_lower: option::Option<Tick>, maybe_tick_upper: option::Option<Tick>): u128 {
    let points_growth_lower_delta = if (maybe_tick_lower.is_none()) {
        points_growth
    } else {
        let tick_lower = maybe_tick_lower.borrow();
        if (i32::lt(tick_index, tick_lower.index)) {
            math_u128::wrapping_sub(points_growth, tick_lower.points_growth_outside)
        } else {
            tick_lower.points_growth_outside
        }
    };
    let points_growth_upper_delta = if (maybe_tick_upper.is_none()) {
        0
    } else {
        let tick_upper = maybe_tick_upper.borrow();
        if (i32::lt(tick_index, tick_upper.index)) {
            tick_upper.points_growth_outside
        } else {
            math_u128::wrapping_sub(points_growth, tick_upper.points_growth_outside)
        }
    };
    math_u128::wrapping_sub(math_u128::wrapping_sub(points_growth, points_growth_lower_delta), points_growth_upper_delta)
}

public fun get_reward_growth_outside(tick: &Tick, reward_growth_id: u64): u128 {
    if (tick.rewards_growth_outside.length() <= reward_growth_id) {
        0
    } else {
        *tick.rewards_growth_outside.borrow(reward_growth_id)
    }
}

public fun get_rewards_in_range(current_tick_index: I32, rewards: vector<u128>, maybe_lower_tick: option::Option<Tick>, maybe_upper_tick: option::Option<Tick>): vector<u128> {
    let mut ret = vector::empty<u128>();
    let mut i = 0;
    while (i < rewards.length()) {
        let reward_growth = *rewards.borrow(i);
        let reward_growth_lower = if (maybe_lower_tick.is_none()) {
            reward_growth
        } else {
            let tick_lower = maybe_lower_tick.borrow();
            if (i32::lt(current_tick_index, tick_lower.index)) {
                math_u128::wrapping_sub(reward_growth, tick_lower.get_reward_growth_outside(i))
            } else {
                tick_lower.get_reward_growth_outside(i)
            }
        };
        let reward_growth_upper = if (maybe_upper_tick.is_none()) {
            0
        } else {
            let tick_upper = maybe_upper_tick.borrow();
            if (i32::lt(current_tick_index, tick_upper.index)) {
                tick_upper.get_reward_growth_outside(i)
            } else {
                math_u128::wrapping_sub(reward_growth, tick_upper.get_reward_growth_outside(i))
            }
        };
        ret.push_back(math_u128::wrapping_sub(math_u128::wrapping_sub(reward_growth, reward_growth_lower), reward_growth_upper));
        i = i + 1;
    };
    ret
}

public(package) fun increase_liquidity(
    tick_manager: &mut TickManager,
    current_tick_index: I32,
    tick_lower_index: I32,
    tick_upper_index: I32,
    liquidity_delta: u128,
    fee_growth_a: u128,
    fee_growth_b: u128,
    points_growth: u128,
    rewards_growth: vector<u128>,
    magma_distribution_growth: u128,
) {
    if (liquidity_delta == 0) {
        return
    };
    let tick_lower_score = tick_score(tick_lower_index);
    let tick_upper_score = tick_score(tick_upper_index);
    let mut tick_upper_flipped = false;
    let mut tick_lower_flipped = false;
    if (!tick_manager.ticks.contains(tick_lower_score)) {
        tick_manager.ticks.insert(tick_lower_score, default(tick_lower_index));
        tick_lower_flipped = true;
    };
    if (!tick_manager.ticks.contains(tick_upper_score)) {
        tick_manager.ticks.insert(tick_upper_score, default(tick_upper_index));
        tick_upper_flipped = true;
    };
    tick_manager.ticks.borrow_mut(tick_lower_score).update_by_liquidity(
        current_tick_index,
        liquidity_delta,
        tick_lower_flipped,
        true,
        false,
        fee_growth_a, fee_growth_b, points_growth, rewards_growth, magma_distribution_growth);
    tick_manager.ticks.borrow_mut(tick_upper_score).update_by_liquidity(
        current_tick_index,
        liquidity_delta,
        tick_upper_flipped,
        true,
        true,
        fee_growth_a, fee_growth_b, points_growth, rewards_growth, magma_distribution_growth);
}

public fun index(tick: &Tick): I32 {
    tick.index
}

public fun liquidity_gross(tick: &Tick): u128 {
    tick.liquidity_gross
}

public fun liquidity_net(tick: &Tick): i128::I128 {
    tick.liquidity_net
}

public fun points_growth_outside(tick: &Tick): u128 {
    tick.points_growth_outside
}

public fun rewards_growth_outside(tick: &Tick): &vector<u128> {
    &tick.rewards_growth_outside
}

public fun magma_distribution_growth_outside(tick: &Tick): u128 {
    tick.magma_distribution_growth_outside
}

public fun magma_distribution_staked_liquidity_net(tick: &Tick): i128::I128 {
    tick.magma_distribution_staked_liquidity_net
}

public fun sqrt_price(tick: &Tick): u128 {
    tick.sqrt_price
}

fun tick_score(tick_index: I32): u64 {
    let score = i32::as_u32(i32::add(tick_index, i32::from(tick_math::tick_bound())));
    assert!(score >= 0 && score <= tick_math::tick_bound() * 2, ErrInvalidTick);
    score as u64
}

public fun tick_spacing(tick_manager: &TickManager): u32 {
    tick_manager.tick_spacing
}

public(package) fun try_borrow_tick(tick_manager: &TickManager, tick_index: I32): option::Option<Tick> {
    let tick_score = tick_score(tick_index);
    if (!tick_manager.ticks.contains(tick_score)) {
        return option::none<Tick>()
    };
    option::some<Tick>(*tick_manager.ticks.borrow(tick_score))
}

public(package) fun update_magma_stake(tick_manager: &mut TickManager, tick_index: I32, liquidity_delta: I128, upper: bool) {
    let tick = tick_manager.ticks.borrow_mut(tick_score(tick_index));
    if (upper) {
        tick.magma_distribution_staked_liquidity_net = i128::wrapping_sub(tick.magma_distribution_staked_liquidity_net, liquidity_delta);
    } else {
        tick.magma_distribution_staked_liquidity_net = i128::wrapping_add(tick.magma_distribution_staked_liquidity_net, liquidity_delta);
    };
}

fun update_by_liquidity(
    tick: &mut Tick,
    current_tick_index: I32,
    liquidity_delta: u128,
    flipped: bool,
    increase: bool,
    upper: bool,
    fee_growth_a: u128,
    fee_growth_b: u128,
    points_growth: u128,
    rewards_growth: vector<u128>,
    magma_distribution_growth: u128,
): u128 {
    let liquidity_gross_after = if (increase) {
        assert!(math_u128::add_check(tick.liquidity_gross, liquidity_delta), ErrLiquidityOverflow);
        tick.liquidity_gross + liquidity_delta
    } else {
        assert!(tick.liquidity_gross >= liquidity_delta, ErrLiquidityUnderflow);
        tick.liquidity_gross - liquidity_delta
    };
    if (liquidity_gross_after == 0) {
        return 0
    };
    let (fee_growth_outside_a, fee_growth_outside_b, rewards_growth_outside, points_growth_outside, magma_distribution_growth_outside) = if (flipped) {
        if (i32::lt(current_tick_index, tick.index)) {
            (0, 0, default_rewards_growth_outside(rewards_growth.length()), 0, 0)
        } else {
            (fee_growth_a, fee_growth_b, rewards_growth, points_growth, magma_distribution_growth)
        }
    } else {
        (tick.fee_growth_outside_a, tick.fee_growth_outside_b, tick.rewards_growth_outside, tick.points_growth_outside, tick.magma_distribution_growth_outside)
    };
    let (liquidity_net_after, overflowed) = if (increase) {
        if (upper) {
            i128::overflowing_sub(tick.liquidity_net, i128::from(liquidity_delta))
        } else {
            i128::overflowing_add(tick.liquidity_net, i128::from(liquidity_delta))
        }
    } else {
        if (upper) {
            i128::overflowing_add(tick.liquidity_net, i128::from(liquidity_delta))
        } else {
            i128::overflowing_sub(tick.liquidity_net, i128::from(liquidity_delta))
        }
    };
    if (overflowed) {
        abort ErrLiquidityOverflow
    };
    tick.liquidity_gross = liquidity_gross_after;
    tick.liquidity_net = liquidity_net_after;
    tick.fee_growth_outside_a = fee_growth_outside_a;
    tick.fee_growth_outside_b = fee_growth_outside_b;
    tick.rewards_growth_outside = rewards_growth_outside;
    tick.points_growth_outside = points_growth_outside;
    tick.magma_distribution_growth_outside = magma_distribution_growth_outside;
    liquidity_gross_after
}
