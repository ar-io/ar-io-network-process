import { handle, startMemory } from './helpers.mjs';
import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert';
import {
  STUB_ADDRESS,
  PROCESS_OWNER,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';
import { assertNoInvariants } from './invariants.mjs';

const makeCSV = (entries) => entries.map(([addr, qty]) => `${addr},${qty}`).join('\n');

describe('Transfers', async () => {
  let endingMemory;
  afterEach(() => {
    assertNoInvariants({ memory: endingMemory, timestamp: STUB_TIMESTAMP });
  });

  it('should transfer tokens to another wallet', async () => {
    const checkTransfer = async (recipient, sender, quantity) => {
      let mem = startMemory;

      if (sender != STUB_ADDRESS) {
        const transferResult = await handle({
          options: {
            Tags: [
              { name: 'Action', value: 'Transfer' },
              { name: 'Recipient', value: sender },
              { name: 'Quantity', value: quantity },
              { name: 'Cast', value: true },
            ],
          },
        });
        mem = transferResult.Memory;
      }

      const senderBalance = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Balance' },
            { name: 'Target', value: sender },
          ],
        },
        memory: mem,
      });
      const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);

      const transferResult = await handle({
        options: {
          From: sender,
          Owner: sender,
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: recipient },
            { name: 'Quantity', value: quantity }, // 100 ARIO
            { name: 'Cast', value: true },
          ],
        },
        memory: mem,
      });

      // get balances
      const result = await handle({
        options: {
          From: sender,
          Owner: sender,
          Tags: [{ name: 'Action', value: 'Balances' }],
        },
        memory: transferResult.Memory,
      });
      const balances = JSON.parse(result.Messages[0].Data);
      assert.equal(balances[recipient], quantity);
      assert.equal(balances[sender], senderBalanceData - quantity);
      return result.Memory;
    };

    const arweave1 = STUB_ADDRESS;
    const arweave2 = ''.padEnd(43, 'a');
    // EIP55 checksummed addresses
    const eth1 = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa';
    const eth2 = '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB';

    await checkTransfer(arweave1, arweave2, 100000000);
    await checkTransfer(eth1, arweave2, 100000000);
    endingMemory = await checkTransfer(eth2, eth1, 100000000);
  });

  it('should not transfer tokens to another wallet if the sender does not have enough tokens', async () => {
    const recipient = STUB_ADDRESS;
    const sender = PROCESS_OWNER;
    const senderBalance = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Address', value: sender },
        ],
      },
    });
    const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
    const transferResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: senderBalanceData + 1 },
          { name: 'Cast', value: true },
        ],
      },

      shouldAssertNoResultError: false,
    });
    // get balances
    const result = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory: transferResult.Memory,
    });
    const balances = JSON.parse(result.Messages[0].Data);
    // the new balance won't be defined
    assert.equal(balances[recipient] || 0, 0);
    assert.equal(balances[sender], senderBalanceData);
    endingMemory = result.Memory;
  });

  for (const allowUnsafeAddresses of [false, undefined]) {
    it(`should not transfer when an invalid address is provided and \`Allow-Unsafe-Addresses\` is ${allowUnsafeAddresses}`, async () => {
      const recipient = 'invalid-address';
      const sender = PROCESS_OWNER;
      const senderBalance = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Balance' },
            { name: 'Target', value: sender },
          ],
        },
      });
      const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
      const transferResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: recipient },
            { name: 'Quantity', value: 100000000 }, // 100 ARIO
            { name: 'Cast', value: true },
            { name: 'Allow-Unsafe-Addresses', value: allowUnsafeAddresses },
          ],
        },

        shouldAssertNoResultError: false,
      });

      // assert the error tag
      const errorTag = transferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.ok(errorTag, 'Error tag should be present');

      const result = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balances' }],
        },
        memory: transferResult.Memory,
      });
      const balances = JSON.parse(result.Messages[0].Data);
      assert.equal(balances[recipient] || 0, 0);
      assert.equal(balances[sender], senderBalanceData);
      endingMemory = result.Memory;
    });
  }

  /**
   * We allow transfers to addresses that may appear invalid if the `Allow-Unsafe-Addresses` tag is true for several reasons:
   * 1. To support future address formats and signature schemes that may emerge
   * 2. To maintain compatibility with new blockchain networks that could be integrated
   * 3. To avoid breaking changes if address validation rules need to be updated
   * 4. To give users flexibility in how they structure their addresses
   * 5. To reduce protocol-level restrictions that could limit innovation
   */
  it('should transfer when an invalid address is provided and `Allow-Unsafe-Addresses` is true', async () => {
    const recipient = 'invalid-address';
    const sender = PROCESS_OWNER;
    const senderBalance = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: sender },
        ],
      },
    });
    const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
    const transferResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: 100000000 }, // 100 ARIO
          { name: 'Cast', value: true },
          { name: 'Allow-Unsafe-Addresses', value: true },
        ],
      },
    });

    // get balances
    const result = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory: transferResult.Memory,
    });
    const balances = JSON.parse(result.Messages[0].Data);
    assert.equal(balances[recipient] || 0, 100000000);
    assert.equal(balances[sender], senderBalanceData - 100000000);
    endingMemory = result.Memory;
  });

  it('should not transfer when an invalid quantity is provided', async () => {
    const recipient = STUB_ADDRESS;
    const sender = PROCESS_OWNER;
    const senderBalance = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: sender },
        ],
      },
    });
    const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
    const transferResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: 100000000.1 },
          { name: 'Cast', value: true },
        ],
      },
      shouldAssertNoResultError: false,
    });

    // get balances
    const result = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory: transferResult.Memory,
    });
    const balances = JSON.parse(result.Messages[0].Data);
    assert.equal(balances[recipient] || 0, 0);
    assert.equal(balances[sender], senderBalanceData);
    endingMemory = result.Memory;
  });
});

