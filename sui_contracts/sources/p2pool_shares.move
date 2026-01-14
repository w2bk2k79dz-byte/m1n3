module p2pool_shares::share_registry {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use sui::hash::sha2_256;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};

    /// Error codes
    const E_INVALID_SHARE: u64 = 1;
    const E_DUPLICATE_SHARE: u64 = 2;
    const E_INVALID_DIFFICULTY: u64 = 3;
    const E_INVALID_BLOCK_TEMPLATE: u64 = 4;
    const E_SHARE_NOT_FOUND: u64 = 5;

    /// Represents a mined share registered on Sui
    struct MiningShare has key, store {
        id: UID,
        /// Bitcoin block header hash
        block_header_hash: vector<u8>,
        /// P2Pool share hash
        share_hash: vector<u8>,
        /// Previous share hash in the chain
        previous_share_hash: vector<u8>,
        /// Miner's Bitcoin address (pubkey hash)
        miner_pubkey_hash: vector<u8>,
        /// Share difficulty (bits)
        difficulty_bits: u32,
        /// Target difficulty value
        difficulty_target: vector<u8>,
        /// Bitcoin block height
        block_height: u32,
        /// Timestamp of the share
        timestamp: u64,
        /// Nonce used
        nonce: u32,
        /// Subsidy amount
        subsidy: u64,
        /// Reference to block template ID
        block_template_id: vector<u8>,
        /// Is this share part of a winning block?
        is_block_winner: bool,
        /// Minted timestamp on Sui
        minted_at: u64,
        /// Current owner (for trading)
        owner: address,
    }

    /// Represents a Bitcoin block template registered on Sui
    struct BlockTemplate has key, store {
        id: UID,
        /// Template hash (hash of the template data)
        template_hash: vector<u8>,
        /// Bitcoin block height
        height: u32,
        /// Previous block hash
        previous_block_hash: vector<u8>,
        /// Merkle root
        merkle_root: vector<u8>,
        /// Block version
        version: u32,
        /// Target bits
        bits: u32,
        /// Coinbase value
        coinbase_value: u64,
        /// Timestamp
        timestamp: u64,
        /// Transaction count
        tx_count: u32,
        /// Registered timestamp on Sui
        registered_at: u64,
    }

    /// Global registry for tracking shares and preventing duplicates
    struct ShareRegistry has key {
        id: UID,
        /// Maps share_hash => bool (exists or not)
        shares: Table<vector<u8>, bool>,
        /// Maps block_template_hash => bool
        templates: Table<vector<u8>, bool>,
        /// Total shares registered
        total_shares: u64,
        /// Total block templates
        total_templates: u64,
        /// Total block winners
        total_block_winners: u64,
    }

    /// Events
    struct ShareMinted has copy, drop {
        share_id: address,
        share_hash: vector<u8>,
        miner: vector<u8>,
        difficulty_bits: u32,
        block_height: u32,
        timestamp: u64,
        is_block_winner: bool,
    }

    struct BlockTemplatRegistered has copy, drop {
        template_id: address,
        template_hash: vector<u8>,
        height: u32,
        previous_block: vector<u8>,
        timestamp: u64,
    }

    struct ShareTraded has copy, drop {
        share_id: address,
        from: address,
        to: address,
        timestamp: u64,
    }

    /// Initialize the share registry (called once on deployment)
    fun init(ctx: &mut TxContext) {
        let registry = ShareRegistry {
            id: object::new(ctx),
            shares: table::new(ctx),
            templates: table::new(ctx),
            total_shares: 0,
            total_templates: 0,
            total_block_winners: 0,
        };
        transfer::share_object(registry);
    }

    /// Register a block template on Sui
    public entry fun register_block_template(
        registry: &mut ShareRegistry,
        template_hash: vector<u8>,
        height: u32,
        previous_block_hash: vector<u8>,
        merkle_root: vector<u8>,
        version: u32,
        bits: u32,
        coinbase_value: u64,
        timestamp: u64,
        tx_count: u32,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if template already registered
        assert!(!table::contains(&registry.templates, template_hash), E_DUPLICATE_SHARE);

        let block_template = BlockTemplate {
            id: object::new(ctx),
            template_hash: template_hash,
            height,
            previous_block_hash,
            merkle_root,
            version,
            bits,
            coinbase_value,
            timestamp,
            tx_count,
            registered_at: clock::timestamp_ms(clock),
        };

        let template_id = object::uid_to_address(&block_template.id);

        // Mark template as registered
        table::add(&mut registry.templates, template_hash, true);
        registry.total_templates = registry.total_templates + 1;

        // Emit event
        event::emit(BlockTemplatRegistered {
            template_id,
            template_hash: template_hash,
            height,
            previous_block: previous_block_hash,
            timestamp: clock::timestamp_ms(clock),
        });

        // Share the template object
        transfer::share_object(block_template);
    }

    /// Verify and mint a mining share as an NFT
    public entry fun mint_share(
        registry: &mut ShareRegistry,
        block_header_hash: vector<u8>,
        share_hash: vector<u8>,
        previous_share_hash: vector<u8>,
        miner_pubkey_hash: vector<u8>,
        difficulty_bits: u32,
        difficulty_target: vector<u8>,
        block_height: u32,
        timestamp: u64,
        nonce: u32,
        subsidy: u64,
        block_template_id: vector<u8>,
        is_block_winner: bool,
        // For verification: the data that should hash to share_hash
        share_data_to_verify: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if share already exists
        assert!(!table::contains(&registry.shares, share_hash), E_DUPLICATE_SHARE);

        // Verify the share hash matches the provided data
        let computed_hash = sha2_256(share_data_to_verify);
        assert!(computed_hash == share_hash, E_INVALID_SHARE);

        // Verify difficulty (hash must be less than target)
        assert!(is_hash_below_target(&block_header_hash, &difficulty_target), E_INVALID_DIFFICULTY);

        let share = MiningShare {
            id: object::new(ctx),
            block_header_hash,
            share_hash: share_hash,
            previous_share_hash,
            miner_pubkey_hash: miner_pubkey_hash,
            difficulty_bits,
            difficulty_target,
            block_height,
            timestamp,
            nonce,
            subsidy,
            block_template_id,
            is_block_winner,
            minted_at: clock::timestamp_ms(clock),
            owner: tx_context::sender(ctx),
        };

        let share_id = object::uid_to_address(&share.id);

        // Mark share as registered
        table::add(&mut registry.shares, share_hash, true);
        registry.total_shares = registry.total_shares + 1;

        if (is_block_winner) {
            registry.total_block_winners = registry.total_block_winners + 1;
        };

        // Emit event
        event::emit(ShareMinted {
            share_id,
            share_hash: share_hash,
            miner: miner_pubkey_hash,
            difficulty_bits,
            block_height,
            timestamp,
            is_block_winner,
        });

        // Transfer the share NFT to the miner
        transfer::transfer(share, tx_context::sender(ctx));
    }

    /// Transfer share ownership (trading)
    public entry fun transfer_share(
        share: MiningShare,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        event::emit(ShareTraded {
            share_id: object::uid_to_address(&share.id),
            from: sender,
            to: recipient,
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::transfer(share, recipient);
    }

    /// Sell share for SUI tokens (simple direct sale)
    public entry fun sell_share(
        share: MiningShare,
        payment: Coin<SUI>,
        expected_amount: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify payment amount
        assert!(coin::value(&payment) >= expected_amount, 0);

        // Transfer payment to share seller
        transfer::public_transfer(payment, sender);

        // Emit trade event
        event::emit(ShareTraded {
            share_id: object::uid_to_address(&share.id),
            from: sender,
            to: recipient,
            timestamp: clock::timestamp_ms(clock),
        });

        // Transfer share to buyer
        transfer::transfer(share, recipient);
    }

    /// Helper function to verify hash is below target
    fun is_hash_below_target(hash: &vector<u8>, target: &vector<u8>): bool {
        let len = vector::length(hash);
        let i = 0;

        while (i < len) {
            let hash_byte = *vector::borrow(hash, i);
            let target_byte = *vector::borrow(target, i);

            if (hash_byte < target_byte) {
                return true
            } else if (hash_byte > target_byte) {
                return false
            };
            i = i + 1;
        };

        // Equal means valid (hash == target)
        true
    }

    // === Getter functions ===

    public fun get_share_hash(share: &MiningShare): vector<u8> {
        share.share_hash
    }

    public fun get_share_miner(share: &MiningShare): vector<u8> {
        share.miner_pubkey_hash
    }

    public fun get_share_difficulty(share: &MiningShare): u32 {
        share.difficulty_bits
    }

    public fun get_share_height(share: &MiningShare): u32 {
        share.block_height
    }

    public fun is_share_block_winner(share: &MiningShare): bool {
        share.is_block_winner
    }

    public fun get_registry_stats(registry: &ShareRegistry): (u64, u64, u64) {
        (registry.total_shares, registry.total_templates, registry.total_block_winners)
    }
}
