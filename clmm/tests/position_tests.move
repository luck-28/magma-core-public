#[test_only]
module magma_clmm::position_tests {
    use sui::test_scenario;
    use sui::test_utils::destroy;
    use sui::clock;
    use sui::coin;

    use magma_clmm::config;
    use magma_clmm::factory;
    use magma_clmm::pool;
    use magma_clmm::position;
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B}; 
    use magma_clmm::setup_coins;
    use integer_mate::i32;

    const INITIAL_AMOUNT: u64 = 1000000000000;
    const LIQUIDITY_AMOUNT: u64 = 1000000000;

    #[test]
    fun test_position_lifecycle() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        // Initialize test scenario
        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Setup test coins
        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(INITIAL_AMOUNT, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(INITIAL_AMOUNT, scenario.ctx());

        // Create factory and pool
        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000, // Initial sqrt price
            &clk,
            scenario.ctx()
        );

        // Test position creation
        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position = pool::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Verify position properties
        let (lower, upper) = position::tick_range(&position);
        assert!(i32::eq(lower, i32::from(tick_lower)), 0);
        assert!(i32::eq(upper, i32::from(tick_upper)), 1);
        assert!(position::liquidity(&position) == 0, 2);

        assert!(pool.is_position_exist(object::id(&position)));

        // Test adding liquidity
        let add_liquidity_receipt = pool::add_liquidity_fix_coin(
            &cfg,
            &mut pool,
            &mut position,
            LIQUIDITY_AMOUNT,
            true,
            &clk,
            scenario.ctx()
        );

        let (pay_amount_b, pay_amount_a) = pool::add_liquidity_pay_amount(&add_liquidity_receipt);
        pool::repay_add_liquidity(
            &cfg,
            &mut pool,
            coin_b.split(pay_amount_b, scenario.ctx()).into_balance(),
            coin_a.split(pay_amount_a, scenario.ctx()).into_balance(),
            add_liquidity_receipt
        );

        // Verify liquidity was added
        assert!(position::liquidity(&position) > 0, 3);

        // Test removing liquidity
        let liquidity_to_remove = position::liquidity(&position);
        let (balance_a, balance_b) = pool::remove_liquidity(
            &cfg,
            &mut pool,
            &mut position,
            liquidity_to_remove,
            &clk
        );
        let removed_a = coin::from_balance(balance_a, scenario.ctx());
        let removed_b = coin::from_balance(balance_b, scenario.ctx());

        // Verify all liquidity was removed
        assert!(position::liquidity(&position) == 0, 4);
        assert!(removed_a.value() > 0 || removed_b.value() > 0, 5);

        // Close position
        pool::close_position(&cfg, &mut pool, position);

        // Cleanup
        destroy(removed_a);
        destroy(removed_b);
        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(pool);
        destroy(coins_setups);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::position::ErrInvalidPositionTickRange)]
    fun test_invalid_tick_range() {
        let deployer = @0xFFFF;
        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        // Try to create position with invalid tick range
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000,
            &clk,
            scenario.ctx()
        );

        // This should fail because upper tick is lower than lower tick
        let position = pool::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            12350, // Higher tick
            12330, // Lower tick
            scenario.ctx()
        );

        destroy(position);

        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(pool);
        destroy(clk);
        scenario.end();
    }

    #[test]
    fun test_open_position_with_neg_tick() {
        let deployer = @0xFFFF;
        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        // -10000: 0.3678978343771642: 0x5e2e8d6eeb4d1400
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x5e2e8d6eeb4d1400,
            &clk,
            scenario.ctx()
        );


        let tick_lower = i32::neg_from(10100).as_u32();
        let tick_upper = i32::neg_from(9900).as_u32();

        // This should fail because upper tick is lower than lower tick
        let position = pool::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        destroy(position);

        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(pool);
        destroy(clk);
        scenario.end();
    }

    #[test]
    fun test_position_manager_fetch_positions() {
        let deployer = @0xFFFF;
        let liquidity_provider = @0xCAFE;

        // Initialize test scenario
        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Setup test coins
        let mut coins_setups = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setups.mint<TEST_COIN_A>(INITIAL_AMOUNT, scenario.ctx());
        let mut coin_b = coins_setups.mint<TEST_COIN_B>(INITIAL_AMOUNT, scenario.ctx());

        // Create factory and pool
        scenario.next_tx(deployer);
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(liquidity_provider);
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000, // Initial sqrt price
            &clk,
            scenario.ctx()
        );

        scenario.next_tx(liquidity_provider);
        let tick_lower = 12330;
        let tick_upper = 12350;
        let mut position1 = pool::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );
        let mut position2 = pool::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            tick_upper,
            tick_upper + 50,
            scenario.ctx()
        );

        assert!(pool.fetch_positions(vector[], 1).length() == 1);
        assert!(pool.fetch_positions(vector[], 2).length() == 2);
        assert!(pool.fetch_positions(vector[], 3).length() == 2);

        assert!(pool.fetch_positions(vector[object::id(&position1)], 1).length() == 1);
        assert!(pool.fetch_positions(vector[object::id(&position1)], 2).length() == 2);


        // Cleanup
        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(pool);
        destroy(coins_setups);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        destroy(position1);
        destroy(position2);

        scenario.end();
    }
}
