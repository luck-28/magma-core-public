#[test_only]
module magma_clmm::factory_tests {
    use sui::test_scenario;
    use sui::test_utils::destroy;
    use sui::clock;
    use sui::coin;
    use sui::balance;

    use integer_mate::i32;
    use magma_clmm::config;
    use magma_clmm::factory;
    use magma_clmm::pool::{Self as pool_mod, Pool};
    use magma_clmm::position;
    use magma_clmm::tick_math;
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::setup_coins;

    const DEPLOYER: address = @0xffff;

    public struct COIN_A has drop {}
    public struct COIN_B has drop {}
    public struct COIN_C has drop {}

    #[test]
    fun test_create_pool() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[config::create_fee_tier(10, 10)], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        assert!(test_factory.borrow_pools().index() == 0);
        scenario.next_tx(DEPLOYER);
        let pool_id = factory::create_pool<COIN_B, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());
        assert!(test_factory.borrow_pools().index() == 1);
        scenario.next_tx(DEPLOYER);
        let pool = scenario.take_shared<Pool<COIN_B, COIN_A>>();
        assert!(object::id(&pool) == pool_id);
        let pool_ = factory::create_pool_<COIN_C, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());
        assert!(test_factory.borrow_pools().index() == 2);

        destroy(admin_cap);
        destroy(pool);
        destroy(pool_);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::factory::ErrPoolAlreadyExisted)]
    fun test_create_pool_repeated() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[config::create_fee_tier(10, 10)], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(DEPLOYER);
        let pool_id = factory::create_pool<COIN_B, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let pool = scenario.take_shared<Pool<COIN_B, COIN_A>>();
        assert!(object::id(&pool) == pool_id);
        let pool_ = factory::create_pool_<COIN_B, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());

        destroy(admin_cap);
        destroy(pool);
        destroy(pool_);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::factory::ErrInvalidSqrtPrice)]
    fun test_create_pool_with_invalid_low_price() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(DEPLOYER);
        factory::create_pool<COIN_A, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, tick_math::min_sqrt_price() - 1, b"test".to_string(), &clk, scenario.ctx());

        destroy(admin_cap);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::factory::ErrInvalidSqrtPrice)]
    fun test_create_pool_with_invalid_high_price() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(DEPLOYER);
        factory::create_pool<COIN_A, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, tick_math::max_sqrt_price() + 1, b"test".to_string(), &clk, scenario.ctx());

        destroy(admin_cap);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::factory::ErrSameCoinType)]
    fun test_create_pool_with_the_same_token() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(DEPLOYER);
        factory::create_pool<COIN_A, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());

        destroy(admin_cap);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::factory::ErrInvalidCoinTypeSequence)]
    fun test_create_pool_invalid_sequence() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(DEPLOYER);
        factory::create_pool<COIN_A, COIN_B>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());

        destroy(admin_cap);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    fun test_fetch_pools() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[config::create_fee_tier(10, 10)], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        scenario.next_tx(DEPLOYER);
        let pool_id = factory::create_pool<COIN_B, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let pool_ = factory::create_pool_<COIN_C, COIN_A>(test_factory.borrow_pools_mut(), &config, 10, 12345000000, b"test".to_string(), &clk, scenario.ctx());

        scenario.next_tx(DEPLOYER);

        let pool_key = factory::new_pool_key<COIN_B, COIN_A>(10);
        let pool_key_ = factory::new_pool_key<COIN_C, COIN_A>(10);

        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[], 1).length() == 1);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[], 2).length() == 2);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[], 3).length() == 2);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[pool_key], 1).length() == 1);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[pool_key], 2).length() == 2);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[pool_key], 3).length() == 2);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[pool_key_], 1).length() == 1);
        assert!(factory::fetch_pools(test_factory.borrow_pools(), vector[pool_key_], 2).length() == 1);

        destroy(admin_cap);
        destroy(pool_);
        destroy(test_factory);
        destroy(config);
        destroy(clk);
        scenario.end();
    }

    #[test]
    fun test_create_pool_with_liquidity() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let (config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[config::create_fee_tier(10, 10)], scenario.ctx());
        let mut test_factory = factory::build_test_factory(scenario.ctx());

        let mut coins_setup = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setup.mint<TEST_COIN_A>(10000_000000, scenario.ctx());
        let mut coin_b = coins_setup.mint<TEST_COIN_B>(10000_000000, scenario.ctx());

        scenario.next_tx(DEPLOYER);
        let (position, coin_b, coin_a) = factory::create_pool_with_liquidity<TEST_COIN_B, TEST_COIN_A>(
            test_factory.borrow_pools_mut(),
            &config,
            10,
            tick_math::min_sqrt_price(),
            b"".to_string(),
            12340,
            12360,
            coin_b,
            coin_a,
            10_000000,
            0,
            true,
            &clk,
            scenario.ctx());

        scenario.next_tx(DEPLOYER);
        let pool = scenario.take_shared<Pool<TEST_COIN_B, TEST_COIN_A>>();

        destroy(admin_cap);
        destroy(test_factory);
        destroy(config);
        destroy(position);
        destroy(pool);
        destroy(coin_a);
        destroy(coin_b);
        destroy(coins_setup);
        destroy(clk);
        scenario.end();
    }
}
