# Magma CLMM

**High-Performance Concentrated Liquidity Market Maker on Sui Blockchain**

Magma CLMM is an advanced concentrated liquidity AMM protocol deployed on the Sui blockchain, enabling liquidity providers to concentrate capital within custom price ranges for optimal capital efficiency and maximized returns.

## Overview

Magma CLMM serves as the core trading engine of the Magma Protocol, delivering a comprehensive suite of decentralized exchange capabilities. The protocol empowers users to:

- Concentrate liquidity within targeted price ranges for enhanced capital efficiency
- Execute high-performance token swaps with minimal slippage
- Earn trading fees and multiple reward tokens simultaneously
- Manage positions through NFT-based ownership

## Architecture Highlights

### Core Components

- **Pool**: Central liquidity pool with swap execution engine and state management
- **Factory**: Automated pool creation and registry system
- **Position**: NFT-based position management with transferable ownership
- **Tick**: Price range discretization and liquidity tracking
- **Rewarder**: Multi-token incentive distribution system
- **Partner**: Referral fee-sharing mechanism for ecosystem partners
- **Config**: Protocol-wide configuration and permission system
- **ACL**: Granular role-based access control framework
- **Math Libraries**: Precision mathematical operations (CLMM Math, Tick Math)

### Distinctive Features

- **Concentrated Liquidity**: Providers deploy capital within specific price ranges for up to 4000x capital efficiency
- **Multi-Reward System**: Support for up to 5 concurrent reward token types per pool
- **NFT Position Tokens**: Positions are represented as transferable NFTs with full metadata
- **Dynamic Fee Tiers**: Flexible fee structures with protocol and referral fee components
- **Flash Operations**: Native flash swap and flash loan support for arbitrage and composability
- **Fine-Grained Permissions**: Role-based access control for protocol governance

## Getting Started

### Requirements

- **Sui CLI**: Version 1.41.1 or later
- **Move Language**: Edition 2024.beta

### Building and Testing

```bash
# Navigate to the CLMM directory
cd clmm

# Build the contracts
sui move build

# Run the complete test suite
sui move test

# Run specific test module
sui move test --test pool_tests
```

### Deployment

```bash
# Deploy to testnet
sui client publish --gas-budget 500000000

# Deploy to mainnet (ensure proper configuration)
sui client publish --gas-budget 500000000 --network mainnet
```

## Directory Structure

```
sources/
├── acl.move              # Access control and role management
├── config.move           # Global protocol configuration
├── factory.move          # Pool factory and registry
├── pool.move             # Core pool and swap logic
├── position.move         # Position NFT and management
├── rewarder.move         # Reward emission and distribution
├── partner.move          # Partner referral system
├── tick.move             # Tick-based liquidity tracking
├── utils.move            # Shared utility functions
└── math/
    ├── clmm_math.move    # Concentrated liquidity mathematics
    └── tick_math.move    # Price-tick conversion formulas

tests/
├── coins.move            # Test token implementations
├── config_tests.move     # Configuration tests
├── factory_tests.move    # Pool creation tests
├── fee_tests.move        # Fee calculation tests
├── partner_tests.move    # Partner system tests
├── pool_tests.move       # Core pool functionality tests
├── position_tests.move   # Position management tests
├── rewarder_tests.move   # Reward system tests
└── swap_tests.move       # Swap execution tests
```

## API Reference

This section provides comprehensive documentation for all public interfaces in the Magma CLMM protocol.

### Pool Module (`pool.move`)

The pool module contains the core trading and liquidity management logic.

#### Position Lifecycle

**Open a new position**
```move
public fun open_position<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    tick_lower: I32,
    tick_upper: I32,
    ctx: &mut TxContext,
): Position
```
Creates a new liquidity position NFT with specified tick range.

**Close a position**
```move
public fun close_position<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: Position,
)
```
Destroys an empty position NFT (must have zero liquidity and no unclaimed rewards).

#### Liquidity Operations

**Add liquidity by delta**
```move
public fun add_liquidity<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut Position,
    delta_liquidity: u128,
    clock: &Clock,
): AddLiquidityReceipt<CoinTypeA, CoinTypeB>
```
Adds liquidity by specifying the exact liquidity delta amount.

**Add liquidity with fixed coin amount**
```move
public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut Position,
    amount: u64,
    fix_amount_a: bool,
    clock: &Clock,
): AddLiquidityReceipt<CoinTypeA, CoinTypeB>
```
Adds liquidity by fixing one coin amount and calculating the required amount for the other coin.

