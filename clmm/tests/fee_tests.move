#[test_only]
module magma_clmm::fee_tests {
    use sui::coin::{Self, Coin};
    use sui::clock;
    use sui::balance;
    use sui::test_scenario;
    use sui::test_utils::destroy;

    use magma_clmm::config;
    use magma_clmm::factory::{Self, TestFactory};
    use magma_clmm::tick_math;
    use magma_clmm::pool::{Self as pool_mod, Pool};
    use magma_clmm::setup_coins;
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::test_coin_magma::{Self, TEST_COIN_MAGMA};

    use integer_mate::{i32, full_math_u64};

    #[test]
    fun test_10percent_protocol_fee_by_default() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let protocol_fee_rate = 1000;
        let swap_fee_rate = 500;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(
            0,
            protocol_fee_rate,
            vector[config::create_fee_tier(10, swap_fee_rate)],
            scenario.ctx());

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
        {
            let amount_out = 558943800;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, false, amount_out, tick_math::min_sqrt_price(), &clk);
            assert!(swap_out_b.value() == 0);
            assert!(swap_out_a.value() > 0);
            let (protocol_fee_a, _protocol_fee_b) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(full_math_u64::mul_div_ceil(receipt.swap_pay_amount(), swap_fee_rate, config::fee_rate_denom()), protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee_a);
            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };

        scenario.next_tx(liquidity_provider);
        {
            let (protocol_fee_a_before, _) = pool.protocol_fee();
            let amount_in = 558943800;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, true, amount_in, tick_math::min_sqrt_price(), &clk);
            assert!(swap_out_b.value() == 0);
            assert!(swap_out_a.value() > 0);
            let (protocol_fee_a, _protocol_fee_b) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(full_math_u64::mul_div_ceil(receipt.swap_pay_amount(), swap_fee_rate, config::fee_rate_denom()), protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee_a - protocol_fee_a_before);
            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };

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
    fun test_every_swap_should_pay_protocol_fee_at_least_1() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let protocol_fee_rate = 1000;
        let swap_fee_rate = 500;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(
            0,
            protocol_fee_rate,
            vector[config::create_fee_tier(10, swap_fee_rate)],
            scenario.ctx());

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
        {
            let amount_out = 1;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, false, amount_out, tick_math::min_sqrt_price(), &clk);
            assert!(swap_out_b.value() == 0);
            assert!(swap_out_a.value() > 0);
            let (protocol_fee_a, _protocol_fee_b) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(full_math_u64::mul_div_ceil(receipt.swap_pay_amount(), swap_fee_rate, config::fee_rate_denom()), protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee_a);
            assert!(protocol_fee_a > 0);
            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };

        scenario.next_tx(liquidity_provider);
        {
            let (protocol_fee_a_before, _) = pool.protocol_fee();
            let amount_in = 445623424;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, true, amount_in, tick_math::min_sqrt_price(), &clk);
            assert!(swap_out_b.value() == 0);
            assert!(swap_out_a.value() > 0);
            let (protocol_fee_a, _protocol_fee_b) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(full_math_u64::mul_div_ceil(receipt.swap_pay_amount(), swap_fee_rate, config::fee_rate_denom()), protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee_a - protocol_fee_a_before);
            assert!(protocol_fee_a > 0);
            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };

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
    fun test_pool_protocol_fee_override_default() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let protocol_fee_rate = 1000;
        let unstaked_liquidity_fee_rate = 2000;
        let swap_fee_rate = 500;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(
            0,
            protocol_fee_rate,
            vector[config::create_fee_tier(10, swap_fee_rate)],
            scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        // tick: 12345
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(&cfg, 10, 0x1da90654c407ac000, &clk, scenario.ctx());
        scenario.next_tx(deployer);
        pool_mod::update_unstaked_liquidity_fee_rate(&cfg, &mut pool, unstaked_liquidity_fee_rate, scenario.ctx());

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
        {
            let amount_out = 558943800;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, false, amount_out, tick_math::min_sqrt_price(), &clk);

            let pay_amount = receipt.swap_pay_amount();
            let fee_amount = full_math_u64::mul_div_ceil(pay_amount, swap_fee_rate, config::fee_rate_denom());
            let supposed_protocol_fee = full_math_u64::mul_div_ceil(fee_amount, protocol_fee_rate, config::protocol_fee_rate_denom());
            let (protocol_fee, _) = pool.protocol_fee();
            assert!(supposed_protocol_fee == protocol_fee);

            let supposed_gauger_fee = full_math_u64::mul_div_ceil(fee_amount - protocol_fee, pool.unstaked_liquidity_fee_rate(), config::protocol_fee_rate_denom());
            let gauger_fee = pool.magma_distribution_gauger_fee();
            let (gauger_fee, _) = gauger_fee.pool_fee_a_b();
            assert!(supposed_gauger_fee == gauger_fee);

            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };

        scenario.next_tx(liquidity_provider);
        {
            let gauger_fee_before = pool.magma_distribution_gauger_fee();
            let (gauger_fee_before, _) = gauger_fee_before.pool_fee_a_b();

            let (protocol_fee_a_before, _) = pool.protocol_fee();
            let amount_in = 284750374;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, true, amount_in, tick_math::min_sqrt_price(), &clk);
            let pay_amount = receipt.swap_pay_amount();
            let fee_amount = full_math_u64::mul_div_ceil(pay_amount, swap_fee_rate, config::fee_rate_denom());
            let (protocol_fee, _) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(fee_amount, protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee - protocol_fee_a_before);

            let supposed_gauger_fee = full_math_u64::mul_div_ceil(fee_amount - supposed, pool.unstaked_liquidity_fee_rate(), config::protocol_fee_rate_denom());
            let gauger_fee = pool.magma_distribution_gauger_fee();
            let (gauger_fee, _) = gauger_fee.pool_fee_a_b();
            assert!(supposed_gauger_fee == gauger_fee - gauger_fee_before);

            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };

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
    fun test_some_pool_with_0_unstaked_liquidity_fee() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        let protocol_fee_rate = 1000;
        let unstaked_liquidity_fee_rate = 1000;
        let swap_fee_rate = 500;

        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config_with_fee_rates(
            unstaked_liquidity_fee_rate,
            protocol_fee_rate,
            vector[config::create_fee_tier(10, swap_fee_rate)],
            scenario.ctx());

        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(&cfg, 10, 0x1da90654c407ac000, &clk, scenario.ctx());
        scenario.next_tx(deployer);
        pool_mod::update_unstaked_liquidity_fee_rate(&cfg, &mut pool, 0, scenario.ctx());

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
        {
            let amount_out = 558943800;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, false, amount_out, tick_math::min_sqrt_price(), &clk);
            assert!(swap_out_b.value() == 0);
            assert!(swap_out_a.value() > 0);
            let (protocol_fee_a, _protocol_fee_b) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(full_math_u64::mul_div_ceil(receipt.swap_pay_amount(), swap_fee_rate, config::fee_rate_denom()), protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee_a);
            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };
        let gauger_fee = pool.magma_distribution_gauger_fee();
        let (gauger_fee, _) = gauger_fee.pool_fee_a_b();
        assert!(gauger_fee == 0);

        scenario.next_tx(deployer);
        pool_mod::update_unstaked_liquidity_fee_rate(&cfg, &mut pool, config::default_unstaked_fee_rate(), scenario.ctx());

        scenario.next_tx(liquidity_provider);
        {
            let (protocol_fee_a_before, _) = pool.protocol_fee();
            let amount_in = 558943800;
            let (swap_out_b, swap_out_a, receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, true, amount_in, tick_math::min_sqrt_price(), &clk);
            assert!(swap_out_b.value() == 0);
            assert!(swap_out_a.value() > 0);
            let (protocol_fee_a, _protocol_fee_b) = pool.protocol_fee();
            let supposed = full_math_u64::mul_div_ceil(full_math_u64::mul_div_ceil(receipt.swap_pay_amount(), swap_fee_rate, config::fee_rate_denom()), protocol_fee_rate, config::protocol_fee_rate_denom());
            assert!(supposed == protocol_fee_a - protocol_fee_a_before);
            destroy(swap_out_a);
            destroy(swap_out_b);
            destroy(receipt);
        };
        let gauger_fee = pool.magma_distribution_gauger_fee();
        let (gauger_fee, _) = gauger_fee.pool_fee_a_b();
        assert!(gauger_fee > 0);


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

    // #[test]
    // fun test_swap_with_fee() {
    //     let deployer = @0xFFFF;
    //     let liquidity_provider = @0xCAFE;

    //     let mut scenario = test_scenario::begin(deployer);
    //     let clk = clock::create_for_testing(scenario.ctx());
    //     let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

    //     let mut coins_setups = setup_coins::setup(scenario.ctx());
    //     let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
    //     let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

    //     scenario.next_tx(deployer);
    //     let mut test_factory = factory::build_test_factory(scenario.ctx());

    //     scenario.next_tx(liquidity_provider);
    //     let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         10,
    //         0x1da90654c407ac000,
    //         &clk,
    //         scenario.ctx()
    //     );

    //     scenario.next_tx(liquidity_provider);
    //     let tick_lower = 12330;
    //     let tick_upper = 12350;
    //     let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         tick_lower,
    //         tick_upper,
    //         scenario.ctx()
    //     );

    //     // Add initial liquidity
    //     let fix_coin_amount = 1000000000;
    //     let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         &mut position,
    //         fix_coin_amount,
    //         true,
    //         &clk,
    //         scenario.ctx()
    //     );

    //     let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
    //     pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
    //         coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
    //         add_liquidity_receipt
    //     );

    //     // Record initial balances
    //     let coin_b_before = coin_b.value();
    //     let coin_a_before = coin_a.value();

    //     // Perform swap using the swap helper function
    //     let swap_amount = 100000000;
    //     let (coin_b, coin_a) = swap<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         coin_b,
    //         coin_a,
    //         true,  // a2b
    //         true,  // by_amount_in
    //         swap_amount,
    //         1,     // min amount out
    //         tick_math::min_sqrt_price(),
    //         &clk,
    //         scenario.ctx()
    //     );

    //     // Verify swap results and fee collection
    //     assert!(coin_b.value() == coin_b_before - swap_amount, 0);
    //     assert!(coin_a.value() > coin_a_before, 1);

    //     // Check pool fees
    //     let gauger_fees = pool.magma_distribution_gauger_fee();
    //     let (fee_b, fee_a) = gauger_fees.pool_fee_a_b();
    //     assert!(fee_b > 0, 2); // Should have collected some fees
    //     assert!(fee_a == 0, 3); // No fees for token A

    //     // Cleanup
    //     destroy(gauger_fees);
    //     destroy(position);
    //     destroy(pool);
    //     destroy(cfg);
    //     destroy(admin_cap);
    //     destroy(clk);
    //     destroy(coin_a);
    //     destroy(coin_b);
    //     destroy(test_factory);
    //     destroy(coins_setups);

    //     scenario.end();
    // }

    // #[test]
    // fun test_swap_fee_without_gauge() {
    //     let deployer = @0xFFFF;
    //     let liquidity_provider = @0xCAFE;

    //     let mut scenario = test_scenario::begin(deployer);
    //     let clk = clock::create_for_testing(scenario.ctx());
    //     let (mut cfg, admin_cap) = config::create_config_with_fee_rates(
    //         0, // unstaked_liquidity_fee_rate: 0%
    //         1000, // protocol_fee_rate: 10%
    //         vector[config::create_fee_tier(10, 200000)],
    //         scenario.ctx()
    //     );

    //     let mut coins_setups = setup_coins::setup(scenario.ctx());
    //     let mut coin_a = coins_setups.mint<TEST_COIN_A>(1000000000000, scenario.ctx());
    //     let mut coin_b = coins_setups.mint<TEST_COIN_B>(1000000000000, scenario.ctx());

    //     // Create pool and add liquidity
    //     scenario.next_tx(deployer);
    //     let mut test_factory = factory::build_test_factory(scenario.ctx());

    //     let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         10,
    //         0x1da90654c407ac000,
    //         &clk,
    //         scenario.ctx()
    //     );

    //     let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         12330,
    //         12350,
    //         scenario.ctx()
    //     );

    //     let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         &mut position,
    //         1000000000,
    //         true,
    //         &clk,
    //         scenario.ctx()
    //     );

    //     let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
    //     pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
    //         coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
    //         add_liquidity_receipt
    //     );

    //     // Perform swap and check fees
    //     let coin_b_before = coin_b.value();
    //     let swap_amount = 100000000;
    //     let (coin_b, coin_a) = swap<TEST_COIN_B, TEST_COIN_A>(
    //         &cfg,
    //         &mut pool,
    //         coin_b,
    //         coin_a,
    //         true,
    //         true,
    //         swap_amount,
    //         1,
    //         tick_math::min_sqrt_price(),
    //         &clk,
    //         scenario.ctx()
    //     );

    //     // Verify swap results
    //     assert!(coin_b.value() == coin_b_before - swap_amount, 0);

    //     // Check pool fees without gauge
    //     let total_fee = (swap_amount as u128) * (pool.fee_rate() as u128) / 1000000;  // 0.2% total fee
    //     let protocol_fee = (total_fee * (cfg.protocol_fee_rate() as u128) / (config::protocol_fee_rate_denom() as u128)) as u64; // Calculate protocol fee
    //     let pool_fee = (total_fee - (protocol_fee as u128)) as u64; // Actual fee collected by pool

    //     // Get actual fees from pool
    //     let (protocol_fee_b, protocol_fee_a) = pool_mod::protocol_fee(&pool);
    //     let (fee_growth_global_b, fee_growth_global_a) = pool_mod::fees_growth_global(&pool);

    //     // Verify fees, allowing 1 unit error
    //     let actual_fee = (fee_growth_global_b * pool.liquidity()) >> 64;
    //     let pool_fee_u128 = (pool_fee as u128);

    //     assert!(fee_growth_global_b > 0 && (actual_fee >= pool_fee_u128 - 1 && actual_fee <= pool_fee_u128 + 1), 1); // Verify pool fee
    //     assert!(protocol_fee_b == protocol_fee, 2); // Verify protocol fee
    //     assert!(fee_growth_global_a == 0 && protocol_fee_a == 0, 3); // Verify no fees for token A

    //     // Cleanup
    //     destroy(position);
    //     destroy(pool);
    //     destroy(cfg);
    //     destroy(admin_cap);
    //     destroy(clk);
    //     destroy(coin_a);
    //     destroy(coin_b);
    //     destroy(test_factory);
    //     destroy(coins_setups);

    //     scenario.end();
    // }

}
