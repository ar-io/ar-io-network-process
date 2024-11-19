import {
  assertNoResultError,
  handle,
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
    const buyRecordResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: name },
          { name: 'Purchase-Type', value: type },
          { name: 'Years', value: years },
          { name: 'Process-Id', value: processId },
        ],
      },
      memory,
    );
    assertNoResultError(buyRecordResult);
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
    const requestPrimaryNameResult = await handle(
      {
        From: caller,
        Owner: caller,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Primary-Name-Request' },
          { name: 'Name', value: name },
          ...(fundFrom ? [{ name: 'Fund-From', value: fundFrom }] : []),
        ],
      },
      memory,
    );
    assertNoResultError(requestPrimaryNameResult);
    return {
      result: requestPrimaryNameResult,
      memory: requestPrimaryNameResult.Memory,
    };
  };

  const approvePrimaryNameRequest = async ({
    name,
    caller,
    recipient,
    timestamp,
    memory,
  }) => {
    const approvePrimaryNameRequestResult = await handle(
      {
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
    );
    assertNoResultError(approvePrimaryNameRequestResult);
    return {
      result: approvePrimaryNameRequestResult,
      memory: approvePrimaryNameRequestResult.Memory,
    };
  };

  const removePrimaryNames = async ({ names, caller, memory }) => {
    const removePrimaryNamesResult = await handle(
      {
        From: caller,
        Owner: caller,
        Tags: [
          { name: 'Action', value: 'Remove-Primary-Names' },
          { name: 'Names', value: names.join(',') },
        ],
      },
      memory,
    );
    assertNoResultError(removePrimaryNamesResult);
    return {
      result: removePrimaryNamesResult,
      memory: removePrimaryNamesResult.Memory,
    };
  };

  const getPrimaryNameForAddress = async ({
    address,
    memory,
    assert = true,
  }) => {
    const getPrimaryNameResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Address', value: address },
        ],
      },
      memory,
    );
    if (assert) {
      assertNoResultError(getPrimaryNameResult);
    }
    return {
      result: getPrimaryNameResult,
      memory: getPrimaryNameResult.Memory,
    };
  };

  const getOwnerOfPrimaryName = async ({ name, memory }) => {
    const getOwnerResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Name', value: name },
        ],
      },
      memory,
    );
    assertNoResultError(getOwnerResult);
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
    assertNoResultError(requestPrimaryNameResult);

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
        balance: 100000000,
        shortfall: 0,
        stakes: [],
      },
      fundingResult: {
        newWithdrawVaults: [],
        totalFunded: 100000000,
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
    // assert the primary name is no longer set
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: recipient,
        memory: removePrimaryNameResult.Memory,
        assert: false, // we expect an error here, don't throw
      });

    const errorTag = primaryNameForAddressResult.Error;
    assert.ok(errorTag, 'Expected an error tag');
  });

  describe('getPaginatedPrimaryNames', function () {
    it('should return all primary names', async function () {
      const getPaginatedPrimaryNamesResult = await handle({
        Tags: [
          { name: 'Action', value: 'Primary-Names' },
          { name: 'Limit', value: 10 },
          { name: 'Sort-By', value: 'owner' },
          { name: 'Sort-Order', value: 'asc' },
        ],
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
        Tags: [
          { name: 'Action', value: 'Primary-Name-Requests' },
          { name: 'Limit', value: 10 },
          { name: 'Sort-By', value: 'startTimestamp' },
          { name: 'Sort-Order', value: 'asc' },
        ],
      });
      assertNoResultError(getPaginatedPrimaryNameRequestsResult);
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
