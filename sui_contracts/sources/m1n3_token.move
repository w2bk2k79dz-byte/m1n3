module p2pool_shares::m1n3_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use std::option::{Self, Option};

    /// M1N3 Token - rewards for Bitcoin block verification
    struct M1N3 has drop {}

    /// Token treasury and global state
    struct M1N3Treasury has key {
        id: UID,
        treasury_cap: TreasuryCap<M1N3>,
        /// Total tokens minted
        total_minted: u64,
        /// Total blocks registered
        total_blocks_registered: u64,
        /// Total rewards distributed
        total_rewards_distributed: u64,
    }

    /// Initialize M1N3 token
    fun init(witness: M1N3, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            8, // decimals (like Bitcoin)
            b"M1N3",
            b"M1N3 Token",
            b"Decentralized trustless Bitcoin mining verification token",
            option::none(),
            ctx
        );

        // Share metadata publicly
        transfer::public_freeze_object(metadata);

        // Create treasury
        let treasury = M1N3Treasury {
            id: object::new(ctx),
            treasury_cap,
            total_minted: 0,
            total_blocks_registered: 0,
            total_rewards_distributed: 0,
        };

        transfer::share_object(treasury);
    }

    /// Mint tokens as rewards (only callable by block verification module)
    public(friend) fun mint_reward(
        treasury: &mut M1N3Treasury,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<M1N3> {
        treasury.total_minted = treasury.total_minted + amount;
        treasury.total_rewards_distributed = treasury.total_rewards_distributed + amount;
        coin::mint(&mut treasury.treasury_cap, amount, ctx)
    }

    /// Record a block registration
    public(friend) fun record_block_registration(treasury: &mut M1N3Treasury) {
        treasury.total_blocks_registered = treasury.total_blocks_registered + 1;
    }

    /// Get treasury stats
    public fun get_stats(treasury: &M1N3Treasury): (u64, u64, u64) {
        (treasury.total_minted, treasury.total_blocks_registered, treasury.total_rewards_distributed)
    }

    /// Burn tokens (if needed)
    public fun burn(treasury: &mut M1N3Treasury, coin: Coin<M1N3>) {
        coin::burn(&mut treasury.treasury_cap, coin);
    }
}
