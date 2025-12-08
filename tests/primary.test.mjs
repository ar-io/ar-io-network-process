import {
  assertNoResultError,
  buyRecord,
  getDemandFactorInfo,
  handle,
  parseEventsFromResult,
  setUpStake,
  startMemory,
  totalTokenSupply,
  transfer,
} from './helpers.mjs';
import assert from 'assert';
import { describe, it, beforeEach, afterEach } from 'node:test';
import {
  STUB_ADDRESS,
  STUB_TIMESTAMP,
  STUB_PROCESS_ID,
} from '../tools/constants.mjs';
import { assertNoInvariants } from './invariants.mjs';

describe('primary names', function () {
  let sharedMemory;
  let endingMemory;
  beforeEach(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    sharedMemory = totalTokenSupplyMemory;
  });

  afterEach(async () => {
    await assertNoInvariants({
      timestamp: STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 365,
      memory: endingMemory,
    });
  });

  const requestPrimaryName = async ({
    name,
    caller,
    timestamp,
    fundFrom,
    memory,
  }) => {
    // give it balance if not stub address
    if (caller !== STUB_ADDRESS) {
      const transferMemory = await transfer({
        recipient: caller,
        quantity: 100000000, // primary name cost
        memory,
        timestamp,
      });
      memory = transferMemory;
    }
    const requestPrimaryNameResult = await handle({
      options: {
        From: caller,
        Owner: caller,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Request-Primary-Name' },
          { name: 'Name', value: name },
          ...(fundFrom ? [{ name: 'Fund-From', value: fundFrom }] : []),
        ],
      },
      memory,
    });
    return {
      result: requestPrimaryNameResult,
      memory: requestPrimaryNameResult.Memory,
    };
  };

  const getPrimaryNameRequest = async ({ initiator, memory, timestamp }) => {
    const getPrimaryNameRequestResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Primary-Name-Request' },
          { name: 'Initiator', value: initiator },
        ],
      },
      memory,
      timestamp,
    });
    return {
      result: getPrimaryNameRequestResult,
      memory: getPrimaryNameRequestResult.Memory,
    };
  };

  const approvePrimaryNameRequest = async ({
    name,
    caller,
    recipient,
    timestamp,
    memory,
  }) => {
    const approvePrimaryNameRequestResult = await handle({
      options: {
        From: caller,
        Owner: caller,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Approve-Primary-Name-Request' },
          { name: 'Name', value: name },
          { name: 'Recipient', value: recipient },
        ],
      },
      memory,
    });
    return {
      result: approvePrimaryNameRequestResult,
      memory: approvePrimaryNameRequestResult.Memory,
    };
  };

  const removePrimaryNames = async ({
    names,
    caller,
    memory,
    timestamp = STUB_TIMESTAMP,
    notifyOwners = false,
  }) => {
    const removePrimaryNamesResult = await handle({
      options: {
        From: caller,
        Owner: caller,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Remove-Primary-Names' },
          { name: 'Names', value: names.join(',') },
          { name: 'Notify-Owners', value: notifyOwners ? 'true' : 'false' },
        ],
      },
      memory,
    });
    return {
      result: removePrimaryNamesResult,
      memory: removePrimaryNamesResult.Memory,
    };
  };

  const getPrimaryNameForAddress = async ({
    address,
    memory,
    timestamp = STUB_TIMESTAMP,
    shouldAssertNoResultError = true,
  }) => {
    const getPrimaryNameResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Address', value: address },
        ],
        Timestamp: timestamp,
      },
      memory,
      shouldAssertNoResultError,
    });
    return {
      result: getPrimaryNameResult,
      memory: getPrimaryNameResult.Memory,
    };
  };

  const getOwnerOfPrimaryName = async ({
    name,
    memory,
    timestamp = STUB_TIMESTAMP,
  }) => {
    const getOwnerResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Name', value: name },
        ],
        Timestamp: timestamp,
      },
      memory,
    });
    return {
      result: getOwnerResult,
      memory: getOwnerResult.Memory,
    };
  };

  const validPrimaryNames = [
    '1',
    'a',
    '1a',
    '1-1',
    'a-1',
    '1-a',
    ''.padEnd(51, '1'),
    ''.padEnd(51, 'a'),
    // undernames
    '1_test',
    '1234_test',
    'fsakdjhflkasjdhflkaf_test',
    ''.padEnd(61, '1') + '_t',
    ''.padEnd(61, 'a') + '_t',
    'a_' + ''.padEnd(51, '1'),
    '9_' + ''.padEnd(51, 'z'),
  ];

  for (const validPrimaryName of validPrimaryNames) {
    it(`should allow creating and approving a primary name for an existing base name (${validPrimaryName}) when the recipient is not the base name owner and is funding from stakes`, async function () {
      const processId = ''.padEnd(43, 'a');
      const recipient = ''.padEnd(43, 'b');
      const requestTimestamp = 1234567890;
      const { result: buyRecordResult } = await buyRecord({
        name: validPrimaryName.includes('_')
          ? validPrimaryName.split('_')[1]
          : validPrimaryName,
        processId,
        timestamp: requestTimestamp,
        memory: sharedMemory,
        type: 'permabuy',
      });

      const buyRecordData = JSON.parse(buyRecordResult.Messages[0].Data);

      const stakeResult = await setUpStake({
        memory: buyRecordResult.Memory,
        stakerAddress: recipient,
        transferQty: 550000000,
        stakeQty: 500000000,
        timestamp: requestTimestamp,
      });

      const { result: requestPrimaryNameResult } = await requestPrimaryName({
        name: validPrimaryName,
        caller: recipient,
        timestamp: requestTimestamp,
        memory: stakeResult.memory,
        fundFrom: 'stakes',
      });

      const requestPrimaryNameData = JSON.parse(
        requestPrimaryNameResult.Messages[0].Data,
      );

      const parsedEvents = parseEventsFromResult(requestPrimaryNameResult);
      assert.equal(parsedEvents.length, 1);
      assert.deepStrictEqual(parsedEvents[0], {
        _e: 1,
        Action: 'Request-Primary-Name',
        'Base-Name-Owner': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        Cast: false,
        Cron: false,
        'Request-End-Timestamp': 1839367890,
        'Epoch-Index': -5864,
        'FP-Balance': 0,
        'FP-Stakes-Amount': 1000000,
        From: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'From-Formatted': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'Fund-From': 'stakes',
        'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
        Name: validPrimaryName,
        'Request-Start-Timestamp': 1234567890,
        Timestamp: 1234567890,
        'Total-Primary-Name-Requests': 1,
        'Total-Primary-Names': 0,
        'Memory-KiB-Used': parsedEvents[0]['Memory-KiB-Used'],
        'Handler-Memory-KiB-Used': parsedEvents[0]['Handler-Memory-KiB-Used'],
        'Final-Memory-KiB-Used': parsedEvents[0]['Final-Memory-KiB-Used'],
        'DF-Consecutive-Periods-With-Min-Demand-Factor': 0,
        'DF-Trailing-Period-Purchases': [0, 0, 0, 0, 0, 0, 0],
        'DF-Trailing-Period-Revenues': [0, 0, 0, 0, 0, 0, 0],
        'DF-Current-Demand-Factor': 1,
        'DF-Current-Period': 1,
        'DF-Purchases-This-Period': 2,
        'DF-Revenue-This-Period':
          buyRecordData.purchasePrice +
          requestPrimaryNameData.fundingResult.totalFunded,
      });

      const { result: getPrimaryNameRequestResult } =
        await getPrimaryNameRequest({
          initiator: recipient,
          memory: requestPrimaryNameResult.Memory,
          timestamp: requestTimestamp,
        });

      const requestData = JSON.parse(
        getPrimaryNameRequestResult.Messages[0].Data,
      );
      assert.deepStrictEqual(requestData, {
        name: validPrimaryName,
        startTimestamp: 1234567890,
        endTimestamp: 1839367890,
        initiator: recipient,
      });

      const approvedTimestamp = 1234567899;
      const { result: approvePrimaryNameRequestResult } =
        await approvePrimaryNameRequest({
          name: validPrimaryName,
          caller: processId,
          recipient: recipient,
          timestamp: approvedTimestamp,
          memory: requestPrimaryNameResult.Memory,
        });

      assertNoResultError(approvePrimaryNameRequestResult);
      const parsedApproveEvents = parseEventsFromResult(
        approvePrimaryNameRequestResult,
      );
      assert.equal(parsedApproveEvents.length, 1);
      assert.deepStrictEqual(parsedApproveEvents[0], {
        _e: 1,
        Action: 'Approve-Primary-Name-Request',
        Cast: false,
        Cron: false,
        'Epoch-Index': -5864,
        From: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'From-Formatted': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
        Name: validPrimaryName,
        Owner: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        Recipient: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'Request-End-Timestamp': 1839367890,
        'Request-Start-Timestamp': 1234567890,
        'Start-Timestamp': 1234567899,
        Timestamp: 1234567899,
        'Total-Primary-Names': 1,
        'Total-Primary-Name-Requests': 0,
        'Memory-KiB-Used': parsedApproveEvents[0]['Memory-KiB-Used'],
        'Handler-Memory-KiB-Used':
          parsedApproveEvents[0]['Handler-Memory-KiB-Used'],
        'Final-Memory-KiB-Used':
          parsedApproveEvents[0]['Final-Memory-KiB-Used'],
      });

      // there should be messages: one to the ant, one to the owner, and one patch message
      assert.equal(approvePrimaryNameRequestResult.Messages.length, 3);
      assert.equal(
        approvePrimaryNameRequestResult.Messages[0].Target,
        processId,
      );
      assert.equal(
        approvePrimaryNameRequestResult.Messages[1].Target,
        recipient,
      );

      // find the action tag in the messages
      const actionTag = approvePrimaryNameRequestResult.Messages[0].Tags.find(
        (tag) => tag.name === 'Action',
      ).value;
      assert.equal(actionTag, 'Approve-Primary-Name-Request-Notice');

      // the primary name should be set
      const approvedPrimaryNameResult = JSON.parse(
        approvePrimaryNameRequestResult.Messages[0].Data,
      );
      const expectedNewPrimaryName = {
        name: validPrimaryName,
        owner: recipient,
        startTimestamp: approvedTimestamp,
      };
      assert.deepStrictEqual(approvedPrimaryNameResult, {
        newPrimaryName: expectedNewPrimaryName,
        request: {
          endTimestamp: 1839367890,
          name: validPrimaryName,
          startTimestamp: 1234567890,
        },
      });
      const { result: primaryNameForAddressResult } =
        await getPrimaryNameForAddress({
          address: recipient,
          memory: approvePrimaryNameRequestResult.Memory,
          timestamp: approvedTimestamp,
        });

      const primaryNameLookupResult = JSON.parse(
        primaryNameForAddressResult.Messages[0].Data,
      );
      assert.deepStrictEqual(primaryNameLookupResult, {
        ...expectedNewPrimaryName,
        processId,
      });

      // reverse lookup the owner of the primary name
      const { result: ownerOfPrimaryNameResult, memory } =
        await getOwnerOfPrimaryName({
          name: validPrimaryName,
          memory: approvePrimaryNameRequestResult.Memory,
          timestamp: approvedTimestamp,
        });

      const ownerResult = JSON.parse(ownerOfPrimaryNameResult.Messages[0].Data);
      assert.deepStrictEqual(ownerResult, {
        ...expectedNewPrimaryName,
        processId,
      });
      endingMemory = memory;
    });
  }

  it('should immediately approve a primary name for an existing base name when the caller of the request is the base name owner', async function () {
    const processId = ''.padEnd(43, 'a');
    const requestTimestamp = 1234567890;
    const { result: buyRecordResult } = await buyRecord({
      name: 'test-name',
      processId,
      timestamp: requestTimestamp,
      memory: sharedMemory,
      type: 'permabuy',
    });

    const approvalTimestamp = 1234567899;
    const { result: requestPrimaryNameResult } = await requestPrimaryName({
      name: 'test-name',
      caller: processId,
      timestamp: approvalTimestamp,
      memory: buyRecordResult.Memory,
    });

    const demandFactor = await getDemandFactorInfo({
      memory: requestPrimaryNameResult.Memory,
      timestamp: approvalTimestamp,
    });

    assertNoResultError(requestPrimaryNameResult);
    const parsedEvents = parseEventsFromResult(requestPrimaryNameResult);
    assert.equal(parsedEvents.length, 1);
    assert.deepStrictEqual(parsedEvents[0], {
      _e: 1,
      Action: 'Request-Primary-Name',
      'Base-Name-Owner': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      Cast: false,
      Cron: false,
      'Request-End-Timestamp': 1839367899,
      'Epoch-Index': -5864,
      'FP-Balance': 1000000,
      From: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'From-Formatted': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
      Name: 'test-name',
      Owner: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'Request-Start-Timestamp': 1234567899,
      'Start-Timestamp': 1234567899,
      Timestamp: 1234567899,
      'Total-Primary-Name-Requests': 0,
      'Total-Primary-Names': 1,
      'Memory-KiB-Used': parsedEvents[0]['Memory-KiB-Used'],
      'Handler-Memory-KiB-Used': parsedEvents[0]['Handler-Memory-KiB-Used'],
      'Final-Memory-KiB-Used': parsedEvents[0]['Final-Memory-KiB-Used'],
      // validate the demand factor data was updated
      'DF-Consecutive-Periods-With-Min-Demand-Factor': 0,
      'DF-Trailing-Period-Purchases': [0, 0, 0, 0, 0, 0, 0],
      'DF-Trailing-Period-Revenues': [0, 0, 0, 0, 0, 0, 0],
      'DF-Current-Demand-Factor': 1,
      'DF-Current-Period': 1,
      'DF-Purchases-This-Period': 2,
      'DF-Revenue-This-Period': 2001000000, // buy name + request primary name
    });

    // there should be one notice message and two patch messages (primary-names and balances)
    assert.equal(requestPrimaryNameResult.Messages.length, 3);
    assert.equal(requestPrimaryNameResult.Messages[0].Target, processId);

    // find the action tag in the messages
    const actionTag = requestPrimaryNameResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Action',
    ).value;
    assert.equal(actionTag, 'Approve-Primary-Name-Request-Notice');

    // the primary name should be set
    const approvedPrimaryNameResult = JSON.parse(
      requestPrimaryNameResult.Messages[0].Data,
    );
    const expectedNewPrimaryName = {
      name: 'test-name',
      owner: processId,
      startTimestamp: approvalTimestamp,
    };
    assert.deepStrictEqual(approvedPrimaryNameResult, {
      baseNameOwner: processId,
      fundingPlan: {
        address: processId,
        balance: 1000000,
        shortfall: 0,
        stakes: [],
      },
      fundingResult: {
        newWithdrawVaults: [],
        totalFunded: 1000000,
      },
      newPrimaryName: expectedNewPrimaryName,
      request: {
        endTimestamp: 1839367899,
        name: 'test-name',
        startTimestamp: approvalTimestamp,
      },
      demandFactor,
    });

    // now fetch the primary name using the owner address
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: processId,
        memory: requestPrimaryNameResult.Memory,
        timestamp: approvalTimestamp,
      });

    const primaryNameLookupResult = JSON.parse(
      primaryNameForAddressResult.Messages[0].Data,
    );
    assert.deepStrictEqual(primaryNameLookupResult, {
      ...expectedNewPrimaryName,
      processId,
    });

    // reverse lookup the owner of the primary name
    const { result: ownerOfPrimaryNameResult, memory } =
      await getOwnerOfPrimaryName({
        name: 'test-name',
        memory: requestPrimaryNameResult.Memory,
        timestamp: approvalTimestamp,
      });

    const ownerResult = JSON.parse(ownerOfPrimaryNameResult.Messages[0].Data);
    assert.deepStrictEqual(ownerResult, {
      ...expectedNewPrimaryName,
      processId,
    });
    endingMemory = memory;
  });

  it('should allow removing a primary named by the owner or the owner of the base record', async function () {
    const processId = ''.padEnd(43, 'a');
    const recipient = ''.padEnd(43, 'b');
    const requestTimestamp = 1234567890;
    const { result: buyRecordResult } = await buyRecord({
      name: 'test-name',
      processId,
      timestamp: requestTimestamp,
      memory: sharedMemory,
      type: 'permabuy',
    });
    // create a primary name claim
    const { result: requestPrimaryNameResult } = await requestPrimaryName({
      name: 'test-name',
      caller: recipient,
      timestamp: requestTimestamp,
      memory: buyRecordResult.Memory,
    });
    // claim the primary name
    const { result: approvePrimaryNameRequestResult } =
      await approvePrimaryNameRequest({
        name: 'test-name',
        caller: processId,
        recipient: recipient,
        timestamp: requestTimestamp,
        memory: requestPrimaryNameResult.Memory,
      });

    // remove the primary name by the owner
    const { result: removePrimaryNameResult } = await removePrimaryNames({
      names: ['test-name'],
      caller: processId,
      memory: approvePrimaryNameRequestResult.Memory,
      timestamp: requestTimestamp,
      notifyOwners: true, // notify the owner of the primary name
    });

    // assert no error
    assertNoResultError(removePrimaryNameResult);
    // assert messages sent - one to the owner, one to the recipient, and one patch message
    assert.equal(removePrimaryNameResult.Messages.length, 3);
    assert.equal(removePrimaryNameResult.Messages[0].Target, processId);
    assert.equal(removePrimaryNameResult.Messages[1].Target, recipient);
    const removedPrimaryNameData = JSON.parse(
      removePrimaryNameResult.Messages[0].Data,
    );
    assert.deepStrictEqual(removedPrimaryNameData, [
      {
        owner: recipient,
        name: 'test-name',
      },
    ]);
    // assert 2 messages sent - one to the owner and one to the recipient
    const removedPrimaryNameDataForRecipient = JSON.parse(
      removePrimaryNameResult.Messages[1].Data,
    );
    assert.deepStrictEqual(removedPrimaryNameDataForRecipient, {
      owner: recipient,
      name: 'test-name',
    });
    const removePrimaryNameEvents = parseEventsFromResult(
      removePrimaryNameResult,
    );
    assert.equal(removePrimaryNameEvents.length, 1);
    assert.deepStrictEqual(removePrimaryNameEvents[0], {
      _e: 1,
      Action: 'Remove-Primary-Names',
      Cast: false,
      Cron: false,
      'Epoch-Index': -5864,
      From: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'From-Formatted': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
      Names: 'test-name',
      'Num-Removed-Primary-Names': 1,
      'Removed-Primary-Names': ['test-name'],
      'Removed-Primary-Name-Owners': [recipient],
      Timestamp: requestTimestamp,
      'Total-Primary-Name-Requests': 0,
      'Total-Primary-Names': 0,
      'Notify-Owners': 'true',
      'Memory-KiB-Used': removePrimaryNameEvents[0]['Memory-KiB-Used'],
      'Handler-Memory-KiB-Used':
        removePrimaryNameEvents[0]['Handler-Memory-KiB-Used'],
      'Final-Memory-KiB-Used':
        removePrimaryNameEvents[0]['Final-Memory-KiB-Used'],
    });
    // assert the primary name is no longer set
    const { result: primaryNameForAddressResult, memory } =
      await getPrimaryNameForAddress({
        address: recipient,
        memory: removePrimaryNameResult.Memory,
        timestamp: requestTimestamp,
        shouldAssertNoResultError: false, // we expect an error here, don't throw
      });

    const errorTag = primaryNameForAddressResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Error',
    ).value;
    assert.ok(errorTag, 'Expected an error tag');
    endingMemory = memory;
  });

  describe('getPaginatedPrimaryNames', function () {
    it('should return all primary names', async function () {
      const getPaginatedPrimaryNamesResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Primary-Names' },
            { name: 'Limit', value: 10 },
            { name: 'Sort-By', value: 'owner' },
            { name: 'Sort-Order', value: 'asc' },
          ],
        },
      });
      assertNoResultError(getPaginatedPrimaryNamesResult);
      const primaryNames = JSON.parse(
        getPaginatedPrimaryNamesResult.Messages[0].Data,
      );
      assert.deepStrictEqual(primaryNames, {
        items: [],
        totalItems: 0,
        limit: 10,
        hasMore: false,
        sortBy: 'owner',
        sortOrder: 'asc',
      });
      endingMemory = getPaginatedPrimaryNamesResult.Memory;
    });
  });

  describe('getPaginatedPrimaryNameRequests', function () {
    it('should return all primary name requests', async function () {
      const getPaginatedPrimaryNameRequestsResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Primary-Name-Requests' },
            { name: 'Limit', value: 10 },
            { name: 'Sort-By', value: 'startTimestamp' },
            { name: 'Sort-Order', value: 'asc' },
          ],
        },
      });

      const primaryNameRequests = JSON.parse(
        getPaginatedPrimaryNameRequestsResult.Messages[0].Data,
      );
      assert.deepStrictEqual(primaryNameRequests, {
        items: [],
        totalItems: 0,
        limit: 10,
        hasMore: false,
        sortBy: 'startTimestamp',
        sortOrder: 'asc',
      });
      endingMemory = getPaginatedPrimaryNameRequestsResult.Memory;
    });
  });

  describe('hyperbeam patch', function () {
    it('should send patch message on primary name request', async function () {
      const processId = ''.padEnd(43, 'a');
      const recipient = ''.padEnd(43, 'b');
      const requestTimestamp = 1234567890;

      // First buy a record
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        timestamp: requestTimestamp,
        memory: sharedMemory,
        type: 'permabuy',
      });

      // Request primary name - this should trigger a patch message
      const { result: requestPrimaryNameResult } = await requestPrimaryName({
        name: 'test-name',
        caller: recipient,
        timestamp: requestTimestamp,
        memory: buyRecordResult.Memory,
      });

      assertNoResultError(requestPrimaryNameResult);

      // Find the primary-names patch message (sent as individual message now)
      const patchMessage = requestPrimaryNameResult.Messages.find((msg) =>
        msg.Tags.some(
          (tag) =>
            tag.name === 'device' &&
            tag.value === 'patch@1.0' &&
            msg.Tags.some((t) => t.name === 'primary-names'),
        ),
      );
      assert.ok(patchMessage, 'Expected to find primary-names patch message');

      // Verify the patch message has primary-names field with the request
      const patchData = patchMessage.Tags.find(
        (tag) => tag.name === 'primary-names',
      )?.value;

      assert.ok(patchData, 'Expected primary-names tag in patch');
      assert.ok(
        patchData.requests,
        'Expected requests field in primary-names patch',
      );
      assert.ok(
        patchData.requests[recipient],
        'Expected request for recipient in patch',
      );
      assert.equal(
        patchData.requests[recipient].name,
        'test-name',
        'Expected correct name in patch request',
      );

      endingMemory = requestPrimaryNameResult.Memory;
    });

    it('should send patch message on primary name approval', async function () {
      const processId = ''.padEnd(43, 'a');
      const recipient = ''.padEnd(43, 'b');
      const requestTimestamp = 1234567890;

      // Buy record and create request
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        timestamp: requestTimestamp,
        memory: sharedMemory,
        type: 'permabuy',
      });

      const { result: requestPrimaryNameResult } = await requestPrimaryName({
        name: 'test-name',
        caller: recipient,
        timestamp: requestTimestamp,
        memory: buyRecordResult.Memory,
      });

      const approvalTimestamp = 1234567899;

      // Approve primary name - this should trigger a patch message
      const { result: approvePrimaryNameRequestResult } =
        await approvePrimaryNameRequest({
          name: 'test-name',
          caller: processId,
          recipient: recipient,
          timestamp: approvalTimestamp,
          memory: requestPrimaryNameResult.Memory,
        });

      assertNoResultError(approvePrimaryNameRequestResult);

      // Find the primary-names patch message (sent as individual message now)
      const patchMessage = approvePrimaryNameRequestResult.Messages.find(
        (msg) =>
          msg.Tags.some(
            (tag) =>
              tag.name === 'device' &&
              tag.value === 'patch@1.0' &&
              msg.Tags.some((t) => t.name === 'primary-names'),
          ),
      );
      assert.ok(patchMessage, 'Expected to find primary-names patch message');

      // Verify the patch message contains the updated primary name data
      const patchData = patchMessage.Tags.find(
        (tag) => tag.name === 'primary-names',
      )?.value;

      assert.ok(patchData, 'Expected primary-names tag in patch');

      // Should have the new owner entry
      assert.ok(
        patchData.owners,
        'Expected owners field in primary-names patch',
      );
      assert.ok(
        patchData.owners[recipient],
        'Expected owner entry for recipient in patch',
      );
      assert.equal(
        patchData.owners[recipient].name,
        'test-name',
        'Expected correct name in patch owner',
      );

      // Should have the new name entry
      assert.ok(patchData.names, 'Expected names field in primary-names patch');
      assert.equal(
        patchData.names['test-name'],
        recipient,
        'Expected correct owner for name in patch',
      );

      // Should remove the request (set to nil/null)
      assert.ok(
        patchData.requests,
        'Expected requests field in primary-names patch',
      );
      // In Lua, nil becomes null in JSON, or the key exists with null value
      // or the key exists because it changed from something to nil
      const requestExists = recipient in patchData.requests;
      if (requestExists) {
        assert.equal(
          patchData.requests[recipient],
          null,
          'Expected request to be removed (null) in patch',
        );
      }

      endingMemory = approvePrimaryNameRequestResult.Memory;
    });

    it('should send patch message on primary name removal', async function () {
      const processId = ''.padEnd(43, 'a');
      const recipient = ''.padEnd(43, 'b');
      const requestTimestamp = 1234567890;

      // Buy record, create request, and approve
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        timestamp: requestTimestamp,
        memory: sharedMemory,
        type: 'permabuy',
      });

      const { result: requestPrimaryNameResult } = await requestPrimaryName({
        name: 'test-name',
        caller: recipient,
        timestamp: requestTimestamp,
        memory: buyRecordResult.Memory,
      });

      const { result: approvePrimaryNameRequestResult } =
        await approvePrimaryNameRequest({
          name: 'test-name',
          caller: processId,
          recipient: recipient,
          timestamp: requestTimestamp,
          memory: requestPrimaryNameResult.Memory,
        });

      // Remove primary name - this should trigger a patch message
      const { result: removePrimaryNameResult } = await removePrimaryNames({
        names: ['test-name'],
        caller: processId,
        memory: approvePrimaryNameRequestResult.Memory,
        timestamp: requestTimestamp,
        notifyOwners: true,
      });

      assertNoResultError(removePrimaryNameResult);

      // Find the patch message - it should be the last message
      const patchMessage = removePrimaryNameResult.Messages.at(-1);

      // Verify it has device tag
      const deviceTag = patchMessage.Tags.find((tag) => tag.name === 'device');
      assert.ok(deviceTag, 'Expected to find device tag');
      assert.equal(
        deviceTag.value,
        'patch@1.0',
        'Expected device tag to be patch@1.0',
      );

      // Verify the patch message contains the removed primary name data
      const patchData = patchMessage.Tags.find(
        (tag) => tag.name === 'primary-names',
      )?.value;

      assert.ok(patchData, 'Expected primary-names tag in patch');

      // Should remove the owner entry (set to nil/null)
      assert.ok(
        patchData.owners,
        'Expected owners field in primary-names patch',
      );
      const ownerExists = recipient in patchData.owners;
      if (ownerExists) {
        assert.equal(
          patchData.owners[recipient],
          null,
          'Expected owner to be removed (null) in patch',
        );
      }

      // Should remove the name entry (set to nil/null)
      assert.ok(patchData.names, 'Expected names field in primary-names patch');
      const nameExists = 'test-name' in patchData.names;
      if (nameExists) {
        assert.equal(
          patchData.names['test-name'],
          null,
          'Expected name to be removed (null) in patch',
        );
      }

      endingMemory = removePrimaryNameResult.Memory;
    });

    it('should send patch message when owner immediately approves their own request', async function () {
      const processId = ''.padEnd(43, 'a');
      const requestTimestamp = 1234567890;

      // Buy record
      const { result: buyRecordResult } = await buyRecord({
        name: 'test-name',
        processId,
        timestamp: requestTimestamp,
        memory: sharedMemory,
        type: 'permabuy',
      });

      // Request as the owner - should immediately approve
      const { result: requestPrimaryNameResult } = await requestPrimaryName({
        name: 'test-name',
        caller: processId,
        timestamp: requestTimestamp,
        memory: buyRecordResult.Memory,
      });

      assertNoResultError(requestPrimaryNameResult);

      // Find the primary-names patch message (sent as individual message now)
      const patchMessage = requestPrimaryNameResult.Messages.find((msg) =>
        msg.Tags.some(
          (tag) =>
            tag.name === 'device' &&
            tag.value === 'patch@1.0' &&
            msg.Tags.some((t) => t.name === 'primary-names'),
        ),
      );
      assert.ok(patchMessage, 'Expected to find primary-names patch message');

      // Verify the patch message contains the immediate primary name assignment
      const patchData = patchMessage.Tags.find(
        (tag) => tag.name === 'primary-names',
      )?.value;

      assert.ok(patchData, 'Expected primary-names tag in patch');

      // Should have the new owner entry
      assert.ok(
        patchData.owners,
        'Expected owners field in primary-names patch',
      );
      assert.ok(
        patchData.owners[processId],
        'Expected owner entry for processId in patch',
      );

      // Should have the new name entry
      assert.ok(patchData.names, 'Expected names field in primary-names patch');
      assert.equal(
        patchData.names['test-name'],
        processId,
        'Expected correct owner for name in patch',
      );

      // Should NOT have a pending request since it was immediately approved
      // The requests field should be empty or not contain this processId
      if (patchData.requests) {
        assert.ok(
          !(processId in patchData.requests) ||
            patchData.requests[processId] === null,
          'Expected no pending request for processId in patch',
        );
      }

      endingMemory = requestPrimaryNameResult.Memory;
    });
  });

  describe('Primary-Names-Filters', () => {
    it('should filter primary names by owner', async () => {
      const owner1 = ''.padEnd(43, 'x');
      const owner2 = ''.padEnd(43, 'y');

      // Buy two records (use the same processId for ANT)
      const { memory: buyMemory1 } = await buyRecord({
        memory: sharedMemory,
        name: 'filter-name-one',
        timestamp: STUB_TIMESTAMP,
        type: 'lease',
        years: 1,
        processId: STUB_PROCESS_ID,
      });

      const { memory: buyMemory2 } = await buyRecord({
        memory: buyMemory1,
        name: 'filter-name-two',
        timestamp: STUB_TIMESTAMP,
        type: 'lease',
        years: 1,
        processId: STUB_PROCESS_ID,
      });

      // Request and approve primary names for both owners
      const { memory: requestMemory1 } = await requestPrimaryName({
        name: 'filter-name-one',
        caller: owner1,
        timestamp: STUB_TIMESTAMP,
        memory: buyMemory2,
      });

      // Approve from the ANT process (STUB_PROCESS_ID)
      const { memory: approveMemory1 } = await approvePrimaryNameRequest({
        name: 'filter-name-one',
        caller: STUB_PROCESS_ID,
        recipient: owner1,
        timestamp: STUB_TIMESTAMP,
        memory: requestMemory1,
      });

      const { memory: requestMemory2 } = await requestPrimaryName({
        name: 'filter-name-two',
        caller: owner2,
        timestamp: STUB_TIMESTAMP,
        memory: approveMemory1,
      });

      const { memory: approveMemory2 } = await approvePrimaryNameRequest({
        name: 'filter-name-two',
        caller: STUB_PROCESS_ID,
        recipient: owner2,
        timestamp: STUB_TIMESTAMP,
        memory: requestMemory2,
      });

      // Get all primary names without filter
      const allNamesResult = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Primary-Names' }],
        },
        memory: approveMemory2,
        timestamp: STUB_TIMESTAMP,
      });
      const allNames = JSON.parse(allNamesResult.Messages[0].Data);
      assert.strictEqual(allNames.items.length, 2);

      // Filter by owner1
      const filteredResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Primary-Names' },
            { name: 'Filters', value: JSON.stringify({ owner: owner1 }) },
          ],
        },
        memory: approveMemory2,
        timestamp: STUB_TIMESTAMP,
      });
      const filteredNames = JSON.parse(filteredResult.Messages[0].Data);
      assert.strictEqual(filteredNames.items.length, 1);
      assert.strictEqual(filteredNames.items[0].owner, owner1);
      assert.strictEqual(filteredNames.items[0].name, 'filter-name-one');

      endingMemory = approveMemory2;
    });

    it('should filter primary names by name', async () => {
      const owner1 = ''.padEnd(43, 'u');
      const owner2 = ''.padEnd(43, 'v');

      // Buy two records
      const { memory: buyMemory1 } = await buyRecord({
        memory: sharedMemory,
        name: 'filter-test-alpha',
        timestamp: STUB_TIMESTAMP,
        type: 'lease',
        years: 1,
        processId: STUB_PROCESS_ID,
      });

      const { memory: buyMemory2 } = await buyRecord({
        memory: buyMemory1,
        name: 'filter-test-beta',
        timestamp: STUB_TIMESTAMP,
        type: 'lease',
        years: 1,
        processId: STUB_PROCESS_ID,
      });

      // Request and approve primary names
      const { memory: requestMemory1 } = await requestPrimaryName({
        name: 'filter-test-alpha',
        caller: owner1,
        timestamp: STUB_TIMESTAMP,
        memory: buyMemory2,
      });

      const { memory: approveMemory1 } = await approvePrimaryNameRequest({
        name: 'filter-test-alpha',
        caller: STUB_PROCESS_ID,
        recipient: owner1,
        timestamp: STUB_TIMESTAMP,
        memory: requestMemory1,
      });

      const { memory: requestMemory2 } = await requestPrimaryName({
        name: 'filter-test-beta',
        caller: owner2,
        timestamp: STUB_TIMESTAMP,
        memory: approveMemory1,
      });

      const { memory: approveMemory2 } = await approvePrimaryNameRequest({
        name: 'filter-test-beta',
        caller: STUB_PROCESS_ID,
        recipient: owner2,
        timestamp: STUB_TIMESTAMP,
        memory: requestMemory2,
      });

      // Filter by specific name
      const filteredResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Primary-Names' },
            {
              name: 'Filters',
              value: JSON.stringify({ name: 'filter-test-alpha' }),
            },
          ],
        },
        memory: approveMemory2,
        timestamp: STUB_TIMESTAMP,
      });
      const filteredNames = JSON.parse(filteredResult.Messages[0].Data);
      assert.strictEqual(filteredNames.items.length, 1);
      assert.strictEqual(filteredNames.items[0].name, 'filter-test-alpha');

      endingMemory = approveMemory2;
    });
  });
});
