"""
M1N3 - Decentralized trustless Bitcoin mining verification client

This client coordinates with other nodes to register and verify Bitcoin block data on Sui,
earning M1N3 tokens as rewards.
"""

import hashlib
import struct
import sys
import time
from twisted.internet import defer, threads
from twisted.python import log

try:
    from pysui import SuiConfig, SyncClient
    from pysui.sui.sui_txn import SyncTransaction
    M1N3_AVAILABLE = True
except ImportError:
    M1N3_AVAILABLE = False
    print >>sys.stderr, 'Warning: pysui not installed. M1N3 integration disabled.'

from p2pool.bitcoin import data as bitcoin_data
from p2pool.util import pack

class M1N3Client(object):
    """
    M1N3 client for decentralized Bitcoin block verification
    """
    def __init__(self, config_path=None, package_id=None, registry_id=None,
                 treasury_id=None, start_height=0, end_height=None):
        """
        Initialize M1N3 client

        Args:
            config_path: Path to Sui client config
            package_id: Deployed M1N3 package ID
            registry_id: BlockRegistry shared object ID
            treasury_id: M1N3Treasury shared object ID
            start_height: Starting block height to verify
            end_height: Ending block height (None = continuous)
        """
        self.enabled = M1N3_AVAILABLE and package_id and registry_id and treasury_id

        if not self.enabled:
            if not M1N3_AVAILABLE:
                print >>sys.stderr, 'M1N3 disabled: pysui not installed'
            else:
                print >>sys.stderr, 'M1N3 disabled: missing configuration'
            return

        try:
            self.config = SuiConfig.default_config() if not config_path else SuiConfig.from_config_file(config_path)
            self.client = SyncClient(self.config)
            self.package_id = package_id
            self.registry_id = registry_id
            self.treasury_id = treasury_id
            self.start_height = start_height
            self.end_height = end_height

            # Track registered sessions
            self.registered_sessions = set()
            # Track submitted fields
            self.submitted_fields = {}  # {height: {field_id: True}}

            print 'M1N3 verification client enabled:'
            print '  Package ID:', self.package_id
            print '  Registry ID:', self.registry_id
            print '  Treasury ID:', self.treasury_id
            print '  Block range:', start_height, '-', end_height if end_height else 'continuous'

        except Exception as e:
            print >>sys.stderr, 'Failed to initialize M1N3 client:', str(e)
            self.enabled = False

    @defer.inlineCallbacks
    def register_block_from_bitcoind(self, bitcoind, height):
        """
        Fetch block from bitcoind and register on Sui

        Args:
            bitcoind: Bitcoin RPC client
            height: Block height to register

        Returns:
            True on success, False on failure
        """
        if not self.enabled:
            defer.returnValue(False)

        try:
            # Get block hash at height
            block_hash_hex = yield bitcoind.rpc_getblockhash(height)

            # Get block header
            block_header = yield bitcoind.rpc_getblockheader(block_hash_hex)

            # Get block for subsidy calculation
            block_data = yield bitcoind.rpc_getblock(block_hash_hex)

            # Calculate subsidy (simplified - should use proper halving logic)
            subsidy = self._calculate_subsidy(height)

            # Register on Sui
            result = yield threads.deferToThread(
                self._register_block_sync,
                height,
                block_header,
                subsidy
            )

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error registering block %d on M1N3:' % height)
            defer.returnValue(False)

    def _register_block_sync(self, height, header, subsidy):
        """Synchronous block registration"""
        try:
            # Parse header data
            header_hash = bytes.fromhex(header['hash'])[::-1]  # Reverse for little-endian
            version = header['version']
            prev_hash = bytes.fromhex(header['previousblockhash'])[::-1] if 'previousblockhash' in header else b'\x00' * 32
            merkle_root = bytes.fromhex(header['merkleroot'])[::-1]
            timestamp = header['time']
            bits = int(header['bits'], 16)
            nonce = header['nonce']

            # Build transaction
            txn = SyncTransaction(client=self.client)

            # Convert to proper format for Move
            txn.move_call(
                target=f"{self.package_id}::m1n3_verification::register_block_header",
                arguments=[
                    self.registry_id,
                    self.treasury_id,
                    height,
                    list(bytearray(header_hash)),
                    version,
                    list(bytearray(prev_hash)),
                    list(bytearray(merkle_root)),
                    timestamp,
                    bits,
                    nonce,
                    subsidy,
                    "0x6",  # Clock
                ]
            )

            # Execute
            result = txn.execute(gas_budget="100000000")

            if result.is_ok():
                print 'Block %d registered on M1N3! Digest: %s' % (height, result.result_data.digest)
                print '  Total reward pool: %d M1N3' % (subsidy * 1000)
                print '  Block verification reward: %d M1N3' % (subsidy * 1000 / 2)
                return True
            else:
                print >>sys.stderr, 'Block registration failed:', result.result_string
                return False

        except Exception as e:
            print >>sys.stderr, 'Block registration error:', str(e)
            return False

    @defer.inlineCallbacks
    def register_for_verification(self, height, session_id):
        """
        Register this node to participate in block verification

        Args:
            height: Block height
            session_id: Verification session object ID

        Returns:
            True on success
        """
        if not self.enabled:
            defer.returnValue(False)

        # Track registration
        if height in self.registered_sessions:
            defer.returnValue(True)

        try:
            result = yield threads.deferToThread(
                self._register_for_verification_sync,
                session_id
            )

            if result:
                self.registered_sessions.add(height)
                self.submitted_fields[height] = {}

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error registering for verification:')
            defer.returnValue(False)

    def _register_for_verification_sync(self, session_id):
        """Synchronous verification registration"""
        try:
            txn = SyncTransaction(client=self.client)

            txn.move_call(
                target=f"{self.package_id}::m1n3_verification::register_for_verification",
                arguments=[session_id]
            )

            result = txn.execute(gas_budget="50000000")

            if result.is_ok():
                print 'Registered for verification session'
                return True
            else:
                print >>sys.stderr, 'Registration failed:', result.result_string
                return False

        except Exception as e:
            print >>sys.stderr, 'Registration error:', str(e)
            return False

    @defer.inlineCallbacks
    def submit_field(self, bitcoind, height, session_id, block_header_id, field_id):
        """
        Submit a block field for verification

        Args:
            bitcoind: Bitcoin RPC client
            height: Block height
            session_id: Verification session object ID
            block_header_id: Block header object ID
            field_id: Field ID to submit (0-5, excluding 2)

        Returns:
            Reward amount on success, 0 on failure
        """
        if not self.enabled:
            defer.returnValue(0)

        # Check if already submitted
        if height in self.submitted_fields and field_id in self.submitted_fields[height]:
            defer.returnValue(0)

        # Field 2 (merkle root) is disabled
        if field_id == 2:
            defer.returnValue(0)

        try:
            # Get block data
            block_hash_hex = yield bitcoind.rpc_getblockhash(height)
            block_header = yield bitcoind.rpc_getblockheader(block_hash_hex)

            # Extract field data
            field_data = self._extract_field_data(block_header, field_id)

            if field_data is None:
                defer.returnValue(0)

            # Submit to Sui
            result = yield threads.deferToThread(
                self._submit_field_sync,
                session_id,
                block_header_id,
                field_id,
                field_data
            )

            if result > 0:
                if height not in self.submitted_fields:
                    self.submitted_fields[height] = {}
                self.submitted_fields[height][field_id] = True

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Error submitting field:')
            defer.returnValue(0)

    def _submit_field_sync(self, session_id, block_id, field_id, field_data):
        """Synchronous field submission"""
        try:
            txn = SyncTransaction(client=self.client)

            txn.move_call(
                target=f"{self.package_id}::m1n3_verification::submit_field",
                arguments=[
                    session_id,
                    block_id,
                    self.treasury_id,
                    field_id,
                    list(bytearray(field_data)),
                    "0x6",  # Clock
                ]
            )

            result = txn.execute(gas_budget="100000000")

            if result.is_ok():
                print 'Field %d verified! M1N3 reward earned.' % field_id
                # Parse reward from events (simplified - should parse actual events)
                return 1  # Placeholder
            else:
                print >>sys.stderr, 'Field submission failed:', result.result_string
                return 0

        except Exception as e:
            print >>sys.stderr, 'Field submission error:', str(e)
            return 0

    def _extract_field_data(self, header, field_id):
        """Extract field data from block header"""
        try:
            if field_id == 0:
                # Version (4 bytes, little-endian)
                return struct.pack('<I', header['version'])
            elif field_id == 1:
                # Previous block hash (32 bytes)
                if 'previousblockhash' in header:
                    return bytes.fromhex(header['previousblockhash'])[::-1]
                else:
                    return b'\x00' * 32  # Genesis block
            elif field_id == 2:
                # Merkle root - DISABLED
                return None
            elif field_id == 3:
                # Timestamp (4 bytes, little-endian)
                return struct.pack('<I', header['time'])
            elif field_id == 4:
                # Bits (4 bytes, little-endian)
                bits_int = int(header['bits'], 16)
                return struct.pack('<I', bits_int)
            elif field_id == 5:
                # Nonce (4 bytes, little-endian)
                return struct.pack('<I', header['nonce'])
            else:
                return None
        except Exception as e:
            print >>sys.stderr, 'Error extracting field data:', str(e)
            return None

    def _calculate_subsidy(self, height):
        """Calculate block subsidy at given height (in satoshis)"""
        halvings = height // 210000
        if halvings >= 64:
            return 0
        subsidy = 50 * 100000000  # 50 BTC in satoshis
        return subsidy >> halvings

    @defer.inlineCallbacks
    def run_verification_loop(self, bitcoind):
        """
        Main verification loop - registers blocks and verifies fields

        Args:
            bitcoind: Bitcoin RPC client
        """
        if not self.enabled:
            defer.returnValue(None)

        current_height = self.start_height

        while True:
            try:
                # Check if we've reached end height
                if self.end_height and current_height > self.end_height:
                    print 'Reached end height %d. Stopping verification.' % self.end_height
                    break

                # Register block
                print 'Processing block %d...' % current_height
                registered = yield self.register_block_from_bitcoind(bitcoind, current_height)

                if registered:
                    # TODO: Get session ID from registry
                    # TODO: Register for verification
                    # TODO: Submit fields

                    # For now, just move to next block
                    current_height += 1
                else:
                    # Block might already be registered, try next
                    current_height += 1

                # Sleep between blocks
                yield defer.sleep(1)

            except Exception as e:
                log.err(None, 'Error in verification loop:')
                yield defer.sleep(5)


# Global instance
_m1n3_client = None

def init_m1n3_client(config_path=None, package_id=None, registry_id=None,
                     treasury_id=None, start_height=0, end_height=None):
    """Initialize the global M1N3 client"""
    global _m1n3_client
    _m1n3_client = M1N3Client(config_path, package_id, registry_id, treasury_id, start_height, end_height)
    return _m1n3_client

def get_m1n3_client():
    """Get the global M1N3 client"""
    return _m1n3_client
