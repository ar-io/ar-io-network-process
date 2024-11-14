import { assertNoResultError } from './utils.mjs';
import { describe, it, before } from 'node:test';
import {
  handle,
  startMemory,
  transfer,
  joinNetwork,
  setUpStake,
  baseLeasePrice,
  basePermabuyPrice,
  getBalance,
} from './helpers.mjs';
import assert from 'node:assert';
import {
  PROCESS_ID,
  PROCESS_OWNER,
  STUB_ADDRESS,
  INITIAL_PROTOCOL_BALANCE,
  STUB_MESSAGE_ID,
  STUB_OPERATOR_ADDRESS,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';

// EIP55-formatted test address
const testEthAddress = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa';

describe('ArNS', async () => {
  const runBuyRecord = async ({
    sender = STUB_ADDRESS,
    processId = ''.padEnd(43, 'a'),
    transferQty = 1_000_000_000_000,
    name = 'test-name',
    type = 'lease',
    memory,
  }) => {
    if (sender != PROCESS_OWNER) {
      // transfer from the owner to the sender
      memory = await transfer({
        recipient: sender,
        quantity: transferQty,
        cast: true,
      });
    }

    const buyRecordResult = await handle(
      {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: name },
          { name: 'Purchase-Type', value: type },
          { name: 'Process-Id', value: processId },
          { name: 'Years', value: '1' },
        ],
      },
      memory,
    );

    const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);
    const buyRecordEvent = JSON.parse(
      buyRecordResult.Output.data.split('\n')[1],
    );

    const expectedRemainingBalance = {
      '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa': 0,
      [PROCESS_OWNER]: 950000000000000 - transferQty,
      [PROCESS_ID]: 50_000_000_000_000 + buyRecordData.purchasePrice,
      [sender]: transferQty - buyRecordData.purchasePrice,
    };
    const expectedEvent = {
      _e: 1,
      Timestamp: STUB_TIMESTAMP,
      'Start-Timestamp': STUB_TIMESTAMP,
      ...(type == 'lease' && { 'End-Timestamp': STUB_TIMESTAMP + 31536000000 }), // 1 year in ms
      'Purchase-Type': type,
      Years: '1', // Note: this added because we are sending the tag, but not relevant for permabuys
      'Undername-Limit': 10,
      'Purchase-Price': buyRecordData.purchasePrice,
      'DF-Purchases-This-Period': 1,
      'DF-Revenue-This-Period': buyRecordData.purchasePrice,
      'DF-Current-Demand-Factor': 1,
      Action: 'Buy-Record',
      'Name-Length': 9,
      'Base-Registration-Fee': 500000000,
      'DF-Current-Period': 1,
      'DF-Trailing-Period-Revenues': [0, 0, 0, 0, 0, 0],
      'DF-Trailing-Period-Purchases': [0, 0, 0, 0, 0, 0, 0],
      Cron: false,
      Cast: false,
      Name: name,
      'DF-Consecutive-Periods-With-Min-Demand-Factor': 0,
      'Process-Id': processId,
      From: sender,
      'From-Formatted': sender,
      'Message-Id': STUB_MESSAGE_ID,
      'Records-Count': 1,
      'Protocol-Balance': expectedRemainingBalance[PROCESS_ID],
      'Reserved-Records-Count': 0,
      'Remaining-Balance': expectedRemainingBalance[sender],
      'Circulating-Supply': -buyRecordData.purchasePrice, // Artifact of starting out without initializing this properly
      'Total-Token-Supply': 50000000000000, // Artifact of starting out without initializing this properly
      'Staked-Supply': 0, // Artifact of starting out without initializing this properly
      'Delegated-Supply': 0, // Artifact of starting out without initializing this properly
      'Withdraw-Supply': 0, // Artifact of starting out without initializing this properly
      'Locked-Supply': 0, // Artifact of starting out without initializing this properly
    };
    // TODO: ASSERT THE EVENT DATA

    // fetch the record
    const realRecord = await handle(
      {
        From: sender,
        Owner: sender,
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: name },
        ],
      },
      buyRecordResult.Memory,
    );

    const record = JSON.parse(realRecord.Messages[0].Data);
    assert.deepEqual(record, {
      processId: processId,
      purchasePrice: buyRecordData.purchasePrice,
      startTimestamp: buyRecordData.startTimestamp,
      type: type,
      undernameLimit: 10,
      ...(type == 'lease' && { endTimestamp: buyRecordData.endTimestamp }),
    });

    return {
      record,
      memory: buyRecordResult.Memory,
    };
  };

  describe('Buy-Record', () => {
    it('should buy a record with an Arweave address', async () => {
      await runBuyRecord({ sender: STUB_ADDRESS });
    });

    it('should buy a record with an Ethereum address', async () => {
      await runBuyRecord({ sender: testEthAddress });
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
        purchasePrice: basePermabuyPrice,
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
        purchasePrice: baseLeasePrice,
        startTimestamp: buyRecordData.startTimestamp,
        endTimestamp: buyRecordData.endTimestamp,
        type: 'lease',
        undernameLimit: 10,
      });
    });
  });

  describe('Increase-Undername-Limit', () => {
    it('should increase the undernames by spending from balance', async () => {
      const assertIncreaseUndername = async (sender) => {
        let memory = startMemory;

        if (sender != PROCESS_OWNER) {
          const transferResult = await handle({
            From: PROCESS_OWNER,
            Owner: PROCESS_OWNER,
            Tags: [
              { name: 'Action', value: 'Transfer' },
              { name: 'Recipient', value: sender },
              { name: 'Quantity', value: 6000000000 },
              { name: 'Cast', value: true },
            ],
          });
          memory = transferResult.Memory;
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
          memory,
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
      await assertIncreaseUndername(STUB_ADDRESS);
      await assertIncreaseUndername(testEthAddress);
    });

    it('should increase the undernames by spending from stakes', async () => {
      const assertIncreaseUndername = async (sender) => {
        let memory = startMemory;

        if (sender != PROCESS_OWNER) {
          // Send enough money to the user to delegate stake, buy record, and increase undername limit
          memory = await transfer({
            recipient: sender,
            quantity: 650000000,
            memory,
            cast: true,
          });

          // Stake a gateway for the user to delegate to
          const joinNetworkResult = await joinNetwork({
            memory,
            address: STUB_OPERATOR_ADDRESS,
          });
          memory = joinNetworkResult.memory;

          const stakeResult = await handle(
            {
              From: sender,
              Owner: sender,
              Tags: [
                { name: 'Action', value: 'Delegate-Stake' },
                { name: 'Quantity', value: `${650000000}` }, // delegate all of their balance
                { name: 'Address', value: STUB_OPERATOR_ADDRESS }, // our gateway address
              ],
              Timestamp: STUB_TIMESTAMP + 1,
            },
            memory,
          );
          memory = stakeResult.Memory;
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
              { name: 'Fund-From', value: 'stakes' },
            ],
          },
          memory,
        );
        memory = buyUndernameResult.Memory;

        const increaseUndernameResult = await handle(
          {
            From: sender,
            Owner: sender,
            Tags: [
              { name: 'Action', value: 'Increase-Undername-Limit' },
              { name: 'Name', value: 'test-name' },
              { name: 'Quantity', value: '1' },
              { name: 'Fund-From', value: 'stakes' },
            ],
          },
          memory,
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
      await assertIncreaseUndername(STUB_ADDRESS);
      await assertIncreaseUndername(testEthAddress);
    });
  });

  describe('Get-Registration-Fees', () => {
    it('should return the base registration fees for each name length', async () => {
      const priceListResult = await handle({
        Tags: [{ name: 'Action', value: 'Get-Registration-Fees' }],
      });

      const priceList = JSON.parse(priceListResult.Messages[0].Data);
      // check that each key has lease with years and permabuy prices
      assert(Object.keys(priceList).length == 51);
      Object.keys(priceList).forEach((key) => {
        assert(priceList[key].lease);
        assert(priceList[key].permabuy);
        assert(Object.keys(priceList[key].lease).length == 5);
      });
    });
  });

  describe('Token-Cost', () => {
    //Reference: https://ardriveio.sharepoint.com/:x:/s/AR.IOLaunch/Ec3L8aX0wuZOlG7yRtlQoJgB39wCOoKu02PE_Y4iBMyu7Q?e=ZG750l
    it('should return the correct cost of buying a name as a lease', async () => {
      // the name will cost 600_000_000, so we'll want to see a shortfall of 200_000_000 in the funding plan
      const transferMemory = await transfer({
        recipient: STUB_ADDRESS,
        quantity: 400_000_000,
        cast: true,
      });

      const result = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Get-Cost-Details-For-Action' },
            { name: 'Intent', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
            { name: 'Fund-From', value: 'balance' },
          ],
        },
        transferMemory,
      );

      const tokenCostResult = JSON.parse(result.Messages[0].Data);
      assert.deepEqual(tokenCostResult, {
        discounts: [],
        tokenCost: baseLeasePrice,
        fundingPlan: {
          address: STUB_ADDRESS,
          balance: 400_000_000,
          shortfall: 200_000_000,
          stakes: [],
        },
      });
    });

    it('should return the correct cost of increasing an undername limit', async () => {
      const buyRecordResult = await handle({
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      });

      // assert no error tag
      const buyRecordErrorTag = buyRecordResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(buyRecordErrorTag, undefined);

      const result = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Increase-Undername-Limit' },
            { name: 'Name', value: 'test-name' },
            { name: 'Quantity', value: '1' },
          ],
        },
        buyRecordResult.Memory,
      );
      const tokenCost = JSON.parse(result.Messages[0].Data);
      const expectedPrice = 500000000 * 0.001 * 1 * 1;
      assert.equal(tokenCost, expectedPrice);
    });

    it('should return the correct cost of extending an existing leased record', async () => {
      const buyRecordResult = await handle({
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      });

      // assert no error tag
      const buyRecordErrorTag = buyRecordResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(buyRecordErrorTag, undefined);

      const result = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Extend-Lease' },
            { name: 'Name', value: 'test-name' },
            { name: 'Years', value: '2' },
          ],
        },
        buyRecordResult.Memory,
      );
      const tokenCost = JSON.parse(result.Messages[0].Data);
      assert.equal(tokenCost, 200000000); // known cost for extending a 9 character name by 2 years (500 IO * 0.2 * 2)
    });

    it('should get the cost of upgrading an existing leased record to permanently owned', async () => {
      const buyRecordResult = await handle({
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      });

      // assert no error tag
      const buyRecordErrorTag = buyRecordResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(buyRecordErrorTag, undefined);

      const upgradeNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Upgrade-Name' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        buyRecordResult.Memory,
      );

      const tokenCost = JSON.parse(upgradeNameResult.Messages[0].Data);
      assert.equal(tokenCost, basePermabuyPrice);
    });
  });

  describe('Extend-Lease', () => {
    it('should properly handle extending a leased record', async () => {
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

    it('should properly handle extending a leased record paying with balance and stakes', async () => {
      let memory = startMemory;
      const stakeResult = await setUpStake({
        memory,
        transferQty: 700000000, // 600000000 for name purchase + 100000000 for extending the lease
        stakeQty: 650000000, // delegate most of their balance so that name purchase uses balance and stakes
      });

      memory = stakeResult.memory;

      const buyRecordResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
            { name: 'Fund-From', value: 'any' },
          ],
        },
        memory,
      );
      memory = buyRecordResult.Memory;

      const recordResultBefore = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        buyRecordResult.Memory,
      );
      const recordBefore = JSON.parse(recordResultBefore.Messages[0].Data);

      // Last 100,000,000 mIO will be paid from exit vault 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm'
      const extendResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Extend-Lease' },
            { name: 'Name', value: 'test-name' },
            { name: 'Years', value: '1' },
            { name: 'Fund-From', value: 'any' },
          ],
        },
        buyRecordResult.Memory,
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
        recordBefore.endTimestamp + 60 * 1000 * 60 * 24 * 365,
        record.endTimestamp,
      );
    });
  });

  describe('Upgrade-Name', () => {
    it('should properly handle upgrading a name', async () => {
      const buyRecordTimestamp = STUB_TIMESTAMP + 1;
      const buyRecordResult = await handle({
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
        Timestamp: buyRecordTimestamp,
      });

      // assert no error tag
      const buyRecordErrorTag = buyRecordResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(buyRecordErrorTag, undefined);

      // now upgrade the name
      const upgradeNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Upgrade-Name' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: buyRecordTimestamp + 1,
        },
        buyRecordResult.Memory,
      );

      // assert no error tag
      const upgradeNameErrorTag = upgradeNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(upgradeNameErrorTag, undefined);

      // assert the message includes the upgrade name notice
      const upgradeNameNoticeTag = upgradeNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Upgrade-Name-Notice',
      );

      assert.ok(upgradeNameNoticeTag);

      const upgradedNameData = JSON.parse(
        upgradeNameResult.Messages?.[0]?.Data,
      );
      assert.deepStrictEqual(upgradedNameData, {
        name: 'test-name',
        type: 'permabuy',
        startTimestamp: buyRecordTimestamp,
        processId: ''.padEnd(43, 'a'),
        undernameLimit: 10,
        purchasePrice: basePermabuyPrice, // expected price for a permanent 9 character name
      });
    });

    it('should properly handle upgrading a name paying with balance and stakes', async () => {
      let memory = startMemory;
      const stakeResult = await setUpStake({
        memory,
        transferQty: 3_100_000_000, // 60,000,0000 for name purchase + 2,500,000,000 for upgrading the name
        stakeQty: 3_100_000_000 - 50_000_000, // delegate most of their balance so that name purchase uses balance and stakes
        stakerAddress: STUB_ADDRESS,
      });
      memory = stakeResult.memory;

      const buyRecordTimestamp = STUB_TIMESTAMP + 1;
      const buyRecordResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
            { name: 'Fund-From', value: 'any' },
          ],
          Timestamp: buyRecordTimestamp,
        },
        memory,
      );
      assertNoResultError(buyRecordResult);

      // now upgrade the name
      const upgradeNameResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Upgrade-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Fund-From', value: 'stakes' },
          ],
          Timestamp: buyRecordTimestamp + 1,
        },
        buyRecordResult.Memory,
      );
      assertNoResultError(upgradeNameResult);

      // assert the message includes the upgrade name notice
      const upgradeNameNoticeTag = upgradeNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Upgrade-Name-Notice',
      );

      assert.ok(upgradeNameNoticeTag);

      const upgradedNameData = JSON.parse(
        upgradeNameResult.Messages?.[0]?.Data,
      );
      assert.deepStrictEqual(
        {
          name: upgradedNameData.name,
          type: upgradedNameData.record.type,
          startTimestamp: upgradedNameData.record.startTimestamp,
          processId: upgradedNameData.record.processId,
          undernameLimit: upgradedNameData.record.undernameLimit,
          purchasePrice: upgradedNameData.record.purchasePrice,
        },
        {
          name: 'test-name',
          type: 'permabuy',
          startTimestamp: buyRecordTimestamp,
          processId: ''.padEnd(43, 'a'),
          undernameLimit: 10,
          purchasePrice: 2500000000, // expected price for a permanent 9 character name
        },
      );
    });
  });

  describe('Release-Name', () => {
    it('should create an auction for an existing permabuy record owned by a process id, accept a bid and add the new record to the registry', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const initiator = 'ant-owner-'.padEnd(43, '0'); // owner of the ANT at the time of release
      const { memory, record: initialRecord } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId,
        type: 'permabuy',
      });

      const releaseNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Release-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Initiator', value: initiator }, // simulate who the owner is of the ANT process when sending the message
          ],
          From: processId,
          Owner: processId,
        },
        memory,
      );

      // assert no error tag
      const releaseNameErrorTag = releaseNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(releaseNameErrorTag, undefined);

      // fetch the auction
      const auctionResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Auction-Info' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        releaseNameResult.Memory,
      );
      // assert no error tag
      const auctionErrorTag = auctionResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(auctionErrorTag, undefined);
      const auction = JSON.parse(auctionResult.Messages?.[0]?.Data);
      const expectedStartPrice = 125000000000;
      const expectedStartTimestamp = STUB_TIMESTAMP;
      assert.deepEqual(auction, {
        name: 'test-name',
        initiator: initiator,
        startTimestamp: auction.startTimestamp,
        endTimestamp: expectedStartTimestamp + 60 * 60 * 1000 * 24 * 14,
        baseFee: 500000000,
        demandFactor: 1,
        settings: {
          decayRate: 0.02037911 / (1000 * 60 * 60 * 24 * 14),
          scalingExponent: 190,
          durationMs: 1209600000,
          startPriceMultiplier: 50,
        },
      });

      // TRANSFER FROM THE OWNER TO A NEW STUB ADDRESS
      const bidderAddress = 'auction-bidder-'.padEnd(43, '0');
      const bidTimestamp = auction.startTimestamp + 60 * 1000; // same as the original interval but 1 minute after the auction has started
      const decayRate = auction.settings.decayRate;
      const expectedPurchasePrice = Math.floor(
        expectedStartPrice *
          (1 - decayRate * (bidTimestamp - auction.startTimestamp)) **
            auction.settings.scalingExponent,
      );
      const transferResult = await handle(
        {
          From: PROCESS_OWNER,
          Owner: PROCESS_OWNER,
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: bidderAddress },
            { name: 'Quantity', value: expectedPurchasePrice },
            { name: 'Cast', value: true },
          ],
        },
        releaseNameResult.Memory,
      );

      // assert no error in the transfer
      const transferErrorTag = transferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(transferErrorTag, undefined);
      const submitBidResult = await handle(
        {
          From: bidderAddress,
          Owner: bidderAddress,
          Tags: [
            { name: 'Action', value: 'Auction-Bid' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: processId },
          ],
          Timestamp: bidTimestamp,
        },
        transferResult.Memory,
      );

      // assert no error tag
      const submitBidErrorTag = submitBidResult.Messages[0].Tags.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(submitBidErrorTag, undefined);

      // should send three messages including a Buy-Record-Notice and a Debit-Notice
      assert.equal(submitBidResult.Messages.length, 2);

      // should send a buy record notice
      const buyRecordNoticeTag = submitBidResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Buy-Record-Notice',
      );

      assert.ok(buyRecordNoticeTag);

      // expect the target tag to be the bidder
      assert.equal(submitBidResult.Messages?.[0]?.Target, bidderAddress);

      const expectedRecord = {
        processId,
        purchasePrice: expectedPurchasePrice,
        startTimestamp: bidTimestamp,
        undernameLimit: 10,
        type: 'permabuy',
      };
      const expectedRewardForInitiator = Math.floor(
        expectedPurchasePrice * 0.5,
      );
      const expectedRewardForProtocol =
        expectedPurchasePrice - expectedRewardForInitiator;

      // assert the data response contains the record
      const buyRecordNoticeData = JSON.parse(
        submitBidResult.Messages?.[0]?.Data,
      );
      assert.deepEqual(buyRecordNoticeData, {
        name: 'test-name',
        ...expectedRecord,
      });

      // should send a debit notice
      const debitNoticeTag = submitBidResult.Messages?.[1]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Debit-Notice',
      );
      assert.ok(debitNoticeTag);

      // expect the target to be to the initiator
      assert.equal(submitBidResult.Messages?.[1]?.Target, initiator);

      // assert the data response contains the record
      const debitNoticeData = JSON.parse(submitBidResult.Messages?.[1]?.Data);
      assert.deepEqual(debitNoticeData, {
        record: expectedRecord,
        bidder: bidderAddress,
        bidAmount: expectedPurchasePrice,
        rewardForInitiator: expectedRewardForInitiator,
        rewardForProtocol: expectedRewardForProtocol,
        name: 'test-name',
      });

      // should add the record to the registry
      const recordResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: bidTimestamp,
        },
        submitBidResult.Memory,
      );

      const record = JSON.parse(recordResult.Messages?.[0]?.Data);
      assert.deepEqual(record, {
        processId,
        purchasePrice: expectedPurchasePrice,
        startTimestamp: bidTimestamp,
        undernameLimit: 10,
        type: 'permabuy',
      });

      // assert the balance of the initiator and the protocol where updated correctly
      const balancesResult = await handle(
        {
          Tags: [{ name: 'Action', value: 'Balances' }],
        },
        submitBidResult.Memory,
      );

      const expectedProtocolBalance =
        INITIAL_PROTOCOL_BALANCE +
        initialRecord.purchasePrice +
        expectedRewardForProtocol;
      const balances = JSON.parse(balancesResult.Messages[0].Data);
      assert.equal(balances[initiator], expectedRewardForInitiator);
      assert.equal(balances[PROCESS_ID], expectedProtocolBalance);
      assert.equal(balances[bidderAddress], 0);
    });

    it('should create a lease expiration initiated auction and accept a bid', async () => {
      const { record: initialRecord, memory } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
      });

      // tick the contract after the lease leaves its grace period
      const futureTimestamp =
        initialRecord.endTimestamp + 60 * 1000 * 60 * 24 * 14 + 1;
      const tickResult = await handle(
        {
          Tags: [{ name: 'Action', value: 'Tick' }],
          Timestamp: futureTimestamp,
        },
        memory,
      );

      // fetch the auction
      const auctionResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Auction-Info' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        tickResult.Memory,
      );
      // assert no error tag
      const auctionErrorTag = auctionResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(auctionErrorTag, undefined);
      const auction = JSON.parse(auctionResult.Messages?.[0]?.Data);
      assert.deepEqual(auction, {
        name: 'test-name',
        initiator: PROCESS_ID,
        startTimestamp: futureTimestamp,
        endTimestamp: futureTimestamp + 60 * 60 * 1000 * 24 * 14,
        baseFee: 500000000,
        demandFactor: 1,
        settings: {
          decayRate: 0.02037911 / (1000 * 60 * 60 * 24 * 14),
          scalingExponent: 190,
          durationMs: 1209600000,
          startPriceMultiplier: 50,
        },
      });

      // // TRANSFER FROM THE OWNER TO A NEW STUB ADDRESS
      const bidYears = 3;
      const expectedFloorPrice = Math.floor(
        auction.baseFee + auction.baseFee * bidYears * 0.2,
      );
      const expectedStartPrice = Math.floor(
        expectedFloorPrice * auction.settings.startPriceMultiplier,
      );
      const bidderAddress = 'auction-bidder-'.padEnd(43, '0');
      const bidTimestamp = futureTimestamp + 60 * 60 * 1000 * 24 * 7; // 7 days into the auction
      const expectedPurchasePrice = Math.floor(
        expectedStartPrice *
          (1 - auction.settings.decayRate * (bidTimestamp - futureTimestamp)) **
            auction.settings.scalingExponent,
      );
      const transferResult = await handle(
        {
          From: PROCESS_OWNER,
          Owner: PROCESS_OWNER,
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: bidderAddress },
            { name: 'Quantity', value: `${expectedPurchasePrice}` },
            { name: 'Cast', value: true },
          ],
          Timestamp: bidTimestamp - 1,
        },
        tickResult.Memory,
      );

      // assert no error in the transfer
      const transferErrorTag = transferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(transferErrorTag, undefined);
      const processId = 'new-name-owner-'.padEnd(43, '1');
      const submitBidResult = await handle(
        {
          From: bidderAddress,
          Owner: bidderAddress,
          Tags: [
            { name: 'Action', value: 'Auction-Bid' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: processId },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: bidYears },
          ],
          Timestamp: bidTimestamp,
        },
        transferResult.Memory,
      );

      // assert no error tag
      const submitBidErrorTag = submitBidResult.Messages[0].Tags.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(submitBidErrorTag, undefined);

      // should send three messages including a Buy-Record-Notice and a Debit-Notice
      assert.equal(submitBidResult.Messages.length, 2);

      // should send a buy record notice
      const buyRecordNoticeTag = submitBidResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Buy-Record-Notice',
      );

      assert.ok(buyRecordNoticeTag);

      // expect the target tag to be the bidder
      assert.equal(submitBidResult.Messages?.[0]?.Target, bidderAddress);

      const expectedRecord = {
        processId,
        purchasePrice: expectedPurchasePrice,
        startTimestamp: bidTimestamp,
        endTimestamp: bidTimestamp + 60 * 60 * 1000 * 24 * 365 * 3,
        undernameLimit: 10,
        type: 'lease',
      };
      // the protocol gets the entire bid amount
      const expectedRewardForProtocol = expectedPurchasePrice;

      // assert the data response contains the record
      const buyRecordNoticeData = JSON.parse(
        submitBidResult.Messages?.[0]?.Data,
      );
      assert.deepEqual(buyRecordNoticeData, {
        name: 'test-name',
        ...expectedRecord,
      });

      // should send a debit notice
      const debitNoticeTag = submitBidResult.Messages?.[1]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Debit-Notice',
      );
      assert.ok(debitNoticeTag);

      // expect the target to be to the protocol balance
      assert.equal(submitBidResult.Messages?.[1]?.Target, PROCESS_ID);

      // assert the data response contains the record
      const debitNoticeData = JSON.parse(submitBidResult.Messages?.[1]?.Data);
      assert.deepEqual(debitNoticeData, {
        record: expectedRecord,
        bidder: bidderAddress,
        bidAmount: expectedPurchasePrice,
        rewardForInitiator: 0,
        rewardForProtocol: expectedRewardForProtocol,
        name: 'test-name',
      });

      // should add the record to the registry
      const recordResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: bidTimestamp,
        },
        submitBidResult.Memory,
      );

      const record = JSON.parse(recordResult.Messages?.[0]?.Data);
      assert.deepEqual(record, expectedRecord);

      // assert the balance of the initiator and the protocol where updated correctly
      const balancesResult = await handle(
        {
          Tags: [{ name: 'Action', value: 'Balances' }],
        },
        submitBidResult.Memory,
      );

      const expectedProtocolBalance =
        INITIAL_PROTOCOL_BALANCE +
        initialRecord.purchasePrice +
        expectedRewardForProtocol;
      const balances = JSON.parse(balancesResult.Messages[0].Data);
      assert.equal(balances[PROCESS_ID], expectedProtocolBalance);
      assert.equal(balances[bidderAddress], 0);
    });
  });

  describe('Auction-Prices', () => {
    it('should compute the prices of an auction at a specific interval', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const initiator = 'ant-owner-'.padEnd(43, '0'); // owner of the ANT at the time of release
      const { memory } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId,
        type: 'permabuy',
      });

      const releaseNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Release-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Initiator', value: initiator }, // simulate who the owner is of the ANT process when sending the message
          ],
          From: processId,
          Owner: processId,
        },
        memory,
      );

      // assert no error tag
      const releaseNameErrorTag = releaseNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(releaseNameErrorTag, undefined);

      // fetch the auction
      const auctionResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Auction-Info' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        releaseNameResult.Memory,
      );
      // assert no error tag
      const auctionErrorTag = auctionResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(auctionErrorTag, undefined);
      const auctionPrices = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Auction-Prices' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
          ],
        },
        releaseNameResult.Memory,
      );

      // assert no error tag for auction prices
      const auctionPricesErrorTag = auctionPrices.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(auctionPricesErrorTag, undefined);
      // parse the auction prices data
      const auctionPricesData = JSON.parse(auctionPrices.Messages?.[0]?.Data);

      // expectations
      const expectedStartPrice = 30000000000; // price for a 1 year lease
      const expectedFloorPrice = Math.floor(expectedStartPrice / 50);

      // validate the response structure
      assert.ok(auctionPricesData.name, 'Auction prices should include a name');
      assert.ok(auctionPricesData.type, 'Auction prices should include a type');
      assert.ok(
        auctionPricesData.prices,
        'Auction prices should include prices',
      );
      assert.ok(
        auctionPricesData.currentPrice,
        'Auction prices should include a current price',
      );

      // validate the prices
      assert.ok(
        Object.keys(auctionPricesData.prices).length > 0,
        'Prices should not be empty',
      );
      Object.entries(auctionPricesData.prices).forEach(([timestamp, price]) => {
        assert.ok(
          Number.isInteger(Number(timestamp)),
          'Timestamp should be a number',
        );
        assert.ok(Number.isInteger(price), 'Price should be an integer');
        assert.ok(price > 0, 'Price should be positive');
      });
      // assert the first price is the start price
      assert.equal(
        auctionPricesData.prices[STUB_TIMESTAMP],
        expectedStartPrice,
      );

      // assert the last price is the floor price
      const lastPriceTimestamp = Math.max(
        ...Object.keys(auctionPricesData.prices).map(Number),
      );
      assert.equal(
        auctionPricesData.prices[lastPriceTimestamp],
        expectedFloorPrice,
      );

      // validate the current price
      assert.ok(
        Number.isInteger(auctionPricesData.currentPrice),
        'Current price should be an integer',
      );
      assert.ok(
        auctionPricesData.currentPrice > 0,
        'Current price should be positive',
      );
    });
  });

  describe('Reassign-Name', () => {
    it('should reassign an arns name to a new process id', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { memory } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId,
        type: 'permabuy',
      });

      const reassignNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
          ],
          From: processId,
          Owner: processId,
        },
        memory,
      );

      // assert no error tag
      const releaseNameErrorTag = reassignNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(releaseNameErrorTag, undefined);
      assert.equal(reassignNameResult.Messages?.[0]?.Target, processId);
    });

    it('should reassign an arns name to a new process id with initiator', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { memory } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId,
        type: 'permabuy',
      });

      const reassignNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
            { name: 'Initiator', value: STUB_MESSAGE_ID },
          ],
          From: processId,
          Owner: processId,
        },
        memory,
      );

      // assert no error tag
      const releaseNameErrorTag = reassignNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(releaseNameErrorTag, undefined);
      assert.equal(reassignNameResult.Messages?.[0]?.Target, processId);
      assert.equal(reassignNameResult.Messages?.[1]?.Target, STUB_MESSAGE_ID); // Check for the message sent to the initiator
    });

    it('should not reassign an arns name with invalid ownership', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { memory } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId,
        type: 'permabuy',
      });

      const reassignNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
          ],
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
        },
        memory,
      );

      // assert error
      const releaseNameErrorTag = reassignNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(releaseNameErrorTag.value, 'Reassign-Name-Error');
    });

    it('should not reassign an arns name with invalid new process id', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { memory } = await runBuyRecord({
        sender: STUB_ADDRESS,
        processId,
        type: 'permabuy',
      });

      const reassignNameResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: 'this is an invalid process id' },
          ],
          From: processId,
          Owner: processId,
        },
        memory,
      );

      // assert error
      const releaseNameErrorTag = reassignNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(releaseNameErrorTag.value, 'Bad-Input');
    });
  });

  describe('Paginated-Records', () => {
    it('should paginate records correctly', async () => {
      // buy 3 records
      let buyRecordsMemory; // updated after each purchase
      const recordsCount = 3;
      for (let i = 0; i < recordsCount; i++) {
        const buyRecordsResult = await handle(
          {
            Tags: [
              { name: 'Action', value: 'Buy-Record' },
              { name: 'Name', value: `test-name-${i}` },
              { name: 'Process-Id', value: ''.padEnd(43, `${i}`) },
            ],
            Timestamp: STUB_TIMESTAMP + i * 1000, // order of names is based on timestamp
          },
          buyRecordsMemory,
        );
        buyRecordsMemory = buyRecordsResult.Memory;
      }

      // call the paginated records handler repeatedly until all records are fetched
      let paginatedRecords = [];
      let cursor = undefined;
      while (true) {
        const result = await handle(
          {
            Tags: [
              { name: 'Action', value: 'Paginated-Records' },
              { name: 'Cursor', value: cursor },
              { name: 'Limit', value: 1 },
            ],
          },
          buyRecordsMemory,
        );
        // assert no error tag
        const errorTag = result.Messages?.[0]?.Tags?.find(
          (tag) => tag.name === 'Error',
        );
        assert.equal(errorTag, undefined);
        // add the records to the paginated records array
        const {
          items: records,
          nextCursor,
          hasMore,
          totalItems,
          sortBy,
          sortOrder,
        } = JSON.parse(result.Messages?.[0]?.Data);
        assert.equal(totalItems, recordsCount);
        assert.equal(sortBy, 'startTimestamp');
        assert.equal(sortOrder, 'desc');
        paginatedRecords.push(...records);
        // update the cursor
        cursor = nextCursor;
        // if the cursor is undefined, we have reached the end of the records
        if (!hasMore) {
          break;
        }
      }
      assert.equal(paginatedRecords.length, recordsCount);
      // assert all the names are returned in the correct order
      const expectedNames = Array.from(
        { length: recordsCount },
        (_, i) => `test-name-${recordsCount - i - 1}`,
      );
      assert.deepEqual(
        paginatedRecords.map((record) => record.name),
        expectedNames,
      );
    });
  });

  describe('Cost-Details', () => {
    const joinedGateway = 'joined-unique-gateway-'.padEnd(43, '0');
    const nonEligibleAddress = 'non-eligible-address'.padEnd(43, '1');

    const firstEpochTimestamp = 1719900000000;
    const afterDistributionTimestamp =
      firstEpochTimestamp + 1000 * 60 * 60 * 24 + 1000 * 60 * 40;

    let arnsDiscountMemory;
    before(async () => {
      // add a gateway and distribute to increment stats
      const { memory: join1Memory } = await joinNetwork({
        address: joinedGateway,
        quantity: 300_000_000_000,
        timestamp: firstEpochTimestamp - 1000 * 60 * 60 * 24 * 365, // 365 days before the first epoch
      });

      const firstTickAndDistribution = await handle(
        {
          Tags: [{ name: 'Action', value: 'Tick' }],
          Timestamp: afterDistributionTimestamp,
        },
        join1Memory,
      );

      // assert our gateway has weights making it eligible for ArNS discount
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: joinedGateway },
          ],
        },
        firstTickAndDistribution.Memory,
      );
      // ensure the gateway is joined and has weights making it eligible for ArNS discount
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.equal(gatewayData.status, 'joined');
      assert(
        gatewayData.weights.tenureWeight >= 1,
        'Gateway should have a tenure weight greater than or equal to 1',
      );
      assert(
        gatewayData.weights.gatewayRewardRatioWeight >= 1,
        'Gateway should have a gateway reward ratio weight greater than or equal to 1',
      );

      // add funds for the non-eligible gateway
      const transferMemory = await transfer({
        recipient: nonEligibleAddress,
        quantity: 200_000_000_000,
        timestamp: afterDistributionTimestamp - 1,
        memory: firstTickAndDistribution.Memory,
      });
      arnsDiscountMemory = transferMemory;
    });

    it('should return discounted cost for a buy record by an eligible gateway', async () => {
      const result = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Get-Cost-Details-For-Action' },
            { name: 'Intent', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
          ],
          From: joinedGateway,
          Owner: joinedGateway,
          Timestamp: afterDistributionTimestamp,
        },
        arnsDiscountMemory,
      );

      const { tokenCost, discounts } = JSON.parse(result.Messages[0].Data);
      assert.equal(tokenCost, baseLeasePrice * 0.8);
      assert.deepEqual(discounts, [
        {
          discountTotal: baseLeasePrice * 0.2,
          multiplier: 0.2,
          name: 'ArNS Discount',
        },
      ]);
    });

    it('should return the correct cost for a buy record by a non-eligible gateway', async () => {
      const result = await handle(
        {
          From: nonEligibleAddress,
          Owner: nonEligibleAddress,
          Tags: [
            { name: 'Action', value: 'Get-Cost-Details-For-Action' },
            { name: 'Intent', value: 'Buy-Record' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        arnsDiscountMemory,
      );
      const costDetails = JSON.parse(result.Messages[0].Data);
      assert.equal(costDetails.tokenCost, baseLeasePrice);
      assert.deepEqual(costDetails.discounts, []);
    });

    describe('for an existing record', () => {
      let buyRecordResult;
      let nonEligibleBuyRecordResult;
      const baseFeeForName = 500000000; // base fee for a 10 character name
      const buyRecordTimestamp = afterDistributionTimestamp;
      before(async () => {
        buyRecordResult = await handle(
          {
            From: joinedGateway,
            Owner: joinedGateway,
            Tags: [
              { name: 'Action', value: 'Buy-Record' },
              { name: 'Name', value: 'great-name' },
              { name: 'Purchase-Type', value: 'lease' },
              { name: 'Process-Id', value: ''.padEnd(43, 'a') },
              { name: 'Years', value: '1' },
            ],
            Timestamp: buyRecordTimestamp,
          },
          arnsDiscountMemory,
        );
        nonEligibleBuyRecordResult = await handle(
          {
            From: nonEligibleAddress,
            Owner: nonEligibleAddress,
            Tags: [
              { name: 'Action', value: 'Buy-Record' },
              { name: 'Name', value: 'great-name' },
              { name: 'Purchase-Type', value: 'lease' },
              { name: 'Process-Id', value: ''.padEnd(43, 'a') },
              { name: 'Years', value: '1' },
            ],
            Timestamp: buyRecordTimestamp,
          },
          arnsDiscountMemory,
        );
        assertNoResultError(buyRecordResult);
      });

      describe('extending the lease', () => {
        const extendLeaseTags = [
          { name: 'Name', value: 'great-name' },
          { name: 'Years', value: '1' },
        ];
        const extendLeaseCostDetailsTags = [
          { name: 'Action', value: 'Get-Cost-Details-For-Action' },
          { name: 'Intent', value: 'Extend-Lease' },
          ...extendLeaseTags,
        ];
        const extendLeaseActionTags = [
          { name: 'Action', value: 'Extend-Lease' },
          ...extendLeaseTags,
        ];
        const extendLeaseTimestamp = buyRecordTimestamp + 1;
        const baseFeeForName = 500000000; // base fee for a 10 character name
        const baseLeaseOneYearExtensionPrice = baseFeeForName * 0.2; // 1 year extension at 20% for the year

        it('should apply the discount to extending the lease for an eligible gateway', async () => {
          const result = await handle(
            {
              From: joinedGateway,
              Owner: joinedGateway,
              Tags: extendLeaseCostDetailsTags,
              Timestamp: extendLeaseTimestamp,
            },
            buyRecordResult.Memory,
          );
          const { tokenCost, discounts } = JSON.parse(result.Messages[0].Data);
          assert.equal(tokenCost, baseLeaseOneYearExtensionPrice * 0.8);
          assert.deepEqual(discounts, [
            {
              discountTotal: baseLeaseOneYearExtensionPrice * 0.2,
              multiplier: 0.2,
              name: 'ArNS Discount',
            },
          ]);
        });

        it('should not apply the discount to extending the lease for a non-eligible gateway', async () => {
          const result = await handle(
            {
              From: nonEligibleAddress,
              Owner: nonEligibleAddress,
              Tags: extendLeaseCostDetailsTags,
              Timestamp: extendLeaseTimestamp,
            },
            buyRecordResult.Memory,
          );
          const { tokenCost, discounts } = JSON.parse(result.Messages[0].Data);
          assert.equal(tokenCost, baseLeaseOneYearExtensionPrice);
          assert.deepEqual(discounts, []);
        });

        it('balances should be updated when the extend lease action is performed', async () => {
          const eligibleGatewayBalanceBefore = await getBalance({
            memory: buyRecordResult.Memory,
            timestamp: extendLeaseTimestamp - 1,
            address: joinedGateway,
          });
          const nonEligibleGatewayBalanceBefore = await getBalance({
            memory: nonEligibleBuyRecordResult.Memory,
            timestamp: extendLeaseTimestamp - 1,
            address: nonEligibleAddress,
          });

          const eligibleGatewayResult = await handle(
            {
              From: joinedGateway,
              Owner: joinedGateway,
              Tags: extendLeaseActionTags,
              Timestamp: extendLeaseTimestamp,
            },
            buyRecordResult.Memory,
          );
          const nonEligibleGatewayResult = await handle(
            {
              From: nonEligibleAddress,
              Owner: nonEligibleAddress,
              Tags: extendLeaseActionTags,
              Timestamp: extendLeaseTimestamp,
            },
            nonEligibleBuyRecordResult.Memory,
          );

          const eligibleBalanceAfter = await getBalance({
            memory: eligibleGatewayResult.Memory,
            timestamp: extendLeaseTimestamp + 1,
            address: joinedGateway,
          });
          const nonEligibleBalanceAfter = await getBalance({
            memory: nonEligibleGatewayResult.Memory,
            timestamp: extendLeaseTimestamp + 1,
            address: nonEligibleAddress,
          });

          assert.equal(
            eligibleGatewayBalanceBefore - baseLeaseOneYearExtensionPrice * 0.8,
            eligibleBalanceAfter,
          );

          assert.equal(
            nonEligibleGatewayBalanceBefore - baseLeaseOneYearExtensionPrice,
            nonEligibleBalanceAfter,
          );
        });

        describe('upgrading the lease to a permabuy', () => {
          const upgradeToPermabuyTags = [
            { name: 'Action', value: 'Get-Cost-Details-For-Action' },
            { name: 'Intent', value: 'Upgrade-Name' },
            { name: 'Name', value: 'great-name' },
          ];
          const upgradeToPermabuyTimestamp = afterDistributionTimestamp;
          const basePermabuyPrice = baseFeeForName + baseFeeForName * 0.2 * 20; // 20 years of annual renewal fees

          it('should apply the discount to upgrading the lease to a permabuy for an eligible gateway', async () => {
            const result = await handle(
              {
                From: joinedGateway,
                Owner: joinedGateway,
                Tags: upgradeToPermabuyTags,
                Timestamp: upgradeToPermabuyTimestamp,
              },
              buyRecordResult.Memory,
            );
            const { tokenCost, discounts } = JSON.parse(
              result.Messages[0].Data,
            );
            assert.equal(tokenCost, basePermabuyPrice * 0.8);
            assert.deepEqual(discounts, [
              {
                discountTotal: basePermabuyPrice * 0.2,
                multiplier: 0.2,
                name: 'ArNS Discount',
              },
            ]);
          });

          it('should not apply the discount to increasing the undername limit for a non-eligible gateway', async () => {
            const result = await handle(
              {
                From: nonEligibleAddress,
                Owner: nonEligibleAddress,
                Tags: upgradeToPermabuyTags,
              },
              buyRecordResult.Memory,
            );
            const { tokenCost, discounts } = JSON.parse(
              result.Messages[0].Data,
            );
            assert.equal(tokenCost, basePermabuyPrice);
            assert.deepEqual(discounts, []);
          });
        });

        describe('increasing the undername limit', () => {
          const increaseUndernameQty = 20;
          const undernameCostsForOneYear =
            baseFeeForName * 0.001 * increaseUndernameQty;
          const increaseUndernameLimitTags = [
            { name: 'Action', value: 'Get-Cost-Details-For-Action' },
            { name: 'Intent', value: 'Increase-Undername-Limit' },
            { name: 'Name', value: 'great-name' },
            { name: 'Quantity', value: increaseUndernameQty.toString() },
          ];

          it('should apply the discount to increasing the undername limit for an eligible gateway', async () => {
            const result = await handle(
              {
                From: joinedGateway,
                Owner: joinedGateway,
                Tags: increaseUndernameLimitTags,
                Timestamp: afterDistributionTimestamp, // timestamp dependent
              },
              buyRecordResult.Memory,
            );
            const { tokenCost, discounts } = JSON.parse(
              result.Messages[0].Data,
            );
            assert.equal(tokenCost, undernameCostsForOneYear * 0.8);
            assert.deepEqual(discounts, [
              {
                discountTotal: undernameCostsForOneYear * 0.2,
                multiplier: 0.2,
                name: 'ArNS Discount',
              },
            ]);
          });

          it('should not apply the discount to increasing the undername limit for a non-eligible gateway', async () => {
            const result = await handle(
              {
                From: nonEligibleAddress,
                Owner: nonEligibleAddress,
                Tags: increaseUndernameLimitTags,
                Timestamp: afterDistributionTimestamp, // timestamp dependent
              },
              buyRecordResult.Memory,
            );
            const { tokenCost, discounts } = JSON.parse(
              result.Messages[0].Data,
            );
            assert.equal(tokenCost, undernameCostsForOneYear);
            assert.deepEqual(discounts, []);
          });
        });

        describe('when the record is in auction', () => {
          let expiredRecordMemory;
          const expiredRecordTimestamp =
            buyRecordTimestamp + 1000 * 60 * 60 * 24 * 379 + 1; // 379 days after the record has expired
          const baseAuctionPrice = 30_000_000_000;
          const auctionTags = [
            { name: 'Action', value: 'Auction-Prices' },
            { name: 'Name', value: 'great-name' },
            { name: 'Purchase-Type', value: 'lease' },
          ];
          before(async () => {
            const tickResult = await handle(
              {
                Tags: [{ name: 'Action', value: 'Tick' }],
                Timestamp: expiredRecordTimestamp,
              },
              buyRecordResult.Memory,
            );
            expiredRecordMemory = tickResult.Memory;
          });

          it('should return discounts for eligible gateways', async () => {
            const result = await handle(
              {
                From: joinedGateway,
                Owner: joinedGateway,
                Tags: auctionTags,
                Timestamp: expiredRecordTimestamp,
              },
              expiredRecordMemory,
            );
            const { currentPrice, discounts } = JSON.parse(
              result.Messages[0].Data,
            );
            assert.equal(currentPrice, baseAuctionPrice);
            assert.deepEqual(discounts, [
              {
                name: 'ArNS Discount',
                multiplier: 0.2,
              },
            ]);
          });

          it('should not apply the discount to auction prices for a non-eligible gateway', async () => {
            const result = await handle(
              {
                From: nonEligibleAddress,
                Owner: nonEligibleAddress,
                Tags: auctionTags,
                Timestamp: expiredRecordTimestamp,
              },
              expiredRecordMemory,
            );
            const { currentPrice, discounts } = JSON.parse(
              result.Messages[0].Data,
            );
            assert.equal(currentPrice, baseAuctionPrice);
            assert.deepEqual(discounts, []);
          });

          const submitBidTags = [
            { name: 'Action', value: 'Auction-Bid' },
            { name: 'Name', value: 'great-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
            { name: 'Purchase-Type', value: 'lease' },
          ];
          const submitBidTimestamp = expiredRecordTimestamp;

          it('should apply the discount on submit bid for an eligible gateway', async () => {
            const result = await handle(
              {
                From: joinedGateway,
                Owner: joinedGateway,
                Tags: submitBidTags,
                Timestamp: submitBidTimestamp,
              },
              expiredRecordMemory,
            );
            const { purchasePrice } = JSON.parse(result.Messages[0].Data);
            assert.equal(purchasePrice, baseAuctionPrice * 0.8);
          });

          it('should not apply the discount on submit bid for a non-eligible gateway', async () => {
            const balanceBefore = await getBalance({
              memory: expiredRecordMemory,
              timestamp: submitBidTimestamp - 1,
              address: nonEligibleAddress,
            });
            const result = await handle(
              {
                From: nonEligibleAddress,
                Owner: nonEligibleAddress,
                Tags: submitBidTags,
                Timestamp: submitBidTimestamp,
              },
              expiredRecordMemory,
            );
            const { purchasePrice } = JSON.parse(result.Messages[0].Data);
            assert.equal(purchasePrice, baseAuctionPrice);
            const balanceAfter = await getBalance({
              memory: result.Memory,
              timestamp: submitBidTimestamp + 1,
              address: nonEligibleAddress,
            });
            assert.equal(balanceBefore - baseAuctionPrice, balanceAfter);
          });
        });
      });
    });
  });
});
