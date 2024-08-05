const { createAntAosLoader } = require('./utils');
const { describe, it } = require('node:test');
const assert = require('node:assert');
const {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
} = require('../tools/constants');

// EIP55-formatted test address
const testEthAddress = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa';
const testEthAddress2 = '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB';

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

  it('should get token info', async () => {
    const result = await handle({
      Tags: [{ name: 'Action', value: 'Info' }],
    });
    const tokenInfo = JSON.parse(result.Messages[0].Data);
    assert(tokenInfo);
  });

  it('should buy a record', async () => {
    const runBuyRecord = async (sender) => {
      let mem = startMemory;
      if (sender != STUB_ADDRESS) {
        const transferResult = await handle({
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: sender },
            { name: 'Quantity', value: 600000000 },
            { name: 'Cast', value: true },
          ],
        });
        mem = transferResult.Memory;
      }

      const buyRecordResult = await handle(
        {
          From: sender,
          Owner: sender,
          Tags: [
            { name: 'Action', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
          ],
        },
        mem,
      );

      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);

      // fetch the record
      const realRecord = await handle(
        {
          From: sender,
          Owner: sender,
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        buyRecordResult.Memory,
      );

      const record = JSON.parse(realRecord.Messages[0].Data);
      assert.deepEqual(record, {
        processId: ''.padEnd(43, 'a'),
        purchasePrice: 600000000,
        startTimestamp: buyRecordData.startTimestamp,
        endTimestamp: buyRecordData.endTimestamp,
        type: 'lease',
        undernameLimit: 10,
      });
    };
    await runBuyRecord(STUB_ADDRESS);
    await runBuyRecord(testEthAddress);
  });

  it('should fail to buy a permanently registered record', async () => {
    const buyRecordResult = await handle({
      Tags: [
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: 'test-name' },
        { name: 'Purchase-Type', value: 'permabuy' },
        { name: 'Process-Id', value: ''.padEnd(43, 'a') },
      ],
    });
    const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);

    // fetch the record
    const realRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      buyRecordResult.Memory,
    );

    const record = JSON.parse(realRecord.Messages[0].Data);
    assert.deepEqual(record, {
      processId: ''.padEnd(43, 'a'),
      purchasePrice: 2500000000,
      startTimestamp: buyRecordData.startTimestamp,
      type: 'permabuy',
      undernameLimit: 10,
    });

    const failedBuyRecordResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      },
      buyRecordResult.Memory,
    );

    const failedBuyRecordError = failedBuyRecordResult.Messages[0].Tags.find(
      (t) => t.name === 'Error',
    );

    assert.equal(failedBuyRecordError?.value, 'Invalid-Buy-Record');
    const alreadyRegistered = failedBuyRecordResult.Messages[0].Data.includes(
      'Name is already registered',
    );
    assert(alreadyRegistered);
  });

  it('should buy a record and default the name to lower case', async () => {
    const buyRecordResult = await handle({
      Tags: [
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: 'Test-NAme' },
        { name: 'Purchase-Type', value: 'lease' },
        { name: 'Years', value: '1' },
        { name: 'Process-Id', value: ''.padEnd(43, 'a') },
      ],
    });

    const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);

    // fetch the record
    const realRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      buyRecordResult.Memory,
    );

    const record = JSON.parse(realRecord.Messages[0].Data);
    assert.deepEqual(record, {
      processId: ''.padEnd(43, 'a'),
      purchasePrice: 600000000,
      startTimestamp: buyRecordData.startTimestamp,
      endTimestamp: buyRecordData.endTimestamp,
      type: 'lease',
      undernameLimit: 10,
    });
  });

  it('should increase the undernames', async () => {
    const runIncreaseUndername = async (sender) => {
      let mem = startMemory;

      if (sender != STUB_ADDRESS) {
        const transferResult = await handle({
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: sender },
            { name: 'Quantity', value: 6000000000 },
            { name: 'Cast', value: true },
          ],
        });
        mem = transferResult.Memory;
      }

      const buyUndernameResult = await handle(
        {
          From: sender,
          Owner: sender,
          Tags: [
            { name: 'Action', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
          ],
        },
        mem,
      );

      const increaseUndernameResult = await handle(
        {
          From: sender,
          Owner: sender,
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
          From: sender,
          Owner: sender,
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        increaseUndernameResult.Memory,
      );
      const record = JSON.parse(result.Messages[0].Data);
      assert.equal(record.undernameLimit, 11);
    };
    await runIncreaseUndername(STUB_ADDRESS);
    await runIncreaseUndername(testEthAddress);
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
