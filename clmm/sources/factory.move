module magma_clmm::factory;

use std::string::{Self, String};
use std::type_name::{Self, TypeName};

use sui::clock;
use sui::coin::{Coin};
use sui::hash;
use sui::event;
use sui::bcs;
use sui::package;

use move_stl::linked_table::{Self, LinkedTable};

use magma_clmm::config;
use magma_clmm::position;
use magma_clmm::pool::{Self, Pool};
use magma_clmm::tick_math;

const ErrPoolAlreadyExisted: u64 = 1;
const ErrInvalidSqrtPrice: u64 = 2;
const ErrSameCoinType: u64 = 3;
const ErrAmountInAboveMaxLimit: u64 = 4;
const ErrAmountOutBelowMinLimit: u64 = 5;
const ErrInvalidCoinTypeSequence: u64 = 6;

public struct FACTORY has drop {}

public struct PoolSimpleInfo has copy, drop, store {
    pool_id: ID,
    pool_key: ID,
    coin_type_a: TypeName,
    coin_type_b: TypeName,
    tick_spacing: u32,
}

public struct Pools has store, key {
    id: UID,
    list: LinkedTable<ID, PoolSimpleInfo>,
    index: u64,
}

public struct InitFactoryEvent has copy, drop {
    pools_id: ID,
}

public struct CreatePoolEvent has copy, drop {
    pool_id: ID,
    coin_type_a: String,
    coin_type_b: String,
    tick_spacing: u32,
}

#[allow(lint(share_owned))]
public fun create_pool<CoinTypeA, CoinTypeB>(
    pools: &mut Pools,
    cfg: &config::GlobalConfig,
    tick_spacing: u32,
    initialize_price: u128,
    name: String,
    clock: &clock::Clock,
    ctx: &mut TxContext
): ID {
    cfg.checked_package_version();
    let pool = pools.create_pool_internal<CoinTypeA, CoinTypeB>(cfg, tick_spacing, initialize_price, name, clock, ctx);
    let pool_id = object::id(&pool);
    transfer::public_share_object(pool);
    pool_id
}

public fun create_pool_<A, B>(
    pools: &mut Pools,
    cfg: &config::GlobalConfig,
    tick_spacing: u32,
    initialize_price: u128,
    name: String,
    clock: &clock::Clock,
    ctx: &mut TxContext
): Pool<A, B> {
    cfg.checked_package_version();
    let pool = pools.create_pool_internal<A, B>(cfg, tick_spacing, initialize_price, name, clock, ctx);
    pool
}

// Gauge creation has been moved to V2
// #[allow(lint(share_owned))]
// public fun create_gauger_for_pool<A, B, C>(
//     _publisher: &package::Publisher,
//     pool: &mut Pool<A, B>,
//     ctx: &mut TxContext
// ) {
//     let gauger = return_new_gauger<A, B, C>(pool, ctx);
//     transfer::public_share_object(gauger);
// }

fun create_pool_internal<CoinTypeA, CoinTypeB>(
    pools: &mut Pools,
    cfg: &config::GlobalConfig,
    tick_spacing: u32,
    initialize_price: u128,
    url: String,
    clock: &clock::Clock,
    ctx: &mut TxContext
): Pool<CoinTypeA, CoinTypeB> {
    assert!(initialize_price >= tick_math::min_sqrt_price() && initialize_price <= tick_math::max_sqrt_price(), ErrInvalidSqrtPrice);
    let coin_type_a = type_name::get<CoinTypeA>();
    let coin_type_b = type_name::get<CoinTypeB>();
    assert!(coin_type_a != coin_type_b, ErrSameCoinType);
    let pool_key = new_pool_key<CoinTypeA, CoinTypeB>(tick_spacing);
    if (pools.list.contains(pool_key)) {
        abort ErrPoolAlreadyExisted
    };
    let pool_url = if (url.length() == 0) {
        string::utf8(b"")
    } else {
        url
    };
    let pool = pool::new<CoinTypeA, CoinTypeB>(tick_spacing, initialize_price, config::get_fee_rate(tick_spacing, cfg), pool_url, pools.index, clock, ctx);
    pools.index = pools.index + 1;
    let pool_id = object::id(&pool);
    let pool_info = PoolSimpleInfo{
        pool_id,
        pool_key,
        coin_type_a,
        coin_type_b,
        tick_spacing,
    };
    pools.list.push_back(pool_key, pool_info);
    event::emit(CreatePoolEvent{
        pool_id,
        coin_type_a: string::from_ascii(type_name::into_string(coin_type_a)),
        coin_type_b: string::from_ascii(type_name::into_string(coin_type_b)),
        tick_spacing,
    });
    pool
}

