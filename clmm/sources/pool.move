#[allow(unused_const)]

module magma_clmm::pool;

use std::string::{Self, String};
use std::type_name::{Self, TypeName};

use sui::balance::{Self, Balance};
use sui::clock;
use sui::event;
use sui::package;
use sui::display;

use integer_mate::{i32::{Self, I32}, math_u64, math_u128, full_math_u64, i128::{Self, I128}, full_math_u128};

use magma_clmm::tick;
use magma_clmm::config;
use magma_clmm::rewarder;
use magma_clmm::position;
use magma_clmm::tick_math;
use magma_clmm::clmm_math;
use magma_clmm::partner;

const ErrAmountIncorrect: u64 = 0;
const ErrLiquidityOverflow: u64 = 1;
const ErrLiquidityUnderflow: u64 = 2;
const ErrLiquidityIsZero: u64 = 3;
const ErrNotEnoughLiquidity: u64 = 4;
const ErrRemainderAmountUnderflow: u64 = 5;
const ErrSwapAmountInOverflow: u64 = 6;
const ErrSwapAmountOutOverflow: u64 = 7;
const ErrFeeAmountOverflow: u64 = 8;
const ErrInvalidFeeRate: u64 = 9;
const ErrInvalidFixedCoinType: u64 = 10;
const ErrWrongSqrtPriceLimit: u64 = 11;
const ErrPoolIdIsError: u64 = 12;
const ErrPoolPaused: u64 = 13;
const ErrFlashSwapReceiptNotMatch: u64 = 14;
const ErrInvalidProtocolFeeRate: u64 = 15;
const ErrInvalidProtocolRefFeeRate: u64 = 16;
const ErrRewardNotExist: u64 = 17;
const ErrAmountOutIsZero: u64 = 18;
const ErrWrongTick: u64 = 19;
const ErrNoTickForSwap: u64 = 20;

#[error]
const ErrStakedLiquidityOverflow: vector<u8> = b"staked liquidity overflow";

const Q64: u128 = 1 << 64;

public struct POOL has drop {}

public struct Pool<phantom CoinTypeA, phantom CoinTypeB> has store, key {
    id: UID,
    coin_a: Balance<CoinTypeA>,
    coin_b: Balance<CoinTypeB>,
    tick_spacing: u32,
    fee_rate: u64,
    liquidity: u128,
    current_sqrt_price: u128,
    current_tick_index: I32,
    fee_growth_global_a: u128,
    fee_growth_global_b: u128,
    fee_protocol_coin_a: u64,
    fee_protocol_coin_b: u64,
    tick_manager: tick::TickManager,
    rewarder_manager: rewarder::RewarderManager,
    position_manager: position::PositionManager,
    is_pause: bool,
    index: u64,
    url: String,

    unstaked_liquidity_fee_rate: u64,

    magma_distribution_gauger_id: Option<ID>,
    magma_distribution_growth_global: u128,
    magma_distribution_rate: u128,
    magma_distribution_reserve: u64,
    magma_distribution_period_finish: u64,
    magma_distribution_rollover: u64,
    magma_distribution_last_updated: u64,
    magma_distribution_staked_liquidity: u128,
    magma_distribution_gauger_fee: PoolFee,
}
public fun magma_distribution_gauger_fee<A, B>(pool: &Pool<A, B>): PoolFee {
    PoolFee {
        coin_a: pool.magma_distribution_gauger_fee.coin_a,
        coin_b: pool.magma_distribution_gauger_fee.coin_b,
    }
}

public struct PoolFee has store, drop {
    coin_a: u64,
    coin_b: u64,
}
public fun pool_fee_a_b(pf: &PoolFee): (u64, u64) {
    (pf.coin_a, pf.coin_b)
}

public struct SwapResult has copy, drop {
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    protocol_fee_amount: u64,
    ref_fee_amount: u64,
    gauge_fee_amount: u64,
    steps: u64,
}

public struct FlashSwapReceipt<phantom CoinTypeA, phantom CoinTypeB> {
    pool_id: ID,
    a2b: bool,
    partner_id: ID,
    pay_amount: u64,
    fee_amount: u64,
    protocol_fee_amount: u64,
    ref_fee_amount: u64,
    gauge_fee_amount: u64,
}

public struct AddLiquidityReceipt<phantom CoinTypeA, phantom CoinTypeB> {
    pool_id: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct CalculatedSwapResult has copy, drop, store {
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    fee_rate: u64,
    ref_fee_amount: u64,
    gauge_fee_amount: u64,
    protocol_fee_amount: u64,
    after_sqrt_price: u128,
    is_exceed: bool,
    step_results: vector<SwapStepResult>,
}

public struct SwapStepResult has copy, drop, store {
    current_sqrt_price: u128,
    target_sqrt_price: u128,
    current_liquidity: u128,
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    remainder_amount: u64,
}

public struct OpenPositionEvent has copy, drop, store {
    pool: ID,
    tick_lower: I32,
    tick_upper: I32,
    position: ID,
}

public struct ClosePositionEvent has copy, drop, store {
    pool: ID,
    position: ID,
}

public struct AddLiquidityEvent has copy, drop, store {
    pool: ID,
    position: ID,
    tick_lower: I32,
    tick_upper: I32,
    liquidity: u128,
    after_liquidity: u128,
    amount_a: u64,
    amount_b: u64,
}

public struct RemoveLiquidityEvent has copy, drop, store {
    pool: ID,
    position: ID,
    tick_lower: I32,
    tick_upper: I32,
    liquidity: u128,
    after_liquidity: u128,
    amount_a: u64,
    amount_b: u64,
}

public struct SwapEvent has copy, drop, store {
    atob: bool,
    pool: ID,
    partner: ID,
    amount_in: u64,
    amount_out: u64,
    magma_fee_amount: u64,
    protocol_fee_amount: u64,
    ref_fee_amount: u64,
    fee_amount: u64,
    vault_a_amount: u64,
    vault_b_amount: u64,
    before_sqrt_price: u128,
    after_sqrt_price: u128,
    steps: u64,
}

public struct CollectProtocolFeeEvent has copy, drop, store {
    pool: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct CollectFeeEvent has copy, drop, store {
    position: ID,
    pool: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct UpdateFeeRateEvent has copy, drop, store {
    pool: ID,
    old_fee_rate: u64,
    new_fee_rate: u64,
}

public struct UpdateEmissionEvent has copy, drop, store {
    pool: ID,
    rewarder_type: TypeName,
    emissions_per_second: u128,
}

public struct AddRewarderEvent has copy, drop, store {
    pool: ID,
    rewarder_type: TypeName,
}

public struct CollectRewardEvent has copy, drop, store {
    position: ID,
    pool: ID,
    amount: u64,
}

public struct CollectGaugeFeeEvent has copy, drop, store {
    pool: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct UpdateUnstakedLiquidityFeeRateEvent has copy, drop, store {
    pool: ID,
    old_fee_rate: u64,
    new_fee_rate: u64,
}

public(package) fun new<CoinTypeA, CoinTypeB>(tick_spacing: u32, current_sqrt_price: u128, fee_rate: u64, url: String, index: u64, clock: &clock::Clock, ctx: &mut TxContext) : Pool<CoinTypeA, CoinTypeB> {
    Pool<CoinTypeA, CoinTypeB>{
        id                  : object::new(ctx),
        coin_a              : balance::zero<CoinTypeA>(),
        coin_b              : balance::zero<CoinTypeB>(),
        tick_spacing        : tick_spacing,
        fee_rate            : fee_rate,
        liquidity           : 0,
        current_sqrt_price  : current_sqrt_price,
        current_tick_index  : tick_math::get_tick_at_sqrt_price(current_sqrt_price),
        fee_growth_global_a : 0,
        fee_growth_global_b : 0,
        fee_protocol_coin_a : 0,
        fee_protocol_coin_b : 0,
        tick_manager        : tick::new(tick_spacing, clock.timestamp_ms(), ctx),
        rewarder_manager    : rewarder::new(),
        position_manager    : position::new(tick_spacing, ctx),
        is_pause            : false,
        index               : index,
        url                 : url,

        unstaked_liquidity_fee_rate: config::default_unstaked_fee_rate(),

        magma_distribution_gauger_id: option::none(),
        magma_distribution_growth_global: 0,
        magma_distribution_rate: 0,
        magma_distribution_reserve: 0,
        magma_distribution_period_finish: 0,
        magma_distribution_rollover: 0,
        magma_distribution_last_updated: clock.timestamp_ms() / 1000,
        magma_distribution_staked_liquidity: 0,
        magma_distribution_gauger_fee: PoolFee{coin_a: 0, coin_b: 0},
    }
}

public fun get_amount_by_liquidity(tick_lower_index: I32, tick_upper_index: I32, current_tick_index: I32, current_sqrt_price: u128, liquidity: u128, round_up: bool): (u64, u64) {
    if (liquidity == 0) {
        return (0, 0)
    };
    if (current_tick_index.lt(tick_lower_index)) {
        (clmm_math::get_delta_a(tick_math::get_sqrt_price_at_tick(tick_lower_index), tick_math::get_sqrt_price_at_tick(tick_upper_index), liquidity, round_up), 0)
    } else {
        let (amount_a, amount_b) = if (current_tick_index.lt(tick_upper_index)) {
            (clmm_math::get_delta_a(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_upper_index), liquidity, round_up),
                clmm_math::get_delta_b(tick_math::get_sqrt_price_at_tick(tick_lower_index), current_sqrt_price, liquidity, round_up))
        } else {
            (0, clmm_math::get_delta_b(tick_math::get_sqrt_price_at_tick(tick_lower_index), tick_math::get_sqrt_price_at_tick(tick_upper_index), liquidity, round_up))
        };
        (amount_a, amount_b)
    }
}

public fun borrow_position_info<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, position_id: ID) : &position::PositionInfo {
    pool.position_manager.borrow_position_info(position_id)
}

public fun close_position<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, position: position::Position) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let position_id = object::id(&position);
    pool.position_manager.close_position(position);
    event::emit(ClosePositionEvent{
        pool: object::id(pool),
        position: position_id,
    });
}

