module p2pool_shares::m1n3_dwallet {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::table::{Self, Table};
    use std::vector;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_DWALLET_ALREADY_EXISTS: u64 = 2;
    const E_INVALID_THRESHOLD: u64 = 3;
    const E_INSUFFICIENT_APPROVALS: u64 = 4;

    /// Shared dWallet for autonomous PPLNS reward distribution
    /// This is a public/shared object that anyone can interact with,
    /// but requires threshold signatures for actual Bitcoin transactions
    struct SharedDWallet has key, store {
        id: UID,
        /// Bitcoin address derived from dWallet
        bitcoin_address: vector<u8>,
        /// dWallet capability ID from IKA
        dwallet_cap_id: vector<u8>,
        /// Network (mainnet, testnet, signet)
        network: vector<u8>,
        /// Threshold for signatures (e.g., 2 for 2-of-3)
        threshold: u8,
        /// Total participants in the dWallet
        total_participants: u8,
        /// Authorized signers (participant addresses)
        authorized_signers: vector<address>,
        /// Pending transactions awaiting signatures
        pending_transactions: Table<ID, PendingTransaction>,
        /// Total transactions processed
        total_transactions: u64,
        /// Total Bitcoin distributed (in satoshis)
        total_distributed: u64,
        /// Created at timestamp
        created_at: u64,
    }

    /// Pending transaction awaiting threshold signatures
    struct PendingTransaction has store, drop {
        /// Transaction ID
        tx_id: ID,
        /// Recipients and amounts (Bitcoin address => satoshis)
        recipients: vector<Recipient>,
        /// Total amount to distribute
        total_amount: u64,
        /// Signers who have approved
        approvals: vector<address>,
        /// Created timestamp
        created_at: u64,
        /// Purpose/description
        purpose: vector<u8>,
    }

    /// Recipient for Bitcoin payout
    struct Recipient has store, drop, copy {
        /// Bitcoin address (base58 encoded)
        bitcoin_address: vector<u8>,
        /// Amount in satoshis
        amount: u64,
        /// M1N3 miner address (for tracking)
        miner_address: address,
    }

    /// Events
    struct DWalletCreated has copy, drop {
        dwallet_id: address,
        bitcoin_address: vector<u8>,
        network: vector<u8>,
        threshold: u8,
        total_participants: u8,
        timestamp: u64,
    }

    struct TransactionProposed has copy, drop {
        dwallet_id: address,
        tx_id: address,
        total_amount: u64,
        recipient_count: u64,
        proposer: address,
        timestamp: u64,
    }

    struct TransactionSigned has copy, drop {
        dwallet_id: address,
        tx_id: address,
        signer: address,
        approvals: u64,
        threshold: u8,
        timestamp: u64,
    }

    struct TransactionExecuted has copy, drop {
        dwallet_id: address,
        tx_id: address,
        total_amount: u64,
        recipient_count: u64,
        timestamp: u64,
    }

    /// Create a new shared dWallet for PPLNS pool
    /// This creates a public dWallet that anyone can query but requires
    /// threshold signatures to execute Bitcoin transactions
    public entry fun create_shared_dwallet(
        bitcoin_address: vector<u8>,
        dwallet_cap_id: vector<u8>,
        network: vector<u8>,
        threshold: u8,
        authorized_signers: vector<address>,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        let total_participants = (vector::length(&authorized_signers) as u8);

        // Validate threshold
        assert!(threshold > 0 && threshold <= total_participants, E_INVALID_THRESHOLD);

        let dwallet = SharedDWallet {
            id: object::new(ctx),
            bitcoin_address,
            dwallet_cap_id,
            network,
            threshold,
            total_participants,
            authorized_signers,
            pending_transactions: table::new(ctx),
            total_transactions: 0,
            total_distributed: 0,
            created_at: sui::clock::timestamp_ms(clock),
        };

        let dwallet_addr = object::uid_to_address(&dwallet.id);

        event::emit(DWalletCreated {
            dwallet_id: dwallet_addr,
            bitcoin_address,
            network,
            threshold,
            total_participants,
            timestamp: sui::clock::timestamp_ms(clock),
        });

        // Share the dWallet - makes it accessible to everyone
        transfer::share_object(dwallet);
    }

