import {
  assertNoResultError,
  handle,
  parseEventsFromResult,
  setUpStake,
  transfer,
} from './helpers.mjs';
import assert from 'assert';
import { describe, it } from 'node:test';
import { STUB_ADDRESS } from '../tools/constants.mjs';

describe('primary names', function () {
  const buyRecord = async ({
    name,
    processId,
    type = 'permabuy',
    years = 1,
    memory,
  }) => {
    const buyRecordResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: name },
          { name: 'Purchase-Type', value: type },
          { name: 'Years', value: years },
          { name: 'Process-Id', value: processId },
        ],
      },
      memory,
    });
    return {
      record: JSON.parse(buyRecordResult.Messages[0].Data),
      memory: buyRecordResult.Memory,
    };
  };

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

  const getPrimaryNameRequest = async ({ initiator, memory }) => {
    const getPrimaryNameRequestResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Primary-Name-Request' },
          { name: 'Initiator', value: initiator },
        ],
      },
      memory,
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

  const removePrimaryNames = async ({ names, caller, memory }) => {
    const removePrimaryNamesResult = await handle({
      options: {
        From: caller,
        Owner: caller,
        Tags: [
          { name: 'Action', value: 'Remove-Primary-Names' },
          { name: 'Names', value: names.join(',') },
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
    shouldAssertNoResultError = true,
  }) => {
    const getPrimaryNameResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Address', value: address },
        ],
      },
      memory,
      shouldAssertNoResultError,
    });
    return {
      result: getPrimaryNameResult,
      memory: getPrimaryNameResult.Memory,
    };
  };

  const getOwnerOfPrimaryName = async ({ name, memory }) => {
    const getOwnerResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Name', value: name },
        ],
      },
      memory,
    });
    return {
      result: getOwnerResult,
      memory: getOwnerResult.Memory,
    };
  };

  it('should allow creating and approving a primary name for an existing base name when the recipient is not the base name owner and is funding from stakes', async function () {
    const processId = ''.padEnd(43, 'a');
    const recipient = ''.padEnd(43, 'b');
    const { memory: buyRecordMemory } = await buyRecord({
      name: 'test-name',
      processId,
    });

    const stakeResult = await setUpStake({
      memory: buyRecordMemory,
      stakerAddress: recipient,
      transferQty: 550000000,
      stakeQty: 500000000,
    });

    const { result: requestPrimaryNameResult } = await requestPrimaryName({
      name: 'test-name',
      caller: recipient,
      timestamp: 1234567890,
      memory: stakeResult.memory,
      fundFrom: 'stakes',
    });

    const parsedEvents = parseEventsFromResult(requestPrimaryNameResult);
    assert.equal(parsedEvents.length, 1);
    assert.deepStrictEqual(parsedEvents[0], {
      _e: 1,
      Action: 'Request-Primary-Name',
      'Base-Name-Owner': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      Cast: false,
      Cron: false,
      'Request-End-Timestamp': 1839367890,
      'Epoch-Index': -5618,
      'FP-Balance': 0,
      'FP-Stakes-Amount': 50000000,
      From: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'From-Formatted': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'Fund-From': 'stakes',
      'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
      Name: 'test-name',
      'Request-Start-Timestamp': 1234567890,
      Timestamp: 1234567890,
      'Total-Primary-Name-Requests': 1,
      'Total-Primary-Names': 0,
    });

    const { result: getPrimaryNameRequestResult } = await getPrimaryNameRequest(
      {
        initiator: recipient,
        memory: requestPrimaryNameResult.Memory,
      },
    );

    const requestData = JSON.parse(
      getPrimaryNameRequestResult.Messages[0].Data,
    );
    assert.deepStrictEqual(requestData, {
      name: 'test-name',
      startTimestamp: 1234567890,
      endTimestamp: 1839367890,
      initiator: recipient,
    });

    const approvedTimestamp = 1234567899;
    const { result: approvePrimaryNameRequestResult } =
      await approvePrimaryNameRequest({
        name: 'test-name',
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
      'Epoch-Index': -5618,
      From: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'From-Formatted': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
      Name: 'test-name',
      Owner: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      Recipient: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'Request-End-Timestamp': 1839367890,
      'Request-Start-Timestamp': 1234567890,
      'Start-Timestamp': 1234567899,
      Timestamp: 1234567899,
      'Total-Primary-Names': 1,
      'Total-Primary-Name-Requests': 0,
    });

    // there should be two messages, one to the ant and one to the owner
    assert.equal(approvePrimaryNameRequestResult.Messages.length, 2);
    assert.equal(approvePrimaryNameRequestResult.Messages[0].Target, processId);
    assert.equal(approvePrimaryNameRequestResult.Messages[1].Target, recipient);

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
      name: 'test-name',
      owner: recipient,
      startTimestamp: approvedTimestamp,
    };
    assert.deepStrictEqual(approvedPrimaryNameResult, {
      newPrimaryName: expectedNewPrimaryName,
      request: {
        endTimestamp: 1839367890,
        name: 'test-name',
        startTimestamp: 1234567890,
      },
    });
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: recipient,
        memory: approvePrimaryNameRequestResult.Memory,
      });

    const primaryNameLookupResult = JSON.parse(
      primaryNameForAddressResult.Messages[0].Data,
    );
    assert.deepStrictEqual(primaryNameLookupResult, expectedNewPrimaryName);

    // reverse lookup the owner of the primary name
    const { result: ownerOfPrimaryNameResult } = await getOwnerOfPrimaryName({
      name: 'test-name',
      memory: approvePrimaryNameRequestResult.Memory,
    });

    const ownerResult = JSON.parse(ownerOfPrimaryNameResult.Messages[0].Data);
    assert.deepStrictEqual(ownerResult, expectedNewPrimaryName);
  });

  it('should immediately approve a primary name for an existing base name when the caller of the request is the base name owner', async function () {
    const processId = ''.padEnd(43, 'a');
    const { memory: buyRecordMemory } = await buyRecord({
      name: 'test-name',
      processId,
    });

    const approvalTimestamp = 1234567899;
    const { result: requestPrimaryNameResult } = await requestPrimaryName({
      name: 'test-name',
      caller: processId,
      timestamp: approvalTimestamp,
      memory: buyRecordMemory,
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
      'Epoch-Index': -5618,
      'FP-Balance': 50000000,
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
    });

    // there should be only one message with the Approve-Primary-Name-Request-Notice action
    assert.equal(requestPrimaryNameResult.Messages.length, 1);
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
        balance: 50000000,
        shortfall: 0,
        stakes: [],
      },
      fundingResult: {
        newWithdrawVaults: [],
        totalFunded: 50000000,
      },
      newPrimaryName: expectedNewPrimaryName,
      request: {
        endTimestamp: 1839367899,
        name: 'test-name',
        startTimestamp: approvalTimestamp,
      },
    });

    // now fetch the primary name using the owner address
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: processId,
        memory: requestPrimaryNameResult.Memory,
      });

    const primaryNameLookupResult = JSON.parse(
      primaryNameForAddressResult.Messages[0].Data,
    );
    assert.deepStrictEqual(primaryNameLookupResult, expectedNewPrimaryName);

    // reverse lookup the owner of the primary name
    const { result: ownerOfPrimaryNameResult } = await getOwnerOfPrimaryName({
      name: 'test-name',
      memory: requestPrimaryNameResult.Memory,
    });

    const ownerResult = JSON.parse(ownerOfPrimaryNameResult.Messages[0].Data);
    assert.deepStrictEqual(ownerResult, expectedNewPrimaryName);
  });

  it('should allow removing a primary named by the owner or the owner of the base record', async function () {
    const processId = ''.padEnd(43, 'a');
    const recipient = ''.padEnd(43, 'b');
    const { memory: buyRecordMemory } = await buyRecord({
      name: 'test-name',
      processId,
    });
    // create a primary name claim
    const { result: requestPrimaryNameResult } = await requestPrimaryName({
      name: 'test-name',
      caller: recipient,
      timestamp: 1234567890,
      memory: buyRecordMemory,
    });
    // claim the primary name
    const { result: approvePrimaryNameRequestResult } =
      await approvePrimaryNameRequest({
        name: 'test-name',
        caller: processId,
        recipient: recipient,
        timestamp: 1234567890,
        memory: requestPrimaryNameResult.Memory,
      });

    // remove the primary name by the owner
    const { result: removePrimaryNameResult } = await removePrimaryNames({
      names: ['test-name'],
      caller: processId,
      memory: approvePrimaryNameRequestResult.Memory,
    });

    // assert no error
    assertNoResultError(removePrimaryNameResult);
    // assert 2 messages sent - one to the owner and one to the recipient
    assert.equal(removePrimaryNameResult.Messages.length, 2);
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
      'Epoch-Index': -19657,
      From: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'From-Formatted': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'Message-Id': 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
      Names: 'test-name',
      'Num-Removed-Primary-Names': 1,
      'Removed-Primary-Names': ['test-name'],
      'Removed-Primary-Name-Owners': [recipient],
      Timestamp: 21600000,
      'Total-Primary-Name-Requests': 0,
      'Total-Primary-Names': 0,
    });
    // assert the primary name is no longer set
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: recipient,
        memory: removePrimaryNameResult.Memory,
        shouldAssertNoResultError: false, // we expect an error here, don't throw
      });

    const errorTag = primaryNameForAddressResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Error',
    ).value;
    assert.ok(errorTag, 'Expected an error tag');
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
    });
  });
});
