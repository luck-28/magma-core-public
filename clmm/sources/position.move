#[allow(unused_const)]

module magma_clmm::position;

use std::type_name;
use std::string::{Self, String};

use sui::package;
use sui::display;
use sui::event;

use move_stl::linked_table;

use integer_mate::{i32::{Self, I32}, math_u64, math_u128, full_math_u128};

use magma_clmm::config;
use magma_clmm::utils;
use magma_clmm::tick_math;

const ErrRemainderAmountUnderflow: u64 = 1;
const ErrFeeOwnedOverflow: u64 = 2;
const ErrPointsOwnedOverflow: u64 = 3;
const ErrInvalidDeltaLiquidity: u64 = 4;
const ErrInvalidPositionTickRange: u64 = 5;
const ErrPositionNotExists: u64 = 6;
const ErrPositionIsNotEmpty: u64 = 7;
const ErrLiquidityChangeOverflow: u64 = 8;
const ErrLiquidityChangeUnderflow: u64 = 9;
const ErrInvalidRewardIndex: u64 = 10;
const ErrPositionStaked: u64 = 11;

public struct StakePositionEvent has copy, drop {
    position_id: ID,
    staked: bool,
}

public struct PositionManager has store {
    tick_spacing: u32,
    position_index: u64,
    positions: linked_table::LinkedTable<ID, PositionInfo>,
}

public struct POSITION has drop {}

public struct Position has store, key {
    id: UID,
    pool: ID,
    index: u64,
    coin_type_a: type_name::TypeName,
    coin_type_b: type_name::TypeName,
    name: String,
    description: String,
    url: String,
    tick_lower_index: I32,
    tick_upper_index: I32,
    liquidity: u128,
}

public struct PositionInfo has copy, drop, store {
    position_id: ID,
    liquidity: u128,
    tick_lower_index: I32,
    tick_upper_index: I32,
    fee_growth_inside_a: u128,
    fee_growth_inside_b: u128,
    fee_owned_a: u64,
    fee_owned_b: u64,
    points_owned: u128,
    points_growth_inside: u128,
    rewards: vector<PositionReward>,
    magma_distribution_staked: bool,
    magma_distribution_growth_inside: u128,
    magma_distribution_owned: u64,
}

public struct PositionReward has copy, drop, store {
    growth_inside: u128,
    amount_owned: u64,
}

public fun is_empty(position_info: &PositionInfo): bool {
    let mut is_rewards_clean = true;
    let mut idx = 0;
    while (idx < position_info.rewards.length()) {
        is_rewards_clean = position_info.rewards.borrow(idx).amount_owned == 0;
        if (!is_rewards_clean) {
            break
        };
        idx = idx + 1;
    };
    let is_position_clean = position_info.liquidity == 0 && position_info.fee_owned_a == 0 && position_info.fee_owned_b == 0;
    is_position_clean && is_rewards_clean
}

public(package) fun new(tick_spacing: u32, ctx: &mut TxContext): PositionManager {
    PositionManager{
        tick_spacing,
        position_index: 0,
        positions: linked_table::new<ID, PositionInfo>(ctx),
    }
}

fun borrow_mut_position_info(position_manager: &mut PositionManager, position_id: ID): &mut PositionInfo {
    assert!(position_manager.positions.contains(position_id), ErrPositionNotExists);
    let position_info = position_manager.positions.borrow_mut(position_id);
    assert!(position_info.position_id == position_id, ErrPositionNotExists);
    position_info
}

public fun borrow_position_info(position_manager: &PositionManager, position_id: ID): &PositionInfo {
    assert!(position_manager.positions.contains(position_id), ErrPositionNotExists);
    let position_info = position_manager.positions.borrow(position_id);
    assert!(position_info.position_id == position_id, ErrPositionNotExists);
    position_info
}

public fun check_position_tick_range(tick_lower_index: I32, tick_upper_index: I32, tick_spacing: u32) {
    assert!(
        i32::lt(tick_lower_index, tick_upper_index)
        && i32::gte(tick_lower_index, tick_math::min_tick())
        && i32::lte(tick_upper_index, tick_math::max_tick())
        && i32::mod(tick_lower_index, i32::from(tick_spacing)) == i32::zero()
        && i32::mod(tick_upper_index, i32::from(tick_spacing)) == i32::zero(), ErrInvalidPositionTickRange);
}

