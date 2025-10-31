/**
 * Do a transfer from one address to a new one to ensure hb patches the new address
 * Do a transfer that transfers all the tokens to a different address to ensure hb patches a 0 amount on the old address
 *   After that, do a computeTotalSupply call to ensure that hb patches the empty (nil) address afterwards as 0
 */

import {
  handle,
  transfer,
  joinNetwork,
  leaveNetwork,
  delegateStake,
  createVault,
  getVault,
  getInfo,
  tick,
  startMemory,
  totalTokenSupply,
} from './helpers.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import {
  PROCESS_OWNER,
  STUB_ADDRESS,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';

describe('hyperbeam patch balances', async () => {
  let sharedMemory = startMemory;

  // Initialize total token supply for tests that need it
  before(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    sharedMemory = totalTokenSupplyMemory;
  });
  it('should handle sending a patch to a newly created address', async () => {
    const sender = STUB_ADDRESS;
    const recipient = ''.padEnd(43, 'a');
    const quantity = 100000000;
    const transferToSenderAddressMemory = await transfer({
      recipient: sender,
      quantity,
    });
    const transferToRecipientAddress = await handle({
      options: {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: String(quantity / 2) },
        ],
        Timestamp: STUB_TIMESTAMP,
      },
      memory: transferToSenderAddressMemory,
    });
    const patchMessage = transferToRecipientAddress.Messages.at(-1);
    const balancesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'balances',
    );
    const patchData = balancesTag.value;
    assert.equal(patchData[sender], quantity / 2);
    assert.equal(patchData[recipient], quantity / 2);
  });

  it('should handle sending a patch that drains an address', async () => {
    const sender = STUB_ADDRESS;
    const recipient = ''.padEnd(43, 'a');
    const quantity = 100000000;
    const transferToSenderAddressMemory = await transfer({
      recipient: sender,
      quantity,
    });

    const transferToRecipientAddress = await handle({
      options: {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: String(quantity / 2) },
        ],
        Timestamp: STUB_TIMESTAMP,
      },
      memory: transferToSenderAddressMemory,
    });

    const patchMessage = transferToRecipientAddress.Messages.at(-1);
    const balancesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'balances',
    );
    const patchData = balancesTag.value;
    assert.equal(patchData[sender], quantity / 2);
    assert.equal(patchData[recipient], quantity / 2);

    const transferToDrainerAddress = await handle({
      options: {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: String(quantity / 2) },
        ],
        Timestamp: STUB_TIMESTAMP,
      },
      memory: transferToRecipientAddress.Memory,
    });

    const patchMessage2 = transferToDrainerAddress.Messages.at(-1);
    const balancesTag2 = patchMessage2.Tags.find(
      (tag) => tag.name === 'balances',
    );
    const patchData2 = balancesTag2.value;
    assert.equal(patchData2[sender], 0);
    assert.equal(patchData2[recipient], quantity);
  });

  it('should handle sending a patch when an address is removed from balances', async () => {
    const sender = STUB_ADDRESS;
    const recipient = ''.padEnd(43, 'a');
    const quantity = 100000000;
    const transferToSenderAddressMemory = await transfer({
      recipient: sender,
      quantity,
    });
    const transferToRecipientAddress = await handle({
      options: {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: String(quantity / 2) },
        ],
        Timestamp: STUB_TIMESTAMP,
      },
      memory: transferToSenderAddressMemory,
    });
    const patchMessage = transferToRecipientAddress.Messages.at(-1);
    const balancesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'balances',
    );
    const patchData = balancesTag.value;
    assert.equal(patchData[sender], quantity / 2);
    assert.equal(patchData[recipient], quantity / 2);

    const transferToDrainerAddress = await handle({
      options: {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: String(quantity / 2) },
        ],
        Timestamp: STUB_TIMESTAMP,
      },
      memory: transferToRecipientAddress.Memory,
    });

    const patchMessage2 = transferToDrainerAddress.Messages.at(-1);
    const balancesTag2 = patchMessage2.Tags.find(
      (tag) => tag.name === 'balances',
    );
    const patchData2 = balancesTag2.value;
    assert.equal(patchData2[sender], 0);
    assert.equal(patchData2[recipient], quantity);

    const tokenSupplyRes = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Total-Supply' }],
      },
      memory: transferToDrainerAddress.Memory,
    });

    const patchMessage3 = tokenSupplyRes.Messages.at(-1);
    const balancesTag3 = patchMessage3.Tags.find(
      (tag) => tag.name === 'balances',
    );
    const patchData3 = balancesTag3.value;
    assert.equal(patchData3[sender], 0);
  });

  it('should only send one patch message on Patch-Hyperbeam-Balances', async () => {
    const result = await handle({
      options: {
        From: PROCESS_OWNER,
        Owner: PROCESS_OWNER,
        Tags: [{ name: 'Action', value: 'Patch-Hyperbeam-Balances' }],
      },
    });
    console.dir(result, { depth: null });
    assert.equal(result.Messages.length, 2);
  });

  it('should only allow the owner to trigger Patch-Hyperbeam-Balances', async () => {
    const result = await handle({
      options: {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
        Tags: [{ name: 'Action', value: 'Patch-Hyperbeam-Balances' }],
      },
      shouldAssertNoResultError: false,
    });
    const error = result.Messages.at(-1).Tags.find(
      (tag) => tag.name === 'Error',
    ).value;
    assert(
      error.includes('Only the owner can trigger Patch-Hyperbeam-Balances'),
      'Only the owner can trigger Patch-Hyperbeam-Balances',
    );
  });

  it('should handle sending a patch when pruning a gateway returns operator stake', async () => {
    const gatewayAddress = ''.padEnd(43, 'g');
    const operatorStake = 50_000_000_000; // 50k IO
    const quantity = 100_000_000_000; // 100k IO

    // Join network with a gateway
    const { memory: joinMemory } = await joinNetwork({
      memory: sharedMemory,
      address: gatewayAddress,
      stakeQuantity: operatorStake,
      quantity,
      timestamp: STUB_TIMESTAMP,
    });

    // Leave the network to start the leaving process
    const { memory: leaveMemory } = await leaveNetwork({
      memory: joinMemory,
      address: gatewayAddress,
      timestamp: STUB_TIMESTAMP,
    });

    // Advance time past gateway end timestamp to trigger pruning
    const leaveNetworkPeriodMs = 90 * 24 * 60 * 60 * 1000;
    const futureTimestamp = STUB_TIMESTAMP + leaveNetworkPeriodMs + 1;

    // Trigger a tick to prune the gateway
    const { result: tickResult } = await tick({
      memory: leaveMemory,
      timestamp: futureTimestamp,
    });

    // Verify patch message was sent with gateway address
    const patchMessage = tickResult.Messages.find((msg) =>
      msg.Tags.some(
        (tag) => tag.name === 'device' && tag.value === 'patch@1.0',
      ),
    );
    assert(patchMessage, 'Should send a patch message');

    const balancesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'balances',
    );
    assert(balancesTag, 'Should include balances in patch');
    assert(
      balancesTag.value[gatewayAddress],
      'Should patch the gateway address',
    );
  });

  it('should handle sending a patch when pruning a balance vault', async () => {
    const vaultOwner = ''.padEnd(43, 'v');
    const vaultId = 'unique-vault-id-'.padEnd(43, 'b');
    const lockLengthMs = 14 * 24 * 60 * 60 * 1000; // 14 days
    const vaultQuantity = 10_000_000_000; // 10k IO
    const initialQuantity = 50_000_000_000; // 50k IO

    // Transfer tokens to vault owner
    const transferMemory = await transfer({
      recipient: vaultOwner,
      quantity: initialQuantity,
      memory: sharedMemory,
      timestamp: STUB_TIMESTAMP,
    });

    // Create a vault with specific ID
    const { result: createVaultResult } = await createVault({
      quantity: vaultQuantity,
      lockLengthMs,
      memory: transferMemory,
      from: vaultOwner,
      msgId: vaultId,
      timestamp: STUB_TIMESTAMP,
    });

    // Get vault data to find end timestamp
    const vaultData = await getVault({
      address: vaultOwner,
      memory: createVaultResult.Memory,
      timestamp: STUB_TIMESTAMP,
      vaultId,
    });

    // Advance time past vault end timestamp to trigger pruning
    const futureTimestamp = vaultData.endTimestamp + 1;

    // Trigger pruning with a simple action
    const { result: getInfoResult } = await getInfo({
      memory: createVaultResult.Memory,
      timestamp: futureTimestamp,
    });

    // Verify patch message was sent with vault owner address
    const patchMessage = getInfoResult.Messages.at(-1);
    assert.equal(
      patchMessage.Tags.find((tag) => tag.name === 'device')?.value,
      'patch@1.0',
      'Should send a patch message',
    );

    const balancesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'balances',
    );
    assert(balancesTag, 'Should include balances in patch');
    assert(
      balancesTag.value[vaultOwner],
      'Should patch the vault owner address',
    );
  });

  it('should handle sending a patch when pruning delegates with vaults', async () => {
    const gatewayAddress = ''.padEnd(43, 'g');
    const delegateAddress = ''.padEnd(43, 'd');
    const operatorStake = 50_000_000_000; // 50k IO
    const delegateStakeAmount = 10_000_000_000; // 10k IO

    // Set up gateway
    const { memory: joinMemory } = await joinNetwork({
      memory: sharedMemory,
      address: gatewayAddress,
      stakeQuantity: operatorStake,
      quantity: 100_000_000_000,
      timestamp: STUB_TIMESTAMP,
    });

    // Delegate stake to gateway (delegateStake helper includes the transfer)
    const { memory: delegateMemory } = await delegateStake({
      memory: joinMemory,
      delegatorAddress: delegateAddress,
      gatewayAddress,
      quantity: delegateStakeAmount,
      timestamp: STUB_TIMESTAMP,
    });

    // Decrease delegate stake to create a withdrawal vault
    const decreaseStakeResult = await handle({
      options: {
        From: delegateAddress,
        Owner: delegateAddress,
        Tags: [
          { name: 'Action', value: 'Decrease-Delegate-Stake' },
          { name: 'Address', value: gatewayAddress },
          { name: 'Quantity', value: String(delegateStakeAmount) },
        ],
        Timestamp: STUB_TIMESTAMP,
      },
      memory: delegateMemory,
    });

    // Advance time past withdrawal vault period to trigger pruning
    const withdrawalPeriodMs = 90 * 24 * 60 * 60 * 1000;
    const futureTimestamp = STUB_TIMESTAMP + withdrawalPeriodMs + 1;

    // Trigger pruning with a tick
    const { result: tickResult } = await tick({
      memory: decreaseStakeResult.Memory,
      timestamp: futureTimestamp,
    });

    // Verify patch message was sent with delegate address
    const patchMessage = tickResult.Messages.find((msg) =>
      msg.Tags.some(
        (tag) => tag.name === 'device' && tag.value === 'patch@1.0',
      ),
    );
    assert(patchMessage, 'Should send a patch message');

    const balancesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'balances',
    );
    assert(balancesTag, 'Should include balances in patch');
    assert(
      balancesTag.value[delegateAddress],
      'Should patch the delegate address',
    );
  });
});
