# P2Pool Sui Blockchain Integration

## Overview

This P2Pool implementation now integrates with the Sui blockchain to register mining shares on-chain, verify them using Sui's native SHA-256 hash function, and mint them as tradeable NFT objects.

## Features

- ✅ **On-Chain Share Registration**: Every valid P2Pool share is registered on Sui blockchain
- ✅ **Block Template Storage**: Bitcoin block templates are stored on-chain for verification
- ✅ **Native Verification**: Shares are verified on-chain using Sui's native `sha2_256` function
- ✅ **Tradeable Share NFTs**: Each share is minted as a unique NFT that can be traded
- ✅ **Block Winner Tracking**: Shares that find Bitcoin blocks are specially marked
- ✅ **Difficulty Metadata**: Each share includes difficulty information for valuation

## Architecture

### Smart Contract (Move)

Located in `sui_contracts/sources/p2pool_shares.move`

Key components:
- **MiningShare**: NFT object representing a mined share with difficulty and metadata
- **BlockTemplate**: On-chain record of Bitcoin block templates
- **ShareRegistry**: Global registry tracking all shares and preventing duplicates
- **Verification**: On-chain SHA-256 verification of share validity

### Python Integration

Located in `p2pool/sui_client.py`

Features:
- Automatic block template registration when new work arrives
- Automatic share minting when shares are verified
- Deferred execution to avoid blocking mining operations
- Configurable via command-line arguments

## Setup Instructions

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

This installs:
- `pysui>=0.50.0` - Sui Python SDK
- Other P2Pool dependencies

### 2. Deploy Smart Contract

First, set up Sui CLI and create a wallet:

```bash
# Install Sui CLI (if not already installed)
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch mainnet sui

# Initialize Sui configuration
sui client

# Request testnet tokens (for testing)
sui client faucet
```

Deploy the smart contract:

```bash
cd sui_contracts

# Build the package
sui move build

# Deploy to Sui network
sui client publish --gas-budget 100000000

# Save the Package ID and ShareRegistry ID from the output
```

### 3. Configure P2Pool

Run P2Pool with Sui integration enabled:

```bash
python run_p2pool.py \
    --sui-enable \
    --sui-package-id 0xYOUR_PACKAGE_ID \
    --sui-registry-id 0xYOUR_REGISTRY_ID \
    --sui-config-path ~/.sui/sui_config/client.yaml \
    [other p2pool arguments]
```

#### Configuration Options

| Argument | Description | Required |
|----------|-------------|----------|
| `--sui-enable` | Enable Sui blockchain integration | Yes |
| `--sui-package-id` | Deployed package ID of p2pool_shares module | Yes |
| `--sui-registry-id` | ShareRegistry shared object ID | Yes |
| `--sui-config-path` | Path to Sui client config (default: ~/.sui/sui_config/client.yaml) | No |
| `--sui-private-key` | Sui private key for signing transactions (hex format) | No |
| `--sui-register-templates` | Register block templates on Sui (default: true) | No |
| `--sui-mint-shares` | Mint shares as tradeable NFTs (default: true) | No |

### 4. View Share Trading Interface

Access the web interface at:
```
http://localhost:9332/static/sui_shares.html
```

This shows:
- Total shares minted on Sui
- Total block templates registered
- Number of block winners
- Recent shares with links to Sui Explorer

## Smart Contract Functions

### For Pool Operators

#### register_block_template
Registers a Bitcoin block template on Sui for verification purposes.

```move
public entry fun register_block_template(
    registry: &mut ShareRegistry,
    template_hash: vector<u8>,
    height: u32,
    previous_block_hash: vector<u8>,
    // ... other parameters
)
```

#### mint_share
Verifies and mints a mining share as an NFT.

```move
public entry fun mint_share(
    registry: &mut ShareRegistry,
    block_header_hash: vector<u8>,
    share_hash: vector<u8>,
    // ... share data
    share_data_to_verify: vector<u8>, // For on-chain verification
)
```

### For Traders

#### transfer_share
Transfer share ownership (free).