public fun fetch_positions<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, start: vector<ID>, limit: u64): vector<position::PositionInfo> {
    pool.position_manager.fetch_positions(start, limit)
}

public fun is_position_exist<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, position_id: ID): bool {
    pool.position_manager.is_position_exist(position_id)
}

public fun liquidity<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
    pool.liquidity
}

public fun open_position<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    tick_lower: u32,
    tick_upper: u32,
    ctx: &mut TxContext
): position::Position {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let tick_lower_index = i32::from_u32(tick_lower);
    let tick_upper_index = i32::from_u32(tick_upper);
    let pool_id = object::id(pool);
    let position = pool.position_manager.open_position<CoinTypeA, CoinTypeB>(pool_id, pool.index, pool.url, tick_lower_index, tick_upper_index, ctx);
    event::emit(OpenPositionEvent{
        pool: pool_id,
        tick_lower: tick_lower_index,
        tick_upper: tick_upper_index,
        position: object::id(&position),
    });
    position
}

public fun update_emission<CoinTypeA, CoinTypeB, RewardType>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    vault: &rewarder::RewarderGlobalVault,
    emissions_per_sec_q64: u128,
    clock: &clock::Clock,
    ctx: &mut TxContext
) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    cfg.check_rewarder_manager_role(ctx.sender());
    rewarder::update_emission<RewardType>(vault, &mut pool.rewarder_manager, pool.liquidity, emissions_per_sec_q64, clock.timestamp_ms() / 1000);
    event::emit(UpdateEmissionEvent{
        pool                 : object::id(pool),
        rewarder_type        : type_name::get<RewardType>(),
        emissions_per_second : emissions_per_sec_q64,
    });
}

public fun borrow_tick<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, tick_index: I32): &tick::Tick {
    pool.tick_manager.borrow_tick(tick_index)
}

public fun fetch_ticks<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, start: vector<u32>, limit: u64): vector<tick::Tick> {
    pool.tick_manager.fetch_ticks(start, limit)
}

public fun index<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
    pool.index
}

public fun add_liquidity<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut position::Position,
    liquidity: u128,
    clock: &clock::Clock,
    _ctx: &mut TxContext,
): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
    cfg.checked_package_version();
    assert!(liquidity != 0, ErrLiquidityIsZero);
    add_liquidity_internal<CoinTypeA, CoinTypeB>(pool, position, false, liquidity, 0, false, clock.timestamp_ms() / 1000)
}

public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut position::Position,
    amount: u64,
    fix_amount_a: bool,
    clock: &clock::Clock,
    _ctx: &mut TxContext,
): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
    cfg.checked_package_version();
    assert!(amount > 0, ErrAmountIncorrect);
    add_liquidity_internal<CoinTypeA, CoinTypeB>(pool, position, true, 0, amount, fix_amount_a, clock.timestamp_ms() / 1000)
}

fun validate_pool_position<A, B>(pool: &Pool<A, B>, position: &position::Position) {
    assert!(object::id(pool) == position.pool_id());
}

fun add_liquidity_internal<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut position::Position,
    by_amount: bool,
    liquidity: u128,
    amount: u64,
    fix_amount_a: bool,
    timestamp: u64,
): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
    assert!(!pool.is_pause, ErrPoolPaused);
    validate_pool_position(pool, position);
    pool.rewarder_manager.settle(pool.liquidity, timestamp);
    let (tick_lower_index, tick_upper_index) = position.tick_range();
    let (liquidity_delta, amount_a, amount_b) = if (by_amount) {
        clmm_math::get_liquidity_by_amount(tick_lower_index, tick_upper_index, pool.current_tick_index, pool.current_sqrt_price, amount, fix_amount_a)
    } else {
        let (amount_a_, amount_b_) = clmm_math::get_amount_by_liquidity(tick_lower_index, tick_upper_index, pool.current_tick_index, pool.current_sqrt_price, liquidity, true);
        (liquidity, amount_a_, amount_b_)
    };
    let (fee_growth_inside_a, fee_growth_inside_b, rewards_growth, points_growth_inside, magma_distribution_growth_inside) = pool.get_all_growths_in_tick_range(tick_lower_index, tick_upper_index);
    pool.tick_manager.increase_liquidity(
        pool.current_tick_index,
        tick_lower_index,
        tick_upper_index,
        liquidity_delta,
        pool.fee_growth_global_a,
        pool.fee_growth_global_b,
        pool.rewarder_manager.points_growth_global(),
        pool.rewarder_manager.rewards_growth_global(),
        pool.magma_distribution_growth_global,
    );
    if (i32::gte(pool.current_tick_index, tick_lower_index) && i32::lt(pool.current_tick_index, tick_upper_index)) {
        assert!(math_u128::add_check(pool.liquidity, liquidity_delta), ErrLiquidityOverflow);
        pool.liquidity = pool.liquidity + liquidity_delta;
    };
    let liquidity_after = pool.position_manager.increase_liquidity(position, liquidity_delta, fee_growth_inside_a, fee_growth_inside_b, points_growth_inside, rewards_growth, magma_distribution_growth_inside);
    event::emit(AddLiquidityEvent{
        pool: object::id(pool),
        position: object::id(position),
        tick_lower: tick_lower_index,
        tick_upper: tick_upper_index,
        liquidity,
        after_liquidity: liquidity_after,
        amount_a,
        amount_b,
    });
    AddLiquidityReceipt<CoinTypeA, CoinTypeB>{
        pool_id: object::id(pool),
        amount_a,
        amount_b,
    }
}

public fun add_liquidity_pay_amount<CoinTypeA, CoinTypeB>(recp: &AddLiquidityReceipt<CoinTypeA, CoinTypeB>): (u64, u64) {
    (recp.amount_a, recp.amount_b)
}

public fun balances<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : (u64, u64) {
    (pool.coin_a.value(), pool.coin_b.value())
}

public fun calculate_and_update_fee<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, position_id: ID): (u64, u64) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let position_info = pool.position_manager.borrow_position_info(position_id);
    if (position_info.info_liquidity() != 0) {
        let (tick_lower_index, tick_upper_index) = position_info.info_tick_range();
        let (fee_a, fee_b) = pool.get_fee_in_tick_range<CoinTypeA, CoinTypeB>(tick_lower_index, tick_upper_index);
        pool.position_manager.update_fee(position_id, fee_a, fee_b)
    } else {
        position_info.info_fee_owned()
    }
}

public fun calculate_and_update_points<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, position_id: ID, clock: &clock::Clock): u128 {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    pool.rewarder_manager.settle(pool.liquidity, clock.timestamp_ms() / 1000);
    let position_info = pool.position_manager.borrow_position_info(position_id);
    if (position_info.info_liquidity() != 0) {
        let (tick_lower_index, tick_upper_index) = position_info.info_tick_range();
        let points = pool.get_points_in_tick_range(tick_lower_index, tick_upper_index);
        pool.position_manager.update_points(position_id, points)
    } else {
        position::info_points_owned(pool.position_manager.borrow_position_info(position_id))
    }
}

