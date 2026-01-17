module p2pool_shares::m1n3_dwallet {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::table::{Self, Table};
    use std::vector;

    /// Error codes
    const E_INVALID_NETWORK: u64 = 1;
    const E_INVALID_REGISTRY: u64 = 2;

    /// Shared dWallet for autonomous PPLNS reward distribution
    /// Sui network maintains accountability, IKA network executes Bitcoin transactions automatically
    struct SharedDWallet has key, store {
        id: UID,
        /// Bitcoin address derived from IKA dWallet
        bitcoin_address: vector<u8>,
        /// IKA dWallet capability ID
        dwallet_cap_id: vector<u8>,
        /// Bitcoin network (mainnet, testnet, signet)
        network: vector<u8>,
        /// Mining registry ID for PPLNS verification
        mining_registry_id: ID,
        /// Distribution history (distribution_id => execution status)
        distributions: Table<u64, DistributionRecord>,
        /// Total distributions proposed
        distribution_count: u64,
        /// Total Bitcoin distributed (in satoshis)
        total_distributed: u64,
        /// Created at timestamp
        created_at: u64,
    }

    /// Record of a PPLNS distribution
    /// IKA network reads this from Sui to execute Bitcoin transactions
    struct DistributionRecord has store, drop {
        /// Distribution ID
        distribution_id: u64,
        /// Block height this distribution is for
        block_height: u32,
        /// Coinbase value (satoshis)
        coinbase_value: u64,
        /// Total recipients
        recipient_count: u64,
        /// Total amount distributed
        total_amount: u64,
        /// Timestamp when proposed
        proposed_at: u64,
        /// IKA execution status
        executed: bool,
        /// Execution timestamp (set by IKA callback)
        executed_at: u64,
    }

    /// Recipient for Bitcoin payout
    struct Recipient has store, drop, copy {
        /// Bitcoin address (base58 encoded)
        bitcoin_address: vector<u8>,
        /// Amount in satoshis
        amount: u64,
        /// Miner's Sui address (for accountability)
        miner_address: address,
        /// Share difficulty contribution
        difficulty: u64,
    }

    /// ==================== EVENTS FOR IKA NETWORK ====================
    /// IKA network listens to these events and automatically executes Bitcoin transactions

    /// Emitted when dWallet is created
    struct DWalletCreated has copy, drop {
        dwallet_id: address,
        bitcoin_address: vector<u8>,
        dwallet_cap_id: vector<u8>,
        network: vector<u8>,
        mining_registry_id: address,
        timestamp: u64,
    }

    /// Emitted when PPLNS distribution is proposed
    /// IKA network reads this and automatically executes the Bitcoin transaction
    struct PPLNSDistributionProposed has copy, drop {
        dwallet_id: address,
        distribution_id: u64,
        block_height: u32,
        coinbase_value: u64,
        total_amount: u64,
        recipient_count: u64,
        /// Serialized recipient data for IKA to parse
        /// Format: repeated (btc_addr_len | btc_addr | amount_u64 | sui_addr | difficulty_u64)
        recipients_data: vector<u8>,
        timestamp: u64,
    }

    /// Emitted when IKA confirms execution
    struct DistributionExecuted has copy, drop {
        dwallet_id: address,
        distribution_id: u64,
        bitcoin_txid: vector<u8>,
        total_amount: u64,
        timestamp: u64,
    }

    /// Create a new shared dWallet for PPLNS pool
    /// This dWallet's Bitcoin address will receive block coinbase rewards
    public entry fun create_shared_dwallet(
        bitcoin_address: vector<u8>,
        dwallet_cap_id: vector<u8>,
        network: vector<u8>,
        mining_registry_id: ID,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        let dwallet = SharedDWallet {
            id: object::new(ctx),
            bitcoin_address,
            dwallet_cap_id,
            network,
            mining_registry_id,
            distributions: table::new(ctx),
            distribution_count: 0,
            total_distributed: 0,
            created_at: sui::clock::timestamp_ms(clock),
        };

        let dwallet_addr = object::uid_to_address(&dwallet.id);
        let registry_addr = object::id_to_address(&mining_registry_id);

        // Emit event for IKA network to register this dWallet
        event::emit(DWalletCreated {
            dwallet_id: dwallet_addr,
            bitcoin_address,
            dwallet_cap_id,
            network,
            mining_registry_id: registry_addr,
            timestamp: sui::clock::timestamp_ms(clock),
        });

        // Share the dWallet - makes it publicly accessible
        transfer::share_object(dwallet);
    }

    /// Propose PPLNS distribution for a found block
    /// IKA network will automatically execute this based on Sui data
    /// Anyone can propose, but IKA verifies against on-chain share window
    public entry fun propose_pplns_distribution(
        dwallet: &mut SharedDWallet,
        block_height: u32,
        coinbase_value: u64,
        recipients: vector<Recipient>,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        // Calculate total amount
        let total_amount: u64 = 0;
        let i = 0;
        let len = vector::length(&recipients);
        while (i < len) {
            let recipient = vector::borrow(&recipients, i);
            total_amount = total_amount + recipient.amount;
            i = i + 1;
        };

        // Create distribution record
        let distribution_id = dwallet.distribution_count;
        let record = DistributionRecord {
            distribution_id,
            block_height,
            coinbase_value,
            recipient_count: len,
            total_amount,
            proposed_at: sui::clock::timestamp_ms(clock),
            executed: false,
            executed_at: 0,
        };

        // Store record
        table::add(&mut dwallet.distributions, distribution_id, record);
        dwallet.distribution_count = dwallet.distribution_count + 1;

        // Serialize recipients for IKA
        let recipients_data = serialize_recipients(&recipients);

        // Emit event for IKA network to consume
        // IKA will:
        // 1. Read this event
        // 2. Verify distribution matches share window on Sui
        // 3. Automatically sign and broadcast Bitcoin transaction
        // 4. Call mark_distribution_executed() after confirmation
        event::emit(PPLNSDistributionProposed {
            dwallet_id: object::uid_to_address(&dwallet.id),
            distribution_id,
            block_height,
            coinbase_value,
            total_amount,
            recipient_count: len,
            recipients_data,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Called by IKA network after successfully executing Bitcoin transaction
    /// This is the only "callback" - IKA confirms execution
    public entry fun mark_distribution_executed(
        dwallet: &mut SharedDWallet,
        distribution_id: u64,
        bitcoin_txid: vector<u8>,
        clock: &sui::clock::Clock,
        _ctx: &mut TxContext
    ) {
        // Get distribution record
        let record = table::borrow_mut(&mut dwallet.distributions, distribution_id);

        // Mark as executed
        record.executed = true;
        record.executed_at = sui::clock::timestamp_ms(clock);

        // Update total distributed
        dwallet.total_distributed = dwallet.total_distributed + record.total_amount;

        // Emit confirmation event
        event::emit(DistributionExecuted {
            dwallet_id: object::uid_to_address(&dwallet.id),
            distribution_id,
            bitcoin_txid,
            total_amount: record.total_amount,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Helper: Serialize recipients for IKA network
    /// Format: For each recipient: btc_addr_len(u8) | btc_addr | amount(u64) | sui_addr(32 bytes) | difficulty(u64)
    fun serialize_recipients(recipients: &vector<Recipient>): vector<u8> {
        let data = vector::empty<u8>();
        let i = 0;
        let len = vector::length(recipients);

        while (i < len) {
            let recipient = vector::borrow(recipients, i);

            // Bitcoin address length (1 byte)
            let btc_addr_len = (vector::length(&recipient.bitcoin_address) as u8);
            vector::push_back(&mut data, btc_addr_len);

            // Bitcoin address bytes
            vector::append(&mut data, recipient.bitcoin_address);

            // Amount (8 bytes, little-endian u64)
            append_u64(&mut data, recipient.amount);

            // Miner Sui address (32 bytes)
            // Note: In production, properly serialize the address
            // For now, placeholder
            let j = 0;
            while (j < 32) {
                vector::push_back(&mut data, 0);
                j = j + 1;
            };

            // Difficulty (8 bytes, little-endian u64)
            append_u64(&mut data, recipient.difficulty);

            i = i + 1;
        };

        data
    }

    /// Helper: Append u64 as little-endian bytes
    fun append_u64(data: &mut vector<u8>, value: u64) {
        vector::push_back(data, ((value >> 0) & 0xFF as u8));
        vector::push_back(data, ((value >> 8) & 0xFF as u8));
        vector::push_back(data, ((value >> 16) & 0xFF as u8));
        vector::push_back(data, ((value >> 24) & 0xFF as u8));
        vector::push_back(data, ((value >> 32) & 0xFF as u8));
        vector::push_back(data, ((value >> 40) & 0xFF as u8));
        vector::push_back(data, ((value >> 48) & 0xFF as u8));
        vector::push_back(data, ((value >> 56) & 0xFF as u8));
    }

    /// Get dWallet info
    public fun get_dwallet_info(dwallet: &SharedDWallet): (vector<u8>, u64, u64) {
        (
            dwallet.bitcoin_address,
            dwallet.distribution_count,
            dwallet.total_distributed
        )
    }

    /// Get distribution record
    public fun get_distribution(dwallet: &SharedDWallet, distribution_id: u64): (u32, u64, u64, bool, u64) {
        let record = table::borrow(&dwallet.distributions, distribution_id);
        (
            record.block_height,
            record.coinbase_value,
            record.total_amount,
            record.executed,
            record.executed_at
        )
    }

    /// Create recipient entry
    public fun create_recipient(
        bitcoin_address: vector<u8>,
        amount: u64,
        miner_address: address,
        difficulty: u64
    ): Recipient {
        Recipient {
            bitcoin_address,
            amount,
            miner_address,
            difficulty,
        }
    }
}
