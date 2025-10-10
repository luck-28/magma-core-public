#[allow(unused_const)]

module magma_clmm::partner;

use std::string::{Self, String};
use std::type_name;

use sui::vec_map;
use sui::bag;
use sui::balance::Balance;
use sui::coin;
use sui::event;
use sui::clock;

use magma_clmm::config;

const ErrPartnerAlreadyExist: u64 = 1;
const ErrInvalidPartnerRefFeeRate: u64 = 2;
const ErrInvalidPartnerCap: u64 = 3;
const ErrInvalidCoinType: u64 = 4;
const ErrInvalidPartnerName: u64 = 5;
const ErrInvalidEndTime: u64 = 6;
const ErrInvalidStartTime: u64 = 7;


public struct Partners has key {
    id: UID,
    partners: vec_map::VecMap<String, ID>,
}

public struct PartnerCap has store, key {
    id: UID,
    name: String,
    partner_id: ID,
}

public struct Partner has store, key {
    id: UID,
    name: String,
    ref_fee_rate: u64,
    start_time: u64,
    end_time: u64,
    balances: bag::Bag,
}

public struct InitPartnerEvent has copy, drop {
    partners_id: ID,
}

public struct CreatePartnerEvent has copy, drop {
    recipient: address,
    partner_id: ID,
    partner_cap_id: ID,
    ref_fee_rate: u64,
    name: String,
    start_time: u64,
    end_time: u64,
}

public struct UpdateRefFeeRateEvent has copy, drop {
    partner_id: ID,
    old_fee_rate: u64,
    new_fee_rate: u64,
}

public struct UpdateTimeRangeEvent has copy, drop {
    partner_id: ID,
    start_time: u64,
    end_time: u64,
}

public struct ReceiveRefFeeEvent has copy, drop {
    partner_id: ID,
    amount: u64,
    type_name: String,
}

public struct ClaimRefFeeEvent has copy, drop {
    partner_id: ID,
    amount: u64,
    type_name: String,
}

public fun balances(partner: &Partner): &bag::Bag {
    &partner.balances
}

#[allow(lint(self_transfer))]
public fun claim_ref_fee<FeeType>(cfg: &config::GlobalConfig, partner_cap: &PartnerCap, partner: &mut Partner, ctx: &mut TxContext) {
    cfg.checked_package_version();
    assert!(partner_cap.partner_id == object::id(partner), ErrInvalidPartnerCap);
    let tn = string::from_ascii(type_name::into_string(type_name::get<FeeType>()));
    assert!(partner.balances.contains<String>(tn), ErrInvalidCoinType);
    let balance = partner.balances.remove<String, Balance<FeeType>>(tn);
    let amount = balance.value();
    transfer::public_transfer(coin::from_balance(balance, ctx), ctx.sender());
    event::emit(ClaimRefFeeEvent{
        partner_id: object::id(partner),
        amount,
        type_name: tn,
    });
}

public fun create_partner(
    cfg: &config::GlobalConfig,
    partners: &mut Partners,
    name: String,
    ref_fee_rate: u64,
    start_time: u64,
    end_time: u64,
    recipient: address,
    clock: &clock::Clock,
    ctx: &mut TxContext) {
    assert!(end_time > start_time, ErrInvalidEndTime);
    assert!(start_time >= clock.timestamp_ms() / 1000, ErrInvalidStartTime);
    assert!(ref_fee_rate < 10000, ErrInvalidPartnerRefFeeRate);
    assert!(!name.is_empty(), ErrInvalidPartnerName);
    assert!(!partners.partners.contains(&name), ErrInvalidPartnerName);
    cfg.checked_package_version();
    cfg.check_partner_manager_role(ctx.sender());
    let new_partner = Partner{
        id: object::new(ctx),
        name: name,
        ref_fee_rate: ref_fee_rate,
        start_time: start_time,
        end_time: end_time,
        balances: bag::new(ctx),
    };
    let new_partner_id = object::id(&new_partner);
    let new_partner_cap = PartnerCap{
        id: object::new(ctx),
        name: name,
        partner_id: new_partner_id,
    };
    partners.partners.insert(name, new_partner_id);
    transfer::share_object(new_partner);
    let new_partner_cap_id = object::id(&new_partner_cap);
    transfer::transfer(new_partner_cap, recipient);
    event::emit(CreatePartnerEvent{
        recipient: recipient,
        partner_id: new_partner_id,
        partner_cap_id: new_partner_cap_id,
        ref_fee_rate: ref_fee_rate,
        name: name,
        start_time: start_time,
        end_time: end_time,
    });
}

public fun current_ref_fee_rate(partner: &Partner, now: u64): u64 {
    if (partner.start_time > now || partner.end_time <= now) {
        return 0
    };
    partner.ref_fee_rate
}

public fun end_time(partner: &Partner): u64 {
    partner.end_time
}

fun init(ctx: &mut TxContext) {
    let partners = Partners{
        id: object::new(ctx),
        partners: vec_map::empty<String, ID>(),
    };
    let partners_id = object::id(&partners);
    transfer::share_object(partners);
    event::emit(InitPartnerEvent{partners_id});
}

public fun name(partner: &Partner): String {
    partner.name
}

public fun receive_ref_fee<CoinType>(partner: &mut Partner, fee: Balance<CoinType>) {
    let coin_type = string::from_ascii(type_name::into_string(type_name::get<CoinType>()));
    let amount = fee.value();
    if (partner.balances.contains(coin_type)) {
        partner.balances.borrow_mut<String, Balance<CoinType>>(coin_type).join(fee);
    } else {
        partner.balances.add<String, Balance<CoinType>>(coin_type, fee);
    };
    event::emit(ReceiveRefFeeEvent{
        partner_id: object::id(partner),
        amount,
        type_name: coin_type,
    });
}

public fun ref_fee_rate(partner: &Partner): u64 {
    partner.ref_fee_rate
}

public fun start_time(partner: &Partner): u64 {
    partner.start_time
}

public fun update_ref_fee_rate(cfg: &config::GlobalConfig, partner: &mut Partner, fee_rate: u64, ctx: &mut TxContext) {
    assert!(fee_rate < 10000, ErrInvalidPartnerRefFeeRate);
    cfg.checked_package_version();
    cfg.check_partner_manager_role(ctx.sender());
    let old_fee_rate = partner.ref_fee_rate;
    partner.ref_fee_rate = fee_rate;
    event::emit(UpdateRefFeeRateEvent{
        partner_id: object::id(partner),
        old_fee_rate,
        new_fee_rate: fee_rate,
    });
}

public fun update_time_range(
    cfg: &config::GlobalConfig,
    partner: &mut Partner,
    start_time: u64,
    end_time: u64,
    clock: &clock::Clock,
    ctx: &mut TxContext
) {
    assert!(end_time > start_time, ErrInvalidEndTime);
    assert!(end_time > clock.timestamp_ms() / 1000, ErrInvalidEndTime);
    cfg.checked_package_version();
    cfg.check_partner_manager_role(ctx.sender());
    partner.start_time = start_time;
    partner.end_time = end_time;
    event::emit(UpdateTimeRangeEvent{
        partner_id : object::id(partner),
        start_time,
        end_time,
    });
}

#[test_only]
public fun init_for_test(ctx: &mut TxContext): Partners {
    let partners = Partners{
        id: object::new(ctx),
        partners: vec_map::empty<String, ID>(),
    };
    partners
}