public fun calculate_and_update_reward<CoinTypeA, CoinTypeB, T2>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, position_id: ID, clock: &clock::Clock): u64 {
    let mut maybe_reward_index = rewarder::rewarder_index<T2>(&pool.rewarder_manager);
    assert!(maybe_reward_index.is_some(), ErrRewardNotExist);
    let rewards = calculate_and_update_rewards<CoinTypeA, CoinTypeB>(cfg, pool, position_id, clock);
    *rewards.borrow(maybe_reward_index.extract())
}

public fun calculate_and_update_rewards<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, position_id: ID, clock: &clock::Clock): vector<u64> {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    pool.rewarder_manager.settle(pool.liquidity, clock.timestamp_ms() / 1000);
    let position = pool.position_manager.borrow_position_info(position_id);
    if (position.info_liquidity() != 0) {
        let (tick_lower_index, tick_upper_index) = position.info_tick_range();
        let rewards = pool.get_rewards_in_tick_range(tick_lower_index, tick_upper_index);
        pool.position_manager.update_rewards(position_id, rewards)
    } else {
        pool.position_manager.rewards_amount_owned(position_id)
    }
}

public fun calculate_and_update_magma_distribution<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, position_id: ID): u64 {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let position_info = pool.position_manager.borrow_position_info(position_id);
    if (position_info.info_liquidity() != 0) {
        let (tick_lower_index, tick_upper_index) = position_info.info_tick_range();
        let g = tick::get_magma_distribution_growth_in_range(
            pool.current_tick_index,
            pool.magma_distribution_growth_global,
            pool.tick_manager.try_borrow_tick(tick_lower_index),
            pool.tick_manager.try_borrow_tick(tick_upper_index)
        );
        pool.position_manager.update_magma_distribution(position_id, g)
    } else {
        position_info.info_magma_distribution_owned()
    }
}

public fun calculate_swap_result<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &Pool<CoinTypeA, CoinTypeB>, a2b: bool, by_amount_in: bool, amount: u64): CalculatedSwapResult {
    let mut from_sqrt_price = pool.current_sqrt_price;
    let mut current_liquidity = pool.liquidity;
    let mut current_magma_distribution_staked_liquidity = pool.magma_distribution_staked_liquidity;
    let mut swap_result = default_swap_result();
    let mut amount_remaining = amount;
    let mut maybe_tick_score = pool.tick_manager.first_score_for_swap(pool.current_tick_index, a2b);
    let mut calculated_result = CalculatedSwapResult{
        amount_in: 0,
        amount_out: 0,
        fee_amount: 0,
        ref_fee_amount: 0,
        gauge_fee_amount: 0,
        protocol_fee_amount: 0,
        fee_rate: pool.fee_rate,
        after_sqrt_price: pool.current_sqrt_price,
        is_exceed: false,
        step_results: vector::empty<SwapStepResult>(),
    };
    let unstaked_liquidity_fee_rate = if (pool.unstaked_liquidity_fee_rate == config::default_unstaked_fee_rate()) {
        cfg.unstaked_liquidity_fee_rate()
    } else {
        pool.unstaked_liquidity_fee_rate
    };
    // let mut gauger_fee = 0;
    let protocol_fee_rate = cfg.protocol_fee_rate();
    while (amount_remaining > 0) {
        if (maybe_tick_score.is_none()) {
            calculated_result.is_exceed = true;
            break
        };
        let (tick, score) = pool.tick_manager.borrow_tick_for_swap(maybe_tick_score.borrow(), a2b);
        maybe_tick_score = score;
        let to_sqrt_price = tick.sqrt_price();
        let (step_amount_in, step_amount_out, step_sqrt_price, step_fee_amount) = clmm_math::compute_swap_step(from_sqrt_price, to_sqrt_price, current_liquidity, amount_remaining, pool.fee_rate, a2b, by_amount_in);
        if (step_amount_in != 0 || step_fee_amount != 0) {
            amount_remaining = if (by_amount_in) {
                check_remainer_amount_sub(check_remainer_amount_sub(amount_remaining, step_amount_in), step_fee_amount)
            } else {
                check_remainer_amount_sub(amount_remaining, step_amount_out)
            };

            // XXX: magma
            let fee_protocol_share = full_math_u64::mul_div_ceil(step_fee_amount, protocol_fee_rate, config::protocol_fee_rate_denom());
            let net_step_fee_amount = step_fee_amount - fee_protocol_share;
            let (_, magma_fee_amount) = calculate_fees(pool, net_step_fee_amount, pool.liquidity, pool.magma_distribution_staked_liquidity, unstaked_liquidity_fee_rate);
            swap_result.update_swap_result(step_amount_in, step_amount_out, step_fee_amount, fee_protocol_share, 0, magma_fee_amount);
        };

        let step_result = SwapStepResult{
            current_sqrt_price: from_sqrt_price,
            target_sqrt_price: to_sqrt_price,
            current_liquidity: current_liquidity,
            amount_in: step_amount_in,
            amount_out: step_amount_out,
            fee_amount: step_fee_amount,
            remainder_amount: amount_remaining,
        };
        calculated_result.step_results.push_back<SwapStepResult>(step_result);
        if (step_sqrt_price == to_sqrt_price) {
            from_sqrt_price = to_sqrt_price;
            let (tick_liquidity_net, tick_magma_distribution_staked_liquidity_net) = if (a2b) {
                (i128::neg(tick.liquidity_net()), i128::neg(tick.magma_distribution_staked_liquidity_net()))
            } else {
                (tick.liquidity_net(), tick.magma_distribution_staked_liquidity_net())
            };
            let _tick_liquidity_net_ = i128::abs_u128(tick_liquidity_net);
            let _tick_magma_distribution_staked_liquidity_net_ = i128::abs_u128(tick_magma_distribution_staked_liquidity_net);
            if (!i128::is_neg(tick_liquidity_net)) {
                assert!(math_u128::add_check(current_liquidity, _tick_liquidity_net_), ErrLiquidityOverflow);
                current_liquidity = current_liquidity + _tick_liquidity_net_;
            } else {
                assert!(current_liquidity >= _tick_liquidity_net_, ErrLiquidityOverflow);
                current_liquidity = current_liquidity - _tick_liquidity_net_;
            };
            if (!i128::is_neg(tick_magma_distribution_staked_liquidity_net)) {
                assert!(math_u128::add_check(current_magma_distribution_staked_liquidity, _tick_magma_distribution_staked_liquidity_net_), ErrLiquidityOverflow);
                current_magma_distribution_staked_liquidity = current_magma_distribution_staked_liquidity + _tick_magma_distribution_staked_liquidity_net_;
            } else {
                assert!(current_magma_distribution_staked_liquidity >= _tick_magma_distribution_staked_liquidity_net_, ErrLiquidityOverflow);
                current_magma_distribution_staked_liquidity = current_magma_distribution_staked_liquidity - _tick_magma_distribution_staked_liquidity_net_;
            };
            continue
        };
        from_sqrt_price = step_sqrt_price;
    };
    calculated_result.amount_in = swap_result.amount_in;
    calculated_result.amount_out = swap_result.amount_out;
    calculated_result.fee_amount = swap_result.fee_amount;
    calculated_result.gauge_fee_amount = swap_result.gauge_fee_amount;
    calculated_result.protocol_fee_amount = swap_result.protocol_fee_amount;
    calculated_result.after_sqrt_price = from_sqrt_price;
    calculated_result
}

