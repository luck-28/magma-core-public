#[test_only]
module magma_clmm::swap_tests {
    use sui::coin::{Self, Coin};
    use sui::clock;
    use sui::balance;
    use sui::test_scenario;
    use sui::test_utils::destroy;

    use magma_clmm::config;
    use magma_clmm::factory::{Self, TestFactory};
    use magma_clmm::tick_math;
    use magma_clmm::partner;
    use magma_clmm::pool::{Self as pool_mod, Pool};
    use magma_clmm::setup_coins;
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::test_coin_magma::{Self, TEST_COIN_MAGMA};

    use integer_mate::i32;

    #[test_only]
    public fun swap<A, B>(
        cfg: &config::GlobalConfig,
        pool: &mut Pool<A, B>,
        mut coin_a: Coin<A>,
        mut coin_b: Coin<B>,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        amount_in_out_limit: u64,
        target_price: u128,
        clock: &clock::Clock,
        ctx: &mut TxContext
    ): (Coin<A>, Coin<B>) {
        let (balance_a, balance_b, flash_swap_receipt) = pool_mod::flash_swap<A, B>(cfg, pool, a2b, by_amount_in, amount, target_price, clock);
        let flash_swap_receipt = flash_swap_receipt;
        let balance_b = balance_b;
        let balance_a = balance_a;
        let pay_amount = pool_mod::swap_pay_amount<A, B>(&flash_swap_receipt);
        let out_amount = if (a2b) {
            balance_b.value()
        } else {
            balance_a.value()
        };
        if (by_amount_in) {
            assert!(pay_amount == amount, 2);
            assert!(out_amount >= amount_in_out_limit, 1);
        } else {
            assert!(out_amount == amount, 2);
            assert!(pay_amount <= amount_in_out_limit, 0);
        };
        let (pay_balance_a, pay_balance_b) = if (a2b) {
            (coin_a.split(pay_amount, ctx).into_balance(), balance::zero<B>())
        } else {
            (balance::zero<A>(), coin_b.split(pay_amount, ctx).into_balance())
        };
        pool_mod::repay_flash_swap<A, B>(cfg, pool, pay_balance_a, pay_balance_b, flash_swap_receipt);
        coin_b.join(coin::from_balance(balance_b, ctx));
        coin_a.join(coin::from_balance(balance_a, ctx));

        (coin_a, coin_b)
    }

