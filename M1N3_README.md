# M1N3 - Decentralized Trustless Bitcoin Mining Verification

## 🎯 Vision

M1N3 is a revolutionary decentralized system for trustlessly verifying the Bitcoin blockchain using economic incentives. Instead of traditional mining, nodes earn M1N3 tokens by registering and verifying Bitcoin block data on the Sui blockchain, leveraging Sui's native SHA-256 hash function for on-chain proof of correctness.

## 🌟 What Makes M1N3 Unique

### Traditional Bitcoin Mining Problems
- High energy consumption
- Centralized mining pools
- Expensive specialized hardware (ASICs)
- Geographic concentration

### M1N3 Solution
- ✅ **No Mining Hardware**: Verify existing blocks, no hashing power needed
- ✅ **Decentralized**: Coordination happens on-chain via Sui smart contracts
- ✅ **Trustless Verification**: SHA-256 verification happens on-chain
- ✅ **Economic Incentives**: Rewards proportional to original Bitcoin block subsidies
- ✅ **Dynamic Participation**: System automatically adjusts to node count

## 🏗️ Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Bitcoin Blockchain                       │
│  (Source of Truth - Known Block Headers)                   │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                   Sui Blockchain                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  BlockRegistry (Global State)                        │  │
│  │  - Maps heights to block headers                     │  │
│  │  - Tracks verification sessions                      │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  VerificationSession (Per Block)                     │  │
│  │  - Registered nodes                                  │  │
│  │  - Dynamic granularity                               │  │
│  │  - Field submissions                                 │  │
│  │  - Reward distribution                               │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  M1N3 Token                                          │  │
│  │  - Fungible token (8 decimals)                       │  │
│  │  - Minted as verification rewards                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│             M1N3 Verification Nodes                         │
│  - Fetch Bitcoin block data                                 │
│  - Register blocks on Sui                                   │
│  - Submit field verifications                               │
│  - Earn M1N3 rewards                                        │
└─────────────────────────────────────────────────────────────┘
```

### Smart Contracts (Move)

#### 1. M1N3 Token (`m1n3_token.move`)
- Fungible token with 8 decimals (matching Bitcoin)
- Treasury manages minting and total supply
- Tracks total blocks registered and rewards distributed

#### 2. Block Verification (`m1n3_verification.move`)
- **BlockHeader**: On-chain Bitcoin block header storage
- **VerificationSession**: Coordination for each block
- **Field Verification**: On-chain SHA-256 validation
- **Reward Distribution**: Automatic M1N3 minting

### How It Works

```
1. BLOCK REGISTRATION
   Node A: Fetches block 100 from Bitcoin
   Node A: Registers header on Sui → Creates VerificationSession

2. NODE COORDINATION
   Node B: Registers interest in verifying block 100
   Node C: Registers interest in verifying block 100
   ... (more nodes join)
   Session: Adjusts granularity based on node count

3. FIELD DIVISION
   If 1-100 nodes: Divide by BYTE (e.g., version = 4 bytes)
   If 100+ nodes: Divide by BIT (e.g., version byte 0, bit 0-7)

4. FIELD SUBMISSION
   Node B: Submits "version" field data
   Sui: Verifies data matches block header (SHA-256)
   Sui: Mints M1N3 reward to Node B

5. COMPLETION
   All fields verified → Session closes
   Total rewards distributed = (block subsidy × 1000) / 2