**Repay liquidity addition**
```move
public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    balance_a: Balance<CoinTypeA>,
    balance_b: Balance<CoinTypeB>,
    receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>,
)
```
Completes the add liquidity operation by providing the required token balances.

**Remove liquidity**
```move
public fun remove_liquidity<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &mut Position,
    delta_liquidity: u128,
    clock: &Clock,
): (Balance<CoinTypeA>, Balance<CoinTypeB>)
```
Removes specified liquidity amount from position and returns corresponding token balances.

#### Fee and Reward Collection

**Collect trading fees**
```move
public fun collect_fee<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
    recalculate: bool,
    clock: &Clock,
): (Balance<CoinTypeA>, Balance<CoinTypeB>)
```
Claims accumulated trading fees from a position.

**Collect reward tokens**
```move
public fun collect_reward<CoinTypeA, CoinTypeB, RewardType>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
    vault: &mut RewarderGlobalVault,
    recalculate: bool,
    clock: &Clock,
): Balance<RewardType>
```
Claims a specific reward token from a position.

**Calculate and update fees**
```move
public fun calculate_and_update_fee<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
): (u64, u64)
```
Recalculates and updates accumulated fees for a position, returning the amounts.

**Calculate and update rewards**
```move
public fun calculate_and_update_rewards<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
    clock: &Clock,
): vector<u64>
```
Updates all reward accumulators for a position and returns amounts for each reward token.

**Calculate and update specific reward**
```move
public fun calculate_and_update_reward<CoinTypeA, CoinTypeB, RewardType>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
    clock: &Clock,
): u64
```
Updates a specific reward accumulator and returns the amount.

**Calculate and update points**
```move
public fun calculate_and_update_points<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
    clock: &Clock,
): u128
```
Updates the points accumulator for a position (used for time-weighted liquidity tracking).

**Calculate and update Magma distribution**
```move
public fun calculate_and_update_magma_distribution<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
): u64
```
Updates Magma token distribution rewards for a staked position.

#### Swap Operations

**Execute flash swap**
```move
public fun flash_swap<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
    clock: &Clock,
): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>)
```
Executes a flash swap, borrowing output tokens before paying input tokens.

**Execute flash swap with partner**
```move
public fun flash_swap_with_partner<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    partner: &Partner,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
    clock: &Clock,
): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>)
```
Flash swap with referral fee attribution to a partner.

**Repay flash swap**
```move
public fun repay_flash_swap<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    coin_a: Balance<CoinTypeA>,
    coin_b: Balance<CoinTypeB>,
    receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>,
)
```
Completes a flash swap by repaying the required tokens.

**Repay flash swap with partner**
```move
public fun repay_flash_swap_with_partner<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    partner: &mut Partner,
    coin_a: Balance<CoinTypeA>,
    coin_b: Balance<CoinTypeB>,
    receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>,
)
```
Completes a partner flash swap and distributes referral fees.

#### Pool Administration

**Initialize reward system**
```move
public fun initialize_rewarder<CoinTypeA, CoinTypeB, RewardType>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    ctx: &TxContext,
)
```
Initializes a new reward token slot for the pool (up to 5 reward types).

**Update reward emission rate**
```move
public fun update_emission<CoinTypeA, CoinTypeB, RewardType>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    vault: &RewarderGlobalVault,
    emissions_per_second: u128,
    clock: &Clock,
    ctx: &TxContext,
)
```
Updates the emission rate for a specific reward token.

**Update pool fee rate**
```move
public fun update_fee_rate<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    new_fee_rate: u64,
    ctx: &TxContext,
)
```
Updates the trading fee rate for the pool (requires pool manager role).

**Update unstaked liquidity fee rate**
```move
public fun update_unstaked_liquidity_fee_rate<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    fee_rate: u64,
    ctx: &TxContext,
)
```
Sets additional fee rate for unstaked positions to incentivize gauge participation.

**Pause/unpause pool**
```move
public fun pause<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    ctx: &mut TxContext,
)

public fun unpause<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    ctx: &mut TxContext,
)
```
Emergency pause/unpause pool operations.

**Collect protocol fees**
```move
public fun collect_protocol_fee<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    ctx: &TxContext,
): (Balance<CoinTypeA>, Balance<CoinTypeB>)
```
Collects accumulated protocol fees (requires protocol fee claim role).