    #[test]
    fun test_swap_a2b_by_amount_out() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        // tick: 12345
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(&cfg, 10, 0x1da90654c407ac000, &clk, scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, tick_lower, tick_upper, scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, &mut position, fix_coin_amount, true, &clk, scenario.ctx());
        scenario.next_tx(liquidity_provider);
        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        scenario.next_tx(liquidity_provider);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, coin_b.split(pay_amount_b, scenario.ctx()).into_balance(), coin_a.split(pay_amount_a, scenario.ctx()).into_balance(), add_liquidity_receipt);

        scenario.next_tx(liquidity_provider);
        let amount_out = 100000000;

        let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, false, amount_out, tick_math::min_sqrt_price(), &clk);
        assert!(swap_out_b.value() == 0);
        assert!(swap_out_a.value() > 0);

        destroy(swap_out_a);
        destroy(swap_out_b);
        destroy(receipt);
        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(position);

        scenario.end();
    }

    #[test]
    fun test_swap_a2b_by_amount_in() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        // tick: 12345
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(&cfg, 10, 0x1da90654c407ac000, &clk, scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, tick_lower, tick_upper, scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, &mut position, fix_coin_amount, true, &clk, scenario.ctx());
        scenario.next_tx(liquidity_provider);
        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        scenario.next_tx(liquidity_provider);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, coin_b.split(pay_amount_b, scenario.ctx()).into_balance(), coin_a.split(pay_amount_a, scenario.ctx()).into_balance(), add_liquidity_receipt);

        scenario.next_tx(liquidity_provider);
        let amount_in = 100000000;

        let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, true, amount_in, tick_math::min_sqrt_price(), &clk);
        assert!(swap_out_b.value() == 0);
        assert!(swap_out_a.value() > 0);
        assert!(receipt.swap_pay_amount() == amount_in);

        destroy(swap_out_a);
        destroy(swap_out_b);
        destroy(receipt);
        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(position);

        scenario.end();
    }

    #[test]
    fun test_swap_b2a_by_amount_in() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        // tick: 12345
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg, 
            10, 
            0x1da90654c407ac000, 
            &clk, 
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            fix_coin_amount,
            true,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        
        scenario.next_tx(liquidity_provider);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        scenario.next_tx(liquidity_provider);
        let amount_in = 100000000;

        let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(
            &cfg,
            &mut pool,
            false, // b2a
            true,  // by_amount_in
            amount_in,
            tick_math::max_sqrt_price(),
            &clk
        );

        assert!(swap_out_a.value() == 0);
        assert!(swap_out_b.value() > 0);
        assert!(receipt.swap_pay_amount() == amount_in);

        destroy(swap_out_a);
        destroy(swap_out_b);
        destroy(receipt);
        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(position);

        scenario.end();
    }

    #[test]
    fun test_swap_b2a_by_amount_out() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        // tick: 12345
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg, 
            10, 
            0x1da90654c407ac000, 
            &clk, 
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            fix_coin_amount,
            true,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        
        scenario.next_tx(liquidity_provider);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        scenario.next_tx(liquidity_provider);
        let amount_out = 100000000;

        let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(
            &cfg,
            &mut pool,
            false, // b2a
            false, // by_amount_out
            amount_out,
            tick_math::max_sqrt_price(),
            &clk
        );

        assert!(swap_out_a.value() == 0);
        assert!(swap_out_b.value() > 0);

        destroy(swap_out_a);
        destroy(swap_out_b);
        destroy(receipt);
        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(position);

        scenario.end();
    }

    #[test]
    fun test_swap_with_fee() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg, 
            10, 
            0x1da90654c407ac000, 
            &clk, 
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add initial liquidity
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            fix_coin_amount,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        // Record initial balances
        let coin_b_before = coin_b.value();
        let coin_a_before = coin_a.value();

        // Perform swap using the swap helper function
        let swap_amount = 100000000;
        let (coin_b, coin_a) = swap<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b,
            coin_a,
            true,  // a2b
            true,  // by_amount_in
            swap_amount,
            1,     // min amount out
            tick_math::min_sqrt_price(),
            &clk,
            scenario.ctx()
        );

        // Verify swap results and fee collection
        assert!(coin_b.value() == coin_b_before - swap_amount, 0);
        assert!(coin_a.value() > coin_a_before, 1);

        // Check pool fees
        let gauger_fees = pool.magma_distribution_gauger_fee();
        let (fee_b, fee_a) = gauger_fees.pool_fee_a_b();
        assert!(fee_b > 0, 2); // Should have collected some fees
        assert!(fee_a == 0, 3); // No fees for token A

        // Cleanup
        destroy(gauger_fees);
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);

        scenario.end();
    }

    #[test]
    fun test_swap_fee_without_gauge() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(
            0, // unstaked_liquidity_fee_rate: 0%
            1000, // protocol_fee_rate: 10%
            vector[config::create_fee_tier(10, 200000)],
            scenario.ctx()
        );

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        // Create pool and add liquidity
        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg, 
            10, 
            0x1da90654c407ac000, 
            &clk,   
            scenario.ctx()
        );

        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            12330,
            12350,
            scenario.ctx()
        );

        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            1000000000,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        // Perform swap and check fees
        let coin_b_before = coin_b.value();
        let swap_amount = 100000000;
        let (coin_b, coin_a) = swap<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b,
            coin_a,
            true,
            true,
            swap_amount,
            1,
            tick_math::min_sqrt_price(),
            &clk,
            scenario.ctx()
        );

        // Verify swap results
        assert!(coin_b.value() == coin_b_before - swap_amount, 0);

        // Check pool fees without gauge
        let total_fee = (swap_amount as u128) * (pool.fee_rate() as u128) / 1000000;  // 0.2% total fee
        let protocol_fee = (total_fee * (cfg.protocol_fee_rate() as u128) / (config::protocol_fee_rate_denom() as u128)) as u64; // Calculate protocol fee
        let pool_fee = (total_fee - (protocol_fee as u128)) as u64; // Actual fee collected by pool

        // Get actual fees from pool
        let (protocol_fee_b, protocol_fee_a) = pool_mod::protocol_fee(&pool);
        let (fee_growth_global_b, fee_growth_global_a) = pool_mod::fees_growth_global(&pool);

        // Verify fees, allowing 1 unit error
        let actual_fee = (fee_growth_global_b * pool.liquidity()) >> 64;
        let pool_fee_u128 = (pool_fee as u128);

        assert!(fee_growth_global_b > 0 && (actual_fee >= pool_fee_u128 - 1 && actual_fee <= pool_fee_u128 + 1), 1); // Verify pool fee
        assert!(protocol_fee_b == protocol_fee, 2); // Verify protocol fee
        assert!(fee_growth_global_a == 0 && protocol_fee_a == 0, 3); // Verify no fees for token A

        // Cleanup
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);

        scenario.end();
    }

    #[test]
    fun test_swap_crossing_tick_zero() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;
        let liquidity_provider2 = @0xCAFE02;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        // tick: 0
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg, 10, 0x10000000000000000, &clk, scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let tick_lower = i32::neg_from(100).as_u32();
        let tick_upper = 100;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, tick_lower, tick_upper, scenario.ctx());

        scenario.next_tx(liquidity_provider2);
        let tick_lower = i32::neg_from(200).as_u32();
        let tick_upper = i32::neg_from(100).as_u32();
        let mut position2 = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, tick_lower, tick_upper, scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, &mut position, fix_coin_amount, true, &clk, scenario.ctx());
        scenario.next_tx(liquidity_provider);
        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        scenario.next_tx(liquidity_provider);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, coin_b.split(pay_amount_b, scenario.ctx()).into_balance(), coin_a.split(pay_amount_a, scenario.ctx()).into_balance(), add_liquidity_receipt);
        let coina_amount_to_swap = pay_amount_a;

        scenario.next_tx(liquidity_provider2);
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, &mut position2, fix_coin_amount, false, &clk, scenario.ctx());
        scenario.next_tx(liquidity_provider2);
        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        scenario.next_tx(liquidity_provider2);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, coin_b.split(pay_amount_b, scenario.ctx()).into_balance(), coin_a.split(pay_amount_a, scenario.ctx()).into_balance(), add_liquidity_receipt);

        assert!(pool.current_sqrt_price() == 1 << 64);
        assert!(pool.current_tick_index() == i32::from(0));

        let user = @0xabcdef;
        scenario.next_tx(user);
        let amount_out = coina_amount_to_swap;
        let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, false, amount_out, tick_math::min_sqrt_price(), &clk);
        assert!(swap_out_b.value() == 0);
        assert!(swap_out_a.value() >= amount_out);

        assert!(pool.current_sqrt_price() < 1 << 64);
        assert!(pool.current_tick_index().is_neg());

        destroy(swap_out_a);
        destroy(swap_out_b);
        destroy(receipt);
        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(position);
        destroy(position2);

        scenario.end();
    }


    #[test]
    fun test_calculate_swap_fees() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let swap_fee_rate = 100000;
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(1000, 2000, vector[config::create_fee_tier(10, swap_fee_rate)], scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add initial liquidity
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            fix_coin_amount,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        // Record initial balances
        let coin_b_before = coin_b.value();
        let coin_a_before = coin_a.value();

        // Perform swap using the swap helper function
        let swap_amount = 100000000;
        let calc_swap_result = pool_mod::calculate_swap_result(&cfg, &pool, true, true, swap_amount);

        let a2b = true;
        let by_amount_in = true;

        scenario.next_tx(deployer);

        let (balance_a, balance_b, flash_swap_receipt) = pool_mod::flash_swap(&cfg, &mut pool, a2b, by_amount_in, swap_amount, tick_math::min_sqrt_price(), &clk);
        // let (balance_a, balance_b, flash_swap_receipt) = pool_mod::flash_swap<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, a2b, by_amount_in, swap_amount, tick_math::min_sqrt_price(), &clk);
        let (swap_fee_amount, swap_partner_fee_amount, swap_protocol_fee_amount, swap_gauge_fee_amount) = flash_swap_receipt.fees_amount();
        let (calc_fee_amount, calc_ref_fee_amount, calc_protocol_fee_amount, calc_gauge_fee_amount) = calc_swap_result.calculated_swap_result_fees_amount();
        assert!(calc_fee_amount == swap_fee_amount);
        assert!(calc_ref_fee_amount == swap_partner_fee_amount);
        assert!(calc_gauge_fee_amount == swap_gauge_fee_amount);
        assert!(swap_protocol_fee_amount == calc_protocol_fee_amount);

        assert!(swap_amount * swap_fee_rate / config::fee_rate_denom() == swap_fee_amount);
        assert!(0 == swap_partner_fee_amount);
        assert!(swap_fee_amount * cfg.protocol_fee_rate() / config::protocol_fee_rate_denom() == swap_protocol_fee_amount);

        let balance_b = balance_b;
        let balance_a = balance_a;
        let pay_amount = pool_mod::swap_pay_amount<TEST_COIN_B, TEST_COIN_A>(&flash_swap_receipt);
        let out_amount = if (a2b) {
            balance_b.value()
        } else {
            balance_a.value()
        };

        if (by_amount_in) {
            assert!(pay_amount == swap_amount, 2);
            assert!(out_amount >= 1, 1);
        } else {
            assert!(out_amount == swap_amount, 2);
            // assert!(pay_amount <= amount_in_out_limit, 0);
        };
        let (pay_balance_a, pay_balance_b) = if (a2b) {
            (coin_b.split(pay_amount, scenario.ctx()).into_balance(), balance::zero<TEST_COIN_A>())
        } else {
            (balance::zero<TEST_COIN_B>(), coin_a.split(pay_amount, scenario.ctx()).into_balance())
        };
        pool_mod::repay_flash_swap<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, pay_balance_a, pay_balance_b, flash_swap_receipt);
        coin_b.join(coin::from_balance(balance_a, scenario.ctx()));
        coin_a.join(coin::from_balance(balance_b, scenario.ctx()));

        // Verify swap results and fee collection
        assert!(coin_b.value() == coin_b_before - swap_amount, 0);
        assert!(coin_a.value() > coin_a_before, 1);

        // Check pool fees
        let gauger_fees = pool.magma_distribution_gauger_fee();
        let (fee_b, fee_a) = gauger_fees.pool_fee_a_b();
        assert!(fee_b > 0, 2); // Should have collected some fees
        assert!(fee_a == 0, 3); // No fees for token A

        // Cleanup
        destroy(gauger_fees);
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);

        scenario.end();
    }

    #[test]
    fun test_calculate_swap_fees_with_partner() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let swap_fee_rate = 100000;
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(1000, 2000, vector[config::create_fee_tier(10, swap_fee_rate)], scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add initial liquidity
        let fix_coin_amount = 1000000000;
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            fix_coin_amount,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        // Record initial balances
        let coin_b_before = coin_b.value();
        let coin_a_before = coin_a.value();

        let partner_fee_rate = 1500;
        // Perform swap using the swap helper function
        let swap_amount = 100000000;
        let calc_swap_result = pool_mod::calculate_swap_result_with_partner(&cfg, &pool, true, true, swap_amount, partner_fee_rate);

        let a2b = true;
        let by_amount_in = true;
        let partner_addr = @0xa1234;

        scenario.next_tx(deployer);
        let mut partners = partner::init_for_test(scenario.ctx());
        partner::create_partner(&cfg, &mut partners, b"fff".to_string(), partner_fee_rate, clk.timestamp_ms() / 1000, clk.timestamp_ms() / 1000 + 365 * 86400, partner_addr, &clk, scenario.ctx());

        scenario.next_tx(deployer);
        let mut partner = scenario.take_shared<partner::Partner>();
        partner::update_ref_fee_rate(&cfg, &mut partner, partner_fee_rate, scenario.ctx());

        let (balance_a, balance_b, flash_swap_receipt) = pool_mod::flash_swap_with_partner(&cfg, &mut pool, &partner, a2b, by_amount_in, swap_amount, tick_math::min_sqrt_price(), &clk);
        // let (balance_a, balance_b, flash_swap_receipt) = pool_mod::flash_swap<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, a2b, by_amount_in, swap_amount, tick_math::min_sqrt_price(), &clk);
        let (swap_fee_amount, swap_partner_fee_amount, swap_protocol_fee_amount, swap_gauge_fee_amount) = flash_swap_receipt.fees_amount();
        let (calc_fee_amount, calc_ref_fee_amount, calc_protocol_fee_amount, calc_gauge_fee_amount) = calc_swap_result.calculated_swap_result_fees_amount();
        assert!(calc_fee_amount == swap_fee_amount);
        assert!(calc_ref_fee_amount == swap_partner_fee_amount);
        assert!(calc_gauge_fee_amount == swap_gauge_fee_amount);
        assert!(swap_protocol_fee_amount == calc_protocol_fee_amount);

        assert!(swap_amount * swap_fee_rate / config::fee_rate_denom() == swap_fee_amount);
        assert!(swap_fee_amount * partner_fee_rate / config::protocol_fee_rate_denom() == swap_partner_fee_amount);
        assert!((swap_fee_amount - swap_partner_fee_amount) * cfg.protocol_fee_rate() / config::protocol_fee_rate_denom() == swap_protocol_fee_amount);

        let balance_b = balance_b;
        let balance_a = balance_a;
        let pay_amount = pool_mod::swap_pay_amount<TEST_COIN_B, TEST_COIN_A>(&flash_swap_receipt);
        let out_amount = if (a2b) {
            balance_b.value()
        } else {
            balance_a.value()
        };

        if (by_amount_in) {
            assert!(pay_amount == swap_amount, 2);
            assert!(out_amount >= 1, 1);
        } else {
            assert!(out_amount == swap_amount, 2);
            // assert!(pay_amount <= amount_in_out_limit, 0);
        };
        let (pay_balance_a, pay_balance_b) = if (a2b) {
            (coin_b.split(pay_amount, scenario.ctx()).into_balance(), balance::zero<TEST_COIN_A>())
        } else {
            (balance::zero<TEST_COIN_B>(), coin_a.split(pay_amount, scenario.ctx()).into_balance())
        };
        pool_mod::repay_flash_swap_with_partner<TEST_COIN_B, TEST_COIN_A>(&cfg, &mut pool, &mut partner, pay_balance_a, pay_balance_b, flash_swap_receipt);
        coin_b.join(coin::from_balance(balance_a, scenario.ctx()));
        coin_a.join(coin::from_balance(balance_b, scenario.ctx()));

        // Verify swap results and fee collection
        assert!(coin_b.value() == coin_b_before - swap_amount, 0);
        assert!(coin_a.value() > coin_a_before, 1);

        // Check pool fees
        let gauger_fees = pool.magma_distribution_gauger_fee();
        let (fee_b, fee_a) = gauger_fees.pool_fee_a_b();
        assert!(fee_b > 0, 2); // Should have collected some fees
        assert!(fee_a == 0, 3); // No fees for token A

        // Cleanup
        destroy(gauger_fees);
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(partners);
        destroy(partner);

        scenario.end();
    }
}
