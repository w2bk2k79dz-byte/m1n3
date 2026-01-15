module p2pool_shares::m1n3_verification {
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

    /// Error codes
    const E_BLOCK_ALREADY_REGISTERED: u64 = 1;
    const E_BLOCK_NOT_FOUND: u64 = 2;
    const E_INVALID_BLOCK_HEADER: u64 = 3;
    const E_FIELD_ALREADY_SUBMITTED: u64 = 4;
    const E_INVALID_FIELD_DATA: u64 = 5;
    const E_VERIFICATION_FAILED: u64 = 6;
    const E_SESSION_CLOSED: u64 = 7;
    const E_NOT_REGISTERED_NODE: u64 = 8;
    const E_MERKLE_ROOT_DISABLED: u64 = 9;

    /// Granularity levels for field division
    const GRANULARITY_BYTE: u8 = 0;  // Divide by byte
    const GRANULARITY_BIT: u8 = 1;   // Divide by bit

    /// Bitcoin block header structure (80 bytes)
    struct BlockHeader has key, store {
        id: UID,
        /// Block height
        height: u32,
        /// Block header hash (double SHA-256)
        header_hash: vector<u8>,
        /// Version (4 bytes)
        version: u32,
        /// Previous block hash (32 bytes)
        prev_block_hash: vector<u8>,
        /// Merkle root (32 bytes) - DISABLED FOR NOW
        merkle_root: vector<u8>,
        /// Timestamp (4 bytes)
        timestamp: u32,
        /// Difficulty bits (4 bytes)
        bits: u32,
        /// Nonce (4 bytes)
        nonce: u32,
        /// Block subsidy in satoshis
        subsidy: u64,
        /// Registered timestamp
        registered_at: u64,
    }

    /// Verification session for a block
    struct VerificationSession has key, store {
        id: UID,
        /// Block height
        block_height: u32,
        /// Reference to block header
        block_header_id: ID,
        /// Registered nodes (address => true)
        registered_nodes: Table<address, bool>,
        /// Number of registered nodes
        node_count: u32,
        /// Current granularity level
        granularity: u8,
        /// Submitted fields (field_id => submitter_address)
        submitted_fields: Table<u64, address>,
        /// Verified fields (field_id => verified_data)
        verified_fields: Table<u64, vector<u8>>,
        /// Total reward pool for this block (subsidy * 1000)
        total_reward: u64,
        /// Block verification reward (50% of total) - excluding merkle root
        block_reward: u64,
        /// Merkle root reward (50% of total) - DISABLED
        merkle_reward: u64,
        /// Rewards claimed by each node
        rewards_claimed: Table<address, u64>,
        /// Session status
        is_active: bool,
        /// Session created timestamp
        created_at: u64,
    }

    /// Field submission
    struct FieldSubmission has key {
        id: UID,
        session_id: ID,
        block_height: u32,
        field_id: u64,
        field_data: vector<u8>,
        submitter: address,
        submitted_at: u64,
        is_verified: bool,
    }

    /// Global block registry
    struct BlockRegistry has key {
        id: UID,
        /// Maps block height => block header ID
        blocks: Table<u32, ID>,
        /// Maps block height => verification session ID
        sessions: Table<u32, ID>,
        /// Total blocks registered
        total_blocks: u64,
        /// Total verifications completed
        total_verifications: u64,
        /// Total active nodes across all sessions
        total_active_nodes: u64,
    }

    /// Events
    struct BlockRegistered has copy, drop {
        height: u32,
        header_hash: vector<u8>,
        subsidy: u64,
        total_reward: u64,
    }

    struct NodeRegisteredForVerification has copy, drop {
        block_height: u32,
        node: address,
        node_count: u32,
        granularity: u8,
    }

    struct FieldVerified has copy, drop {
        block_height: u32,
        field_id: u64,
        submitter: address,
        reward_amount: u64,
    }

    struct BlockFullyVerified has copy, drop {
        block_height: u32,
        total_fields_verified: u64,
        total_rewards_distributed: u64,
    }

    /// Initialize registry
    fun init(ctx: &mut TxContext) {
        let registry = BlockRegistry {
            id: object::new(ctx),
            blocks: table::new(ctx),
            sessions: table::new(ctx),
            total_blocks: 0,
            total_verifications: 0,
            total_active_nodes: 0,
        };
        transfer::share_object(registry);
    }

    /// Register a Bitcoin block header
    public entry fun register_block_header(
        registry: &mut BlockRegistry,
        treasury: &mut M1N3Treasury,
        height: u32,
        header_hash: vector<u8>,
        version: u32,
        prev_block_hash: vector<u8>,
        merkle_root: vector<u8>,
        timestamp: u32,
        bits: u32,
        nonce: u32,
        subsidy: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if block already registered
        assert!(!table::contains(&registry.blocks, height), E_BLOCK_ALREADY_REGISTERED);

        // Verify block header hash
        let header_data = construct_block_header(
            version, prev_block_hash, merkle_root, timestamp, bits, nonce
        );
        let computed_hash = double_sha256(header_data);
        assert!(computed_hash == header_hash, E_INVALID_BLOCK_HEADER);

        // Create block header
        let block = BlockHeader {
            id: object::new(ctx),
            height,
            header_hash,
            version,
            prev_block_hash,
            merkle_root,
            timestamp,
            bits,
            nonce,
            subsidy,
            registered_at: clock::timestamp_ms(clock),
        };

        let block_id = object::uid_to_inner(&block.id);

        // Calculate rewards: subsidy * 1000
        let total_reward = subsidy * 1000;
        // Split 50/50: block verification and merkle root (but merkle is disabled)
        let block_reward = total_reward / 2;
        let merkle_reward = total_reward / 2;

        // Create verification session
        let session = VerificationSession {
            id: object::new(ctx),
            block_height: height,
            block_header_id: block_id,
            registered_nodes: table::new(ctx),
            node_count: 0,
            granularity: GRANULARITY_BYTE,
            submitted_fields: table::new(ctx),
            verified_fields: table::new(ctx),
            total_reward,
            block_reward, // This is what nodes will earn (merkle disabled)
            merkle_reward, // DISABLED - not distributed
            rewards_claimed: table::new(ctx),
            is_active: true,
            created_at: clock::timestamp_ms(clock),
        };

        let session_id = object::uid_to_inner(&session.id);

        // Update registry
        table::add(&mut registry.blocks, height, block_id);
        table::add(&mut registry.sessions, height, session_id);
        registry.total_blocks = registry.total_blocks + 1;

        // Record in treasury
        m1n3_token::record_block_registration(treasury);

        // Emit event
        event::emit(BlockRegistered {
            height,
            header_hash,
            subsidy,
            total_reward,
        });

        // Share objects
        transfer::share_object(block);
        transfer::share_object(session);
    }

    /// Node registers interest in verifying a block
    public entry fun register_for_verification(
        session: &mut VerificationSession,
        ctx: &mut TxContext
    ) {
        assert!(session.is_active, E_SESSION_CLOSED);

        let sender = tx_context::sender(ctx);

        // Check if already registered
        if (!table::contains(&session.registered_nodes, sender)) {
            table::add(&mut session.registered_nodes, sender, true);
            session.node_count = session.node_count + 1;

            // Adjust granularity based on node count
            // More nodes = finer granularity
            if (session.node_count > 100) {
                session.granularity = GRANULARITY_BIT; // Bit level
            } else {
                session.granularity = GRANULARITY_BYTE; // Byte level
            };

            event::emit(NodeRegisteredForVerification {
                block_height: session.block_height,
                node: sender,
                node_count: session.node_count,
                granularity: session.granularity,
            });
        };
    }

    /// Submit and verify a block field
    /// Field IDs:
    /// 0 = version (4 bytes)
    /// 1 = prev_block_hash (32 bytes)
    /// 2 = merkle_root (32 bytes) - DISABLED
    /// 3 = timestamp (4 bytes)
    /// 4 = bits (4 bytes)
    /// 5 = nonce (4 bytes)
    public entry fun submit_field(
        session: &mut VerificationSession,
        block: &BlockHeader,
        treasury: &mut M1N3Treasury,
        field_id: u64,
        field_data: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(session.is_active, E_SESSION_CLOSED);
        let sender = tx_context::sender(ctx);

        // Verify node is registered
        assert!(table::contains(&session.registered_nodes, sender), E_NOT_REGISTERED_NODE);

        // Check if field already submitted
        assert!(!table::contains(&session.submitted_fields, field_id), E_FIELD_ALREADY_SUBMITTED);

        // Merkle root is disabled
        assert!(field_id != 2, E_MERKLE_ROOT_DISABLED);

        // Verify field data
        let is_valid = verify_field(block, field_id, &field_data);
        assert!(is_valid, E_INVALID_FIELD_DATA);

        // Mark field as submitted and verified
        table::add(&mut session.submitted_fields, field_id, sender);
        table::add(&mut session.verified_fields, field_id, field_data);

        // Calculate reward for this field
        // Total fields (excluding merkle root): 5 fields
        let total_fields: u64 = 5;
        let field_reward = session.block_reward / total_fields;

        // Mint reward
        let reward_coin = m1n3_token::mint_reward(treasury, field_reward, ctx);

        // Track reward
        if (table::contains(&session.rewards_claimed, sender)) {
            let current = table::remove(&mut session.rewards_claimed, sender);
            table::add(&mut session.rewards_claimed, sender, current + field_reward);
        } else {
            table::add(&mut session.rewards_claimed, sender, field_reward);
        };

        // Transfer reward to submitter
        transfer::public_transfer(reward_coin, sender);

        // Emit event
        event::emit(FieldVerified {
            block_height: session.block_height,
            field_id,
            submitter: sender,
            reward_amount: field_reward,
        });

        // Check if all fields verified (5 fields, excluding merkle root)
        if (table::length(&session.verified_fields) == total_fields) {
            session.is_active = false;

            event::emit(BlockFullyVerified {
                block_height: session.block_height,
                total_fields_verified: total_fields,
                total_rewards_distributed: session.block_reward,
            });
        };
    }

    /// Verify a field against the block header
    fun verify_field(block: &BlockHeader, field_id: u64, data: &vector<u8>): bool {
        if (field_id == 0) {
            // Version (4 bytes, little-endian)
            let expected = u32_to_bytes_le(block.version);
            &expected == data
        } else if (field_id == 1) {
            // Previous block hash (32 bytes)
            &block.prev_block_hash == data
        } else if (field_id == 2) {
            // Merkle root - DISABLED
            false
        } else if (field_id == 3) {
            // Timestamp (4 bytes, little-endian)
            let expected = u32_to_bytes_le(block.timestamp);
            &expected == data
        } else if (field_id == 4) {
            // Bits (4 bytes, little-endian)
            let expected = u32_to_bytes_le(block.bits);
            &expected == data
        } else if (field_id == 5) {
            // Nonce (4 bytes, little-endian)
            let expected = u32_to_bytes_le(block.nonce);
            &expected == data
        } else {
            false
        }
    }

    /// Construct block header bytes (80 bytes)
    fun construct_block_header(
        version: u32,
        prev_block: vector<u8>,
        merkle_root: vector<u8>,
        timestamp: u32,
        bits: u32,
        nonce: u32
    ): vector<u8> {
        let header = vector::empty<u8>();

        // Version (4 bytes, little-endian)
        vector::append(&mut header, u32_to_bytes_le(version));

        // Previous block hash (32 bytes)
        vector::append(&mut header, prev_block);

        // Merkle root (32 bytes)
        vector::append(&mut header, merkle_root);

        // Timestamp (4 bytes, little-endian)
        vector::append(&mut header, u32_to_bytes_le(timestamp));

        // Bits (4 bytes, little-endian)
        vector::append(&mut header, u32_to_bytes_le(bits));

        // Nonce (4 bytes, little-endian)
        vector::append(&mut header, u32_to_bytes_le(nonce));

        header
    }

    /// Double SHA-256 (Bitcoin's hash function)
    fun double_sha256(data: vector<u8>): vector<u8> {
        let hash1 = sha2_256(data);
        sha2_256(hash1)
    }

    /// Convert u32 to little-endian bytes
    fun u32_to_bytes_le(value: u32): vector<u8> {
        let bytes = vector::empty<u8>();
        vector::push_back(&mut bytes, ((value & 0xFF) as u8));
        vector::push_back(&mut bytes, (((value >> 8) & 0xFF) as u8));
        vector::push_back(&mut bytes, (((value >> 16) & 0xFF) as u8));
        vector::push_back(&mut bytes, (((value >> 24) & 0xFF) as u8));
        bytes
    }

    /// Get session info
    public fun get_session_info(session: &VerificationSession): (u32, u32, u8, u64, bool) {
        (
            session.block_height,
            session.node_count,
            session.granularity,
            session.total_reward,
            session.is_active
        )
    }

    /// Get block info
    public fun get_block_info(block: &BlockHeader): (u32, vector<u8>, u64) {
        (block.height, block.header_hash, block.subsidy)
    }
}
