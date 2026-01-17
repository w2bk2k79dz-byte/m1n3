"""
IKA dWallet Manager for Autonomous PPLNS Rewards

This module handles the Sui-side of PPLNS distributions.
IKA network automatically executes Bitcoin transactions by listening to Sui events.

Architecture:
  SUI NETWORK (Source of Truth):
    - Share window tracking (last 8,640 shares)
    - PPLNS calculations (transparent, verifiable)
    - Distribution events emitted via PPLNSDistributionProposed

  IKA NETWORK (Autonomous Execution):
    - Listens to Sui blockchain events
    - Reads distribution data from Sui
    - Verifies calculations against on-chain share window
    - Automatically signs and broadcasts Bitcoin transactions
    - Confirms execution via mark_distribution_executed callback

  NO MANUAL APPROVALS - Fully autonomous based on on-chain data verification
"""

from twisted.internet import defer
from twisted.python import log

try:
    from pysui import SuiConfig, SyncClient
    from pysui.sui.sui_txn import SyncTransaction
    IKA_AVAILABLE = True
except ImportError:
    IKA_AVAILABLE = False
    import sys
    print >>sys.stderr, 'Warning: pysui not installed. IKA dWallet integration disabled.'


class DWalletManager(object):
    """
    Manages IKA dWallet for PPLNS pool rewards.

    Responsibilities:
      - Create dWallet with IKA SDK
      - Register dWallet as shared object on Sui
      - Propose PPLNS distributions (emit events for IKA)
      - IKA network handles all Bitcoin transaction signing AUTONOMOUSLY
    """

    def __init__(self, config):
        """
        Initialize dWallet manager.

        Args:
            config: Configuration dict with:
                - enabled: bool
                - network: 'mainnet', 'testnet', or 'signet'
                - package_id: M1N3 package ID
                - dwallet_id: Existing dWallet ID (optional)
                - bitcoin_address: dWallet Bitcoin address (optional)
        """
        self.enabled = config.get('enabled', False) and IKA_AVAILABLE
        self.network = config.get('network', 'mainnet')
        self.package_id = config.get('package_id')

        # dWallet info (set after creation or from config)
        self.dwallet_id = config.get('dwallet_id')
        self.bitcoin_address = config.get('bitcoin_address')
        self.dwallet_cap_id = config.get('dwallet_cap_id')

        # Sui client
        self.sui_client = None

        if self.enabled:
            try:
                self.sui_config = SuiConfig.default_config()
                self.sui_client = SyncClient(self.sui_config)
                log.msg('IKA dWallet manager initialized')
                log.msg('  Network: %s' % self.network)
                log.msg('  Package: %s' % self.package_id)
                if self.dwallet_id:
                    log.msg('  dWallet ID: %s' % self.dwallet_id)
                    log.msg('  Bitcoin Address: %s' % self.bitcoin_address)
            except Exception as e:
                log.err('Failed to initialize dWallet manager: %s' % str(e))
                self.enabled = False

    @defer.inlineCallbacks
    def create_shared_dwallet(self, mining_registry_id):
        """
        Create a shared dWallet for PPLNS pool using IKA SDK.

        This creates:
          1. IKA dWallet (Bitcoin key management via 2PC-MPC)
          2. Sui shared object (for on-chain accountability)

        Args:
            mining_registry_id: MiningRegistry object ID

        Returns:
            dict with dwallet_id, bitcoin_address, dwallet_cap_id

        Note: In production, you would call IKA SDK here to create the actual dWallet.
              For now, this is a placeholder that expects dWallet info to be configured.

        Example IKA SDK usage (JavaScript):
          ```javascript
          const ika = new IkaClient(suiClient);
          const dwallet = await ika.createDWallet({
            network: 'bitcoin',
          });
          const btcAddress = await dwallet.getAddress('bitcoin');
          ```
        """
        if not self.enabled:
            defer.returnValue(None)

        try:
            # TODO: Call IKA SDK to create dWallet
            # from ika import IkaClient
            # ika = IkaClient(self.sui_client)
            # dwallet_result = yield ika.create_dwallet(network='bitcoin')
            # self.bitcoin_address = dwallet_result['bitcoin_address']
            # self.dwallet_cap_id = dwallet_result['cap_id']

            # For now, check if configured
            if not self.bitcoin_address or not self.dwallet_cap_id:
                log.err('dWallet not configured. Please set bitcoin_address and dwallet_cap_id.')
                log.err('Use IKA SDK to create dWallet first.')
                defer.returnValue(None)

            # Register as shared object on Sui
            result = yield self._register_shared_dwallet_on_sui(mining_registry_id)

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error creating shared dWallet:')
            defer.returnValue(None)

    @defer.inlineCallbacks
    def _register_shared_dwallet_on_sui(self, mining_registry_id):
        """Register dWallet as shared object on Sui blockchain."""
        try:
            # Build transaction
            txn = SyncTransaction(client=self.sui_client)

            # Convert Bitcoin address and cap ID to bytes
            btc_addr_bytes = list(bytearray(self.bitcoin_address.encode('utf-8')))
            cap_id_bytes = list(bytearray(self.dwallet_cap_id.encode('utf-8')))
            network_bytes = list(bytearray(self.network.encode('utf-8')))

            txn.move_call(
                target=f"{self.package_id}::m1n3_dwallet::create_shared_dwallet",
                arguments=[
                    btc_addr_bytes,
                    cap_id_bytes,
                    network_bytes,
                    mining_registry_id,
                    "0x6",  # Clock
                ]
            )

            # Execute
            result = txn.execute(gas_budget="100000000")

            if result.is_ok():
                log.msg('=' * 70)
                log.msg('Shared dWallet created on Sui!')
                log.msg('  Bitcoin Address: %s' % self.bitcoin_address)
                log.msg('  Network: %s' % self.network)
                log.msg('  Mining Registry: %s' % mining_registry_id)
                log.msg('')
                log.msg('IKA NETWORK IS NOW LISTENING FOR PPLNS DISTRIBUTIONS')
                log.msg('Bitcoin transactions will be executed AUTOMATICALLY when:')
                log.msg('  1. Block is found')
                log.msg('  2. PPLNS distribution proposed on Sui')
                log.msg('  3. IKA verifies distribution against share window')
                log.msg('  4. IKA signs and broadcasts Bitcoin transaction')
                log.msg('=' * 70)

                # TODO: Extract dwallet_id from events
                defer.returnValue({
                    'bitcoin_address': self.bitcoin_address,
                    'dwallet_cap_id': self.dwallet_cap_id,
                    'network': self.network
                })
            else:
                log.err('Failed to create shared dWallet: %s' % result.result_string)
                defer.returnValue(None)

        except Exception as e:
            log.err(None, 'Error registering dWallet on Sui:')
            defer.returnValue(None)

    @defer.inlineCallbacks
    def propose_pplns_distribution(self, block_height, coinbase_value, recipients):
        """
        Propose PPLNS distribution for a found block.

        This emits an event on Sui that IKA network will AUTOMATICALLY execute.

        Args:
            block_height: Block height (u32)
            coinbase_value: Block reward in satoshis (u64)
            recipients: List of tuples (miner_sui_addr, btc_addr, amount_satoshis, difficulty)

        Returns:
            distribution_id if successful, None otherwise

        AUTONOMOUS FLOW:
          1. M1N3 calls this when block is found
          2. Transaction emits PPLNSDistributionProposed event on Sui
          3. IKA network reads event from Sui blockchain
          4. IKA verifies distribution matches on-chain share window
          5. IKA AUTOMATICALLY signs and broadcasts Bitcoin transaction
          6. IKA calls mark_distribution_executed() to confirm on Sui
          7. Done - NO MANUAL INTERACTION NEEDED
        """
        if not self.enabled or not self.dwallet_id:
            defer.returnValue(None)

        try:
            log.msg('')
            log.msg('=' * 70)
            log.msg('PROPOSING PPLNS DISTRIBUTION')
            log.msg('  Block Height: %d' % block_height)
            log.msg('  Coinbase: %.8f BTC' % (coinbase_value / 1e8))
            log.msg('  Recipients: %d miners' % len(recipients))
            log.msg('=' * 70)

            # Build Sui transaction
            result = yield defer.succeed(self._propose_distribution_sync(
                block_height,
                coinbase_value,
                recipients
            ))

            if result:
                log.msg('')
                log.msg('PPLNS DISTRIBUTION PROPOSED SUCCESSFULLY!')
                log.msg('  Distribution ID: %s' % result)
                log.msg('')
                log.msg('IKA NETWORK WILL NOW AUTOMATICALLY:')
                log.msg('  [1] Read PPLNSDistributionProposed event from Sui')
                log.msg('  [2] Verify distribution against on-chain share window')
                log.msg('  [3] Sign Bitcoin transaction (2PC-MPC automatic)')
                log.msg('  [4] Broadcast transaction to Bitcoin network')
                log.msg('  [5] Confirm execution on Sui blockchain')
                log.msg('')
                log.msg('NO MANUAL APPROVAL NEEDED - Fully autonomous execution!')
                log.msg('=' * 70)

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error proposing PPLNS distribution:')
            defer.returnValue(None)

    def _propose_distribution_sync(self, block_height, coinbase_value, recipients):
        """Synchronous distribution proposal."""
        try:
            txn = SyncTransaction(client=self.sui_client)

            # Build recipients array
            # Format: each recipient is (btc_addr_bytes, amount, sui_addr, difficulty)
            recipients_data = []
            for miner_sui_addr, btc_addr, amount_sats, difficulty in recipients:
                # Create recipient using the contract's helper function
                # In practice, you'd build this more carefully
                recipients_data.append({
                    'bitcoin_address': list(bytearray(btc_addr.encode('utf-8'))),
                    'amount': amount_sats,
                    'miner_address': miner_sui_addr,
                    'difficulty': difficulty
                })

            # Call propose_pplns_distribution
            # This emits PPLNSDistributionProposed event that IKA listens to
            txn.move_call(
                target=f"{self.package_id}::m1n3_dwallet::propose_pplns_distribution",
                arguments=[
                    self.dwallet_id,
                    block_height,
                    coinbase_value,
                    recipients_data,  # This needs proper serialization
                    "0x6",  # Clock
                ]
            )

            # Execute
            result = txn.execute(gas_budget="200000000")

            if result.is_ok():
                # TODO: Extract distribution_id from events
                return "distribution_0"  # Placeholder
            else:
                log.err('Distribution proposal failed: %s' % result.result_string)
                return None

        except Exception as e:
            log.err('Distribution proposal error: %s' % str(e))
            return None

    def get_bitcoin_address(self):
        """Get the dWallet's Bitcoin address for pool coinbase."""
        return self.bitcoin_address

    def get_dwallet_id(self):
        """Get the shared dWallet object ID on Sui."""
        return self.dwallet_id


# Global instance
_dwallet_manager = None

def create_ika_config(network='mainnet', threshold=None, participants=None):
    """
    Create IKA dWallet configuration.

    Note: threshold and participants are NO LONGER NEEDED.
          IKA network validators automatically handle signing based on
          Sui data verification. No manual threshold approvals required.

    Args:
        network: Bitcoin network ('mainnet', 'testnet', 'signet')
        threshold: [DEPRECATED - Not used, IKA decides automatically]
        participants: [DEPRECATED - Not used, IKA network validators]

    Returns:
        config dict
    """
    return {
        'enabled': False,  # Set to True when dWallet is configured
        'network': network,
        # No threshold or participants - IKA handles this automatically
    }

def init_dwallet_manager(config):
    """Initialize global dWallet manager."""
    global _dwallet_manager
    _dwallet_manager = DWalletManager(config)
    return _dwallet_manager

def get_dwallet_manager():
    """Get global dWallet manager."""
    return _dwallet_manager
