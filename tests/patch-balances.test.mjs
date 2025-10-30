/**
 * Do a transfer from one address to a new one to ensure hb patches the new address
 * Do a transfer that transfers all the tokens to a different address to ensure hb patches a 0 amount on the old address
 *   After that, do a computeTotalSupply call to ensure that hb patches the empty (nil) address afterwards as 0
 */

import { handle, transfer } from './helpers.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  PROCESS_OWNER,
  STUB_ADDRESS,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';

describe('hyperbeam patch balances', async () => {
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
});