#### Magma Distribution (Gauge) Operations (deprecated)

**Initialize Magma distribution gauge**
```move
public fun init_magma_distribution_gauge<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    gauge_cap: &GaugeCap,
)
```
Initializes the Magma token distribution system for a pool.

**Update distribution growth global**
```move
public fun update_magma_distribution_growth_global<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    gauge_cap: &GaugeCap,
    clock: &Clock,
)
```
Updates the global Magma distribution accumulator based on elapsed time.

**Stake position in gauge(deprecated)**
```move
public fun stake_in_magma_distribution<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &Position,
    gauge_cap: &GaugeCap,
)
```
Marks a position as staked to start earning Magma distribution rewards.

**Unstake position from gauge(deprecated)**
```move
public fun unstake_from_magma_distribution<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position: &Position,
    gauge_cap: &GaugeCap,
)
```
Marks a position as unstaked, stopping Magma distribution rewards.

**Mark position staked(deprecated)**
```move
public fun mark_position_staked<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    gauge_cap: &GaugeCap,
    position_id: ID,
)
```
Internal function to mark position as staked (called by gauge).

**Mark position unstaked(deprecated)**
```move
public fun mark_position_unstaked<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    gauge_cap: &GaugeCap,
    position_id: ID,
)
```
Internal function to mark position as unstaked (called by gauge).

#### Query Functions

**Calculate swap result**
```move
public fun calculate_swap_result<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &Pool<CoinTypeA, CoinTypeB>,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
): CalculatedSwapResult
```
Simulates a swap and returns expected amounts without executing.

**Calculate swap result with partner**
```move
public fun calculate_swap_result_with_partner<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &Pool<CoinTypeA, CoinTypeB>,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    protocol_ref_fee_rate: u64,
): CalculatedSwapResult
```
Simulates a swap with partner referral fee included.

**Fetch ticks**
```move
public fun fetch_ticks<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    start: vector<u32>,
    limit: u64,
): vector<Tick>
```
Retrieves tick data for a specified range.

**Fetch positions**
```move
public fun fetch_positions<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    start: vector<ID>,
    limit: u64,
): vector<PositionInfo>
```
Retrieves position information for specified position IDs.

**Get position amounts**
```move
public fun get_position_amounts<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
): (u64, u64)
```
Calculates the token amounts represented by a position's liquidity.

**Get position fee**
```move
public fun get_position_fee<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
): (u64, u64)
```
Returns unclaimed trading fees for a position.

**Get position rewards**
```move
public fun get_position_rewards<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
): vector<u64>
```
Returns unclaimed reward amounts for all reward tokens.

**Get position reward**
```move
public fun get_position_reward<CoinTypeA, CoinTypeB, RewardType>(
    pool: &Pool<CoinTypeA, CoinTypeB>,
    position_id: ID,
): u64
```
Returns unclaimed amount for a specific reward token.

**Pool state getters**
```move
public fun current_sqrt_price<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u128

public fun current_tick_index<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): I32

public fun liquidity<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u128

public fun fee_rate<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u64

public fun unstaked_liquidity_fee_rate<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u64

public fun fees_growth_global<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): (u128, u128)

public fun protocol_fee<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): (u64, u64)

public fun is_pause<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): bool

public fun balances<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): (u64, u64)
```

**Magma distribution getters**
```move
public fun get_magma_distribution_growth_global<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u128

public fun get_magma_distribution_reserve<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u64

public fun get_magma_distribution_staked_liquidity<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u128

public fun get_magma_distribution_gauger_id<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): ID

public fun get_magma_distribution_rollover<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u64

public fun get_magma_distribution_last_updated<CoinTypeA, CoinTypeB>(
    pool: &Pool<CoinTypeA, CoinTypeB>
): u64
```

### Factory Module (`factory.move`)

Pool creation and registry management.

**Create a new pool**
```move
public fun create_pool<CoinTypeA, CoinTypeB>(
    pools: &mut Pools,
    config: &GlobalConfig,
    tick_spacing: u32,
    initialize_price: u128,
    name: String,
    clock: &Clock,
    ctx: &mut TxContext,
): ID
```
Creates and shares a new pool, returning the pool ID.

