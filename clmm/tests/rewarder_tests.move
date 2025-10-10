#[test_only]
module magma_clmm::rewarder_tests {
    use sui::test_scenario;
    use sui::test_utils::destroy;
    use sui::clock;
    use sui::coin;
    use sui::balance;
    use sui::transfer;
    use sui::object;

    use magma_clmm::config;
    use magma_clmm::factory;
    use magma_clmm::pool::{Self, Pool};
    use magma_clmm::position;
    use magma_clmm::rewarder::{Self, RewarderManager};
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::test_coin_magma::{Self, TEST_COIN_MAGMA};
    use magma_clmm::setup_coins;

    const INITIAL_AMOUNT: u64 = 1000000000000;
    const LIQUIDITY_AMOUNT: u64 = 1000000000;
    const REWARD_AMOUNT: u64 = 100000000000;
    const REWARD_DURATION: u64 = 86400; // 1 day

    #[test]
    fun test_rewarder_lifecycle() {
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

        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000,
            &clk,
            scenario.ctx()
        );

        // Create position and add liquidity
        let mut position = pool::open_position<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            &mut pool,
            12330,
            12350,
            scenario.ctx()
        );

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

        // Initialize rewarder
        let rewarder_vault_id = rewarder::init_for_test(scenario.ctx());
        scenario.next_tx(deployer);
        let mut rewarder_vault = test_scenario::take_shared<rewarder::RewarderGlobalVault>(&scenario);

        // Create reward coins and add to vault (small amount)
        let reward_coins = coin::mint_for_testing<TEST_COIN_MAGMA>(REWARD_AMOUNT, scenario.ctx());
        let reward_balance = coin::into_balance(reward_coins);
        rewarder::test_add_reward_balance(&mut rewarder_vault, reward_balance);

        // Add rewarder for TEST_COIN_MAGMA
        rewarder::add_rewarder<TEST_COIN_MAGMA>(pool::borrow_rewarder_manager_mut_test(&mut pool));

        // Verify initial state
        assert!(rewarder::balance_of<TEST_COIN_MAGMA>(&rewarder_vault) == 100000000000, 0);
        assert!(rewarder::last_update_time(pool::borrow_rewarder_manager_test(&pool)) == 0, 1);

        // Update emission rate
        let emissions_per_sec = ((REWARD_AMOUNT as u128) / (REWARD_DURATION as u128)) << 64;
        let liquidity = pool::liquidity(&pool);
        let rewarder_manager = pool::borrow_rewarder_manager_mut_test(&mut pool);
        rewarder::update_emission<TEST_COIN_MAGMA>(
            &rewarder_vault,
            rewarder_manager,
            liquidity,
            emissions_per_sec,
            clock::timestamp_ms(&clk) / 1000
        );

        // Verify updated state
        let rewarder = rewarder::borrow_rewarder<TEST_COIN_MAGMA>(pool::borrow_rewarder_manager_test(&pool));
        assert!(rewarder::emissions_per_second(rewarder) == emissions_per_sec, 2);

        // Cleanup
        destroy(position);
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(coins_setups);
        destroy(clk);
        destroy(coin_a);
        destroy(coin_b);
        test_scenario::return_shared(rewarder_vault);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::rewarder::ErrRewardAmountInsufficient)]
    fun test_insufficient_reward_amount() {
        let deployer = @0xFFFF;
        let mut scenario = test_scenario::begin(deployer);
        let clk = clock::create_for_testing(scenario.ctx());
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Create pool with rewarder
        let mut test_factory = factory::build_test_factory(scenario.ctx());
        let mut pool = test_factory.t_create_pool<TEST_COIN_B, TEST_COIN_A>(
            &cfg,
            10,
            0x1da90654c407ac000,
            &clk,
            scenario.ctx()
        );

        // Initialize rewarder
        let rewarder_vault_id = rewarder::init_for_test(scenario.ctx());
        scenario.next_tx(deployer);
        let mut rewarder_vault = test_scenario::take_shared<rewarder::RewarderGlobalVault>(&scenario);

        // Create reward coins and add to vault (small amount)
        let reward_coins = coin::mint_for_testing<TEST_COIN_MAGMA>(100000000, scenario.ctx());
        let reward_balance = coin::into_balance(reward_coins);
        rewarder::test_add_reward_balance(&mut rewarder_vault, reward_balance);

        // Add rewarder for TEST_COIN_MAGMA
        rewarder::add_rewarder<TEST_COIN_MAGMA>(pool::borrow_rewarder_manager_mut_test(&mut pool));

        // Try to set emission rate without sufficient rewards
        // This should fail because the reward amount is too small
        rewarder::update_emission<TEST_COIN_MAGMA>(
            &rewarder_vault,
            pool::borrow_rewarder_manager_mut_test(&mut pool),
            1000000,  // liquidity
            1000000 << 64,  // emissions per second (scaled by Q64)
            clock::timestamp_ms(&clk) / 1000
        );

        // Cleanup
        destroy(pool);
        destroy(cfg);
        destroy(admin_cap);
        destroy(test_factory);
        destroy(clk);
        test_scenario::return_shared(rewarder_vault);

        scenario.end();
    }
} 