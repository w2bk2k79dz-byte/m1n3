module p2pool_shares::m1n3_staking {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use p2pool_shares::m1n3_token::{M1N3};

    /// Error codes
    const E_INSUFFICIENT_STAKE: u64 = 1;
    const E_NOT_STAKED: u64 = 2;
    const E_ALREADY_STAKED: u64 = 3;
    const E_UNSTAKING_COOLDOWN: u64 = 4;
    const E_NOT_TEMPLATE_PROPOSER: u64 = 5;

    /// Minimum stake to become template proposer (100,000 M1N3)
    const MIN_STAKE: u64 = 100000_00000000;

    /// Unstaking cooldown period (7 days in milliseconds)
    const UNSTAKING_COOLDOWN_MS: u64 = 7 * 24 * 60 * 60 * 1000;

    /// Stake position for a node
    struct StakePosition has key, store {
        id: UID,
        /// Staker address
        staker: address,
        /// Staked balance
        staked_balance: Balance<M1N3>,
        /// Staked amount
        amount: u64,
        /// Timestamp when staked
        staked_at: u64,
        /// Timestamp when unstake requested (0 if not unstaking)
        unstake_requested_at: u64,
        /// Is active template proposer
        is_active: bool,
        /// Templates proposed
        templates_proposed: u64,
        /// Shares verified
        shares_verified: u64,
        /// Rewards earned as proposer
        proposer_rewards: u64,
    }

    /// Global staking registry
    struct StakingRegistry has key {
        id: UID,
        /// Maps staker address => stake position ID
        stakes: Table<address, ID>,
        /// Active template proposers
        active_proposers: Table<address, bool>,
        /// Collected fees from share trading (to be distributed)
        fee_pool: Balance<M1N3>,
        /// Total fees collected
        total_fees_collected: u64,
        /// Total staked M1N3
        total_staked: u64,
        /// Total active proposers
        total_proposers: u64,
        /// Minimum stake required
        min_stake: u64,
    }

    /// Events
    struct Staked has copy, drop {
        staker: address,
        amount: u64,
        timestamp: u64,
    }

    struct UnstakeRequested has copy, drop {
        staker: address,
        amount: u64,
        cooldown_ends: u64,
    }

    struct Unstaked has copy, drop {
        staker: address,
        amount: u64,
        timestamp: u64,
    }

    struct BecameProposer has copy, drop {
        proposer: address,
        stake_amount: u64,
    }

    /// Initialize staking registry
    fun init(ctx: &mut TxContext) {
        let registry = StakingRegistry {
            id: object::new(ctx),
            stakes: table::new(ctx),
            active_proposers: table::new(ctx),
            fee_pool: balance::zero<M1N3>(),
            total_fees_collected: 0,
            total_staked: 0,
            total_proposers: 0,
            min_stake: MIN_STAKE,
        };
        transfer::share_object(registry);
    }

    /// Stake M1N3 tokens to become template proposer
    public entry fun stake(
        registry: &mut StakingRegistry,
        stake_coin: Coin<M1N3>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let amount = coin::value(&stake_coin);

        // Check minimum stake
        assert!(amount >= registry.min_stake, E_INSUFFICIENT_STAKE);

        // Check not already staked
        assert!(!table::contains(&registry.stakes, sender), E_ALREADY_STAKED);

        // Create stake position
        let position = StakePosition {
            id: object::new(ctx),
            staker: sender,
            staked_balance: coin::into_balance(stake_coin),
            amount,
            staked_at: clock::timestamp_ms(clock),
            unstake_requested_at: 0,
            is_active: true,
            templates_proposed: 0,
            shares_verified: 0,
            proposer_rewards: 0,
        };

        let position_id = object::uid_to_inner(&position.id);

        // Update registry
        table::add(&mut registry.stakes, sender, position_id);
        table::add(&mut registry.active_proposers, sender, true);
        registry.total_staked = registry.total_staked + amount;
        registry.total_proposers = registry.total_proposers + 1;

        // Emit events
        event::emit(Staked {
            staker: sender,
            amount,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(BecameProposer {
            proposer: sender,
            stake_amount: amount,
        });

        // Share position
        transfer::share_object(position);
    }

    /// Request unstake (starts cooldown period)
    public entry fun request_unstake(
        registry: &mut StakingRegistry,
        position: &mut StakePosition,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify ownership
        assert!(position.staker == sender, E_NOT_STAKED);

        // Mark as unstaking
        position.unstake_requested_at = clock::timestamp_ms(clock);
        position.is_active = false;

        // Remove from active proposers
        if (table::contains(&registry.active_proposers, sender)) {
            table::remove(&mut registry.active_proposers, sender);
            registry.total_proposers = registry.total_proposers - 1;
        };

        let cooldown_ends = position.unstake_requested_at + UNSTAKING_COOLDOWN_MS;

        event::emit(UnstakeRequested {
            staker: sender,
            amount: position.amount,
            cooldown_ends,
        });
    }

    /// Complete unstake after cooldown period
    public entry fun unstake(
        registry: &mut StakingRegistry,
        position: StakePosition,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify ownership
        assert!(position.staker == sender, E_NOT_STAKED);

        // Check cooldown period
        let current_time = clock::timestamp_ms(clock);
        assert!(
            position.unstake_requested_at > 0 &&
            current_time >= position.unstake_requested_at + UNSTAKING_COOLDOWN_MS,
            E_UNSTAKING_COOLDOWN
        );

        let StakePosition {
            id,
            staker,
            staked_balance,
            amount,
            staked_at: _,
            unstake_requested_at: _,
            is_active: _,
            templates_proposed: _,
            shares_verified: _,
            proposer_rewards: _,
        } = position;

        // Remove from registry
        if (table::contains(&registry.stakes, staker)) {
            table::remove(&mut registry.stakes, staker);
        };
        registry.total_staked = registry.total_staked - amount;

        // Return staked tokens
        let unstaked_coin = coin::from_balance(staked_balance, ctx);
        transfer::public_transfer(unstaked_coin, sender);

        event::emit(Unstaked {
            staker,
            amount,
            timestamp: current_time,
        });

        object::delete(id);
    }

    /// Increase stake
    public entry fun increase_stake(
        registry: &mut StakingRegistry,
        position: &mut StakePosition,
        additional_stake: Coin<M1N3>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(position.staker == sender, E_NOT_STAKED);

        let additional_amount = coin::value(&additional_stake);
        coin::put(&mut position.staked_balance, additional_stake);
        position.amount = position.amount + additional_amount;

        registry.total_staked = registry.total_staked + additional_amount;
    }

    /// Record template proposal (called by template system)
    public(friend) fun record_template_proposal(position: &mut StakePosition) {
        assert!(position.is_active, E_NOT_TEMPLATE_PROPOSER);
        position.templates_proposed = position.templates_proposed + 1;
    }

    /// Record share verification (called by mining system)
    public(friend) fun record_share_verification(position: &mut StakePosition) {
        assert!(position.is_active, E_NOT_TEMPLATE_PROPOSER);
        position.shares_verified = position.shares_verified + 1;
    }

    /// Add proposer rewards
    public(friend) fun add_proposer_reward(position: &mut StakePosition, amount: u64) {
        position.proposer_rewards = position.proposer_rewards + amount;
    }

    /// Distribute share trading fee to all stakers (called by mining module)
    public(friend) fun distribute_fee_to_stakers(
        registry: &mut StakingRegistry,
        fee: Coin<M1N3>
    ) {
        let fee_amount = coin::value(&fee);
        coin::put(&mut registry.fee_pool, fee);
        registry.total_fees_collected = registry.total_fees_collected + fee_amount;
    }

    /// Claim share of collected fees (proportional to stake)
    public entry fun claim_fees(
        registry: &mut StakingRegistry,
        position: &StakePosition,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(position.staker == sender, E_NOT_STAKED);

        // Calculate proportional share of fee pool
        let total_fees_available = balance::value(&registry.fee_pool);
        if (total_fees_available > 0 && registry.total_staked > 0) {
            let stake_share = (position.amount * 1000000) / registry.total_staked; // Fixed point math
            let reward_amount = (total_fees_available * stake_share) / 1000000;

            if (reward_amount > 0) {
                let reward_balance = balance::split(&mut registry.fee_pool, reward_amount);
                let reward_coin = coin::from_balance(reward_balance, ctx);
                transfer::public_transfer(reward_coin, sender);
            };
        };
    }

    /// Check if address is active proposer
    public fun is_active_proposer(registry: &StakingRegistry, addr: address): bool {
        table::contains(&registry.active_proposers, addr)
    }

    /// Get stake amount
    public fun get_stake_amount(position: &StakePosition): u64 {
        position.amount
    }

    /// Get staking stats
    public fun get_staking_stats(registry: &StakingRegistry): (u64, u64, u64) {
        (registry.total_staked, registry.total_proposers, registry.min_stake)
    }

    /// Get position stats
    public fun get_position_stats(position: &StakePosition): (u64, u64, u64, u64, bool) {
        (
            position.amount,
            position.templates_proposed,
            position.shares_verified,
            position.proposer_rewards,
            position.is_active
        )
    }
}