**Create pool with initial liquidity**
```move
public fun create_pool_with_liquidity<CoinTypeA, CoinTypeB>(
    pools: &mut Pools,
    config: &GlobalConfig,
    tick_spacing: u32,
    initialize_price: u128,
    name: String,
    tick_lower: u32,
    tick_upper: u32,
    coin_a: Coin<CoinTypeA>,
    coin_b: Coin<CoinTypeB>,
    amount_a: u64,
    amount_b: u64,
    fix_amount_a: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): (ID, Position, Coin<CoinTypeA>, Coin<CoinTypeB>)
```
Creates a pool and adds initial liquidity in one transaction.

**Fetch pools**
```move
public fun fetch_pools(
    pools: &Pools,
    start: vector<ID>,
    limit: u64,
): vector<PoolSimpleInfo>
```
Retrieves pool information for pagination.

**Generate pool key**
```move
public fun new_pool_key<CoinTypeA, CoinTypeB>(tick_spacing: u32): ID
```
Generates a deterministic pool key from coin types and tick spacing.

**Pool info getters**
```move
public fun pool_id(pool_info: &PoolSimpleInfo): ID
public fun pool_key(pool_info: &PoolSimpleInfo): ID
public fun tick_spacing(pool_info: &PoolSimpleInfo): u32
public fun coin_types(pool_info: &PoolSimpleInfo): (TypeName, TypeName)
```

### Position Module (`position.move`)

NFT-based position management.

**Check position tick range validity**
```move
public fun check_position_tick_range(
    tick_lower_index: I32,
    tick_upper_index: I32,
    tick_spacing: u32,
)
```
Validates that tick indices are valid and aligned with tick spacing.

**Set position display**
```move
public fun set_display(
    config: &GlobalConfig,
    publisher: &Publisher,
    description: String,
    link: String,
    project_url: String,
    creator: String,
    ctx: &mut TxContext,
)
```
Configures NFT display metadata for position tokens.

**Fetch positions**
```move
public fun fetch_positions(
    position_manager: &PositionManager,
    start: vector<ID>,
    limit: u64,
): vector<PositionInfo>
```
Retrieves position information for specified IDs.

**Position getters**
```move
public fun pool_id(position: &Position): ID
public fun index(position: &Position): u64
public fun liquidity(position: &Position): u128
public fun tick_range(position: &Position): (I32, I32)
public fun name(position: &Position): String
public fun description(position: &Position): String
public fun url(position: &Position): String
```

**Position info getters**
```move
public fun info_position_id(position_info: &PositionInfo): ID
public fun info_liquidity(position_info: &PositionInfo): u128
public fun info_tick_range(position_info: &PositionInfo): (I32, I32)
public fun info_fee_owned(position_info: &PositionInfo): (u64, u64)
public fun info_fee_growth_inside(position_info: &PositionInfo): (u128, u128)
public fun info_points_owned(position_info: &PositionInfo): u128
public fun info_points_growth_inside(position_info: &PositionInfo): u128
public fun info_rewards(position_info: &PositionInfo): &vector<PositionReward>
public fun info_magma_distribution_owned(position_info: &PositionInfo): u64
public fun is_empty(position_info: &PositionInfo): bool
public fun is_staked(position_info: &PositionInfo): bool
```

### Config Module (`config.move`)

Global protocol configuration and governance.

#### Configuration Management

**Update protocol fee rate**
```move
public fun update_protocol_fee_rate(
    config: &mut GlobalConfig,
    new_fee_rate: u64,
    ctx: &TxContext,
)
```
Updates the protocol's share of trading fees.

**Update unstaked liquidity fee rate**
```move
public fun update_unstaked_liquidity_fee_rate(
    config: &mut GlobalConfig,
    new_fee_rate: u64,
    ctx: &TxContext,
)
```
Updates the penalty fee rate for unstaked positions.

**Add fee tier**
```move
public fun add_fee_tier(
    config: &mut GlobalConfig,
    tick_spacing: u32,
    fee_rate: u64,
    ctx: &TxContext,
)
```
Adds a new fee tier with specified tick spacing and fee rate.

**Update fee tier**
```move
public fun update_fee_tier(
    config: &mut GlobalConfig,
    tick_spacing: u32,
    new_fee_rate: u64,
    ctx: &TxContext,
)
```
Modifies an existing fee tier's fee rate.

**Delete fee tier**
```move
public fun delete_fee_tier(
    config: &mut GlobalConfig,
    tick_spacing: u32,
    ctx: &TxContext,
)
```
Removes a fee tier from the system.

