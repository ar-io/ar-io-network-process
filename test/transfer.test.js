const { createAntAosLoader } = require('./utils');
const { describe, it } = require('node:test');
const assert = require('node:assert');
const {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
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
    assert.equal(balances[recipient], 100000000);
    assert.equal(balances[sender], senderBalanceData - 100000000);
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