public fun calculate_swap_result_with_partner<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &Pool<CoinTypeA, CoinTypeB>, a2b: bool, by_amount_in: bool, amount: u64, protocol_ref_fee_rate: u64): CalculatedSwapResult {
    let mut from_sqrt_price = pool.current_sqrt_price;
    let mut current_liquidity = pool.liquidity;
    let mut current_magma_distribution_staked_liquidity = pool.magma_distribution_staked_liquidity;
    let mut swap_result = default_swap_result();
    let mut amount_remaining = amount;
    let mut maybe_tick_score = pool.tick_manager.first_score_for_swap(pool.current_tick_index, a2b);
    let mut calculated_result = CalculatedSwapResult{
        amount_in: 0,
        amount_out: 0,
        fee_amount: 0,
        ref_fee_amount: 0,
        gauge_fee_amount: 0,
        protocol_fee_amount: 0,
        fee_rate: pool.fee_rate,
        after_sqrt_price: pool.current_sqrt_price,
        is_exceed: false,
        step_results: vector::empty<SwapStepResult>(),
    };
    let unstaked_liquidity_fee_rate = if (pool.unstaked_liquidity_fee_rate == config::default_unstaked_fee_rate()) {
        cfg.unstaked_liquidity_fee_rate()
    } else {
        pool.unstaked_liquidity_fee_rate
    };
    let protocol_fee_rate = cfg.protocol_fee_rate();
    while (amount_remaining > 0) {
        if (maybe_tick_score.is_none()) {
            calculated_result.is_exceed = true;
            break
        };
        let (tick, score) = pool.tick_manager.borrow_tick_for_swap(maybe_tick_score.borrow(), a2b);
        maybe_tick_score = score;
        let to_sqrt_price = tick.sqrt_price();
        let (step_amount_in, step_amount_out, step_sqrt_price, step_fee_amount) = clmm_math::compute_swap_step(from_sqrt_price, to_sqrt_price, current_liquidity, amount_remaining, pool.fee_rate, a2b, by_amount_in);
        if (step_amount_in != 0 || step_fee_amount != 0) {
            amount_remaining = if (by_amount_in) {
                check_remainer_amount_sub(check_remainer_amount_sub(amount_remaining, step_amount_in), step_fee_amount)
            } else {
                check_remainer_amount_sub(amount_remaining, step_amount_out)
            };

            // XXX: magma
            let step_partner_share = full_math_u64::mul_div_ceil(step_fee_amount, protocol_ref_fee_rate, config::protocol_fee_rate_denom());
            let mut net_step_fee_amount = step_fee_amount - step_partner_share;
            let mut magma_fee_amount = 0;
            let mut step_protocol_share = 0;
            if (net_step_fee_amount > 0) {
                step_protocol_share = full_math_u64::mul_div_ceil(net_step_fee_amount, protocol_fee_rate, config::protocol_fee_rate_denom());
                net_step_fee_amount = net_step_fee_amount - step_protocol_share;
                if (net_step_fee_amount > 0) {
                    (_, magma_fee_amount) = calculate_fees(pool, net_step_fee_amount, pool.liquidity, pool.magma_distribution_staked_liquidity, unstaked_liquidity_fee_rate);
                    // net_step_fee_amount = net_step_fee_amount - magma_fee_amount;
                };
            };
            swap_result.update_swap_result(step_amount_in, step_amount_out, step_fee_amount, step_protocol_share, step_partner_share, magma_fee_amount);
        };
        let step_result = SwapStepResult{
            current_sqrt_price: from_sqrt_price,
            target_sqrt_price: to_sqrt_price,
            current_liquidity: current_liquidity,
            amount_in: step_amount_in,
            amount_out: step_amount_out,
            fee_amount: step_fee_amount,
            remainder_amount: amount_remaining,
        };
        calculated_result.step_results.push_back<SwapStepResult>(step_result);
        if (step_sqrt_price == to_sqrt_price) {
            from_sqrt_price = to_sqrt_price;
            let (tick_liquidity_net, tick_magma_distribution_staked_liquidity_net) = if (a2b) {
                (i128::neg(tick.liquidity_net()), i128::neg(tick.magma_distribution_staked_liquidity_net()))
            } else {
                (tick.liquidity_net(), tick.magma_distribution_staked_liquidity_net())
            };
            let _tick_liquidity_net_ = i128::abs_u128(tick_liquidity_net);
            let _tick_magma_distribution_staked_liquidity_net_ = i128::abs_u128(tick_magma_distribution_staked_liquidity_net);
            if (!i128::is_neg(tick_liquidity_net)) {
                assert!(math_u128::add_check(current_liquidity, _tick_liquidity_net_), ErrLiquidityOverflow);
                current_liquidity = current_liquidity + _tick_liquidity_net_;
            } else {
                assert!(current_liquidity >= _tick_liquidity_net_, ErrLiquidityOverflow);
                current_liquidity = current_liquidity - _tick_liquidity_net_;
            };
            if (!i128::is_neg(tick_magma_distribution_staked_liquidity_net)) {
                assert!(math_u128::add_check(current_magma_distribution_staked_liquidity, _tick_magma_distribution_staked_liquidity_net_), ErrLiquidityOverflow);
                current_magma_distribution_staked_liquidity = current_magma_distribution_staked_liquidity + _tick_magma_distribution_staked_liquidity_net_;
            } else {
                assert!(current_magma_distribution_staked_liquidity >= _tick_magma_distribution_staked_liquidity_net_, ErrLiquidityOverflow);
                current_magma_distribution_staked_liquidity = current_magma_distribution_staked_liquidity - _tick_magma_distribution_staked_liquidity_net_;
            };
            continue
        };
        from_sqrt_price = step_sqrt_price;
    };
    calculated_result.amount_in = swap_result.amount_in;
    calculated_result.amount_out = swap_result.amount_out;
    calculated_result.fee_amount = swap_result.fee_amount;
    calculated_result.gauge_fee_amount = swap_result.gauge_fee_amount;
    calculated_result.protocol_fee_amount = swap_result.protocol_fee_amount;
    calculated_result.ref_fee_amount = swap_result.ref_fee_amount;
    calculated_result.after_sqrt_price = from_sqrt_price;
    calculated_result
}

public fun calculate_swap_result_step_results(res: &CalculatedSwapResult): &vector<SwapStepResult> {
    &res.step_results
}

public fun calculated_swap_result_after_sqrt_price(res: &CalculatedSwapResult): u128 {
    res.after_sqrt_price
}

public fun calculated_swap_result_amount_in(res: &CalculatedSwapResult): u64 {
    res.amount_in
}

public fun calculated_swap_result_amount_out(res: &CalculatedSwapResult): u64 {
    res.amount_out
}

public fun calculated_swap_result_fees_amount(res: &CalculatedSwapResult): (u64, u64, u64, u64) {
    (res.fee_amount, res.ref_fee_amount, res.protocol_fee_amount, res.gauge_fee_amount)
}

public fun calculated_swap_result_is_exceed(res: &CalculatedSwapResult): bool {
    res.is_exceed
}

public fun calculated_swap_result_step_swap_result(res: &CalculatedSwapResult, step: u64): &SwapStepResult {
    res.step_results.borrow(step)
}

public fun calculated_swap_result_steps_length(res: &CalculatedSwapResult): u64 {
    res.step_results.length()
}

fun check_remainer_amount_sub(lhd: u64, rhd: u64): u64 {
    assert!(lhd >= rhd, ErrRemainderAmountUnderflow);
    lhd - rhd
}

public fun collect_fee<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &position::Position,
    recalculate: bool
): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let position_id = object::id(position);
    let position_info = pool.borrow_position_info(position_id);
    if (position_info.is_staked()) {
        return (balance::zero(), balance::zero())
    };
    let (tick_lower_index, tick_upper_index) = position.tick_range();
    let (amount_a, amount_b) = if (recalculate && position.liquidity() != 0) {
        let (fee_amount_a, fee_amount_b) = pool.get_fee_in_tick_range(tick_lower_index, tick_upper_index);
        pool.position_manager.update_and_reset_fee(position_id, fee_amount_a, fee_amount_b)
    } else {
        pool.position_manager.reset_fee(position_id)
    };
    event::emit(CollectFeeEvent{
        position: position_id,
        pool: object::id(pool),
        amount_a,
        amount_b,
    });
    (pool.coin_a.split(amount_a), pool.coin_b.split(amount_b))
}

public fun collect_protocol_fee<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    ctx: &mut TxContext
): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    cfg.check_protocol_fee_claim_role(ctx.sender());
    let fee_protocol_coin_a = pool.fee_protocol_coin_a;
    let fee_protocol_coin_b = pool.fee_protocol_coin_b;
    pool.fee_protocol_coin_a = 0;
    pool.fee_protocol_coin_b = 0;
    event::emit(CollectProtocolFeeEvent{
        pool     : object::id(pool),
        amount_a : fee_protocol_coin_a,
        amount_b : fee_protocol_coin_b,
    });
    (pool.coin_a.split(fee_protocol_coin_a), pool.coin_b.split(fee_protocol_coin_b))
}

public fun collect_reward<CoinTypeA, CoinTypeB, RewardType>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &position::Position,
    vault: &mut rewarder::RewarderGlobalVault,
    recalculate: bool,
    clock: &clock::Clock
): Balance<RewardType> {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    pool.rewarder_manager.settle(pool.liquidity, clock.timestamp_ms() / 1000);
    let position_id = object::id(position);
    let mut maybe_rewarder_index = pool.rewarder_manager.rewarder_index<RewardType>();
    assert!(maybe_rewarder_index.is_some(), ErrRewardNotExist);
    let rewarder_index = maybe_rewarder_index.extract();
    let amount = if (recalculate && position.liquidity() != 0 || pool.position_manager.inited_rewards_count(position_id) <= rewarder_index) {
        let (tick_lower_index, tick_upper_index) = position.tick_range();
        let rewards = pool.get_rewards_in_tick_range(tick_lower_index, tick_upper_index);
        pool.position_manager.update_and_reset_rewards(position_id, rewards, rewarder_index)
    } else {
        pool.position_manager.reset_rewarder(position_id, rewarder_index)
    };
    event::emit(CollectRewardEvent{
        position : position_id,
        pool     : object::id(pool),
        amount   : amount,
    });
    vault.withdraw_reward(amount)
}