public(package) fun close_position(position_manager: &mut PositionManager, position: Position) {
    let position_id = object::id(&position);
    if (!is_empty(position_manager.borrow_mut_position_info(position_id))) {
        abort ErrPositionIsNotEmpty
    };
    position_manager.positions.remove(position_id);
    destroy(position);
}

public(package) fun decrease_liquidity(
    position_manager: &mut PositionManager,
    position: &mut Position,
    liquidity: u128,
    fee_growth_a: u128,
    fee_growth_b: u128,
    points_growth: u128,
    rewards_growth: vector<u128>,
    magma_distribution_growth: u128,
): u128 {
    let position_info = position_manager.borrow_mut_position_info(object::id(position));
    if (liquidity == 0) {
        return position_info.liquidity
    };
    position_info.update_fee_internal(fee_growth_a, fee_growth_b);
    position_info.update_points_internal(points_growth);
    position_info.update_rewards_internal(rewards_growth);
    position_info.update_magma_distribution_internal(magma_distribution_growth);
    assert!(position_info.liquidity >= liquidity, ErrLiquidityChangeUnderflow);
    position_info.liquidity = position_info.liquidity - liquidity;
    position.liquidity = position_info.liquidity;
    position_info.liquidity
}

public fun description(position: &Position): String {
    position.description
}

fun destroy(position: Position) {
    let Position {
        id              : position_id,
        pool            : _,
        index           : _,
        coin_type_a     : _,
        coin_type_b     : _,
        name            : _,
        description     : _,
        url             : _,
        tick_lower_index: _,
        tick_upper_index: _,
        liquidity       : _,
    } = position;
    object::delete(position_id);
}

public fun fetch_positions(position_manager: &PositionManager, start: vector<ID>, limit: u64): vector<PositionInfo> {
    let mut ret = vector::empty<PositionInfo>();
    let mut maybe_key = if (start.is_empty()) {
        linked_table::head<ID, PositionInfo>(&position_manager.positions)
    } else {
        option::some(start[0])
        // linked_table::next<ID, PositionInfo>(position_manager.positions.borrow_node(*start.borrow(0)))
    };
    let mut cnt = 0;
    while (maybe_key.is_some()) {
        let node = position_manager.positions.borrow_node(*maybe_key.borrow());
        maybe_key = linked_table::next(node);
        ret.push_back(*node.borrow_value());
        cnt = cnt + 1;
        if (cnt == limit) {
            break
        };
    };
    ret
}

public(package) fun increase_liquidity(
    position_manager: &mut PositionManager,
    position: &mut Position,
    liquidity: u128,
    fee_growth_inside_a: u128,
    fee_growth_inside_b: u128,
    points_growth_inside: u128,
    rewards: vector<u128>,
    magma_distribution_growth_inside: u128,
): u128 {
    let position_info = position_manager.borrow_mut_position_info(object::id(position));
    position_info.update_fee_internal(fee_growth_inside_a, fee_growth_inside_b);
    position_info.update_points_internal(points_growth_inside);
    position_info.update_rewards_internal(rewards);
    position_info.update_magma_distribution_internal(magma_distribution_growth_inside);
    assert!(math_u128::add_check(position_info.liquidity, liquidity), ErrLiquidityChangeOverflow);
    position_info.liquidity = position_info.liquidity + liquidity;
    position.liquidity = position_info.liquidity;
    position_info.liquidity
}

public fun index(position: &Position): u64 {
    position.index
}

public fun info_fee_growth_inside(position_info: &PositionInfo): (u128, u128) {
    (position_info.fee_growth_inside_a, position_info.fee_growth_inside_b)
}

public fun info_fee_owned(position_info: &PositionInfo): (u64, u64) {
    (position_info.fee_owned_a, position_info.fee_owned_b)
}

public fun info_liquidity(position_info: &PositionInfo): u128 {
    position_info.liquidity
}

public fun info_points_growth_inside(position_info: &PositionInfo): u128 {
    position_info.points_growth_inside
}