**Update package version**
```move
public fun update_package_version(
    admin_cap: &AdminCap,
    config: &mut GlobalConfig,
    new_version: u64,
)
```
Updates the protocol package version for upgrade management.

**Update gauge liveness(deprecated)**
```move
public fun update_gauge_liveness(
    config: &mut GlobalConfig,
    gauge_ids: vector<ID>,
    alive: bool,
    ctx: &mut TxContext,
)
```
Marks gauges as alive or inactive for the current epoch.

#### Access Control

**Set member roles**
```move
public fun set_roles(
    admin_cap: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
    roles: u128,
)
```
Sets all roles for a member at once (bitmask).

**Add role**
```move
public fun add_role(
    admin_cap: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
    role: u8,
)
```
Grants a specific role to a member.

**Remove role**
```move
public fun remove_role(
    admin_cap: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
    role: u8,
)
```
Revokes a specific role from a member.

**Remove member**
```move
public fun remove_member(
    admin_cap: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
)
```
Removes a member and all their roles.

#### Permission Checkers

```move
public fun check_pool_manager_role(config: &GlobalConfig, addr: address)
public fun check_fee_tier_manager_role(config: &GlobalConfig, addr: address)
public fun check_partner_manager_role(config: &GlobalConfig, addr: address)
public fun check_rewarder_manager_role(config: &GlobalConfig, addr: address)
public fun check_protocol_fee_claim_role(config: &GlobalConfig, addr: address)
```

#### Query Functions

```move
public fun protocol_fee_rate(config: &GlobalConfig): u64
public fun unstaked_liquidity_fee_rate(config: &GlobalConfig): u64
public fun get_fee_rate(tick_spacing: u32, config: &GlobalConfig): u64
public fun fee_tiers(config: &GlobalConfig): &VecMap<u32, FeeTier>
public fun acl(config: &GlobalConfig): &ACL
public fun get_members(config: &GlobalConfig): vector<Member>
public fun is_gauge_alive(config: &GlobalConfig, gauge_id: ID): bool
```

#### Constants

```move
public fun week(): u64  // Returns 604800 seconds
public fun fee_rate_denom(): u64  // Fee rate denominator
public fun protocol_fee_rate_denom(): u64  // Protocol fee rate denominator
public fun unstaked_liquidity_fee_rate_denom(): u64  // Unstaked fee rate denominator
public fun max_fee_rate(): u64  // Maximum allowed fee rate
public fun max_protocol_fee_rate(): u64  // Maximum protocol fee rate
public fun max_unstaked_liquidity_fee_rate(): u64  // Maximum unstaked fee rate
public fun default_unstaked_fee_rate(): u64  // Default unstaked rate (no penalty)

// Epoch utilities
public fun epoch(ts: u64): u64  // Gets epoch number from timestamp
public fun epoch_start(ts: u64): u64  // Gets epoch start timestamp
public fun epoch_next(ts: u64): u64  // Gets next epoch start timestamp
```

### Rewarder Module (`rewarder.move`)

Multi-token reward distribution system.

**Deposit rewards**
```move
public fun deposit_reward<RewardType>(
    config: &GlobalConfig,
    vault: &mut RewarderGlobalVault,
    deposit: Balance<RewardType>,
): u64
```
Deposits reward tokens into the global vault, returns deposited amount.

**Emergency withdraw**
```move
public fun emergent_withdraw<RewardType>(
    admin_cap: &AdminCap,
    config: &GlobalConfig,
    vault: &mut RewarderGlobalVault,
    amount: u64,
): Balance<RewardType>
```
Emergency withdrawal of reward tokens (admin only).

**Query functions**
```move
public fun balance_of<RewardType>(vault: &RewarderGlobalVault): u64
public fun balances(vault: &RewarderGlobalVault): &Bag
public fun rewarders(reward_manager: &RewarderManager): vector<Rewarder>
public fun rewards_growth_global(reward_manager: &RewarderManager): vector<u128>
public fun points_growth_global(reward_manager: &RewarderManager): u128
public fun points_released(reward_manager: &RewarderManager): u128
public fun last_update_time(reward_manager: &RewarderManager): u64
public fun borrow_rewarder<RewardType>(reward_manager: &RewarderManager): &Rewarder
public fun rewarder_index<RewardType>(reward_manager: &RewarderManager): Option<u64>
public fun emissions_per_second(rewarder: &Rewarder): u128
public fun growth_global(rewarder: &Rewarder): u128
public fun reward_coin(rewarder: &Rewarder): TypeName
```