public fun current_sqrt_price<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
    pool.current_sqrt_price
}

public fun current_tick_index<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): I32 {
    pool.current_tick_index
}

fun default_swap_result(): SwapResult {
    SwapResult{
        amount_in: 0,
        amount_out: 0,
        fee_amount: 0,
        protocol_fee_amount: 0,
        ref_fee_amount: 0,
        gauge_fee_amount: 0,
        steps: 0,
    }
}

public fun fee_rate<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
    pool.fee_rate
}

public fun fees_growth_global<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): (u128, u128) {
    (pool.fee_growth_global_a, pool.fee_growth_global_b)
}

public fun flash_swap<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    target_sqrt_price: u128,
    clock: &clock::Clock
): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    flash_swap_internal<CoinTypeA, CoinTypeB>(pool, cfg, object::id_from_address(@0x0), 0, a2b, by_amount_in, amount, target_sqrt_price, clock)
}

fun flash_swap_internal<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    cfg: &config::GlobalConfig,
    partner_id: ID,
    partner_fee_rate: u64,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    target_sqrt_price: u128,
    clock: &clock::Clock
): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
    assert!(amount > 0, ErrAmountIncorrect);
    pool.rewarder_manager.settle(pool.liquidity, clock.timestamp_ms() / 1000);
    if (a2b) {
        assert!(pool.current_sqrt_price > target_sqrt_price && target_sqrt_price >= tick_math::min_sqrt_price(), ErrWrongSqrtPriceLimit);
    } else {
        assert!(pool.current_sqrt_price < target_sqrt_price && target_sqrt_price <= tick_math::max_sqrt_price(), ErrWrongSqrtPriceLimit);
    };
    let local_unstaked_liquidity_fee_rate = pool.unstaked_liquidity_fee_rate;
    let swap_result = pool.swap_in_pool(
        a2b,
        by_amount_in,
        target_sqrt_price,
        amount,
        if (local_unstaked_liquidity_fee_rate == config::default_unstaked_fee_rate()) { cfg.unstaked_liquidity_fee_rate() } else { local_unstaked_liquidity_fee_rate },
        cfg.protocol_fee_rate(),
        partner_fee_rate,
        clock
    );
    assert!(swap_result.amount_out > 0, ErrAmountOutIsZero);
    let (balance_a, balance_b) = if (a2b) {
        (balance::zero<CoinTypeA>(), pool.coin_b.split(swap_result.amount_out))
    } else {
        (pool.coin_a.split(swap_result.amount_out), balance::zero<CoinTypeB>())
    };
    event::emit(SwapEvent{
        atob: a2b,
        pool: object::id(pool),
        partner: partner_id,
        amount_in: swap_result.amount_in + swap_result.fee_amount,
        amount_out: swap_result.amount_out,
        ref_fee_amount: swap_result.ref_fee_amount,
        fee_amount: swap_result.fee_amount,
        magma_fee_amount: swap_result.gauge_fee_amount,
        protocol_fee_amount: swap_result.protocol_fee_amount,
        vault_a_amount: pool.coin_a.value(),
        vault_b_amount: pool.coin_b.value(),
        before_sqrt_price: pool.current_sqrt_price,
        after_sqrt_price: pool.current_sqrt_price,
        steps: swap_result.steps,
    });
    let recp = FlashSwapReceipt<CoinTypeA, CoinTypeB>{
        pool_id: object::id(pool),
        a2b: a2b,
        partner_id: partner_id,
        pay_amount: swap_result.amount_in + swap_result.fee_amount,
        fee_amount: swap_result.fee_amount,
        protocol_fee_amount: swap_result.protocol_fee_amount,
        ref_fee_amount: swap_result.ref_fee_amount,
        gauge_fee_amount: swap_result.gauge_fee_amount,
    };
    (balance_a, balance_b, recp)
}

public fun flash_swap_with_partner<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    partner: &partner::Partner,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    target_sqrt_price: u128,
    clock: &clock::Clock
): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    flash_swap_internal<CoinTypeA, CoinTypeB>(pool, cfg, object::id(partner), partner.current_ref_fee_rate(clock.timestamp_ms() / 1000), a2b, by_amount_in, amount, target_sqrt_price, clock)
}

public fun get_fee_in_tick_range<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, tick_lower_index: I32, tick_upper_index: I32): (u128, u128) {
    tick::get_fee_in_range(
        pool.current_tick_index,
        pool.fee_growth_global_a,
        pool.fee_growth_global_b,
        pool.tick_manager.try_borrow_tick(tick_lower_index),
        pool.tick_manager.try_borrow_tick(tick_upper_index))
}

public fun get_all_growths_in_tick_range<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    tick_lower_index: I32,
    tick_upper_index: I32
): (u128, u128, vector<u128>, u128, u128) {
    let tick_lower = pool.tick_manager.try_borrow_tick(tick_lower_index);
    let tick_upper = pool.tick_manager.try_borrow_tick(tick_upper_index);
    let (fee_growth_a, fee_growth_b) = tick::get_fee_in_range(
        pool.current_tick_index,
        pool.fee_growth_global_a,
        pool.fee_growth_global_b,
        tick_lower,
        tick_upper);
    (
        fee_growth_a,
        fee_growth_b,
        tick::get_rewards_in_range(pool.current_tick_index, pool.rewarder_manager.rewards_growth_global(), tick_lower, tick_upper),
        tick::get_points_in_range(pool.current_tick_index, pool.rewarder_manager.points_growth_global(), tick_lower, tick_upper),
        tick::get_magma_distribution_growth_in_range(pool.current_tick_index, pool.magma_distribution_growth_global, tick_lower, tick_upper)
    )
}

public fun get_liquidity_from_amount(tick_lower_index: I32, tick_upper_index: I32, current_tick_index: I32, current_sqrt_price: u128, amount: u64, by_amount_a: bool): (u128, u64, u64) {
    if (by_amount_a) {
        if (i32::lt(current_tick_index, tick_lower_index)) {
            (clmm_math::get_liquidity_from_a(tick_math::get_sqrt_price_at_tick(tick_lower_index), tick_math::get_sqrt_price_at_tick(tick_upper_index), amount, false), amount, 0)
        } else {
            assert!(i32::lt(current_tick_index, tick_upper_index), ErrWrongTick);
            let liquidity = clmm_math::get_liquidity_from_a(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_upper_index), amount, false);
            let amount_b = clmm_math::get_delta_b(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_lower_index), liquidity, true);
            (liquidity, amount, amount_b)
        }
    } else {
        if (i32::gte(current_tick_index, tick_upper_index)) {
            (clmm_math::get_liquidity_from_b(tick_math::get_sqrt_price_at_tick(tick_lower_index), tick_math::get_sqrt_price_at_tick(tick_upper_index), amount, false), 0, amount)
        } else {
            assert!(i32::gte(current_tick_index, tick_lower_index), ErrWrongTick);
            let liquidity = clmm_math::get_liquidity_from_b(tick_math::get_sqrt_price_at_tick(tick_lower_index), current_sqrt_price, amount, false);
            let amount_a = clmm_math::get_delta_a(current_sqrt_price, tick_math::get_sqrt_price_at_tick(tick_upper_index), liquidity, true);
            (liquidity, amount_a, amount)
        }
    }
}

public fun get_points_in_tick_range<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, tick_lower_index: I32, tick_upper_index: I32): u128 {
    tick::get_points_in_range(
        pool.current_tick_index,
        pool.rewarder_manager.points_growth_global(),
        pool.tick_manager.try_borrow_tick(tick_lower_index),
        pool.tick_manager.try_borrow_tick(tick_upper_index))
}

public fun get_position_amounts<CoinTypeA, CoinTypeB>(pool: &mut Pool<CoinTypeA, CoinTypeB>, position_id: ID): (u64, u64) {
    let position_info = pool.position_manager.borrow_position_info(position_id);
    let (lower_range, upper_index) = position_info.info_tick_range();
    get_amount_by_liquidity(lower_range, upper_index, pool.current_tick_index, pool.current_sqrt_price, position_info.info_liquidity(), false)
}

public fun get_position_fee<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, position_id: ID): (u64, u64) {
    pool.position_manager.borrow_position_info(position_id).info_fee_owned()
}

public fun get_position_points<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, position_id: ID): u128 {
    pool.position_manager.borrow_position_info(position_id).info_points_owned()
}

