module magma_clmm::rewarder;

use std::type_name;

use sui::bag;
use sui::balance::{Self, Balance};
use sui::event;

use integer_mate::full_math_u128;

use magma_clmm::config;

const ErrSlotIsFull: u64 = 1;
const ErrRewardAlreadyExist: u64 = 2;
const ErrInvalidTime: u64 = 3;
const ErrRewardAmountInsufficient: u64 = 4;
const ErrRewardNotExist: u64 = 5;

const Q64_SCALE: u128 = 18446744073709551616000000;

public struct RewarderManager has store {
    rewarders: vector<Rewarder>,
    points_released: u128,
    points_growth_global: u128,
    last_updated_time: u64,
}

public struct Rewarder has copy, drop, store {
    reward_coin: type_name::TypeName,
    emissions_per_second: u128,
    growth_global: u128,
}

public struct RewarderGlobalVault has store, key {
    id: UID,
    balances: bag::Bag,
}

public struct RewarderInitEvent has copy, drop {
    global_vault_id: ID,
}

public struct DepositEvent has copy, drop, store {
    reward_type: type_name::TypeName,
    deposit_amount: u64,
    after_amount: u64,
}

public struct EmergentWithdrawEvent has copy, drop, store {
    reward_type: type_name::TypeName,
    withdraw_amount: u64,
    after_amount: u64,
}

public(package) fun new(): RewarderManager {
    RewarderManager{
        rewarders: vector::empty<Rewarder>(),
        points_released: 0,
        points_growth_global: 0,
        last_updated_time: 0,
    }
}

public(package) fun add_rewarder<RewardType>(reward_manager: &mut RewarderManager) {
    let maybe_index = reward_manager.rewarder_index<RewardType>();
    assert!(maybe_index.is_none(), ErrRewardAlreadyExist);
    assert!(reward_manager.rewarders.length() <= 2, ErrSlotIsFull);
    reward_manager.rewarders.push_back(Rewarder{
        reward_coin: type_name::get<RewardType>(),
        emissions_per_second: 0,
        growth_global: 0,
    });
}

public fun balance_of<RewardType>(vault: &RewarderGlobalVault): u64 {
    let reward_type = type_name::get<RewardType>();
    if (!vault.balances.contains<type_name::TypeName>(reward_type)) {
        return 0
    };
    vault.balances.borrow<type_name::TypeName, Balance<RewardType>>(reward_type).value()
}

public fun balances(vault: &RewarderGlobalVault): &bag::Bag {
    &vault.balances
}

public(package) fun borrow_mut_rewarder<RewardType>(reward_manager: &mut RewarderManager): &mut Rewarder {
    let mut i = 0;
    let reward_type = type_name::get<RewardType>();
    while (i < reward_manager.rewarders.length()) {
        if (reward_manager.rewarders.borrow(i).reward_coin == reward_type) {
            return reward_manager.rewarders.borrow_mut(i)
        };
        i = i + 1;
    };
    abort ErrRewardNotExist
}

public fun borrow_rewarder<RewardType>(reward_manager: &RewarderManager): &Rewarder {
    let mut i = 0;
    let reward_type = type_name::get<RewardType>();
    while (i < reward_manager.rewarders.length()) {
        if (reward_manager.rewarders.borrow(i).reward_coin == reward_type) {
            return reward_manager.rewarders.borrow(i)
        };
        i = i + 1;
    };
    abort ErrRewardNotExist
}

public fun deposit_reward<RewardType>(cfg: &config::GlobalConfig, vault: &mut RewarderGlobalVault, deposit: Balance<RewardType>): u64 {
    cfg.checked_package_version();
    let reward_type = type_name::get<RewardType>();
    if (!vault.balances.contains(reward_type)) {
        vault.balances.add(reward_type, balance::zero<RewardType>());
    };
    let deposit_amount = deposit.value();
    let after_amount = vault.balances.borrow_mut<type_name::TypeName, Balance<RewardType>>(reward_type).join(deposit);
    event::emit(DepositEvent{
        reward_type,
        deposit_amount,
        after_amount,
    });
    after_amount
}

public fun emergent_withdraw<RewardType>(_admin_cap: &config::AdminCap, cfg: &config::GlobalConfig, vault: &mut RewarderGlobalVault, amount: u64): Balance<RewardType> {
    cfg.checked_package_version();
    event::emit(EmergentWithdrawEvent{
        reward_type: type_name::get<RewardType>(),
        withdraw_amount: amount,
        after_amount: vault.balance_of<RewardType>(),
    });
    vault.withdraw_reward<RewardType>(amount)
}

public fun emissions_per_second(rewarder: &Rewarder): u128 {
    rewarder.emissions_per_second
}

