#[test_only]
module magma_clmm::test_coin_a {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use sui::test_utils;

    public struct TEST_COIN_A has drop {}

    public fun initialize(decimal: u8, ctx: &mut TxContext): (TreasuryCap<TEST_COIN_A>, CoinMetadata<TEST_COIN_A>) {
        let otw = test_utils::create_one_time_witness<TEST_COIN_A>();
        let (treasury, metadata) = coin::create_currency(otw, decimal, b"", b"", b"", option::none(), ctx);
        (treasury, metadata)
    }
}

#[test_only]
module magma_clmm::test_coin_b {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use sui::test_utils;

    public struct TEST_COIN_B has drop {}

    public fun initialize(decimal: u8, ctx: &mut TxContext): (TreasuryCap<TEST_COIN_B>, CoinMetadata<TEST_COIN_B>) {
        let otw = test_utils::create_one_time_witness<TEST_COIN_B>();
        let (treasury, metadata) = coin::create_currency(otw, decimal, b"", b"", b"", option::none(), ctx);
        (treasury, metadata)
    }
}

#[test_only]
module magma_clmm::test_coin_magma {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use sui::test_utils;

    public struct TEST_COIN_MAGMA has drop {}

    public fun initialize(decimal: u8, ctx: &mut TxContext): (TreasuryCap<TEST_COIN_MAGMA>, CoinMetadata<TEST_COIN_MAGMA>) {
        let otw = test_utils::create_one_time_witness<TEST_COIN_MAGMA>();
        let (treasury, metadata) = coin::create_currency(otw, decimal, b"", b"", b"", option::none(), ctx);
        (treasury, metadata)
    }
}

#[test_only]
module magma_clmm::setup_coins {
    use std::type_name::{Self, TypeName};
    use sui::bag::{Self, Bag};
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::tx_context::TxContext;

    use magma_clmm::test_coin_a::{Self, TEST_COIN_A};
    use magma_clmm::test_coin_b::{Self, TEST_COIN_B};
    use magma_clmm::test_coin_magma::{Self, TEST_COIN_MAGMA};

    const DECIMAL: u8 = 6;

    public struct CoinsSetups {
        treasury_caps: Bag,
        coin_metadatas: Bag,
    }

    public fun setup(ctx: &mut TxContext): CoinsSetups {
        let (treasury_cap_a, metadata_a) = test_coin_a::initialize(DECIMAL, ctx);
        let (treasury_cap_b, metadata_b) = test_coin_b::initialize(DECIMAL, ctx);
        let (treasury_cap_magma, metadata_magma) = test_coin_magma::initialize(DECIMAL, ctx);

        let mut cs = CoinsSetups {
            treasury_caps: bag::new(ctx),
            coin_metadatas: bag::new(ctx),
        };

        bag::add(&mut cs.treasury_caps, type_name::get<TEST_COIN_A>(), treasury_cap_a);
        bag::add(&mut cs.treasury_caps, type_name::get<TEST_COIN_B>(), treasury_cap_b);
        bag::add(&mut cs.treasury_caps, type_name::get<TEST_COIN_MAGMA>(), treasury_cap_magma);

        bag::add(&mut cs.coin_metadatas, type_name::get<TEST_COIN_A>(), metadata_a);
        bag::add(&mut cs.coin_metadatas, type_name::get<TEST_COIN_B>(), metadata_b);
        bag::add(&mut cs.coin_metadatas, type_name::get<TEST_COIN_MAGMA>(), metadata_magma);

        cs
    }

    public fun mint<C>(self: &mut CoinsSetups, amount: u64, ctx: &mut TxContext): Coin<C> {
        coin::mint(
            bag::borrow_mut(&mut self.treasury_caps, type_name::get<C>()),
            amount,
            ctx
        )
    }
}
