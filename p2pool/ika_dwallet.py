"""
IKA dWallet integration for M1N3 PPLNS autonomous rewards.
Creates and manages shared dWallets for decentralized Bitcoin custody.
"""

from twisted.internet import defer
import json
import subprocess
import logging

log = logging.getLogger(__name__)

# Global dWallet instance
_dwallet_manager = None

def get_dwallet_manager():
    """Get global dWallet manager instance."""
    return _dwallet_manager

def init_dwallet_manager(config):
    """Initialize global dWallet manager."""
    global _dwallet_manager
    _dwallet_manager = DWalletManager(config)
    return _dwallet_manager


class DWalletManager(object):
    """
    Manages IKA dWallet for PPLNS pool rewards.
    Handles dWallet creation, transaction proposals, and threshold signing.
    """

    def __init__(self, config):
        self.enabled = config.get('enabled', False)
        self.network = config.get('network', 'testnet')  # mainnet, testnet, signet
        self.threshold = config.get('threshold', 2)  # 2-of-3 default
        self.participants = config.get('participants', [])  # Sui addresses
        self.package_id = config.get('package_id')
        self.dwallet_id = config.get('dwallet_id')  # Set after creation
        self.bitcoin_address = config.get('bitcoin_address')  # Set after creation

        log.info('IKA dWallet Manager initialized: network=%s, threshold=%d/%d',
                 self.network, self.threshold, len(self.participants))

    @defer.inlineCallbacks
    def create_shared_dwallet(self, sui_client):
        """
        Create a new shared IKA dWallet for the PPLNS pool.

        Steps:
        1. Use IKA SDK to create dWallet with threshold signatures
        2. Register the dWallet in M1N3 Sui contract as shared object
        3. Store dWallet ID and Bitcoin address for pool use

        Args:
            sui_client: Sui blockchain client

        Returns:
            dict: dWallet info (id, bitcoin_address, cap_id)
        """
        if not self.enabled:
            defer.returnValue(None)

        log.info('Creating shared IKA dWallet...')

        try:
            # Step 1: Create dWallet using IKA SDK
            # This would normally use IKA JavaScript/TypeScript SDK
            # For now, we'll call it via subprocess

            dwallet_info = yield self._call_ika_sdk_create_dwallet()

            bitcoin_address = dwallet_info['bitcoin_address']
            dwallet_cap_id = dwallet_info['cap_id']

            # Step 2: Register as shared object in Sui
            result = yield self._register_shared_dwallet(
                sui_client,
                bitcoin_address,
                dwallet_cap_id
            )

            # Store for future use
            self.dwallet_id = result['dwallet_id']
            self.bitcoin_address = bitcoin_address

            log.info('Shared dWallet created successfully!')
            log.info('  dWallet ID: %s', self.dwallet_id)
            log.info('  Bitcoin Address: %s', bitcoin_address)
            log.info('  Network: %s', self.network)
            log.info('  Threshold: %d/%d', self.threshold, len(self.participants))

            defer.returnValue({
                'dwallet_id': self.dwallet_id,
                'bitcoin_address': bitcoin_address,
                'cap_id': dwallet_cap_id,
                'network': self.network,
                'threshold': self.threshold,
            })

        except Exception as e:
            log.err(None, 'Failed to create shared dWallet:')
            defer.returnValue(None)

    @defer.inlineCallbacks
    def _call_ika_sdk_create_dwallet(self):
        """
        Call IKA SDK to create dWallet via Node.js subprocess.

        In production, this would use the IKA SDK:

        const ika = new IkaClient(suiClient);
        const dwallet = await ika.createDWallet({
            network: 'bitcoin',
            threshold: 2,
            participants: [address1, address2, address3]
        });
        """

        # For demonstration, return mock data
        # In production, call actual IKA SDK
        log.info('Calling IKA SDK to create dWallet (network=%s, threshold=%d/%d)',
                 self.network, self.threshold, len(self.participants))

        # Mock response - replace with actual IKA SDK call
        dwallet_info = {
            'bitcoin_address': 'tb1q' + 'a' * 39,  # Mock testnet address
            'cap_id': '0x' + 'f' * 64,  # Mock capability ID
            'dwallet_id': '0x' + 'd' * 64,  # Mock dWallet ID from IKA
        }

        defer.returnValue(dwallet_info)

    @defer.inlineCallbacks
    def _register_shared_dwallet(self, sui_client, bitcoin_address, dwallet_cap_id):
        """
        Register the dWallet as a shared Sui object.

        Calls m1n3_dwallet::create_shared_dwallet()
        """
        try:
            # Convert Bitcoin address and cap ID to bytes
            btc_addr_bytes = list(bitcoin_address.encode('utf-8'))
            cap_id_bytes = list(dwallet_cap_id.encode('utf-8'))
            network_bytes = list(self.network.encode('utf-8'))

            # Prepare transaction
            tx_data = {
                'packageObjectId': self.package_id,
                'module': 'm1n3_dwallet',
                'function': 'create_shared_dwallet',
                'typeArguments': [],
                'arguments': [
                    btc_addr_bytes,
                    cap_id_bytes,
                    network_bytes,
                    self.threshold,
                    self.participants,
                ],
                'gasBudget': 10000000,
            }

            # Execute transaction (simplified)
            log.info('Registering shared dWallet on Sui...')

            # Mock result - in production, use actual Sui client
            result = {
                'dwallet_id': '0x' + 'a' * 64,
                'tx_digest': '0x' + 'b' * 64,
            }

            defer.returnValue(result)

        except Exception as e:
            log.err(None, 'Failed to register shared dWallet:')
            raise

    @defer.inlineCallbacks
    def propose_pplns_distribution(self, recipients):
        """
        Propose a PPLNS reward distribution transaction.

        Args:
            recipients: List of (miner_address, bitcoin_address, amount_satoshis)

        Returns:
            str: Transaction ID
        """
        if not self.enabled or not self.dwallet_id:
            defer.returnValue(None)

        log.info('Proposing PPLNS distribution to %d recipients...', len(recipients))

        try:
            # Create recipient objects
            recipient_objects = []
            total_amount = 0

            for miner_addr, btc_addr, amount in recipients:
                recipient_objects.append({
                    'bitcoin_address': list(btc_addr.encode('utf-8')),
                    'amount': amount,
                    'miner_address': miner_addr,
                })
                total_amount += amount

            # Propose transaction on-chain
            purpose = 'PPLNS reward distribution for block height XXX'

            # Call propose_pplns_distribution on Sui
            tx_id = yield self._call_sui_propose_distribution(
                recipient_objects,
                purpose
            )

            log.info('PPLNS distribution proposed: tx_id=%s, total=%d sats, recipients=%d',
                     tx_id, total_amount, len(recipients))

            defer.returnValue(tx_id)

        except Exception as e:
            log.err(None, 'Failed to propose PPLNS distribution:')
            defer.returnValue(None)

    @defer.inlineCallbacks
    def _call_sui_propose_distribution(self, recipients, purpose):
        """
        Call Sui contract to propose distribution transaction.
        """
        # Mock implementation - replace with actual Sui transaction
        tx_id = '0x' + 'c' * 64
        defer.returnValue(tx_id)

    @defer.inlineCallbacks
    def sign_transaction(self, tx_id, signer_private_key):
        """
        Sign a pending dWallet transaction.

        Args:
            tx_id: Transaction ID to sign
            signer_private_key: Private key of authorized signer

        Returns:
            bool: True if signature successful
        """
        if not self.enabled:
            defer.returnValue(False)

        log.info('Signing dWallet transaction: %s', tx_id)

        try:
            # Call Sui contract to record signature
            # When threshold is reached, IKA 2PC-MPC signing will trigger

            # Mock implementation
            success = True

            if success:
                log.info('Transaction signature recorded: %s', tx_id)

            defer.returnValue(success)

        except Exception as e:
            log.err(None, 'Failed to sign transaction:')
            defer.returnValue(False)

    def get_bitcoin_address(self):
        """Get the dWallet's Bitcoin address for pool coinbase."""
        return self.bitcoin_address

    def get_dwallet_id(self):
        """Get the shared dWallet object ID."""
        return self.dwallet_id


def create_ika_config(network='testnet', threshold=2, participants=None):
    """
    Create IKA dWallet configuration.

    Args:
        network: Bitcoin network (mainnet, testnet, signet)
        threshold: Threshold for signatures (e.g., 2 for 2-of-3)
        participants: List of Sui addresses that can sign

    Returns:
        dict: Configuration for DWalletManager
    """
    if participants is None:
        participants = []

    return {
        'enabled': True,
        'network': network,
        'threshold': threshold,
        'participants': participants,
        'package_id': None,  # Set after deployment
        'dwallet_id': None,  # Set after creation
        'bitcoin_address': None,  # Set after creation
    }