### Partner Module (`partner.move`)

Referral and partnership management.

**Create partner**
```move
public fun create_partner(
    config: &GlobalConfig,
    partners: &mut Partners,
    name: String,
    ref_fee_rate: u64,
    start_time: u64,
    end_time: u64,
    recipient: address,
    clock: &Clock,
    ctx: &mut TxContext,
)
```
Creates a new partner with referral fee configuration.

**Update referral fee rate**
```move
public fun update_ref_fee_rate(
    config: &GlobalConfig,
    partner: &mut Partner,
    fee_rate: u64,
    ctx: &mut TxContext,
)
```
Updates the partner's referral fee rate.

**Update time range**
```move
public fun update_time_range(
    config: &GlobalConfig,
    partner: &mut Partner,
    start_time: u64,
    end_time: u64,
    clock: &Clock,
    ctx: &mut TxContext,
)
```
Updates the validity period for partner referrals.

**Claim referral fees**
```move
public fun claim_ref_fee<FeeType>(
    config: &GlobalConfig,
    partner_cap: &PartnerCap,
    partner: &mut Partner,
    ctx: &mut TxContext,
)
```
Claims accumulated referral fees for a specific token type.

**Query functions**
```move
public fun name(partner: &Partner): String
public fun ref_fee_rate(partner: &Partner): u64
public fun current_ref_fee_rate(partner: &Partner, now: u64): u64
public fun start_time(partner: &Partner): u64
public fun end_time(partner: &Partner): u64
public fun balances(partner: &Partner): &Bag
```

### ACL Module (`acl.move`)

Low-level access control primitives.

```move
public fun new(ctx: &mut TxContext): ACL
public fun has_role(acl: &ACL, member: address, role: u8): bool
public fun set_roles(acl: &mut ACL, member: address, roles: u128)
public fun add_role(acl: &mut ACL, member: address, role: u8)
public fun remove_role(acl: &mut ACL, member: address, role: u8)
public fun remove_member(acl: &mut ACL, member: address)
public fun get_members(acl: &ACL): vector<Member>
public fun get_permission(acl: &ACL, member: address): u128
```

### Math Modules

#### CLMM Math (`clmm_math.move`)

Core mathematical operations for concentrated liquidity.

```move
public fun fee_rate_denominator(): u64

public fun get_liquidity_from_a(
    from_sqrt_price: u128,
    to_sqrt_price: u128,
    amount: u64,
    round_up: bool,
): u128

public fun get_liquidity_from_b(
    from_sqrt_price: u128,
    to_sqrt_price: u128,
    amount: u64,
    round_up: bool,
): u128

public fun get_delta_a(
    price1: u128,
    price2: u128,
    liquidity: u128,
    round_up: bool,
): u64

public fun get_delta_b(
    price1: u128,
    price2: u128,
    liquidity: u128,
    round_up: bool,
): u64

public fun get_liquidity_by_amount(
    tick_lower_index: I32,
    tick_upper_index: I32,
    current_tick_index: I32,
    current_sqrt_price: u128,
    amount: u64,
    fix_amount_a: bool,
): (u128, u64, u64)

public fun get_amount_by_liquidity(
    tick_lower_index: I32,
    tick_upper_index: I32,
    current_tick_index: I32,
    current_sqrt_price: u128,
    liquidity: u128,
    round_up: bool,
): (u64, u64)

public fun get_next_sqrt_price_from_input(
    from_price: u128,
    liquidity: u128,
    amount_in: u64,
    a2b: bool,
): u128

public fun get_next_sqrt_price_from_output(
    from_price: u128,
    liquidity: u128,
    amount_out: u64,
    a2b: bool,
): u128

public fun compute_swap_step(
    current_sqrt_price: u128,
    target_sqrt_price: u128,
    liquidity: u128,
    amount: u64,
    fee_rate: u64,
    by_amount_in: bool,
    a2b: bool,
): (u128, u64, u64, u64)
```

#### Tick Math (`tick_math.move`)

Price-tick conversion and validation.

```move
public fun min_tick(): I32
public fun max_tick(): I32
public fun min_sqrt_price(): u128
public fun max_sqrt_price(): u128
public fun tick_bound(): u32

public fun get_sqrt_price_at_tick(tick_index: I32): u128
public fun get_tick_at_sqrt_price(sqrt_price: u128): I32
public fun is_valid_index(index: I32, tick_spacing: u32): bool
```

