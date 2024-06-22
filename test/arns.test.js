const { createAntAosLoader } = require('./utils');
const { describe, it } = require('node:test');
const assert = require('node:assert');
const {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
} = require('../tools/constants');

describe('aos ARNS', async () => {
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

  it('should increase the undernames', async () => {
    const buyUndernameResult = await handle({
      Tags: [
        { name: 'Action', value: 'BuyRecord' },
        { name: 'Name', value: 'timmy' },
        { name: 'PurchaseType', value: 'lease' },
        { name: 'Years', value: '1' },
        { name: 'ProcessId', value: ''.padEnd(43, 'a') },
      ],
    });
    const increaseUndernameResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'IncreaseUndernameLimit' },
          { name: 'Name', value: 'timmy' },
          { name: 'Quantity', value: '1' },
        ],
      },
      buyUndernameResult.Memory,
    );

    const recordsResult = await handle(
      {
        Tags: [{ name: 'Action', value: 'Records' }],
      },
      increaseUndernameResult.Memory,
    );
    const arnsRecords = JSON.parse(recordsResult.Messages[0].Data);
    assert.equal(Object.keys(arnsRecords).includes('timmy'), true);
    //console.dir(recordResult, { depth: null });
    assert.equal(arnsRecords['timmy'].undernameLimit, 11);
  });
});
