"""
Sui blockchain client for P2Pool share registration and trading
"""

import hashlib
import time
import sys
from twisted.internet import defer, threads
from twisted.python import log

try:
    from pysui import SuiConfig, SyncClient, ObjectID
    from pysui.sui.sui_types.scalars import SuiInteger, SuiString
    from pysui.sui.sui_txn import SyncTransaction
    SUI_AVAILABLE = True
except ImportError:
    SUI_AVAILABLE = False
    print >>sys.stderr, 'Warning: pysui not installed. Sui integration disabled.'
    print >>sys.stderr, '         Install with: pip install pysui>=0.50.0'

from p2pool.bitcoin import data as bitcoin_data
from p2pool.util import pack

class SuiShareRegistry(object):
    """
    Manages registration of P2Pool shares on Sui blockchain
    """
    def __init__(self, config_path=None, package_id=None, registry_id=None, private_key=None):
        """
        Initialize Sui client for P2Pool

        Args:
            config_path: Path to Sui client config (default: ~/.sui/sui_config/client.yaml)
            package_id: Deployed package ID of p2pool_shares module
            registry_id: Shared object ID of ShareRegistry
            private_key: Private key for signing transactions (hex string)
        """
        self.enabled = SUI_AVAILABLE and package_id and registry_id

        if not self.enabled:
            if not SUI_AVAILABLE:
                print >>sys.stderr, 'Sui integration disabled: pysui not installed'
            else:
                print >>sys.stderr, 'Sui integration disabled: missing package_id or registry_id'
            return

        try:
            # Initialize Sui client
            self.config = SuiConfig.default_config() if not config_path else SuiConfig.from_config_file(config_path)
            self.client = SyncClient(self.config)
            self.package_id = package_id
            self.registry_id = registry_id

            print 'Sui integration enabled:'
            print '  Network:', self.config.active_address
            print '  Package ID:', self.package_id
            print '  Registry ID:', self.registry_id

        except Exception as e:
            print >>sys.stderr, 'Failed to initialize Sui client:', str(e)
            self.enabled = False

    @defer.inlineCallbacks
    def register_block_template(self, work):
        """
        Register a Bitcoin block template on Sui

        Args:
            work: Block template dict from bitcoind getblocktemplate

        Returns:
            Transaction digest on success, None on failure
        """
        if not self.enabled:
            defer.returnValue(None)

        try:
            # Prepare template data
            template_data = {
                'height': work['height'],
                'previous_block': work['previous_block'],
                'version': work['version'],
                'bits': work['bits'].target,
                'coinbase_value': work['subsidy'],
                'timestamp': work['time'],
                'tx_count': len(work['transactions']),
            }

            # Compute template hash
            template_bytes = pack.IntType(32).pack(template_data['height'])
            template_bytes += pack.IntType(256).pack(template_data['previous_block'])
            template_bytes += pack.IntType(32).pack(template_data['version'])
            template_hash = hashlib.sha256(template_bytes).digest()

            # Call Sui move function in a thread to avoid blocking
            result = yield threads.deferToThread(
                self._register_template_sync,
                template_hash,
                template_data
            )

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error registering block template on Sui:')
            defer.returnValue(None)

    def _register_template_sync(self, template_hash, template_data):
        """Synchronous call to register template"""
        try:
            # Build transaction
            txn = SyncTransaction(client=self.client)

            # Call register_block_template
            txn.move_call(
                target=f"{self.package_id}::share_registry::register_block_template",
                arguments=[
                    self.registry_id,  # ShareRegistry
                    list(bytearray(template_hash)),  # template_hash
                    template_data['height'],  # height
                    list(bytearray(pack.IntType(256).pack(template_data['previous_block']))),  # previous_block_hash
                    list(bytearray(b'\x00' * 32)),  # merkle_root (placeholder)
                    template_data['version'],  # version
                    template_data['bits'],  # bits
                    template_data['coinbase_value'],  # coinbase_value
                    template_data['timestamp'],  # timestamp
                    template_data['tx_count'],  # tx_count
                    "0x6",  # Clock object
                ]
            )

            # Execute transaction
            result = txn.execute(gas_budget="100000000")

            if result.is_ok():
                return result.result_data.digest
            else:
                print >>sys.stderr, 'Template registration failed:', result.result_string
                return None

        except Exception as e:
            print >>sys.stderr, 'Template registration error:', str(e)
            return None

    @defer.inlineCallbacks
    def mint_share(self, share, block_header, is_block_winner=False):
        """
        Mint a P2Pool share as an NFT on Sui

        Args:
            share: BaseShare instance
            block_header: Bitcoin block header dict
            is_block_winner: Whether this share found a block

        Returns:
            Share object ID on success, None on failure
        """
        if not self.enabled:
            defer.returnValue(None)

        try:
            # Extract share data
            share_hash = share.hash
            share_info = share.share_info
            share_data = share_info['share_data']

            # Prepare share data for verification
            share_bytes = self._serialize_share_for_verification(share)

            # Block header hash
            block_header_hash = bitcoin_data.hash256(bitcoin_data.block_header_type.pack(block_header))

            # Difficulty target from bits
            difficulty_target = pack.IntType(256).pack(share_info['bits'].target)

            # Previous share hash
            previous_share_hash = pack.IntType(256).pack(share_data['previous_share_hash']) if share_data['previous_share_hash'] else b'\x00' * 32

            # Block template ID (use block hash for now)
            template_id = pack.IntType(256).pack(block_header['previous_block'])

            # Call Sui move function in a thread
            result = yield threads.deferToThread(
                self._mint_share_sync,
                block_header_hash,
                pack.IntType(256).pack(share_hash),
                previous_share_hash,
                pack.IntType(160).pack(share_data['pubkey_hash']),
                share_info['bits'].bits,
                difficulty_target,
                share_info['absheight'],
                share_info['timestamp'],
                share_data['nonce'],
                share_data['subsidy'],
                template_id,
                is_block_winner,
                share_bytes
            )

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error minting share on Sui:')
            defer.returnValue(None)

    def _mint_share_sync(self, block_header_hash, share_hash, previous_share_hash,
                         miner_pubkey_hash, difficulty_bits, difficulty_target,
                         block_height, timestamp, nonce, subsidy, template_id,
                         is_block_winner, share_data):
        """Synchronous call to mint share"""
        try:
            # Build transaction
            txn = SyncTransaction(client=self.client)

            # Call mint_share
            txn.move_call(
                target=f"{self.package_id}::share_registry::mint_share",
                arguments=[
                    self.registry_id,  # ShareRegistry
                    list(bytearray(block_header_hash)),  # block_header_hash
                    list(bytearray(share_hash)),  # share_hash
                    list(bytearray(previous_share_hash)),  # previous_share_hash
                    list(bytearray(miner_pubkey_hash)),  # miner_pubkey_hash
                    difficulty_bits,  # difficulty_bits
                    list(bytearray(difficulty_target)),  # difficulty_target
                    block_height,  # block_height
                    timestamp,  # timestamp
                    nonce,  # nonce
                    subsidy,  # subsidy
                    list(bytearray(template_id)),  # block_template_id
                    is_block_winner,  # is_block_winner
                    list(bytearray(share_data)),  # share_data_to_verify
                    "0x6",  # Clock object
                ]
            )

            # Execute transaction
            result = txn.execute(gas_budget="100000000")

            if result.is_ok():
                # Extract share object ID from transaction effects
                # This would be in the created objects
                print 'Share minted on Sui! Digest:', result.result_data.digest
                return result.result_data.digest
            else:
                print >>sys.stderr, 'Share minting failed:', result.result_string
                return None

        except Exception as e:
            print >>sys.stderr, 'Share minting error:', str(e)
            return None

    def _serialize_share_for_verification(self, share):
        """
        Serialize share data for on-chain verification
        Returns bytes that should hash to share_hash
        """
        # This should match the share serialization format
        # For now, use the share's packed format
        try:
            share_type = share.__class__.get_dynamic_types(share.net)['share_type']
            share_dict = {
                'min_header': share.min_header,
                'share_info': share.share_info,
                'ref_merkle_link': share.ref_merkle_link,
                'last_txout_nonce': share.last_txout_nonce,
                'hash_link': share.hash_link,
                'merkle_link': share.merkle_link,
            }
            return share_type.pack(share_dict)
        except Exception as e:
            print >>sys.stderr, 'Share serialization error:', str(e)
            return b''

    @defer.inlineCallbacks
    def get_registry_stats(self):
        """
        Get statistics from the Sui share registry

        Returns:
            Tuple of (total_shares, total_templates, total_block_winners)
        """
        if not self.enabled:
            defer.returnValue((0, 0, 0))

        try:
            result = yield threads.deferToThread(self._get_stats_sync)
            defer.returnValue(result)
        except Exception as e:
            log.err(None, 'Error getting registry stats:')
            defer.returnValue((0, 0, 0))

    def _get_stats_sync(self):
        """Synchronous call to get registry stats"""
        try:
            # Query the registry object
            result = self.client.get_object(self.registry_id)

            if result.is_ok():
                data = result.result_data
                # Extract stats from registry fields
                total_shares = data.content.fields.get('total_shares', 0)
                total_templates = data.content.fields.get('total_templates', 0)
                total_winners = data.content.fields.get('total_block_winners', 0)
                return (total_shares, total_templates, total_winners)
            else:
                return (0, 0, 0)
        except Exception:
            return (0, 0, 0)


# Singleton instance
_sui_registry = None

def init_sui_registry(config_path=None, package_id=None, registry_id=None, private_key=None):
    """Initialize the global Sui registry instance"""
    global _sui_registry
    _sui_registry = SuiShareRegistry(config_path, package_id, registry_id, private_key)
    return _sui_registry

def get_sui_registry():
    """Get the global Sui registry instance"""
    return _sui_registry