public fun growth_global(rewarder: &Rewarder): u128 {
    rewarder.growth_global
}

fun init(ctx: &mut TxContext) {
    let vault = RewarderGlobalVault{
        id: object::new(ctx),
        balances: bag::new(ctx),
    };
    let vault_id = object::id<RewarderGlobalVault>(&vault);
    transfer::share_object<RewarderGlobalVault>(vault);
    event::emit(RewarderInitEvent{global_vault_id: vault_id});
}

public fun last_update_time(reward_manager: &RewarderManager): u64 {
    reward_manager.last_updated_time
}

public fun points_growth_global(reward_manager: &RewarderManager): u128 {
    reward_manager.points_growth_global
}

public fun points_released(reward_manager: &RewarderManager): u128 {
    reward_manager.points_released
}

public fun reward_coin(reward_manager: &Rewarder): type_name::TypeName {
    reward_manager.reward_coin
}

public fun rewarder_index<RewardType>(reward_manager: &RewarderManager): option::Option<u64> {
    let mut i = 0;
    while (i < reward_manager.rewarders.length()) {
        if (reward_manager.rewarders.borrow(i).reward_coin == type_name::get<RewardType>()) {
            return option::some<u64>(i)
        };
        i = i + 1;
    };
    option::none<u64>()
}

public fun rewarders(reward_manager: &RewarderManager): vector<Rewarder> {
    reward_manager.rewarders
}

public fun rewards_growth_global(reward_manager: &RewarderManager): vector<u128> {
    let mut i = 0;
    let mut ret = vector::empty<u128>();
    while (i < reward_manager.rewarders.length()) {
        ret.push_back(reward_manager.rewarders.borrow(i).growth_global);
        i = i + 1;
    };
    ret
}

// update_time is in seconds
public(package) fun settle(reward_manager: &mut RewarderManager, pool_liquidity: u128, update_time: u64) {
    let last_updated_time = reward_manager.last_updated_time;
    reward_manager.last_updated_time = update_time;
    assert!(last_updated_time <= update_time, ErrInvalidTime);
    if (pool_liquidity == 0 || last_updated_time == update_time) {
        return
    };
    let elapsed = update_time - last_updated_time;
    let mut i = 0;
    while (i < reward_manager.rewarders.length()) {
        let rewarder_growth_global = reward_manager.rewarders.borrow(i).growth_global;
        let rewarder_emissions_per_sec = reward_manager.rewarders.borrow(i).emissions_per_second;
        reward_manager.rewarders.borrow_mut(i).growth_global = rewarder_growth_global + full_math_u128::mul_div_floor(elapsed as u128, rewarder_emissions_per_sec, pool_liquidity);
        i = i + 1;
    };
    reward_manager.points_released = reward_manager.points_released + (elapsed as u128) * Q64_SCALE;
    reward_manager.points_growth_global = reward_manager.points_growth_global + full_math_u128::mul_div_floor(elapsed as u128, Q64_SCALE, pool_liquidity);
}

public(package) fun update_emission<RewardType>(vault: &RewarderGlobalVault, reward_manager: &mut RewarderManager, growth: u128, emissions_per_sec_q64: u128, update_time: u64) {
    reward_manager.settle(growth, update_time);
    if (emissions_per_sec_q64 > 0) {
        let reward_type = type_name::get<RewardType>();
        assert!(vault.balances.contains(reward_type), ErrRewardNotExist);
        assert!((vault.balances.borrow<type_name::TypeName, Balance<RewardType>>(reward_type).value() as u128) << 64 >= 86400 * emissions_per_sec_q64, ErrRewardAmountInsufficient);
    };
    reward_manager.borrow_mut_rewarder<RewardType>().emissions_per_second = emissions_per_sec_q64;
}

public(package) fun withdraw_reward<RewardType>(vault: &mut RewarderGlobalVault, amount: u64): Balance<RewardType> {
    let reward_type = type_name::get<RewardType>();
    vault.balances.borrow_mut<type_name::TypeName, Balance<RewardType>>(reward_type).split(amount)
}

#[test_only]
public fun init_for_test(ctx: &mut TxContext): ID {
    let vault = RewarderGlobalVault{
        id: object::new(ctx),
        balances: bag::new(ctx),
    };
    let vault_id = object::id<RewarderGlobalVault>(&vault);
    transfer::share_object<RewarderGlobalVault>(vault);
    vault_id
}

#[test_only]
public fun test_add_reward_balance<RewardType>(vault: &mut RewarderGlobalVault, balance: Balance<RewardType>) {
    let reward_type = type_name::get<RewardType>();
    vault.balances.add(reward_type, balance);
}