public fun get_position_reward<CoinTypeA, CoinTypeB, RewardType>(pool: &Pool<CoinTypeA, CoinTypeB>, position_id: ID): u64 {
    let mut rewarder_index = pool.rewarder_manager.rewarder_index<RewardType>();
    assert!(rewarder_index.is_some(), ErrRewardNotExist);
    let rewards_amount_owned = pool.position_manager.rewards_amount_owned(position_id);
    *rewards_amount_owned.borrow(rewarder_index.extract())
}

public fun get_position_rewards<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, position_id: ID) : vector<u64> {
    pool.position_manager.rewards_amount_owned(position_id)
}

public fun get_rewards_in_tick_range<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, tick_lower_index: I32, tick_upper_index: i32::I32) : vector<u128> {
    tick::get_rewards_in_range(
        pool.current_tick_index,
        pool.rewarder_manager.rewards_growth_global(),
        pool.tick_manager.try_borrow_tick(tick_lower_index),
        pool.tick_manager.try_borrow_tick(tick_upper_index))
}

fun init(otw: POOL, ctx: &mut TxContext) {
    transfer::public_transfer(package::claim(otw, ctx), ctx.sender());
}

public fun initialize_rewarder<CoinTypeA, CoinTypeB, RewardType>(
    cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, ctx: &mut TxContext
) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    cfg.check_rewarder_manager_role(ctx.sender());
    pool.rewarder_manager.add_rewarder<RewardType>();
    event::emit(AddRewarderEvent{
        pool: object::id(pool),
        rewarder_type: type_name::get<RewardType>(),
    });
}

public fun is_pause<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : bool {
    pool.is_pause
}

public fun pause<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, ctx: &mut TxContext) {
    cfg.checked_package_version();
    cfg.check_pool_manager_role(ctx.sender());
    assert!(!pool.is_pause);
    pool.is_pause = true;
}

public fun position_manager<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): &position::PositionManager {
    &pool.position_manager
}

public fun protocol_fee<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : (u64, u64) {
    (pool.fee_protocol_coin_a, pool.fee_protocol_coin_b)
}

public fun unstaked_liquidity_fee_rate<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : u64 {
    pool.unstaked_liquidity_fee_rate
}

public fun fees_amount<CoinTypeA, CoinTypeB>(recp: &FlashSwapReceipt<CoinTypeA, CoinTypeB>): (u64, u64, u64, u64) {
    (recp.fee_amount, recp.ref_fee_amount, recp.protocol_fee_amount, recp.gauge_fee_amount)
}

public fun remove_liquidity<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut position::Position,
    liquidity: u128,
    clock: &clock::Clock
): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    assert!(liquidity > 0, ErrLiquidityIsZero);
    pool.rewarder_manager.settle(pool.liquidity, clock.timestamp_ms() / 1000);
    let (tick_lower_index, tick_upper_index) = position.tick_range();
    let (fee_growth_a, fee_growth_b, rewards_growth, points_growth, magma_distribution_growth) = pool.get_all_growths_in_tick_range(tick_lower_index, tick_upper_index);
    pool.tick_manager.decrease_liquidity(
        pool.current_tick_index,
        tick_lower_index,
        tick_upper_index,
        liquidity,
        pool.fee_growth_global_a,
        pool.fee_growth_global_b,
        pool.rewarder_manager.points_growth_global(),
        pool.rewarder_manager.rewards_growth_global(),
        pool.magma_distribution_growth_global
    );
    if (i32::lte(tick_lower_index, pool.current_tick_index) && i32::lt(pool.current_tick_index, tick_upper_index)) {
        pool.liquidity = pool.liquidity - liquidity;
    };
    let (amount_a, amount_b) = get_amount_by_liquidity(tick_lower_index, tick_upper_index, pool.current_tick_index, pool.current_sqrt_price, liquidity, false);
    event::emit(RemoveLiquidityEvent{
        pool            : object::id(pool),
        position        : object::id(position),
        tick_lower      : tick_lower_index,
        tick_upper      : tick_upper_index,
        liquidity       : liquidity,
        after_liquidity : pool.position_manager.decrease_liquidity(position, liquidity, fee_growth_a, fee_growth_b, points_growth, rewards_growth, magma_distribution_growth),
        amount_a        : amount_a,
        amount_b        : amount_b,
    });
    (pool.coin_a.split(amount_a), pool.coin_b.split(amount_b))
}

public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    balance_a: Balance<CoinTypeA>,
    balance_b: Balance<CoinTypeB>,
    add_liquidity_receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>
) {
    cfg.checked_package_version();
    let AddLiquidityReceipt {
        pool_id,
        amount_a,
        amount_b,
    } = add_liquidity_receipt;
    assert!(balance_a.value() == amount_a, ErrAmountIncorrect);
    assert!(balance_b.value() == amount_b, ErrAmountIncorrect);
    assert!(object::id(pool) == pool_id, ErrPoolIdIsError);
    pool.coin_a.join(balance_a);
    pool.coin_b.join(balance_b);
}

public fun repay_flash_swap<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    balance_a: Balance<CoinTypeA>,
    balance_b: Balance<CoinTypeB>,
    flash_swap_receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let FlashSwapReceipt {
        pool_id,
        a2b,
        partner_id: _,
        pay_amount,
        fee_amount: _,
        protocol_fee_amount: _,
        ref_fee_amount,
        gauge_fee_amount: _,
    } = flash_swap_receipt;
    assert!(object::id(pool) == pool_id, ErrFlashSwapReceiptNotMatch);
    assert!(ref_fee_amount == 0, ErrFlashSwapReceiptNotMatch);
    if (a2b) {
        assert!(balance_a.value() == pay_amount, ErrAmountIncorrect);
        pool.coin_a.join(balance_a);
        balance_b.destroy_zero();
    } else {
        assert!(balance_b.value() == pay_amount, ErrAmountIncorrect);
        pool.coin_b.join(balance_b);
        balance_a.destroy_zero();
    };
}

public fun repay_flash_swap_with_partner<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    partner: &mut partner::Partner,
    mut balance_a: Balance<CoinTypeA>,
    mut balance_b: Balance<CoinTypeB>,
    flash_swap_receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    let FlashSwapReceipt {
        pool_id,
        a2b,
        partner_id,
        pay_amount,
        ref_fee_amount,
        fee_amount: _,
        protocol_fee_amount: _,
        gauge_fee_amount: _,
    } = flash_swap_receipt;
    assert!(object::id(pool) == pool_id, ErrFlashSwapReceiptNotMatch);
    assert!(object::id(partner) == partner_id, ErrFlashSwapReceiptNotMatch);
    if (a2b) {
        assert!(balance_a.value() == pay_amount, ErrAmountIncorrect);
        if (ref_fee_amount > 0) {
            partner.receive_ref_fee(balance_a.split(ref_fee_amount));
        };
        pool.coin_a.join(balance_a);
        balance_b.destroy_zero();
    } else {
        assert!(balance_b.value() == pay_amount, ErrAmountIncorrect);
        if (ref_fee_amount > 0) {
            partner.receive_ref_fee(balance_b.split(ref_fee_amount));
        };
        pool.coin_b.join(balance_b);
        balance_a.destroy_zero();
    };
}

public fun rewarder_manager<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : &rewarder::RewarderManager {
    &pool.rewarder_manager
}

#[allow(lint(self_transfer))]
public fun set_display<CoinTypeA, CoinTypeB>(
    cfg: &config::GlobalConfig,
    publisher: &package::Publisher,
    name: String,
    description: String,
    image_url: String,
    link: String,
    project_url: String,
    creator: String,
    ctx: &mut TxContext,
) {
    cfg.checked_package_version();
    let mut fields = vector::empty();
    fields.push_back(string::utf8(b"name"));
    fields.push_back(string::utf8(b"coin_a"));
    fields.push_back(string::utf8(b"coin_b"));
    fields.push_back(string::utf8(b"link"));
    fields.push_back(string::utf8(b"image_url"));
    fields.push_back(string::utf8(b"description"));
    fields.push_back(string::utf8(b"project_url"));
    fields.push_back(string::utf8(b"creator"));
    let mut values = vector::empty();
    values.push_back(name);
    values.push_back(string::from_ascii(type_name::into_string(type_name::get<CoinTypeA>())));
    values.push_back(string::from_ascii(type_name::into_string(type_name::get<CoinTypeB>())));
    values.push_back(link);
    values.push_back(image_url);
    values.push_back(description);
    values.push_back(project_url);
    values.push_back(creator);
    let mut disp = display::new_with_fields<Pool<CoinTypeA, CoinTypeB>>(publisher, fields, values, ctx);
    disp.update_version();
    transfer::public_transfer(disp, ctx.sender());
}