```

## 💰 Economics

### Reward Structure

**Total Reward Per Block**: `Original Block Subsidy × 1,000`

**Distribution (50/50 split)**:
1. **Block Verification**: 50% of total (ACTIVE)
   - Divided among 5 active fields
   - Each field worth: `(subsidy × 1000 / 2) / 5`

2. **Merkle Root**: 50% of total (DISABLED)
   - Reserved for future Merkle path verification
   - Not currently distributed

### Examples

#### Genesis Block (Height 0)
- **Original Subsidy**: 50 BTC (5,000,000,000 satoshis)
- **Total M1N3 Pool**: 50,000 M1N3
- **Block Verification**: 25,000 M1N3
- **Per Field**: 5,000 M1N3
- **Merkle**: 25,000 M1N3 (not distributed)

#### Block 210,000 (First Halving)
- **Original Subsidy**: 25 BTC
- **Total M1N3 Pool**: 25,000 M1N3
- **Block Verification**: 12,500 M1N3
- **Per Field**: 2,500 M1N3

#### Block 840,000 (Fourth Halving - 2024)
- **Original Subsidy**: 3.125 BTC
- **Total M1N3 Pool**: 3,125 M1N3
- **Block Verification**: 1,562.5 M1N3
- **Per Field**: 312.5 M1N3

### Fields Being Verified

Currently verifying **5 out of 6** Bitcoin block header fields:

| Field ID | Field Name | Size | Status |
|----------|-----------|------|---------|
| 0 | Version | 4 bytes | ✅ Active |
| 1 | Previous Block Hash | 32 bytes | ✅ Active |
| 2 | Merkle Root | 32 bytes | ❌ DISABLED |
| 3 | Timestamp | 4 bytes | ✅ Active |
| 4 | Bits (Difficulty) | 4 bytes | ✅ Active |
| 5 | Nonce | 4 bytes | ✅ Active |

**Total Header Size**: 80 bytes
**Active Verification**: 48 bytes (excluding merkle root)

## 🚀 Getting Started

### Prerequisites

1. **Bitcoin Core Node** (0.21.0+)
   ```bash
   # Running and synced
   bitcoin-cli getblockcount
   ```

2. **Sui Wallet** with SUI for gas
   ```bash
   sui client active-address
   sui client gas
   ```

3. **Python 2.7** with dependencies
   ```bash
   pip install -r requirements.txt
   ```

### Deploy Smart Contracts

```bash
cd sui_contracts

# Build contracts
sui move build

# Publish to Sui
sui client publish --gas-budget 200000000

# Save the output:
# - Package ID: 0x...
# - M1N3Treasury ID: 0x... (shared object)
# - BlockRegistry ID: 0x... (shared object)
```

### Run M1N3 Node

```bash
python run_p2pool.py \
    --m1n3-enable \
    --m1n3-package-id 0xYOUR_PACKAGE_ID \
    --m1n3-registry-id 0xYOUR_REGISTRY_ID \
    --m1n3-treasury-id 0xYOUR_TREASURY_ID \
    --m1n3-start-height 0 \
    --m1n3-end-height 100 \
    --m1n3-auto-verify \
    --bitcoind-address 127.0.0.1 \
    --bitcoind-rpc-port 8332 \
    USERNAME PASSWORD