describe('Batch Transfers', async () => {
  let endingMemory;
  afterEach(() => {
    assertNoInvariants({ memory: endingMemory, timestamp: STUB_TIMESTAMP });
  });

  it('should perform a batch transfer to multiple wallets', async () => {
    let mem = startMemory;
    const sender = ''.padEnd(43, 'a'); // Arweave-style
    const recipients = [
      [''.padEnd(43, 'b'), 100], // Arweave-style
      ['0xB0bBbbbbBbBBBBbBbBbBBBBbbBBBbbbbBbBbBBBBb', 500], // Valid ETH address
    ];

    // Prefund the sender (must be From: PROCESS_OWNER or STUB_ADDRESS, not the sender itself)
    const prefund = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: sender },
          { name: 'Quantity', value: 2000 },
        ],
      },
      memory: mem,
    });

    const balancesResponse1 = await handle({
      options: { Tags: [{ name: 'Action', value: 'Balances' }] },
      memory: prefund.Memory,
    });
    const balances1 = JSON.parse(balancesResponse1.Messages[0].Data);
    console.log ("BALANCES!!!", balances1)
    console.log ("RECIPIENTS!!", makeCSV(recipients))

    // Step 2: Perform batch transfer
    const batchTransfer = await handle({
      options: {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Batch-Transfer' },
        ],
        Data: makeCSV(recipients),
      },
      memory: prefund.Memory,
    });
    console.log ("BATCH TRANSFER RESPONSE!!!", batchTransfer.Messages[0].Data)

    const balancesResponse = await handle({
      options: { Tags: [{ name: 'Action', value: 'Balances' }] },
      memory: batchTransfer.Memory,
    });
    const balances = JSON.parse(balancesResponse.Messages[0].Data);
    console.log ("UPDATED BALANCES!!!", balances)

    assert.equal(balances[recipients[0][0]], recipients[0][1]);
    assert.equal(balances[recipients[1][0]], recipients[1][1]);
    assert.equal(balances[sender], 2000 - recipients[0][1] - recipients[1][1]);

    endingMemory = balancesResponse.Memory;
  });

  it('should fail on invalid address if unsafe addresses not allowed', async () => {
    const sender = PROCESS_OWNER;
    const invalidRecipient = 'invalid-wallet-address';

    const response = await handle({
      options: {
        From: sender,
        Tags: [
          { name: 'Action', value: 'Batch-Transfer' },
          { name: 'Allow-Unsafe-Addresses', value: false },
        ],
        Data: makeCSV([[invalidRecipient, 100]]),
      },
      shouldAssertNoResultError: false,
    });

    const errorTag = response.Messages?.[0]?.Tags?.find(t => t.name === 'Error');
    assert.ok(errorTag);
    endingMemory = response.Memory;
  });

  it('should succeed with unsafe address if explicitly allowed', async () => {
    const sender = PROCESS_OWNER;
    const unsafeRecipient = 'unsafe-address';

    const memory = await handle({
      options: {
        From: STUB_ADDRESS,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: sender },
          { name: 'Quantity', value: 500000 },
          { name: 'Cast', value: true },
        ],
      },
    });    

    const batchResult = await handle({
      options: {
        From: sender,
        Tags: [
          { name: 'Action', value: 'Batch-Transfer' },
          { name: 'Allow-Unsafe-Addresses', value: true },
        ],
        Data: makeCSV([[unsafeRecipient, 500000]]),
      },
      memory: memory.Memory,
    });

    const balancesResponse = await handle({
      options: { Tags: [{ name: 'Action', value: 'Balances' }] },
      memory: batchResult.Memory,
    });
    const balances = JSON.parse(balancesResponse.Messages[0].Data);
    assert.equal(balances[unsafeRecipient], 500000);
    endingMemory = balancesResponse.Memory;
  });

  it('should fail if sender balance is insufficient', async () => {
    const sender = PROCESS_OWNER;
    const recipient = ''.padEnd(43, 'Z');
  
    // Get initial sender balance
    const senderBalanceResp = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: sender },
        ],
      },
    });
    const senderBalanceData = JSON.parse(senderBalanceResp.Messages[0].Data);
  
    // Attempt to transfer more than balance
    const batch = await handle({
      options: {
        From: sender,
        Tags: [{ name: 'Action', value: 'Batch-Transfer' }],
        Data: makeCSV([[recipient, senderBalanceData + 1]]),
      },
      shouldAssertNoResultError: false,
      memory: senderBalanceResp.Memory,
    });
  
    // Confirm error
    assert.ok(batch.Messages?.length, 'No messages returned from handler');
    const errorTag = batch.Messages[0].Tags?.find(t => t.name === 'Error');
    assert.ok(errorTag, 'Expected an Error tag on the response message');
    assert.match(errorTag.value, /Insufficient balance/i);
  
    // Confirm balances unchanged
    const result = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory: batch.Memory,
    });
    const balances = JSON.parse(result.Messages[0].Data);
    assert.equal(balances[recipient] || 0, 0);
    assert.equal(balances[sender], senderBalanceData);
  
    endingMemory = result.Memory;
  });
});
