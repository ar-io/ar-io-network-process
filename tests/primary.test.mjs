import { assertNoResultError, handle, transfer } from './helpers.mjs';
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
    // assert no error
    assertNoResultError(buyRecordResult);
    return {
      record: JSON.parse(buyRecordResult.Messages[0].Data),
      memory: buyRecordResult.Memory,
    };
  };

  const createNameClaim = async ({
    name,
    owner,
    recipient,
    timestamp,
    memory,
  }) => {
    const createNameClaimResult = await handle(
      {
        From: owner,
        Owner: owner,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Create-Primary-Name-Claim' },
          { name: 'Name', value: name },
          { name: 'Recipient', value: recipient },
        ],
      },
      memory,
    );
    assertNoResultError(createNameClaimResult);
    return {
      result: createNameClaimResult,
      memory: createNameClaimResult.Memory,
    };
  };

  const claimPrimaryName = async ({ name, recipient, timestamp, memory }) => {
    const claimPrimaryNameResult = await handle(
      {
        From: recipient,
        Owner: recipient,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Claim-Primary-Name' },
          { name: 'Name', value: name },
        ],
      },
      memory,
    );
    assertNoResultError(claimPrimaryNameResult);
    return {
      result: claimPrimaryNameResult,
      memory: claimPrimaryNameResult.Memory,
    };
  };

  const revokeClaims = async ({ initiator, names, memory }) => {
    const revokeClaimsResult = await handle(
      {
        From: initiator,
        Owner: initiator,
        Tags: [
          { name: 'Action', value: 'Revoke-Claims' },
          { name: 'Names', value: names.join(',') },
        ],
      },
      memory,
    );
    assertNoResultError(revokeClaimsResult);
    return {
      result: revokeClaimsResult,
      memory: revokeClaimsResult.Memory,
    };
  };

  const getPrimaryNameForAddress = async ({ address, memory }) => {
    const getPrimaryNameResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Primary-Name' },
          { name: 'Address', value: address },
        ],
      },
      memory,
    );
    assertNoResultError(getPrimaryNameResult);
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

  it('should allow creating and claiming a primary name on a an arns record', async function () {
    const processId = ''.padEnd(43, 'a');
    const recipient = ''.padEnd(43, 'b');
    const { memory: buyRecordMemory } = await buyRecord({
      name: 'test-name',
      processId,
    });

    // give balance to the owner
    const transferMemory = await transfer({
      recipient,
      quantity: 100000000, // the cost of a primary name
      memory: buyRecordMemory,
    });

    const { result: createClaimResult } = await createNameClaim({
      name: 'test-name',
      owner: processId,
      recipient, // the process creates the claim, the recipient approves it
      timestamp: 1234567890,
      memory: transferMemory,
    });

    const { result: claimPrimaryNameResult } = await claimPrimaryName({
      name: 'test-name',
      recipient,
      timestamp: 1234567890,
      memory: createClaimResult.Memory,
    });

    assertNoResultError(claimPrimaryNameResult);

    // there should be two messages, one to the ant and one to the owner
    assert.equal(claimPrimaryNameResult.Messages.length, 2);
    assert.equal(claimPrimaryNameResult.Messages[0].Target, processId);
    assert.equal(claimPrimaryNameResult.Messages[1].Target, recipient);

    // find the action tag in the messages
    const actionTag = claimPrimaryNameResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Action',
    ).value;
    assert.equal(actionTag, 'Claim-Primary-Name-Notice');

    // the primary name should be set
    const primaryNameSetResult = JSON.parse(
      claimPrimaryNameResult.Messages[0].Data,
    );
    assert.deepStrictEqual(primaryNameSetResult, {
      claim: {
        baseName: 'test-name',
        endTimestamp: 3826567890,
        initiator: processId,
        name: 'test-name',
        recipient,
        startTimestamp: 1234567890,
      },
      primaryName: {
        name: 'test-name',
        owner: recipient,
        startTimestamp: 1234567890,
        baseName: 'test-name',
      },
    });

    // now fetch the primary name using the owner address
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: recipient,
        memory: claimPrimaryNameResult.Memory,
      });

    const primaryNameLookupResult = JSON.parse(
      primaryNameForAddressResult.Messages[0].Data,
    );
    assert.deepStrictEqual(primaryNameLookupResult, {
      name: 'test-name',
      owner: recipient,
      startTimestamp: 1234567890,
      baseName: 'test-name',
    });

    // reverse lookup the owner of the primary name
    const { result: ownerOfPrimaryNameResult } = await getOwnerOfPrimaryName({
      name: 'test-name',
      memory: claimPrimaryNameResult.Memory,
    });

    const ownerResult = JSON.parse(ownerOfPrimaryNameResult.Messages[0].Data);
    assert.deepStrictEqual(ownerResult, {
      name: 'test-name',
      owner: recipient,
      startTimestamp: 1234567890,
      baseName: 'test-name',
    });
  });

  it('should allow revoking claims for an initiator', async function () {
    const processId = ''.padEnd(43, 'a');
    const recipient = ''.padEnd(43, 'b');
    const { memory: buyRecordMemory } = await buyRecord({
      name: 'test-name',
      processId,
    });
    // create a primary name claim
    const { result: createClaimResult } = await createNameClaim({
      name: 'test-name',
      owner: processId,
      recipient,
      timestamp: 1234567890,
      memory: buyRecordMemory,
    });
    // revoke the claim
    const { result: revokeClaimsResult } = await revokeClaims({
      initiator: processId,
      names: ['test-name'],
      memory: createClaimResult.Memory,
    });

    // assert no error
    assertNoResultError(revokeClaimsResult);
    // assert 2 messages sent - one to the initiator and one to the recipient
    assert.equal(revokeClaimsResult.Messages.length, 2);
    assert.equal(revokeClaimsResult.Messages[0].Target, processId);
    assert.equal(revokeClaimsResult.Messages[1].Target, recipient);
    // assert the claim was revoked
    const revokedClaimsData = JSON.parse(revokeClaimsResult.Messages[0].Data);
    assert.deepStrictEqual(revokedClaimsData, [
      {
        baseName: 'test-name',
        endTimestamp: 3826567890,
        initiator: processId,
        name: 'test-name',
        recipient,
        startTimestamp: 1234567890,
      },
    ]);
    // assert the claim was sent to the recipient
    const recipientRevokedClaimsData = JSON.parse(
      revokeClaimsResult.Messages[1].Data,
    );
    assert.deepStrictEqual(recipientRevokedClaimsData, {
      baseName: 'test-name',
      endTimestamp: 3826567890,
      initiator: processId,
      name: 'test-name',
      recipient,
      startTimestamp: 1234567890,
    });
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
});