## Usage Examples

### Creating a Pool

```move
use magma_clmm::factory;
use magma_clmm::config;

// Create a new pool with 1% fee tier (tick spacing 100)
let pool_id = factory::create_pool<COIN_A, COIN_B>(
    &mut pools,
    &global_config,
    100,  // tick_spacing
    79228162514264337593543950336,  // initial sqrt price (1:1)
    string::utf8(b"COIN_A/COIN_B Pool"),
    &clock,
    &mut ctx
);
```

### Adding Liquidity

```move
use magma_clmm::pool;

// Open a new position
let position = pool::open_position<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    i32::from(4600),  // tick_lower
    i32::from(5400),  // tick_upper
    &mut ctx
);

// Add liquidity
let receipt = pool::add_liquidity_fix_coin<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    &mut position,
    1000000,  // amount
    true,  // fix coin A
    &clock
);

// Repay the liquidity
pool::repay_add_liquidity<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    coin_a_balance,
    coin_b_balance,
    receipt
);
```

### Executing a Swap

```move
// Flash swap
let (balance_a, balance_b, receipt) = pool::flash_swap<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    true,  // a2b direction
    true,  // by_amount_in
    1000000,  // amount
    0,  // sqrt_price_limit (0 = no limit)
    &clock
);

// Repay the swap
pool::repay_flash_swap<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    repay_balance_a,
    repay_balance_b,
    receipt
);
```

### Collecting Rewards

```move
// Collect trading fees
let (fee_a, fee_b) = pool::collect_fee<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    position_id,
    true,  // recalculate
    &clock
);

// Collect specific reward
let reward_balance = pool::collect_reward<COIN_A, COIN_B, REWARD_COIN>(
    &global_config,
    &mut pool,
    position_id,
    &mut rewarder_vault,
    true,  // recalculate
    &clock
);
```

### Staking in Magma Distribution(deprecated)

```move
// Initialize gauge for the pool (done once)
pool::init_magma_distribution_gauge<COIN_A, COIN_B>(
    &mut pool,
    &gauge_cap
);

// Stake a position
pool::stake_in_magma_distribution<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    &position,
    &gauge_cap
);

// Collect Magma rewards
let magma_amount = pool::calculate_and_update_magma_distribution<COIN_A, COIN_B>(
    &global_config,
    &mut pool,
    position_id
);
```

## Development Guidelines

### Testing Strategy

```bash
# Run all tests
sui move test

# Run with verbose output
sui move test --verbose

# Run specific test function
sui move test --filter test_swap_exact_input

# Generate test coverage
sui move test --coverage
```

### Code Standards

- Follow Move 2024 edition best practices
- All public functions must include comprehensive documentation
- Use explicit type annotations for clarity
- Prefer immutable references (`&`) over mutable (`&mut`) where possible
- Include event emissions for all state-changing operations
- Validate all inputs and use descriptive error codes

### Security Considerations

- Always validate tick ranges and price limits
- Check for arithmetic overflow/underflow in calculations
- Ensure position ownership before allowing operations
- Verify fee rates are within acceptable bounds
- Implement emergency pause functionality for critical issues
- Use capability-based security for privileged operations

## Contributing

We welcome contributions to the Magma CLMM protocol. Please follow these guidelines:

### Contribution Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Implement your changes with comprehensive tests
4. Ensure all tests pass (`sui move test`)
5. Format code according to Move style guidelines
6. Commit with clear, descriptive messages
7. Submit a Pull Request with detailed description

### Code Review Process

- All PRs require at least one maintainer approval
- Automated tests must pass
- Code coverage should not decrease
- Breaking changes require migration documentation

## Resources

- **Magma Website** [magmafinance.io](https://magmafinance.io/)
- **Documentation**: [MagmaDocs](https://magma-finance-1.gitbook.io/magma-finance/)
- **GitHub**: [github.com/MagmaFinanceIO](https://github.com/MagmaFinanceIO)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Version History

### v1.0.0 (Current)
- Initial release with full CLMM functionality
- Multi-reward system support (up to 5 reward tokens)
- Unstaked liquidity penalty mechanism
- Partner referral system
- Flash swap and flash loan support

## Acknowledgments

Built with ❤️ by the Magma Finance team on Sui blockchain.
