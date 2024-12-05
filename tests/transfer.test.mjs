import { handle, startMemory } from './helpers.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { STUB_ADDRESS, PROCESS_OWNER } from '../tools/constants.mjs';

describe('Transfers', async () => {
  it('should transfer tokens to another wallet', async () => {
    const checkTransfer = async (recipient, sender, quantity) => {
      let mem = startMemory;

      if (sender != STUB_ADDRESS) {
        const transferResult = await handle({
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: sender },
            { name: 'Quantity', value: quantity }, // 100 IO
            { name: 'Cast', value: true },
          ],
        });
        mem = transferResult.Memory;
      }

      const senderBalance = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Balance' },
            { name: 'Target', value: sender },
          ],
        },
        mem,
      );
      const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);

      const transferResult = await handle(
        {
          From: sender,
          Owner: sender,
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: recipient },
            { name: 'Quantity', value: quantity }, // 100 IO
            { name: 'Cast', value: true },
          ],
        },
        mem,
      );

      // get balances
      const result = await handle(
        {
          From: sender,
          Owner: sender,
          Tags: [{ name: 'Action', value: 'Balances' }],
        },
        transferResult.Memory,
      );
      const balances = JSON.parse(result.Messages[0].Data);
      assert.equal(balances[recipient], quantity);
      assert.equal(balances[sender], senderBalanceData - quantity);
    };

    const arweave1 = STUB_ADDRESS;
    const arweave2 = ''.padEnd(43, 'a');
    // EIP55 checksummed addresses
    const eth1 = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa';
    const eth2 = '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB';

    await checkTransfer(arweave1, arweave2, 100000000);
    await checkTransfer(eth1, arweave2, 100000000);
    await checkTransfer(eth2, eth1, 100000000);
  });

  it('should not transfer tokens to another wallet if the sender does not have enough tokens', async () => {
    const recipient = STUB_ADDRESS;
    const sender = PROCESS_OWNER;
    const senderBalance = await handle({
      Tags: [
        { name: 'Action', value: 'Balance' },
        { name: 'Address', value: sender },
      ],
    });
    const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
    const transferResult = await handle({
      Tags: [
        { name: 'Action', value: 'Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: senderBalanceData + 1 },
        { name: 'Cast', value: true },
      ],
    });
    // get balances
    const result = await handle(
      {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      transferResult.Memory,
    );
    const balances = JSON.parse(result.Messages[0].Data);
    // the new balance won't be defined
    assert.equal(balances[recipient] || 0, 0);
    assert.equal(balances[sender], senderBalanceData);
  });

  for (const allowUnsafeAddresses of [false, undefined]) {
    it(`should not transfer when an invalid address is provided and \`Allow-Unsafe-Addresses\` is ${allowUnsafeAddresses}`, async () => {
      const recipient = 'invalid-address';
      const sender = PROCESS_OWNER;
      const senderBalance = await handle({
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: sender },
        ],
      });
      const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
      const transferResult = await handle({
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: 100000000 }, // 100 IO
          { name: 'Cast', value: true },
          { name: 'Allow-Unsafe-Addresses', value: allowUnsafeAddresses },
        ],
      });

      // assert the error tag
      const errorTag = transferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.ok(errorTag, 'Error tag should be present');

      const result = await handle(
        {
          Tags: [{ name: 'Action', value: 'Balances' }],
        },
        transferResult.Memory,
      );
      const balances = JSON.parse(result.Messages[0].Data);
      assert.equal(balances[recipient] || 0, 0);
      assert.equal(balances[sender], senderBalanceData);
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
      Tags: [
        { name: 'Action', value: 'Balance' },
        { name: 'Target', value: sender },
      ],
    });
    const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
    const transferResult = await handle({
      Tags: [
        { name: 'Action', value: 'Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: 100000000 }, // 100 IO
        { name: 'Cast', value: true },
        { name: 'Allow-Unsafe-Addresses', value: true },
      ],
    });

    // get balances
    const result = await handle(
      {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      transferResult.Memory,
    );
    const balances = JSON.parse(result.Messages[0].Data);
    assert.equal(balances[recipient] || 0, 100000000);
    assert.equal(balances[sender], senderBalanceData - 100000000);
  });

  it('should not transfer when an invalid quantity is provided', async () => {
    const recipient = STUB_ADDRESS;
    const sender = PROCESS_OWNER;
    const senderBalance = await handle({
      Tags: [
        { name: 'Action', value: 'Balance' },
        { name: 'Target', value: sender },
      ],
    });
    const senderBalanceData = JSON.parse(senderBalance.Messages[0].Data);
    const transferResult = await handle({
      Tags: [
        { name: 'Action', value: 'Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: 100000000.1 },
        { name: 'Cast', value: true },
      ],
    });
    // get balances
    const result = await handle(
      {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      transferResult.Memory,
    );
    const balances = JSON.parse(result.Messages[0].Data);
    assert.equal(balances[recipient] || 0, 0);
    assert.equal(balances[sender], senderBalanceData);
  });
});