public fun step_swap_result_amount_in(result: &SwapStepResult) : u64 {
    result.amount_in
}

public fun step_swap_result_amount_out(result: &SwapStepResult) : u64 {
    result.amount_out
}

public fun step_swap_result_current_liquidity(result: &SwapStepResult) : u128 {
    result.current_liquidity
}

public fun step_swap_result_current_sqrt_price(result: &SwapStepResult) : u128 {
    result.current_sqrt_price
}

public fun step_swap_result_fee_amount(result: &SwapStepResult) : u64 {
    result.fee_amount
}

public fun step_swap_result_remainder_amount(result: &SwapStepResult) : u64 {
    result.remainder_amount
}

public fun step_swap_result_target_sqrt_price(result: &SwapStepResult) : u128 {
    result.target_sqrt_price
}

fun swap_in_pool<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    a2b: bool,
    by_amount_in: bool,
    target_price: u128,
    amount: u64,
    unstaked_liquidity_fee_rate: u64,
    protocol_fee_rate: u64,
    protocol_ref_fee_rate: u64,
    clock: &clock::Clock,
): SwapResult {
    assert!(protocol_ref_fee_rate <= 10000, ErrInvalidProtocolRefFeeRate);
    let mut swap_result = default_swap_result();
    let mut amount_remaining = amount;
    let mut maybe_score = tick::first_score_for_swap(&pool.tick_manager, pool.current_tick_index, a2b);

    // either specified amount been fulfilled or specified target price been reached will terminate the SWAP
    while (amount_remaining > 0 && pool.current_sqrt_price != target_price) {
        if (maybe_score.is_none()) {
            abort ErrNoTickForSwap
        };
        let (tick, next_score) = pool.tick_manager.borrow_tick_for_swap(maybe_score.borrow(), a2b);
        maybe_score = next_score;
        let tick_index = tick.index();
        let tick_price = tick.sqrt_price();
        let price_boundry = if (a2b) {
            math_u128::max(target_price, tick_price)
        } else {
            math_u128::min(target_price, tick_price)
        };
        // one step ahead: make the price slides towards price_boundry meanwhile take remaining amount into account
        let (step_amount_in, step_amount_out, step_landing_sqrt_price, step_fee_amount) = clmm_math::compute_swap_step(pool.current_sqrt_price, price_boundry, pool.liquidity, amount_remaining, pool.fee_rate, a2b, by_amount_in);
        if (step_amount_in != 0 || step_fee_amount != 0) {
            if (by_amount_in) {
                amount_remaining = check_remainer_amount_sub(check_remainer_amount_sub(amount_remaining, step_amount_in), step_fee_amount);
            } else {
                // amount remaining doesn't care about fees when we are doing swap based on amount_out
                amount_remaining = check_remainer_amount_sub(amount_remaining, step_amount_out);
            };

            let step_partner_share = full_math_u64::mul_div_ceil(step_fee_amount, protocol_ref_fee_rate, config::protocol_fee_rate_denom());
            let mut net_step_fee_amount = step_fee_amount - step_partner_share;
            let mut magma_fee_amount = 0;
            let mut step_protocol_share = 0;
            if (net_step_fee_amount > 0) {
                step_protocol_share = full_math_u64::mul_div_ceil(net_step_fee_amount, protocol_fee_rate, config::protocol_fee_rate_denom());
                net_step_fee_amount = net_step_fee_amount - step_protocol_share;
                if (net_step_fee_amount > 0) {
                    (_, magma_fee_amount) = calculate_fees(pool, net_step_fee_amount, pool.liquidity, pool.magma_distribution_staked_liquidity, unstaked_liquidity_fee_rate);
                    net_step_fee_amount = net_step_fee_amount - magma_fee_amount;
                };
            };
            swap_result.update_swap_result(step_amount_in, step_amount_out, step_fee_amount, step_protocol_share, step_partner_share, magma_fee_amount);
            if (net_step_fee_amount > 0) {
                pool.update_fee_growth_global(net_step_fee_amount, a2b);
            };

            // XXX: magma
            // let (_, magma_fee_amount) = calculate_fees(pool, step_fee_amount, pool.liquidity, pool.magma_distribution_staked_liquidity, unstaked_liquidity_fee_rate);
            // let step_unstaked_fee_amount = step_fee_amount - magma_fee_amount;
            // gauger_fee = gauger_fee + magma_fee_amount;
            // swap_result.update_swap_result(step_amount_in, step_amount_out, step_fee_amount, magma_fee_amount);
            // protocol_fee = protocol_fee + pool.update_pool_fee(step_unstaked_fee_amount, protocol_fee_rate, a2b);
        };
        if (step_landing_sqrt_price == tick_price) {
            pool.current_sqrt_price = price_boundry;
            pool.current_tick_index = if (a2b) {
                i32::sub(tick_index, i32::from(1))
            } else {
                tick_index
            };

            pool.update_magma_distribution_growth_global_internal(clock);

            let (pool_liquidity, pool_magma_distribution_staked_liquidity) = tick::cross_by_swap(
                &mut pool.tick_manager,
                tick_index,
                a2b,
                pool.liquidity,
                pool.magma_distribution_staked_liquidity,
                pool.fee_growth_global_a,
                pool.fee_growth_global_b,
                pool.rewarder_manager.points_growth_global(),
                pool.rewarder_manager.rewards_growth_global(),
                pool.magma_distribution_growth_global,
            );
            pool.liquidity = pool_liquidity;
            pool.magma_distribution_staked_liquidity = pool_magma_distribution_staked_liquidity;
            continue
        };
        if (pool.current_sqrt_price != step_landing_sqrt_price) {
            pool.current_sqrt_price = step_landing_sqrt_price;
            pool.current_tick_index = tick_math::get_tick_at_sqrt_price(step_landing_sqrt_price);
            continue
        };
    };
    if (a2b) {
        pool.fee_protocol_coin_a = pool.fee_protocol_coin_a + swap_result.protocol_fee_amount;
        pool.magma_distribution_gauger_fee.coin_a = pool.magma_distribution_gauger_fee.coin_a + swap_result.gauge_fee_amount;
    } else {
        pool.fee_protocol_coin_b = pool.fee_protocol_coin_b + swap_result.protocol_fee_amount;
        pool.magma_distribution_gauger_fee.coin_b = pool.magma_distribution_gauger_fee.coin_b + swap_result.gauge_fee_amount;
    };
    swap_result
}

public fun swap_pay_amount<CoinTypeA, CoinTypeB>(flash_swap_receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>) : u64 {
    flash_swap_receipt.pay_amount
}

public fun tick_manager<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : &tick::TickManager {
    &pool.tick_manager
}

public fun tick_spacing<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>) : u32 {
    pool.tick_spacing
}

public fun unpause<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, ctx: &mut TxContext) {
    cfg.checked_package_version();
    cfg.check_pool_manager_role(ctx.sender());
    assert!(pool.is_pause);
    pool.is_pause = false;
}

public fun update_unstaked_liquidity_fee_rate<A, B>(cfg: &config::GlobalConfig, pool: &mut Pool<A, B>, fee_rate: u64, ctx: &mut TxContext) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    assert!(fee_rate == config::default_unstaked_fee_rate() || fee_rate <= config::max_unstaked_liquidity_fee_rate(), ErrInvalidFeeRate);
    assert!(fee_rate != pool.unstaked_liquidity_fee_rate, ErrInvalidFeeRate);
    cfg.check_pool_manager_role(ctx.sender());
    let old_fee_rate = pool.unstaked_liquidity_fee_rate;
    pool.unstaked_liquidity_fee_rate = fee_rate;
    event::emit(UpdateUnstakedLiquidityFeeRateEvent{pool: object::id(pool), old_fee_rate, new_fee_rate: fee_rate });
}

public fun update_fee_rate<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, new_fee_rate: u64, ctx: &mut TxContext) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    if (new_fee_rate > config::max_fee_rate()) {
        abort ErrInvalidFeeRate
    };
    cfg.check_pool_manager_role(ctx.sender());
    let old_fee_rate = pool.fee_rate;
    pool.fee_rate = new_fee_rate;
    event::emit(UpdateFeeRateEvent{pool: object::id(pool), old_fee_rate, new_fee_rate});
}

fun update_fee_growth_global<A, B>(self: &mut Pool<A, B>, fee_amount: u64, a2b: bool) {
    if (fee_amount == 0 || self.liquidity == 0) {
        return
    };
    if (a2b) {
        self.fee_growth_global_a = math_u128::wrapping_add(self.fee_growth_global_a, ((fee_amount as u128) << 64) / self.liquidity);
    } else {
        self.fee_growth_global_b = math_u128::wrapping_add(self.fee_growth_global_b, ((fee_amount as u128) << 64) / self.liquidity);
    };
}

