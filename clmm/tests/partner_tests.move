#[test_only]
module magma_clmm::partner_tests {
    use sui::test_scenario;
    use sui::test_utils::destroy;
    use sui::clock;
    use sui::coin::{Self, Coin};

    use magma_clmm::config;
    use magma_clmm::partner;
    use magma_clmm::factory;
    use magma_clmm::pool;
    use magma_clmm::rewarder;
    use magma_clmm::position;
    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::setup_coins;
    use integer_mate::i32;

    const DEPLOYER: address = @0xFFFF;
    const LP: address = @0xCAFE;
    const TICK_SPACING: u32 = 10;
    const INIT_SQRT_PRICE: u128 = 0x1da90654c407ac000;
    const LIQUIDITY: u64 = 1000000000;
    const SWAP_AMOUNT: u64 = 100000000;
    const TICK_LOWER: u32 = 12000;
    const TICK_UPPER: u32 = 13000;

    #[test]
    fun test_create_partner() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let mut partners = partner::init_for_test(scenario.ctx());
        let (mut cfg, config_admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());

        clk.increment_for_testing(1000000);
        let start = clk.timestamp_ms() / 1000;
        scenario.next_tx(DEPLOYER);
        partner::create_partner(&cfg, &mut partners, b"test".to_string(), 10, start, start + 1, DEPLOYER, &clk, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
        let mut partner = scenario.take_shared<partner::Partner>();

        assert!(partner.ref_fee_rate() == 10);
        assert!(partner.start_time() == start);
        assert!(partner.end_time() == start + 1);

        assert!(partner.current_ref_fee_rate(clk.timestamp_ms() / 1000) == 10);
        clk.increment_for_testing(2000);
        assert!(partner.current_ref_fee_rate(clk.timestamp_ms() / 1000) == 0);

        scenario.next_tx(DEPLOYER);
        partner::update_time_range(&cfg, &mut partner, clk.timestamp_ms() / 1000, clk.timestamp_ms() / 1000 + 30, &clk, scenario.ctx());

        clk.increment_for_testing(1000);
        scenario.next_tx(DEPLOYER);
        partner::update_ref_fee_rate(&cfg, &mut partner, 25, scenario.ctx());
        assert!(partner.current_ref_fee_rate(clk.timestamp_ms() / 1000) == 25);

        destroy(cfg);
        destroy(config_admin_cap);
        destroy(partners);
        destroy(partner);
        destroy(partner_cap);
        destroy(clk);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = magma_clmm::partner::ErrInvalidEndTime)]
    fun test_update_partner_invalid_time_range() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let mut partners = partner::init_for_test(scenario.ctx());
        let (mut cfg, config_admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());

        clk.increment_for_testing(1000000);
        let start = clk.timestamp_ms() / 1000;
        scenario.next_tx(DEPLOYER);
        partner::create_partner(&cfg, &mut partners, b"test".to_string(), 10, start, start + 1, DEPLOYER, &clk, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
        let mut partner = scenario.take_shared<partner::Partner>();



        scenario.next_tx(DEPLOYER);
        partner::update_time_range(&cfg, &mut partner, start - 10, start, &clk, scenario.ctx());


        destroy(cfg);
        destroy(config_admin_cap);
        destroy(partners);
        destroy(partner);
        destroy(partner_cap);
        destroy(clk);

        scenario.end();
    }

    #[test]
    fun test_receive_ref_fee() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let mut partners = partner::init_for_test(scenario.ctx());
        let (mut cfg, config_admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());

        let mut coins_setup = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setup.mint<TEST_COIN_A>(1000000000, scenario.ctx());

        clk.increment_for_testing(1000000);
        let start = clk.timestamp_ms() / 1000;
        scenario.next_tx(DEPLOYER);
        partner::create_partner(&cfg, &mut partners, b"test".to_string(), 10, start, start + 1, DEPLOYER, &clk, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
        let mut partner = scenario.take_shared<partner::Partner>();

        scenario.next_tx(DEPLOYER);
        partner.receive_ref_fee(coin_a.into_balance());

        destroy(cfg);
        destroy(coins_setup);
        destroy(config_admin_cap);
        destroy(partners);
        destroy(partner);
        destroy(partner_cap);
        destroy(clk);

        scenario.end();
    }

    #[test]
    fun test_claim_ref_fee() {
        let mut scenario = test_scenario::begin(DEPLOYER);
        let mut clk = clock::create_for_testing(scenario.ctx());
        let mut partners = partner::init_for_test(scenario.ctx());
        let (mut cfg, config_admin_cap) = config::create_config_with_fee_rates(0, 0, vector[], scenario.ctx());

        let mut coins_setup = setup_coins::setup(scenario.ctx());
        let mut coin_a = coins_setup.mint<TEST_COIN_A>(1000000000, scenario.ctx());

        clk.increment_for_testing(1000000);
        let start = clk.timestamp_ms() / 1000;
        scenario.next_tx(DEPLOYER);
        partner::create_partner(&cfg, &mut partners, b"test".to_string(), 10, start, start + 1, DEPLOYER, &clk, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
        let mut partner = scenario.take_shared<partner::Partner>();

        scenario.next_tx(DEPLOYER);
        partner.receive_ref_fee(coin_a.into_balance());

        scenario.next_tx(DEPLOYER);
        partner::claim_ref_fee<TEST_COIN_A>(&cfg, &partner_cap, &mut partner, scenario.ctx());
        scenario.next_tx(DEPLOYER);
        let n_coina = scenario.take_from_sender<Coin<TEST_COIN_A>>();
        assert!(n_coina.value() == 1000000000);

        destroy(cfg);
        destroy(n_coina);
        destroy(coins_setup);
        destroy(config_admin_cap);
        destroy(partners);
        destroy(partner);
        destroy(partner_cap);
        destroy(clk);

        scenario.end();
    }
}