    /// Propose a new Bitcoin transaction for PPLNS rewards
    /// Anyone can propose, but execution requires threshold signatures
    public entry fun propose_pplns_distribution(
        dwallet: &mut SharedDWallet,
        recipients: vector<Recipient>,
        purpose: vector<u8>,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Calculate total amount
        let total_amount: u64 = 0;
        let i = 0;
        let len = vector::length(&recipients);
        while (i < len) {
            let recipient = vector::borrow(&recipients, i);
            total_amount = total_amount + recipient.amount;
            i = i + 1;
        };

        // Create pending transaction
        let tx_id = object::new(ctx);
        let tx_id_inner = object::uid_to_inner(&tx_id);
        let tx_id_addr = object::uid_to_address(&tx_id);

        let pending_tx = PendingTransaction {
            tx_id: tx_id_inner,
            recipients,
            total_amount,
            approvals: vector::empty<address>(),
            created_at: sui::clock::timestamp_ms(clock),
            purpose,
        };

        // Store pending transaction
        table::add(&mut dwallet.pending_transactions, tx_id_inner, pending_tx);

        event::emit(TransactionProposed {
            dwallet_id: object::uid_to_address(&dwallet.id),
            tx_id: tx_id_addr,
            total_amount,
            recipient_count: len,
            proposer: sender,
            timestamp: sui::clock::timestamp_ms(clock),
        });

        // Clean up tx_id object
        object::delete(tx_id);
    }

    /// Sign a pending transaction (requires authorized signer)
    public entry fun sign_transaction(
        dwallet: &mut SharedDWallet,
        tx_id: ID,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Verify sender is authorized signer
        assert!(is_authorized_signer(dwallet, sender), E_NOT_AUTHORIZED);

        // Get pending transaction
        let pending_tx = table::borrow_mut(&mut dwallet.pending_transactions, tx_id);

        // Check if already signed
        if (!vector::contains(&pending_tx.approvals, &sender)) {
            vector::push_back(&mut pending_tx.approvals, sender);
        };

        let approval_count = vector::length(&pending_tx.approvals);

        event::emit(TransactionSigned {
            dwallet_id: object::uid_to_address(&dwallet.id),
            tx_id: object::uid_to_address_inner(tx_id),
            signer: sender,
            approvals: approval_count,
            threshold: dwallet.threshold,
            timestamp: sui::clock::timestamp_ms(clock),
        });

        // If threshold reached, mark ready for execution
        // In production, this would trigger IKA 2PC-MPC signing
        if (approval_count >= (dwallet.threshold as u64)) {
            // Transaction is ready for execution
            // Note: Actual Bitcoin transaction signing happens off-chain via IKA
            execute_transaction_internal(dwallet, tx_id, clock);
        };
    }

    /// Internal: Execute transaction after threshold is met
    fun execute_transaction_internal(
        dwallet: &mut SharedDWallet,
        tx_id: ID,
        clock: &sui::clock::Clock
    ) {
        // Remove from pending
        let pending_tx = table::remove(&mut dwallet.pending_transactions, tx_id);

        // Update stats
        dwallet.total_transactions = dwallet.total_transactions + 1;
        dwallet.total_distributed = dwallet.total_distributed + pending_tx.total_amount;

        event::emit(TransactionExecuted {
            dwallet_id: object::uid_to_address(&dwallet.id),
            tx_id: object::uid_to_address_inner(tx_id),
            total_amount: pending_tx.total_amount,
            recipient_count: vector::length(&pending_tx.recipients),
            timestamp: sui::clock::timestamp_ms(clock),
        });

        // Note: Actual Bitcoin transaction is signed and broadcast by IKA signers
        // listening to TransactionExecuted events
    }

    /// Helper: Check if address is authorized signer
    fun is_authorized_signer(dwallet: &SharedDWallet, addr: address): bool {
        vector::contains(&dwallet.authorized_signers, &addr)
    }

    /// Helper: Convert object ID to address for events
    fun object::uid_to_address_inner(id: ID): address {
        // This is a placeholder - in production, use proper ID to address conversion
        @0x0
    }

    /// Get dWallet info
    public fun get_dwallet_info(dwallet: &SharedDWallet): (vector<u8>, u8, u8, u64, u64) {
        (
            dwallet.bitcoin_address,
            dwallet.threshold,
            dwallet.total_participants,
            dwallet.total_transactions,
            dwallet.total_distributed
        )
    }

    /// Get pending transaction count
    public fun get_pending_count(dwallet: &SharedDWallet): u64 {
        table::length(&dwallet.pending_transactions)
    }

    /// Create recipient entry
    public fun create_recipient(
        bitcoin_address: vector<u8>,
        amount: u64,
        miner_address: address
    ): Recipient {
        Recipient {
            bitcoin_address,
            amount,
            miner_address,
        }
    }
}