// fun update_pool_fee<CoinTypeA, CoinTypeB>(
//     pool: &mut Pool<CoinTypeA, CoinTypeB>,
//     amount: u64,
//     protocol_fee_rate: u64,
//     a2b: bool
// ): u64 {
//     let protocol_share = full_math_u64::mul_div_ceil(amount, protocol_fee_rate, 10000);
//     let pool_share = amount - protocol_share;
//     if (pool_share == 0 || pool.liquidity == 0) {
//         return protocol_share
//     };
//     if (a2b) {
//         pool.fee_growth_global_a = math_u128::wrapping_add(pool.fee_growth_global_a, ((pool_share as u128) << 64) / pool.liquidity);
//     } else {
//         pool.fee_growth_global_b = math_u128::wrapping_add(pool.fee_growth_global_b, ((pool_share as u128) << 64) / pool.liquidity);
//     };
//     protocol_share
// }

public fun update_pool_url<CoinTypeA, CoinTypeB>(cfg: &config::GlobalConfig, pool: &mut Pool<CoinTypeA, CoinTypeB>, url: String, ctx: &mut TxContext) {
    cfg.checked_package_version();
    assert!(!pool.is_pause, ErrPoolPaused);
    cfg.check_pool_manager_role(ctx.sender());
    pool.url = url;
}

// fee_amount is the total amount covering all kinds of fees
fun update_swap_result(swap_result: &mut SwapResult, amount_in: u64, amount_out: u64, fee_amount: u64, protocol_fee_amount: u64, ref_fee_amount: u64, gauge_fee_amount: u64) {
    assert!(math_u64::add_check(swap_result.amount_in, amount_in), ErrSwapAmountInOverflow);
    assert!(math_u64::add_check(swap_result.amount_out, amount_out), ErrSwapAmountOutOverflow);
    assert!(math_u64::add_check(swap_result.fee_amount, fee_amount), ErrFeeAmountOverflow);
    swap_result.amount_in = swap_result.amount_in + amount_in;
    swap_result.amount_out = swap_result.amount_out + amount_out;
    swap_result.fee_amount = swap_result.fee_amount + fee_amount;
    swap_result.protocol_fee_amount = swap_result.protocol_fee_amount + protocol_fee_amount;
    swap_result.gauge_fee_amount = swap_result.gauge_fee_amount + gauge_fee_amount;
    swap_result.ref_fee_amount = swap_result.ref_fee_amount + ref_fee_amount;
    swap_result.steps = swap_result.steps + 1;
}

public fun url<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): String {
    pool.url
}


// (fee_growth_global: u128, staked_fee_amount: u128)
fun calculate_fees<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    fee_amount: u64,
    liquidity: u128,
    staked_liquidity: u128,
    unstaked_liquidity_fee_rate: u64,
): (u128, u64) {
    // if there is only staked liquidity
    if (liquidity == pool.magma_distribution_staked_liquidity) {
        (0, fee_amount)
    }
    // if there is only unstaked liquidity
    else if (staked_liquidity == 0) {
        let (unstaked_fee_amount, staked_fee_amount) = apply_unstaked_fees(fee_amount as u128, 0, unstaked_liquidity_fee_rate);
        let fee_growth_global = full_math_u128::mul_div_floor(unstaked_fee_amount, Q64, liquidity);
        (fee_growth_global, staked_fee_amount as u64)
    }
    // if there are staked and unstaked liquidities
    else {
        let (unstaked_fee_amount, staked_fee_amount) = split_fees(fee_amount, liquidity, staked_liquidity, unstaked_liquidity_fee_rate);
        let fee_growth_global = full_math_u128::mul_div_floor(unstaked_fee_amount as u128, Q64, liquidity - staked_liquidity);
        (fee_growth_global, staked_fee_amount)
    }
}

fun split_fees(fee_amount: u64, liquidity: u128, staked_liquidity: u128, unstaked_liquidity_fee_rate: u64): (u64, u64) {
    let staked_fee_amount = full_math_u128::mul_div_ceil(fee_amount as u128, staked_liquidity, liquidity);
    let (unstaked, staked) = apply_unstaked_fees(fee_amount as u128 - staked_fee_amount, staked_fee_amount, unstaked_liquidity_fee_rate);
    (unstaked as u64, staked as u64)
}

fun apply_unstaked_fees(unstaked_fee_amount: u128, staked_fee_amount: u128, unstaked_liquidity_fee_rate: u64): (u128, u128) {
    let shift_fee = full_math_u128::mul_div_ceil(unstaked_fee_amount, unstaked_liquidity_fee_rate as u128, 10000);
    (unstaked_fee_amount - shift_fee, staked_fee_amount + shift_fee)
}


/// @dev timeDelta != 0 handles case when function is called twice in the same block.
/// @dev stakedLiquidity > 0 handles case when depositing staked liquidity and there is no liquidity staked yet,
/// @dev or when notifying rewards when there is no liquidity stake
fun update_magma_distribution_growth_global_internal<CoinTypeA, CoinTypeB>(pool: &mut Pool<CoinTypeA, CoinTypeB>, clock: &clock::Clock): u64 {
    let now = clock.timestamp_ms() / 1000;
    let elapsed = now - pool.magma_distribution_last_updated; // skip if second call in same block
    let mut ret = 0;
    if (elapsed != 0) {
        if (pool.magma_distribution_reserve > 0) {
            // there is no meaning to upscale reward_amount to u128 if it is restricted by reserve which is u64
            let mut reward_amount = full_math_u128::mul_div_floor(pool.magma_distribution_rate, elapsed as u128, Q64) as u64;
            if (reward_amount > pool.magma_distribution_reserve) {
                reward_amount = pool.magma_distribution_reserve;
            };
            pool.magma_distribution_reserve = pool.magma_distribution_reserve - reward_amount;
            if (pool.magma_distribution_staked_liquidity > 0) {
                pool.magma_distribution_growth_global = pool.magma_distribution_growth_global + full_math_u128::mul_div_floor(reward_amount as u128, Q64, pool.magma_distribution_staked_liquidity);
            } else {
                pool.magma_distribution_rollover = pool.magma_distribution_rollover + reward_amount;
            };
            ret = reward_amount
        };
        pool.magma_distribution_last_updated = now;
    };

    ret
}

fun check_tick_range(tick_lower: I32, tick_upper: I32): bool {
    if (i32::gte(tick_lower, tick_upper) || i32::lt(tick_lower, tick_math::min_tick()) || i32::gt(tick_upper, tick_math::max_tick())) {
        return false
    };
    true
}

public fun get_magma_distribution_growth_inside<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, tick_lower_index: I32, tick_upper_index: I32, mut global_growth: u128): u128 {
    assert!(check_tick_range(tick_lower_index, tick_upper_index));
    if (global_growth == 0) {
        global_growth = pool.magma_distribution_growth_global;
    };
    tick::get_magma_distribution_growth_in_range(pool.current_tick_index, global_growth, option::some(*pool.borrow_tick(tick_lower_index)), option::some(*pool.borrow_tick(tick_upper_index)))
}



public fun get_magma_distribution_last_updated<A, B>(pool: &Pool<A, B>): u64 {
    pool.magma_distribution_last_updated
}

public fun get_magma_distribution_growth_global<A, B>(pool: &Pool<A, B>): u128 {
    pool.magma_distribution_growth_global
}

public fun get_magma_distribution_reserve<A, B>(pool: &Pool<A, B>): u64 {
    pool.magma_distribution_reserve
}

public fun get_magma_distribution_staked_liquidity<A, B>(pool: &Pool<A, B>): u128 {
    pool.magma_distribution_staked_liquidity
}

public fun get_magma_distribution_gauger_id<A, B>(pool: &Pool<A, B>): ID {
    assert!(pool.magma_distribution_gauger_id.is_some());
    *pool.magma_distribution_gauger_id.borrow()
}

public fun get_magma_distribution_rollover<A, B>(pool: &Pool<A, B>): u64 {
    pool.magma_distribution_rollover
}




#[test_only]
/// Test-only accessor for rewarder_manager
public fun borrow_rewarder_manager_test<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): &rewarder::RewarderManager {
    &pool.rewarder_manager
}

#[test_only]
/// Test-only accessor for rewarder_manager mut reference
public fun borrow_rewarder_manager_mut_test<CoinTypeA, CoinTypeB>(pool: &mut Pool<CoinTypeA, CoinTypeB>): &mut rewarder::RewarderManager {
    &mut pool.rewarder_manager
}
