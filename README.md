# m1n3 - Decentralized Trustless Bitcoin Mining & Verification

m1n3 is a next-generation decentralized Bitcoin mining protocol based on P2Pool, featuring on-chain verification via Sui blockchain and a revolutionary share trading economy.

## Overview

m1n3 combines traditional P2Pool mining with blockchain verification and creates a tradeable share marketplace where miners can instantly monetize their work before blocks are found.

### Built on P2Pool Architecture

m1n3 extends P2Pool V2 (https://github.com/p2poolv2/p2poolv2) design with on-chain verification capabilities:

**P2Pool Foundations:**
- **Sharechain with Uncle Blocks** - Inspired by P2Pool v2's uncle block support for comprehensive work accounting
- **Non-Custodial Model** - Following decentralized principles where miners retain full control
- **Atomic Swap Integration** - Building on market maker concepts for trustless peer-to-peer trading
- **Stratum v2 Compatibility** - Ready for modern mining protocols with improved efficiency
- **Rust-Bitcoin Standards** - Aligned with modern Bitcoin protocol implementations

**m1n3 Enhancements:**
- **Sui Blockchain Verification** - Adds trustless on-chain SHA-256 verification layer
- **Tradeable Share NFTs** - Every valid share becomes a liquid financial instrument
- **Two-Phase Bootstrap** - Historical verification distributes initial token supply fairly
- **Staking Security** - Economic incentives through M1N3 token staking for template proposers

### Key Features

- **Phase 1**: Historical block header verification with coordinated field-level validation
- **Phase 2**: Real-time mining with staking security and on-chain share verification
- **Share Trading**: All valid shares become a tradeable SUI object.
- **Uncle Block Accounting**: All submitted work credited, reducing orphaned share waste
- **PPS Redemption**: Shares redeemable for Bitcoin rewards proportional to their difficulty
- **Native Verification**: Uses Sui's native SHA-256 for trustless on-chain validation
- **Market Maker Support**: Enables liquidity providers to buy shares from smaller miners

## Requirements

### Generic
- **Bitcoin Core >= 22.0** (Taproot activated, recommended >= 28.0 for latest features)
- Python >= 2.7
- Twisted >= 10.0.0
- pysui >= 0.50.0
- **IKA SDK** (optional, for PPLNS mode with dWallet integration)


### Linux
```bash
sudo apt-get install python-zope.interface python-twisted python-twisted-web
pip install pysui

# Optional: For PPLNS mode with IKA dWallet
npm install @dwallet-labs/ika
```

### Windows
1. Install [Python 2.7](http://www.python.org/getit/)
2. Install [Twisted](http://twistedmatrix.com/trac/wiki/Downloads)
3. Install [Zope.Interface](http://pypi.python.org/pypi/zope.interface/)
4. Install pysui: `pip install pysui`
5. Optional (PPLNS mode): Install IKA SDK: `npm install @dwallet-labs/ika`

## Bitcoin Full Node Requirement

**CRITICAL: m1n3 requires a fully synced Bitcoin node running locally.**

### Why Full Node is Required

m1n3's entire architecture depends on accessing complete Bitcoin blockchain data:

1. **Phase 1 - Historical Verification**:
   - Retrieves all historical block headers from Bitcoin nodes
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
rpcallowip=127.0.0.1

# Network settings (P2Pool v2 compatible)
listen=1
daemon=1

# Required for getblocktemplate with modern features
txindex=1

# Taproot support (activated block 709,632)
# Automatically enabled in Bitcoin Core 22.0+

# SegWit and witness data (BIP 141, BIP 144)
# Automatically enabled for native address support

# Compact blocks (BIP 152) for efficient propagation
blocksonly=0

# Performance optimization
dbcache=4096
maxmempool=512

# For Phase 1 historical verification
# Keep full blockchain (no pruning)
prune=0

# P2P network optimization
maxconnections=125
maxuploadtarget=0  # Unlimited for mining pool operation

# Mempool settings for optimal template generation
mempoolexpiry=336  # 2 weeks in hours
maxmempool=300     # MB
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
# 1. Download Bitcoin Core 28.0 or newer (recommended for P2Pool v2 compatibility)
wget https://bitcoincore.org/bin/bitcoin-core-28.0/bitcoin-28.0-x86_64-linux-gnu.tar.gz

# 2. Extract and install
tar -xzf bitcoin-28.0-x86_64-linux-gnu.tar.gz
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-28.0/bin/*

# 3. Create configuration with modern P2Pool v2 compatible settings
mkdir -p ~/.bitcoin
cat > ~/.bitcoin/bitcoin.conf <<EOF
server=1
rpcuser=m1n3user
rpcpassword=$(openssl rand -base64 32)
rpcport=8332
rpcallowip=127.0.0.1
txindex=1
dbcache=4096
maxmempool=300
prune=0
maxconnections=125
EOF

# 4. Start syncing (this will take time!)
bitcoind -daemon

# 5. Monitor sync progress
watch bitcoin-cli getblockchaininfo

# 6. Verify Taproot activation (should show "active")
bitcoin-cli getblockchaininfo | grep -A2 taproot
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

### Payout Modes: PPS vs PPLNS

M1N3 supports two payout modes to accommodate different miner preferences:

#### PPS Mode (Pay Per Share)
**Default mode** - Miners receive immediate M1N3 token rewards:

- **Instant Payouts**: Shares rewarded immediately upon verification
- **Predictable Income**: Fixed reward per valid share
- **Zero Variance**: No dependency on block finding luck
- **Share Trading**: Shares become tradeable NFTs with 2% fee
- **PPS Redemption**: Optional Bitcoin-backed redemption when blocks are found

**Best for**: Miners wanting instant liquidity and tradeable shares

#### PPLNS Mode (Pay Per Last N Shares)
**Traditional P2Pool method** - Miners receive Bitcoin rewards when blocks are found:

- **Share Window**: Last 8,640 shares (~3 days) tracked in share chain
- **Block Found Payout**: Rewards distributed proportionally to share window contributors
- **True Bitcoin Rewards**: Direct Bitcoin payouts from mined blocks
- **Decentralized Custody**: IKA dWallet manages pool funds via 2PC-MPC
- **Lower Fees**: No share trading fees, just pool operation costs
- **Fair Variance**: Rewards smoothed over the share window

**Best for**: Traditional miners preferring P2Pool's proven reward model

#### IKA dWallet Integration (PPLNS)

**What is IKA?**
[IKA](https://github.com/dwallet-labs/ika) provides decentralized wallet (dWallet) functionality using 2-Party Computation Multi-Party Computation (2PC-MPC):

- **No Single Point of Failure**: No single party controls pool funds
- **Cryptographic Security**: Signatures require threshold participation
- **Bitcoin Native**: Direct Bitcoin transaction signing
- **Cross-Chain**: Works across any blockchain without bridges

**How it works in M1N3:**

1. **Pool Setup**: M1N3 creates an IKA dWallet for PPLNS pool rewards
2. **Block Found**: When miner finds block, coinbase goes to dWallet address
3. **Reward Distribution**: M1N3 calculates PPLNS shares from share window
4. **2PC-MPC Signing**: Threshold signers approve Bitcoin transactions to miners
5. **Payout**: Miners receive Bitcoin directly to their addresses

**Security Properties:**
- Pool cannot steal funds (requires threshold signatures)
- Miners cannot manipulate rewards (on-chain verification)
- Transparent accounting (all shares recorded on Sui)
- Censorship resistant (decentralized signing)

**Configuration:**
```bash
# Enable PPLNS mode with IKA dWallet
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function set_payout_mode \
  --args <REGISTRY_ID> 1  # 1 = PPLNS mode

# Configure IKA dWallet
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function set_dwallet \
  --args <REGISTRY_ID> <DWALLET_ADDRESS> <DWALLET_CAP_ID>
```

#### Choosing Your Payout Mode

| Feature | PPS Mode | PPLNS Mode |
|---------|----------|------------|
| **Payout Timing** | Immediate | When block found |
| **Reward Type** | M1N3 tokens | Bitcoin (via IKA) |
| **Variance** | Zero | ~3 days average |
| **Share Trading** | Yes | No (direct BTC) |
| **Pool Fees** | 2% trading fee | Pool operation only |
| **Custody** | Individual | IKA dWallet (decentralized) |
| **Best For** | Traders, speculators | Traditional miners |

**You can choose your preferred mode** - M1N3 supports both simultaneously!

### Share Trading Economy (PPS Mode)

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

### For PPLNS Miners (Traditional P2Pool)

If you prefer traditional P2Pool's proven payout method with direct Bitcoin rewards:

#### 1. Enable PPLNS Mode

**Pool operator** sets PPLNS mode:
```bash
# Switch to PPLNS mode
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function set_payout_mode \
  --args <MINING_REGISTRY_ID> 1

# Configure IKA dWallet for pool custody
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function set_dwallet \
  --args <MINING_REGISTRY_ID> <DWALLET_ADDRESS> <DWALLET_CAP_ID>
```

#### 2. Mining in PPLNS Mode

```bash
# Connect to M1N3 in PPLNS mode (same as PPS)
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

#### 3. How PPLNS Rewards Work

**Share Window**: Your shares remain in the pool's share chain for ~3 days (8,640 shares)

**Block Found**: When any pool miner finds a block:
1. Bitcoin coinbase goes to IKA dWallet address
2. M1N3 calculates your share of last N shares
3. Your reward = `(your_difficulty / total_window_difficulty) × coinbase_value`
4. IKA dWallet signs Bitcoin transaction to your address
5. You receive Bitcoin directly (no token conversion)

**Example**:
```
Block Found: 6.25 BTC coinbase
Your shares: 100 difficulty
Total window: 10,000 difficulty
Your reward: (100/10,000) × 6.25 = 0.0625 BTC
```

#### 4. Setting Up IKA dWallet (Pool Operators)

**Install IKA SDK**:
```bash
# Add IKA to your project
npm install @dwallet-labs/ika

# Or using the Sui Move integration
cd sui_contracts
sui move add ika@git+https://github.com/dwallet-labs/ika
```

**Create dWallet**:
```javascript
import { IkaClient } from '@dwallet-labs/ika';

const ika = new IkaClient(suiClient);

// Create 2PC-MPC dWallet for Bitcoin
const dwallet = await ika.createDWallet({
  network: 'bitcoin',
  threshold: 2,  // 2-of-3 multisig
  participants: [node1, node2, node3]
});

// Get dWallet address for pool coinbase
const btcAddress = await dwallet.getAddress('bitcoin');
console.log('Pool Bitcoin Address:', btcAddress);
```

**Configure in M1N3**:
```bash
# Set the dWallet configuration
sui client call \
  --package <PACKAGE_ID> \
  --module m1n3_mining \
  --function set_dwallet \
  --args <REGISTRY_ID> ${dwallet.address} ${dwallet.capId}
```

#### 5. Creating a Shared dWallet for Autonomous Rewards

**Why Shared dWallet?**
A shared (public) dWallet allows autonomous reward distribution without requiring pool operator intervention for each payout. Multiple authorized signers can approve transactions independently.

**Key Features**:
- **Public Object**: Anyone can query status and propose distributions
- **Threshold Security**: Requires N-of-M signatures to execute Bitcoin transactions
- **Autonomous**: Signers can independently approve rewards based on on-chain PPLNS data
- **Transparent**: All pending transactions visible on-chain

**Step-by-Step Creation**:

**1. Install Dependencies**:
```bash
# Install IKA SDK
npm install @dwallet-labs/ika

# Install Sui CLI (if not already installed)
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch mainnet sui
```

**2. Configure Signers** (Pool Operators):
```javascript
// signers.js - Configure authorized signers for the pool
const signers = [
  '0xSIGNER_1_SUI_ADDRESS',  // Pool operator 1
  '0xSIGNER_2_SUI_ADDRESS',  // Pool operator 2
  '0xSIGNER_3_SUI_ADDRESS',  // Pool operator 3
];

const threshold = 2;  // Require 2 of 3 signatures
const network = 'mainnet';  // or 'testnet', 'signet'
```

**3. Create IKA dWallet** (JavaScript):
```javascript
// create-dwallet.js
import { IkaClient } from '@dwallet-labs/ika';
import { SuiClient } from '@mysten/sui.js/client';

async function createPoolDWallet() {
  // Initialize Sui client
  const suiClient = new SuiClient({
    url: 'https://fullnode.mainnet.sui.io:443'
  });

  // Initialize IKA client
  const ika = new IkaClient(suiClient);

  // Create 2-of-3 multisig dWallet for Bitcoin
  const dwallet = await ika.createDWallet({
    network: 'bitcoin',
    threshold: 2,
    participants: signers
  });

  // Get Bitcoin address for pool coinbase
  const btcAddress = await dwallet.getAddress('bitcoin');

  console.log('dWallet Created Successfully!');
  console.log('  dWallet ID:', dwallet.id);
  console.log('  Bitcoin Address:', btcAddress);
  console.log('  Capability ID:', dwallet.capId);
  console.log('  Threshold:', threshold, '/', signers.length);

  return {
    dwalletId: dwallet.id,
    bitcoinAddress: btcAddress,
    capId: dwallet.capId
  };
}

createPoolDWallet().then(result => {
  console.log('\nUse this Bitcoin address for pool coinbase:');
  console.log(result.bitcoinAddress);
});
```

**4. Register as Shared Object** (Sui):
```bash
# Create shared dWallet on Sui blockchain
sui client call \
  --package <M1N3_PACKAGE_ID> \
  --module m1n3_dwallet \
  --function create_shared_dwallet \
  --args \
    "[$(echo -n ${BTC_ADDRESS} | xxd -p -c 256)]" \
    "[$(echo -n ${DWALLET_CAP_ID} | xxd -p -c 256)]" \
    "[$(echo -n 'mainnet' | xxd -p -c 256)]" \
    2 \
    "['0xSIGNER_1','0xSIGNER_2','0xSIGNER_3']" \
  --gas-budget 10000000
```

**5. Configure in M1N3**:
```bash
# Link the shared dWallet to M1N3 mining registry
sui client call \
  --package <M1N3_PACKAGE_ID> \
  --module m1n3_mining \
  --function set_dwallet \
  --args <MINING_REGISTRY_ID> \
    "[$(echo -n ${BTC_ADDRESS} | xxd -p -c 256)]" \
    "[$(echo -n ${DWALLET_CAP_ID} | xxd -p -c 256)]"
```

**6. Set Pool Coinbase** (Bitcoin Core):
```bash
# Update bitcoin.conf to mine to dWallet address
echo "
# M1N3 Pool dWallet address
miningaddress=${BTC_ADDRESS}
" >> ~/.bitcoin/bitcoin.conf

# Restart Bitcoin Core
bitcoin-cli stop && sleep 5 && bitcoind -daemon
```

#### 6. Autonomous Reward Distribution

**How Autonomous Rewards Work**:

When a block is found, PPLNS rewards are distributed **automatically** through on-chain coordination:

**Flow**:
1. **Block Found**: Miner finds block, coinbase goes to dWallet Bitcoin address
2. **Calculate Rewards**: M1N3 contract calculates PPLNS shares from on-chain share window
3. **Propose Distribution**: Anyone can propose reward transaction based on on-chain data
4. **Threshold Signing**: Authorized signers approve the distribution
5. **IKA Execution**: Once threshold reached, IKA 2PC-MPC signs Bitcoin transaction
6. **Bitcoin Payout**: Miners receive Bitcoin directly to their addresses

**Proposing Rewards** (Python - Automated):
```python
# In p2pool/ika_dwallet.py
from p2pool import ika_dwallet

# Initialize dWallet manager
dwallet = ika_dwallet.init_dwallet_manager({
    'enabled': True,
    'network': 'mainnet',
    'threshold': 2,
    'participants': [
        '0xSIGNER_1_SUI_ADDRESS',
        '0xSIGNER_2_SUI_ADDRESS',
        '0xSIGNER_3_SUI_ADDRESS',
    ],
    'package_id': '<M1N3_PACKAGE_ID>',
})

# When block is found, propose PPLNS distribution
recipients = [
    (miner1_sui_addr, miner1_btc_addr, 12500000),  # 0.125 BTC
    (miner2_sui_addr, miner2_btc_addr, 37500000),  # 0.375 BTC
    (miner3_sui_addr, miner3_btc_addr, 50000000),  # 0.5 BTC
]

tx_id = yield dwallet.propose_pplns_distribution(recipients)
print('Distribution proposed:', tx_id)
```

**Approving Rewards** (Sui - Each Signer):
```bash
# Each authorized signer approves the distribution
sui client call \
  --package <M1N3_PACKAGE_ID> \
  --module m1n3_dwallet \
  --function sign_transaction \
  --args <SHARED_DWALLET_ID> <TRANSACTION_ID> \
  --gas-budget 5000000
```

**Monitoring Status**:
```bash
# Check pending distributions
sui client object <SHARED_DWALLET_ID> --json | jq '.data.content.fields.pending_transactions'

# Watch for threshold reached
sui client events --type 'm1n3_dwallet::TransactionExecuted'
```

**Automated Signer** (Optional):
```javascript
// auto-signer.js - Automatically sign valid PPLNS distributions
import { SuiClient } from '@mysten/sui.js/client';

const suiClient = new SuiClient({ url: 'https://fullnode.mainnet.sui.io:443' });

// Listen for new distribution proposals
suiClient.subscribeEvent({
  filter: { MoveEventType: 'm1n3_dwallet::TransactionProposed' },
  onMessage: async (event) => {
    const { dwallet_id, tx_id, recipients } = event.parsedJson;

    // Verify distribution matches on-chain PPLNS data
    const isValid = await verifyPPLNSDistribution(tx_id, recipients);

    if (isValid) {
      console.log('Auto-signing valid distribution:', tx_id);
      await signTransaction(dwallet_id, tx_id);
    } else {
      console.warn('Invalid distribution detected:', tx_id);
    }
  }
});

console.log('Automated signer running...');
```

#### 7. Advantages of PPLNS Mode

**For Miners**:
- Real Bitcoin payouts (no token conversion)
- Proven P2Pool reward distribution
- Lower fees (no 2% trading fee)
- Automatic variance smoothing
- Compatible with traditional P2Pool tooling

**For Pool**:
- Decentralized custody (IKA 2PC-MPC)
- No custodial risk
- Transparent on-chain accounting
- No share trading infrastructure needed

**Trade-offs**:
- ❌ No instant liquidity (must wait for block)
- ❌ No share trading/speculation
- ❌ Higher variance if pool is small
- ✅ Direct Bitcoin rewards
- ✅ Lower complexity
- ✅ Traditional P2Pool behavior

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
Phase 2 real-time mining with dual payout modes
- **Payout Modes**: PPS (instant M1N3 rewards) or PPLNS (traditional Bitcoin rewards)
- **Share Chain**: Maintains PPLNS window of last 8,640 shares (~3 days)
- **IKA Integration**: dWallet configuration for PPLNS pool custody
- Template proposal (staked nodes only)
- Share submission and on-chain verification
- Share transfer with 2% fee (PPS mode)
- Block reward pools and PPS redemption
- PPLNS reward distribution via IKA 2PC-MPC

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

- **9332**: Stratum mining port (Stratum v1, v2-ready)
- **9333**: P2P communication (sharechain propagation)
- **9334**: Web interface (default)

## Mining Protocol Support

### Stratum v1 (Current)
M1N3 currently supports Stratum v1 for maximum miner compatibility:
- Standard `mining.subscribe` and `mining.authorize` flow
- Extranonce subscription for efficient share generation
- Compatible with all major mining software (cgminer, bfgminer, etc.)

### Stratum v2 (Future)
**Following P2Pool v2 architecture**, M1N3 is designed for Stratum v2 compatibility:

**Benefits of Stratum v2:**
- **Job Declaration** - Miners can construct their own block templates
- **Reduced Bandwidth** - Binary protocol with header-only mining
- **Better Security** - Encrypted connections, preventing man-in-the-middle attacks
- **Hashrate Attestation** - Cryptographic proof of hashrate contribution
- **Standard Channels** - Multiple miners can share single connection

**Implementation Roadmap:**
1. Current: Stratum v1 with M1N3-specific extensions for Sui verification
2. Phase 2: Hybrid mode supporting both Stratum v1 and v2
3. Future: Full Stratum v2 with job declaration for maximum decentralization

### Mining Software Compatibility

**Tested and Compatible:**
- cgminer 4.10.0+
- bfgminer 5.5.0+
- CPUMiner (reference implementation)

**Stratum v2 Ready:**
- braiins-pool Stratum v2 reference implementation
- SRI (Stratum V2 Reference Implementation)

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

### Should I use PPS or PPLNS mode?
**PPS Mode** - Choose if you want:
- Instant M1N3 token rewards
- Ability to trade shares for profit
- Zero variance (predictable income)
- Don't want to wait for blocks

**PPLNS Mode** - Choose if you prefer:
- Traditional P2Pool experience
- Direct Bitcoin rewards (no tokens)
- Lower fees (no 2% trading fee)
- Support for decentralized pool custody

### How does IKA dWallet secure pool funds?
IKA uses 2PC-MPC (Two-Party Computation Multi-Party Computation) cryptography:
- No single party can sign transactions alone
- Requires threshold of signers to approve payouts
- Fully decentralized - no custodial risk
- Bitcoin-native signing without bridges or wrapping

### Can the pool operator steal funds in PPLNS mode?
No. IKA dWallet requires threshold signatures (e.g., 2-of-3). The pool operator cannot unilaterally move funds. All reward distributions are verified on-chain against the share window before IKA signers approve transactions.

### What happens to my shares if the pool switches payout modes?
Payout modes are pool-wide settings. Existing shares in PPS mode remain tradeable. If switching to PPLNS, new shares go into the share window for Bitcoin payouts. Your existing PPS shares are unaffected.

### How long does PPLNS payout take?
PPLNS pays when a block is found. Payout timing depends on:
1. Block finding (average ~10 minutes for network, varies by pool hashrate)
2. IKA threshold signers approving distribution (~minutes)
3. Bitcoin transaction confirmation (10-60 minutes)

Total: Usually within 1-2 hours after block is found.

## Support & Community

- **Documentation**: See `M1N3_README.md` and `SUI_INTEGRATION.md`
- **Issues**: Report bugs via GitHub issues
- **Updates**: Follow development on the main branch

## Roadmap

### Completed
- [x] Phase 1: Historical block verification
- [x] Phase 2: Real-time mining with staking
- [x] Share trading with 2% fee (PPS mode)
- [x] PPS redemption system
- [x] PPLNS mode with share window tracking
- [x] IKA dWallet integration structure for PPLNS
- [x] Dual payout mode support (PPS + PPLNS)
- [x] Bitcoin Core 28.0+ compatibility
- [x] Taproot and SegWit native support

### In Progress (P2Pool v2 Alignment)
- [ ] IKA 2PC-MPC Bitcoin transaction signing
- [ ] Complete dWallet setup automation
- [ ] Uncle block implementation for comprehensive work accounting
- [ ] Stratum v2 protocol support
- [ ] Compact block propagation (BIP 152)
- [ ] Sharechain optimization with rust-bitcoin standards

### Future Enhancements
- [ ] Marketplace web interface
- [ ] Mobile app for share trading
- [ ] Cross-chain share bridges
- [ ] Advanced trading features (limit orders, options)
- [ ] Hashrate attestation via Stratum v2
- [ ] Job declaration for maximum miner autonomy
- [ ] Integration with CKPool for solo mining fallback

## Comparison with P2Pool v2

| Feature | P2Pool v2 | M1N3 PPS Mode | M1N3 PPLNS Mode |
|---------|-----------|---------------|-----------------|
| **Implementation** | Rust | Python 2.7 + Sui Move | Python 2.7 + Sui Move |
| **Share Accounting** | Uncle blocks | Uncle blocks (planned) | Share window (8,640 shares) |
| **Verification** | Distributed nodes | On-chain Sui SHA-256 | On-chain Sui SHA-256 |
| **Share Trading** | Atomic swaps | NFT marketplace + Atomic swaps | No (direct Bitcoin) |
| **Payout Model** | PPLNS coinbase | PPS via M1N3 tokens | PPLNS via IKA dWallet |
| **Payout Timing** | When block found | Immediate | When block found |
| **Custody** | Miners self-custody | Individual wallets | IKA 2PC-MPC dWallet |
| **Staking** | No | Yes (M1N3 tokens) | Yes (M1N3 tokens) |
| **Fees** | Pool operation | 2% trading fee | Pool operation only |
| **Variance** | ~3 days | Zero | ~3 days |
| **Protocol** | Stratum v2 ready | Stratum v1 (v2 planned) | Stratum v1 (v2 planned) |
| **Bitcoin Core** | 22.0+ | 22.0+ (28.0+ recommended) | 22.0+ (28.0+ recommended) |

## License

[Available here](COPYING)

## Acknowledgments

**M1N3** builds upon decades of decentralized mining innovation:

- **Original P2Pool** by forrestv - pioneering decentralized pool architecture
- **P2Pool v2** ([p2poolv2](https://github.com/p2poolv2/p2poolv2)) - modern Rust implementation with uncle blocks and Stratum v2
- **IKA/dWallet Labs** ([ika](https://github.com/dwallet-labs/ika)) - 2PC-MPC decentralized wallet for PPLNS custody
- **rust-bitcoin** - Bitcoin protocol implementation standards
- **Sui Foundation** - native SHA-256 verification capabilities

Enhanced with blockchain verification, dual payout modes (PPS/PPLNS), tradeable shares, and decentralized custody for the M1N3 project.

## References

- [P2Pool v2 GitHub](https://github.com/p2poolv2/p2poolv2) - Modern P2Pool reboot for Bitcoin
- [Stratum V2 Specifications](https://stratumprotocol.org/) - Next-generation mining protocol
- [Bitcoin Core 28.0](https://bitcoincore.org/en/releases/28.0/) - Latest Bitcoin node software
- [BIP 152 - Compact Blocks](https://github.com/bitcoin/bips/blob/master/bip-0152.mediawiki) - Efficient block propagation
- [Sui Documentation](https://docs.sui.io/) - Sui blockchain platform
- [IKA dWallet](https://github.com/dwallet-labs/ika) - Decentralized wallet with 2PC-MPC for Bitcoin custody
- [IKA Documentation](https://docs.ika.xyz/) - IKA SDK and dWallet integration guides
- [2PC-MPC Cryptography](https://docs.ika.xyz/core-concepts/cryptography/2pc-mpc) - Two-party computation for decentralized signing

---

**M1N3**: Making Bitcoin mining more accessible, liquid, and profitable through decentralized verification and share trading.
