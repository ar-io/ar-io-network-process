const { createAntAosLoader } = require('./utils');
const { describe, it } = require('node:test');
const assert = require('node:assert');
const {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
} = require('../tools/constants');

describe('ArNS', async () => {
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
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: 'test-name' },
        { name: 'Purchase-Type', value: 'lease' },
        { name: 'Years', value: '1' },
        { name: 'Process-Id', value: ''.padEnd(43, 'a') },
      ],
    });
    const increaseUndernameResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Increase-Undername-Limit' },
          { name: 'Name', value: 'test-name' },
          { name: 'Quantity', value: '1' },
        ],
      },
      buyUndernameResult.Memory,
    );
    const result = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      increaseUndernameResult.Memory,
    );
    const record = JSON.parse(result.Messages[0].Data);
    assert.equal(record.undernameLimit, 11);
  });

  //Reference: https://ardriveio.sharepoint.com/:x:/s/AR.IOLaunch/Ec3L8aX0wuZOlG7yRtlQoJgB39wCOoKu02PE_Y4iBMyu7Q?e=ZG750l
  it('should get the costs buy record correctly', async () => {
    const result = await handle({
      Tags: [
        { name: 'Action', value: 'Token-Cost' },
        { name: 'Intent', value: 'Buy-Record' },
        { name: 'Name', value: 'test-name' },
        { name: 'Purchase-Type', value: 'lease' },
        { name: 'Years', value: '1' },
        { name: 'Process-Id', value: ''.padEnd(43, 'a') },
      ],
    });
    const tokenCost = JSON.parse(result.Messages[0].Data);
    assert.equal(tokenCost, 600000000);
  });

  it('should get the costs increase undername correctly', async () => {
    const buyUndernameResult = await handle({
      Tags: [
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: 'test-name' },
        { name: 'Purchase-Type', value: 'lease' },
        { name: 'Years', value: '1' },
        { name: 'Process-Id', value: ''.padEnd(43, 'a') },
      ],
    });
    const result = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Token-Cost' },
          { name: 'Intent', value: 'Increase-Undername-Limit' },
          { name: 'Name', value: 'test-name' },
          { name: 'Quantity', value: '1' },
        ],
      },
      buyUndernameResult.Memory,
    );
    const tokenCost = JSON.parse(result.Messages[0].Data);
    const expectedPrice = 500000000 * 0.001 * 1 * 1;
    assert.equal(tokenCost, expectedPrice);
  });

  it('should get the cost of increasing a lease correctly', async () => {
    const buyUndernameResult = await handle({
      Tags: [
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: 'test-name' },
        { name: 'Purchase-Type', value: 'lease' },
        { name: 'Years', value: '1' },
        { name: 'Process-Id', value: ''.padEnd(43, 'a') },
      ],
    });
    const recordResultBefore = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      buyUndernameResult.Memory,
    );
    const recordBefore = JSON.parse(recordResultBefore.Messages[0].Data);
    const extendResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Extend-Lease' },
          { name: 'Name', value: 'test-name' },
          { name: 'Years', value: '1' },
        ],
      },
      buyUndernameResult.Memory,
    );
    const recordResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      extendResult.Memory,
    );
    const record = JSON.parse(recordResult.Messages[0].Data);
    assert.equal(
      record.endTimestamp,
      recordBefore.endTimestamp + 60 * 1000 * 60 * 24 * 365,
    );
  });

  // TODO: add several error scenarios
});
