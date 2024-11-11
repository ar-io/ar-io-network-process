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

  const setPrimaryName = async ({
    name,
    owner,
    processId,
    timestamp,
    memory,
  }) => {
    const setPrimaryNameResult = await handle(
      {
        From: processId,
        Owner: processId,
        Timestamp: timestamp,
        Tags: [
          { name: 'Action', value: 'Set-Primary-Name' },
          { name: 'Name', value: name },
          { name: 'Owner', value: owner },
        ],
      },
      memory,
    );
    assertNoResultError(setPrimaryNameResult);
    return {
      result: setPrimaryNameResult,
      memory: setPrimaryNameResult.Memory,
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

  it('should allow setting of a primary name on a record owned by a specific ant', async function () {
    const { memory: buyRecordMemory } = await buyRecord({
      name: 'test-name',
      processId: ''.padEnd(43, 'a'),
    });

    // give balance to the owner
    const transferMemory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100000000, // the cost of a primary name
      memory: buyRecordMemory,
    });

    const { result: primaryNameResult } = await setPrimaryName({
      name: 'test-name',
      owner: STUB_ADDRESS,
      processId: ''.padEnd(43, 'a'),
      timestamp: 1234567890,
      memory: transferMemory,
    });

    // there should be two messages, one to the ant and one to the owner
    assert.equal(primaryNameResult.Messages.length, 2);
    assert.equal(primaryNameResult.Messages[0].Target, STUB_ADDRESS);
    assert.equal(primaryNameResult.Messages[1].Target, ''.padEnd(43, 'a'));

    // find the action tag in the messages
    const actionTag = primaryNameResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Action',
    ).value;
    assert.equal(actionTag, 'Set-Primary-Name-Notice');

    // the primary name should be set
    assert.equal(
      primaryNameResult.Messages[0].Data,
      JSON.stringify({
        name: 'test-name',
        startTimestamp: 1234567890,
      }),
    );

    // now fetch the primary name using the owner address
    const { result: primaryNameForAddressResult } =
      await getPrimaryNameForAddress({
        address: STUB_ADDRESS,
        memory: primaryNameResult.Memory,
      });

    const primaryNameLookupResult = JSON.parse(
      primaryNameForAddressResult.Messages[0].Data,
    );
    assert.deepStrictEqual(primaryNameLookupResult, {
      name: 'test-name',
      owner: STUB_ADDRESS,
      startTimestamp: 1234567890,
    });

    // reverse lookup the owner of the primary name
    const { result: ownerOfPrimaryNameResult } = await getOwnerOfPrimaryName({
      name: 'test-name',
      memory: primaryNameForAddressResult.Memory,
    });

    const ownerResult = JSON.parse(ownerOfPrimaryNameResult.Messages[0].Data);
    assert.deepStrictEqual(ownerResult, {
      name: 'test-name',
      owner: STUB_ADDRESS,
      startTimestamp: 1234567890,
    });
  });
});
