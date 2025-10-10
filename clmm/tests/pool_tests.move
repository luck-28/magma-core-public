#[test_only]
module magma_clmm::pool_tests {
    use sui::test_scenario;
    use sui::test_utils::destroy;
    use sui::clock;
    use sui::coin;
    use sui::balance;

    use integer_mate::i32;
    use magma_clmm::config;
    use magma_clmm::factory;
    use magma_clmm::rewarder;
    use magma_clmm::pool::{Self as pool_mod, Pool};
    use magma_clmm::position;
    use magma_clmm::tick_math;
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::setup_coins;
    use magma_clmm::swap_tests::swap;
    use magma_clmm::clmm_math;

    const DEPLOYER: address = @0xFFFF;
    const LP: address = @0xCAFE;
    const TICK_SPACING: u32 = 10;
    const INIT_SQRT_PRICE: u128 = 0x1da90654c407ac000;
    const LIQUIDITY: u64 = 1000000000;
    const SWAP_AMOUNT: u64 = 100000000;
    const TICK_LOWER: u32 = 12000;
    const TICK_UPPER: u32 = 13000;

    #[test]
    fun test_create_pool() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        // Create pool
        let pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        // Verify pool state
        assert!(pool.current_sqrt_price() == INIT_SQRT_PRICE, 0);
        assert!(pool.tick_spacing() == TICK_SPACING, 1);
        assert!(pool.liquidity() == 0, 2);

        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(test_factory);
        destroy(clk);
        scenario.end();
    }

    #[test]
    fun test_add_liquidity() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        // Create pool
        scenario.next_tx(DEPLOYER);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        // Create position with wider range to ensure current tick is inside
        scenario.next_tx(LP);
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            TICK_LOWER,
            TICK_UPPER,
            scenario.ctx()
        );

        // Add liquidity
        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            LIQUIDITY,
            true,
            &clk,
            scenario.ctx()
        );

        // Get required amounts
        let (pay_amount_a, pay_amount_b) = pool_mod::add_liquidity_pay_amount(&add_liquidity_receipt);
        
        // Repay liquidity
        let coin_a = coins_setups.mint<TEST_COIN_B>(pay_amount_a, scenario.ctx());
        let coin_b = coins_setups.mint<TEST_COIN_A>(pay_amount_b, scenario.ctx());
        
        pool_mod::repay_add_liquidity(
            &cfg,
            &mut pool,
            coin_a.into_balance(),
            coin_b.into_balance(),
            add_liquidity_receipt
        );

        // Verify state after adding liquidity
        assert!(pool.liquidity() > 0, 0);
        assert!(position.liquidity() > 0, 1);

        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(test_factory);
        destroy(clk);
        destroy(position);
        destroy(coins_setups);

        scenario.end();
    }

    #[test]
    fun test_remove_liquidity() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        // Setup pool with liquidity
        scenario.next_tx(DEPLOYER);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        // Add initial liquidity
        scenario.next_tx(LP);
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            TICK_LOWER,
            TICK_UPPER,
            scenario.ctx()
        );

        let add_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            LIQUIDITY,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_a, pay_b) = pool_mod::add_liquidity_pay_amount(&add_receipt);
        let coin_a = coins_setups.mint<TEST_COIN_B>(pay_a, scenario.ctx());
        let coin_b = coins_setups.mint<TEST_COIN_A>(pay_b, scenario.ctx());
        
        pool_mod::repay_add_liquidity(
            &cfg,
            &mut pool,
            coin_a.into_balance(),
            coin_b.into_balance(),
            add_receipt
        );

        // Remove liquidity
        scenario.next_tx(LP);
        let initial_liquidity = (position.liquidity() as u128);
        let (balance_a, balance_b) = pool_mod::remove_liquidity(
            &cfg,
            &mut pool,
            &mut position,
            initial_liquidity,
            &clk
        );

        // Verify state after removal
        assert!(position.liquidity() == 0, 0);
        assert!(pool.liquidity() == 0, 1);

        // Destroy the returned balances
        let coin_a = coin::from_balance(balance_a, scenario.ctx());
        let coin_b = coin::from_balance(balance_b, scenario.ctx());

        destroy(coin_a);
        destroy(coin_b);

        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(test_factory);
        destroy(clk);
        destroy(position);
        destroy(coins_setups);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::tick::ErrTickNotFound)]
    fun test_remove_zero_liquidity() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        // Create position without adding any liquidity
        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            TICK_LOWER,
            TICK_UPPER,
            scenario.ctx()
        );

        // Try to remove liquidity directly (should fail with ErrLiquidityIsZero)
        let (balance_a, balance_b) = pool_mod::remove_liquidity(
            &cfg,
            &mut pool,
            &mut position,
            1u128,  // Try to remove some liquidity
            &clk
        );

        // Cleanup
        let coin_a = coin::from_balance(balance_a, scenario.ctx());
        let coin_b = coin::from_balance(balance_b, scenario.ctx());
        destroy(coin_a);
        destroy(coin_b);
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(clk);

        scenario.end();
    }

    #[test]
    fun test_valid_sqrt_price_range() {
        let min_price = tick_math::min_sqrt_price();
        let max_price = tick_math::max_sqrt_price();
        
        // Your INIT_SQRT_PRICE should be between these values
        assert!(INIT_SQRT_PRICE >= min_price, 0);
        assert!(INIT_SQRT_PRICE <= max_price, 1);
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::rewarder::ErrRewardNotExist)]
    fun test_update_pool_emission_reward_not_exists() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());
        let rewarder_vault_id = rewarder::init_for_test(scenario.ctx());

        let mut coins_setup = setup_coins::setup(scenario.ctx());
        let coin_a = coins_setup.mint<TEST_COIN_A>(86400_000000, scenario.ctx());

        // Create pool
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(DEPLOYER);
        pool_mod::initialize_rewarder<TEST_COIN_B, TEST_COIN_A, TEST_COIN_A>(&cfg, &mut pool, scenario.ctx());

        let mut vault = scenario.take_shared_by_id<rewarder::RewarderGlobalVault>(rewarder_vault_id);

        let emissions_per_sec_q64 = 1000000 << 64;
        pool_mod::update_emission<TEST_COIN_B, TEST_COIN_A, TEST_COIN_A>(&cfg, &mut pool, &vault, emissions_per_sec_q64, &clk, scenario.ctx());

        // rewarder::deposit_reward(&cfg, &mut vault, coin_a.into_balance());
        // rewarder::update_emission(&mut vault, reward_manager, growth, emissions_per_sec_q64, update_time)

        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(test_factory);
        destroy(clk);
        destroy(coin_a);
        destroy(coins_setup);
        destroy(vault);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::rewarder::ErrRewardAmountInsufficient)]
    fun test_update_pool_emission_insuffient_rewards() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());
        let rewarder_vault_id = rewarder::init_for_test(scenario.ctx());

        let mut coins_setup = setup_coins::setup(scenario.ctx());
        let coin_a = coins_setup.mint<TEST_COIN_A>(86400_000000 - 1, scenario.ctx());

        // Create pool
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(DEPLOYER);
        pool_mod::initialize_rewarder<TEST_COIN_B, TEST_COIN_A, TEST_COIN_A>(&cfg, &mut pool, scenario.ctx());

        let mut vault = scenario.take_shared_by_id<rewarder::RewarderGlobalVault>(rewarder_vault_id);
        rewarder::deposit_reward(&cfg, &mut vault, coin_a.into_balance());
        let emissions_per_sec_q64 = 1000000 << 64;
        pool_mod::update_emission<TEST_COIN_B, TEST_COIN_A, TEST_COIN_A>(&cfg, &mut pool, &vault, emissions_per_sec_q64, &clk, scenario.ctx());


        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(test_factory);
        destroy(clk);
        destroy(coins_setup);
        destroy(vault);
        scenario.end();
    }

    #[test]
    fun test_update_pool_emission() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let clk = clock::create_for_testing(scenario.ctx());
        let (cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());
        let rewarder_vault_id = rewarder::init_for_test(scenario.ctx());

        let mut coins_setup = setup_coins::setup(scenario.ctx());
        let coin_a = coins_setup.mint<TEST_COIN_A>(86400_000000, scenario.ctx());

        // Create pool
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            TICK_SPACING,
            INIT_SQRT_PRICE,
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(DEPLOYER);
        pool_mod::initialize_rewarder<TEST_COIN_B, TEST_COIN_A, TEST_COIN_A>(&cfg, &mut pool, scenario.ctx());

        let mut vault = scenario.take_shared_by_id<rewarder::RewarderGlobalVault>(rewarder_vault_id);
        rewarder::deposit_reward(&cfg, &mut vault, coin_a.into_balance());
        let emissions_per_sec_q64 = 1000000 << 64;
        pool_mod::update_emission<TEST_COIN_B, TEST_COIN_A, TEST_COIN_A>(&cfg, &mut pool, &vault, emissions_per_sec_q64, &clk, scenario.ctx());


        destroy(cfg);
        destroy(admin_cap);
        destroy(pool);
        destroy(test_factory);
        destroy(clk);
        destroy(coins_setup);
        destroy(vault);
        scenario.end();
    }

    #[test]
    fun test_collect_swap_fee() {
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

        scenario.next_tx(liquidity_provider);
        let (balance_a, balance_b) = pool_mod::collect_fee(&cfg, &mut pool, &position, true);
        let mut swap_fee = swap_amount * 2 / 10;
        swap_fee =  swap_fee - swap_fee / 10;
        if (swap_fee > balance_a.value()) {
            assert!(swap_fee - balance_a.value() < 10);
        } else {
            assert!(balance_a.value() - swap_fee < 10);
        };
        assert!(balance_b.value() == 0);

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
        destroy(balance_a);
        destroy(balance_b);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = clmm_math::ErrMultiplicationOverflow)]
    fun test_522_attack() {
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
        let mut test_coin_a = coins_setups.mint<TEST_COIN_A>(10000000000000000, scenario.ctx());
        let mut test_coin_b = coins_setups.mint<TEST_COIN_B>(10000000000000000, scenario.ctx());

        // Create pool and add liquidity
        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x10000000000000000,
            &clk,
            scenario.ctx()
        );

        let mut position = pool_mod::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            i32::neg_from(10).as_u32(),
            10,
            scenario.ctx()
        );

        let add_liquidity_receipt = pool_mod::add_liquidity_fix_coin<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            &mut position,
            test_coin_b.value() * 9 / 10,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_amount_b, pay_amount_a) = pool_mod::add_liquidity_pay_amount<TEST_COIN_B, TEST_COIN_A>(&add_liquidity_receipt);
        pool_mod::repay_add_liquidity<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            test_coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            test_coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        // Perform swap and check fees
        let adversary = @0x3333;
        scenario.next_tx(adversary);
        let (amount_a, amount_b) = pool_mod::balances<TEST_COIN_B, TEST_COIN_A>(&pool);
        let (balance_a, balance_b, swap_receipt) = pool_mod::flash_swap(&cfg, &mut pool, true, true, amount_a - 10, tick_math::min_sqrt_price(), &clk);
        let mut adv_position = pool_mod::open_position(&cfg, &mut pool, 300000, 300200, scenario.ctx());
        let adv_add_receipt = pool_mod::add_liquidity(&cfg, &mut pool, &mut adv_position, 10365647984364446732462244378333008, &clk, scenario.ctx());
        let (a, b) = pool_mod::add_liquidity_pay_amount(&adv_add_receipt);
        std::debug::print(&a);
        std::debug::print(&b);
        destroy(adv_add_receipt);
        destroy(swap_receipt);

        // let mut up: u256 = 2905647984364446732333008;
        // let mut down: u256 = 2905647984364446732333008;
        // let mut binary = false;
        // while () {
        //     let a = clmm_math::get_delta_a(tick_math::get_sqrt_price_at_tick(i32::from(300000)), tick_math::get_sqrt_price_at_tick(i32::from(300200)), x, true);
        //     if (!binary) {
        //         if (a > amount_a) {
        //             binary = true;
        //             continue
        //         } else {
        //             x = x * 2;
        //         };
        //     } else {
        //         if (a > amount_a) {

        //         };
        //     }
        // };
        let (l, _, _) = clmm_math::get_liquidity_by_amount(i32::from(300000), i32::from(300200), pool_mod::current_tick_index(&pool), pool_mod::current_sqrt_price(&pool), amount_a -1, true);
        std::debug::print(&l);
        let (out_balance_a1, out_balance_b1) = pool_mod::remove_liquidity(&cfg, &mut pool, &mut adv_position, l, &clk);

        std::debug::print(&out_balance_a1.value());
        std::debug::print(&out_balance_b1.value());
        destroy(out_balance_a1);
        destroy(out_balance_b1);
        destroy(adv_position);


        // Cleanup
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(clk);
        destroy(test_coin_a);
        destroy(test_coin_b);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(balance_a);
        destroy(balance_b);

        scenario.end();
    }
}
