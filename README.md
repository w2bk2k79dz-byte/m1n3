# M1N3 - Decentralized Trustless Bitcoin Mining & Verification

M1N3 is a next-generation decentralized Bitcoin mining protocol based on P2Pool, featuring on-chain verification via Sui blockchain and a revolutionary share trading economy.

## Overview

M1N3 combines traditional P2Pool mining with blockchain verification and creates a tradeable share marketplace where miners can instantly monetize their work before blocks are found.

### Key Features

- **Phase 1**: Historical block header verification with coordinated field-level validation
- **Phase 2**: Real-time mining with staking security and on-chain share verification
- **Share Trading**: All valid shares become tradeable NFTs with a 2% fee benefiting stakers
- **PPS Redemption**: Shares can be redeemed for Bitcoin rewards proportional to their difficulty
- **Native Verification**: Uses Sui's native SHA-256 for trustless on-chain validation

## Requirements

### Generic
- Bitcoin Core >= 0.21.0 (with Taproot support)
- Python >= 2.7
- Twisted >= 10.0.0
- pysui >= 0.50.0

### Linux
```bash
sudo apt-get install python-zope.interface python-twisted python-twisted-web
pip install pysui
```

### Windows
1. Install [Python 2.7](http://www.python.org/getit/)
2. Install [Twisted](http://twistedmatrix.com/trac/wiki/Downloads)
3. Install [Zope.Interface](http://pypi.python.org/pypi/zope.interface/)
4. Install pysui: `pip install pysui`

## Bitcoin Full Node Requirement

**CRITICAL: M1N3 requires a fully synced Bitcoin Core node running locally.**

### Why Full Node is Required

M1N3's entire architecture depends on accessing complete Bitcoin blockchain data:

1. **Phase 1 - Historical Verification**:
   - Retrieves all historical block headers from Bitcoin Core
   - Fetches complete block data (version, prev_hash, merkle_root, timestamp, bits, nonce)
   - Reads coinbase transaction values for reward calculation
   - Requires complete blockchain history from genesis to current height

2. **Phase 2 - Real-Time Mining**:
   - Requests block templates via `getblocktemplate` RPC
   - Monitors mempool for transaction selection
   - Submits found blocks to Bitcoin network
   - Validates share difficulty against network target

3. **On-Chain Registration**:
   - Block headers registered on Sui are sourced from your Bitcoin node
   - Field verification data comes directly from block bytes
   - Ensures trustless verification through independent node validation

### Bitcoin Core Configuration

Create or edit `~/.bitcoin/bitcoin.conf`:

```conf
# RPC server settings (required)
server=1
rpcuser=your_rpc_username
rpcpassword=your_rpc_password
rpcport=8332

# Network settings
listen=1
daemon=1

# Required for getblocktemplate
txindex=1

# Taproot support (Bitcoin Core 0.21.0+)
# No additional flags needed, Taproot activated at block 709632

# Performance optimization
dbcache=4096
maxmempool=512

# For Phase 1 historical verification
# Keep full blockchain (no pruning)
prune=0
```

### Starting Bitcoin Core

```bash
# Start Bitcoin daemon
bitcoind -daemon

# Wait for full synchronization (may take several days)
bitcoin-cli getblockchaininfo

# Verify sync status
# Look for: "blocks" == "headers" and "initialblockdownload" == false
```

### Disk Space Requirements

- **Full Node**: ~500-600 GB for complete blockchain (as of 2026)
- **txindex enabled**: Additional ~50-100 GB for transaction index
- **Recommended**: 1 TB SSD for optimal performance

### RPC Access

M1N3 connects to Bitcoin Core via JSON-RPC. Required RPC methods:

**Phase 1 - Historical Verification**:
- `getblockchaininfo` - Get current blockchain state
- `getblockhash <height>` - Get block hash at specific height
- `getblock <hash> 0` - Get raw block data (hex)
- `getblock <hash> 1` - Get block details (JSON)
- `getrawtransaction` - Get coinbase transaction for subsidy

**Phase 2 - Real-Time Mining**:
- `getblocktemplate` - Get block template for mining
- `submitblock` - Submit found block to network
- `getpeerinfo` - Monitor network connectivity
- `getmininginfo` - Get mining difficulty and network hashrate

### Network Connectivity

Your Bitcoin node must be able to:
- Connect to Bitcoin P2P network (port 8333)
- Accept RPC connections from P2Pool (port 8332)
- Broadcast found blocks to the network

### Verification Process

**How Block Registration Works:**

1. **P2Pool queries Bitcoin Core**:
   ```python
   # Get block at specific height
   block_hash = bitcoind.rpc_getblockhash(height)
   block_data = bitcoind.rpc_getblock(block_hash, 0)  # Raw hex
   ```

2. **Parse block header** (80 bytes):
   ```
   Bytes 0-3:   Version (4 bytes)
   Bytes 4-35:  Previous block hash (32 bytes)
   Bytes 36-67: Merkle root (32 bytes)
   Bytes 68-71: Timestamp (4 bytes)
   Bytes 72-75: Difficulty bits (4 bytes)
   Bytes 76-79: Nonce (4 bytes)
   ```

3. **Register on Sui blockchain**:
   ```move
   public entry fun register_block(
       registry: &mut BlockRegistry,
       height: u32,
       header_data: vector<u8>,  // 80 bytes from Bitcoin Core
       subsidy: u64,             // From coinbase transaction
       ...
   )
   ```

4. **Verification session created**:
   - Other nodes query their own Bitcoin Core instances
   - Compare field data independently
   - Submit matching data on-chain
   - SHA-256 verification ensures correctness

**This creates trustless verification** - each node independently validates against their own full node, making collusion impossible.

### Quick Start for Bitcoin Node

```bash
# 1. Download Bitcoin Core 0.21.0 or newer
wget https://bitcoincore.org/bin/bitcoin-core-0.21.0/bitcoin-0.21.0-x86_64-linux-gnu.tar.gz

# 2. Extract and install
tar -xzf bitcoin-0.21.0-x86_64-linux-gnu.tar.gz
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-0.21.0/bin/*

# 3. Create configuration
mkdir -p ~/.bitcoin
cat > ~/.bitcoin/bitcoin.conf <<EOF
server=1
rpcuser=m1n3user
rpcpassword=$(openssl rand -base64 32)
rpcport=8332
txindex=1
dbcache=4096
prune=0
EOF

# 4. Start syncing (this will take time!)
bitcoind -daemon

# 5. Monitor sync progress
watch bitcoin-cli getblockchaininfo
```

### Recommended Hardware

For optimal M1N3 operation:

- **CPU**: 4+ cores (8+ recommended)
- **RAM**: 8 GB minimum (16 GB recommended)
- **Storage**: 1 TB SSD (NVMe preferred)
- **Network**: 100 Mbps+ with unlimited bandwidth
- **Uptime**: 24/7 operation recommended for Phase 2 mining

### Without Full Node

**M1N3 cannot operate without a local Bitcoin full node.** Alternative configurations:

- ❌ **SPV/Light clients**: Insufficient - cannot provide full block data
- ❌ **Block explorers**: Centralized - defeats trustless verification
- ❌ **Remote RPC**: Latency issues and trust assumptions
- ✅ **Local full node**: Required for trustless operation

## Architecture

### Phase 1: Historical Verification

Distribute M1N3 tokens by verifying all historical Bitcoin blocks:

1. **Block Registration**: Nodes register known Bitcoin block headers on Sui
2. **Field Division**: Block fields divided dynamically (byte or bit level) based on node count
3. **Verification**: Nodes submit field data, verified on-chain using SHA-256
4. **Rewards**: Block subsidy × 1000 M1N3 tokens (50% for block fields, 50% for Merkle root when enabled)

### Phase 2: Real-Time Mining

Decentralized mining with staking security:

1. **Staking**: Nodes stake 100,000+ M1N3 to become template proposers
2. **Template Proposal**: Staked nodes propose block templates (10-minute validity)
3. **Share Mining**: Miners find shares based on templates
4. **On-Chain Verification**: Shares verified against templates using Sui's SHA-256
5. **Rewards**: 95% to miner, 5% to template proposer

### Share Trading Economy

**Every valid share becomes a tradeable financial instrument:**

#### Share Properties
- **NFT Ownership**: Each share is a unique Sui object
- **Difficulty Metadata**: Share difficulty determines market value
- **Redeemable**: Can be exchanged for Bitcoin rewards via PPS
- **Tradeable**: Can be bought/sold on the open market

#### Trading Mechanics
1. **Instant Liquidity**: Miners can sell shares immediately without waiting for block
2. **Market Pricing**: Shares priced based on difficulty and block-finding probability
3. **2% Transfer Fee**: Every share transfer/sale incurs 2% fee to M1N3 stakers
4. **Fee Distribution**: Stakers claim proportional share of collected fees

#### Redemption System (PPS)
1. **Block Found Trigger**: When block is found, redemption pool is created
2. **Registration**: Share holders register their shares to the pool
3. **PPS Calculation**: `reward = (share_difficulty / total_difficulty) × coinbase_value × 1000`
4. **Redemption**: Share holder claims M1N3 tokens, share is destroyed
5. **Guaranteed Payout**: All registered shares receive proportional rewards

## Running M1N3

### Prerequisites

Before running M1N3, ensure:
1. ✅ Bitcoin Core is fully synced (check with `bitcoin-cli getblockchaininfo`)
2. ✅ Bitcoin RPC is accessible (test with `bitcoin-cli getblockcount`)
3. ✅ Sui wallet configured with funded account
4. ✅ M1N3 smart contracts deployed on Sui

### Phase 1: Historical Verification

**Verify all historical Bitcoin blocks and earn M1N3 tokens:**

```bash
python run_p2pool.py \
  --bitcoind-address 127.0.0.1 \
  --bitcoind-rpc-port 8332 \
  --bitcoind-rpc-username your_rpc_username \
  --bitcoind-rpc-password your_rpc_password \
  --m1n3-enable \
  --m1n3-package-id <SUI_PACKAGE_ID> \
  --m1n3-registry-id <BLOCK_REGISTRY_ID> \
  --m1n3-treasury-id <TREASURY_ID> \
  --m1n3-start-height 0 \
  --m1n3-end-height 100000 \
  --m1n3-auto-verify
```

**What happens:**
1. P2Pool fetches blocks 0-100000 from your Bitcoin Core node
2. Registers block headers on Sui blockchain
3. Participates in field verification with other nodes
4. Earns M1N3 tokens for correct field submissions
5. Dynamically adjusts verification granularity based on network participation

**Monitoring Progress:**
```bash
# View M1N3 stats
curl http://localhost:9334/m1n3_stats

# Check Bitcoin node sync
bitcoin-cli getblockchaininfo

# View verification sessions
tail -f p2pool.log | grep M1N3
```

### Phase 2: Real-Time Mining

**Prerequisites for Phase 2:**
- Phase 1 completed (historical blocks verified)
- M1N3 tokens earned from Phase 1
- Bitcoin node fully synced to current height

#### As Staker/Template Proposer

**Stake M1N3 to propose block templates and earn fees:**

```bash
python run_p2pool.py \
  --bitcoind-address 127.0.0.1 \
  --bitcoind-rpc-port 8332 \
  --bitcoind-rpc-username your_rpc_username \
  --bitcoind-rpc-password your_rpc_password \
  --m1n3-enable \
  --m1n3-mining-mode \
  --m1n3-package-id <SUI_PACKAGE_ID> \
  --m1n3-staking-registry-id <STAKING_REGISTRY_ID> \
  --m1n3-mining-registry-id <MINING_REGISTRY_ID> \
  --m1n3-stake-amount 100000
```

**Proposer responsibilities:**
- Fetch block templates from Bitcoin Core via `getblocktemplate`
- Register templates on Sui (10-minute validity)
- Earn 5% of all shares mined against your templates
- Earn 2% of share trading fees

#### As Miner

**Mine shares without staking:**

```bash
python run_p2pool.py \
  --bitcoind-address 127.0.0.1 \
  --bitcoind-rpc-port 8332 \
  --bitcoind-rpc-username your_rpc_username \
  --bitcoind-rpc-password your_rpc_password \
  --m1n3-enable \
  --m1n3-mining-mode \
  --m1n3-package-id <SUI_PACKAGE_ID> \
  --m1n3-mining-registry-id <MINING_REGISTRY_ID>
```

Then connect your mining software to `127.0.0.1:9332`:

```bash
# Example with cgminer
cgminer -o http://127.0.0.1:9332 -u username -p password

# Example with bfgminer
bfgminer -o http://127.0.0.1:9332 -u username -p password
```

**Miner flow:**
1. P2Pool fetches active templates from Sui
2. Your mining hardware finds shares
3. Shares verified on-chain against templates
4. Valid shares minted as tradeable NFTs to your address
5. Earn 95% of share reward immediately
6. Option to sell shares or hold for PPS redemption

## Share Trading Guide

### For Miners

#### 1. Mining Shares
- Mine normally, shares automatically minted as NFTs to your address
- Each share has difficulty metadata for pricing

#### 2. Selling Shares
```bash
# Via Sui CLI or web interface
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function transfer_share \
  --args <REGISTRY_ID> <STAKING_REGISTRY_ID> <SHARE_OBJECT_ID> <BUYER_ADDRESS> <PAYMENT_COIN>
```

**Note**: 2% of payment goes to M1N3 stakers, 98% to you

#### 3. Redeeming Shares

**After block is found:**

```bash
# 1. Register share for redemption
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function register_share_for_redemption \
  --args <REWARD_POOL_ID> <SHARE_OBJECT_ID>

# 2. Redeem share for M1N3 tokens (PPS)
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function redeem_share \
  --args <REWARD_POOL_ID> <SHARE_OBJECT_ID> <TREASURY_ID>
```

### For Traders

#### Buying Shares
- Browse available shares on marketplace
- Evaluate shares by difficulty and block height
- Higher difficulty = larger portion of block reward
- Purchase shares with M1N3 tokens

#### Profit Strategies
1. **Speculation**: Buy shares for blocks near completion
2. **Diversification**: Hold shares across multiple heights
3. **Arbitrage**: Price inefficiencies between difficulty levels

### For Stakers

#### Earning Trading Fees
```bash
# 1. Stake M1N3 tokens
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_staking \
  --function stake \
  --args <STAKING_REGISTRY_ID> <STAKE_COIN>

# 2. Claim accumulated fees
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_staking \
  --function claim_fees \
  --args <STAKING_REGISTRY_ID> <STAKE_POSITION_ID>
```

**Benefits**:
- Earn 2% of all share trading volume
- Earn 5% of share mining rewards as template proposer
- Passive income from market activity

## Economic Model

### Token Distribution
- **Historical Verification**: ~210M M1N3 (all historical blocks × 1000)
- **Mining Rewards**: Ongoing as shares are found
- **Total Supply**: Mirrors Bitcoin's issuance schedule × 1000

### Share Valuation Formula
```
Share Value = (difficulty / avg_difficulty) × expected_block_reward × risk_discount
```

Where:
- `difficulty`: Share's specific difficulty
- `avg_difficulty`: Network average
- `expected_block_reward`: Coinbase value × 1000 M1N3
- `risk_discount`: Market-determined based on block completion probability

### Fee Distribution
```
Every Share Transfer:
  98% → Seller
  2% → All M1N3 Stakers (proportional to stake)
```

## Smart Contracts

### m1n3_token.move
Fungible M1N3 token with friend-only minting

### m1n3_verification.move
Phase 1 historical block verification system

### m1n3_staking.move
Stake M1N3 to become template proposer and earn fees
- Minimum stake: 100,000 M1N3
- Unstaking cooldown: 7 days
- Fee pool for trading fee distribution

### m1n3_mining.move
Phase 2 real-time mining with share trading
- Template proposal (staked nodes only)
- Share submission and verification
- Share transfer with 2% fee
- Block reward pools
- PPS redemption system

## API Endpoints

### Web Interface
- `/` - P2Pool dashboard
- `/sui_stats` - Sui integration statistics
- `/m1n3_stats` - M1N3 system statistics
- `/m1n3.html` - M1N3 web interface

### JSON-RPC
- `getwork` - Get block template for mining
- `submitblock` - Submit found block

## Development

### Building Smart Contracts
```bash
cd sui_contracts
sui move build
sui move test
```

### Deploying
```bash
sui client publish --gas-budget 100000000
```

### Testing
```bash
# Run P2Pool tests
python -m pytest tests/

# Run Sui contract tests
cd sui_contracts
sui move test
```

## Network Ports

- **9332**: Stratum mining port
- **9333**: P2P communication
- **9334**: Web interface (default)

## Security Considerations

### Staking Security
- 7-day unstaking cooldown prevents rapid stake manipulation
- Template proposers economically incentivized to be honest (5% rewards)

### Share Verification
- On-chain SHA-256 verification ensures share validity
- Duplicate share prevention via hash registry
- Template expiration prevents stale work

### Trading Security
- Share ownership verified on-chain
- 2% fee prevents wash trading
- Atomic swaps for trustless trading

## Troubleshooting

### Bitcoin Node Issues

**"Connection refused" or "Could not connect to Bitcoin RPC"**
```bash
# Check if bitcoind is running
bitcoin-cli getblockchaininfo

# If not running, start it
bitcoind -daemon

# Verify RPC credentials match bitcoin.conf
cat ~/.bitcoin/bitcoin.conf | grep rpc
```

**"Block not found" errors during Phase 1**
```bash
# Verify node is fully synced
bitcoin-cli getblockchaininfo

# Check specific block exists
bitcoin-cli getblockhash <height>

# If pruning was enabled, you'll need to re-sync without pruning
# Stop bitcoind, remove blockchain, and restart with prune=0
```

**"Method not found: getblocktemplate"**
```bash
# Ensure txindex is enabled in bitcoin.conf
grep txindex ~/.bitcoin/bitcoin.conf

# If missing, add it and reindex
bitcoind -reindex -txindex
```

**Slow block retrieval**
```bash
# Increase dbcache for better performance
# Add to bitcoin.conf:
dbcache=4096

# Restart bitcoind
bitcoin-cli stop
bitcoind -daemon
```

**"Insufficient funds" for transactions**
```bash
# This is about Bitcoin Core wallet, not M1N3
# M1N3 doesn't require Bitcoin Core wallet funding
# Only need RPC access for block data
```

### Sui Integration Issues

**"Transaction failed: Insufficient gas"**
```bash
# Check Sui wallet balance
sui client gas

# Request testnet SUI if needed
curl --location --request POST 'https://faucet.testnet.sui.io/gas' \
  --header 'Content-Type: application/json' \
  --data-raw '{"FixedAmountRequest":{"recipient":"<YOUR_SUI_ADDRESS>"}}'
```

**"Object not found" errors**
```bash
# Verify contract IDs are correct
sui client object <PACKAGE_ID>
sui client object <REGISTRY_ID>

# Ensure contracts are deployed on correct network (testnet/mainnet)
sui client active-env
```

**"Share verification failed"**
```bash
# Ensure your Bitcoin node data matches network consensus
# Different Bitcoin node = different block data = verification failure

# Verify your node is on correct chain
bitcoin-cli getblockchaininfo | grep chain

# Should show "main" for mainnet, not "test" or "regtest"
```

### Performance Issues

**High CPU usage**
```bash
# Bitcoin Core indexing - normal during initial sync
# Reduce after sync complete

# If persistent, check dbcache setting
# Lower value reduces RAM but increases CPU
```

**High disk I/O**
```bash
# Move Bitcoin data directory to SSD
# Stop bitcoind
bitcoin-cli stop

# Move data
mv ~/.bitcoin /path/to/ssd/.bitcoin
ln -s /path/to/ssd/.bitcoin ~/.bitcoin

# Restart
bitcoind -daemon
```

**Network bandwidth saturation**
```bash
# Limit Bitcoin Core connections
# Add to bitcoin.conf:
maxconnections=16
maxuploadtarget=5000  # 5GB/day upload limit
```

## FAQ

### How do shares become valuable?
Shares represent proportional claim to block rewards. Higher difficulty shares = larger reward portion when block is found.

### What happens if a block is never found?
Shares for that height remain tradeable but cannot be redeemed. Market prices this risk.

### Why 2% trading fee?
Creates sustainable income for stakers who secure the network and propose templates.

### Can I mine without staking?
Yes! Only template proposers need to stake. Regular miners just find shares.

### How is PPS calculated?
`PPS_reward = (your_share_difficulty / total_pool_difficulty) × coinbase_value × 1000`

### When can I redeem shares?
Only after the block is found and redemptions are enabled for that height.

### Can I use a pruned Bitcoin node?
No. Pruned nodes discard old block data, which prevents Phase 1 historical verification. You must run a full archival node with `prune=0`.

### Do I need to run Bitcoin Core 24/7?
For Phase 1, you can run intermittently during verification. For Phase 2 real-time mining, 24/7 uptime is strongly recommended to propose templates and mine shares continuously.

### What if my Bitcoin node is still syncing?
You can start Phase 1 verification for already-synced heights. For example, if synced to block 50000, set `--m1n3-end-height 50000`. Continue verification as more blocks sync.

### Why can't I use a block explorer API instead of Bitcoin Core?
M1N3's trustless security model requires each participant to independently verify block data from their own node. Using a block explorer would introduce trust assumptions and centralization.

## Support & Community

- **Documentation**: See `M1N3_README.md` and `SUI_INTEGRATION.md`
- **Issues**: Report bugs via GitHub issues
- **Updates**: Follow development on the main branch

## Roadmap

- [x] Phase 1: Historical block verification
- [x] Phase 2: Real-time mining with staking
- [x] Share trading with 2% fee
- [x] PPS redemption system
- [ ] Marketplace web interface
- [ ] Mobile app for share trading
- [ ] Cross-chain share bridges
- [ ] Advanced trading features (limit orders, options)

## License

[Available here](COPYING)

## Acknowledgments

Based on the original P2Pool protocol by forrestv. Enhanced with Sui blockchain integration and share trading economy for the M1N3 project.

---

**M1N3**: Making Bitcoin mining more accessible, liquid, and profitable through decentralized verification and share trading.
