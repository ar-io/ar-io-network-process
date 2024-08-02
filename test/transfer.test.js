const { createAntAosLoader } = require('./utils');
const { describe, it } = require('node:test');
const assert = require('node:assert');
const {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
} = require('../tools/constants');

describe('Transfers', async () => {
  const { handle: originalHandle, memory: startMemory } =
    await createAntAosLoader();

  async function handle(options = {}, mem = startMemory) {
    return originalHandle(
      mem,
      {
        ...DEFAULT_HANDLE_OPTIONS,
        ...options,
      },
      AO_LOADER_HANDLER_ENV,
    );
  }

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
      assert.equal(balances[recipient.toLowerCase()], quantity);
      assert.equal(
        balances[sender.toLowerCase()],
        senderBalanceData - quantity,
      );
    };

    const arweave1 = ''.padEnd(43, 'a');
    const arweave2 = ''.padEnd(43, '1');
    // test with mixed case
    const eth1 = '0x'.padEnd(42, 'Aa');
    const eth2 = '0x'.padEnd(42, 'Bb');

    await checkTransfer(arweave1, arweave2, 100000000);
    await checkTransfer(eth1, arweave2, 100000000);
    await checkTransfer(eth2, eth1, 100000000);
  });

  it('should not transfer tokens to another wallet if the sender does not have enough tokens', async () => {
    const recipient = ''.padEnd(43, 'a');
    const sender = ''.padEnd(43, '1');
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

  it('should not transfer when an invalid recipient is provided', async () => {
    const recipient = ''.padEnd(44, 'z');
    const sender = ''.padEnd(43, '1');
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

  it('should not transfer when an invalid quantity is provided', async () => {
    const recipient = ''.padEnd(43, 'a');
    const sender = ''.padEnd(43, '1');
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
