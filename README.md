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

### Phase 1: Historical Verification

```bash
python run_p2pool.py \
  --m1n3-enable \
  --m1n3-package-id <SUI_PACKAGE_ID> \
  --m1n3-registry-id <BLOCK_REGISTRY_ID> \
  --m1n3-treasury-id <TREASURY_ID> \
  --m1n3-start-height 0 \
  --m1n3-end-height 100000 \
  --m1n3-auto-verify
```

### Phase 2: Real-Time Mining

#### As Staker/Template Proposer
```bash
python run_p2pool.py \
  --m1n3-enable \
  --m1n3-mining-mode \
  --m1n3-package-id <SUI_PACKAGE_ID> \
  --m1n3-staking-registry-id <STAKING_REGISTRY_ID> \
  --m1n3-mining-registry-id <MINING_REGISTRY_ID> \
  --m1n3-stake-amount 100000
```

#### As Miner
```bash
python run_p2pool.py \
  --m1n3-enable \
  --m1n3-mining-mode \
  --m1n3-package-id <SUI_PACKAGE_ID> \
  --m1n3-mining-registry-id <MINING_REGISTRY_ID>
```

Then connect your mining software to `127.0.0.1:9332`

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