```

### Configuration Options

| Argument | Description | Required | Default |
|----------|-------------|----------|---------|
| `--m1n3-enable` | Enable M1N3 verification | Yes | False |
| `--m1n3-package-id` | Deployed package ID | Yes | None |
| `--m1n3-registry-id` | BlockRegistry object ID | Yes | None |
| `--m1n3-treasury-id` | M1N3Treasury object ID | Yes | None |
| `--m1n3-start-height` | Starting block height | No | 0 |
| `--m1n3-end-height` | Ending block height | No | None (continuous) |
| `--m1n3-auto-verify` | Auto-register and verify | No | False |

## 📊 Web Interface

Access the M1N3 dashboard at:
```
http://localhost:9332/static/m1n3.html
```

Features:
- Real-time statistics (blocks, nodes, rewards)
- Active verification sessions
- Field verification status
- Your earned M1N3 tokens
- Dynamic granularity visualization

## 🔧 Dynamic Granularity System

M1N3's unique feature is **dynamic field division** based on node participation:

### Byte-Level Division (1-100 nodes)

**Example: Version Field (4 bytes)**
```
Byte 0: [0x01]  → Node A
Byte 1: [0x00]  → Node B
Byte 2: [0x00]  → Node C
Byte 3: [0x00]  → Node D
```

### Bit-Level Division (100+ nodes)

**Example: Version Field (4 bytes = 32 bits)**
```
Byte 0, Bit 0: [0/1]  → Node A
Byte 0, Bit 1: [0/1]  → Node B
...
Byte 3, Bit 7: [0/1]  → Node AF
```

This ensures **fair participation opportunities** regardless of network size!

## 🔐 Security

### On-Chain Verification

All submitted data is verified on-chain:

```move
// Simplified verification logic
fun verify_field(block: &BlockHeader, field_id: u64, data: &vector<u8>): bool {
    if (field_id == 0) {
        // Verify version matches
        let expected = u32_to_bytes_le(block.version);
        &expected == data
    }
    // ... other fields
}
```

### Double SHA-256

Block header hashes are computed using Bitcoin's double SHA-256:

```move
fun double_sha256(data: vector<u8>): vector<u8> {
    let hash1 = sha2_256(data);
    sha2_256(hash1)
}
```

### Duplicate Prevention

The `BlockRegistry` prevents duplicate block registrations and field submissions:

```move
assert!(!table::contains(&registry.blocks, height), E_BLOCK_ALREADY_REGISTERED);
assert!(!table::contains(&session.submitted_fields, field_id), E_FIELD_ALREADY_SUBMITTED);
```

## 📈 Use Cases

### 1. Passive Income
- Run verification node to earn M1N3 tokens
- No expensive hardware required
- Rewards proportional to Bitcoin history

### 2. Historical Preservation
- Entire Bitcoin blockchain registered on Sui
- Permanent, verifiable record
- Cross-chain proof of Bitcoin state

### 3. Research & Analytics
- On-chain Bitcoin data for analysis
- Verified difficulty progression
- Block time statistics

### 4. DeFi Integration
- M1N3 tokens can be traded
- Liquidity pools (M1N3/SUI)
- Staking mechanisms

### 5. Educational Tool
- Learn Bitcoin block structure
- Understand SHA-256 hashing
- Practice blockchain verification

## 🛣️ Roadmap

### Phase 1: Core Verification (Current)
- ✅ Block header registration
- ✅ Field verification (5 fields)
- ✅ M1N3 token rewards
- ✅ Dynamic granularity
- ✅ Web interface

### Phase 2: Merkle Path (Future)
- ❌ Enable merkle root verification
- ❌ Transaction path proofs
- ❌ Distribute remaining 50% rewards

### Phase 3: Advanced Features
- ❌ Cross-chain bridges
- ❌ M1N3 governance
- ❌ Automated market maker
- ❌ Mobile verification app

### Phase 4: Scale
- ❌ Lightning-fast verification
- ❌ Parallel session processing
- ❌ Global node coordination

## 🤝 Contributing

We welcome contributions! Areas of focus:

- **Smart Contract Optimization**: Gas efficiency
- **Python Client**: Better error handling
- **Web UI**: Enhanced visualizations
- **Documentation**: Tutorials and guides
- **Testing**: Comprehensive test suite

## 📜 License

GPL-3.0 (same as P2Pool)

## 🆘 Support

- **Issues**: GitHub Issues
- **Documentation**: This README + SUI_INTEGRATION.md
- **Community**: (TODO: Discord/Telegram)

## 🔬 Technical Details

### Block Header Format

Bitcoin block header (80 bytes):

```
┌─────────────┬───────────────────────────┐
│ Offset      │ Field                     │
├─────────────┼───────────────────────────┤
│ 0-3         │ Version (4 bytes)         │
│ 4-35        │ Previous Block (32 bytes) │
│ 36-67       │ Merkle Root (32 bytes)    │
│ 68-71       │ Timestamp (4 bytes)       │
│ 72-75       │ Bits (4 bytes)            │
│ 76-79       │ Nonce (4 bytes)           │
└─────────────┴───────────────────────────┘
```

### Subsidy Calculation

```python
def calculate_subsidy(height):
    halvings = height // 210000
    if halvings >= 64:
        return 0
    subsidy = 50 * 100000000  # 50 BTC in satoshis
    return subsidy >> halvings
```

### M1N3 Reward Formula

```
total_m1n3 = subsidy_satoshis × 1000
block_verification_pool = total_m1n3 / 2
merkle_pool = total_m1n3 / 2  # Not distributed yet

field_reward = block_verification_pool / 5
```

## 💡 FAQ

**Q: Do I need mining hardware?**
A: No! M1N3 verifies existing blocks, no mining needed.

**Q: How much can I earn?**
A: Depends on which blocks you verify. Early blocks (high subsidy) offer more rewards.

**Q: What about Merkle root verification?**
A: Currently disabled. 50% of rewards are reserved for future Merkle path verification.

**Q: Can I verify the same block as others?**
A: Yes! Multiple nodes coordinate to verify different fields of the same block.

**Q: What if I submit wrong data?**
A: On-chain SHA-256 verification will reject it. No reward.

**Q: How long does verification take?**
A: Depends on node participation. More nodes = faster completion.

**Q: Is M1N3 token valuable?**
A: Market determines value. It represents verified Bitcoin blockchain work.

---

**Built with ❤️ for decentralized Bitcoin verification**