```move
public entry fun transfer_share(
    share: MiningShare,
    recipient: address,
    clock: &Clock,
)
```

#### sell_share
Sell share for SUI tokens.

```move
public entry fun sell_share(
    share: MiningShare,
    payment: Coin<SUI>,
    expected_amount: u64,
    recipient: address,
)
```

## Trading Shares

### Direct Transfers

```bash
# Get your share object IDs
sui client objects

# Transfer a share
sui client call \
    --package $PACKAGE_ID \
    --module share_registry \
    --function transfer_share \
    --args $SHARE_OBJECT_ID $RECIPIENT_ADDRESS "0x6" \
    --gas-budget 10000000
```

### Selling Shares

```bash
# Sell a share for SUI
sui client call \
    --package $PACKAGE_ID \
    --module share_registry \
    --function sell_share \
    --args $SHARE_OBJECT_ID $PAYMENT_COIN $AMOUNT $BUYER_ADDRESS "0x6" \
    --gas-budget 10000000
```

### Integrating with NFT Marketplaces

Since shares are standard Sui objects, they can be listed on any Sui NFT marketplace that supports custom objects. Integration examples:

1. **Sui Kiosk**: Create a kiosk and list shares
2. **Bluemove**: List as collectibles
3. **Hyperspace**: Custom collection integration

## Verification

All shares can be independently verified on-chain:

1. The share hash is computed from share data
2. The Bitcoin block header hash is verified against difficulty target
3. Both use Sui's native `sha2_256` function
4. Invalid shares cannot be minted due to on-chain verification

## Economics

### Share Valuation Factors

- **Difficulty**: Higher difficulty shares are rarer and more valuable
- **Block Winners**: Shares that found actual Bitcoin blocks have historical significance
- **Timestamp**: Older shares may have collector value
- **Pool History**: Shares from significant mining events

### Use Cases

1. **Speculation**: Trade shares based on difficulty and rarity
2. **Collectibles**: Block winner shares as memorabilia
3. **Proof of Work**: Verifiable proof of contributed mining power
4. **Derivatives**: Create financial products based on share pools

## API Endpoints

### GET /sui_stats

Returns Sui integration statistics:

```json
{
    "enabled": true,
    "total_shares": 12345,
    "total_templates": 678,
    "total_block_winners": 5,
    "package_id": "0x...",
    "registry_id": "0x...",
    "recent_shares": []
}
```

## Monitoring

### Check Registry Stats

```bash
sui client call \
    --package $PACKAGE_ID \
    --module share_registry \
    --function get_registry_stats \
    --args $REGISTRY_ID
```

### Query Share Details

```bash
sui client object $SHARE_OBJECT_ID
```

## Troubleshooting

### "Sui integration disabled: pysui not installed"

Install the Sui Python SDK:
```bash
pip install pysui>=0.50.0
```

### "Failed to initialize Sui client"

Check your Sui configuration:
```bash
sui client active-address
sui client gas
```

### "Transaction failed: insufficient gas"

Ensure you have enough SUI for gas:
```bash
sui client gas
# Request more from faucet if on testnet
sui client faucet
```

### Shares not appearing on Sui

Check P2Pool logs for errors:
```bash
tail -f data/bitcoin/log
```

## Security Considerations

1. **Private Key Management**: Never commit private keys. Use environment variables or secure vaults.
2. **Gas Management**: Monitor gas usage to avoid excessive costs.
3. **Duplicate Prevention**: The registry prevents duplicate shares automatically.
4. **Verification**: All shares are verified on-chain before minting.

## Future Enhancements

- [ ] Share pooling contracts for collective trading
- [ ] Difficulty-based automatic pricing
- [ ] Integration with DeFi protocols
- [ ] Historical share analytics
- [ ] Mobile wallet integration
- [ ] NFT marketplace frontend

## Support

For issues related to:
- **P2Pool**: Check the main README
- **Sui Integration**: Open an issue with the `sui-integration` label
- **Smart Contracts**: Review the Move code in `sui_contracts/`

## License

This Sui integration maintains the same license as P2Pool (GPL-3.0).
