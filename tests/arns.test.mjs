import { assertNoResultError } from './utils.mjs';
import { describe, it, before, beforeEach, afterEach } from 'node:test';
import {
  handle,
  startMemory,
  transfer,
  joinNetwork,
  setUpStake,
  baseLeasePriceFor9CharNameFor1Year,
  basePermabuyPrice,
  getBalance,
  returnedNamesPeriod,
  buyRecord,
  increaseUndernameLimit,
  baseLeasePriceFor9CharNameFor3Years,
  totalTokenSupply,
  tick,
  getTokenCost,
  getRecord,
  getGateway,
  delegateStake,
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
import { assertNoInvariants } from './invariants.mjs';
import { start } from 'node:repl';

// EIP55-formatted test address
const testEthAddress = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa';

describe('ArNS', async () => {
  let sharedMemory;
  beforeEach(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });

    const transferMemory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 1_000_000_000_000,
      memory: totalTokenSupplyMemory,
    });
    sharedMemory = transferMemory;
  });

  afterEach(async () => {
    await assertNoInvariants({
      timestamp: 1719988800001, // after latest known timestamp from a test
      memory: sharedMemory,
    });
  });

  describe('Buy-Name', () => {
    it('should buy a record with an Arweave address', async () => {
      const { result: buyRecordResult } = await buyRecord({
        from: STUB_ADDRESS,
        name: 'test-arweave-address',
        type: 'lease',
        years: 1,
        processId: ''.padEnd(43, 'a'),
        memory: sharedMemory,
      });

      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);
      const record = await getRecord({
        name: 'test-arweave-address',
        memory: buyRecordResult.Memory,
      });

      assert.deepEqual(record, {
        processId: ''.padEnd(43, 'a'),
        purchasePrice: buyRecordData.purchasePrice,
        startTimestamp: buyRecordData.startTimestamp,
        type: 'lease',
        undernameLimit: 10,
        endTimestamp: buyRecordData.endTimestamp,
      });
      sharedMemory = buyRecordResult.Memory;
    });

    it('should buy a record with an Ethereum address', async () => {
      // transfer it tokens
      const transferMemory = await transfer({
        recipient: testEthAddress,
        quantity: 1_000_000_000_000,
        memory: sharedMemory,
      });

      const { result: buyRecordResult } = await buyRecord({
        from: testEthAddress,
        name: 'test-ethereum-address',
        type: 'lease',
        years: 1,
        processId: ''.padEnd(43, 'a'),
        memory: transferMemory,
      });

      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);
      const record = await getRecord({
        name: 'test-ethereum-address',
        memory: buyRecordResult.Memory,
      });

      assert.deepEqual(record, {
        processId: ''.padEnd(43, 'a'),
        purchasePrice: buyRecordData.purchasePrice,
        startTimestamp: buyRecordData.startTimestamp,
        type: 'lease',
        undernameLimit: 10,
        endTimestamp: buyRecordData.endTimestamp,
      });
      sharedMemory = buyRecordResult.Memory;
    });

    it('should support `Buy-Record` as a backwards compatible alias', async () => {
      // not using stub to test the backwards compatibility of the tag
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-buy-record-tag',
        type: 'lease',
        years: 1,
        processId: ''.padEnd(43, 'a'),
        memory: sharedMemory,
      });
      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);
      assert.equal(
        buyRecordResult.Messages[0].Tags.find((t) => t.name === 'Action').value,
        'Buy-Name-Notice',
      );
      const buyRecordResponse = JSON.parse(buyRecordResult.Messages[0].Data);
      assert.deepEqual(buyRecordResponse, {
        name: 'test-buy-record-tag',
        processId: ''.padEnd(43, 'a'),
        purchasePrice: buyRecordData.purchasePrice,
        startTimestamp: buyRecordData.startTimestamp,
        type: 'lease',
        undernameLimit: 10,
        endTimestamp: buyRecordData.endTimestamp,
        baseRegistrationFee: buyRecordData.baseRegistrationFee,
        remainingBalance: 948999520000000,
      });
    });

    it('should fail to buy a permanently registered record', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-owned-name',
        processId: ''.padEnd(43, 'a'),
        type: 'permabuy',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
        from: STUB_ADDRESS,
      });

      // try and buy it again
      const { result: failedBuyRecordResult } = await buyRecord({
        name: 'test-owned-name',
        processId: ''.padEnd(43, 'a'),
        type: 'permabuy',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: buyRecordResult.Memory,
        assertError: false,
      });

      const failedBuyRecordError = failedBuyRecordResult.Messages[0].Tags.find(
        (t) => t.name === 'Error',
      );
      assert.ok(failedBuyRecordError, 'Error tag should be present');
      const alreadyRegistered = failedBuyRecordResult.Messages[0].Data.includes(
        'Name is already registered',
      );
      assert(alreadyRegistered);
      sharedMemory = failedBuyRecordResult.Memory;
    });

    it('should buy a record and default the name to lower case', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'Test-Name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);

      // fetch the record
      const record = await getRecord({
        name: 'test-name',
        memory: buyRecordResult.Memory,
      });
      assert.deepEqual(record, {
        processId: ''.padEnd(43, 'a'),
        purchasePrice: buyRecordData.purchasePrice,
        startTimestamp: buyRecordData.startTimestamp,
        endTimestamp: buyRecordData.endTimestamp,
        type: 'lease',
        undernameLimit: 10,
      });
      sharedMemory = buyRecordResult.Memory;
    });

    it('should buy a record and default the name to lower case', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'Test-Name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);
      // fetch the record
      const record = await getRecord({
        name: 'test-name',
        memory: buyRecordResult.Memory,
      });
      assert.deepEqual(record, {
        processId: ''.padEnd(43, 'a'),
        purchasePrice: buyRecordData.purchasePrice,
        startTimestamp: buyRecordData.startTimestamp,
        endTimestamp: buyRecordData.endTimestamp,
        type: 'lease',
        undernameLimit: 10,
      });
      sharedMemory = buyRecordResult.Memory;
    });
  });

  describe('Increase-Undername-Limit', () => {
    let costForIncreaseUndernameLimit;
    let increaseUndernameMemory;

    before(async () => {
      const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
        memory: startMemory,
      });
      // doesn't matter who buys it, increasing undername limit is permissionless
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: totalTokenSupplyMemory,
      });

      // get the cost for increasing the undername limit
      const tokenCostResult = await getTokenCost({
        from: STUB_ADDRESS,
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        intent: 'Increase-Undername-Limit',
        memory: buyRecordResult.Memory,
      });

      const transferMemory = await transfer({
        recipient: STUB_ADDRESS,
        quantity: 15_000_000_000,
        memory: buyRecordResult.Memory,
      });

      costForIncreaseUndernameLimit = tokenCostResult.tokenCost;
      increaseUndernameMemory = transferMemory;
    });

    it('should increase the undernames by spending from balance', async () => {
      const balanceBefore = await getBalance({
        address: STUB_ADDRESS,
        memory: increaseUndernameMemory,
      });
      const { result: increaseUndernameResult } = await increaseUndernameLimit({
        from: STUB_ADDRESS,
        name: 'test-name',
        quantity: 1,
        memory: increaseUndernameMemory,
      });
      const record = await getRecord({
        name: 'test-name',
        memory: increaseUndernameResult.Memory,
      });
      assert.equal(record.undernameLimit, 11);

      // validate the balance was reduced by the cost of increasing the undername limit
      const balanceAfter = await getBalance({
        address: STUB_ADDRESS,
        memory: increaseUndernameResult.Memory,
      });
      // validate the cost matched the expected cost
      assert.equal(balanceAfter, balanceBefore - costForIncreaseUndernameLimit);
      sharedMemory = increaseUndernameResult.Memory;
    });

    it('should increase the undernames by spending from stakes', async () => {
      // Stake a gateway for the user to delegate to
      const { result: joinNetworkResult } = await joinNetwork({
        memory: increaseUndernameMemory,
        address: STUB_OPERATOR_ADDRESS,
        stakeQty: 15_000_000_000,
      });

      // delegate stake from someone else
      const transferMemory = await transfer({
        recipient: STUB_ADDRESS,
        quantity: 10_000_000_000,
        memory: joinNetworkResult.Memory,
      });

      const { result: delegateStakeResult } = await delegateStake({
        memory: transferMemory,
        from: STUB_ADDRESS,
        address: STUB_OPERATOR_ADDRESS,
        quantity: 10_000_000_000,
      });

      const { result: increaseUndernameResult } = await increaseUndernameLimit({
        from: STUB_ADDRESS,
        name: 'test-name',
        quantity: 1,
        fundFrom: 'stakes',
        memory: delegateStakeResult.Memory,
      });

      const record = await getRecord({
        name: 'test-name',
        memory: increaseUndernameResult.Memory,
      });
      assert.equal(record.undernameLimit, 11);

      // validate the operator stake was reduced by the cost of increasing the undername limit
      const gatewayAfter = await getGateway({
        memory: increaseUndernameResult.Memory,
        address: STUB_OPERATOR_ADDRESS,
      });
      assert.equal(
        gatewayAfter.delegatedStake,
        gatewayBefore.delegatedStake - costForIncreaseUndernameLimit,
      );
    });
  });

  describe('Get-Registration-Fees', () => {
    it('should return the base registration fees for each name length', async () => {
      const priceListResult = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Get-Registration-Fees' }],
        },
        memory: sharedMemory,
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
    const testNewAddress = 'test-new-address-'.padEnd(43, 'b');
    //Reference: https://ardriveio.sharepoint.com/:x:/s/AR.IOLaunch/Ec3L8aX0wuZOlG7yRtlQoJgB39wCOoKu02PE_Y4iBMyu7Q?e=ZG750l
    it('should return the correct cost of buying a name as a lease', async () => {
      // the name will cost 600_000_000, so we'll want to see a shortfall of 200_000_000 in the funding plan
      const transferMemory = await transfer({
        recipient: testNewAddress,
        quantity: 400_000_000,
        cast: true,
        memory: sharedMemory,
      });

      const tokenCostResult = await getTokenCost({
        from: testNewAddress,
        memory: transferMemory,
        intent: 'Buy-Name',
        name: 'test-name',
        type: 'lease',
        years: 1,
        fundFrom: 'balance',
      });

      assert.deepEqual(tokenCostResult, {
        discounts: [],
        tokenCost: baseLeasePriceFor9CharNameFor1Year,
        fundingPlan: {
          address: testNewAddress,
          balance: 400_000_000,
          shortfall: 200_000_000,
          stakes: [],
        },
      });
    });

    it('should return the correct cost of buying a name as a lease', async () => {
      // the name will cost 600_000_000, so we'll want to see a shortfall of 200_000_000 in the funding plan
      const transferMemory = await transfer({
        recipient: testNewAddress,
        quantity: 400_000_000,
        cast: true,
        memory: sharedMemory,
      });

      const result = await handle({
        options: {
          From: testNewAddress,
          Owner: testNewAddress,
          Tags: [
            // latest tags
            { name: 'Action', value: 'Cost-Details' },
            { name: 'Intent', value: 'Buy-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
            { name: 'Process-Id', value: ''.padEnd(43, 'a') },
            { name: 'Fund-From', value: 'balance' },
          ],
        },
        memory: transferMemory,
      });

      const tokenCostResult = JSON.parse(result.Messages[0].Data);
      assert.deepEqual(tokenCostResult, {
        discounts: [],
        tokenCost: baseLeasePriceFor9CharNameFor1Year,
        fundingPlan: {
          address: testNewAddress,
          balance: 400_000_000,
          shortfall: 200_000_000,
          stakes: [],
        },
      });
      sharedMemory = result.Memory;
    });

    it('should return the correct cost of increasing an undername limit', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      const result = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Increase-Undername-Limit' },
            { name: 'Name', value: 'test-name' },
            { name: 'Quantity', value: '1' },
          ],
        },
        memory: buyRecordResult.Memory,
      });
      const tokenCost = JSON.parse(result.Messages[0].Data);
      const expectedPrice = 500000000 * 0.001 * 1 * 1;
      assert.equal(tokenCost, expectedPrice);
      sharedMemory = result.Memory;
    });

    it('should return the correct cost of extending an existing leased record', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      const result = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Extend-Lease' },
            { name: 'Name', value: 'test-name' },
            { name: 'Years', value: '2' },
          ],
        },
        memory: buyRecordResult.Memory,
      });
      const tokenCost = JSON.parse(result.Messages[0].Data);
      assert.equal(tokenCost, 200000000); // known cost for extending a 9 character name by 2 years (500 ARIO * 0.2 * 2)
      sharedMemory = result.Memory;
    });

    it('should get the cost of upgrading an existing leased record to permanently owned', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      const upgradeNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Upgrade-Name' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        memory: buyRecordResult.Memory,
      });

      const tokenCost = JSON.parse(upgradeNameResult.Messages[0].Data);
      assert.equal(tokenCost, basePermabuyPrice);
      sharedMemory = upgradeNameResult.Memory;
    });

    it('should return the correct cost of creating a primary name request', async () => {
      const memory = await transfer({
        quantity: 400_000_000,
        memory: sharedMemory,
        recipient: STUB_ADDRESS,
      });
      let buyNameMemory = memory;
      // primary names should cost the same as an undername on a 51 character name, so buy both a 9 character name and a 51 character name and compare the primary name cost for *any* name length against the increase undername limit cost
      for (const name of ['test-name', ''.padEnd(51, 'a')]) {
        const { memory: buyMemory } = await buyRecord({
          from: STUB_ADDRESS,
          memory: buyNameMemory,
          name: name,
          processId: ''.padEnd(43, 'a'),
        });
        buyNameMemory = buyMemory;
      }

      // get the cost of increasing the undername limit for a 51 character name
      const undernameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Increase-Undername-Limit' },
            { name: 'Name', value: ''.padEnd(51, 'a') },
            { name: 'Quantity', value: '1' },
          ],
          Timestamp: STUB_TIMESTAMP,
        },
        memory: buyNameMemory,
      });
      const undernameTokenCost = JSON.parse(undernameResult.Messages[0].Data);

      // check the costs for both primary names, they should be the same as the undername limit cost for a 51 character name
      for (const name of ['test-name', ''.padEnd(51, 'a')]) {
        const primaryNameRequestResult = await handle({
          options: {
            Tags: [
              { name: 'Action', value: 'Token-Cost' },
              { name: 'Intent', value: 'Primary-Name-Request' },
              { name: 'Name', value: name },
            ],
            Timestamp: STUB_TIMESTAMP,
          },
          memory: buyNameMemory,
        });
        const primaryNameCost = JSON.parse(
          primaryNameRequestResult.Messages[0].Data,
        );
        assert.equal(primaryNameCost, undernameTokenCost);
      }
      sharedMemory = undernameResult.Memory;
    });
  });

  describe('Extend-Lease', () => {
    it('should properly handle extending a leased record', async () => {
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });
      const recordBefore = await getRecord({
        name: 'test-name',
        memory: buyRecordResult.Memory,
      });
      const extendResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Extend-Lease' },
            { name: 'Name', value: 'test-name' },
            { name: 'Years', value: '1' },
          ],
        },
        memory: buyRecordResult.Memory,
      });
      const record = await getRecord({
        name: 'test-name',
        memory: extendResult.Memory,
      });
      assert.equal(
        record.endTimestamp,
        recordBefore.endTimestamp + 60 * 1000 * 60 * 24 * 365,
      );
      sharedMemory = extendResult.Memory;
    });

    it('should properly handle extending a leased record paying with balance and stakes', async () => {
      let memory = sharedMemory;
      const stakeResult = await setUpStake({
        memory,
        transferQty: 700000000, // 600000000 for name purchase + 100000000 for extending the lease
        stakeQty: 650000000, // delegate most of their balance so that name purchase uses balance and stakes
        timestamp: STUB_TIMESTAMP,
      });

      memory = stakeResult.memory;

      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory,
      });
      memory = buyRecordResult.Memory;

      const recordBefore = await getRecord({
        name: 'test-name',
        memory: buyRecordResult.Memory,
      });

      // Last 100,000,000 mARIO will be paid from exit vault 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm'
      const extendResult = await handle({
        options: {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Extend-Lease' },
            { name: 'Name', value: 'test-name' },
            { name: 'Years', value: '1' },
            { name: 'Fund-From', value: 'any' },
          ],
        },
        memory: buyRecordResult.Memory,
      });

      const record = await getRecord({
        name: 'test-name',
        memory: extendResult.Memory,
      });
      assert.equal(
        recordBefore.endTimestamp + 60 * 1000 * 60 * 24 * 365,
        record.endTimestamp,
      );
      sharedMemory = extendResult.Memory;
    });
  });

  describe('Upgrade-Name', () => {
    it('should properly handle upgrading a name', async () => {
      const buyRecordTimestamp = STUB_TIMESTAMP + 1;
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: buyRecordTimestamp,
        memory: sharedMemory,
      });

      // now upgrade the name
      const upgradeNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Upgrade-Name' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: buyRecordTimestamp,
        },
        memory: buyRecordResult.Memory,
      });

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
      sharedMemory = upgradeNameResult.Memory;
    });

    it('should properly handle upgrading a name paying with balance and stakes', async () => {
      let memory = sharedMemory;
      const stakeResult = await setUpStake({
        memory,
        transferQty: 3_100_000_000, // 60,000,0000 for name purchase + 2,500,000,000 for upgrading the name
        stakeQty: 3_100_000_000 - 50_000_000, // delegate most of their balance so that name purchase uses balance and stakes
        stakerAddress: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
      });
      memory = stakeResult.memory;

      const buyRecordTimestamp = STUB_TIMESTAMP + 1;
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        fundFrom: 'any',
        timestamp: buyRecordTimestamp,
        memory,
      });

      // now upgrade the name
      const upgradeNameResult = await handle({
        options: {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Upgrade-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Fund-From', value: 'stakes' },
          ],
          Timestamp: buyRecordTimestamp + 1,
        },
        memory: buyRecordResult.Memory,
      });
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
      sharedMemory = upgradeNameResult.Memory;
    });
  });

  describe('Release-Name', () => {
    it('should create a released name for an existing permabuy record owned by a process id, accept a Buy-Name and add the new record to the registry', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const initiator = 'ant-owner-'.padEnd(43, '0'); // owner of the ANT at the time of release
      const { memory, result: buyRecordResult } = await buyRecord({
        from: STUB_ADDRESS,
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP,
      });

      const initialRecord = JSON.parse(buyRecordResult.Messages[0].Data);

      const releaseNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Release-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Initiator', value: initiator }, // simulate who the owner is of the ANT process when sending the message
          ],
          From: processId,
          Owner: processId,
        },
        memory,
      });

      // assert no error tag
      assertNoResultError(releaseNameResult);

      // fetch the auction
      const returnedNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Returned-Name' },
            { name: 'Name', value: 'test-name' },
          ],
        },
        memory: releaseNameResult.Memory,
      });

      const returnedName = JSON.parse(returnedNameResult.Messages?.[0]?.Data);
      const expectedStartTimestamp = STUB_TIMESTAMP;
      assert.deepEqual(returnedName, {
        name: 'test-name',
        initiator: initiator,
        startTimestamp: returnedName.startTimestamp,
        endTimestamp: expectedStartTimestamp + returnedNamesPeriod,
        premiumMultiplier: 50,
      });

      // TRANSFER FROM THE OWNER TO A NEW STUB ADDRESS
      const newBuyerAddress = 'returned-name-buyer-'.padEnd(43, '0');

      const timePassed = 60 * 1000; // 1 minute
      const newBuyTimestamp = returnedName.startTimestamp + timePassed; // same as the original interval but 1 minute after the returnedName has started

      const expectedPremiumMultiplier =
        50 * (1 - timePassed / returnedNamesPeriod);
      const expectedPurchasePrice = Math.floor(
        basePermabuyPrice * expectedPremiumMultiplier,
      );
      const transferMemory = await transfer({
        recipient: newBuyerAddress,
        quantity: expectedPurchasePrice,
        memory: releaseNameResult.Memory,
      });

      const { result: newBuyResult } = await buyRecord({
        from: newBuyerAddress,
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: transferMemory,
        timestamp: newBuyTimestamp,
      });

      // should send three messages including a Buy-Name-Notice and a Debit-Notice
      assert.equal(newBuyResult.Messages.length, 2);

      // should send a buy record notice
      const buyRecordNoticeTag = newBuyResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Buy-Name-Notice',
      );

      assert.ok(buyRecordNoticeTag);

      // expect the target tag to be the bidder
      assert.equal(newBuyResult.Messages?.[0]?.Target, newBuyerAddress);

      const expectedRecord = {
        processId,
        purchasePrice: expectedPurchasePrice,
        startTimestamp: newBuyTimestamp,
        undernameLimit: 10,
        type: 'permabuy',
        baseRegistrationFee: 500000000,
        returnedName: {
          initiator: 'ant-owner-000000000000000000000000000000000',
          rewardForInitiator: Math.floor(expectedPurchasePrice * 0.5),
          rewardForProtocol: Math.ceil(expectedPurchasePrice * 0.5),
        },
        remainingBalance: 0,
      };

      const expectedRewardForInitiator = Math.floor(
        expectedPurchasePrice * 0.5,
      );
      const expectedRewardForProtocol =
        expectedPurchasePrice - expectedRewardForInitiator;

      // assert the data response contains the record
      const buyRecordNoticeData = JSON.parse(newBuyResult.Messages?.[0]?.Data);
      assert.deepEqual(buyRecordNoticeData, {
        name: 'test-name',
        ...expectedRecord,
      });

      // should send a credit notice
      const creditNoticeTag = newBuyResult.Messages?.[1]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Credit-Notice',
      );
      assert.ok(creditNoticeTag);

      // expect the target to be to the initiator
      assert.equal(newBuyResult.Messages?.[1]?.Target, initiator);

      // assert the data response contains the record
      const creditNoticeData = JSON.parse(newBuyResult.Messages?.[1]?.Data);
      assert.deepEqual(creditNoticeData, {
        record: {
          processId,
          purchasePrice: expectedPurchasePrice,
          startTimestamp: newBuyTimestamp,
          type: 'permabuy',
          undernameLimit: 10,
        },
        buyer: newBuyerAddress,
        rewardForInitiator: expectedRewardForInitiator,
        rewardForProtocol: expectedRewardForProtocol,
        name: 'test-name',
      });

      // should add the record to the registry
      const recordResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: newBuyTimestamp,
        },
        memory: newBuyResult.Memory,
      });

      const record = JSON.parse(recordResult.Messages?.[0]?.Data);
      assert.deepEqual(record, {
        processId,
        purchasePrice: expectedPurchasePrice,
        startTimestamp: newBuyTimestamp,
        undernameLimit: 10,
        type: 'permabuy',
      });

      // assert the balance of the initiator and the protocol where updated correctly
      const balancesResult = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balances' }],
          Timestamp: newBuyTimestamp,
        },
        memory: newBuyResult.Memory,
      });

      const expectedProtocolBalance =
        INITIAL_PROTOCOL_BALANCE +
        initialRecord.purchasePrice +
        expectedRewardForProtocol;
      const balances = JSON.parse(balancesResult.Messages[0].Data);

      assert.equal(balances[initiator], expectedRewardForInitiator);
      assert.equal(balances[PROCESS_ID], expectedProtocolBalance);
      assert.equal(balances[newBuyerAddress], 0);
      sharedMemory = balancesResult.Memory;
    });

    const runReturnedNameTest = async ({ fundFrom }) => {
      const { result: buyRecordResult } = await buyRecord({
        from: STUB_ADDRESS,
        name: 'test-name',
        processId: ''.padEnd(43, 'a'),
        type: 'lease',
        years: 1,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      const initialRecord = JSON.parse(buyRecordResult.Messages[0].Data);

      // tick the contract after the lease leaves its grace period
      const futureTimestamp =
        initialRecord.endTimestamp + 60 * 1000 * 60 * 24 * 14 + 1;
      const tickResult = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Tick' }],
          Timestamp: futureTimestamp,
        },
        memory: buyRecordResult.Memory,
      });

      // fetch the returned name
      const returnedNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Returned-Name' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: futureTimestamp,
        },
        memory: tickResult.Memory,
      });
      // assert no error tag
      const returnedNameErrorTag = returnedNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );

      assert.equal(returnedNameErrorTag, undefined);
      const returnedName = JSON.parse(returnedNameResult.Messages?.[0]?.Data);
      assert.deepEqual(returnedName, {
        name: 'test-name',
        initiator: PROCESS_ID,
        startTimestamp: futureTimestamp,
        endTimestamp: futureTimestamp + returnedNamesPeriod,
        premiumMultiplier: 50,
      });

      // should list the name from returned-names
      const returnedNamesResult = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Returned-Names' }],
          Timestamp: futureTimestamp,
        },
        memory: returnedNameResult.Memory,
      });
      const { items, hasMore, cursor, sortBy, sortOrder, totalItems } =
        JSON.parse(returnedNamesResult.Messages[0].Data);
      assert.ok(Array.isArray(items));
      assert.ok(hasMore === false);
      assert.ok(cursor === undefined);
      assert.equal(sortBy, 'endTimestamp');
      assert.equal(sortOrder, 'desc');
      assert.equal(totalItems, 1);

      // // TRANSFER FROM THE OWNER TO A NEW STUB ADDRESS
      const years = 3;
      const bidderAddress = 'returned-name-buyer-'.padEnd(43, '0');
      const timeIntoReturnedNamePeriod = 60 * 60 * 1000 * 24 * 7; // 7 days into the period
      const bidTimestamp = futureTimestamp + timeIntoReturnedNamePeriod;

      const expectedPremiumMultiplier =
        50 * (1 - timeIntoReturnedNamePeriod / returnedNamesPeriod);
      const expectedPurchasePrice = Math.floor(
        baseLeasePriceFor9CharNameFor3Years * expectedPremiumMultiplier,
      );

      const transferMemory = await transfer({
        recipient: bidderAddress,
        quantity: expectedPurchasePrice,
        memory: tickResult.Memory,
        timestamp: bidTimestamp,
      });

      let memoryToUse = transferMemory;
      if (fundFrom === 'stakes') {
        // Stake the bidder's balance
        const stakeResult = await setUpStake({
          memory: memoryToUse,
          transferQty: 0,
          stakeQty: expectedPurchasePrice,
          stakerAddress: bidderAddress,
          timestamp: bidTimestamp,
        });
        memoryToUse = stakeResult.memory;
      }

      const processId = 'new-name-owner-'.padEnd(43, '1');
      const { result: buyReturnedNameResult } = await buyRecord({
        from: bidderAddress,
        fundFrom,
        name: 'test-name',
        processId,
        type: 'lease',
        years: 3,
        timestamp: bidTimestamp,
        memory: memoryToUse,
      });

      // should send three messages including a Buy-Name-Notice and a Debit-Notice
      assert.equal(buyReturnedNameResult.Messages.length, 2);

      // should send a buy record notice
      const buyRecordNoticeTag =
        buyReturnedNameResult.Messages?.[0]?.Tags?.find(
          (tag) => tag.name === 'Action' && tag.value === 'Buy-Name-Notice',
        );

      assert.ok(buyRecordNoticeTag);

      // expect the target tag to be the bidder
      assert.equal(buyReturnedNameResult.Messages?.[0]?.Target, bidderAddress);

      const expectedRecord = {
        processId,
        purchasePrice: expectedPurchasePrice,
        startTimestamp: bidTimestamp,
        endTimestamp: bidTimestamp + 60 * 60 * 1000 * 24 * 365 * 3,
        undernameLimit: 10,
        type: 'lease',
      };
      const expectedFundingResults = {
        fundingPlan: {
          address: bidderAddress,
          balance: fundFrom === 'stakes' ? 0 : expectedPurchasePrice,
          shortfall: 0,
          stakes:
            fundFrom === 'stakes'
              ? {
                  [STUB_OPERATOR_ADDRESS]: {
                    delegatedStake: expectedPurchasePrice,
                    vaults: [],
                  },
                }
              : [],
        },
        fundingResult: {
          newWithdrawVaults: [],
          totalFunded: expectedPurchasePrice,
        },
      };
      // the protocol gets the entire bid amount
      const expectedRewardForProtocol = expectedPurchasePrice;

      // assert the data response contains the record
      const buyRecordNoticeData = JSON.parse(
        buyReturnedNameResult.Messages?.[0]?.Data,
      );
      assert.deepEqual(buyRecordNoticeData, {
        ...expectedRecord,
        ...(fundFrom === 'stakes' ? expectedFundingResults : {}),
        ...{
          name: 'test-name',
          returnedName: {
            initiator: PROCESS_ID,
            rewardForInitiator: 0,
            rewardForProtocol: expectedPurchasePrice,
          },
          remainingBalance: 0,
          baseRegistrationFee: 500000000,
        },
      });

      // should send a credit notice
      const creditNoticeTag = buyReturnedNameResult.Messages?.[1]?.Tags?.find(
        (tag) => tag.name === 'Action' && tag.value === 'Credit-Notice',
      );
      assert.ok(creditNoticeTag);

      // expect the target to be to the protocol balance
      assert.equal(buyReturnedNameResult.Messages?.[1]?.Target, PROCESS_ID);

      // assert the data response contains the record
      const creditNoticeData = JSON.parse(
        buyReturnedNameResult.Messages?.[1]?.Data,
      );
      assert.deepEqual(creditNoticeData, {
        record: expectedRecord,
        buyer: bidderAddress,
        rewardForInitiator: 0,
        rewardForProtocol: expectedRewardForProtocol,
        name: 'test-name',
      });

      // should add the record to the registry
      const recordResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Record' },
            { name: 'Name', value: 'test-name' },
          ],
          Timestamp: bidTimestamp,
        },
        memory: buyReturnedNameResult.Memory,
      });

      const record = JSON.parse(recordResult.Messages?.[0]?.Data);
      assert.deepEqual(record, { ...expectedRecord, type: 'lease' });

      // assert the balance of the initiator and the protocol where updated correctly
      const balancesResult = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balances' }],
          Timestamp: bidTimestamp,
        },
        memory: buyReturnedNameResult.Memory,
      });

      const expectedProtocolBalance =
        INITIAL_PROTOCOL_BALANCE +
        initialRecord.purchasePrice +
        expectedRewardForProtocol;
      const balances = JSON.parse(balancesResult.Messages[0].Data);
      assert.equal(balances[PROCESS_ID], expectedProtocolBalance);
      assert.equal(balances[bidderAddress], 0);
      return balancesResult.Memory;
    };

    it('should create a lease expiration initiated returned name and accept buy records for it', async () => {
      sharedMemory = await runReturnedNameTest({});
    });

    it('should create a lease expiration initiated returned name and accept a buy record funded by stakes', async () => {
      sharedMemory = await runReturnedNameTest({ fundFrom: 'stakes' });
    });
  });

  describe('Returned Name Premium', () => {
    it('should compute the correct premiums of returned names at a specific intervals', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const initiator = 'ant-owner-'.padEnd(43, '0'); // owner of the ANT at the time of release
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: sharedMemory,
      });

      const releasedTimestamp = STUB_TIMESTAMP;

      const releaseNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Release-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Initiator', value: initiator }, // simulate who the owner is of the ANT process when sending the message
          ],
          From: processId,
          Owner: processId,
          Timestamp: releasedTimestamp,
        },
        memory: buyRecordResult.Memory,
      });

      // assert no error tag
      const releaseNameErrorTag = releaseNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.equal(releaseNameErrorTag, undefined);

      const tokenCostForReturnedName = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Buy-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
          ],
          Timestamp: releasedTimestamp,
        },
        memory: releaseNameResult.Memory,
      });

      const returnedNameTokenCost = JSON.parse(
        tokenCostForReturnedName.Messages?.[0]?.Data,
      );

      const expectedStartPrice = Math.floor(
        baseLeasePriceFor9CharNameFor1Year * 50,
      );
      assert.equal(returnedNameTokenCost, expectedStartPrice);

      const tokenCostResultForReturnedNameHalfwayThroughPeriod = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Buy-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
          ],
          Timestamp: releasedTimestamp + returnedNamesPeriod / 2,
        },
        memory: releaseNameResult.Memory,
      });

      const tokenCostForReturnedNameHalfwayThroughPeriod = JSON.parse(
        tokenCostResultForReturnedNameHalfwayThroughPeriod.Messages?.[0]?.Data,
      );
      const expectedHalfwayPrice = Math.floor(
        baseLeasePriceFor9CharNameFor1Year * 25,
      );
      assert.equal(
        tokenCostForReturnedNameHalfwayThroughPeriod,
        expectedHalfwayPrice,
      );

      const tokenCostResultForReturnedNameAfterThePeriod = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Token-Cost' },
            { name: 'Intent', value: 'Buy-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Purchase-Type', value: 'lease' },
            { name: 'Years', value: '1' },
          ],
          Timestamp: releasedTimestamp + returnedNamesPeriod + 1,
        },
        memory: releaseNameResult.Memory,
      });

      const tokenCostForReturnedNameAfterThePeriod = JSON.parse(
        tokenCostResultForReturnedNameAfterThePeriod.Messages?.[0]?.Data,
      );
      const expectedFloorPrice = baseLeasePriceFor9CharNameFor1Year;
      assert.equal(tokenCostForReturnedNameAfterThePeriod, expectedFloorPrice);
      sharedMemory = tokenCostResultForReturnedNameAfterThePeriod.Memory;
    });
  });

  describe('Reassign-Name', () => {
    it('should reassign an arns name to a new process id', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: sharedMemory,
      });

      const reassignNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
          ],
          From: processId,
          Owner: processId,
        },
        memory: buyRecordResult.Memory,
      });

      assert.equal(reassignNameResult.Messages?.[0]?.Target, processId);
      sharedMemory = reassignNameResult.Memory;
    });

    it('should reassign an arns name to a new process id with initiator', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: sharedMemory,
      });

      const reassignNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
            { name: 'Initiator', value: STUB_MESSAGE_ID },
          ],
          From: processId,
          Owner: processId,
        },
        memory: buyRecordResult.Memory,
      });

      assert.equal(reassignNameResult.Messages?.[0]?.Target, processId);
      assert.equal(reassignNameResult.Messages?.[1]?.Target, STUB_MESSAGE_ID); // Check for the message sent to the initiator
      sharedMemory = reassignNameResult.Memory;
    });

    it('should not reassign an arns name with invalid ownership', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: sharedMemory,
      });

      const reassignNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: ''.padEnd(43, 'b') },
          ],
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
        },
        memory: buyRecordResult.Memory,
        shouldAssertNoResultError: false,
      });

      // assert error
      const reassignNameErrorTag = reassignNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.ok(reassignNameErrorTag, 'Error tag should be present');
      sharedMemory = reassignNameResult.Memory;
    });

    it('should not reassign an arns name with invalid new process id', async () => {
      // buy the name first
      const processId = ''.padEnd(43, 'a');
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        type: 'permabuy',
        memory: sharedMemory,
      });

      const reassignNameResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Reassign-Name' },
            { name: 'Name', value: 'test-name' },
            { name: 'Process-Id', value: 'this is an invalid process id' },
          ],
          From: processId,
          Owner: processId,
        },
        memory: buyRecordResult.Memory,
        shouldAssertNoResultError: false,
      });

      // assert error
      const reassignNameErrorTag = reassignNameResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.ok(reassignNameErrorTag, 'Error tag should be present');
      sharedMemory = reassignNameResult.Memory;
    });
  });

  describe('Paginated-Records', () => {
    it('should paginate records correctly', async () => {
      // buy 3 records
      let lastTimestamp = STUB_TIMESTAMP;
      let buyRecordsMemory = sharedMemory; // updated after each purchase
      const recordsCount = 3;
      for (let i = 0; i < recordsCount; i++) {
        const { result: buyRecordsResult } = await buyRecord({
          name: `test-name-${i}`,
          processId: ''.padEnd(43, `${i}`),
          type: 'lease',
          years: 1,
          timestamp: lastTimestamp + i * 1000,
          fundFrom: 'any',
          memory: buyRecordsMemory,
        });
        buyRecordsMemory = buyRecordsResult.Memory;
        lastTimestamp = lastTimestamp + i * 1000;
      }

      // call the paginated records handler repeatedly until all records are fetched
      let paginatedRecords = [];
      let cursor = undefined;
      while (true) {
        const result = await handle({
          options: {
            Tags: [
              { name: 'Action', value: 'Paginated-Records' },
              { name: 'Cursor', value: cursor },
              { name: 'Limit', value: 1 },
            ],
            Timestamp: lastTimestamp,
          },
          memory: buyRecordsMemory,
        });
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
      sharedMemory = buyRecordsMemory;
    });
  });

  describe('Cost-Details', () => {
    const joinedGateway = 'joined-unique-gateway-'.padEnd(43, '0');
    const nonEligibleAddress = 'non-eligible-address'.padEnd(43, '1');

    const firstEpochTimestamp = 1719900000000;
    const afterDistributionTimestamp =
      firstEpochTimestamp + 1000 * 60 * 60 * 24;

    let arnsDiscountMemory;
    before(async () => {
      // add a gateway and distribute to increment stats
      const { memory: join1Memory } = await joinNetwork({
        memory: sharedMemory,
        address: joinedGateway,
        quantity: 300_000_000_000,
        timestamp: firstEpochTimestamp - 1000 * 60 * 60 * 24 * 365, // 365 days before the first epoch
      });

      const { result: firstTickAndDistribution } = await tick({
        memory: join1Memory,
        timestamp: afterDistributionTimestamp,
      });

      // assert our gateway has weights making it eligible for ArNS discount
      const gateway = await getGateway({
        memory: firstTickAndDistribution.Memory,
        address: joinedGateway,
        timestamp: afterDistributionTimestamp,
      });
      assert.equal(gateway.status, 'joined');
      assert(
        gateway.weights.tenureWeight >= 1,
        'Gateway should have a tenure weight greater than or equal to 1',
      );
      assert(
        gateway.weights.gatewayPerformanceRatio >= 1,
        'Gateway should have a gateway reward ratio weight greater than or equal to 1',
      );

      // add funds for the non-eligible gateway
      const transferMemory = await transfer({
        recipient: nonEligibleAddress,
        quantity: 200_000_000_000,
        timestamp: afterDistributionTimestamp,
        memory: firstTickAndDistribution.Memory,
      });
      arnsDiscountMemory = transferMemory;
    });

    it('should return discounted cost for a buy record by an eligible gateway', async () => {
      const tokenCostResult = await getTokenCost({
        from: joinedGateway,
        name: 'test-name',
        intent: 'Buy-Name',
        years: 1,
        memory: arnsDiscountMemory,
        timestamp: afterDistributionTimestamp,
      });

      assert.equal(
        tokenCostResult.tokenCost,
        baseLeasePriceFor9CharNameFor1Year * 0.8,
      );
      assert.deepEqual(tokenCostResult.discounts, [
        {
          discountTotal: baseLeasePriceFor9CharNameFor1Year * 0.2,
          multiplier: 0.2,
          name: 'ArNS Discount',
        },
      ]);
    });

    it('should return the correct cost for a buy record by a non-eligible gateway', async () => {
      const tokenCostResult = await getTokenCost({
        from: nonEligibleAddress,
        name: 'test-name',
        intent: 'Buy-Name',
        years: 1,
        memory: arnsDiscountMemory,
        timestamp: afterDistributionTimestamp,
      });
      assertNoResultError(tokenCostResult);
      assert.equal(
        tokenCostResult.tokenCost,
        baseLeasePriceFor9CharNameFor1Year,
      );
      assert.deepEqual(tokenCostResult.discounts, []);
    });

    describe('for an existing record', () => {
      let buyRecordMemory;
      const baseFeeForName = 500000000; // base fee for a 10 character name
      const buyRecordTimestamp = afterDistributionTimestamp;
      before(async () => {
        const tokenSupplyMemory = await totalTokenSupply({
          memory: startMemory,
        });

        const { result: buyRecordResult } = await buyRecord({
          memory: tokenSupplyMemory,
          name: 'great-name',
          processId: ''.padEnd(43, 'a'),
          type: 'lease',
          years: 1,
          timestamp: buyRecordTimestamp,
        });
        buyRecordMemory = buyRecordResult.Memory;
      });

      it('returns the correct cost details for a returned name', async () => {
        // Tick to the end of the lease period and grace period
        const oneYearMs = 1000 * 60 * 60 * 24 * 365;
        const twoWeeksMs = 1000 * 60 * 60 * 24 * 14;
        const returnedNameTimestamp =
          buyRecordTimestamp + oneYearMs + twoWeeksMs + 1; // 1 year and 2 weeks after the buy record
        const tickResult = await tick({
          timestamp: returnedNameTimestamp,
          memory: buyRecordMemory,
        });

        const tokenCostResult = await getTokenCost({
          from: joinedGateway,
          name: 'great-name',
          intent: 'Buy-Name',
          years: 1,
          processId: ''.padEnd(43, 'a'),
          memory: tickResult.Memory,
          timestamp: returnedNameTimestamp,
        });
        assert.equal(tokenCostResult.tokenCost, 600000000); // 50 times the base fee for a 10 character name
      });

      describe('extending the lease', () => {
        const extendLeaseTimestamp = buyRecordTimestamp + 1;
        const baseFeeForName = 500000000; // base fee for a 10 character name
        const baseLeaseOneYearExtensionPrice = baseFeeForName * 0.2; // 1 year extension at 20% for the year

        it('should apply the discount to extending the lease for an eligible gateway', async () => {
          const tokenCostResult = await getTokenCost({
            from: joinedGateway,
            name: 'great-name',
            intent: 'Extend-Lease',
            years: 1,
            memory: buyRecordMemory,
            timestamp: extendLeaseTimestamp,
          });
          assert.equal(
            tokenCostResult.tokenCost,
            baseLeaseOneYearExtensionPrice * 0.8,
          );
          assert.deepEqual(tokenCostResult.discounts, [
            {
              discountTotal: baseLeaseOneYearExtensionPrice * 0.2,
              multiplier: 0.2,
              name: 'ArNS Discount',
            },
          ]);
        });

        it('should not apply the discount to extending the lease for a non-eligible gateway', async () => {
          const tokenCostResult = await getTokenCost({
            from: nonEligibleAddress,
            name: 'great-name',
            intent: 'Extend-Lease',
            memory: buyRecordMemory,
            timestamp: extendLeaseTimestamp,
          });
          assert.equal(
            tokenCostResult.tokenCost,
            baseLeaseOneYearExtensionPrice,
          );
          assert.deepEqual(tokenCostResult.discounts, []);
        });

        it('balances should be updated when the extend lease action is performed', async () => {
          const eligibleGatewayBalanceBefore = await getBalance({
            memory: buyRecordMemory,
            timestamp: extendLeaseTimestamp - 1,
            address: joinedGateway,
          });
          const nonEligibleGatewayBalanceBefore = await getBalance({
            memory: buyRecordMemory,
            timestamp: extendLeaseTimestamp - 1,
            address: nonEligibleAddress,
          });

          const eligibleGatewayResult = await getTokenCost({
            from: joinedGateway,
            name: 'great-name',
            intent: 'Extend-Lease',
            years: 1,
            memory: buyRecordMemory,
            timestamp: extendLeaseTimestamp,
          });
          const nonEligibleGatewayResult = await getTokenCost({
            from: nonEligibleAddress,
            name: 'great-name',
            intent: 'Extend-Lease',
            years: 1,
            memory: buyRecordMemory,
            timestamp: extendLeaseTimestamp,
          });

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
          sharedMemory = nonEligibleGatewayResult.Memory;
        });

        describe('upgrading the lease to a permabuy', () => {
          const basePermabuyPrice = baseFeeForName + baseFeeForName * 0.2 * 20; // 20 years of annual renewal fees

          it('should apply the discount to upgrading the lease to a permabuy for an eligible gateway', async () => {
            const tokenCostResult = await getTokenCost({
              from: joinedGateway,
              name: 'great-name',
              intent: 'Upgrade-Name',
              memory: buyRecordMemory,
              timestamp: afterDistributionTimestamp,
            });
            assert.equal(tokenCostResult.tokenCost, basePermabuyPrice * 0.8);
            assert.deepEqual(tokenCostResult.discounts, [
              {
                discountTotal: basePermabuyPrice * 0.2,
                multiplier: 0.2,
                name: 'ArNS Discount',
              },
            ]);
          });

          it('should not apply the discount to increasing the undername limit for a non-eligible gateway', async () => {
            const tokenCostResult = await getTokenCost({
              from: nonEligibleAddress,
              name: 'great-name',
              intent: 'Upgrade-Name',
              memory: buyRecordMemory,
              timestamp: afterDistributionTimestamp,
            });
            assert.equal(tokenCostResult.tokenCost, basePermabuyPrice);
            assert.deepEqual(tokenCostResult.discounts, []);
          });
        });
      });

      describe('increasing the undername limit', () => {
        const increaseUndernameQty = 20;
        const undernameCostForName =
          baseFeeForName * 0.001 * increaseUndernameQty;

        it('should apply the discount to increasing the undername limit for an eligible gateway', async () => {
          const tokenCostResult = await getTokenCost({
            from: joinedGateway,
            name: 'great-name',
            intent: 'Increase-Undername-Limit',
            quantity: increaseUndernameQty,
            memory: buyRecordMemory,
            timestamp: afterDistributionTimestamp,
          });
          assert.deepEqual(tokenCostResult.discounts, [
            {
              discountTotal: undernameCostForName * 0.2,
              multiplier: 0.2,
              name: 'ArNS Discount',
            },
          ]);
          assert.equal(tokenCostResult.tokenCost, undernameCostForName * 0.8);
        });

        it('should not apply the discount to increasing the undername limit for a non-eligible gateway', async () => {
          const tokenCostResult = await getTokenCost({
            from: nonEligibleAddress,
            name: 'great-name',
            intent: 'Increase-Undername-Limit',
            quantity: increaseUndernameQty,
            memory: buyRecordMemory,
            timestamp: afterDistributionTimestamp,
          });
          assertNoResultError(tokenCostResult);
          assert.equal(tokenCostResult.tokenCost, undernameCostForName);
          assert.deepEqual(tokenCostResult.discounts, []);
        });
      });
    });
  });

  describe('Reserved-Names', () => {
    it('should paginate reserved names', async () => {
      const result = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Reserved-Names' }],
        },
      });
      const { items, hasMore, cursor, sortBy, sortOrder, totalItems } =
        JSON.parse(result.Messages[0].Data);
      assert.ok(Array.isArray(items));
      assert.ok(hasMore === false);
      assert.ok(cursor === undefined);
      assert.equal(sortBy, 'name');
      assert.equal(sortOrder, 'desc');
      assert.equal(totalItems, 0);
      sharedMemory = result.Memory;
    });
  });
});
