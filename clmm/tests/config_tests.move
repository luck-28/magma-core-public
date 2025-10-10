#[test_only]
module magma_clmm::config_tests {
    use sui::test_scenario;
    use sui::test_utils::destroy;
    use sui::clock;

    use magma_clmm::config;
    use magma_clmm::acl;

    const ADMIN: address = @0xFFFF;
    const USER: address = @0xCAFE;

    #[test]
    fun test_create_config() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (cfg, admin_cap) = config::create_config(scenario.ctx());

        // Test default values
        assert!(config::protocol_fee_rate(&cfg) == 0, 0);
        assert!(config::unstaked_liquidity_fee_rate(&cfg) == 1000, 0); // 10%
        assert!(config::fee_rate_denom() == 1000000, 0);
        assert!(config::max_fee_rate() == 200000, 0);
        assert!(config::max_protocol_fee_rate() == 3000, 0);

        // Test ACL initialization
        let members = config::get_members(&cfg);
        assert!(vector::length(&members) == 1, 1); // Only admin
        let admin_member = vector::borrow(&members, 0);
        assert!(acl::get_permission(config::acl(&cfg), ADMIN) != 0, 2);

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_add_fee_tier() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Add new fee tier with a different tick spacing
        let tick_spacing = 20;
        let fee_rate = 100000; // 10%
        config::add_fee_tier(&mut cfg, tick_spacing, fee_rate, scenario.ctx());

        // Verify fee tier
        assert!(config::get_fee_rate(tick_spacing, &cfg) == fee_rate, 0);

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::config::ErrFeeTierAlreadyExist)]
    fun test_add_duplicate_fee_tier() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let tick_spacing = 20;
        let fee_rate = 100000;
        
        // Add fee tier twice
        config::add_fee_tier(&mut cfg, tick_spacing, fee_rate, scenario.ctx());
        config::add_fee_tier(&mut cfg, tick_spacing, fee_rate, scenario.ctx());

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_update_unstaked_liquidity_fee_rate() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        let new_rate = 2000; // 20%
        config::update_unstaked_liquidity_fee_rate(&mut cfg, new_rate, scenario.ctx());
        assert!(config::unstaked_liquidity_fee_rate(&cfg) == new_rate, 0);

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::config::ErrInvalidUnstakedLiquidityFeeRate)]
    fun test_update_unstaked_liquidity_fee_rate_invalid() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Try to set rate higher than max (10000)
        config::update_unstaked_liquidity_fee_rate(&mut cfg, 10001, scenario.ctx());

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_acl_roles() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Test adding roles
        scenario.next_tx(ADMIN);
        config::add_role(&admin_cap, &mut cfg, USER, 0); // POOL_MANAGER_ROLE is 0
        
        // Verify role was added
        assert!(acl::has_role(config::acl(&cfg), USER, 0), 0);

        // Test removing roles
        scenario.next_tx(ADMIN);
        config::remove_role(&admin_cap, &mut cfg, USER, 0);
        
        // Verify role was removed
        assert!(!acl::has_role(config::acl(&cfg), USER, 0), 1);

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::config::ErrPackageVersionDeprecated)]
    fun test_package_version() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut cfg, admin_cap) = config::create_config(scenario.ctx());

        // Test updating package version
        let new_version = 2;
        config::update_package_version(&admin_cap, &mut cfg, new_version);
        
        // Should abort on next operation due to version check
        scenario.next_tx(ADMIN);
        config::checked_package_version(&cfg); // This will abort if version doesn't match

        destroy(cfg);
        destroy(admin_cap);
        scenario.end();
    }

    #[test]
    fun test_epochs() {
        let ts = 86400 * 7 + 1;
        assert!(config::epoch(ts) == 1);
        assert!(config::epoch_next(ts) == config::week() * 2);
        assert!(config::epoch_start(ts) == config::week());
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::config::ErrFeeTierNotFound)]
    fun test_delete_fee_tier() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[config::create_fee_tier(10, 10000)], scenario.ctx());
        config.delete_fee_tier(10, scenario.ctx());

        config::get_fee_rate(10, &config);

        destroy(admin_cap);
        destroy(config);
        scenario.end();
    }

    #[test]
    fun test_add_role() {
        let mut scenario = test_scenario::begin(ADMIN);
        let (mut config, admin_cap) = config::create_config_with_fee_rates(0, 0, vector[config::create_fee_tier(10, 10000)], scenario.ctx());

        config::add_role(&admin_cap, &mut config, USER, 3);
        config::check_partner_manager_role(&config, USER);

        destroy(admin_cap);
        destroy(config);
        scenario.end();
    }
}