#[allow(lint(share_owned))]
public fun create_pool_with_liquidity<CoinTypeA, CoinTypeB>(
    pools: &mut Pools,
    cfg: &config::GlobalConfig,
    tick_spacing: u32,
    initialize_price: u128,
    name: String,
    tick_lower: u32,
    tick_upper: u32,
    mut coin_a: Coin<CoinTypeA>,
    mut coin_b: Coin<CoinTypeB>,
    amount_a: u64,
    amount_b: u64,
    fix_amount_a: bool,
    clock: &clock::Clock,
    ctx: &mut TxContext
): (position::Position, Coin<CoinTypeA>, Coin<CoinTypeB>) {
    cfg.checked_package_version();
    let mut pool = pools.create_pool_internal<CoinTypeA, CoinTypeB>(cfg, tick_spacing, initialize_price, name, clock, ctx);
    let mut position = pool::open_position<CoinTypeA, CoinTypeB>(cfg, &mut pool, tick_lower, tick_upper, ctx);
    let amount = if (fix_amount_a) {
        amount_a
    } else {
        amount_b
    };
    let add_liquidity_receipt = pool::add_liquidity_fix_coin(cfg, &mut pool, &mut position, amount, fix_amount_a, clock, ctx);
    let (pay_amount_a, pay_amount_b) = pool::add_liquidity_pay_amount<CoinTypeA, CoinTypeB>(&add_liquidity_receipt);
    if (fix_amount_a) {
        assert!(pay_amount_b <= amount_b, ErrAmountInAboveMaxLimit);
    } else {
        assert!(pay_amount_a <= amount_a, ErrAmountOutBelowMinLimit);
    };
    pool::repay_add_liquidity<CoinTypeA, CoinTypeB>(
        cfg,
        &mut pool,
        coin_a.split(pay_amount_a, ctx).into_balance(),
        coin_b.split(pay_amount_b, ctx).into_balance(),
        add_liquidity_receipt
    );
    transfer::public_share_object(pool);
    (position, coin_a, coin_b)
}

public fun fetch_pools(pools: &Pools, start: vector<ID>, limit: u64) : vector<PoolSimpleInfo> {
    let mut ret = vector::empty<PoolSimpleInfo>();
    let mut maybe_key = if (start.is_empty()) {
        pools.list.head()
    } else {
        option::some(start[0])
    };
    let mut counter = 0;
    while (maybe_key.is_some() && counter < limit) {
        let node = pools.list.borrow_node(*maybe_key.borrow());
        maybe_key = linked_table::next<ID, PoolSimpleInfo>(node);
        ret.push_back(*node.borrow_value());
        counter = counter + 1;
    };
    ret
}

public fun index(pools: &Pools) : u64 {
    pools.index
}

fun init(otw: FACTORY, ctx: &mut tx_context::TxContext) {
    let pools = Pools{
        id    : object::new(ctx),
        list  : linked_table::new<ID, PoolSimpleInfo>(ctx),
        index : 0,
    };
    let pools_id = object::id(&pools);
    transfer::share_object(pools);
    event::emit(InitFactoryEvent{pools_id});

    package::claim_and_keep(otw, ctx);
}

// Also make sure that CoinTypeA > CoinTypeB
public fun new_pool_key<CoinTypeA, CoinTypeB>(tick_spacing: u32): ID {
    let mut coin_type_a = *type_name::into_string(type_name::get<CoinTypeA>()).as_bytes();
    let coin_type_b = type_name::into_string(type_name::get<CoinTypeB>()).as_bytes();
    let mut idx = 0;
    let mut sorted = false;
    while (idx < coin_type_b.length()) {
        let b_char = *coin_type_b.borrow(idx);
        if (!sorted && idx < coin_type_a.length()) {
            let a_char = *coin_type_a.borrow(idx);
            if (a_char < b_char) {
                abort ErrInvalidCoinTypeSequence
            };
            if (a_char > b_char) {
                sorted = true;
            };
        };
        coin_type_a.push_back(b_char);
        idx = idx + 1;
    };
    if (!sorted) {
        if (coin_type_a.length() < coin_type_b.length()) {
            abort ErrInvalidCoinTypeSequence
        };
    };
    coin_type_a.append(bcs::to_bytes(&tick_spacing));
    object::id_from_bytes(hash::blake2b256(&coin_type_a))
}

public fun pool_id(pool_info: &PoolSimpleInfo): ID {
    pool_info.pool_id
}

public fun pool_key(pool_info: &PoolSimpleInfo): ID {
    pool_info.pool_key
}

public fun pool_simple_info(pools: &Pools, id: ID): &PoolSimpleInfo {
    pools.list.borrow(id)
}

public fun tick_spacing(pool_info: &PoolSimpleInfo): u32 {
    pool_info.tick_spacing
}

public fun coin_types(pool_info: &PoolSimpleInfo): (TypeName, TypeName) {
    (pool_info.coin_type_a, pool_info.coin_type_b)
}

#[test_only]
public struct TestFactory {
    publisher: package::Publisher,
    pools: Pools,
}

#[test_only]
public fun build_test_factory(ctx: &mut TxContext): TestFactory {
    use sui::test_utils::create_one_time_witness;

    let otw = create_one_time_witness<FACTORY>();
    let publisher = package::claim(otw, ctx);

    TestFactory {
        publisher,
        pools: Pools {
            id    : object::new(ctx),
            list  : linked_table::new<ID, PoolSimpleInfo>(ctx),
            index : 0,
        },
    }
}

#[test_only]
public fun t_create_pool<A, B>(self: &mut TestFactory, cfg: &config::GlobalConfig, tick_spacing: u32, init_price: u128, clock: &clock::Clock, ctx: &mut TxContext): Pool<A, B> {
    self.pools.create_pool_internal<A, B>(cfg, tick_spacing, init_price, b"".to_string(), clock, ctx)
}

#[test_only]
public fun borrow_pools(self: &TestFactory): &Pools {
    &self.pools
}

#[test_only]
public fun borrow_pools_mut(self: &mut TestFactory): &mut Pools {
    &mut self.pools
}