public fun info_points_owned(position_info: &PositionInfo): u128 {
    position_info.points_owned
}

public fun info_position_id(position_info: &PositionInfo): ID {
    position_info.position_id
}

public fun info_rewards(position_info: &PositionInfo): &vector<PositionReward> {
    &position_info.rewards
}

public fun info_tick_range(position_info: &PositionInfo): (I32, I32) {
    (position_info.tick_lower_index, position_info.tick_upper_index)
}

public fun info_magma_distribution_owned(position_info: &PositionInfo): u64 {
    position_info.magma_distribution_owned
}

fun init(otw: POSITION, ctx: &mut TxContext) {
    let mut fields = vector::empty();
    fields.push_back(string::utf8(b"name"));
    fields.push_back(string::utf8(b"coin_a"));
    fields.push_back(string::utf8(b"coin_b"));
    fields.push_back(string::utf8(b"link"));
    fields.push_back(string::utf8(b"image_url"));
    fields.push_back(string::utf8(b"description"));
    fields.push_back(string::utf8(b"website"));
    fields.push_back(string::utf8(b"creator"));
    let mut values = vector::empty();
    values.push_back(string::utf8(b"{name}"));
    values.push_back(string::utf8(b"{coin_type_a}"));
    values.push_back(string::utf8(b"{coin_type_b}"));
    values.push_back(string::utf8(b"https://app.magmafinance.io/position?chain=sui&id={id}"));
    values.push_back(string::utf8(b"{url}"));
    values.push_back(string::utf8(b"{description}"));
    values.push_back(string::utf8(b"https://magmafinance.io"));
    values.push_back(string::utf8(b"MAGMA"));
    let publisher = package::claim<POSITION>(otw, ctx);
    let mut disp = display::new_with_fields<Position>(&publisher, fields, values, ctx);
    disp.update_version();
    transfer::public_transfer(disp, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}

public fun inited_rewards_count(position_manager: &PositionManager, position_id: ID): u64 {
    position_manager.positions.borrow(position_id).rewards.length()
}

public fun is_position_exist(position_manager: &PositionManager, position_id: ID): bool {
    position_manager.positions.contains(position_id)
}

public fun liquidity(position: &Position): u128 {
    position.liquidity
}

public fun name(position: &Position): String {
    position.name
}

fun new_position_name(pool_index: u64, position_index: u64): String {
    let mut name = string::utf8(b"Magma position | Pool");
    name.append(utils::str(pool_index));
    name.append_utf8(b"-");
    name.append(utils::str(position_index));
    name
}

public(package) fun open_position<CoinTypeA, CoinTypeB>(
    position_manager: &mut PositionManager,
    pool_id: ID,
    pool_index: u64,
    url: String,
    tick_lower_index: I32,
    tick_upper_index: I32,
    ctx: &mut TxContext): Position {
    check_position_tick_range(tick_lower_index, tick_upper_index, position_manager.tick_spacing);
    let position_index = position_manager.position_index + 1;
    let position = Position{
        id: object::new(ctx),
        pool: pool_id,
        index: position_index,
        coin_type_a: type_name::get<CoinTypeA>(),
        coin_type_b: type_name::get<CoinTypeB>(),
        name: new_position_name(pool_index, position_index),
        description: string::utf8(b"Magma Liquidity Position"),
        url: url,
        tick_lower_index: tick_lower_index,
        tick_upper_index: tick_upper_index,
        liquidity: 0,
    };
    let position_id = object::id(&position);
    let position_info = PositionInfo{
        position_id: position_id,
        liquidity: 0,
        tick_lower_index: tick_lower_index,
        tick_upper_index: tick_upper_index,
        fee_growth_inside_a: 0,
        fee_growth_inside_b: 0,
        fee_owned_a: 0,
        fee_owned_b: 0,
        points_owned: 0,
        points_growth_inside: 0,
        rewards: vector::empty(),
        magma_distribution_staked: false,
        magma_distribution_owned: 0,
        magma_distribution_growth_inside: 0,
    };
    position_manager.positions.push_back(position_id, position_info);
    position_manager.position_index = position_index;
    position
}

public fun pool_id(position: &Position): ID {
    position.pool
}

public fun set_description(position: &mut Position, desc: String) {
    position.description = desc;
}

public(package) fun mark_position_staked(position_manager: &mut PositionManager, position_id: ID, staked: bool) {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    assert!(position_info.magma_distribution_staked != staked, ErrPositionStaked);
    position_info.magma_distribution_staked = staked;
    event::emit(StakePositionEvent{
        position_id: position_info.position_id,
        staked,
    });
}

public(package) fun reset_fee(position_manager: &mut PositionManager, position_id: ID): (u64, u64) {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    let fee_owned_a = position_info.fee_owned_a;
    let fee_owned_b = position_info.fee_owned_b;
    position_info.fee_owned_a = 0;
    position_info.fee_owned_b = 0;
    (fee_owned_a, fee_owned_b)
}

public(package) fun reset_rewarder(position_manager: &mut PositionManager, position_id: ID, reward_idx: u64): u64 {
    let rewarder = position_manager.borrow_mut_position_info(position_id).rewards.borrow_mut(reward_idx);
    let amount_owned = rewarder.amount_owned;
    rewarder.amount_owned = 0;
    amount_owned
}

public fun reward_amount_owned(position_reward: &PositionReward): u64 {
    position_reward.amount_owned
}

public fun reward_growth_inside(position_reward: &PositionReward): u128 {
    position_reward.growth_inside
}

public(package) fun rewards_amount_owned(position_manager: &PositionManager, position_id: ID): vector<u64> {
    let rewards = position_manager.borrow_position_info(position_id).info_rewards();
    let mut i = 0;
    let mut ret = vector::empty();
    while (i < rewards.length()) {
        ret.push_back(rewards.borrow(i).reward_amount_owned());
        i = i + 1;
    };
    ret
}

#[allow(lint(self_transfer))]
public fun set_display(
    cfg: &config::GlobalConfig,
    publisher: &package::Publisher,
    description: String,
    link: String,
    project_url: String,
    creator: String,
    ctx: &mut TxContext
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
    values.push_back(string::utf8(b"{name}"));
    values.push_back(string::utf8(b"{coin_type_a}"));
    values.push_back(string::utf8(b"{coin_type_b}"));
    values.push_back(link);
    values.push_back(string::utf8(b"{url}"));
    values.push_back(description);
    values.push_back(project_url);
    values.push_back(creator);
    let mut disp = display::new_with_fields<Position>(publisher, fields, values, ctx);
    disp.update_version();
    transfer::public_transfer(disp, ctx.sender());
}

public fun tick_range(position: &Position): (I32, I32) {
    (position.tick_lower_index, position.tick_upper_index)
}

public(package) fun update_and_reset_fee(
    position_manager: &mut PositionManager,
    position_id: ID,
    fee_growth_inside_a: u128,
    fee_growth_inside_b: u128
): (u64, u64) {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_fee_internal(fee_growth_inside_a, fee_growth_inside_b);
    let fee_owned_a = position_info.fee_owned_a;
    let fee_owned_b = position_info.fee_owned_b;
    position_info.fee_owned_a = 0;
    position_info.fee_owned_b = 0;
    (fee_owned_a, fee_owned_b)
}

public(package) fun update_and_reset_rewards(position_manager: &mut PositionManager, position_id: ID, rewards_growth: vector<u128>, reward_id: u64): u64 {
    assert!(rewards_growth.length() > reward_id, ErrInvalidRewardIndex);
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_rewards_internal(rewards_growth);

    let position_reward = position_info.rewards.borrow_mut(reward_id);
    let amount_owned = position_reward.amount_owned;
    position_reward.amount_owned = 0;
    amount_owned
}

public(package) fun update_and_reset_magma_distribution(position_manager: &mut PositionManager, position_id: ID, distribution_growth: u128): u64 {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_magma_distribution_internal(distribution_growth);
    let distribution_owned = position_info.magma_distribution_owned;
    position_info.magma_distribution_owned = 0;
    distribution_owned
}

public(package) fun update_fee(position_manager: &mut PositionManager, position_id: ID, fee_growth_a: u128, fee_growth_b: u128): (u64, u64) {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_fee_internal(fee_growth_a, fee_growth_b);
    position_info.info_fee_owned()
}

fun update_fee_internal(position_info: &mut PositionInfo, fee_growth_a: u128, fee_growth_b: u128) {
    let fee_owned_a = full_math_u128::mul_shr(
        position_info.liquidity,
        math_u128::wrapping_sub(
            fee_growth_a, 
            position_info.fee_growth_inside_a), 
            64) as u64;
    let fee_owned_b = full_math_u128::mul_shr(position_info.liquidity, math_u128::wrapping_sub(fee_growth_b, position_info.fee_growth_inside_b), 64) as u64;
    assert!(math_u64::add_check(position_info.fee_owned_a, fee_owned_a), ErrRemainderAmountUnderflow);
    assert!(math_u64::add_check(position_info.fee_owned_b, fee_owned_b), ErrRemainderAmountUnderflow);
    position_info.fee_owned_a = position_info.fee_owned_a + fee_owned_a;
    position_info.fee_owned_b = position_info.fee_owned_b + fee_owned_b;
    position_info.fee_growth_inside_a = fee_growth_a;
    position_info.fee_growth_inside_b = fee_growth_b;
}

public(package) fun update_points(position_manager: &mut PositionManager, position_id: ID, points_growth: u128): u128 {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_points_internal(points_growth);
    position_info.points_owned
}

fun update_points_internal(position_info: &mut PositionInfo, points_growth: u128) {
    let points = full_math_u128::mul_shr(position_info.liquidity, math_u128::wrapping_sub(points_growth, position_info.points_growth_inside), 64);
    assert!(math_u128::add_check(position_info.points_owned, points), ErrPointsOwnedOverflow);
    position_info.points_owned = position_info.points_owned + points;
    position_info.points_growth_inside = points_growth;
}

public(package) fun update_rewards(position_manager: &mut PositionManager, position_id: ID, rewards: vector<u128>): vector<u64> {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_rewards_internal(rewards);
    let position_rewards = position_info.info_rewards();
    let mut i = 0;
    let mut ret = vector::empty();
    while (i < position_rewards.length()) {
        ret.push_back(position_rewards.borrow(i).reward_amount_owned());
        i = i + 1;
    };
    ret
}

public(package) fun update_magma_distribution(position_manager: &mut PositionManager, position_id: ID, growth: u128): u64 {
    let position_info = position_manager.borrow_mut_position_info(position_id);
    position_info.update_magma_distribution_internal(growth);
    position_info.magma_distribution_owned
}

fun update_magma_distribution_internal(position_info: &mut PositionInfo, growth: u128) {
    let distribution = full_math_u128::mul_shr(position_info.liquidity, math_u128::wrapping_sub(growth, position_info.magma_distribution_growth_inside), 64) as u64;
    assert!(math_u64::add_check(position_info.magma_distribution_owned, distribution));
    position_info.magma_distribution_owned = position_info.magma_distribution_owned + distribution;
    position_info.magma_distribution_growth_inside = growth;
}

fun update_rewards_internal(position_info: &mut PositionInfo, rewards_growth: vector<u128>) {
    let mut i = 0;
    while (i < rewards_growth.length()) {
        let reward_growth = *rewards_growth.borrow(i);
        if (position_info.rewards.length() > i) {
            let position_reward = position_info.rewards.borrow_mut(i);
            let reward_owned = full_math_u128::mul_shr(math_u128::wrapping_sub(reward_growth, position_reward.growth_inside), position_info.liquidity, 64) as u64;
            assert!(math_u64::add_check(position_reward.amount_owned, reward_owned), ErrRemainderAmountUnderflow);
            position_reward.growth_inside = reward_growth;
            position_reward.amount_owned = position_reward.amount_owned + reward_owned;
        } else {
            position_info.rewards.push_back(PositionReward{
                growth_inside: reward_growth,
                amount_owned : full_math_u128::mul_shr(reward_growth, position_info.liquidity, 64) as u64,
            });
        };
        i = i + 1;
    };
}

public fun url(position: &Position): String {
    position.url
}

public fun is_staked(info: &PositionInfo): bool {
    info.magma_distribution_staked
}
