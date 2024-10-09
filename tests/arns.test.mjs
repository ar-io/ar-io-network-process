import { createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  PROCESS_ID,
  PROCESS_OWNER,
  STUB_ADDRESS,
  INITIAL_PROTOCOL_BALANCE,
  STUB_MESSAGE_ID,
} from '../tools/constants.mjs';

// EIP55-formatted test address
const testEthAddress = '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa';

describe('ArNS', async () => {
  const { handle: originalHandle, memory: startMemory } =
    await createAosLoader();

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

  const runBuyRecord = async ({
    sender = STUB_ADDRESS,
    processId = ''.padEnd(43, 'a'),
    name = 'test-name',
    mem = startMemory,
  }) => {
    if (sender != PROCESS_OWNER) {
      // transfer from the owner to the sender
      const transferResult = await handle({
        From: PROCESS_OWNER,
        Owner: PROCESS_OWNER,
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
          { name: 'Name', value: name },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: processId },
        ],
      },
      mem,
    );

    const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);
    const buyRecordEvent = JSON.parse(
      buyRecordResult.Output.data.split('\n')[1],
    );

    // Fields based on timestamps will be unstable for testing, but verify their type
    assert.equal('number', typeof buyRecordEvent.Timestamp);
    assert.equal('number', typeof buyRecordEvent['Epoch-Index']);
    assert.equal('number', typeof buyRecordEvent['Start-Timestamp']);
    assert.equal('number', typeof buyRecordEvent['End-Timestamp']);
    delete buyRecordEvent.Timestamp;
    delete buyRecordEvent['Epoch-Index'];
    delete buyRecordEvent['Start-Timestamp'];
    delete buyRecordEvent['End-Timestamp'];
    const expectedRemainingBalance = {
      '0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa': 0,
      [PROCESS_OWNER]: 950000000000000,
      [PROCESS_ID]: 50000600000000,
      [sender]: 0,
    };
    assert.deepEqual(buyRecordEvent, {
      _e: 1,
      'Purchase-Type': 'lease',
      'DF-Purchases-This-Period': 1,
      'DF-Revenue-This-Period': 600000000,
      'DF-Current-Demand-Factor': 1,
      Action: 'Buy-Record',
      'Name-Length': 9,
      'Purchase-Price': 600000000,
      'Base-Registration-Fee': 500000000,
      'DF-Current-Period': 1,
      'DF-Trailing-Period-Revenues': [0, 0, 0, 0, 0, 0],
      'DF-Trailing-Period-Purchases': [0, 0, 0, 0, 0, 0, 0],
      Cron: false,
      Cast: false,
      'Undername-Limit': 10,
      Name: name,
      Years: '1',
      'DF-Consecutive-Periods-With-Min-Demand-Factor': 0,
      'Process-Id': processId,
      From: sender,
      'From-Formatted': sender,
      'Message-Id': STUB_MESSAGE_ID,
      'Records-Count': 1,
      'Protocol-Balance': expectedRemainingBalance[PROCESS_ID],
      'Reserved-Records-Count': 0,
      'Remaining-Balance': expectedRemainingBalance[sender],
    });

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
      purchasePrice: 600000000,
      startTimestamp: buyRecordData.startTimestamp,
      endTimestamp: buyRecordData.endTimestamp,
      type: 'lease',
      undernameLimit: 10,
    });

    return {
      record,
      mem: buyRecordResult.Memory,
    };
  };

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
    const assertIncreaseUndername = async (sender) => {
      let mem = startMemory;

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
    await assertIncreaseUndername(STUB_ADDRESS);
    await assertIncreaseUndername(testEthAddress);
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

  it('should get registration fees', async () => {
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

  it('should create an auction on a record owned by a process id, accept a bid and add the record to the registry', async () => {
    // buy the name first
    const processId = ''.padEnd(43, 'a');
    const { mem, record: initialRecord } = await runBuyRecord({
      sender: STUB_ADDRESS,
      processId,
    });

    const releaseNameResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Release-Name' },
          { name: 'Name', value: 'test-name' },
          { name: 'Initiator', value: 'test-owner-of-ant' }, // simulate who the owner is of the ANT process when sending the message
        ],
        From: processId,
        Owner: processId,
      },
      mem,
    );

    // assert no error tag
    const releaseNameErrorTag = releaseNameResult.Messages[0].Tags.find(
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
    const auctionErrorTag = auctionResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Error',
    );

    assert.equal(auctionErrorTag, undefined);
    const auction = JSON.parse(auctionResult.Messages[0].Data);
    const expectedStartPrice = 30000000000;
    const expectedFloorPrice = 600000000;
    assert.deepEqual(auction, {
      name: 'test-name',
      type: 'lease',
      startPrice: expectedStartPrice,
      floorPrice: expectedFloorPrice,
      years: 1,
      initiator: 'test-owner-of-ant',
      startTimestamp: auction.startTimestamp,
      endTimestamp: auction.endTimestamp,
      currentPrice: auction.startPrice,
    });

    // TRANSFER FROM THE OWNER TO THE STUB ADDRESS
    const transferResult = await handle(
      {
        From: PROCESS_OWNER,
        Owner: PROCESS_OWNER,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: STUB_ADDRESS },
          { name: 'Quantity', value: expectedStartPrice },
          { name: 'Cast', value: true },
        ],
      },
      releaseNameResult.Memory,
    );

    // assert no error in the transfer
    const transferErrorTag = transferResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );

    const bidTimestamp = auction.startTimestamp + 60 * 1000; // same as the original interval but 1 minute after the auction has started
    const submitBidResult = await handle(
      {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
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
    const buyRecordNoticeTag = submitBidResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Action' && tag.value === 'Buy-Record-Notice',
    );

    assert.ok(buyRecordNoticeTag);

    // should send a debit notice
    const debitNoticeTag = submitBidResult.Messages[1].Tags.find(
      (tag) => tag.name === 'Action' && tag.value === 'Debit-Notice',
    );
    assert.ok(debitNoticeTag);

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

    const expectedEndTimestamp = bidTimestamp + 60 * 1000 * 60 * 24 * 365;
    const expectedRewardForInitiator = 30000000000 * 0.5;
    const expectedRewardForProtocol = 30000000000 - expectedRewardForInitiator;

    const record = JSON.parse(recordResult.Messages[0].Data);
    assert.deepEqual(record, {
      processId,
      purchasePrice: 30000000000,
      startTimestamp: bidTimestamp,
      endTimestamp: expectedEndTimestamp,
      type: 'lease',
      undernameLimit: 10,
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
    assert.equal(balances['test-owner-of-ant'], expectedRewardForInitiator);
    assert.equal(balances[PROCESS_ID], expectedProtocolBalance);
  });

  // TODO: add several error scenarios
});
