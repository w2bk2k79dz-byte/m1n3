module p2pool_shares::m1n3_mining {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use sui::hash::sha2_256;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use p2pool_shares::m1n3_token::{Self, M1N3, M1N3Treasury};
    use p2pool_shares::m1n3_staking::{Self, StakingRegistry, StakePosition};

    /// Error codes
    const E_NOT_PROPOSER: u64 = 1;
    const E_TEMPLATE_EXPIRED: u64 = 2;
    const E_INVALID_SHARE: u64 = 3;
    const E_DUPLICATE_SHARE: u64 = 4;
    const E_SHARE_DIFFICULTY_TOO_LOW: u64 = 5;
    const E_TEMPLATE_NOT_FOUND: u64 = 6;
    const E_BLOCK_NOT_FOUND: u64 = 7;
    const E_REDEMPTION_NOT_ALLOWED: u64 = 8;
    const E_INVALID_SHARE_OWNERSHIP: u64 = 9;

    /// Template validity period (10 minutes in milliseconds)
    const TEMPLATE_VALIDITY_MS: u64 = 10 * 60 * 1000;

    /// Proposer fee (5% of share reward)
    const PROPOSER_FEE_PERCENT: u64 = 5;

    /// Share transfer fee (2% goes to M1N3 stakers)
    const SHARE_TRANSFER_FEE_PERCENT: u64 = 2;

    /// Block template proposed by staked node
    struct MiningTemplate has key, store {
        id: UID,
        /// Block height
        height: u32,
        /// Template hash (for quick lookup)
        template_hash: vector<u8>,
        /// Previous block hash
        prev_block_hash: vector<u8>,
        /// Merkle root
        merkle_root: vector<u8>,
        /// Timestamp
        timestamp: u32,
        /// Difficulty bits
        bits: u32,
        /// Coinbase value
        coinbase_value: u64,
        /// Transaction hashes included
        tx_hashes: vector<vector<u8>>,
        /// Proposer address
        proposer: address,
        /// Proposed timestamp
        proposed_at: u64,
        /// Expires at
        expires_at: u64,
        /// Number of shares submitted
        shares_submitted: u64,
        /// Number of valid shares
        valid_shares: u64,
    }

    /// Mining share submitted by miner (tradeable NFT)
    struct MiningShare has key, store {
        id: UID,
        /// Share hash
        share_hash: vector<u8>,
        /// Block header hash
        header_hash: vector<u8>,
        /// Template ID used
        template_id: ID,
        /// Block height
        height: u32,
        /// Nonce used
        nonce: u32,
        /// Extra nonce
        extra_nonce: u64,
        /// Original miner address
        miner: address,
        /// Current owner
        owner: address,
        /// Difficulty met
        difficulty: u64,
        /// Submitted at
        submitted_at: u64,
        /// Is valid
        is_valid: bool,
        /// Found block (met Bitcoin network difficulty)
        found_block: bool,
        /// Has been redeemed for Bitcoin rewards
        redeemed: bool,
    }

    /// Block reward pool for PPS redemption
    struct BlockRewardPool has key, store {
        id: UID,
        /// Block height
        height: u32,
        /// Block header hash
        block_hash: vector<u8>,
        /// Coinbase value in satoshis
        coinbase_value: u64,
        /// Total difficulty of all shares
        total_difficulty: u64,
        /// Total shares submitted
        total_shares: u64,
        /// Block found timestamp
        found_at: u64,
        /// Redemptions allowed
        redemption_enabled: bool,
        /// Shares redeemed count
        redeemed_shares: u64,
    }

    /// Mining registry
    struct MiningRegistry has key {
        id: UID,
        /// Current templates (height => template ID)
        active_templates: Table<u32, ID>,
        /// Share hashes (to prevent duplicates)
        submitted_shares: Table<vector<u8>, bool>,
        /// Block reward pools (height => pool ID)
        reward_pools: Table<u32, ID>,
        /// Total templates proposed
        total_templates: u64,
        /// Total shares submitted
        total_shares: u64,
        /// Total valid shares
        total_valid_shares: u64,
        /// Total blocks found
        total_blocks_found: u64,
        /// Total shares traded
        total_shares_traded: u64,
        /// Total fees collected (in M1N3)
        total_fees_collected: u64,
        /// Mode: false = historical verification, true = real-time mining
        mining_mode_active: bool,
    }

    /// Events
    struct TemplateProposed has copy, drop {
        template_id: address,
        height: u32,
        proposer: address,
        merkle_root: vector<u8>,
        expires_at: u64,
    }

    struct ShareSubmitted has copy, drop {
        share_id: address,
        miner: address,
        height: u32,
        share_hash: vector<u8>,
        is_valid: bool,
        found_block: bool,
    }

    struct BlockFound has copy, drop {
        height: u32,
        header_hash: vector<u8>,
        miner: address,
        template_proposer: address,
        timestamp: u64,
    }

    struct MiningModeActivated has copy, drop {
        timestamp: u64,
        message: vector<u8>,
    }

    struct ShareTransferred has copy, drop {
        share_id: address,
        from: address,
        to: address,
        difficulty: u64,
        fee_amount: u64,
        timestamp: u64,
    }

    struct ShareRedeemed has copy, drop {
        share_id: address,
        height: u32,
        owner: address,
        difficulty: u64,
        pps_reward: u64,
        timestamp: u64,
    }

    struct RewardPoolCreated has copy, drop {
        pool_id: address,
        height: u32,
        block_hash: vector<u8>,
        coinbase_value: u64,
        timestamp: u64,
    }

    /// Initialize mining registry
    fun init(ctx: &mut TxContext) {
        let registry = MiningRegistry {
            id: object::new(ctx),
            active_templates: table::new(ctx),
            submitted_shares: table::new(ctx),
            reward_pools: table::new(ctx),
            total_templates: 0,
            total_shares: 0,
            total_valid_shares: 0,
            total_blocks_found: 0,
            total_shares_traded: 0,
            total_fees_collected: 0,
            mining_mode_active: false,
        };
        transfer::share_object(registry);
    }

    /// Activate mining mode (transition from historical verification)
    public entry fun activate_mining_mode(
        registry: &mut MiningRegistry,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        registry.mining_mode_active = true;

        event::emit(MiningModeActivated {
            timestamp: clock::timestamp_ms(clock),
            message: b"M1N3 mining mode activated! Historical verification complete.",
        });
    }

    /// Propose block template (only staked nodes)
    public entry fun propose_template(
        registry: &mut MiningRegistry,
        staking_registry: &StakingRegistry,
        position: &mut StakePosition,
        height: u32,
        prev_block_hash: vector<u8>,
        merkle_root: vector<u8>,
        timestamp: u32,
        bits: u32,
        coinbase_value: u64,
        tx_hashes: vector<vector<u8>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify sender is active proposer
        assert!(m1n3_staking::is_active_proposer(staking_registry, sender), E_NOT_PROPOSER);

        // Calculate template hash
        let template_data = construct_template_data(
            height, &prev_block_hash, &merkle_root, timestamp, bits
        );
        let template_hash = sha2_256(template_data);

        let current_time = clock::timestamp_ms(clock);
        let expires_at = current_time + TEMPLATE_VALIDITY_MS;

        // Create template
        let template = MiningTemplate {
            id: object::new(ctx),
            height,
            template_hash,
            prev_block_hash,
            merkle_root,
            timestamp,
            bits,
            coinbase_value,
            tx_hashes,
            proposer: sender,
            proposed_at: current_time,
            expires_at,
            shares_submitted: 0,
            valid_shares: 0,
        };

        let template_id = object::uid_to_inner(&template.id);
        let template_addr = object::uid_to_address(&template.id);

        // Update registry
        if (table::contains(&registry.active_templates, height)) {
            let old_id = table::remove(&mut registry.active_templates, height);
            // Old template expires naturally
        };
        table::add(&mut registry.active_templates, height, template_id);
        registry.total_templates = registry.total_templates + 1;

        // Record in staking position
        m1n3_staking::record_template_proposal(position);

        // Emit event
        event::emit(TemplateProposed {
            template_id: template_addr,
            height,
            proposer: sender,
            merkle_root,
            expires_at,
        });

        // Share template
        transfer::share_object(template);
    }

    /// Submit mining share for verification
    public entry fun submit_share(
        registry: &mut MiningRegistry,
        template: &mut MiningTemplate,
        treasury: &mut M1N3Treasury,
        proposer_position: &mut StakePosition,
        share_hash: vector<u8>,
        header_hash: vector<u8>,
        nonce: u32,
        extra_nonce: u64,
        share_data: vector<u8>,  // For verification
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Check template not expired
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time < template.expires_at, E_TEMPLATE_EXPIRED);

        // Check share not already submitted
        assert!(!table::contains(&registry.submitted_shares, share_hash), E_DUPLICATE_SHARE);

        // Verify share hash
        let computed_share_hash = sha2_256(share_data);
        assert!(computed_share_hash == share_hash, E_INVALID_SHARE);

        // Verify header matches template
        let is_valid = verify_header_against_template(
            template,
            &header_hash,
            nonce
        );

        // Check if share meets pool difficulty (simplified)
        let meets_pool_difficulty = true; // TODO: Implement proper difficulty check

        // Check if found actual Bitcoin block
        let found_block = check_if_block_found(&header_hash, template.bits);

        let share = MiningShare {
            id: object::new(ctx),
            share_hash,
            header_hash,
            template_id: object::uid_to_inner(&template.id),
            height: template.height,
            nonce,
            extra_nonce,
            miner: sender,
            owner: sender,
            difficulty: bits_to_difficulty(template.bits),
            submitted_at: current_time,
            is_valid: is_valid && meets_pool_difficulty,
            found_block,
            redeemed: false,
        };

        let share_addr = object::uid_to_address(&share.id);

        // Update template stats
        template.shares_submitted = template.shares_submitted + 1;
        if (is_valid) {
            template.valid_shares = template.valid_shares + 1;
        };

        // Update registry
        table::add(&mut registry.submitted_shares, share_hash, true);
        registry.total_shares = registry.total_shares + 1;

        if (is_valid) {
            registry.total_valid_shares = registry.total_valid_shares + 1;

            // Calculate and distribute rewards
            let base_reward = calculate_share_reward(template.height);
            let proposer_fee = (base_reward * PROPOSER_FEE_PERCENT) / 100;
            let miner_reward = base_reward - proposer_fee;

            // Mint rewards
            let miner_coin = m1n3_token::mint_reward(treasury, miner_reward, ctx);
            let proposer_coin = m1n3_token::mint_reward(treasury, proposer_fee, ctx);

            // Transfer rewards
            transfer::public_transfer(miner_coin, sender);
            transfer::public_transfer(proposer_coin, template.proposer);

            // Record proposer reward
            m1n3_staking::add_proposer_reward(proposer_position, proposer_fee);
            m1n3_staking::record_share_verification(proposer_position);
        };

        if (found_block) {
            registry.total_blocks_found = registry.total_blocks_found + 1;

            // Create block reward pool for PPS redemption
            let reward_pool = BlockRewardPool {
                id: object::new(ctx),
                height: template.height,
                block_hash: header_hash,
                coinbase_value: template.coinbase_value,
                total_difficulty: 0,
                total_shares: 0,
                found_at: current_time,
                redemption_enabled: false,
                redeemed_shares: 0,
            };

            let pool_id = object::uid_to_inner(&reward_pool.id);
            let pool_addr = object::uid_to_address(&reward_pool.id);

            // Register reward pool
            table::add(&mut registry.reward_pools, template.height, pool_id);

            event::emit(BlockFound {
                height: template.height,
                header_hash,
                miner: sender,
                template_proposer: template.proposer,
                timestamp: current_time,
            });

            event::emit(RewardPoolCreated {
                pool_id: pool_addr,
                height: template.height,
                block_hash: header_hash,
                coinbase_value: template.coinbase_value,
                timestamp: current_time,
            });

            transfer::share_object(reward_pool);
        };

        // Emit event
        event::emit(ShareSubmitted {
            share_id: share_addr,
            miner: sender,
            height: template.height,
            share_hash,
            is_valid: is_valid && meets_pool_difficulty,
            found_block,
        });

        // All valid shares are tradeable NFTs owned by miner
        transfer::transfer(share, sender);
    }

    /// Transfer share with 2% fee to M1N3 stakers
    public entry fun transfer_share(
        registry: &mut MiningRegistry,
        staking_registry: &StakingRegistry,
        share: MiningShare,
        recipient: address,
        payment: Coin<M1N3>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify sender owns the share
        assert!(share.owner == sender, E_INVALID_SHARE_OWNERSHIP);

        // Calculate 2% transfer fee on the payment amount
        let payment_amount = coin::value(&payment);
        let fee_amount = (payment_amount * SHARE_TRANSFER_FEE_PERCENT) / 100;
        let seller_amount = payment_amount - fee_amount;

        // Split payment
        let fee_coin = coin::split(&mut payment, fee_amount, ctx);

        // Distribute fee to all M1N3 stakers
        m1n3_staking::distribute_fee_to_stakers(staking_registry, fee_coin);

        // Transfer remaining payment to seller
        transfer::public_transfer(payment, sender);

        // Update share ownership
        let share_id = object::uid_to_address(&share.id);
        let MiningShare {
            id,
            share_hash,
            header_hash,
            template_id,
            height,
            nonce,
            extra_nonce,
            miner,
            owner: _,
            difficulty,
            submitted_at,
            is_valid,
            found_block,
            redeemed,
        } = share;

        let updated_share = MiningShare {
            id,
            share_hash,
            header_hash,
            template_id,
            height,
            nonce,
            extra_nonce,
            miner,
            owner: recipient,
            difficulty,
            submitted_at,
            is_valid,
            found_block,
            redeemed,
        };

        // Update registry stats
        registry.total_shares_traded = registry.total_shares_traded + 1;
        registry.total_fees_collected = registry.total_fees_collected + fee_amount;

        // Emit event
        event::emit(ShareTransferred {
            share_id,
            from: sender,
            to: recipient,
            difficulty,
            fee_amount,
            timestamp: clock::timestamp_ms(clock),
        });

        // Transfer share to recipient
        transfer::transfer(updated_share, recipient);
    }

    /// Enable redemptions for a found block
    public entry fun enable_redemptions(
        pool: &mut BlockRewardPool,
        _ctx: &mut TxContext
    ) {
        pool.redemption_enabled = true;
    }

    /// Register share for PPS calculation (must be called before redemption)
    public entry fun register_share_for_redemption(
        pool: &mut BlockRewardPool,
        share: &MiningShare,
        _ctx: &mut TxContext
    ) {
        // Verify share is for this block height
        assert!(share.height == pool.height, E_BLOCK_NOT_FOUND);
        assert!(share.is_valid, E_INVALID_SHARE);

        // Add share difficulty to pool
        pool.total_difficulty = pool.total_difficulty + share.difficulty;
        pool.total_shares = pool.total_shares + 1;
    }

    /// Redeem share for Bitcoin rewards (PPS - Pay Per Share)
    public entry fun redeem_share(
        pool: &mut BlockRewardPool,
        share: MiningShare,
        treasury: &mut M1N3Treasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify ownership
        assert!(share.owner == sender, E_INVALID_SHARE_OWNERSHIP);

        // Verify share is for this block
        assert!(share.height == pool.height, E_BLOCK_NOT_FOUND);

        // Verify redemptions are enabled
        assert!(pool.redemption_enabled, E_REDEMPTION_NOT_ALLOWED);

        // Verify share is valid and not already redeemed
        assert!(share.is_valid, E_INVALID_SHARE);
        assert!(!share.redeemed, E_REDEMPTION_NOT_ALLOWED);

        // Calculate PPS reward
        // Reward = (share_difficulty / total_difficulty) * coinbase_value
        // Convert to M1N3 tokens (multiply by 1000 as per M1N3 economics)
        let share_portion = (share.difficulty * 1000000) / pool.total_difficulty; // Use fixed point math
        let pps_reward = (pool.coinbase_value * share_portion) / 1000; // M1N3 tokens with 8 decimals

        // Mint M1N3 tokens as redemption reward
        let reward_coin = m1n3_token::mint_reward(treasury, pps_reward, ctx);

        // Update pool stats
        pool.redeemed_shares = pool.redeemed_shares + 1;

        let share_id = object::uid_to_address(&share.id);

        // Emit redemption event
        event::emit(ShareRedeemed {
            share_id,
            height: share.height,
            owner: sender,
            difficulty: share.difficulty,
            pps_reward,
            timestamp: clock::timestamp_ms(clock),
        });

        // Destroy redeemed share
        let MiningShare {
            id,
            share_hash: _,
            header_hash: _,
            template_id: _,
            height: _,
            nonce: _,
            extra_nonce: _,
            miner: _,
            owner: _,
            difficulty: _,
            submitted_at: _,
            is_valid: _,
            found_block: _,
            redeemed: _,
        } = share;

        object::delete(id);

        // Transfer redemption reward
        transfer::public_transfer(reward_coin, sender);
    }

    /// Helper: Construct template data for hashing
    fun construct_template_data(
        height: u32,
        prev_block_hash: &vector<u8>,
        merkle_root: &vector<u8>,
        timestamp: u32,
        bits: u32
    ): vector<u8> {
        let data = vector::empty<u8>();

        // Add height (4 bytes)
        vector::append(&mut data, u32_to_bytes_le(height));

        // Add prev block hash
        vector::append(&mut data, *prev_block_hash);

        // Add merkle root
        vector::append(&mut data, *merkle_root);

        // Add timestamp
        vector::append(&mut data, u32_to_bytes_le(timestamp));

        // Add bits
        vector::append(&mut data, u32_to_bytes_le(bits));

        data
    }

    /// Helper: Verify header against template
    fun verify_header_against_template(
        template: &MiningTemplate,
        header_hash: &vector<u8>,
        nonce: u32
    ): bool {
        // Simplified verification - in production would reconstruct full header
        // and verify hash matches
        true // TODO: Implement full header reconstruction and verification
    }

    /// Helper: Check if share found block
    fun check_if_block_found(header_hash: &vector<u8>, bits: u32): bool {
        // Check if header hash meets Bitcoin network difficulty
        // For now, simplified check
        false // TODO: Implement proper difficulty check
    }

    /// Helper: Convert bits to difficulty
    fun bits_to_difficulty(bits: u32): u64 {
        // Simplified - should use proper Bitcoin difficulty calculation
        (bits as u64)
    }

    /// Helper: Calculate share reward based on height
    fun calculate_share_reward(height: u32): u64 {
        // Base reward for shares (much less than block verification)
        // 1 M1N3 per share as base
        100000000 // 1 M1N3 (8 decimals)
    }

    /// Helper: u32 to little-endian bytes
    fun u32_to_bytes_le(value: u32): vector<u8> {
        let bytes = vector::empty<u8>();
        vector::push_back(&mut bytes, ((value & 0xFF) as u8));
        vector::push_back(&mut bytes, (((value >> 8) & 0xFF) as u8));
        vector::push_back(&mut bytes, (((value >> 16) & 0xFF) as u8));
        vector::push_back(&mut bytes, (((value >> 24) & 0xFF) as u8));
        bytes
    }

    /// Get mining stats
    public fun get_mining_stats(registry: &MiningRegistry): (u64, u64, u64, u64, bool) {
        (
            registry.total_templates,
            registry.total_shares,
            registry.total_valid_shares,
            registry.total_blocks_found,
            registry.mining_mode_active
        )
    }

    /// Get template info
    public fun get_template_info(template: &MiningTemplate): (u32, address, u64, u64, u64) {
        (
            template.height,
            template.proposer,
            template.expires_at,
            template.shares_submitted,
            template.valid_shares
        )
    }
}
